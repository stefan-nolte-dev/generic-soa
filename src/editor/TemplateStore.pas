unit TemplateStore;

{ Read and write templates.sqlite, one operation at a time.

  Every operation opens the file, does its work and closes it again - the same
  way SqlTemplatesFromDb does on the server, and for the same reason: nobody
  should hold the template file open. It means the editor and a running server
  never fight over it, and the file stays readable in any SQLite viewer while
  the editor is open.

  Adding a column later touches three places
  here: the create statement, Load and Save. Nothing else, because everything
  above passes a whole TSqlRec around rather than a key and a statement. }

{$I mormot.defines.inc}

interface

uses
  SysUtils,
  mormot.core.base,
  mormot.core.os,   // for FileFromString
  mormot.core.text,
  mormot.core.unicode,
  mormot.db.sql,
  mormot.db.sql.sqlite3,
  mormot.db.raw.sqlite3,
  SqlTemplateTypes,
  SqlTemplateRegistry; // for the probe below - the editor may see everything

type

  { TTemplateStore }

  TTemplateStore = class
  private
    fFileName: TFileName;
    function Open(out Db: TSqlDatabase;
      out Props: TSqlDBSQLite3ConnectionProperties; out Msg: RawUtf8): boolean;
  public
    constructor Create(const aFileName: TFileName);
    /// create the file and the table if they are not there yet
    function EnsureTable(out Msg: RawUtf8): boolean;
    /// every template, by key
    function Load(out Recs: TSqlRecArray; out Msg: RawUtf8): boolean;
    /// insert or replace one template
    function Save(const Rec: TSqlRec; out Msg: RawUtf8): boolean;
    /// remove one template
    function Delete(const ActionKey: RawUtf8; out Msg: RawUtf8): boolean;
    /// write the whole set as insert statements, for version control
    // - a binary database file gives no readable diff; this does
    function ExportSql(const DestFile: TFileName; out Msg: RawUtf8): boolean;
    property FileName: TFileName read fFileName write fFileName;
  end;

/// run a set through the very check the server applies on ReloadTemplates
// - so what the editor accepts, the server accepts: same code, not a copy
function CheckSet(const Recs: TSqlRecArray; out Msg: RawUtf8): boolean;

implementation

uses
  SqlTemplatesFromDb; // for TEMPLATE_TABLE_SQL - one definition of the table

function CheckSet(const Recs: TSqlRecArray; out Msg: RawUtf8): boolean;
var
  probe: TSqlTemplateRegistry;
  n: integer;
