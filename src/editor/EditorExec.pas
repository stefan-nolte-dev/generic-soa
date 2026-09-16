unit EditorExec;

{ Run one statement for the editor, and never leave a trace.

  The statement is not registered anywhere yet, which is why the server must
  not be asked to run it: a "run this SQL" method would throw away the
  property the whole sample rests on. So the editor runs it itself.

  Everything below the wrapping is the server's code, not a copy: the
  infrastructure layer does the preparing, binding and fetching on an ad hoc
  TSqlRec, so what is tested here is what will run there, down to the JSON.
  The editor may reach into that layer - the layering rule protects the
  server's application layer from knowing how SQL runs, and says nothing about
  a developer tool that has to know.

  Writes are wrapped in a transaction, and what happens to it at the end is
  the caller's to say: rolled back, which is what a test is and what every
  caller gets that does not ask for anything else, or committed, which is
  what the editor's Rollback box turns off so the row can be looked at in the
  database itself. Nothing here decides that on its own, and nothing here
  commits a statement that failed. See EditorDb for what that does not
  cover.

  Two run modes, because sharing the server's code has a cost the sharing
  itself cannot reveal: a fault in the binding would be reproduced faithfully
  and reported as success. rmBound is what the server does, and the default.
  rmInlined writes the values into the statement as literals and binds
  nothing, so the two paths share no code where such a fault could hide.
  Agreement means the binding delivered what the literal says. }
{$I mormot.defines.inc}
{ The source of this unit is UTF-8, and its literals carry umlauts. Without
  this the compiler reads them as the system codepage and re-encodes them on
  the way into a RawUtf8 parameter, which turns "Ü" into "Ã" on screen. }
{$codepage UTF8}
interface

uses
  SysUtils,
  mormot.core.base,
  mormot.core.text,
  mormot.core.unicode,
  mormot.core.variants,
  mormot.db.sql,
  SqlStatus,
  SqlBounds,
  SqlTemplateTypes,
  InfraSqlServices, // ISqlTemplateExec is declared with its consumer, not here
  InfraSqlImplementation,
  SqlRecordBind, // the record direction, and the editor runs the same one
  EditorDb;

type
  /// what becomes of a write when it has run
  // - the editor's Rollback box, and nothing else, chooses weCommit: the
  //   promise that a test changes nothing is worth more than the convenience,
  //   so it is the default everywhere it is not asked about
  TWriteEnd = (
    /// undo it - a test, and the default
    weRollback,
    /// keep it, so the row can be seen in the database itself
    weCommit);

  /// which of the two paths a test run takes
  TRunMode = (
    /// bind the values, exactly as the server does - the default
    rmBound,
    /// write the values into the statement and bind nothing - the counter-check
    rmInlined);

  /// what the first keyword of a statement says it will do
  TStatementKind = (
    skUnknown,
    skSelect,
    skWrite);

  /// the outcome of one test run
  TRunResult = record
    Status: TSqlStatus;
    Kind: TStatementKind;
    /// the rows, as the server would have sent them
    Json: RawUtf8;
    /// what to put in front of the user
    Message: RawUtf8;
    /// the statement as it was actually handed to the driver
    // - the template for rmBound, the substituted text for rmInlined
    ExecutedSql: RawUtf8;
  end;

/// select, insert/update/delete, or neither
function KindOf(const Sql: RawUtf8): TStatementKind;

/// how many bind parameters the statement expects
// - counts ? outside string literals, so a ? inside 'text' is not counted
function ParamCount(const Sql: RawUtf8): integer;

/// the checks that do not need a database
// - returns true when nothing is wrong; Msg carries the findings either way
function StaticCheck(const Sql: RawUtf8; BoundCount: integer;
  out Msg: RawUtf8): boolean;

/// run the statement against the editor's connection
// - a write runs inside a transaction, rolled back unless Ending says
// otherwise - and a write that failed is rolled back either way
function Run(Db: TEditorDb; const ActionKey, Sql: RawUtf8;
  const Bounds: TBoundArray; Mode: TRunMode;
  Ending: TWriteEnd = weRollback): TRunResult;

