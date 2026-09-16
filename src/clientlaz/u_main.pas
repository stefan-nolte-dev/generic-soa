unit u_main;

{$mode objfpc}{$H+}
{ The source of this unit is UTF-8, and its literals carry umlauts. Without
  this the compiler reads them as the system codepage and re-encodes them on
  the way into a RawUtf8 parameter, which turns "Ü" into "Ã" on screen. }
{$codepage UTF8}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls, ExtCtrls,
  Buttons,
  mormot.core.base,
  AppSqlServices,
  AppSqlClient,
  SqlStatus, // TSqlStatus appears in ShowResult below
  ClientTests;

type

  { TFormMain }

  TFormMain = class(TForm)
    ButtonActions: TButton;
    ButtonLogin: TButton;
    ButtonRun: TButton;
    ButtonTest: TButton;
    ComboAction: TComboBox;
    ComboProfile: TComboBox;
    EditBounds: TEdit;
    EditServer: TEdit;
    LabelAction: TLabel;
    LabelBounds: TLabel;
    LabelProfile: TLabel;
    LabelServer: TLabel;
    LabelView: TLabel;
    Memo1: TMemo;
    MemoLog: TMemo;
    PanelTop: TPanel;
    SpeedJson: TSpeedButton;
    SpeedTable: TSpeedButton;
    SplitterResult: TSplitter;
    procedure ComboProfileChange(Sender: TObject);
    procedure ButtonActionsClick(Sender: TObject);
    procedure ButtonLoginClick(Sender: TObject);
    procedure ButtonRunClick(Sender: TObject);
    procedure SpeedViewClick(Sender: TObject);
    procedure ButtonTestClick(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure Splitter1CanOffset(Sender: TObject; var NewOffset: Integer;
      var Accept: Boolean);
  private
    { the last result, kept so the two view buttons can redraw it without
      asking the server again - the editor keeps its last JSON for the same
      reason }
    fActionKey: RawUtf8;
    fStatus: TSqlStatus;
    fJson: RawUtf8;
    fHasResult: boolean;
    function Connect: boolean;
    /// the login window, and what comes of it
    // - Connected says whether a connection is already open: the login is
    // used both on its own and in the middle of a refused call
    function ShowLogin(Connected: boolean): boolean;
    /// a refused call, answered with the login window and one retry
    function AskAgain(Status: TSqlStatus): boolean;
    /// who is logged in, in the title bar - the top row has no room left
    procedure ShowLoginState;
    /// ask the server which keys it knows, and offer them
    // - the contract has one method for this, so a client can be pointed at
    // a server it knows nothing about and still show what is on offer
    procedure LoadActions;
    /// take one result set and put it in front of the user
    procedure ShowResult(const ActionKey: RawUtf8; Status: TSqlStatus;
      const Json: RawUtf8);
    /// draw the result already held, in whichever view is selected
    // - the same two views the editor offers: the table is what you read,
    // the JSON is what actually came over the wire
    procedure RenderResult;
  end;

var
  FormMain: TFormMain;

implementation

{$R *.lfm}

{ TFormMain }
uses u_client_parsing, ClientDtos, WriteDtos, u_jsontable, u_logindialog,
  SqlProfiles, SqlAuthTypes, mormot.core.variants, Variants;

procedure TFormMain.FormCreate(Sender: TObject);
var
  i: PtrInt;
begin
  { one entry per profile, from the same table the server and the editor read
    - each profile has its own port, so both servers may run at once and
    switching means pointing somewhere else }
  ComboProfile.Items.BeginUpdate;
  try
    for i := 0 to high(SQL_PROFILES) do
      ComboProfile.Items.Add(string(SQL_PROFILES[i].Description));
  finally
    ComboProfile.Items.EndUpdate;
  end;
  ComboProfile.ItemIndex := 0;
  ComboProfileChange(nil);
  MemoLog.Clear;
  MemoLog.Lines.Add('Server starten, dann "Aktionen vom Server holen".');
  MemoLog.Lines.Add('Verlangt der Server ein Token (Start mit "token"), ' +
    'erst anmelden.');
  ShowLoginState;
end;

procedure TFormMain.ComboProfileChange(Sender: TObject);
var
  i: integer;
begin
  i := ComboProfile.ItemIndex;
  if i < 0 then
    exit;
  EditServer.Text := 'localhost:' + string(SQL_PROFILES[i].Port);
  { the keys of the other profile are unknown here - an old list would only
    produce sqlUnknownKey }
  ComboAction.Items.Clear;
  ComboAction.Text := '';
end;

{ Who is logged in, in the title bar. The top row is full, and a login state
  that is only in the log scrolls away exactly when it matters. }
procedure TFormMain.ShowLoginState;
const
  TITLE = 'SQL Template Service - Test Client';
var
  user: RawUtf8;
  reads, writes: Int64;
  seconds: integer; // not 'left': TControl has a Left, and it wins here
begin
  if not LoggedIn then
  begin
    Caption := TITLE + ' - nicht angemeldet';
    ButtonLogin.Caption := 'Anmelden...';
    exit;
  end;
  ButtonLogin.Caption := 'Abmelden';
  Caption := TITLE + ' - ' + string(ClientUser);
  { and what the server says about the token, which is the half the client
    cannot know: masks and remaining time. This connects, so it belongs
    outside a call, never into the middle of one }
  if not Connect then
    exit;
  try
    if AuthTool.WhoAmI(user, reads, writes, seconds) = sqlOk then
      Caption := Format('%s - %s  rd=%d wr=%d  noch %d min',
        [TITLE, string(user), reads, writes, seconds div 60]);
  finally
    DisconnectClient;
  end;
end;

{ The login window. Connected says whether the caller already holds a
  connection - this is used both from the button, which holds none, and from
  the middle of a call that was refused, which does. }
function TFormMain.ShowLogin(Connected: boolean): boolean;
var
  user, pass, msg: RawUtf8;
begin
  result := false;
  user := ClientUser; // the name is offered again, the password never is
  pass := '';
  if not AskForLogin(RawUtf8(Trim(EditServer.Text)), user, pass) then
    exit;
  if not Connected then
    if not Connect then
      exit;
  try
    result := LoginClient(user, pass, msg);
    if result then
      MemoLog.Lines.Add('Angemeldet als ' + string(user) + '.')
    else
      MemoLog.Lines.Add(string(msg));
  finally
    if not Connected then
      DisconnectClient;
  end;
end;

{ A call that came back sqlNeedsLogin: the token is missing, expired or from
  a server that has since restarted. Ask once, and let the caller try again -
  anything else and the user has to guess what to press. }
function TFormMain.AskAgain(Status: TSqlStatus): boolean;
begin
  result := false;
  if Status <> sqlNeedsLogin then
    exit;
  MemoLog.Lines.Add('Der Server verlangt eine Anmeldung.');
  { nur anmelden. Die Titelzeile fragt der Aufrufer nach, wenn er seine
    Verbindung wieder losgelassen hat - hier steht sie noch offen }
  result := ShowLogin({connected=}true);
end;

procedure TFormMain.ButtonLoginClick(Sender: TObject);
begin
  if LoggedIn then
  begin
    LogoutClient;
    MemoLog.Lines.Add('Abgemeldet - das Token ist vergessen.');
    ShowLoginState;
    exit;
  end;
  if ShowLogin({connected=}false) then
    ShowLoginState;
end;

procedure TFormMain.LoadActions;
var
  keys: TRawUtf8DynArray;
  who: RawUtf8;
  reads, writes: Int64;
  seconds: integer;
  i: PtrInt;
begin
  if not Connect then
    exit;
  try
    keys := SqlTool.AvailableActions;
    if keys = nil then
    begin
      { an empty list is not an error and not necessarily an empty server:
        an unauthenticated caller gets one too. WhoAmI says which it is }
      if AuthTool.WhoAmI(who, reads, writes, seconds) = sqlNeedsLogin then
        if AskAgain(sqlNeedsLogin) then
          keys := SqlTool.AvailableActions;
    end;
  finally
    DisconnectClient;
  end;
  ComboAction.Items.BeginUpdate;
  try
    ComboAction.Items.Clear;
    for i := 0 to high(keys) do
      ComboAction.Items.Add(string(keys[i]));
  finally
    ComboAction.Items.EndUpdate;
  end;
  if ComboAction.Items.Count > 0 then
    ComboAction.ItemIndex := 0;
  MemoLog.Lines.Add(Format('%d Aktion(en) von %s',
    [length(keys), EditServer.Text]));
end;

procedure TFormMain.ButtonActionsClick(Sender: TObject);
begin
  MemoLog.Clear;
  Screen.Cursor := crHourGlass;
  try
    LoadActions;
  except
    on E: Exception do
      MemoLog.Lines.Add('FAILED: ' + E.ClassName + ' - ' + E.Message);
  end;
  ShowLoginState;
  Screen.Cursor := crDefault;
end;

{ The generic run: a key, a list of bounds, and whatever comes back. No type
  of this client is involved - which is the reason it can be pointed at either
  profile without knowing a thing about the database behind it. }
procedure TFormMain.ButtonRunClick(Sender: TObject);
var
  key, json, bounds: RawUtf8; // "Action" is taken: TControl has one
  values: variant;
  erg: TSqlStatus;
begin
  key := RawUtf8(Trim(ComboAction.Text));
  if key = '' then
  begin
    MemoLog.Lines.Add('Erst eine Aktion wählen.');
    exit;
  end;
  bounds := RawUtf8(Trim(EditBounds.Text));
  if bounds = '' then
    bounds := '[]';
  MemoLog.Clear;
  Memo1.Clear;
  Screen.Cursor := crHourGlass;
  try
    { the bounds are typed by hand as JSON, so a wrong one is a wrong one -
      the declared ParamTypes of the template turn them into what the driver
      needs, which is exactly what a hand-typed value is there to show }
    values := _JsonFast(bounds);
    if VarIsEmptyOrNull(values) then
      values := _ArrFast([]);
    if not Connect then
      exit;
    try
      json := '';
      erg := SqlTool.GetJsonFromAction(key, values, json);
      { no token, an expired one, or one from a server that has restarted
        since: ask, and run the same call again with what comes back }
      if AskAgain(erg) then
        erg := SqlTool.GetJsonFromAction(key, values, json);
      MemoLog.Lines.Add(string(key) + ' ' + string(bounds) +
        ' -> ' + string(ToText(erg)));
      { the commonest reason by far, and the one the bare status does not
        explain: a template with a ? was called with an empty list }
      if (erg = sqlBadParams) and
         (bounds = '[]') then
        MemoLog.Lines.Add('Diese Aktion erwartet Parameter. Bounds als ' +
          'JSON-Liste angeben, z. B. [100] oder ["Fr%"].');
      ShowResult(key, erg, json);
    finally
      DisconnectClient;
    end;
  except
    on E: Exception do
      MemoLog.Lines.Add('FAILED: ' + E.ClassName + ' - ' + E.Message);
  end;
  ShowLoginState;
  Screen.Cursor := crDefault;
end;

procedure TFormMain.ShowResult(const ActionKey: RawUtf8; Status: TSqlStatus;
  const Json: RawUtf8);
begin
  fActionKey := ActionKey;
  fStatus := Status;
  fJson := Json;
  fHasResult := true;
  RenderResult;
end;

procedure TFormMain.RenderResult;
begin
  Memo1.Lines.BeginUpdate;
  try
    Memo1.Clear;
    if not fHasResult then
      exit;
    Memo1.Lines.Add(string(fActionKey) + '  ->  ' + string(ToText(fStatus)));
    Memo1.Lines.Add('');
    if SpeedJson.Down then
      { the bytes the server put on the wire - all it ever sends, with no
        type of its own travelling along }
      Memo1.Lines.Add(JsonPretty(fJson))
    else
      Memo1.Lines.Add(JsonAsTextTable(fJson));
  finally
    Memo1.Lines.EndUpdate;
  end;
end;

procedure TFormMain.SpeedViewClick(Sender: TObject);
begin
  RenderResult; // no second call to the server: the same bytes, drawn twice
end;

procedure TFormMain.Splitter1CanOffset(Sender: TObject; var NewOffset: Integer;
  var Accept: Boolean);
begin

end;

function TFormMain.Connect: boolean;
var
  host, port: string;
  p, i: integer;
begin
  host := Trim(EditServer.Text);
  port := string(SQL_PROFILES[0].Port); // only when the field carries none
  p := Pos(':', host);
  if p > 0 then
  begin
    port := Copy(host, p + 1, MaxInt);
    host := Copy(host, 1, p - 1);
  end;
  result := ConnectClient(RawUtf8(host), RawUtf8(port));
  if result then
    exit;
  MemoLog.Lines.Add('Kein Dienst auf ' + host + ':' + port + '.');
  if LastConnectError <> '' then
    MemoLog.Lines.Add('  ' + string(LastConnectError));
  { each profile has its own port, so the commonest cause is that the other
    server was started and this one was not }
  i := ComboProfile.ItemIndex;
  if i >= 0 then
    MemoLog.Lines.Add('Starten mit:  ./soa_sql_templates_server ' +
      string(SQL_PROFILES[i].Name));
end;

procedure TFormMain.ButtonTestClick(Sender: TObject);
var
  arr: TDtoMitarbeiterArray;
  rec: TDtoArtikel;
  json: RawUtf8;
  erg: TSqlStatus;
  i: integer;
begin
  rec.ID := 4;
  rec.ArtName := 'Sonnenschirm-Wetterfest';
  rec.ArtNr := 4;
  rec.Kind := 'Aussenbereich';
  arr := nil;
  MemoLog.Clear;
  Memo1.Clear;
  Screen.Cursor := crHourGlass;
  MemoLog.Lines.BeginUpdate;
  try
    if not Connect then
      exit;
    try
      { the write direction: one whole record, no statement behind the key }
    //  erg := WriteRecord('OrmUpdateTDTOArtikel', rec, TypeInfo(TDtoArtikel));
    //  MemoLog.Lines.Add('OrmUpdateTDTOArtikel -> ' + string(ToText(erg)));

      { the read direction, and what Memo1 shows - a hundred rows, which is
        what the table view is for. One line to point it at another key }
      erg := ParseDynArrayJson('GetAlleMitarbeiter', _ArrFast([]),
        arr, TypeInfo(TDtoMitarbeiterArray), json);
      MemoLog.Lines.Add('GetAlleMitarbeiter -> ' + string(ToText(erg)) +
        ', ' + IntToStr(length(arr)) + ' row(s)');
      ShowResult('GetAlleMitarbeiter', erg, json);

      { and the proof that it is not only text: the same rows, typed, out of
        a record the server has never heard of }
      for i := 0 to 2 do
        if i <= high(arr) then
          MemoLog.Lines.Add(Format('  arr[%d].Name = %s  .Gehalt = %.2f',
            [i, string(arr[i].Name), arr[i].Gehalt]));
    finally
      DisconnectClient;
    end;
  except
    on E: Exception do
      MemoLog.Lines.Add('FAILED: ' + E.ClassName + ' - ' + E.Message);
  end;
  MemoLog.Lines.EndUpdate;
  Screen.Cursor := crDefault;
end;

end.
