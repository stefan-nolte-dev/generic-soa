unit EditorDb;

{ The editor's own connection to the data database.

  Deliberately its own and not the server's: the editor runs statements that
  are not registered anywhere yet, and has to do that while the server runs,
  or while no server exists.

  It is a TSqlDBConnectionProperties like the server's, so the same editor
  points at this sample's SQLite file or at SQL Server over ODBC with no
  change but what is typed into the connection fields.

  On safety, because that is the part that matters. There is no throwaway copy
  of the database - against SQL Server there could not be. What protects the
  data is the transaction: TestWrite opens one, runs the statement and rolls
  it back, with no code path that commits. Enough for insert, update and
  delete. NOT enough for everything: DDL is not transactional on every engine,
  identity counters do not roll back, and a trigger with an effect outside the
  database is beyond reach. Point the editor at a development database. }
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
  mormot.core.unicode, // for mORMot's Utf8ToString - the RTL's returns UnicodeString
  mormot.db.sql,
  mormot.db.sql.sqlite3,
  mormot.db.sql.odbc,
  mormot.db.raw.sqlite3;

type
  /// which driver the editor talks to
  // - no data source entry: a DSN is a name unixODBC looks up in a file that
  //   is not part of this sample, and a driver asked for one it cannot find
  //   waits instead of failing - which shows up as an editor that hangs. The
  //   connection string says the same things and says them here
  TEditorEngine = (
    engSQLite,
    engOdbcString);

  { TEditorDb }

  TEditorDb = class
  private
    fProps: TSqlDBConnectionProperties;
    fDb: TSqlDatabase;
    fDescription: RawUtf8;
    fShortDescription: RawUtf8;
    fLastCleanupError: RawUtf8;
  public
    destructor Destroy; override;
    /// open a connection, replacing any previous one
    // - Target is a file name for engSQLite, or a full ODBC connection
    // string for engOdbcString
    // - never raises: a failure is reported through Msg, because a mistyped
    // connection string is an ordinary event in an editor
    function Connect(Engine: TEditorEngine; const Target, User, Password: RawUtf8;
      out Msg: RawUtf8): boolean;
    /// close whatever is open, whatever state it is in
    // - never raises either: a server that went away while the handle was
    // open is reported by the driver when the handle is freed, and the
    // connection is being dropped either way. What it said is in
    // LastCleanupError, for the log
    procedure Disconnect;
    function Connected: boolean;
    /// the connection statements run on - also the one a transaction is on
    // - nil when there is none, and nil when getting one failed: asking for
    // it can reconnect, and a reconnect can fail long after Connect went
    // through - a Kerberos ticket is good for ten hours, a tunnel for as long
    // as it is up. The reason is in LastCleanupError
    function Connection: TSqlDBConnection;
    property Props: TSqlDBConnectionProperties read fProps;
    /// what is currently open, for the status line
    property Description: RawUtf8 read fDescription;
    /// the same thing in the few words a window title has room for
    // - the path and the connection string are on screen anyway, in Ziel
    property ShortDescription: RawUtf8 read fShortDescription;
    /// what the driver said the last time Disconnect or Connection failed
    // - '' when it did not: these two report rather than raise, so this is
    // where the reason is
    property LastCleanupError: RawUtf8 read fLastCleanupError;
  end;

/// the usual cause behind a failed connection, in one line, or ''
// - a guess and nothing more, so it is worded as one: what the driver said
// stays in the message above it. The four it knows are the four that happen
// here, and each was read off a real failure rather than guessed at
function ConnectionHint(const Msg: RawUtf8): RawUtf8;

implementation

function ConnectionHint(const Msg: RawUtf8): RawUtf8;
begin
  { PosI compares against an UPPER CASE needle - that is the contract, not a
    shouted string }
  result := '';
  if Msg = '' then
    exit;
  if PosI('SSPI', Msg) > 0 then
    result := 'Das sieht nach einem fehlenden oder abgelaufenen Kerberos-' +
      'Ticket aus: "klist" zeigt, was da ist, "kinit <benutzer>@<REALM>" ' +
      'holt ein neues. Ein Ticket gilt üblicherweise etwa zehn Stunden.'
  else if (PosI('SSL ROUTINES', Msg) > 0) or
          (PosI('UNSUPPORTED PROTOCOL', Msg) > 0) then
    result := 'Das ist die TLS-Seite: bietet der Server nur TLS 1.0, dann ' +
      'lehnt OpenSSL das ohne openssl-tls1.cnf ab. Die Datei muss neben der ' +
      'ausführbaren Datei liegen.'
  else if (PosI('TCP PROVIDER', Msg) > 0) or
          (PosI('LOGIN TIMEOUT', Msg) > 0) or
          (PosI('NOT FOUND OR NOT ACCESSIBLE', Msg) > 0) then
    result := 'Das sieht nach dem Weg zum Server aus: ohne Route dorthin ' +
      '(VPN, Tunnel) löst der Name nicht auf oder die Verbindung läuft in ' +
      'die Zeitüberschreitung.'
  else if (PosI('IM002', Msg) > 0) or
          (PosI('DATA SOURCE NAME NOT FOUND', Msg) > 0) or
          (PosI('CAN''T OPEN LIB', Msg) > 0) then
    result := 'Das sieht nach dem ODBC-Treiber aus: der Name in DRIVER={...} ' +
      'muss einer sein, den "odbcinst -q -d" auflistet.';
end;

{ TEditorDb }

