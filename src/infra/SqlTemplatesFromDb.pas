unit SqlTemplatesFromDb;

{$I mormot.defines.inc}

{ Where the templates come from - templates.sqlite, and nothing else.

  There is no second source. A statement lives in the table, is edited in the
  editor, and reaches a running server without a rebuild; nothing about a
  query is compiled into this binary. The domain layer owns the registry and
  asks an ISqlTemplateSource to fill it, so nothing here knows that a registry
  exists.

  Two deliberate decisions:

  - the table is read at startup, on an explicit reload, and on an unknown
    action key IF the file has changed since - which is what Changed() below
    answers, from a stat call. A lookup per call would put a query in front of
    every request; a reload per miss would put one in front of every typo.
  - a missing templates.sqlite is rebuilt from templates.sql next to it. That
    file is what version control holds a readable diff of, the editor rewrites
    it on every save, and it carries its own create table - so a fresh clone
    starts even if the binary database never travelled. }

interface

uses
  SysUtils,
  mormot.core.base,
  mormot.core.text,
  mormot.core.log,
  mormot.db.sql,
  mormot.db.sql.sqlite3,
  mormot.db.raw.sqlite3,
  mormot.core.os,
  mormot.core.unicode,
  SqlTemplateTypes,
  InfraSqlServices;

const
  TEMPLATE_DB_FILE = 'templates.sqlite';

  { Every column is a field of TSqlRec, and nothing above the registry has to
    change to add one - the claim this table is here to make. Still open on
    the same terms: the recorded shape of the result. }
  TEMPLATE_TABLE_SQL =
    'create table if not exists SqlTemplate (' +
    '  ActionKey   text not null primary key,' +
    '  Sql         text not null,' +
    '  ParamTypes  text,' +
    '  Rules       text,' +
    '  TestBounds  text,' +
    '  RecordType  text,' +
    '  RecordDecl  text,' +
    '  KeyField    text,' +
    '  CallerScope text,' +
    '  Filter      text,' +
    '  OrderBy     text,' +
    '  ReadGroups  integer,' +
    '  WriteGroups integer);';

  { added later than the first two, so an older file is brought forward
    rather than rejected }
  TEMPLATE_ADDED_COLUMNS: array[0..10] of RawUtf8 = (
    'ParamTypes text',
    'ReadGroups integer',
    'WriteGroups integer',
    'RecordType text',
    'RecordDecl text',
    'KeyField text',
    'CallerScope text',
    'Filter text',
    'OrderBy text',
    'Rules text',
    'TestBounds text');

/// add any column this version knows and the file does not
// - an older file keeps its rows and gains the new columns as NULL, which
// every reader treats as "not declared"
procedure MigrateTemplateDb(Props: TSqlDBConnectionProperties);

type
  { TDbTemplateSource

    templates.sqlite as a source.

    Changed() compares the file's timestamp AND its size against the last
    successful load. Both, because a filesystem timestamp has one second of
    resolution: a save and a call inside the same second would otherwise look
    like no change, and the size almost always moves when a statement does. }
  TDbTemplateSource = class(TInterfacedObject, ISqlTemplateSource)
  private
    fFileName: TFileName;
    fStampTime: TUnixTime;
    fStampSize: Int64;
  public
    constructor Create(const aFileName: TFileName); reintroduce;
    function Changed: boolean;
    function Load(out Recs: TSqlRecArray): boolean;
    function SourceName: RawUtf8;
    property FileName: TFileName
      read fFileName;
  end;

/// rebuild a missing template database from the .sql export next to it
// - does nothing when the database is there, which is the normal case
// - false only when neither file exists: then there is nothing to serve, and
// the startup code says so rather than starting empty
function SeedTemplateDb(const FileName: TFileName): boolean;

/// read every template from the table
// - false when the file is missing or unreadable; the reason goes to the log
function ReadTemplates(const FileName: TFileName;
  out Recs: TSqlRecArray): boolean;

implementation

procedure MigrateTemplateDb(Props: TSqlDBConnectionProperties);
var
  rows: ISqlDBRows;
  have: TRawUtf8DynArray;
  i: PtrInt;
  name: RawUtf8;
begin
  rows := Props.Execute('pragma table_info(SqlTemplate);', []);
  if rows = nil then
    exit;
  while rows.Step do
    AddRawUtf8(have, rows.ColumnUtf8(1)); // 1 = column name
  rows := nil;
  for i := 0 to high(TEMPLATE_ADDED_COLUMNS) do
  begin
    name := GetFirstCsvItem(TEMPLATE_ADDED_COLUMNS[i], ' ');
    if FindRawUtf8(have, name, {casesensitive=}false) < 0 then
      Props.ExecuteNoResult('alter table SqlTemplate add column ' +
        TEMPLATE_ADDED_COLUMNS[i] + ';', []);
  end;
