unit InfraSqlImplementation;

{$I mormot.defines.inc}

{ The infrastructure layer: the only place SQL runs.

  It binds and executes, and that is all. Resolving a key and deciding whether
  the caller may use it happens one layer up - which is why these methods take
  a TSqlRec and not a key.

  The flip side, worth keeping in mind when copying this: the layer no longer
  enforces that only registered statements run, it executes what it is handed.
  What protects it is that a TSqlRec is only ever issued by the registry, and
  that ISqlTemplateExec goes to nobody but TAppSqlTool. Do not widen these
  methods to take a plain RawUtf8 statement.

  Note what is NOT here: no DTO, no field by field copying, no method per
  query. The shape of the data is decided by the caller, in the client.

  The connection is a TSqlDBConnectionProperties, so nothing here is tied to
  SQLite - pointing it at TOdbcConnectionProperties talks to SQL Server. }

interface

uses
  SysUtils,
  mormot.core.base,
  mormot.core.text,
  mormot.core.log,
  mormot.core.variants,
  mormot.db.sql,
  SqlStatus,
  SqlParamTypes,
  SqlRecordBind,
  SqlTemplateTypes, // the template type - never the registry that issues it
  InfraSqlServices;

type

  { TSqlTemplateExec }

  TSqlTemplateExec = class(TInterfacedObject, ISqlTemplateExec)
  private
    fProps: TSqlDBConnectionProperties;
    function Prepare(const Rec: TSqlRec; const Bounds: variant;
      ExpectResults: boolean; out Stmt: ISqlDBStatement): TSqlStatus;
    /// convert the caller's values to what the template declares
    function Coerce(const Rec: TSqlRec; const Bounds: variant;
      out Coerced: variant): TSqlStatus;
    /// give a retrieve or a delete the statement it does not carry
    // - a no-op for everything else, which is why the two callers can ask
    // unconditionally
    function GenerateIfOrm(var Rec: TSqlRec;
      Wanted: TRecordActionKinds; const Called: RawUtf8): TSqlStatus;
  public
    constructor Create(aProps: TSqlDBConnectionProperties); reintroduce;
    /// run a resolved select and return its rows as a JSON object array
    function SelectJson(const Rec: TSqlRec; const Bounds: variant;
      var Json: RawUtf8): TSqlStatus;
    /// run a resolved insert, update or delete from a list of values
    function Execute(const Rec: TSqlRec;
      const Bounds: variant): TSqlStatus;
    /// run a resolved insert or update from one serialised record
    function ExecuteRecord(const Rec: TSqlRec;
      const Json: RawUtf8): TSqlStatus;
  end;

/// what went wrong in this thread's last call, in the driver's own words
// - every failure is a status, and a status has no room for a sentence. The
// server does not need one: it logs. The editor does - a statement being
// drafted is wrong most of the time, and "sqlFailed" alone sends its author
// guessing. So the reason is left here on the way out
// - a threadvar rather than a field: one TSqlTemplateExec serves every
// request of the server at once, and a shared string would be a race
// - empty when the last call succeeded, or when nothing has run yet
function LastSqlError: RawUtf8;

implementation

threadvar
  LastError: RawUtf8;

function LastSqlError: RawUtf8;
begin
  result := LastError;
end;

procedure SetLastError(const Fmt: RawUtf8; const Args: array of const);
begin
  FormatUtf8(Fmt, Args, LastError);
end;

{ TSqlTemplateExec }

constructor TSqlTemplateExec.Create(aProps: TSqlDBConnectionProperties);
begin
  inherited Create;
  if aProps = nil then
    // a nil connection is a wiring mistake, not an outcome: still an exception
    raise ESqlTemplate.Create('TSqlTemplateExec.Create(nil)');
  fProps := aProps;
end;

{ JSON has four types; what the driver binds is decided by the variant's. The
  declaration closes that gap - and a template that declares nothing hands its
  values on untouched. }
function TSqlTemplateExec.Coerce(const Rec: TSqlRec; const Bounds: variant;
  out Coerced: variant): TSqlStatus;
var
  msg: RawUtf8;
begin
  if CoerceBounds(Rec.ParamTypes, Bounds, Coerced, msg) then
    result := sqlOk
  else
  begin
    { the reason names a parameter and is the caller's, so it earns its own
      status rather than sqlFailed }
    SynDBLog.Add.Log(sllWarning, 'Coerce(%): %', [Rec.ActionKey, msg]);
    SetLastError('%', [msg]);
    result := sqlBadParams;
  end;
end;

function TSqlTemplateExec.Prepare(const Rec: TSqlRec; const Bounds: variant;
  ExpectResults: boolean; out Stmt: ISqlDBStatement): TSqlStatus;
begin
  Stmt := nil;
  if Rec.Sql = '' then
    exit(sqlFailed); // the registry never stores an empty statement
  try
    { raiseonerror=false: a statement that does not prepare comes back as a
      status, and the reason goes to the log }
    Stmt := fProps.NewThreadSafeStatementPrepared(
      Rec.Sql, ExpectResults, {raiseonerror=}false);
    if Stmt = nil then
    begin
      { mORMot logged what the driver said, and left it on the connection }
      SynDBLog.Add.Log(sllError, 'Prepare(%) refused: %',
        [Rec.ActionKey, Rec.Sql]);
      SetLastError('%', [fProps.ThreadSafeConnection.LastErrorMessage]);
      exit(sqlFailed);
    end;
    Stmt.Bind(_Safe(Bounds)^.ToArrayOfConst);
  except
    on E: Exception do
    begin
      SynDBLog.Add.Log(sllError, 'Prepare(%) failed: % %',
        [Rec.ActionKey, E.ClassType, E.Message]);
      SetLastError('% %', [E.ClassType, E.Message]);
      Stmt := nil;
      exit(sqlFailed);
    end;
  end;
  result := sqlOk;