/// run a template that carries no statement of its own
// - a retrieve and a delete are made from the action key and the record type
// alone, so there is nothing in the SQL box to hand to Run - and the one
// bound value is the key, not a record: Add/Insert and Update are the two
// that need one, and RunRecord is theirs
// - the statement is NOT generated here: the record travels down with an
// empty Sql and the server's own execution code makes it, the way it will be
// made in the server. What the editor shows as ExecutedSql is that same
// generator asked a second time, for the display
function RunGenerated(Db: TEditorDb; const Rec: TSqlRec;
  const Bounds: TBoundArray; Ending: TWriteEnd = weRollback): TRunResult;

/// run a template as it stands, with the values a client would send
// - the whole TSqlRec goes down, so a template that carries no statement has
// it generated where it will be generated in the server, and one that does
// runs the text it holds
// - Bounds is the variant array a client would put on the wire, not the
// editor's typed list: this is the entry point for a run whose values came
// from somewhere other than the parameter memo - the TestBounds column
// - a write runs in a transaction that Ending decides the end of, and
// weRollback is what a sweep over the whole set gets
function RunTemplate(Db: TEditorDb; const Rec: TSqlRec; const Bounds: variant;
  Ending: TWriteEnd = weRollback): TRunResult;

/// fetch the row a record template is about, to fill a dialog from
// - the statement is the retrieve branch asked for by name, so a template
// with no statement of its own can still be looked up
// - Row comes back as a TDocVariant object, or as null when the key matched
// nothing - which is not an error and says so in Msg
function LoadRecordRow(Db: TEditorDb; const Rec: TSqlRec; const Key: variant;
  out Row: variant; out Msg: RawUtf8): boolean;

/// run a record template from one record's JSON, the way the server does
// - the statement is not passed in: it is generated from the record type and
// the action key, or its :Names are filled - the same call the server makes,
// so what the editor tests is the path that will run, not a copy of it
// - ExecutedSql shows what came out of that, which is the interesting part
// - a write, so it runs inside the transaction Ending decides the end of
function RunRecord(Db: TEditorDb; const Rec: TSqlRec;
  const Json: RawUtf8; Ending: TWriteEnd = weRollback): TRunResult;

implementation

const
  KIND_TEXT: array[TStatementKind] of RawUtf8 = (
    'unrecognised', 'select', 'write');

{ does a write keyword stand anywhere outside a string literal }
function HasWriteKeyword(const Sql: RawUtf8): boolean;
var
  i: PtrInt;
  inString, atWordStart: boolean;
  p: PUtf8Char;
begin
  result := true;
  inString := false;
  atWordStart := true;
  for i := 1 to length(Sql) do
  begin
    if Sql[i] = '''' then
      inString := not inString
    else if not inString and atWordStart then
    begin
      p := @PUtf8Char(pointer(Sql))[i - 1];
      if IdemPChar(p, 'INSERT ') or
         IdemPChar(p, 'UPDATE ') or
         IdemPChar(p, 'DELETE ') or
         IdemPChar(p, 'MERGE ') then
        exit;
    end;
    { a keyword only counts where a word begins }
    atWordStart := not (Sql[i] in ['A'..'Z', 'a'..'z', '0'..'9', '_']);
  end;
  result := false;
end;

function KindOf(const Sql: RawUtf8): TStatementKind;
var
  p: PUtf8Char;
begin
  p := pointer(Sql);
  while (p <> nil) and
        (p^ <= ' ') and
        (p^ <> #0) do
    inc(p);
  if p = nil then
    exit(skUnknown);
  if IdemPChar(p, 'WITH') then
    { A common table expression is not a statement kind. It usually precedes
      a select, but "with x as (...) delete from y where ..." is just as legal
      - and a select runs outside the rollback transaction, so getting this
      wrong would commit the write this tool promises never to commit. The
      first keyword cannot decide it, so the rest of the text does, and an
      alias that merely reads like "update" costs nothing but the row display }
    if HasWriteKeyword(Sql) then
      result := skWrite
    else
      result := skSelect
  else if IdemPChar(p, 'SELECT') or
     IdemPChar(p, 'PRAGMA') then
    result := skSelect
  else if IdemPChar(p, 'INSERT') or
          IdemPChar(p, 'UPDATE') or
          IdemPChar(p, 'DELETE') or
          IdemPChar(p, 'MERGE') then
    result := skWrite
  else
    result := skUnknown;
end;

function ParamCount(const Sql: RawUtf8): integer;
var
  i: PtrInt;
  inString: boolean;
begin
  result := 0;
  inString := false;
  for i := 1 to length(Sql) do
    case Sql[i] of
      '''':
        inString := not inString; // a doubled '' flips twice: still correct
      '?':
        if not inString then
          inc(result);
    end;