begin
  Msg := '';
  { a throwaway registry, never the live one: this only answers "would the
    server take this?" and must not change anything }
  probe := TSqlTemplateRegistry.Create;
  try
    n := probe.Reload(Recs);
  finally
    probe.Free;
  end;
  result := n >= 0;
  if result then
    Msg := FormatUtf8('% template(s) - the server would accept this set.', [n])
  else
    Msg := 'Refused: the set is empty, or has a duplicate key, an empty ' +
           'key, an empty statement without a record type, or a record ' +
           'declaration without a record type.';
end;

{ TTemplateStore }

constructor TTemplateStore.Create(const aFileName: TFileName);
begin
  inherited Create;
  fFileName := aFileName;
end;

function TTemplateStore.Open(out Db: TSqlDatabase;
  out Props: TSqlDBSQLite3ConnectionProperties; out Msg: RawUtf8): boolean;
begin
  Db := nil;
  Props := nil;
  Msg := '';
  result := false;
  if fFileName = '' then
  begin
    Msg := 'No template file given.';
    exit;
  end;
  try
    Db := TSqlDatabase.Create(fFileName, '');
    Db.LockingMode := lmNormal;
    Props := TSqlDBSQLite3ConnectionProperties.Create(Db);
    result := true;
  except
    on E: Exception do
    begin
      FreeAndNil(Props);
      FreeAndNil(Db);
      Msg := FormatUtf8('% %', [E.ClassType, E.Message]);
    end;
  end;
end;

function TTemplateStore.EnsureTable(out Msg: RawUtf8): boolean;
var
  db: TSqlDatabase;
  props: TSqlDBSQLite3ConnectionProperties;
begin
  result := Open(db, props, Msg);
  if not result then
    exit;
  try
    try
      props.ExecuteNoResult(TEMPLATE_TABLE_SQL, []);
      Msg := FormatUtf8('% is ready.', [StringToUtf8(fFileName)]);
    except
      on E: Exception do
      begin
        Msg := FormatUtf8('% %', [E.ClassType, E.Message]);
        result := false;
      end;
    end;
  finally
    props.Free;
    db.Free;
  end;
end;

function TTemplateStore.Load(out Recs: TSqlRecArray; out Msg: RawUtf8): boolean;
var
  db: TSqlDatabase;
  props: TSqlDBSQLite3ConnectionProperties;
  rows: ISqlDBRows;
  n: PtrInt;
begin
  Recs := nil;
  result := Open(db, props, Msg);
  if not result then
    exit;
  n := 0;
  try
    try
      props.ExecuteNoResult(TEMPLATE_TABLE_SQL, []); // a fresh file is not an error
      MigrateTemplateDb(props); // a file from before the later columns
      rows := props.Execute('select ActionKey, Sql, ParamTypes, ' +
        'RecordType, RecordDecl, KeyField, ReadGroups, WriteGroups, ' +
        'CallerScope, Filter, OrderBy, Rules, TestBounds ' +
        'from SqlTemplate order by ActionKey;',
        []);
      if rows <> nil then
        while rows.Step do
        begin
          if n = length(Recs) then
            SetLength(Recs, n + 16);
          Recs[n].ActionKey := rows.ColumnUtf8(0);
          Recs[n].Sql := rows.ColumnUtf8(1);
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
      Msg := FormatUtf8('% template(s) loaded.', [n]);
    except
      on E: Exception do
      begin
        Msg := FormatUtf8('% %', [E.ClassType, E.Message]);
        result := false;
      end;
    end;
  finally
    rows := nil;
    props.Free;
    db.Free;
  end;
end;

function TTemplateStore.Save(const Rec: TSqlRec; out Msg: RawUtf8): boolean;
var
  db: TSqlDatabase;
  props: TSqlDBSQLite3ConnectionProperties;
begin
  result := false;
  Msg := '';
  if Rec.ActionKey = '' then
  begin
    Msg := 'The action key is empty.';
    exit;
  end;
  if (Rec.Sql = '') and
     (Rec.RecordType = '') then
  begin
    { the one case an empty statement is allowed is a record write that has
      its statement generated - and that needs a record type to generate from }
    Msg := 'The statement is empty, and no record type is given to ' +
           'generate one from.';
    exit;
  end;
  if not Open(db, props, Msg) then
    exit;
  try
    try
      props.ExecuteNoResult(TEMPLATE_TABLE_SQL, []);
      MigrateTemplateDb(props);
      { insert or replace, so the same button saves a new key and an edit of
        an existing one - the key is the primary key }
      props.ExecuteNoResult(
        'insert or replace into SqlTemplate ' +
        '(ActionKey, Sql, ParamTypes, RecordType, RecordDecl, KeyField, ' +
        'CallerScope, Filter, OrderBy, Rules, TestBounds, ' +
        'ReadGroups, WriteGroups) ' +
        'values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);',
        [Rec.ActionKey, Rec.Sql, Rec.ParamTypes, Rec.RecordType,
         Rec.RecordDecl, Rec.KeyField, Rec.CallerScope,
         Rec.Filter, Rec.OrderBy, Rec.Rules, Rec.TestBounds,
         Rec.ReadGroups, Rec.WriteGroups]);
      Msg := FormatUtf8('% saved.', [Rec.ActionKey]);
      result := true;
    except
      on E: Exception do
        Msg := FormatUtf8('% %', [E.ClassType, E.Message]);
    end;
  finally
    props.Free;
    db.Free;
  end;
end;

function TTemplateStore.Delete(const ActionKey: RawUtf8; out Msg: RawUtf8): boolean;
var
  db: TSqlDatabase;
  props: TSqlDBSQLite3ConnectionProperties;
begin
  result := false;
  Msg := '';
  if ActionKey = '' then
  begin
    Msg := 'No action key selected.';
    exit;
  end;
  if not Open(db, props, Msg) then
    exit;
  try
    try
      props.ExecuteNoResult(
        'delete from SqlTemplate where ActionKey = ?;', [ActionKey]);
      Msg := FormatUtf8('% deleted.', [ActionKey]);
      result := true;
    except
      on E: Exception do
        Msg := FormatUtf8('% %', [E.ClassType, E.Message]);
    end;
  finally
    props.Free;
    db.Free;
  end;
end;

function TTemplateStore.ExportSql(const DestFile: TFileName;
  out Msg: RawUtf8): boolean;
var
  recs: TSqlRecArray;
  txt, script, db: RawUtf8;
  i: PtrInt;
begin
  result := Load(recs, Msg);
  if not result then
    exit;
  { Deliberately no timestamp and no row count in the header: an unchanged
    set has to produce an unchanged file, or every commit carries a diff that
    means nothing and the real changes drown in it. }
  { the header names the two files it is about - there is one pair per
    database, and a header naming the wrong one is worse than none }
  script := StringToUtf8(ExtractFileName(DestFile));
  db := StringToUtf8(ExtractFileName(ChangeFileExt(DestFile, '.sqlite')));
  txt := '-- Written by the template editor on every save. Two jobs: a diff ' +
         'that can be read'#10 +
         '-- in a commit, and a backup the whole set can be restored from:'#10 +
         '--   sqlite3 ' + db + ' < ' + script + #10 +
         '-- The database of record is ' + db + '. Rows are ordered by ' +
         'key, so a'#10 +
         '-- diff shows what changed and nothing else.'#10 +
         TEMPLATE_TABLE_SQL + #10 +
         'delete from SqlTemplate;'#10;
  for i := 0 to high(recs) do
    txt := txt + FormatUtf8(
      'insert into SqlTemplate (ActionKey, Sql, ParamTypes, RecordType, ' +
      'RecordDecl, KeyField, CallerScope, Filter, OrderBy, Rules, ' +
      'TestBounds, ReadGroups, WriteGroups) ' +
      'values (%, %, %, %, %, %, %, %, %, %, %, %, %);'#10,
      [QuotedStr(recs[i].ActionKey), QuotedStr(recs[i].Sql),
       QuotedStr(recs[i].ParamTypes), QuotedStr(recs[i].RecordType),
       QuotedStr(recs[i].RecordDecl), QuotedStr(recs[i].KeyField),
       QuotedStr(recs[i].CallerScope),
       QuotedStr(recs[i].Filter), QuotedStr(recs[i].OrderBy),
       QuotedStr(recs[i].Rules), QuotedStr(recs[i].TestBounds),
       recs[i].ReadGroups,
       recs[i].WriteGroups]);
  try
    FileFromString(txt, DestFile);
    Msg := FormatUtf8('% template(s) written to %.',
      [length(recs), StringToUtf8(DestFile)]);
  except
    on E: Exception do
    begin
      Msg := FormatUtf8('% %', [E.ClassType, E.Message]);
      result := false;
    end;
  end;
end;

end.
