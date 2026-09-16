unit ServSqlTemplates;

{ Start up of the sample server - the one place that sees every layer.

  Creates the demo database on first run, wires the layers together and
  publishes IAppSqlTool over HTTP. No ORM model: TRestServerFullMemory is
  enough for an interface based service, which also shows that this style does
  not depend on the ORM at all. }
interface

uses
  mormot.core.base,
  { the profile table itself is in common/, because the client and the editor
    switch by the same names - see SqlProfiles.pas }
  SqlProfiles;

/// start the sample server for one profile
// - the profile decides two things and nothing else: which database the
// statements run against, and which file they are read from. An empty or
// unknown name is refused rather than guessed
// - the templates come from that file next to the binary, and from nowhere
// else: no statement of this application is compiled in
procedure StartServer(const Profile: RawUtf8 = PROFILE_DEMO);

procedure StopServer;

implementation

uses
  SysUtils,
  mormot.core.text,
  mormot.core.unicode, // IdemPropNameU
  mormot.core.os,
  mormot.core.log,
  mormot.db.sql,
  mormot.db.sql.sqlite3,
  mormot.db.raw.sqlite3,
  mormot.core.interfaces, // optNoLogInput/optNoLogOutput: no password in a log
  mormot.rest.server,
  mormot.rest.memserver,
  mormot.rest.http.server,
  AppSqlServices,
  AppSqlImplementation,
  AppCallerToken,        // the signer lives there, and is drawn at startup
  AppAuthImplementation, // the login, on its own interface
  { the record types a record write may name - the unit is here for its
    initialization alone: this server names none of these types in its code,
    it only has to be able to find them by name, and no layer below the
    application has it in its uses clause at all }
  WriteDtos,
  SqlTemplateTypes,
  DomSqlServices,
  DomSqlImplementation,
  InfraSqlServices,
  InfraSqlImplementation, // the one place that knows the implementation class
  SqlTemplatesFromDb,
  AuthAccountsFromDb, // the accounts a login is checked against
  SqlServerConn; // the SQL Server connection of the mssql profile


var
  TemplateFile: TFileName;
  { the accounts, shared by every profile - see StartServer }
  AuthFile: TFileName;
  DB: TSqlDatabase;
  { whichever the profile connects - the layers below take the base type,
    so none of them can tell SQLite from SQL Server }
  Props: TSqlDBConnectionProperties;
  Rest: TRestServerFullMemory;
  Http: TRestHttpServer;
  Source: ISqlTemplateSource;
  Dom: IDomSqlTool;
  Auth: TAppAuthTool;
  Service: TAppSqlTool;

procedure CreateDemoDatabase;
var
  rows: ISqlDBRows;
begin
  { the row count decides whether the demo data still has to go in, so an
    edited database is left alone }
  Props.ExecuteNoResult(
    'create table if not exists Customer (' +
    '  ID integer primary key autoincrement,' +
    '  Name text not null,' +
    '  City text not null);', []);
  Props.ExecuteNoResult(
    'create table if not exists Invoice (' +
    '  ID integer primary key autoincrement,' +
    '  CustomerID integer not null,' +
    '  Amount real not null,' +
    { a date column, because that is where the declaration earns its keep }
    '  InvoiceDate text not null);', []);
  rows := Props.Execute('select count(*) from Customer;', []);
  if (rows <> nil) and
     rows.Step and
     (rows.ColumnInt(0) > 0) then
    exit; // demo data already present
  Props.ExecuteNoResult('insert into Customer (Name, City) values ' +
    '(''Bergmann Werkzeuge'', ''Wegberg''),' +
    '(''Ostwald Holzbearbeitung'', ''Detmold''),' +
    '(''Nordharz Fenster'', ''Goslar''),' +
    '(''Niederrhein Tischlerei'', ''Kempen'');', []);
  Props.ExecuteNoResult(
    'insert into Invoice (CustomerID, Amount, InvoiceDate) values ' +
    '(1, 1250.00, ''2025-02-11''), (1, 830.50, ''2025-06-30''),' +
    '(1, 2100.00, ''2026-03-04''),' +
    '(2, 4990.00, ''2025-01-20''), (2, 1275.25, ''2026-05-15''),' +
    '(3, 615.00, ''2026-07-02''),' +
    '(4, 3400.00, ''2024-11-08''), (4, 1890.75, ''2025-09-19''),' +
    '(4, 220.00, ''2026-08-01'');', []);