end;

function StaticCheck(const Sql: RawUtf8; BoundCount: integer;
  out Msg: RawUtf8): boolean;
var
  kind: TStatementKind;
  wanted: integer;
  low: RawUtf8;
begin
  result := true;
  Msg := '';
  if Sql = '' then
  begin
    Msg := 'The statement is empty.';
    exit(false);
  end;
  kind := KindOf(Sql);
  if kind = skUnknown then
  begin
    Msg := Msg + 'The first keyword is neither select nor insert/update/' +
      'delete - the server would not know whether to expect rows.'#13#10;
    result := false;
  end;
  { the rule that costs nothing here and is expensive to discover in
    production: a write without a where touches every row }
  low := LowerCase(Sql);
  { not only when the statement STARTS with update or delete: after a common
    table expression the verb stands in the middle, and that is exactly the
    form where a missing where is easiest to overlook }
  if (kind = skWrite) and
     ((PosEx('update', low) > 0) or
      (PosEx('delete', low) > 0)) and
     (PosEx('where', low) = 0) then
  begin
    Msg := Msg + 'This update or delete has no where clause: it would ' +
      'touch every row of the table.'#13#10;
    result := false;
  end;
  wanted := ParamCount(Sql);
  if wanted <> BoundCount then
  begin
    Msg := Msg + FormatUtf8(
      'The statement has % parameter(s) but % value(s) were given.'#13#10,
      [wanted, BoundCount]);
    result := false;
  end;
  if result then
    Msg := FormatUtf8('Looks sound: % statement, % parameter(s).',
      [KIND_TEXT[kind], wanted]);
end;

{ Why the reason is fetched here and not returned by SelectJson.

  mORMot catches a failed Prepare itself and answers with nil rather than an
  exception - which is why the editor sees sqlFailed and not a crash, and also
  why the debugger reports an ESqlite3Exception that is already handled. The
  reason text is left on the connection, and the editor holds that connection,
  so it can read it without widening the server's interface by one field it
  does not need. }
function LastError(Db: TEditorDb): RawUtf8;
var
  conn: TSqlDBConnection;
begin
  { the reason Infra kept on the way out, first: it covers the calls that
    raise AFTER a successful prepare - binding, executing, converting - which
    is where a statement being drafted usually goes wrong, and where the
    connection has nothing to say because the prepare went fine }
  result := LastSqlError;
  if result <> '' then
    exit;
  if Db = nil then
    exit;
  { and for a statement the driver refused outright, what it said then }
  conn := Db.Connection;
  if conn <> nil then
    result := conn.LastErrorMessage;
  if result = '' then
    { asking for the connection can fail too, and then that is the reason }
    result := Db.LastCleanupError;
  if result = '' then
    result := 'No reason reported by the driver.';
end;

function Perform(Db: TEditorDb; const Template: TSqlRec;
  const Bound: variant; Ending: TWriteEnd): TRunResult; forward;

function Run(Db: TEditorDb; const ActionKey, Sql: RawUtf8;
  const Bounds: TBoundArray; Mode: TRunMode;
  Ending: TWriteEnd): TRunResult;
var
  rec: TSqlRec;
  bound: variant;
  msg: RawUtf8;
  wanted: integer;
