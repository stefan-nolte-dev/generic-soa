unit SqlProfiles;

{ The profiles, as a table, in the one folder everybody sees.

  A service talks to one database. A profile names that database's port and
  the file its templates live in - two databases are two services, two files,
  two histories, which is also what keeps a merge small.

  This unit is a list of names and nothing else: no connection, no statement,
  no decision. The server takes the file name, the client takes the port, the
  editor takes both - so the three cannot disagree about what "mssql" means,
  which is the whole reason the table is not written down three times.

  Each profile has its OWN port, so both servers can run side by side and the
  client switches by pointing somewhere else. }

interface

uses
  mormot.core.base,
  mormot.core.unicode; // IdemPropNameU

type
  TSqlProfile = record
    /// what the server is started with, and what the combo boxes show
    Name: RawUtf8;
    /// its own, so two profiles are two processes that do not collide
    Port: RawUtf8;
    /// next to the binary; its text export is the same name with .sql
    TemplateFile: RawUtf8;
    /// the SQLite file this profile queries, next to the binary
    // - empty when the target is not a file: see TargetDatabase
    TargetFile: RawUtf8;
    /// the SQL Server database this profile queries
    // - empty for a SQLite profile. Only the name is here: which server, and
    // with which driver, is in commonserv where a client cannot see it
    TargetDatabase: RawUtf8;
    /// one line for a user interface
    Description: RawUtf8;
  end;

const
  PROFILE_DEMO   = 'demo';
  PROFILE_MSSQL = 'mssql';

  SQL_PROFILES: array[0..1] of TSqlProfile = (
    (Name: PROFILE_DEMO;
     Port: '8890';
     TemplateFile: 'templates.sqlite';
     TargetFile: 'demo.sqlite';
     TargetDatabase: '';
     Description: 'demo - demo.sqlite next to the binary'),
    (Name: PROFILE_MSSQL;
     Port: '8891';
     TemplateFile: 'templates_mssql.sqlite';
     TargetFile: '';
     TargetDatabase: 'SoaSample';
     Description: 'mssql - a SQL Server database over ODBC (see SqlServerConn)'));

/// the index of a profile, or -1 when there is no such name
// - an unknown name is never guessed: the caller says so and stops
function FindSqlProfile(const aName: RawUtf8): PtrInt;

/// every profile name, for a message or a combo box
function SqlProfileNames: TRawUtf8DynArray;

implementation

function FindSqlProfile(const aName: RawUtf8): PtrInt;
begin
  for result := 0 to high(SQL_PROFILES) do
    if IdemPropNameU(SQL_PROFILES[result].Name, aName) then
      exit;
  result := -1;
end;

function SqlProfileNames: TRawUtf8DynArray;
var
  i: PtrInt;
begin
  SetLength(result, length(SQL_PROFILES));
  for i := 0 to high(SQL_PROFILES) do
    result[i] := SQL_PROFILES[i].Name;
end;

end.