destructor TEditorDb.Destroy;
begin
  Disconnect;
  inherited Destroy;
end;

procedure TEditorDb.Disconnect;
begin
  fLastCleanupError := '';
  try
    FreeAndNil(fProps);
  except
    on E: Exception do
      { ODBC reports a connection that died under it when the handle is
        closed, which is here. The handle is gone regardless, so there is
        nothing to do but say what happened: raising it would take down
        whoever is only switching profile or closing the window }
      fLastCleanupError := FormatUtf8('% %', [E.ClassType, E.Message]);
  end;
  try
    FreeAndNil(fDb); // owned by us, not by the properties
  except
    on E: Exception do
      if fLastCleanupError = '' then
        fLastCleanupError := FormatUtf8('% %', [E.ClassType, E.Message]);
  end;
  fDescription := '';
  fShortDescription := '';
end;

function TEditorDb.Connected: boolean;
begin
  result := fProps <> nil;
end;

function TEditorDb.Connection: TSqlDBConnection;
begin
  result := nil;
  if fProps = nil then
    exit;
  try
    result := fProps.ThreadSafeConnection;
  except
    on E: Exception do
    begin
      { it reconnects when the connection it holds is no longer usable, and
        that reconnect fails once the ticket has expired or the tunnel is
        down - hours after Connect said yes }
      fLastCleanupError := FormatUtf8('% %', [E.ClassType, E.Message]);
      result := nil;
    end;
  end;
end;

{ the DATABASE= entry of a connection string, or '' when it names none }
function DatabaseOf(const ConnectionString: RawUtf8): RawUtf8;
var
  p: PtrInt;
begin
  result := '';
  p := PosI('DATABASE=', ConnectionString);
  if p = 0 then
    exit;
  result := copy(ConnectionString, p + 9, maxInt);
  p := PosExChar(';', result);
  if p > 0 then
    SetLength(result, p - 1);
end;

function TEditorDb.Connect(Engine: TEditorEngine;
  const Target, User, Password: RawUtf8; out Msg: RawUtf8): boolean;
var
  hint, db: RawUtf8;
  given, full: string;
begin
  result := false;
  Msg := '';
  Disconnect;
  if Target = '' then
  begin
    Msg := 'No target given.';
    exit;
  end;
  try
    case Engine of
      engSQLite:
        begin
          given := Utf8ToString(Target);
          full := ExpandFileName(given);
          if not FileExists(full) then
          begin
            { name the absolute path that was tried, and then say the right
              thing about it. A relative name is resolved against the working
              directory, which is the project folder when the editor is
              started from the IDE - that is where the otherwise puzzling
              failure comes from, and the hint belongs there. A name that was
              already absolute was looked up where it says: there is no path
              to explain, and the same hint would send the reader after a
              problem that is not there. The file is simply not there yet,
              so the way it comes into being is what helps }
            if full = given then
              Msg := FormatUtf8('Not found: %'#13#10 +
                'The path is absolute, so that is where it was looked for. ' +
                'The sample databases are build output: the server writes ' +
                'them on first start, and the .sql script of the same name ' +
                'beside them restores the written-out state.',
                [StringToUtf8(full)])
            else
              Msg := FormatUtf8('Not found: %'#13#10 +
                'A relative name is resolved against the working directory, ' +
                'which is not the folder the executable sits in when started ' +
                'from the IDE. Use the button next to the field, or type an ' +
                'absolute path.',
                [StringToUtf8(full)]);
            exit;
          end;
          fDb := TSqlDatabase.Create(Utf8ToString(Target), '');
          fDb.LockingMode := lmNormal;
          fProps := TSqlDBSQLite3ConnectionProperties.Create(fDb);
          fDescription := FormatUtf8('SQLite: %', [Target]);
          fShortDescription := FormatUtf8('SQLite: %',
            [StringToUtf8(ExtractFileName(Utf8ToString(Target)))]);
        end;
      engOdbcString:
        begin
          { ServerName empty and the full string as database name selects
            SqlDriverConnect - the form that takes DRIVER=...;server=...  }
          fProps := TSqlDBOdbcConnectionProperties.Create(
            '', Target, User, Password);
          fDescription := 'ODBC connection string';
          { the database out of DRIVER=...;SERVER=...;DATABASE=X;... - which
            is the one word that says where the statements will run }
          fShortDescription := 'ODBC';
          db := DatabaseOf(Target);
          if db <> '' then
            fShortDescription := 'ODBC: ' + db;
        end;
    end;
    { Creating the properties does not necessarily touch the server. Force a
      real connection now, so the status line tells the truth. }
    fProps.ThreadSafeConnection.Connect;
    result := true;
    Msg := FormatUtf8('Connected - %', [fDescription]);
  except
    on E: Exception do
    begin
      Disconnect;
      Msg := FormatUtf8('% %', [E.ClassType, E.Message]);
      hint := ConnectionHint(Msg);
      if hint <> '' then
        Msg := Msg + #13#10 + hint;
      { A server holding this very file open reports as a corrupt header
        rather than as a busy database, which sends the reader looking in the
        wrong place. Say what it usually is, without claiming certainty. }
      if (Engine = engSQLite) and
         (PosEx('NOTADB', E.Message) > 0) then
        Msg := Msg + #13#10 +
          'A SQLite file that is open elsewhere reports this. Is the server ' +
          'running on the same file? Stop it and try again. This is a SQLite ' +
          'property only - it does not arise against SQL Server.';
    end;
  end;
end;

end.
