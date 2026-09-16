unit SqlServerConn;

{$I mormot.defines.inc}

{ The SQL Server connection of the "mssql" profile.

  Wiring, not a layer: it hands out a TSqlDBConnectionProperties and knows
  nothing about templates, keys or rights. Infra takes it exactly as it takes
  the SQLite one - which is the point being made here. Nothing below this unit
  changes when the target database does.

  It sits in commonserv because the editor connects to the same server to try
  a statement out, and needs the same connection string and the same OpenSSL
  setting. The client does not have this folder in its search path: a host
  name is nothing a client has to carry around.

  A service talks to one database. Two databases are two services, each with
  its own templates file - see the profiles in ServSqlTemplates.

  No credential is in this source, in the environment or in a configuration
  file: authentication is the Windows one, and on a Unix host that means
  Kerberos, from a ticket the user holds. A SQL login works too - the editor
  has the two fields for it - but then the password is the user's to type, not
  this unit's to keep.

  Point SQLSERVER_HOST below at your own server and SqlProfiles at your own
  database; bin/templates_mssql_schema.sql creates the four tables the
  supplied templates read, with a handful of made-up rows.

  macOS specifics, all four of them the reason this unit exists:

  - there is no "SQL Server Native Client" here, so the unixODBC "ODBC Driver
    17 for SQL Server" is used instead
  - Trusted_Connection works all the same, via Kerberos against the domain, so
    the service authenticates as the domain user just like on Windows. It does
    need a valid ticket - "kinit <user>@<REALM>", or the Ticket Viewer, and
    "klist" shows what is there. Without one the driver reports a login
    failure for an empty user
  - the server must be named by its FQDN: Kerberos resolves the service
    principal MSSQLSvc/<host>:1433 from the name, never from an IP address
  - an older server (2008 R2, say) offers TLS 1.0 only, and OpenSSL 3 refuses
    it by default, so OPENSSL_CONF is pointed at a configuration lowering
    MinProtocol BEFORE the driver initialises OpenSSL. Hence the call at the
    top of Connect() }

interface

uses
  SysUtils,
  mormot.core.base,
  mormot.core.text,
  mormot.core.unicode,
  mormot.core.os,
  mormot.core.log,
  mormot.db.sql,
  mormot.db.sql.odbc;

const
  { the sample names one server and one database; a real service reads them
    from its settings. Your own goes here - by FQDN, see above }
  SQLSERVER_HOST = 'sqlserver.example.com,1433';
  SQLSERVER_TLS_CONFIG = 'openssl-tls1.cnf';

  {$ifdef OSWINDOWS}
  SQLSERVER_DRIVER = 'SQL Server Native Client 11.0';
  {$else}
  SQLSERVER_DRIVER = 'ODBC Driver 17 for SQL Server';
  {$endif OSWINDOWS}

/// the connection string of one database on the sample's SQL Server
function SqlServerConnectionString(const aDatabase: RawUtf8): RawUtf8;

/// point OpenSSL at the configuration that still allows TLS 1.0
// - ConnectSqlServer does this itself; a tool building its own connection
// has to call it BEFORE the driver initialises OpenSSL
procedure SetupOpenSslForLegacyTls;

/// connect to one database on the sample's SQL Server
// - the caller owns the result and frees it
// - raises whatever the driver raises: a server that cannot be reached is a
// startup failure, and the message the driver gives says which of the three
// usual causes it is - no tunnel, no ticket, no driver
function ConnectSqlServer(const aDatabase: RawUtf8): TSqlDBConnectionProperties;

implementation

{$ifdef OSPOSIX}
function setenv(name, value: PAnsiChar; overwrite: integer): integer;
  cdecl; external 'c' name 'setenv';
{$endif OSPOSIX}

procedure SetupOpenSslForLegacyTls;
var
  cfg: RawUtf8;
begin
  {$ifdef OSPOSIX}
  if GetEnvironmentVariable('OPENSSL_CONF') <> '' then
    exit; // never override an explicit setting
  cfg := StringToUtf8(Executable.ProgramFilePath + SQLSERVER_TLS_CONFIG);
  if FileExists(Utf8ToString(cfg)) then
    setenv('OPENSSL_CONF', pointer(cfg), 1)
  else
    SynDBLog.Add.Log(sllWarning, '% not found next to the executable: a ' +
      'server offering TLS 1.0 only will refuse the handshake',
      [SQLSERVER_TLS_CONFIG]);
  {$endif OSPOSIX}
end;

function SqlServerConnectionString(const aDatabase: RawUtf8): RawUtf8;
begin
  result := 'DRIVER={' + SQLSERVER_DRIVER + '};SERVER=' + SQLSERVER_HOST +
    ';DATABASE=' + aDatabase + ';Trusted_Connection=yes' +
    ';Encrypt=yes;TrustServerCertificate=yes';
end;

function ConnectSqlServer(const aDatabase: RawUtf8): TSqlDBConnectionProperties;
begin
  SetupOpenSslForLegacyTls;
  { the whole string goes in as the server name: TOdbcConnectionProperties
    passes it through when the other three are empty }
  result := TOdbcConnectionProperties.Create(
    '', SqlServerConnectionString(aDatabase), '', '');
end;

end.