begin
  result := default(TRunResult);
  result.Status := sqlFailed;
  result.Json := '[]';
  result.Kind := KindOf(Sql);
  if (Db = nil) or
     not Db.Connected then
  begin
    result.Message := 'Not connected to a database.';
    exit;
  end;
  if Sql = '' then
  begin
    result.Message := 'The statement is empty.';
    exit;
  end;
  rec.ActionKey := ActionKey;
  if rec.ActionKey = '' then
    rec.ActionKey := '(unsaved)'; // it only ever reaches the log
  case Mode of
    rmBound:
      begin
        { Counted before anything is bound. A driver asked to run a statement
          with an unbound ? answers differently depending on which one it is:
          SQLite treats the missing value as NULL and returns no rows, ODBC
          raises - and the exception carries no reason the connection can be
          asked for afterwards, so the editor could only say "no reason
          reported". The count is the reason, and it is known here.
          StaticCheck says the same thing, but that is behind the "Prüfen"
          button, and this path has to hold on its own. }
        wanted := ParamCount(Sql);
        if wanted <> length(Bounds) then
        begin
          result.Message := FormatUtf8(
            'The statement has % parameter(s) but % value(s) were given.',
            [wanted, length(Bounds)]);
          exit;
        end;
        { the ordinary path, and what the server does: the values stay values
          and the driver binds them }
        if not BoundsToVariant(Bounds, bound, msg) then
        begin
          result.Message := msg;
          exit;
        end;
        rec.Sql := Sql;
      end;
    rmInlined:
      begin
        { the counter-check: nothing is bound, so nothing in the binding can
          be the reason the two runs differ }
        if not InlineBounds(Sql, Bounds, rec.Sql, msg) then
        begin
          result.Message := msg;
          exit;
        end;
        bound := _Arr([]);
      end;
  end;
  result := Perform(Db, rec, bound, Ending);
  if Mode = rmInlined then
    result.Message := result.Message + ' (values inlined, nothing bound)';
end;

function RunTemplate(Db: TEditorDb; const Rec: TSqlRec; const Bounds: variant;
  Ending: TWriteEnd): TRunResult;
begin
  result := default(TRunResult);
  result.Status := sqlFailed;
  result.Json := '[]';
  if (Db = nil) or
     not Db.Connected then
  begin
    result.Message := 'Not connected to a database.';
    exit;
  end;
  result := Perform(Db, Rec, Bounds, Ending);
end;

{ Everything below the difference between the three ways a statement gets
  here: from the two edit boxes, with the values inlined, or generated from a
  record. By the time it runs, all three are a resolved template and a list of
  bound values - which is exactly what the server has at this point too. }
function Perform(Db: TEditorDb; const Template: TSqlRec;
  const Bound: variant; Ending: TWriteEnd): TRunResult;
var
  rec: TSqlRec;
  exec: ISqlTemplateExec;
  conn: TSqlDBConnection;
  kept: boolean;
  generated, msg: RawUtf8;
