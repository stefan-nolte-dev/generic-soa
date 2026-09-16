unit AppAuthImplementation;

{$I mormot.defines.inc}

{ Logging in - the only door that opens without a token, and the only place
  a token is made.

  Two halves, and neither knows the other's: the accounts live in the
  infrastructure layer (AuthAccountsFromDb), which knows about salts and
  hashes and nothing about tokens; the signing lives in AppCallerToken, which
  knows about tokens and nothing about passwords. This unit is the sentence
  that joins them, and it is short on purpose.

  What it never does is say WHY a login failed. An unknown user, a wrong
  password and a blocked account are one answer - the difference is only ever
  useful to somebody who is guessing. It goes to the log, where the person
  who runs the server can see it. }

interface

uses
  SysUtils,
  mormot.core.base,
  mormot.core.log,
  mormot.core.text,
  mormot.core.interfaces,
  AppSqlServices,
  AppCallerToken,
  AuthAccountsFromDb,
  DomSqlServices, // TSqlCaller: WhoAmI answers about the caller it made
  SqlAuthTypes,
  SqlStatus;

type

  { TAppAuthTool }

  TAppAuthTool = class(TInterfacedObject, IAppAuthTool)
  private
    fAuthFile: TFileName;
  public
    constructor Create(const aAuthFile: TFileName); reintroduce;
    function Login(const UserName, Password: RawUtf8;
      out Token: TSessionToken): TSqlStatus;
    function WhoAmI(out UserName: RawUtf8; out Reads, Writes: Int64;
      out SecondsLeft: integer): TSqlStatus;
  end;

implementation

constructor TAppAuthTool.Create(const aAuthFile: TFileName);
begin
  inherited Create;
  if aAuthFile = '' then
    raise ESynException.Create('TAppAuthTool.Create('''')');
  fAuthFile := aAuthFile;
end;

function TAppAuthTool.Login(const UserName, Password: RawUtf8;
  out Token: TSessionToken): TSqlStatus;
var
  account: TAuthAccount;
  payload: TAuthPayload;
  why: RawUtf8;
begin
  Token := '';
  result := sqlNeedsLogin;
  { the account is looked up even when the name is empty and the password is
    checked even when there is no account: not for correctness - the answer
    is the same either way - but so that guessing a name is not faster than
    guessing a password }
  if not FindAccount(fAuthFile, UserName, account) then
  begin
    why := 'no such account';
    account := default(TAuthAccount);
  end
  else if account.Blocked then
    why := 'the account is blocked'
  else if not PasswordMatches(account, Password) then
    why := 'wrong password'
  else
    why := '';
  if why <> '' then
  begin
    { the reason belongs to whoever runs the server, and to nobody else }
    TSynLog.Add.Log(sllWarning, 'Login(%): %', [UserName, why]);
    { and the failing path pays the same price as the succeeding one, so a
      name that does not exist cannot be told apart by a stopwatch }
    if account.Salt = '' then
      HashPassword(Password, 'no-such-account', AUTH_PBKDF2_ROUNDS);
    exit;
  end;
  payload := default(TAuthPayload);
  payload.UserID := account.UserID;
  payload.UserName := account.UserName;
  payload.Reads := account.Reads;
  payload.Writes := account.Writes;
  Token := IssueToken(payload);
  if Token = '' then
  begin
    TSynLog.Add.Log(sllError, 'Login(%): no signer', [UserName]);
    exit(sqlFailed);
  end;
  TSynLog.Add.Log(sllInfo, 'Login(%): rd=% wr=%',
    [account.UserName, account.Reads, account.Writes]);
  result := sqlOk;
end;

function TAppAuthTool.WhoAmI(out UserName: RawUtf8;
  out Reads, Writes: Int64; out SecondsLeft: integer): TSqlStatus;
var
  caller: TSqlCaller;
begin
  UserName := '';
  Reads := 0;
  Writes := 0;
  SecondsLeft := 0;
  caller := CurrentCaller;
  if not caller.Authenticated then
    exit(sqlNeedsLogin);
  UserName := caller.UserName;
  Reads := caller.Reads;
  Writes := caller.Writes;
  SecondsLeft := TokenSecondsLeft(CurrentToken);
  result := sqlOk;
end;

end.
