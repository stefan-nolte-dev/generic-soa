unit SqlRecordBind;

{$I mormot.defines.inc}

{ One record -> the bound values of one registered statement.

  The incoming counterpart of ParseDynArray. There the caller names the type
  it wants and RTTI turns JSON into an array of records; here the template
  names the type it expects and RTTI turns one record back into typed values.
  Written once for every record there will ever be.

  A record template comes either way round.

  WITHOUT a statement everything is generated, from the record and the action
  key - OrmUpdateTDtoCustomer + TDtoCustomer gives
    update Customer set Name = ?, City = ? where ID = ?
  on conventions that are each one constant and one function: the key is
  marked Orm and then names a verb (SqlTemplateTypes, because the domain
  layer reads the same mark and must not see this unit), the table is the
  record type without its TDto prefix and Row suffix, the key column is what
  KeyField says and ID when it says nothing.

  Four verbs, and only two of them take a record. An insert and an update
  send one; a retrieve and a delete send the key alone, because the columns
  to read are the record type's business and the server knows the type from
  the template - which is what an ORM does when it sends a list of field
  names rather than a record. So those two carry no record here at all: this
  unit only composes their statement, and the ordinary bound-value path runs
  it.

  The record type is either compiled in and registered - see WriteDtos - or
  declared as text in the RecordDecl column and registered from there on
  first use. The second way is what keeps a new record from being a rebuild;
  the first always wins, see ResolveRecordType.

  Nothing in that text comes from the caller - only the record's own field
  names and its type name - and the values are still bound, so this stays as
  far from "send me any SQL" as the rest.

  WITH a statement the placeholders are by NAME, for the cases the convention
  does not fit: another table name, a composite key, an extra condition.

  Either way the record is what restores the types: JSON has four, a Customer
  row has an integer ID and an Invoice a TDateTime and a currency.

  Two lines are easy to get wrong, both marked below - AllocMem, or a RawUtf8
  field starts out pointing at old heap, and ValueFinalize, or every string
  leaks once per call. }

interface

uses
  SysUtils,
  mormot.core.base,
  mormot.core.text,
  mormot.core.unicode, // for IdemPChar and IdemPropNameU
  mormot.core.rtti,
  mormot.core.data, // for TSynDictionary, holding what was registered from text
  mormot.core.json,
  mormot.core.variants,
  SqlTemplateTypes; // for TSqlRec

type
  /// why a record write could not be turned into bound values
  // - rbBadJson is the caller's fault; everything else is a template that
  // does not match the records this server knows
  TRecordBindResult = (
    rbOk,
    rbNoRecordType,
    rbUnknownRecordType,
    rbBadRecordDecl,
    rbNoPlaceholder,
    rbQuestionMark,
    rbUnknownField,
    rbBadJson,
    rbNotOrmAction,
    rbNoWriteKind,
    rbNoTable,
    rbNoKeyField,
    rbNoField);


const
  /// stripped off a record type name to get the table name
  RECORDTYPE_PREFIX = 'TDto';
  /// and off the end
  RECORDTYPE_SUFFIX = 'Row';
  /// the column a generated update matches on, and a generated insert omits
  // - the default only: a template says its own in the KeyField column, and
  // has to, everywhere the demo's convention does not hold
  RECORDKEY_FIELD = 'ID';

/// the key column of a generated statement: the template's, or ID
function KeyFieldOf(const Rec: TSqlRec): RawUtf8;

/// the record type a template names, registered from its text if need be
// - FindName first, so a type compiled into this binary always wins and is
// never redefined from a column - RegisterFromText would REPLACE its fields,
// and a row could then silently reshape a Pascal type the code relies on
// - only names this unit registered itself are re-registered, and only when
// the declaration actually changed: that is what makes an edited RecordDecl
// take effect on a reload instead of staying on the first text ever seen
function ResolveRecordType(const Rec: TSqlRec; out rc: TRttiCustom;
  out Msg: RawUtf8): TRecordBindResult;