end;

function SeedTemplateDb(const FileName: TFileName): boolean;
var
  db: TSqlDatabase;
  script: TFileName;
  sql: RawUtf8;
begin
  result := FileExists(FileName);
  if result then
    exit; // the database of record is there - never touch it
  script := ChangeFileExt(FileName, '.sql');
  sql := StringFromFile(script);
  if sql = '' then
  begin
    SynDBLog.Add.Log(sllError,
      'SeedTemplateDb: neither % nor % - no templates to serve',
      [FileName, script]);
    exit;
  end;
  { the export carries its own create table and its own delete, so running the
    whole script IS the restore - the same bytes sqlite3 would swallow }
  db := TSqlDatabase.Create(FileName, '');
  try
    db.ExecuteAll(sql);
  finally
    db.Free;
  end;
  result := true;
  SynDBLog.Add.Log(sllInfo, 'SeedTemplateDb: % rebuilt from %',
    [FileName, script]);
end;

function ReadTemplates(const FileName: TFileName;
  out Recs: TSqlRecArray): boolean;
var
  db: TSqlDatabase;
  props: TSqlDBSQLite3ConnectionProperties;
  rows: ISqlDBRows;
  n: PtrInt;
begin
  result := false;
  Recs := nil;
  if not FileExists(FileName) then
  begin
    SynDBLog.Add.Log(sllError, 'ReadTemplates: % not found', [FileName]);
    exit;
  end;
  n := 0;
  db := TSqlDatabase.Create(FileName, '');
  try
    db.LockingMode := lmNormal;
    props := TSqlDBSQLite3ConnectionProperties.Create(db);
    try
      MigrateTemplateDb(props);
      rows := props.Execute('select ActionKey, Sql, ParamTypes, ' +
        'RecordType, RecordDecl, KeyField, ReadGroups, WriteGroups, ' +
        'CallerScope, Filter, OrderBy, Rules, TestBounds ' +
        'from SqlTemplate order by ActionKey;',
        []);
      if rows = nil then
        exit;
      while rows.Step do
      begin
        if n = length(Recs) then
          SetLength(Recs, n + 16);
        Recs[n].ActionKey := rows.ColumnUtf8(0);
        Recs[n].Sql := rows.ColumnUtf8(1);
        { NULL in any of them reads as not declared }
        Recs[n].ParamTypes := rows.ColumnUtf8(2);
        Recs[n].RecordType := rows.ColumnUtf8(3);
        Recs[n].RecordDecl := rows.ColumnUtf8(4);
        Recs[n].KeyField := rows.ColumnUtf8(5);
        Recs[n].ReadGroups := rows.ColumnInt(6);
        Recs[n].WriteGroups := rows.ColumnInt(7);
        Recs[n].CallerScope := rows.ColumnUtf8(8);
        Recs[n].Filter := rows.ColumnUtf8(9);
        Recs[n].OrderBy := rows.ColumnUtf8(10);
        Recs[n].Rules := rows.ColumnUtf8(11);
        Recs[n].TestBounds := rows.ColumnUtf8(12);
        inc(n);
      end;
      SetLength(Recs, n);
      result := n > 0;
    finally
      rows := nil;
      props.Free;
    end;
  finally
    db.Free; // the file is closed again: it is read at load time, not per call
  end;
end;


{ TDbTemplateSource }

constructor TDbTemplateSource.Create(const aFileName: TFileName);
begin
  inherited Create;
  fFileName := aFileName;
end;

function TDbTemplateSource.Changed: boolean;
begin
  result := (FileAgeToUnixTimeUtc(fFileName) <> fStampTime) or
            (FileSize(fFileName) <> fStampSize);
end;

function TDbTemplateSource.Load(out Recs: TSqlRecArray): boolean;
begin
  { the stamp is taken BEFORE reading: a write landing while the file is being
    read leaves the stamp older than the file, so the next miss reads again.
    The other order would record a change that was never loaded }
  fStampTime := FileAgeToUnixTimeUtc(fFileName);
  fStampSize := FileSize(fFileName);
  result := ReadTemplates(fFileName, Recs);
end;

function TDbTemplateSource.SourceName: RawUtf8;
begin
  StringToUtf8(fFileName, result);
end;

end.
