unit AuthAccountsFromDb;

{$I mormot.defines.inc}

{ The accounts a login is checked against, in a SQLite file of their own.

  Its own file, and not demo.sqlite and not templates.sqlite, for a reason
  that shows as soon as there are two profiles: a service talks to one target
  database, but the people using it are the same people whichever target that
  is. Identities in the target would mean the same person has one account for
  demo and another for mssql.

  What is NOT here: tokens. This unit answers "is this the password of this
  account, and what may that account do" and nothing else - who signs what,
  and for how long, is the application layer's business. That keeps the one
  thing that must never leak, the password hash, in the layer that talks to
  the database and nowhere above it.

  No password is stored, ever. What is stored is a per-account salt and the
  PBKDF2-HMAC-SHA256 of the password over that salt, and the number of rounds
  is written next to it - so raising it later does not invalidate the rows
  that were written before. }

interface

uses
  SysUtils,
  mormot.core.base,
  mormot.core.text,
  mormot.core.log,
  mormot.core.os,
  mormot.core.unicode,
  mormot.crypt.core, // PBKDF2 and the CSPRNG behind the salt
  mormot.db.sql,
  mormot.db.sql.sqlite3,
  mormot.db.raw.sqlite3;

const
  AUTH_DB_FILE = 'auth.sqlite';

  /// how many PBKDF2 rounds a new account is written with
  // - stored per row, so this can be raised without touching what is there
  AUTH_PBKDF2_ROUNDS = 60000;

  { the columns are named after GlobalAuthAccount of the auth service this
    sample belongs beside, so far as the two overlap - Reads and Writes carry
    the same meaning here as they do in its token }
  AUTH_TABLE_SQL =
    'create table if not exists AuthAccount (' +
    '  UserName     text not null primary key,' +
    '  UserID       integer,' +
    '  Salt         text not null,' +
    '  PasswordHash text not null,' +
    '  Rounds       integer not null,' +
    '  Reads        integer,' +
    '  Writes       integer,' +
    '  Blocked      integer);';

type
  /// one account, as the login needs it
  // - no password anywhere in it: what comes out of the file is the hash and
  // what went into it, so a caller can check a password and cannot learn one
  TAuthAccount = record
    UserName: RawUtf8;
    /// what CallerScope binds where a template asks for the caller
    // - a number that means something in the TARGET database: in the demo,
    // 1 is customer 1, so logging in as that account and asking
    // GetMeineRechnungen returns their invoices and nobody else's
    UserID: integer;
    Salt: RawUtf8;
    PasswordHash: RawUtf8;
    Rounds: integer;
    /// bitmask of the groups this account may read with
    Reads: Int64;
    /// and write with
    Writes: Int64;
    /// set, and no password of theirs is ever right again
    // - the answer to "how do I take a token back": the account is blocked,
    // the running token dies at its own expiry, and there is no login after
    Blocked: boolean;
  end;

/// a salt no two accounts share, from the CSPRNG
function NewSalt: RawUtf8;

/// what is stored for this password and this salt
// - the same input gives the same output, which is the whole point; two
// accounts with the same password still store different bytes, because the
// salt differs
function HashPassword(const Password, Salt: RawUtf8; Rounds: integer): RawUtf8;

/// does this password belong to this account
// - false for a blocked account whatever the password is
// - the comparison is constant time: a hash is public enough that timing it
// against a guess would be a strange way in, and refusing to have the
// question costs one function call
function PasswordMatches(const Account: TAuthAccount;
  const Password: RawUtf8): boolean;

/// create the file and the two demo accounts if it is not there yet
// - an existing file is never touched: an edited account list is data, not
// something a start may overwrite
// - returns false only when the file cannot be created, and says why
function EnsureAuthDb(const FileName: TFileName; out Msg: RawUtf8): boolean;

/// the account of that name
// - false when there is none, and the caller must answer exactly as it does
// for a wrong password: which of the two it was is not the caller's business
function FindAccount(const FileName: TFileName; const UserName: RawUtf8;
  out Account: TAuthAccount): boolean;