end;

{ Three tables of a hundred rows each, so a result set is big enough to be
  worth looking at - four demo customers make a poor table.

  Generated from the loop index and nothing else: no Random, so two machines
  building this database get the same rows, and a template that works here
  works there. }
procedure CreateBulkDemoTables;
const
  VORNAME: array[0..9] of RawUtf8 = (
    'Anna', 'Bernd', 'Clara', 'Dirk', 'Eva',
    'Frank', 'Greta', 'Hans', 'Ida', 'Jens');
  NACHNAME: array[0..9] of RawUtf8 = (
    'Becker', 'Hoffmann', 'Klein', 'Lange', 'Meyer',
    'Neumann', 'Richter', 'Schulz', 'Vogel', 'Wolf');
  ABTEILUNG: array[0..4] of RawUtf8 = (
    'Fertigung', 'Montage', 'Vertrieb', 'Konstruktion', 'Verwaltung');
  { no umlaut anywhere in this data on purpose: a source literal would depend
    on the compiler's source code page, and these rows have to come out the
    same everywhere }
  GEWERK: array[0..4] of RawUtf8 = (
    'Fensterfront', 'Wintergarten', 'Rollladen', 'Fassade', 'Dachfenster');
var
  rows: ISqlDBRows;
  conn: TSqlDBConnection;
  i: integer;