/// the statement a record template would generate, without executing anything
// - what the editor shows: the same three conventions, the same code
function GeneratedSqlFor(const Rec: TSqlRec; out Sql: RawUtf8;
  out Msg: RawUtf8): TRecordBindResult;

/// the same statement in the form a template can carry
// - one difference, and it matters: an insert and an update bind their ?
// from the record's fields by position, and a WRITTEN statement cannot say
// that - it names its fields as :Name placeholders, and a written record
// statement carrying ? is refused (rbQuestionMark). So for those two kinds
// the ? are put back as the names they stand for, and what comes out can be
// edited, saved and run
// - a retrieve, a list and a delete bind nothing from a record: their ? are
// the caller's values and stay ?
// - for the editor, which offers this as the starting point for a statement
// the convention cannot express - a big record is not one anybody wants to
// type out
function EditableSqlFor(const Rec: TSqlRec; out Sql: RawUtf8;
  out Msg: RawUtf8): TRecordBindResult;

/// the select that would fetch the row this template is about
// - the template's OWN verb is not consulted: an update is asked for the row
// it is about to overwrite, and that is a retrieve on the same record type
// and the same key column. Which is why this is here and not a second rule
// in the editor - it is the retrieve branch, asked for by name
function RetrieveSqlFor(const Rec: TSqlRec; out Sql: RawUtf8;
  out Msg: RawUtf8): TRecordBindResult;


/// the SQLite table this record type would need, as a statement to read
// - the cheap half of "create the table": this generates, it never executes.
// What comes back is meant to be looked at, copied and run by hand - which
// is the whole difference between a sample that creates nothing and one that
// creates something behind your back
// - SQLite spelling on purpose: integer/text/real, "if not exists", and
// "autoincrement" on the key. Those are the affinities demo.sql already
// writes out by hand, so what this composes and what the demo database holds
// are the same table
// - the key column is there whether or not the record carries it: a
// generated retrieve and a generated delete both match on it, so a table
// without it would break two of the four verbs. When the record does not
// declare it, it is put in front and Msg says so
// - nullability, defaults, indexes and foreign keys are NOT generated. A
// record type states none of them, and inventing them here would be this
// code deciding something the declaration never said
function CreateTableSqlFor(const Rec: TSqlRec; out Sql: RawUtf8;
  out Msg: RawUtf8): TRecordBindResult;

/// 'TDtoCustomer' -> 'Customer', and 'TDtoArtikel' -> 'Artikel'
// - both affixes are optional and matched case insensitively, as is the type
// name itself when the registry is asked for it
// - returns '' when nothing is left after the affixes are stripped
function TableFromRecordType(const RecordType: RawUtf8): RawUtf8;

/// replace every :Name in a statement by ? and report the names in order
// - text inside '...' literals is left alone, doubled quotes included
// - false when there is no placeholder at all: a record write that binds
// nothing is a mistake in the template, not a no-op
function ExpandNamedParams(const Sql: RawUtf8; out Expanded: RawUtf8;
  out Names: TRawUtf8DynArray; out HasQuestionMark: boolean): boolean;

/// load Json into the record the template names, and bind it
// - Expanded is the statement with ? for every :Name, or the generated one
// - Bounds holds the values in the order the ? appear
// - Msg goes to the log, never to a client
function BindRecordJson(const Rec: TSqlRec; const Json: RawUtf8;
  out Expanded: RawUtf8; out Bounds: variant;
  out Msg: RawUtf8): TRecordBindResult;

implementation

function IsIdentFirst(c: AnsiChar): boolean;
  {$ifdef HASINLINE}inline;{$endif}
begin
  result := c in ['A'..'Z', 'a'..'z', '_'];
end;

function IsIdentChar(c: AnsiChar): boolean;
  {$ifdef HASINLINE}inline;{$endif}
begin
  result := c in ['A'..'Z', 'a'..'z', '0'..'9', '_'];
end;

function ExpandNamedParams(const Sql: RawUtf8; out Expanded: RawUtf8;
  out Names: TRawUtf8DynArray; out HasQuestionMark: boolean): boolean;
