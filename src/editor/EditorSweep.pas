unit EditorSweep;

{ Every template, checked - and run, where it says how.

  One "Prüfen" answers for the template in front of the maintainer. This
  answers for the whole file, which is the question that matters before a
  commit: after an edit to a shared record type, a renamed column, a new
  rights mask, WHICH of the twenty-nine keys stopped working?

  Two halves, and the difference is deliberate. The checks need no database
  and run on every template: the declaration parses, the statement and the
  parameters agree, the record type resolves, the rules read. Running needs
  the TestBounds column, and a template that has none is skipped and says so -
  never silently counted as passed.

  A run here is always rolled back. The Rollback box of the editor is about
  the one statement the maintainer is looking at; a sweep over the whole set
  writing rows into a database is not what anybody presses this for.

  The same sweep can go through the SERVER instead, which answers what the
  direct one cannot: the rights mask against the account that is logged in,
  the caller's own identity bound by CallerScope, the rules. There the
  rollback promise does not exist - the server commits - so a write is left
  out unless the caller says otherwise, and says so in its own line. }

{$I mormot.defines.inc}
{ The source of this unit is UTF-8, and its literals carry umlauts. Without
  this the compiler reads them as the system codepage and re-encodes them on
  the way into a RawUtf8 parameter, which turns "Ü" into "Ã" on screen. }
{$codepage UTF8}

interface

uses
  SysUtils,
  Variants,
  mormot.core.base,
  mormot.core.text,
  mormot.core.rtti,
  mormot.core.variants,
  SqlStatus,
  SqlParamTypes,
  SqlParamRules,
  SqlTemplateTypes,
  SqlRecordBind,
  AppSqlClient, // the sweep through the server speaks as a client does
  EditorDb,
  EditorExec;

type
  /// what became of one template
  TSweepOutcome = (
    /// checked, and run, and the run was answered as it should be
    swOk,
    /// checked and sound, but not run - see the message
    swSkipped,
    /// something is wrong with it
    swBad);

  /// which way a run goes
  TSweepMode = (
    /// straight onto the editor's own database connection, in a transaction
    // that is rolled back - what "Prüfen" has always done
    smDirect,
    /// through the server, as a client would: mask, caller scope and rules
    // all apply, and nothing is rolled back
    smServer);

  /// one line of the report
  TSweepRow = record
    ActionKey: RawUtf8;
    Outcome: TSweepOutcome;
    /// whether the statement actually reached the database
    Ran: boolean;
    /// what it answered, meaningful only when Ran
    Status: TSqlStatus;
    /// what to put in the log next to the key
    Message: RawUtf8;
  end;
  TSweepRows = array of TSweepRow;

const
  SWEEP_MARK: array[TSweepOutcome] of RawUtf8 = (
    'ok  ', 'offen', 'FEHLER');

/// everything about one template that needs no database
// - true when nothing is wrong; Msg carries the findings either way
function CheckTemplate(const Rec: TSqlRec; out Msg: RawUtf8): boolean;

/// check every template, and run the ones that carry TestBounds
// - Execute false checks only, which is what an unconnected editor can do
// - smServer expects an open client connection (ConnectClient), and Db is
// not used at all: the statement runs where the server runs it
// - AllowWrites has a meaning only in smServer, where a write is a real
// write: false leaves them out and says so per line
function SweepTemplates(Db: TEditorDb; const Recs: TSqlRecArray;
  Execute: boolean; Mode: TSweepMode = smDirect;
  AllowWrites: boolean = false): TSweepRows;

/// does this set hold a write that a server sweep would actually execute
// - so the editor can ask once, before it starts, instead of per template
function HasServerWrites(const Recs: TSqlRecArray): boolean;

/// how many of each, in one line
function SweepSummary(const Rows: TSweepRows): RawUtf8;

implementation

{ ---------- the half that needs no database ---------- }

function CheckTemplate(const Rec: TSqlRec; out Msg: RawUtf8): boolean;
var
  kinds: TSqlParamKinds;
  rules: TSqlParamRules;
  rc: TRttiCustom;
  kind: TRecordActionKind;
  sql, why: RawUtf8;
  want: integer;