begin
  Props.ExecuteNoResult(
    'create table if not exists Mitarbeiter (' +
    '  ID integer primary key autoincrement,' +
    '  Name text not null,' +
    '  Abteilung text not null,' +
    '  Eintritt text not null,' +
    '  Gehalt real not null);', []);
  Props.ExecuteNoResult(
    'create table if not exists Projekt (' +
    '  ID integer primary key autoincrement,' +
    '  Titel text not null,' +
    '  CustomerID integer not null,' +
    '  Start text not null,' +
    '  Budget real not null);', []);
  Props.ExecuteNoResult(
    'create table if not exists Zeitbuchung (' +
    '  ID integer primary key autoincrement,' +
    '  MitarbeiterID integer not null,' +
    '  ProjektID integer not null,' +
    '  Datum text not null,' +
    '  Stunden real not null);', []);
  { the table the two Artikel record templates write to - it used to exist
    only in one hand made demo.sqlite, so those two keys pointed at nothing on
    any other machine. Its key column is ID, which is what the generated
    update needs; see SqlRecordBind }
  Props.ExecuteNoResult(
    'create table if not exists Artikel (' +
    '  ID integer primary key autoincrement,' +
    '  ArtNr integer not null,' +
    '  ArtName text not null,' +
    '  Kind text);', []);
  rows := Props.Execute('select count(*) from Artikel;', []);
  if (rows <> nil) and
     rows.Step and
     (rows.ColumnInt(0) = 0) then
  begin
    rows := nil;
    Props.ExecuteNoResult('insert into Artikel (ArtNr, ArtName, Kind) values ' +
      '(1, ''Tisch'', ''Aussenbereich''),' +
      { 2 and not 1: ArtNr is what UpdateTDtoArtikelRow matches on, and a
        demo whose natural key is not unique demonstrates the wrong thing -
        the update would change two rows and look like a bug in the
        generated statement }
      '(2, ''Gartenstuhl'', ''Aussenbereich''),' +
      '(3, ''Fliesen'', ''Innenbereich''),' +
      '(4, ''Sonnenschirm-Wetterfest'', ''Aussenbereich'');', []);
  end;
  rows := nil;
  { and say so in the schema rather than only in the data. A database written
    before this line may hold the old duplicate, and refusing to start over
    that would be the wrong trade - so the index is created when the data
    allows it and skipped, loudly, when it does not }
  rows := Props.Execute('select count(*) from (select ArtNr from Artikel ' +
    'group by ArtNr having count(*) > 1);', []);
  if (rows <> nil) and
     rows.Step and
     (rows.ColumnInt(0) > 0) then
  begin
    rows := nil;
    TextColor(ccBrown);
    writeln('Artikel: ArtNr kommt mehrfach vor, der Unique-Index wurde nicht');
    writeln('angelegt. UpdateTDtoArtikelRow trifft dann mehr als eine Zeile.');
    TextColor(ccLightGray);
  end
  else
  begin
    rows := nil;
    Props.ExecuteNoResult('create unique index if not exists ' +
      'Artikel_ArtNr_unique on Artikel(ArtNr);', []);
  end;
  { the table the Rules column is demonstrated on: a postcode and an e-mail
    are the two things a database column cannot state about itself, and a
    template that writes them says so with '2:plz;3:email' }
  Props.ExecuteNoResult(
    'create table if not exists Kontakt (' +
    '  ID integer primary key autoincrement,' +
    '  Name text not null,' +
    '  Plz text not null,' +
    '  Email text not null);', []);
  rows := Props.Execute('select count(*) from Kontakt;', []);
  if (rows <> nil) and
     rows.Step and
     (rows.ColumnInt(0) = 0) then
  begin
    rows := nil;
    Props.ExecuteNoResult('insert into Kontakt (Name, Plz, Email) values ' +
      '(''Bergmann Werkzeuge'', ''41844'', ''info@example.de''),' +
      '(''Ostwald Holzbearbeitung'', ''32756'', ''kontakt@example.de''),' +
      '(''Nordharz Fenster'', ''38640'', ''buero@example.de''),' +
      '(''Niederrhein Tischlerei'', ''47906'', ''mail@example.de'');',
      []);
  end;
  rows := nil;
  rows := Props.Execute('select count(*) from Mitarbeiter;', []);
  if (rows <> nil) and
     rows.Step and
     (rows.ColumnInt(0) > 0) then
    exit; // already filled - an edited database is left alone
  rows := nil;
  { one transaction for all three hundred inserts: without it SQLite commits
    each one on its own and the first start takes seconds instead of none }
  conn := Props.ThreadSafeConnection;
  conn.StartTransaction;
  try
    for i := 1 to 100 do
      Props.ExecuteNoResult(
        'insert into Mitarbeiter (Name, Abteilung, Eintritt, Gehalt) ' +
        'values (?, ?, ?, ?);',
        [VORNAME[i mod 10] + ' ' + NACHNAME[(i div 10) mod 10],
         ABTEILUNG[i mod 5],
         FormatUtf8('%-%-%', [2015 + i mod 10,
           UInt2DigitsToShortFast(1 + i mod 12),
           UInt2DigitsToShortFast(1 + i mod 28)]),
         3200 + (i mod 25) * 140]);
    for i := 1 to 100 do
      Props.ExecuteNoResult(
        'insert into Projekt (Titel, CustomerID, Start, Budget) ' +
        'values (?, ?, ?, ?);',
        [FormatUtf8('% %-%', [GEWERK[i mod 5], 2020 + i mod 6, i]),
         1 + i mod 4,
         FormatUtf8('%-%-%', [2020 + i mod 6,
           UInt2DigitsToShortFast(1 + (i * 5) mod 12),
           UInt2DigitsToShortFast(1 + (i * 3) mod 28)]),
         5000 + (i mod 40) * 1250]);
    { the bookings point at the first twenty projects only, so the grouped
      query has something to group - a hundred bookings over a hundred
      projects would show one row each }
    for i := 1 to 100 do
      Props.ExecuteNoResult(
        'insert into Zeitbuchung (MitarbeiterID, ProjektID, Datum, Stunden) ' +
        'values (?, ?, ?, ?);',
        [1 + (i * 3) mod 100,
         1 + (i * 7) mod 20,
         FormatUtf8('2026-%-%', [UInt2DigitsToShortFast(1 + i mod 12),
           UInt2DigitsToShortFast(1 + i mod 28)]),
         2 + (i mod 7) * 0.5]);
    conn.Commit;
  except
    conn.Rollback;
    raise;
  end;
end;

{ Without this every log line in the layers below goes nowhere, and a
  statement the database refuses looks like a bare sqlFailed with no reason -
  leaving a debugger as the only way to find out what the driver said. }
