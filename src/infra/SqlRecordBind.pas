unit SqlRecordBind;

{$I mormot.defines.inc}

{ One record -> the bound values of one registered statement.

  The incoming counterpart of ParseDynArray. There the caller names the type
  it wants and RTTI turns JSON into an array of records; here the template
  names the type it expects and RTTI turns one record back into typed values.
  Written once for every record there will ever be.

  A record template comes either way round.

  WITHOUT a statement everything is generated, from the record and the action
  key - OrmTDtoCustomerUpdate + TDtoCustomer gives
    update Customer set Name = ?, City = ? where ID = ?
  on conventions that are each one constant and one function: the key is
  marked Orm, spells the record type and then names a verb (SqlTemplateTypes,
  because the domain layer reads the same mark and must not see this unit),
  the table is the
  record type without its TDto prefix and Row suffix, the key column is what
  KeyField says and ID when it says nothing.

  Four verbs, and only two of them take a record. An insert and an update
  send one; a retrieve sends the values of its where clause and a delete the
  key alone, because the columns to read are the record type's business and
  the server knows the type from the template - which is what an ORM does
  when it sends a list of field names rather than a record. So those two
  carry no record here at all: this unit only composes their statement, and
  the ordinary bound-value path runs it.

  The record type is either compiled in and registered - see WriteDtos - or
  declared as text in the RecordDecl column and registered from there on
  first use. The second way is what keeps a new record from being a rebuild;
  the first always wins, see ResolveRecordType.

  Nothing in that text comes from the caller - only the record's own field
  names and its type name - and the values are still bound, so this stays as
  far from "send me any SQL" as the rest.

  There is no "with a statement". An Orm key never carries one: another
  table name is the TableName column, and what is left over - a composite
  key, an extra condition, a join - is an ordinary template with ? and a
  value list, not a record call that pretends to be one.

  An insert hands its row back in the same statement where the database can
  say so ("returning", SQL Server's "output inserted."), which is how the
  caller learns the key the database gave it and any default it filled.

  The record is what restores the types: JSON has four, a Customer row has an
  integer ID and an Invoice a TDateTime and a currency.

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
    rbOwnStatement,
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

/// the select that would fetch the row this template is about
// - the template's OWN verb and where clause are not consulted: an update is
// asked for the row it is about to overwrite, and that is a select on the
// same record type and the same key column. Which is why this is here and not a second rule
// in the editor - it is the retrieve branch, asked for by name
function RetrieveSqlFor(const Rec: TSqlRec; out Sql: RawUtf8;
  out Msg: RawUtf8): TRecordBindResult;


type
  /// whose spelling a generated create table is written in
  // - the connected profile only PRESELECTS this: the statement is an
  // artefact to hand on, so which database it is meant for is something the
  // person knows and the open connection does not
  // - the list is meant to grow, and one more entry in DDL_DIALECTS is what
  // a new one costs
  TDdlDialect = (
    ddSQLite,
    ddMSSQL,
    ddPostgreSQL,
    ddMySQL);

  /// the handful of column shapes a record field is stored in
  // - fewer than there are field types on purpose: what a create table has
  // to know about a field is how wide it is and whether it is a number, not
  // which Pascal type it came from
  TDdlColumn = (
    dcInteger,
    dcBigInt,
    dcFloat,
    dcMoney,
    dcDate,
    dcText,
    dcBlob);

  /// how an insert hands back the row it wrote, in the same statement
  // - irNone where the database has no such clause: the insert still runs,
  // and the caller gets its status and no row
  TInsertReturning = (
    irNone,
    irReturning,
    irOutput);

  /// everything two dialects spell differently, and nothing else
  TDdlDialectDef = record
    /// what the drop-down shows
    Name: RawUtf8;
    /// the column type per shape
    Column: array[TDdlColumn] of RawUtf8;
    /// the key the database fills itself - % is the column name
    // - this is the one mORMot's own SqlCreate does NOT write: its ORM hands
    // out the key itself, and a generated insert here leaves it to the
    // database, so the column has to count up on its own
    AutoKey: RawUtf8;
    /// put between "create table" and the name, where the guard goes there
    IfNotExists: RawUtf8;
    /// put in FRONT of the whole statement, where it does not - % is the
    // table name
    Guard: RawUtf8;
    /// how a generated insert returns its row - "insert ... returning" or
    // SQL Server's "output inserted.", read in the same statement so no
    // other writer's row can be mistaken for this one
    Returning: TInsertReturning;
  end;

const
  /// one row per dialect, and adding a database means adding a row
  DDL_DIALECTS: array[TDdlDialect] of TDdlDialectDef = (
    (Name: 'SQLite';
     Column: (
       'integer', 'integer', 'real', 'real', 'text', 'text', 'blob');
     AutoKey: '% integer primary key autoincrement';
     IfNotExists: 'if not exists ';
     Guard: '';
     { since 3.35; the static library mORMot links is newer than that }
     Returning: irReturning),
    (Name: 'SQL Server';
     Column: (
       'int', 'bigint', 'float', 'money', 'datetime',
       { nvarchar(max) and not nvarchar(n): a record type states no width,
         and a number invented here would be the only thing in the output
         that nothing derived. This is also what mORMot's own DB_FIELDS puts
         in the slot for a text column that was never given one }
       'nvarchar(max)', 'varbinary(max)');
     AutoKey: '% int identity(1,1) primary key';
     { SQL Server has no "if not exists" on create table, so the guard is a
       statement of its own in front of it }
     IfNotExists: '';
     Guard: 'if not exists (select * from sys.objects' + #13#10 +
            '  where object_id = object_id(''%'') and type = ''U'')'#13#10;
     Returning: irOutput),
    (Name: 'PostgreSQL';
     Column: (
       'integer', 'bigint', 'double precision', 'numeric(19,4)', 'timestamp',
       { unbounded AND indexable, so unlike SQL Server there is nothing to
         trade off here }
       'text', 'bytea');
     AutoKey: '% serial primary key';
     IfNotExists: 'if not exists ';
     Guard: '';
     Returning: irReturning),
    { MariaDB is a dialect of its own to mORMot, but not to this table: the
      create table it wants is the same one, down to auto_increment }
    (Name: 'MySQL / MariaDB';
     Column: (
       'int', 'bigint', 'double', 'decimal(19,4)', 'datetime',
       'mediumtext', 'mediumblob');
     AutoKey: '% int auto_increment primary key';
     IfNotExists: 'if not exists ';
     Guard: '';
     { MariaDB has "returning" since 10.5, MySQL has none at all - so the one
       both understand is none }
     Returning: irNone));

  /// a key the caller supplies rather than the database - % name, % type
  // - the same three words everywhere, so it is not in the table above
  DDL_GIVENKEY = '% % primary key';


/// the table this record type would need, in Dialect's spelling, as a
// statement to read
// - the cheap half of "create the table": this generates, it never executes.
// What comes back is meant to be looked at, copied and run by hand - which
// is the whole difference between a sample that creates nothing and one that
// creates something behind your back
// - it needs no connection, which is the point of taking the dialect as a
// parameter: the statement for a database nobody here is logged into is
// exactly the one somebody has to be handed
// - for ddSQLite what comes out is the schema demo.sql already writes by
// hand, down to the affinities
// - the key column is there whether or not the record carries it: a
// generated retrieve and a generated delete both match on it, so a table
// without it would break two of the four verbs. When the record does not
// declare it, it is put in front and Msg says so
// - nullability, defaults, indexes and foreign keys are NOT generated. A
// record type states none of them, and inventing them here would be this
// code deciding something the declaration never said. Nor is a text width:
// every dialect gets its unbounded text column, so no number in what comes
// out was invented here
// - the key comes out as a counting integer, which is the only key mORMot's
// own ORM knows: its external tables get an Int64 ID and nothing else
function CreateTableSqlFor(const Rec: TSqlRec; Dialect: TDdlDialect;
  out Sql: RawUtf8; out Msg: RawUtf8): TRecordBindResult;

/// 'TDtoCustomer' -> 'Customer', and 'TDtoArtikel' -> 'Artikel'
// - both affixes are optional and matched case insensitively, as is the type
// name itself when the registry is asked for it
// - returns '' when nothing is left after the affixes are stripped
function TableFromRecordType(const RecordType: RawUtf8): RawUtf8;

/// the table a generated statement of this template names: its TableName
// column, or what TableFromRecordType makes of the resolved type
function TableOf(const Rec: TSqlRec; rc: TRttiCustom): RawUtf8;

/// load Json into the record the template names, and bind it
// - Expanded is the generated statement; Bounds holds the values in the
// order its ? appear
// - Returning says how the connected database hands back an inserted row;
// for an insert it is written into Expanded, and ReturnsRow says whether it
// was - an update, and an insert on a database without the clause, return
// none
// - Msg goes to the log, never to a client
function BindRecordJson(const Rec: TSqlRec; const Json: RawUtf8;
  Returning: TInsertReturning; out Expanded: RawUtf8; out Bounds: variant;
  out ReturnsRow: boolean; out Msg: RawUtf8): TRecordBindResult;

implementation

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

function TableOf(const Rec: TSqlRec; rc: TRttiCustom): RawUtf8;
begin
  result := Rec.TableName;
  if result = '' then
    { rc.Name, not Rec.RecordType: the lookup ignores case, so the table
      name should come from the declaration - tdtoartikel gives Artikel }
    result := TableFromRecordType(rc.Name);
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
  if Kind = raRetrieve then
  begin
    { every field, the key included: what comes back has to load into the
      same record type on the other side, so the column list is the record
      and not a subset of it. One row or many is the where clause's business,
      not the shape's - both come back as an array }
    all := '';
    for i := 0 to rc.Props.Count - 1 do
    begin
      if all <> '' then
        all := all + ', ';
      all := all + rc.Props.List[i].Name;
    end;
    if all = '' then
      exit(rbNoField);
    Names := nil; // the bound values are the caller's, not fields
    { The template's own where clause, parenthesised, so that whatever it
      wrote there cannot change how a condition appended after it binds.
      Today that is the caller scope the domain layer appends; an "or" in an
      unparenthesised filter would quietly let rows past it. }
    where := '';
    if Rec.Filter <> '' then
      where := FormatUtf8(' where (%)', [Rec.Filter]);
    order := '';
    if Rec.OrderBy <> '' then
      order := FormatUtf8(' order by %', [Rec.OrderBy]);
    Sql := FormatUtf8('select % from %%%;', [all, Table, where, order]);
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
  table := TableOf(Rec, rc);
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
  kind := RecordKindOf(Rec);
  if kind = raNone then
  begin
    Msg := OrmKeyProblem(Rec);
    exit(rbNoWriteKind);
  end;
  result := GenerateKind(Rec, rc, kind, Sql, Names, Msg);
end;

function RetrieveSqlFor(const Rec: TSqlRec; out Sql: RawUtf8;
  out Msg: RawUtf8): TRecordBindResult;
var
  rc: TRttiCustom;
  names: TRawUtf8DynArray;
  one: TSqlRec;
begin
  Sql := '';
  result := ResolveRecordType(Rec, rc, Msg);
  if result <> rbOk then
    exit;
  { one row by its key, whatever the template's own where clause says: this
    is the record an update is about to change, not a query a caller asked }
  one := Rec;
  one.Filter := FormatUtf8('% = ?', [KeyFieldOf(Rec)]);
  one.OrderBy := '';
  result := GenerateKind(one, rc, raRetrieve, Sql, names, Msg);
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

{ the column shape one field of this type is stored in.

  Which database is not asked here: a currency is money-shaped everywhere,
  and what that is called is the dialect table's business. That split is what
  makes a new database a row in DDL_DIALECTS rather than a second copy of
  this case statement. }
function DdlColumnOf(pt: TRttiParserType; out Col: TDdlColumn): boolean;
begin
  result := true;
  case pt of
    ptBoolean,
    ptByte,
    ptWord,
    ptInteger,
    ptCardinal:
      Col := dcInteger;
    ptInt64,
    ptQWord,
    ptTimeLog,
    ptUnixTime,
    ptUnixMSTime:
      Col := dcBigInt;
    ptDouble,
    ptSingle,
    ptExtended:
      Col := dcFloat;
    ptCurrency:
      Col := dcMoney;
    ptDateTime,
    ptDateTimeMS:
      Col := dcDate;
    ptRawUtf8,
    ptString,
    ptSynUnicode,
    ptWideString,
    ptWinAnsi,
    ptRawJson,
    ptGuid:
      Col := dcText;
    ptRawByteString:
      Col := dcBlob;
  else
    begin
      { refused rather than guessed: a column of the wrong shape is a table
        that looks right and reads values back as something else }
      Col := dcText;
      result := false;
    end;
  end;
end;

function CreateTableSqlFor(const Rec: TSqlRec; Dialect: TDdlDialect;
  out Sql: RawUtf8; out Msg: RawUtf8): TRecordBindResult;
var
  rc: TRttiCustom;
  table, keyfield, cols, name: RawUtf8;
  col: TDdlColumn;
  haskey: boolean;
  i: PtrInt;
begin
  Sql := '';
  Msg := '';
  result := ResolveRecordType(Rec, rc, Msg);
  if result <> rbOk then
    exit;
  { the same table GenerateKind names, so the create table and the
    statements that will run against it cannot disagree about it }
  table := TableOf(Rec, rc);
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
      needs the column even though no field describes it. One the database
      fills, because that is what a generated insert leaves out }
    cols := '  ' + FormatUtf8(DDL_DIALECTS[Dialect].AutoKey, [keyfield]);
  for i := 0 to rc.Props.Count - 1 do
  begin
    name := rc.Props.List[i].Name;
    if not DdlColumnOf(rc.Props.List[i].Value.Parser, col) then
    begin
      Msg := FormatUtf8('% field [%] is a %, and there is no column for it',
        [rc.Name, name,
         RawUtf8(mormot.core.rtti.ToText(rc.Props.List[i].Value.Parser)^)]);
      exit(rbUnknownField);
    end;
    if cols <> '' then
      cols := cols + ','#13#10;
    if not IdemPropNameU(name, keyfield) then
      cols := cols + FormatUtf8('  % %', [name, DDL_DIALECTS[Dialect].Column[col]])
    else if col in [dcInteger, dcBigInt] then
      cols := cols + '  ' + FormatUtf8(DDL_DIALECTS[Dialect].AutoKey, [name])
    else
      { a key the caller supplies: nothing counts up, and the column keeps
        the very type the field maps to - one column per field, here as
        everywhere else }
      cols := cols + '  ' + FormatUtf8(DDL_GIVENKEY,
        [name, DDL_DIALECTS[Dialect].Column[col]]);
  end;
  { plain concatenation and not one big FormatUtf8: the guard carries its own
    % for the table name, and two format strings feeding each other is the
    kind of thing that works until a dialect puts a per cent sign in one }
  Sql := FormatUtf8(DDL_DIALECTS[Dialect].Guard, [table]) +
         'create table ' + DDL_DIALECTS[Dialect].IfNotExists + table +
         ' ('#13#10 + cols + ');';
  if haskey then
    Msg := FormatUtf8('% from %, % column(s), % spelling',
      [table, rc.Name, rc.Props.Count, DDL_DIALECTS[Dialect].Name])
  else
    Msg := FormatUtf8('% from %, % column(s) in % spelling, plus [%], which ' +
      'the record does not declare and a generated retrieve and delete ' +
      'match on', [table, rc.Name, rc.Props.Count,
      DDL_DIALECTS[Dialect].Name, keyfield]);
end;

{ the statement an insert becomes when it has to hand its row back: the
  columns of the record, read from the row the database just wrote. Text
  this unit generated a line earlier, so its shape is known - ") values ("
  occurs once, and nothing a caller sends is in it }
function WithReturning(const Sql: RawUtf8; rc: TRttiCustom;
  Returning: TInsertReturning): RawUtf8;
var
  cols, outs: RawUtf8;
  i, p: PtrInt;
begin
  result := Sql;
  cols := '';
  outs := '';
  for i := 0 to rc.Props.Count - 1 do
  begin
    if cols <> '' then
    begin
      cols := cols + ', ';
      outs := outs + ', ';
    end;
    cols := cols + rc.Props.List[i].Name;
    outs := outs + 'inserted.' + rc.Props.List[i].Name;
  end;
  if (result <> '') and
     (result[length(result)] = ';') then
    SetLength(result, length(result) - 1);
  case Returning of
    irReturning:
      result := FormatUtf8('% returning %;', [result, cols]);
    irOutput:
      begin
        p := PosEx(') values (', result);
        if p > 0 then
          insert(' output ' + outs, result, p + 1);
        result := result + ';';
      end;
  else
    result := result + ';';
  end;
end;

function BindRecordJson(const Rec: TSqlRec; const Json: RawUtf8;
  Returning: TInsertReturning; out Expanded: RawUtf8; out Bounds: variant;
  out ReturnsRow: boolean; out Msg: RawUtf8): TRecordBindResult;
var
  rc: TRttiCustom;
  prop: PRttiCustomProp;
  names: TRawUtf8DynArray;
  arr: TDocVariantData;
  vd: TVarData;
  buf: pointer;
  i: PtrInt;
begin
  Expanded := '';
  VarClear(Bounds);
  ReturnsRow := false;
  Msg := '';
  if not IsOrmActionKey(Rec.ActionKey) then
  begin
    Msg := FormatUtf8('% takes a record but does not start with %',
      [Rec.ActionKey, RECORDACTION_PREFIX]);
    exit(rbNotOrmAction);
  end;
  { and a retrieve or a delete is not one a record is sent into: their
    values are the where clause's or the key, and they travel as ordinary
    bound parameters }
  if RecordKindOf(Rec) in [raRetrieve, raDelete] then
  begin
    Msg := FormatUtf8('% reads or deletes: send the key or the filter''s ' +
      'values as bound values, not a record', [Rec.ActionKey]);
    exit(rbNoWriteKind);
  end;
  { An Orm key is made from its record type and nothing else. A statement of
    its own was once the way out for what the convention could not say; the
    table is now a column, and what is left - a join, a composite key, an
    extra condition - is an ordinary template with ? and a value list }
  if Rec.Sql <> '' then
  begin
    Msg := FormatUtf8('% is generated from % and carries no statement of ' +
      'its own - leave Sql empty, name the table in TableName, or use a key ' +
      'without Orm', [Rec.ActionKey, Rec.RecordType]);
    exit(rbOwnStatement);
  end;
  result := ResolveRecordType(Rec, rc, Msg);
  if result <> rbOk then
    exit;
  result := GenerateFrom(Rec, rc, Expanded, names, Msg);
  if result <> rbOk then
    exit;
  if (RecordKindOf(Rec) = raInsert) and
     (Returning <> irNone) then
  begin
    Expanded := WithReturning(Expanded, rc, Returning);
    ReturnsRow := true;
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