begin
  rec := Template;
  result := default(TRunResult);
  result.Status := sqlFailed;
  result.Json := '[]';
  result.ExecutedSql := rec.Sql;
  if rec.Sql = '' then
  begin
    { There is no text to read the kind off, so the action key says it - the
      same rule the server goes by: a retrieve reads, a delete writes. The
      statement itself is made below this, inside SelectJson or Execute, so
      what runs here is the generator that will run there and not a copy of
      it. Asking the generator a second time is for the display only, and a
      refusal is left to the call that follows, which words it better. }
    case RecordKindFromActionKey(rec.ActionKey) of
      raRetrieve,
      raList:
        result.Kind := skSelect;
      raDelete:
        result.Kind := skWrite;
    end;
    if GeneratedSqlFor(rec, generated, msg) = rbOk then
      result.ExecutedSql := generated;
  end
  else
    result.Kind := KindOf(rec.Sql);
  exec := TSqlTemplateExec.Create(Db.Props);
  try
    if result.Kind = skSelect then
    begin
      result.Status := exec.SelectJson(rec, Bound, result.Json);
      if result.Status = sqlOk then
        result.Message := 'Select ran.'
      else if result.Status = sqlNoRows then
        result.Message := 'Select ran and matched no row.'
      else
        result.Message := 'The statement failed. ' + LastError(Db);
    end
    else
    begin
      conn := Db.Connection;
      if conn = nil then
      begin
        { the connection was good when it was opened and is not any more:
          Db reports rather than raises, and what it reports is here }
        result.Message := 'Keine Verbindung mehr. ' + LastError(Db);
        exit;
      end;
      kept := false;
      conn.StartTransaction;
      try
        result.Status := exec.Execute(rec, Bound);
        { The only place in this unit that commits, and it takes two things
          to get here: the caller asked for it, and the statement ran.
          Everything else - a failure, an exception, a caller that said
          nothing - ends the way it always did. "Changed no row" counts as
          ran: committing nothing changes nothing, and calling that a
          rollback would only invite the question which of the two it was. }
        if (Ending = weCommit) and
           (result.Status in [sqlOk, sqlNothingWritten]) then
        begin
          conn.Commit;
          kept := true;
        end
        else
          conn.Rollback;
      except
        on E: Exception do
        begin
          { a commit that raises leaves the transaction open, and an open
            transaction on a shared connection is worse than a lost row }
          try
            conn.Rollback;
          except
            ; // the connection is gone: there is nothing left to end
          end;
          kept := false;
          raise; // the handler below this one turns it into the message
        end;
      end;
      { A statement whose first keyword is neither select nor insert/update/
        delete goes down this path as well - a transaction that is always
        rolled back is the safe place for something the editor cannot
        classify. It is not a write, though, and saying so about a mistyped
        "select" only sends its author looking for a write that never was. }
      if result.Kind = skWrite then
        case result.Status of
          sqlOk:
            if kept then
              { said plainly, and said first: the row is in the database and
                nothing here will take it back out }
              result.Message := 'Write ran and was COMMITTED - the row is in ' +
                'the database. Rollback is off.'
            else
              result.Message := 'Write ran, and was rolled back.';
          sqlNothingWritten:
            if kept then
              result.Message := 'Write ran but changed no row. Committed, ' +
                'which changed nothing either. Rollback is off.'
            else
              result.Message :=
                'Write ran but changed no row, and was rolled back.';
        else
          result.Message := 'The statement failed, and was rolled back. ' +
            LastError(Db);
        end
      else
        case result.Status of
          sqlOk,
          sqlNothingWritten:
            if kept then
              result.Message := 'Ran, and was COMMITTED. The first keyword ' +
                'is neither select nor insert/update/delete, so this was run ' +
                'as a write would be - and with Rollback off it stands, ' +
                'whatever it did. No rows are shown even if it produced some.'
            else
              result.Message := 'Ran, and nothing was committed. The first ' +
                'keyword is neither select nor insert/update/delete, so this ' +
                'was run as a write would be - no rows are shown even if the ' +
                'statement produced some.';
        else
          result.Message := 'The statement failed. ' + LastError(Db);
        end;
    end;
  except
    on E: Exception do
    begin
      result.Status := sqlFailed;
      result.Message := FormatUtf8('% %', [E.ClassType, E.Message]);
    end;
  end;
  { The editor runs a statement straight on the connection, where the server
    runs it through the dom layer. For every other template that is the same
    statement with the same values - but a template with CallerScope set is
    the one case where it is not: here the last ? carries whatever was typed,
    over the server it carries the caller. Saying nothing would let a green
    run here stand as proof of something that was never tested, so this goes
    in front of the message rather than behind it: the status line is one
    line, and the warning is the half worth seeing. }
  if rec.CallerScope <> '' then
    result.Message := FormatUtf8('Ungescopt getestet (Caller-Scope "%" ' +
      'wirkt nur über den Server, nicht hier). ', [rec.CallerScope]) +
      result.Message;
end;

function RunGenerated(Db: TEditorDb; const Rec: TSqlRec;
  const Bounds: TBoundArray; Ending: TWriteEnd): TRunResult;
var
  one: TSqlRec;
  bound: variant;
  kind: TRecordActionKind;
  wanted: integer;
  msg: RawUtf8;