procedure StartLogging;
begin
  with TSynLog.Family do
  begin
    Level := LOG_STACKTRACE + [sllInfo, sllWarning, sllDebug, sllSQL];
    PerThreadLog := ptIdentifiedInOneFile;
    { and the ones that matter also on the console, so a failed statement is
      visible while the sample is being tried out }
    EchoToConsole := [sllError, sllWarning];
    DestinationPath := Executable.ProgramFilePath;
    HighResolutionTimestamp := true;
  end;
  { SynDBLog is a family of its own - the db layer logs through it }
  SynDBLog := TSynLog;
end;

{ the startup banner asks the domain layer what it loaded, and it has to say
  who is asking like everyone else - this is the process itself, not a call }
function AdminCaller: TSqlCaller;
begin
  result := default(TSqlCaller);
  result.Authenticated := true;
  result.UserName := 'startup';
  result.Reads := -1;  // every bit: in no template's way
  result.Writes := -1;
end;

{ a SQLite file: created on first run, so a clone has something to query }
procedure ConnectFile(const aFile: RawUtf8; out Info: RawUtf8);
var
  dbfile: TFileName;
begin
  dbfile := Executable.ProgramFilePath + Utf8ToString(aFile);
  { One shared TSqlDatabase for all connections, so the whole process talks
    to the file through a single handle.

    demo.sqlite stays locked for the life of the process either way: the
    statically linked SQLite holds it and lmNormal does not release it. Stop
    the server to look inside. The templates file is different on purpose - it
    is opened to be read and closed again, which is also what lets the editor
    write to it while the server runs. }
  try
    DB := TSqlDatabase.Create(dbfile, '');
  except
    on E: Exception do
      { A SQLite file another process holds open does not report as busy, it
        reports as a corrupt header - which sends the reader looking for a
        damaged file that is perfectly fine. Say what it usually is, without
        claiming certainty. }
      if PosEx('NOTADB', StringToUtf8(E.Message)) > 0 then
        raise ESqlTemplate.CreateUtf8(
          '% cannot be opened (%: %).'#13#10 +
          'A SQLite file that is already open elsewhere reports exactly this. ' +
          'Is a second server, or the editor, on the same file? One process ' +
          'per profile - the other profile is free to run at the same time.',
          [dbfile, E.ClassType, E.Message])
      else
        raise;
  end;
  DB.LockingMode := lmNormal;
  Props := TSqlDBSQLite3ConnectionProperties.Create(DB);
  CreateDemoDatabase;
  CreateBulkDemoTables;
  StringToUtf8(dbfile, Info);
end;

{ a SQL Server database. Nothing is created and nothing is written: the
  templates of such a profile select, and that is a decision about which
  statements its file holds, not one this code makes. }
procedure ConnectServer(const aDatabase: RawUtf8; out Info: RawUtf8);
begin
  try
    Props := ConnectSqlServer(aDatabase);
  except
    on E: Exception do
      { the driver's own words are true but unhelpful here, and this is the
        first thing a reader of this sample hits: the host is a placeholder
        until it is theirs }
      raise ESqlTemplate.CreateUtf8(
        'No connection to % (%).'#13#10 +
        'This profile talks to a SQL Server you provide. Set SQLSERVER_HOST ' +
        'in src/commonserv/SqlServerConn.pas and TargetDatabase in ' +
        'src/common/SqlProfiles.pas - both carry a placeholder - and ' +
        'rebuild.'#13#10 +
        'It also needs a route to that server, a login for it (a Kerberos ' +
        'ticket, which "klist" shows, or the user and password fields of the ' +
        'editor), and the tables: bin/templates_mssql_schema.sql creates the ' +
        'four this profile reads.'#13#10 +
        'The driver said: %',
        [SQLSERVER_HOST, E.ClassType, E.Message]);
  end;
  Info := aDatabase + ' on ' + SQLSERVER_HOST +
          ' (' + SQLSERVER_DRIVER + ', Trusted_Connection)';
end;

procedure StartServer(const Profile: RawUtf8);
var
  dbinfo, authmsg: RawUtf8;
  tool: TDomSqlTool;
  n: integer;
  p: PtrInt;