end;

{ The two directions a record type can be used WITHOUT a record.

  A retrieve and a delete carry no statement, and unlike an insert or an
  update they carry no values from a record either: their one value is the
  key, and it arrives the way every other bound value does. So the only thing
  the record type contributes is the statement - the column list for a select,
  the table name for a delete - and once that exists, everything below this
  runs on an ordinary resolved template with a ? in it.

  Which is why neither the domain layer nor the service contract learned a
  new call for these two: GetJsonFromAction and WriteDataForAction already
  say everything they need. }
function TSqlTemplateExec.GenerateIfOrm(var Rec: TSqlRec;
  Wanted: TRecordActionKinds; const Called: RawUtf8): TSqlStatus;
var
  sql, msg: RawUtf8;
begin
  result := sqlOk;
  if (Rec.Sql <> '') or
     (Rec.RecordType = '') or
     not (RecordKindFromActionKey(Rec.ActionKey) in Wanted) then
    exit; // not one of these: leave the template exactly as it was
  if GeneratedSqlFor(Rec, sql, msg) <> rbOk then
  begin
    { a record type nobody registered, or a declaration that does not parse:
      the template is at fault, not the caller }
    SynDBLog.Add.Log(sllError, '%(%): %', [Called, Rec.ActionKey, msg]);
    SetLastError('%', [msg]);
    exit(sqlFailed);
  end;
  Rec.Sql := sql;
end;

function TSqlTemplateExec.SelectJson(const Rec: TSqlRec;
  const Bounds: variant; var Json: RawUtf8): TSqlStatus;
var
  one: TSqlRec;
  stmt: ISqlDBStatement;
  bound: variant;
  rows: PtrInt;
begin
  Json := '[]';
  LastError := ''; // whatever went wrong last time is not this call's reason
  one := Rec;
  { the two kinds that read: one row by its key, or many by the filter the
    template carries - both are a select, and both are generated here }
  result := GenerateIfOrm(one, [raRetrieve, raList], 'SelectJson');
  if result <> sqlOk then
    exit;
  result := Coerce(one, Bounds, bound);
  if result <> sqlOk then
    exit;
  result := Prepare(one, bound, {expectresults=}true, stmt);
  if result <> sqlOk then
    exit;
  rows := 0;
  try
    stmt.ExecutePrepared;
    Json := stmt.FetchAllAsJson({expand=}true, @rows);
  except
    on E: Exception do
    begin
      SynDBLog.Add.Log(sllError, 'SelectJson(%) failed: % %',
        [Rec.ActionKey, E.ClassType, E.Message]);
      SetLastError('% %', [E.ClassType, E.Message]);
      Json := '[]';
      exit(sqlFailed);
    end;
  end;
  { with no row FetchAllAsJson falls back to an object rather than an array,
    which would make DynArrayLoadJson fail in the client }
  if rows <= 0 then
  begin
    Json := '[]';
    result := sqlNoRows;
  end;
end;

function TSqlTemplateExec.Execute(const Rec: TSqlRec;
  const Bounds: variant): TSqlStatus;
var
  one: TSqlRec;
  stmt: ISqlDBStatement;
  bound: variant;
begin
  LastError := '';
  one := Rec;
  result := GenerateIfOrm(one, [raDelete], 'Execute');
  if result <> sqlOk then
    exit;
  result := Coerce(one, Bounds, bound);
  if result <> sqlOk then
    exit;
  result := Prepare(one, bound, {expectresults=}false, stmt);
  if result <> sqlOk then
    exit;
  try
    stmt.ExecutePrepared;
  except
    on E: Exception do
    begin
      SynDBLog.Add.Log(sllError, 'Execute(%) failed: % %',
        [Rec.ActionKey, E.ClassType, E.Message]);
      SetLastError('% %', [E.ClassType, E.Message]);
      exit(sqlFailed);
    end;
  end;
  if stmt.UpdateCount <= 0 then
    result := sqlNothingWritten;
end;

{ The record direction. No branch per type, and nothing to add when the next
  record arrives: the statement is generated from the record type and the
  action key, or its :Name placeholders are filled from the record's fields.

  What is executed is a copy of the resolved record carrying that statement.
  It is still a TSqlRec issued by the registry, so the property that only
  registered templates reach the driver holds. }
function TSqlTemplateExec.ExecuteRecord(const Rec: TSqlRec;
  const Json: RawUtf8): TSqlStatus;
var
  one: TSqlRec;
  bound: variant;
  expanded, msg: RawUtf8;
begin
  LastError := '';
  case BindRecordJson(Rec, Json, expanded, bound, msg) of
    rbOk:
      ;
    rbBadJson,
    rbNoRecordType:
      begin
        { the caller's doing: bad JSON, or a key that wants a value list }
        SynDBLog.Add.Log(sllWarning,
          'ExecuteRecord(%): %', [Rec.ActionKey, msg]);
        SetLastError('%', [msg]);
        exit(sqlBadParams);
      end;
  else
    begin
      { a type nobody registered, or placeholders that miss its fields:
        nothing the caller can do about it }
      SynDBLog.Add.Log(sllError, 'ExecuteRecord(%): %', [Rec.ActionKey, msg]);
      SetLastError('%', [msg]);
      exit(sqlFailed);
    end;
  end;
  one := Rec;
  one.Sql := expanded;
  { the values came out of a typed record, so there is nothing to coerce }
  one.ParamTypes := '';
  result := Execute(one, bound);
end;

end.