var
  i, b, s, n, L: PtrInt;
  P: PAnsiChar;
  tmp: RawUtf8;
begin
  Expanded := '';
  Names := nil;
  HasQuestionMark := false;
  n := 0;
  L := length(Sql);
  P := pointer(Sql);
  i := 0;
  b := 0;
  while i < L do
    if P[i] = '''' then
    begin
      { a literal: nothing inside it is a placeholder, and '' is one quote }
      inc(i);
      while i < L do
        if P[i] <> '''' then
          inc(i)
        else
        begin
          inc(i);
          if (i < L) and
             (P[i] = '''') then
            inc(i)
          else
            break;
        end;
    end
    else if (P[i] = ':') and
            (i + 1 < L) and
            IsIdentFirst(P[i + 1]) then
    begin
      FastSetString(tmp, P + b, i - b);
      Expanded := Expanded + tmp + '?';
      inc(i); // the ':'
      s := i;
      while (i < L) and
            IsIdentChar(P[i]) do
        inc(i);
      FastSetString(tmp, P + s, i - s);
      if n = length(Names) then
        SetLength(Names, n + 8);
      Names[n] := tmp;
      inc(n);
      b := i;
    end
    else
    begin
      { a positional ? in a record statement would want a value nobody
        supplies, so it is reported rather than silently left standing }
      if P[i] = '?' then
        HasQuestionMark := true;
      inc(i);
    end;
  FastSetString(tmp, P + b, L - b);
  Expanded := Expanded + tmp;
  SetLength(Names, n);
  result := n > 0;
end;


function TableFromRecordType(const RecordType: RawUtf8): RawUtf8;
var
  L: PtrInt;
begin
  result := RecordType;
  { IdemPropNameU rather than IdemPChar for both affixes: it compares two
    ordinary strings case insensitively, so the constants above can be spelled
    the way the type is spelled instead of having to be uppercase }
  if IdemPropNameU(copy(result, 1, length(RECORDTYPE_PREFIX)),
       RECORDTYPE_PREFIX) then
    delete(result, 1, length(RECORDTYPE_PREFIX));
  L := length(result) - length(RECORDTYPE_SUFFIX);
  if (L > 0) and
     IdemPropNameU(copy(result, L + 1, maxInt), RECORDTYPE_SUFFIX) then
    SetLength(result, L);
end;

{ Every name in the generated text comes from the record's own RTTI or from
  its type name - none of it from the caller - and the values are bound. }
function GenerateSql(rc: TRttiCustom; Kind: TRecordActionKind;
  const Rec: TSqlRec; const Table: RawUtf8; out Sql: RawUtf8;
  out Names: TRawUtf8DynArray): TRecordBindResult;
var
  i, n: PtrInt;
  cols, vals, sets, key, all, where, order, KeyField: RawUtf8;
begin
  KeyField := KeyFieldOf(Rec);
  { A delete needs no field of the record at all - the table and the key
    column are the whole statement, and the value comes from the caller. It
    is the one kind that says something about a record type without reading
    it, which is also why it is the only one that cannot fail on rbNoField }
  if Kind = raDelete then
  begin
    Names := nil;
    Sql := FormatUtf8('delete from % where % = ?;', [Table, KeyField]);
    exit(rbOk);
  end;
  n := 0;
  SetLength(Names, rc.Props.Count);
  for i := 0 to rc.Props.Count - 1 do
    { the key is matched on, never written: insert leaves it to the
      database, update puts it in the where clause. A record that does not
      carry the key field at all is an insert into a table whose key the
      caller supplies - which is why only the update below refuses }
    if IdemPropNameU(rc.Props.List[i].Name, KeyField) then
      key := rc.Props.List[i].Name
    else
    begin
      if cols <> '' then
      begin
        cols := cols + ', ';
        vals := vals + ', ';
        sets := sets + ', ';
      end;
      cols := cols + rc.Props.List[i].Name;
      vals := vals + '?';
      sets := sets + rc.Props.List[i].Name + ' = ?';
      Names[n] := rc.Props.List[i].Name;
      inc(n);
    end;
  if Kind in [raRetrieve, raList] then
  begin
    { every field, the key included: what comes back has to load into the
      same record type on the other side, so the column list is the record
      and not a subset of it. The key is NOT taken from the record here -
      there is no record yet, that is what is being fetched - so it may name
      a column this type does not carry, and the where clause still holds.
      A list wants that same column list, which is why it shares this branch:
      the one and the many differ in their where clause, not in their shape }
    all := '';
    for i := 0 to rc.Props.Count - 1 do
    begin
      if all <> '' then
        all := all + ', ';
      all := all + rc.Props.List[i].Name;
    end;
    if all = '' then
      exit(rbNoField);
    Names := nil; // the one bound value is the caller's key, not a field
    if Kind = raRetrieve then
      Sql := FormatUtf8('select % from % where % = ?;', [all, Table, KeyField])
    else
    begin
      { A list is the same select with the template's own where clause in
        place of the key - and with it parenthesised, so that whatever the
        template wrote there cannot change how a condition appended after it
        binds. Today that is the caller scope the domain layer appends; an
        "or" in an unparenthesised filter would quietly let rows past it. }
      where := '';
      if Rec.Filter <> '' then
        where := FormatUtf8(' where (%)', [Rec.Filter]);
      order := '';
      if Rec.OrderBy <> '' then
        order := FormatUtf8(' order by %', [Rec.OrderBy]);
      Sql := FormatUtf8('select % from %%%;', [all, Table, where, order]);
    end;
    exit(rbOk);
  end;
  if n = 0 then
    exit(rbNoField); // a record of nothing but the key writes nothing
  case Kind of
    raInsert:
      Sql := FormatUtf8('insert into % (%) values (%);', [Table, cols, vals]);
    raUpdate:
      begin
        { without a key there is no where clause, and a generated update
          without a where clause would rewrite the whole table. Refuse }
        if key = '' then
          exit(rbNoKeyField);
        Names[n] := key;
        inc(n);
        Sql := FormatUtf8('update % set % where % = ?;', [Table, sets, key]);
      end;
  end;
  SetLength(Names, n);
  result := rbOk;
end;

function KeyFieldOf(const Rec: TSqlRec): RawUtf8;
begin
  result := Rec.KeyField;
  if result = '' then
    result := RECORDKEY_FIELD;
end;

var
  { name -> the RecordDecl it was registered from, for the names THIS unit
    put into Rtti and no other. A type that is compiled in never appears
    here, which is what keeps the check below from touching one }
  FromText: TSynDictionary;

function RegisterDecl(const TypeName, Decl: RawUtf8;
  out rc: TRttiCustom; out Msg: RawUtf8): boolean;
var
  known: RawUtf8;
begin
  result := false;
  { the text this name was last registered from successfully, to put back if
    the new one turns out to be broken: RegisterFromText clears the fields
    BEFORE it parses, so a re-registration that raises leaves the type half
    defined - and the next call would find that half and read it as valid }
  if not FromText.FindAndCopy(TypeName, known) then
    known := '';
  try
    { Rtti.RegisterFromText takes its own lock, and re-registering an
      existing text type updates that same instance rather than replacing
      it - so a pointer someone already holds stays valid }
    rc := Rtti.RegisterFromText(TypeName, Decl);
    result := rc <> nil;
    if result then
      FromText.AddOrUpdate(TypeName, Decl)
    else
      Msg := FormatUtf8('[%] could not be registered from its declaration',
        [TypeName]);
  except
    on E: Exception do
    begin
      rc := nil;
      Msg := FormatUtf8('the declaration of [%] does not parse: % %',
        [TypeName, E.ClassType, E.Message]);
    end;
  end;
  if result or
     (known = '') then
    { nothing was registered from text under this name before, so a failure
      leaves nothing behind either: measured, FindName does not see it }
    exit;
  try
    Rtti.RegisterFromText(TypeName, known);
  except
    { there is nothing further to do here, and nothing further to say: the
      message the caller reports is the one about the declaration that failed }
  end;
end;

function ResolveRecordType(const Rec: TSqlRec; out rc: TRttiCustom;
  out Msg: RawUtf8): TRecordBindResult;
var
  known: RawUtf8;
begin
  rc := nil;
  Msg := '';
  if Rec.RecordType = '' then
  begin
    Msg := 'no record type declared for this action key';
    exit(rbNoRecordType);
  end;
  { by name, which is what lets it be a column rather than a case statement.
    The kind is checked here rather than passed to FindName: the overload that
    takes a kind moved from a set to a single value in mORMot, and rkRecordTypes
    is already the portable spelling of "record here, object on FPC" }
  rc := Rtti.FindName(pointer(Rec.RecordType), length(Rec.RecordType));
  if (rc <> nil) and
     not (rc.Kind in rkRecordTypes) then
    rc := nil;
  if Rec.RecordDecl <> '' then
    if rc = nil then
    begin
      { first use of a type that lives in a row and nowhere else }
      if not RegisterDecl(Rec.RecordType, Rec.RecordDecl, rc, Msg) then
        exit(rbBadRecordDecl);
    end
    else if FromText.FindAndCopy(Rec.RecordType, known) and
            (known <> Rec.RecordDecl) then
    begin
      { the row was edited and reloaded: this name is ours, so redefining it
        is right. A name that is NOT in FromText is a compiled type, and the
        declaration beside it is ignored rather than allowed to reshape it }
      if not RegisterDecl(Rec.RecordType, Rec.RecordDecl, rc, Msg) then
        exit(rbBadRecordDecl);
    end;
  if rc = nil then
  begin
    Msg := FormatUtf8('unknown record type [%] - not registered, and no ' +
      'declaration in the RecordDecl column?', [Rec.RecordType]);
    exit(rbUnknownRecordType);
  end;
  result := rbOk;
end;

{ the conventions applied to a kind the caller names, so that a template can
  also be asked for a statement other than its own verb - which is what the
  editor does when it fetches the row an update is about to overwrite }
function GenerateKind(const Rec: TSqlRec; rc: TRttiCustom;
  Kind: TRecordActionKind; out Sql: RawUtf8; out Names: TRawUtf8DynArray;
  out Msg: RawUtf8): TRecordBindResult;
var
  table: RawUtf8;
begin
  Sql := '';
  Names := nil;
  Msg := '';
  { rc.Name, not Rec.RecordType: the lookup ignores case, so the table
    name should come from the declaration - tdtoartikel gives Artikel }
  table := TableFromRecordType(rc.Name);
  if table = '' then
  begin
    Msg := FormatUtf8('no table name left of [%]', [Rec.RecordType]);
    exit(rbNoTable);
  end;
  result := GenerateSql(rc, Kind, Rec, table, Sql, Names);
  case result of
    rbOk:
      ;
    rbNoKeyField:
      Msg := FormatUtf8('% has no field [%], so a generated update would ' +
        'have no where clause', [Rec.RecordType, KeyFieldOf(Rec)]);
    rbNoField:
      Msg := FormatUtf8('% has no field to name in a generated %',
        [Rec.RecordType, Rec.ActionKey]);
  else
    Msg := FormatUtf8('% cannot be generated from %',
      [Rec.ActionKey, Rec.RecordType]);
  end;
end;

{ the whole "no statement, so the key and the record type say everything"
  case, in one place: the editor shows what it produces, the server binds
  against it, and neither has its own copy of the conventions }
function GenerateFrom(const Rec: TSqlRec; rc: TRttiCustom;
  out Sql: RawUtf8; out Names: TRawUtf8DynArray;
  out Msg: RawUtf8): TRecordBindResult;
var
  kind: TRecordActionKind;
begin
  Sql := '';
  Names := nil;
  Msg := '';
  if not IsOrmActionKey(Rec.ActionKey) then
  begin
    Msg := FormatUtf8('% names a record type but does not start with %, ' +
      'so it is not marked as an ORM action and nothing is generated for it',
      [Rec.ActionKey, RECORDACTION_PREFIX]);
    exit(rbNotOrmAction);
  end;
  kind := RecordKindFromActionKey(Rec.ActionKey);
  if kind = raNone then
  begin
    Msg := FormatUtf8('% is marked as an ORM action but names no verb ' +
      'after %: Add/Insert, Update, Retrieve/Get or Delete',
      [Rec.ActionKey, RECORDACTION_PREFIX]);
    exit(rbNoWriteKind);
  end;
  result := GenerateKind(Rec, rc, kind, Sql, Names, Msg);
end;

function RetrieveSqlFor(const Rec: TSqlRec; out Sql: RawUtf8;
  out Msg: RawUtf8): TRecordBindResult;
var
  rc: TRttiCustom;
  names: TRawUtf8DynArray;
begin
  Sql := '';
  result := ResolveRecordType(Rec, rc, Msg);
  if result = rbOk then
    result := GenerateKind(Rec, rc, raRetrieve, Sql, names, Msg);
end;

{ put the ? back as the :Names they stand for, in order - the reverse of
  ExpandNamedParams, and the only place that direction is needed }
function WithNamedParams(const Sql: RawUtf8;
  const Names: TRawUtf8DynArray): RawUtf8;
var
  i, n: PtrInt;
  inString: boolean;
begin
  result := '';
  n := 0;
  inString := false;
  for i := 1 to length(Sql) do
  begin
    if Sql[i] = '''' then
      inString := not inString;
    if (Sql[i] = '?') and
       not inString and
       (n <= high(Names)) then
    begin
      result := result + ':' + Names[n];
      inc(n);
    end
    else
      result := result + Sql[i];
  end;
end;

function EditableSqlFor(const Rec: TSqlRec; out Sql: RawUtf8;
  out Msg: RawUtf8): TRecordBindResult;
var
  rc: TRttiCustom;
  names: TRawUtf8DynArray;
  one: TSqlRec;
  reading: boolean;
begin
  Sql := '';
  result := ResolveRecordType(Rec, rc, Msg);
  if result <> rbOk then
    exit;
  one := Rec;
  reading := RecordKindFromActionKey(Rec.ActionKey) in [raRetrieve, raList];
  if reading then
  begin
    { A draft to go on writing, so it stops where the writing starts. The
      column list and the table come out of the record type - that is the
      part nobody wants to type, and for a record of thirty fields it is the
      whole reason this button exists. The where clause is the part being
      written, so it is not put there: neither the key of a retrieve nor the
      filter of a list, which would only have to be deleted again.
      Asking for a list with no filter is exactly that select, so the kind is
      overridden rather than the text cut up afterwards.
      A delete keeps its where clause and that is not a symmetry worth
      fixing: "delete from Customer" as a starting point sits one keystroke
      away from an emptied table. }
    one.Filter := '';
    one.OrderBy := '';
    result := GenerateKind(one, rc, raList, Sql, names, Msg);
  end
  else
    result := GenerateFrom(one, rc, Sql, names, Msg);
  if result <> rbOk then
    exit;
  if names <> nil then
    { names is nil for the kinds whose ? belong to the caller; it is filled
      for the two whose ? come from the record, and those are the two a
      written statement has to spell with :Names }
    Sql := WithNamedParams(Sql, names);
  { a draft is continued, not terminated: a semicolon in the middle of what
    is still being written is only in the way }
  if (Sql <> '') and
     (Sql[length(Sql)] = ';') then
    SetLength(Sql, length(Sql) - 1);
end;

function GeneratedSqlFor(const Rec: TSqlRec; out Sql: RawUtf8;
  out Msg: RawUtf8): TRecordBindResult;
var
  rc: TRttiCustom;
  names: TRawUtf8DynArray;
begin
  Sql := '';
  result := ResolveRecordType(Rec, rc, Msg);
  if result = rbOk then
    result := GenerateFrom(Rec, rc, Sql, names, Msg);
end;

{ the SQLite column one field of this type is stored in.

  These are the affinities demo.sql writes by hand, and no others: a date is
  text because that is what the demo tables hold and what the driver reads a
  varDate back out of, and a currency is real for the same reason.

  No width anywhere, which is the one thing that makes this generator cheap:
  SQLite parses a width and then ignores it, so there is nothing a RawUtf8
  field would have to declare here that the record does not already say. The
  same function against SQL Server would need nvarchar(n) and a length, and
  the record type has no place to put one. }
function SqliteColumnType(pt: TRttiParserType; out ColType: RawUtf8): boolean;
begin
  result := true;
  case pt of
    ptBoolean,
    ptByte,
    ptWord,
    ptInteger,
    ptCardinal,
    ptInt64,
    ptQWord,
    ptTimeLog,
    ptUnixTime,
    ptUnixMSTime:
      ColType := 'integer';
    ptCurrency,
    ptDouble,
    ptSingle,
    ptExtended:
      ColType := 'real';
    ptDateTime,
    ptDateTimeMS,
    ptRawUtf8,
    ptString,
    ptSynUnicode,
    ptWideString,
    ptWinAnsi,
    ptRawJson,
    ptGuid:
      ColType := 'text';
    ptRawByteString:
      ColType := 'blob';
  else
    begin
      { refused rather than guessed: a column of the wrong affinity is a
        table that looks right and reads values back as something else }
      ColType := '';
      result := false;
    end;
  end;
end;

function CreateTableSqlFor(const Rec: TSqlRec; out Sql: RawUtf8;
  out Msg: RawUtf8): TRecordBindResult;
var
  rc: TRttiCustom;
  table, keyfield, coltype, cols: RawUtf8;
  haskey: boolean;
  i: PtrInt;
begin
  Sql := '';
  Msg := '';
  result := ResolveRecordType(Rec, rc, Msg);
  if result <> rbOk then
    exit;
  { rc.Name and not Rec.RecordType, exactly as GenerateKind does it: the
    lookup ignores case, so the table name has to come from the declaration }
  table := TableFromRecordType(rc.Name);
  if table = '' then
  begin
    Msg := FormatUtf8('no table name left of [%]', [Rec.RecordType]);
    exit(rbNoTable);
  end;
  if rc.Props.Count = 0 then
  begin
    { on FPC 3.2 this is what a type registered by TypeInfo() alone looks
      like - see the note at the top of WriteDtos }
    Msg := FormatUtf8('% has no field, so there is no table to describe',
      [rc.Name]);
    exit(rbNoField);
  end;
  keyfield := KeyFieldOf(Rec);
  haskey := false;
  for i := 0 to rc.Props.Count - 1 do
    if IdemPropNameU(rc.Props.List[i].Name, keyfield) then
      haskey := true;
  cols := '';
  if not haskey then
    { the record does not carry the key, but every generated retrieve and
      every generated delete of this template matches on it - so the table
      needs the column even though no field describes it. Integer, because
      that is the one a generated insert leaves to the database }
    cols := FormatUtf8('  % integer primary key autoincrement', [keyfield]);
  for i := 0 to rc.Props.Count - 1 do
  begin
    if not SqliteColumnType(rc.Props.List[i].Value.Parser, coltype) then
    begin
      Msg := FormatUtf8('% field [%] is a %, and there is no column for it',
        [rc.Name, rc.Props.List[i].Name,
         RawUtf8(mormot.core.rtti.ToText(rc.Props.List[i].Value.Parser)^)]);
      exit(rbUnknownField);
    end;
    if cols <> '' then
      cols := cols + ','#13#10;
    if not IdemPropNameU(rc.Props.List[i].Name, keyfield) then
      cols := cols + FormatUtf8('  % %', [rc.Props.List[i].Name, coltype])
    else if coltype = 'integer' then
      { SQLite makes a column the rowid alias only for this exact spelling -
        "bigint primary key" is an ordinary indexed column, and an insert
        that leaves the key out would then fail on a not-null rowid }
      cols := cols + FormatUtf8('  % integer primary key autoincrement',
        [rc.Props.List[i].Name])
    else
      { a key the caller supplies: no autoincrement, because there is
        nothing to count up }
      cols := cols + FormatUtf8('  % % primary key',
        [rc.Props.List[i].Name, coltype]);
  end;
  Sql := FormatUtf8('create table if not exists % ('#13#10'%);', [table, cols]);
  if haskey then
    Msg := FormatUtf8('% from %, % column(s)',
      [table, rc.Name, rc.Props.Count])
  else
    Msg := FormatUtf8('% from %, % column(s) plus [%], which the record ' +
      'does not declare and a generated retrieve and delete match on',
      [table, rc.Name, rc.Props.Count, keyfield]);
end;

function BindRecordJson(const Rec: TSqlRec; const Json: RawUtf8;
  out Expanded: RawUtf8; out Bounds: variant;
  out Msg: RawUtf8): TRecordBindResult;
var
  rc: TRttiCustom;
  prop: PRttiCustomProp;
  names: TRawUtf8DynArray;
  arr: TDocVariantData;
  vd: TVarData;
  buf: pointer;
  qm: boolean;
  i: PtrInt;
begin
  Expanded := '';
  VarClear(Bounds);
  Msg := '';
  { the mark is checked here too and not only in GenerateFrom: a template
    that carries a written statement with :Names never reaches that function,
    and a record travelling into it is just as much an ORM action }
  if not IsOrmActionKey(Rec.ActionKey) then
  begin
    Msg := FormatUtf8('% takes a record but does not start with %',
      [Rec.ActionKey, RECORDACTION_PREFIX]);
    exit(rbNotOrmAction);
  end;
  { and a retrieve or a delete is not one a record is sent into: their one
    value is the key, and it travels as an ordinary bound parameter }
  if RecordKindFromActionKey(Rec.ActionKey) in
       [raRetrieve, raList, raDelete] then
  begin
    Msg := FormatUtf8('% reads or deletes: send the key or the filter''s ' +
      'values as bound values, not a record', [Rec.ActionKey]);
    exit(rbNoWriteKind);
  end;
  result := ResolveRecordType(Rec, rc, Msg);
  if result <> rbOk then
    exit;
  if Rec.Sql = '' then
  begin
    { no statement, so the key and the record type say everything }
    result := GenerateFrom(Rec, rc, Expanded, names, Msg);
    if result <> rbOk then
      exit;
  end
  else
  begin
    if not ExpandNamedParams(Rec.Sql, Expanded, names, qm) then
    begin
      Msg := 'no :Placeholder in the statement';
      exit(rbNoPlaceholder);
    end;
    if qm then
    begin
      Msg := 'the statement mixes ? with :Placeholder';
      exit(rbQuestionMark);
    end;
  end;
  { AllocMem, not GetMem: the managed fields of the record have to start out
    nil or RecordLoadJson would release whatever the heap happened to hold }
  buf := AllocMem(rc.Size);
  try
    if not RecordLoadJson(buf^, Json, rc.Info) then
    begin
      Msg := FormatUtf8('% does not parse as %', [Json, Rec.RecordType]);
      exit(rbBadJson);
    end;
    arr.InitArray([], JSON_FAST_FLOAT);
    for i := 0 to high(names) do
    begin
      prop := rc.Props.Find(names[i]);
      if prop = nil then
      begin
        Msg := FormatUtf8('% has no field [%]', [Rec.RecordType, names[i]]);
        exit(rbUnknownField);
      end;
      { here the types come back: varDate for a TDateTime, varCurrency for a
        currency - and the driver binds each of them as itself }
      prop^.GetValueVariant(buf, vd, @JSON_[mFastFloat]);
      arr.AddItem(variant(vd));
      VarClearProc(vd);
    end;
    Bounds := variant(arr);
    result := rbOk;
  finally
    rc.ValueFinalize(buf); // every RawUtf8 in the record, or it leaks
    FreeMem(buf);
  end;
end;

initialization
  { thread safe on its own, which is what a server needs: two requests may
    reach an unregistered type at the same moment }
  FromText := TSynDictionary.Create(
    TypeInfo(TRawUtf8DynArray), TypeInfo(TRawUtf8DynArray), {caseinsens=}true);

finalization
  FromText.Free;

end.