begin
  result := default(TRunResult);
  result.Status := sqlFailed;
  result.Json := '[]';
  if (Db = nil) or
     not Db.Connected then
  begin
    result.Message := 'Not connected to a database.';
    exit;
  end;
  kind := RecordKindFromActionKey(Rec.ActionKey);
  if not (kind in [raRetrieve, raList, raDelete]) then
  begin
    { an insert and an update are made from a record, and the values below
      the statement are not one - the dialog is where that record comes from }
    result.Message := FormatUtf8('% hat kein Statement, und ohne Record ' +
      'entstehen nur Retrieve, List und Delete. Add/Insert und Update ' +
      'brauchen einen Record: "Record-Werte eingeben...".',
      [Rec.ActionKey]);
    exit;
  end;
  { How many ? the statement will have is known before it exists: the key is
    one, and a list has what its filter carries. Counted here for the same
    reason Run counts its own: an unbound ? is a NULL and no rows on SQLite,
    and an exception with no reason on ODBC }
  wanted := ExpectedParamCount(Rec);
  if length(Bounds) <> wanted then
  begin
    if kind = raList then
      result.Message := FormatUtf8('Der Filter dieses Templates hat % ?, ' +
        'angegeben sind % Werte.', [wanted, length(Bounds)])
    else
      result.Message := FormatUtf8('Ein erzeugtes % nimmt genau einen ' +
        'Wert - den Schlüssel. Angegeben: %.',
        [Rec.ActionKey, length(Bounds)]);
    exit;
  end;
  if not BoundsToVariant(Bounds, bound, msg) then
  begin
    result.Message := msg;
    exit;
  end;
  one := Rec;
  { emphatically empty: an empty statement is what makes the exec generate
    one, and that is the whole point of this path }
  one.Sql := '';
  result := Perform(Db, one, bound, Ending);
end;

function LoadRecordRow(Db: TEditorDb; const Rec: TSqlRec; const Key: variant;
  out Row: variant; out Msg: RawUtf8): boolean;
var
  one: TSqlRec;
  res: TRunResult;
  rows: TDocVariantData;
  sql: RawUtf8;
begin
  result := false;
  SetVariantNull(Row);
  Msg := '';
  if (Db = nil) or
     not Db.Connected then
  begin
    Msg := 'Not connected to a database.';
    exit;
  end;
  if RetrieveSqlFor(Rec, sql, Msg) <> rbOk then
    exit;
  one := Rec;
  one.Sql := sql;
  { the key is the caller's one value, and it is bound like any other. The
    template's ParamTypes stay: a key declared int is coerced as int here too }
  { a retrieve: it reads, so the ending never comes up - and the one that
    changes nothing is the one to name here }
  res := Perform(Db, one, _Arr([Key]), weRollback);
  if res.Status = sqlNoRows then
  begin
    Msg := FormatUtf8('Keine Zeile mit diesem Schlüssel: %', [res.ExecutedSql]);
    exit;
  end;
  if res.Status <> sqlOk then
  begin
    Msg := res.Message;
    exit;
  end;
  rows.InitJson(res.Json, JSON_FAST_FLOAT);
  if rows.Count <= 0 then
  begin
    Msg := 'Die Abfrage lief, lieferte aber nichts Lesbares.';
    exit;
  end;
  { a select answers with rows; a key matches one, and that one is the row }
  Row := rows.Values[0];
  Msg := res.ExecutedSql;
  result := true;
end;

function RunRecord(Db: TEditorDb; const Rec: TSqlRec;
  const Json: RawUtf8; Ending: TWriteEnd): TRunResult;
var
  one: TSqlRec;
  bound: variant;
  expanded, msg: RawUtf8;
begin
  result := default(TRunResult);
  result.Status := sqlFailed;
  result.Json := '[]';
  result.Kind := skWrite;
  if (Db = nil) or
     not Db.Connected then
  begin
    result.Message := 'Not connected to a database.';
    exit;
  end;
  { the server's own call, with the server's own refusals: an unmarked key, a
    type nobody knows, a declaration that does not parse }
  if BindRecordJson(Rec, Json, expanded, bound, msg) <> rbOk then
  begin
    result.Message := msg;
    exit;
  end;
  one := Rec;
  one.Sql := expanded;
  { the values came out of a typed record, so there is nothing to coerce -
    the same line stands in TSqlTemplateExec.ExecuteRecord }
  one.ParamTypes := '';
  result := Perform(Db, one, bound, Ending);
end;

end.