begin
  StartLogging;
  p := FindSqlProfile(Profile);
  if p < 0 then
    raise ESqlTemplate.CreateUtf8('unknown profile "%" - known are %',
      [Profile, RawUtf8ArrayToCsv(SqlProfileNames, ', ')]);
  TemplateFile := Executable.ProgramFilePath +
                  Utf8ToString(SQL_PROFILES[p].TemplateFile);
  { normally a no-op: the file is there. It rebuilds it from templates.sql
    when it is not, so a clone without the binary database still starts }
  if not SeedTemplateDb(TemplateFile) then
    raise ESqlTemplate.CreateUtf8('no % and no % next to the executable',
      [TemplateFile, ChangeFileExt(TemplateFile, '.sql')]);
  Source := TDbTemplateSource.Create(TemplateFile);

  { the accounts, in a file of their own and shared by both profiles: the
    target database differs per profile, the people do not. Created with its
    two demo accounts on the first start and never touched again }
  AuthFile := Executable.ProgramFilePath + AUTH_DB_FILE;
  if not EnsureAuthDb(AuthFile, authmsg) then
    raise ESqlTemplate.CreateUtf8('% cannot be opened: %',
      [AuthFile, authmsg]);

  { which of the two the profile names is the whole difference: below this
    line nothing can tell them apart }
  if SQL_PROFILES[p].TargetDatabase <> '' then
    ConnectServer(SQL_PROFILES[p].TargetDatabase, dbinfo)
  else
    ConnectFile(SQL_PROFILES[p].TargetFile, dbinfo);

  { the three layers, wired bottom up - each one is handed the interface of
    the next and never its class }
  tool := TDomSqlTool.Create(TSqlTemplateExec.Create(Props), Source);
  Dom := tool;
  n := tool.LoadTemplates;
  if n <= 0 then
    raise ESqlTemplate.Create('no usable SQL template found');
  Service := TAppSqlTool.Create(Dom);

  Rest := TRestServerFullMemory.Create(APPSQL_ROOT);
  Rest.ServiceDefine(Service, [IAppSqlTool]);
  { the login, on its own interface - and with the logging of arguments and
    results switched off, because one of those arguments is a password. The
    auth service next door registers its own the same way }
  InitTokens;
  Auth := TAppAuthTool.Create(AuthFile);
  Rest.ServiceDefine(Auth, [IAppAuthTool])
      .SetOptions([], [optNoLogInput, optNoLogOutput]);

  { its own port, so the other profile can run at the same time }
  Http := TRestHttpServer.Create(SQL_PROFILES[p].Port, [Rest], '+',
    HTTP_DEFAULT_MODE);
  Http.AccessControlAllowOrigin := '*';

  if RequireToken then
  begin
    { with the port, which is the half of the example nobody can guess }
    TextColor(ccBrown);
    writeln('Log in first - the demo accounts are admin and user:');
    writeln('  curl -s -X POST http://localhost:', SQL_PROFILES[p].Port,
      '/', APPSQL_ROOT, '/AppAuthTool.Login -d ''["admin","<password>",""]''');
    writeln('The password is in the documentation. What comes back goes into');
    writeln('  -H "Authorization: Bearer <token>"');
    TextColor(ccLightGray);
  end;

  TextColor(ccLightGreen);
  writeln('SQL template service on port ', SQL_PROFILES[p].Port,
    ', root /', APPSQL_ROOT);
  TextColor(ccLightGray);
  writeln(Dom.TemplateCount, ' templates from ', Source.SourceName, ':');
  writeln('  ', RawUtf8ArrayToCsv(
    Dom.AvailableActions(AdminCaller), ', '));
  writeln('profile:  ', Profile);
  writeln('database: ', dbinfo);
  writeln('log:      ', Executable.ProgramFilePath, Executable.ProgramName,
    '.log  (errors are echoed here as well)');
  writeln;
  writeln('Edit ', TemplateFile, ' while this runs: an action key this');
  writeln('server does not know makes it look at the file again.');
  writeln;
  writeln('Hit enter to stop.');
end;


procedure StopServer;
begin
  FreeAndNil(Http);
  FreeAndNil(Rest);
  Service := nil; // released by the service factory
  Auth := nil;    // released by the service factory, like Service above
  DoneTokens;     // and with the signer, every token it ever signed
  Dom := nil;
  Source := nil;
  FreeAndNil(Props);
  FreeAndNil(DB); // not owned by Props: see its Create(aDB) overload
end;

end.