/// write one account, replacing what is there under that name
// - the seed uses it, and so would any later "change my password"
function SaveAccount(const FileName: TFileName; const Account: TAuthAccount;
  out Msg: RawUtf8): boolean;

implementation

function NewSalt: RawUtf8;
begin
  result := TAesPrng.Main.FillRandomHex(16);
end;

function HashPassword(const Password, Salt: RawUtf8; Rounds: integer): RawUtf8;
var
  dig: TSha256Digest;
begin
  if Rounds <= 0 then
    Rounds := AUTH_PBKDF2_ROUNDS;
  Pbkdf2HmacSha256(Password, Salt, Rounds, dig);
  result := Sha256DigestToString(dig);
end;

{ what PasswordMatches does not do: tell a caller WHICH half was wrong. An
  account that does not exist and a password that does not match are one
  answer, given by the layer above - see AppAuthImplementation }

function PasswordMatches(const Account: TAuthAccount;
  const Password: RawUtf8): boolean;
var
  stored, computed: TSha256Digest;
begin
  result := false;
  if Account.Blocked or
     (Account.UserName = '') or
     (Account.PasswordHash = '') then
    exit;
  if not HexToBin(pointer(Account.PasswordHash), @stored, SizeOf(stored)) then
    exit; // the row is not a SHA-256 hex: nobody gets in on a broken row
  Pbkdf2HmacSha256(Password, Account.Salt, Account.Rounds, computed);
  { IsEqual and not a string compare: mORMot's is the xor/or pattern that
    takes the same time whatever the first differing byte is }
  result := IsEqual(stored, computed);
end;

{ add any column this version knows and the file does not - the same trade as
  MigrateTemplateDb: a file written by an earlier build keeps its accounts }
procedure MigrateAuthDb(Props: TSqlDBConnectionProperties);
var
  rows: ISqlDBRows;
  have: TRawUtf8DynArray;
begin
  rows := Props.Execute('pragma table_info(AuthAccount);', []);
  if rows = nil then
    exit;
  while rows.Step do
    AddRawUtf8(have, rows.ColumnUtf8(1)); // 1 = column name
  rows := nil;
  if FindRawUtf8(have, 'UserID', {casesensitive=}false) < 0 then
    Props.ExecuteNoResult('alter table AuthAccount add column ' +
      'UserID integer;', []);
end;

function OpenAuth(const FileName: TFileName; out Db: TSqlDatabase;
  out Props: TSqlDBSQLite3ConnectionProperties; out Msg: RawUtf8): boolean;
begin
  Db := nil;
  Props := nil;
  Msg := '';
  try
    Db := TSqlDatabase.Create(FileName, '');
    Db.LockingMode := lmNormal;
    Props := TSqlDBSQLite3ConnectionProperties.Create(Db);
    Props.ExecuteNoResult(AUTH_TABLE_SQL, []);
    MigrateAuthDb(Props);
    result := true;
  except
    on E: Exception do
    begin
      Msg := FormatUtf8('% %', [E.ClassType, E.Message]);
      FreeAndNil(Props);
      FreeAndNil(Db);
      result := false;
    end;
  end;
end;

function SaveAccount(const FileName: TFileName; const Account: TAuthAccount;
  out Msg: RawUtf8): boolean;
var
  db: TSqlDatabase;
  props: TSqlDBSQLite3ConnectionProperties;
begin
  result := OpenAuth(FileName, db, props, Msg);
  if not result then
    exit;
  try
    try
      props.ExecuteNoResult(
        'insert or replace into AuthAccount ' +
        '(UserName, UserID, Salt, PasswordHash, Rounds, Reads, Writes, ' +
        'Blocked) values (?, ?, ?, ?, ?, ?, ?, ?);',
        [Account.UserName, Account.UserID, Account.Salt, Account.PasswordHash,
         Account.Rounds, Account.Reads, Account.Writes,
         ord(Account.Blocked)]);
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