begin
  Msg := '';
  result := false;
  if Rec.ActionKey = '' then
  begin
    Msg := 'Kein Action-Key.';
    exit;
  end;
  kind := RecordKindFromActionKey(Rec.ActionKey);
  { what the template says its parameters are }
  if not ParseParamTypes(Rec.ParamTypes, kinds, Msg) then
    exit;
  want := ExpectedParamCount(Rec);
  if (Rec.ParamTypes <> '') and
     (length(kinds) <> want) then
  begin
    Msg := FormatUtf8('% Typ(en) deklariert, % Parameter erwartet.',
      [length(kinds), want]);
    exit;
  end;
  { the rules, and the one place they cannot be applied }
  if not ParseParamRules(Rec.Rules, rules, Msg) then
    exit;
  if (Rec.Rules <> '') and
     (Rec.RecordType <> '') and
     (kind in [raInsert, raUpdate]) then
  begin
    Msg := 'Regeln nennen Parameterpositionen, ein Record-Schreibvorgang ' +
           'hat keine.';
    exit;
  end;
  { the statement, when there is one }
  if Rec.Sql <> '' then
    if not StaticCheck(Rec.Sql, want, Msg) then
      exit;
  { and the record side, through the server's own code }
  if Rec.RecordType <> '' then
  begin
    if ResolveRecordType(Rec, rc, why) <> rbOk then
    begin
      Msg := 'Record-Typ: ' + why;
      exit;
    end;
    if Rec.Sql = '' then
      if GeneratedSqlFor(Rec, sql, why) <> rbOk then
      begin
        Msg := 'Erzeugtes SQL: ' + why;
        exit;
      end;
  end
  else if Rec.Sql = '' then
  begin
    Msg := 'Weder Statement noch Record-Typ.';
    exit;
  end;
  result := true;
  if Msg = '' then
    Msg := FormatUtf8('% Parameter.', [want]);
end;

{ ---------- the half that runs ---------- }

{ The values of the TestBounds column, brought to where a run wants them.

  An array is what a client sends and goes to the statement; an object is one
  record's JSON and goes to the record path. Anything else is a column that
  was filled in by hand and got it wrong, which is worth saying. }
function ReadTestBounds(const Rec: TSqlRec; out Values: variant;
  out IsRecord: boolean; out Msg: RawUtf8): boolean;
var
  doc: PDocVariantData;
begin
  Msg := '';
  IsRecord := false;
  Values := _Json(Rec.TestBounds, JSON_FAST_FLOAT);
  doc := _Safe(Values);
  if doc^.IsObject then
  begin
    IsRecord := true;
    exit(true);
  end;
  if doc^.IsArray then
    exit(true);
  result := false;
  Msg := 'TestBounds ist weder ein JSON-Array noch ein JSON-Objekt.';
end;

{ Is this template a write - the question both run paths ask, and neither
  should answer twice }
function IsWrite(const Rec: TSqlRec): boolean;
begin
  if Rec.Sql <> '' then
    result := KindOf(Rec.Sql) = skWrite
  else
    result := RecordKindFromActionKey(Rec.ActionKey) in
                [raInsert, raUpdate, raDelete];
end;

function HasServerWrites(const Recs: TSqlRecArray): boolean;
var
  i: PtrInt;
begin
  { a record write counts too: WriteRecordForAction reaches the server like
    any other write, and it is committed there like any other }
  for i := 0 to high(Recs) do
    if (Recs[i].TestBounds <> '') and
       IsWrite(Recs[i]) then
      exit(true);
  result := false;
end;

{ The same template, run the way a client runs it.

  Everything the direct run cannot answer is answered here, and the two
  differences from it are both deliberate. A scoped template RUNS - the
  server binds the identity, which is exactly what could not be tested
  before - so it sends one value fewer, like any client. And a refusal by the
  rights mask is not a fault: it is the correct answer for the account that
  is logged in, so it is reported as open rather than red. }
function RunOneOnServer(const Rec: TSqlRec; AllowWrites: boolean): TSweepRow;
var
  values, coerced: variant;
  json, msg: RawUtf8;
  fault: TSqlRuleFault;
  isrec, write: boolean;
  status: TSqlStatus;
  want, have: integer;
begin
  result := default(TSweepRow);
  result.ActionKey := Rec.ActionKey;
  result.Outcome := swSkipped;
  if Rec.TestBounds = '' then
  begin
    result.Message := 'kein TestBounds - geprüft, nicht ausgeführt';
    exit;
  end;
  if not ReadTestBounds(Rec, values, isrec, msg) then
  begin
    result.Outcome := swBad;
    result.Message := msg;
    exit;
  end;
  write := IsWrite(Rec);
  if write and
     not AllowWrites then
  begin
    result.Message := 'Schreibvorgang - der Server rollt nichts zurück, ' +
      'deshalb ausgelassen';
    exit;
  end;
  if isrec then
  begin
    { one record's JSON, sent exactly as a client sends it: the server
      resolves the type, generates the statement and writes. Nothing of the
      editor's own record path is involved, which is the point of running it
      this way at all }
    if not (RecordKindFromActionKey(Rec.ActionKey) in [raInsert, raUpdate]) then
    begin
      result.Outcome := swBad;
      result.Message := 'TestBounds ist ein Objekt, aber der Schlüssel ist ' +
        'kein Record-Schreibvorgang.';
      exit;
    end;
  end
  else
  begin
    { a scoped template leaves its last ? to the server, so the client owes
      one value fewer - the same rule ApplyCallerScope enforces }
    want := ExpectedParamCount(Rec);
    if Rec.CallerScope <> '' then
      dec(want);
    have := _Safe(values)^.Count;
    if have <> want then
    begin
      result.Outcome := swBad;
      result.Message := FormatUtf8(
        'TestBounds hat % Wert(e), % erwartet (Caller-Scope: %).',
        [have, want, Rec.CallerScope <> '']);
      exit;
    end;
    { NOT coerced here. A client sends what JSON can carry and the server
      turns it into what the template declares - and for a scoped template the
      server appends its own value first, so coercing against the full
      declaration here would count one parameter too many. Sending it raw is
      both simpler and what actually travels }
    coerced := values;
  end;
  if SqlTool = nil then
  begin
    result.Outcome := swBad;
    result.Message := 'Keine Verbindung zum Server.';
    exit;
  end;
  json := '[]';
  try
    if isrec then
      status := SqlTool.WriteRecordForAction(Rec.ActionKey, Rec.TestBounds)
    else if write then
      status := SqlTool.WriteDataForAction(Rec.ActionKey, coerced)
    else
      status := SqlTool.GetJsonFromAction(Rec.ActionKey, coerced, json);
  except
    on E: Exception do
    begin
      result.Outcome := swBad;
      result.Message := FormatUtf8('% %', [E.ClassType, E.Message]);
      exit;
    end;
  end;
  result.Ran := true;
  result.Status := status;
  case status of
    sqlOk,
    sqlNoRows,
    sqlNothingWritten:
      begin
        result.Outcome := swOk;
        result.Message := FormatUtf8('% über den Server', [ToText(status)]);
      end;
    sqlNotAllowed:
      begin
        { the account that is logged in may not do this, which is an answer
          and not a fault - a red line here would train the reader to ignore
          red }
        result.Outcome := swSkipped;
        result.Ran := false;
        result.Message := 'die Maske passt nicht zum angemeldeten Konto';
      end;
    sqlNeedsLogin:
      begin
        result.Outcome := swSkipped;
        result.Ran := false;
        result.Message := 'nicht angemeldet';
      end;
  else
    begin
      result.Outcome := swBad;
      result.Message := FormatUtf8('% über den Server', [ToText(status)]);
    end;
  end;
end;

function RunOne(Db: TEditorDb; const Rec: TSqlRec): TSweepRow;
var
  values, coerced: variant;
  isrec: boolean;
  res: TRunResult;
  fault: TSqlRuleFault;
  msg: RawUtf8;
  want, have: integer;
begin
  result := default(TSweepRow);
  result.ActionKey := Rec.ActionKey;
  result.Outcome := swSkipped;
  if Rec.TestBounds = '' then
  begin
    result.Message := 'kein TestBounds - geprüft, nicht ausgeführt';
    exit;
  end;
  if Rec.CallerScope <> '' then
  begin
    { the server binds the caller's own value to the last ?, and this tool
      binds no caller at all. Running it here would either miss a value or
      put the wrong one in its place, and a green line for that would be a
      lie about the very template that most needs one }
    result.Message := 'CallerScope: der Editor bindet keine Identität, ' +
      'also hier nicht ausführbar';
    exit;
  end;
  if not ReadTestBounds(Rec, values, isrec, msg) then
  begin
    result.Outcome := swBad;
    result.Message := msg;
    exit;
  end;
  if isrec then
  begin
    { a record write: the JSON goes down as it stands, the way a client's
      would, and the statement is made from the type and the key }
    res := RunRecord(Db, Rec, Rec.TestBounds, weRollback);
  end
  else
  begin
    want := ExpectedParamCount(Rec);
    have := _Safe(values)^.Count;
    if have <> want then
    begin
      result.Outcome := swBad;
      result.Message := FormatUtf8(
        'TestBounds hat % Wert(e), % Parameter erwartet.', [have, want]);
      exit;
    end;
    { the trip a client's values make: declared types first, then the rules,
      then the statement - the order the server goes in }
    if not CoerceBounds(Rec.ParamTypes, values, coerced, msg) then
    begin
      result.Outcome := swBad;
      result.Message := msg;
      exit;
    end;
    if not CheckParamRules(Rec.Rules, coerced, fault, msg) then
    begin
      result.Outcome := swBad;
      result.Message := 'Regel: ' + msg;
      exit;
    end;
    res := RunTemplate(Db, Rec, coerced, weRollback);
  end;
  result.Ran := true;
  result.Status := res.Status;
  result.Message := res.Message;
  { no rows is an answer and not a fault: a select whose test value matches
    nothing has still run, prepared and bound. The same for a write that
    matched no row - and a write cannot have been kept, this rolls back }
  if Succeeded(res.Status) or
     (res.Status in [sqlNoRows, sqlNothingWritten]) then
    result.Outcome := swOk
  else
  begin
    result.Outcome := swBad;
    result.Message := FormatUtf8('% - %', [ToText(res.Status), res.Message]);
  end;
end;

function SweepTemplates(Db: TEditorDb; const Recs: TSqlRecArray;
  Execute: boolean; Mode: TSweepMode; AllowWrites: boolean): TSweepRows;
var
  i: PtrInt;
  msg: RawUtf8;
begin
  SetLength(result, length(Recs));
  for i := 0 to high(Recs) do
  begin
    result[i] := default(TSweepRow);
    result[i].ActionKey := Recs[i].ActionKey;
    if not CheckTemplate(Recs[i], msg) then
    begin
      result[i].Outcome := swBad;
      result[i].Message := msg;
      continue;
    end;
    if not Execute then
    begin
      result[i].Outcome := swSkipped;
      result[i].Message := FormatUtf8('geprüft: % Nicht verbunden, also ' +
        'nicht ausgeführt.', [msg]);
      continue;
    end;
    if Mode = smServer then
      result[i] := RunOneOnServer(Recs[i], AllowWrites)
    else
      result[i] := RunOne(Db, Recs[i]);
  end;
end;

function SweepSummary(const Rows: TSweepRows): RawUtf8;
var
  i: PtrInt;
  ok, skipped, bad, ran: integer;
begin
  ok := 0;
  skipped := 0;
  bad := 0;
  ran := 0;
  for i := 0 to high(Rows) do
  begin
    case Rows[i].Outcome of
      swOk:
        inc(ok);
      swSkipped:
        inc(skipped);
      swBad:
        inc(bad);
    end;
    if Rows[i].Ran then
      inc(ran);
  end;
  result := FormatUtf8('% Template(s): % ok (% ausgeführt), % offen, % mit ' +
    'Befund.', [length(Rows), ok, ran, skipped, bad]);
end;

end.
