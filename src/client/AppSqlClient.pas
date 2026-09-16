unit AppSqlClient;

{$I mormot.defines.inc}

{ Connection to the sample server, and the token it carries.

  Nothing here knows about customers, invoices or any query: the client holds
  two interfaces - one for the queries, one for logging in - and that stays
  true however many statements the server ends up serving.

  The token is kept in a variable of this unit and not in the connection,
  because this client connects and disconnects around every single call. It
  is put into the Authorization header once per connect, and from then on
  every call of that connection carries it without a single call site knowing
  that it exists. }

interface

uses
  SysUtils,
  mormot.core.base,
  mormot.core.text,
  mormot.core.interfaces,
  mormot.net.http, // AuthorizationBearer: the one line the token needs
  mormot.soa.core,
  mormot.orm.core,
  mormot.rest.http.client,
  SqlAuthTypes,
  SqlStatus,
  AppSqlServices;

var
  /// the resolved service - used by ParseDynArray in u_client_parsing
  SqlTool: IAppSqlTool;
  /// the login, resolved by the same connect
  AuthTool: IAppAuthTool;
  /// what the last login returned, or '' - the header is built from it
  // - not written to disk anywhere: it lives as long as the program does,
  // and the server's own copy dies with the server
  ClientToken: TSessionToken;
  /// who that token says we are, for a status line
  ClientUser: RawUtf8;
  /// why the last ConnectClient returned false
  // - a server that is not there raises inside the socket layer and again in
  // the service factory; neither message says which address was tried, and
  // both stop the IDE. So it is caught here and turned into a value - the
  // same choice the service contract makes for everything else
  LastConnectError: RawUtf8;

/// connect and resolve the two interfaces
// - a token from an earlier login is put into the header here, so every call
// of this connection carries it
function ConnectClient(const aServer: RawUtf8 = 'localhost';
  const aPort: RawUtf8 = APPSQL_PORT): boolean;
procedure DisconnectClient;

/// log in, and keep the token for every later connect
// - expects a connection: the caller connects, logs in, and may disconnect
// again - the token outlives the connection
// - false with Msg set when the server refused; which of the three reasons
// it was is deliberately not said, here or there
function LoginClient(const UserName, Password: RawUtf8;
  out Msg: RawUtf8): boolean;

/// forget the token
procedure LogoutClient;

/// is there a token at all
// - says nothing about whether it is still valid: only the server knows
function LoggedIn: boolean;

implementation

var
  Model: TOrmModel;
  Client: TRestHttpClient;

function ConnectClient(const aServer, aPort: RawUtf8): boolean;
begin
  result := false;
  LastConnectError := '';
  try
    { An empty model: this client uses services only, no ORM table is involved
      on either side }
    Model := TOrmModel.Create([], APPSQL_ROOT);
    Client := TRestHttpClient.Create(aServer, aPort, Model);
    Client.Model.Owner := Client;
    result := Client.ServiceDefine([IAppSqlTool, IAppAuthTool], sicShared) and
              Client.Services.Resolve(TypeInfo(IAppSqlTool), SqlTool) and
              Client.Services.Resolve(TypeInfo(IAppAuthTool), AuthTool);
    if not result then
      LastConnectError := 'the service is not published there';
    if result and
       (ClientToken <> '') then
      { mORMot's own place for "your own header, e.g. a JWT as bearer" - set
        once, and every call of this connection carries it }
      Client.SessionHttpHeader := AuthorizationBearer(ClientToken);
  except
    on E: Exception do
      LastConnectError := FormatUtf8('% %', [E.ClassType, E.Message]);
  end;
  if not result then
    DisconnectClient;
end;

function LoginClient(const UserName, Password: RawUtf8;
  out Msg: RawUtf8): boolean;
var
  token: TSessionToken;
  status: TSqlStatus;
begin
  Msg := '';
  result := false;
  if AuthTool = nil then
  begin
    Msg := 'Nicht verbunden.';
    exit;
  end;
  try
    status := AuthTool.Login(UserName, Password, token);
  except
    on E: Exception do
    begin
      Msg := FormatUtf8('% %', [E.ClassType, E.Message]);
      exit;
    end;
  end;
  if (status <> sqlOk) or
     (token = '') then
  begin
    { the server says no more than this, and neither does the window: the
      difference between an unknown name and a wrong password is only ever
      useful to somebody who is guessing }
    Msg := 'Anmeldung abgelehnt.';
    exit;
  end;
  ClientToken := token;
  ClientUser := UserName;
  { and from this call on, not only from the next connect }
  if Client <> nil then
    Client.SessionHttpHeader := AuthorizationBearer(ClientToken);
  result := true;
end;

procedure LogoutClient;
begin
  ClientToken := '';
  ClientUser := '';
  if Client <> nil then
    Client.SessionHttpHeader := '';
end;

function LoggedIn: boolean;
begin
  result := ClientToken <> '';
end;

procedure DisconnectClient;
begin
  SqlTool := nil;
  AuthTool := nil;
  FreeAndNil(Client); // frees the model as well, see Model.Owner above
  Model := nil;
end;

end.