function FindAccount(const FileName: TFileName; const UserName: RawUtf8;
  out Account: TAuthAccount): boolean;
var
  db: TSqlDatabase;
  props: TSqlDBSQLite3ConnectionProperties;
  rows: ISqlDBRows;
  msg: RawUtf8;
begin
  Account := default(TAuthAccount);
  result := false;
  if (UserName = '') or
     not FileExists(FileName) then
    exit;
  if not OpenAuth(FileName, db, props, msg) then
  begin
    SynDBLog.Add.Log(sllError, 'FindAccount: %', [msg]);
    exit;
  end;
  try
    try
      rows := props.Execute('select UserName, UserID, Salt, PasswordHash, ' +
        'Rounds, Reads, Writes, Blocked from AuthAccount where UserName = ?;',
        [UserName]);
      if (rows = nil) or
         not rows.Step then
        exit;
      Account.UserName := rows.ColumnUtf8(0);
      Account.UserID := rows.ColumnInt(1);
      Account.Salt := rows.ColumnUtf8(2);
      Account.PasswordHash := rows.ColumnUtf8(3);
      Account.Rounds := rows.ColumnInt(4);
      Account.Reads := rows.ColumnInt(5);
      Account.Writes := rows.ColumnInt(6);
      Account.Blocked := rows.ColumnInt(7) <> 0;
      result := true;
    except
      on E: Exception do
        SynDBLog.Add.Log(sllError, 'FindAccount(%): % %',
          [UserName, E.ClassType, E.Message]);
    end;
  finally
    rows := nil;
    props.Free;
    db.Free;
  end;
end;

{ The two accounts the sample ships with, and what they are for.

  'admin' is in groups 1 and 2 both ways, 'user' in group 1 and reads only.
  Against the demo templates that is exactly the difference worth seeing:
  both may read GetMeineRechnungen (ReadGroups = 1), only admin may read
  GetGehaelter (ReadGroups = 2), and a template with a write mask tells the
  two apart again.

  Their password is in the documentation, and it is the same for both, which
  is fine for accounts that exist to be logged into by whoever cloned this -
  and would be inexcusable anywhere else. }
function SeedAccount(const FileName: TFileName; const UserName, Password: RawUtf8;
  UserID: integer; Reads, Writes: Int64; out Msg: RawUtf8): boolean;
var
  acc: TAuthAccount;
begin
  acc := default(TAuthAccount);
  acc.UserName := UserName;
  acc.UserID := UserID;
  acc.Salt := NewSalt;
  acc.Rounds := AUTH_PBKDF2_ROUNDS;
  acc.PasswordHash := HashPassword(Password, acc.Salt, acc.Rounds);
  acc.Reads := Reads;
  acc.Writes := Writes;
  result := SaveAccount(FileName, acc, Msg);
end;

function EnsureAuthDb(const FileName: TFileName; out Msg: RawUtf8): boolean;
var
  db: TSqlDatabase;
  props: TSqlDBSQLite3ConnectionProperties;
  rows: ISqlDBRows;
  empty: boolean;
begin
  result := OpenAuth(FileName, db, props, Msg);
  if not result then
    exit;
  empty := false;
  try
    rows := props.Execute('select count(*) from AuthAccount;', []);
    empty := (rows <> nil) and
             rows.Step and
             (rows.ColumnInt(0) = 0);
  finally
    rows := nil;
    props.Free;
    db.Free;
  end;
  if not empty then
    exit; // accounts are there - a start never touches them
  { the UserIDs are customers of the demo database, so a scoped template has
    something to scope to: log in as user and GetMeineRechnungen returns
    customer 1's three invoices and nobody else's }
  result := SeedAccount(FileName, 'admin', 'demo', 2, 3, 3, Msg) and
            SeedAccount(FileName, 'user',  'demo', 1, 1, 0, Msg);
  if result then
    SynDBLog.Add.Log(sllInfo, 'EnsureAuthDb: % created with admin and user',
      [FileName]);
end;

end.
