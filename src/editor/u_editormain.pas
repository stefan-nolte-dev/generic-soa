unit u_editormain;

{ The template editor.

  A developer tool, and only that: it edits templates.sqlite, runs a statement
  against a database it connects to itself, and writes the record declaration
  that receives the result. It does not belong next to the client on a user's
  machine.

  Three things it deliberately does not do. It never commits a write - see
  EditorExec. It never asks the server to run unregistered SQL - the server
  has no method for that, and giving it one would undo the sample. And it
  holds neither database open: every template operation opens the file and
  closes it again, so a running server and this editor do not fight. }

{$mode objfpc}{$H+}
{ The source of this unit is UTF-8, and its literals carry umlauts. Without
  this the compiler reads them as the system codepage and re-encodes them on
  the way into a RawUtf8 parameter, which turns "Ü" into "Ã" on screen. }
{$codepage UTF8}

interface

uses
  Classes, SysUtils, Variants, Forms, Controls, Graphics, Dialogs, StdCtrls,
  ExtCtrls, ComCtrls, Grids, Clipbrd,
  mormot.core.base,
  mormot.core.os,   // for Executable.ProgramFilePath
  mormot.core.text,
  mormot.core.unicode,
  mormot.core.json,
  mormot.core.rtti, // for the fields of a record declared in its row
  mormot.core.variants,
  SqlStatus,
  SqlTemplateTypes,
  SqlTemplatesFromDb,
  AppSqlServices,
  AppSqlClient,
  SqlParamTypes,
  SqlParamRules,
  SqlProfiles,
  SqlServerConn,
  SqlBounds,
  EditorDb,
  EditorExec,
  EditorSweep,  // dieselben Prüfungen, über den ganzen Satz
  TemplateStore,
  SqlRecordBind, // the very code the server generates a record statement with
  RecordDialog,  // one dialog built from whatever fields the type turns out
  u_logindialog, // the client's login window - the same one, in src/ui
  SqlAuthTypes,
  DtoCodeGen;

type
  /// how loud the one always-visible line should be
  // - a check that failed is red, and nothing else is: a hint is not a
  // failure, and a user who is told in red that something is worth knowing
  // learns to read red as "ignore me"
  TStatusLevel = (
    stOk,
    stHint,
    stBad);

  { TFormEditor }

  TFormEditor = class(TForm)
    ButtonAddBound: TButton;
    ButtonBrowseTarget: TButton;
    ButtonBrowseTemplates: TButton;
    ButtonCheck: TButton;
    ButtonCheckAll: TButton;
    ButtonTestBoundsFromJson: TButton;
    ButtonConnect: TButton;
    ButtonCopyDto: TButton;
    ButtonDelete: TButton;
    ButtonGenerate: TButton;
    ButtonLoadList: TButton;
    ButtonClearBounds: TButton;
    ButtonTypesFromBounds: TButton;
    ButtonNew: TButton;
    ButtonReloadServer: TButton;
    ButtonSave: TButton;
    ButtonSqlFromRecord: TButton;
    ButtonCreateTable: TButton;
    ComboDialect: TComboBox;
    LabelDialect: TLabel;
    ButtonTest: TButton;
    cbRollback: TCheckBox;
    cbViaServer: TCheckBox;
    CheckInline: TCheckBox;
    CheckRawJson: TCheckBox;
    ComboBoundKind: TComboBox;
    ComboEngine: TComboBox;
    ComboProfile: TComboBox;
    EditBoundValue: TEdit;
    EditBoundsJson: TEdit;
    EditFilter: TEdit;
    EditRules: TEdit;
    EditTestBounds: TEdit;
    EditKey: TEdit;
    EditKeyField: TEdit;
    EditParamTypes: TEdit;
    CheckGenerateSql: TCheckBox;
    EditRecordType: TEdit;
    LabelProfile: TLabel;
    MemoRecordDecl: TMemo;
    EditReadGroups: TEdit;
    EditWriteGroups: TEdit;
    EditPassword: TEdit;
    EditServer: TEdit;
    EditTarget: TEdit;
    EditTemplates: TEdit;
    EditTypeName: TEdit;
    EditUser: TEdit;
    GridResult: TStringGrid;
    LabelBoundHint: TLabel;
    LabelBounds: TLabel;
    LabelBoundsJson: TLabel;
    LabelEngine: TLabel;
    LabelKey: TLabel;
    EditOrderBy: TEdit;
    LabelFilter: TLabel;
    LabelRules: TLabel;
    LabelTestBounds: TLabel;
    LabelKeyField: TLabel;
    LabelOrderBy: TLabel;
    LabelParamTypes: TLabel;
    LabelRecordDecl: TLabel;
    ButtonRecordDialog: TButton;
    LabelCallerScope: TLabel;
    EditCallerScope: TEdit;
    LabelRecordType: TLabel;
    LabelRights: TLabel;
    LabelRightsHint: TLabel;
    LabelPassword: TLabel;
    LabelServer: TLabel;
    LabelStatus: TLabel;
    LabelSql: TLabel;
    EditKeyFilter: TEdit;
    LabelKeyFilter: TLabel;
    LabelTarget: TLabel;
    LabelTemplates: TLabel;
    LabelTypeName: TLabel;
    LabelUser: TLabel;
    ListKeys: TListBox;
    MemoBounds: TMemo;
    MemoDto: TMemo;
    MemoJson: TMemo;
    MemoLog: TMemo;
    MemoSql: TMemo;
    PagesResult: TPageControl;
    PanelActions: TPanel;
    PanelDtoTop: TPanel;
    PanelEdit: TScrollBox;
    PanelJsonTop: TPanel;
    PanelKeys: TPanel;
    PanelKeysBottom: TPanel;
    PanelTop: TPanel;
    SplitterEdit: TSplitter;
    Splitter1: TSplitter;
    TabDto: TTabSheet;
    TabJson: TTabSheet;
    TabLog: TTabSheet;
    TabTable: TTabSheet;
    procedure ButtonAddBoundClick(Sender: TObject);
    procedure ButtonBrowseTargetClick(Sender: TObject);
    procedure ButtonBrowseTemplatesClick(Sender: TObject);
    procedure ButtonCheckClick(Sender: TObject);
    procedure ButtonCheckAllClick(Sender: TObject);
    procedure ButtonTestBoundsFromJsonClick(Sender: TObject);
    procedure ButtonTypesFromBoundsClick(Sender: TObject);
    procedure ButtonClearBoundsClick(Sender: TObject);
    procedure ButtonConnectClick(Sender: TObject);
    procedure ComboProfileChange(Sender: TObject);
    procedure ComboEngineChange(Sender: TObject);
    procedure cbRollbackChange(Sender: TObject);
    procedure cbViaServerChange(Sender: TObject);
    procedure ButtonCopyDtoClick(Sender: TObject);
    procedure ButtonDeleteClick(Sender: TObject);
    procedure ButtonGenerateClick(Sender: TObject);
    procedure ButtonLoadListClick(Sender: TObject);
    procedure ButtonNewClick(Sender: TObject);
    procedure ButtonRecordDialogClick(Sender: TObject);
    procedure ButtonReloadServerClick(Sender: TObject);
    procedure ButtonSaveClick(Sender: TObject);
    procedure ButtonSqlFromRecordClick(Sender: TObject);
    procedure ButtonCreateTableClick(Sender: TObject);
    procedure ButtonTestClick(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure CheckRawJsonChange(Sender: TObject);
    procedure CheckGenerateSqlChange(Sender: TObject);
    procedure ComboBoundKindChange(Sender: TObject);
    procedure EditKeyFilterChange(Sender: TObject);
    procedure ListKeysSelectionChange(Sender: TObject; User: boolean);
    procedure MemoBoundsChange(Sender: TObject);
  private
    fDb: TEditorDb;
    fStore: TTemplateStore;
    fRecs: TSqlRecArray;
    fLastJson: RawUtf8;
    /// the last record entered in the dialog, per action key
    // - kept for the session only: it is what was typed, not what is saved.
    // The dialog opens on it instead of on empty fields, and the JSON goes
    // into the "so würde es reisen" box, from where one press puts it in
    // TestBounds
    fLastRecordJson: TDocVariantData;
    fListLoaded: boolean;
    /// the two boxes set each other, and neither may answer the other's move
    fSyncingBoxes: boolean;
    procedure Log(const Msg: RawUtf8); // not 'Text': TControl.Text is in scope
    /// the one line that is always visible, whichever tab is in front
    procedure Say(const Msg: RawUtf8; Level: TStatusLevel);
    /// what is open, in the title bar - the top row has no room for it
    procedure ShowConnection;
    /// what the Rollback box says a write is to end with
    function WriteEnding: TWriteEnd;
    /// the parameters as they stand in the memo, with their declared types
    function ReadBounds(out Bounds: TBoundArray): boolean;
    /// keep the JSON preview honest after every change to the list
    procedure RefreshBoundsJson;
    /// ParamTypes parses, and says as many parameters as the statement has
    function CheckDeclaration(out Msg: RawUtf8): boolean;
    /// the Rules column against the values in the memo
    // - the same reading and the same checks the server runs, so what is
    // refused here is what would be refused there
    function RulesHold(const Rec: TSqlRec; const Bounds: TBoundArray;
      out Msg: RawUtf8): boolean;
    /// the record type resolves, and what a generated statement would be
    function CheckRecordType(out Msg: RawUtf8): boolean;
    /// the last net: whatever nobody else caught lands here
    // - without it the LCL decides, and its decision outside the message loop
    // - while a form is being destroyed, say - is to end the program. A driver
    // whose server went away raises exactly there, so an editor that dies on
    // a closed tunnel is what that costs
    procedure AppException(Sender: TObject; E: Exception);
    /// drop the connection and say what the driver said on the way out
    procedure DropConnection;
    /// ask for a name and a password, and log the server in
    // - the editor talks to the server in one place, and this is the other
    // half of it: with the server started as "token", a reload without a
    // token is refused like anything else
    function ServerLogin: boolean;
    /// open the connection to the server named in the top row
    // - the same two lines the reload needs, and the run through the server
    function ServerConnect: boolean;
    /// run this template the way a client would - through the server
    // - what the editor's own "Testen" cannot show: the rights masks,
    // CallerScope and the rules all live in the domain layer, and the
    // editor's run goes past it straight onto the connection
    // - only a SAVED key can go this way: the server runs registered
    // templates and has no method for anything else, which is the property
    // the whole sample rests on
    procedure RunThroughServer(const Rec: TSqlRec; const Bounds: TBoundArray);
    /// the record a "Testen" on an insert or an update would send
    // - in the order the window itself reads: the JSON box, because that is
    // what the maintainer is looking at; then what the dialog last produced
    // for this key; then the TestBounds column
    // - false when none of the three holds an object, and Msg says so
    function RecordJsonToTest(const Rec: TSqlRec; out Json: RawUtf8;
      out Msg: RawUtf8): boolean;
    /// send one record's JSON through the server, as a client does
    // - the other half of the run through the server: a record write carries
    // no parameter list, so it cannot go through RunThroughServer - what
    // travels is the JSON the record dialog produced
    // - the statement is generated in the server from the type and the key,
    // so this tests the generator that will actually run, over the wire
    procedure RunRecordThroughServer(const Rec: TSqlRec; const Json: RawUtf8);
    /// fill the key list from fRecs, through the filter box
    // - the list index stops being the index into fRecs as soon as a filter
    // hides a line, so each line carries its own position in Objects[]
    procedure FillKeyList;
    /// write the text representation next to the database, after every change
    // - so the .sql file cannot fall behind the .sqlite: both are in version
    // control, and only one of them has a readable diff
    procedure AutoExport;
    procedure ShowResult(const Res: TRunResult);
    procedure FillGrid(const Json: RawUtf8);
    /// put fLastJson in the memo, formatted or exactly as it arrived
    procedure RenderJson;
    function CurrentRec: TSqlRec;
    function TemplateFile: TFileName;
  end;

var
  FormEditor: TFormEditor;

implementation

{$R *.lfm}

const
  { the name of the window; what is connected is appended to it }
  EDITOR_TITLE = 'SQL Template Editor';

{ Where to look for the sample's databases by default.

  Not the working directory: started from the IDE that is the project folder,
  and a bare 'demo.sqlite' would be searched there. Not the raw program folder
  either - on macOS Lazarus can start the program through its .app bundle, and
  the executable inside it is only a symlink back to bin/, so the program
  folder would be .../Contents/MacOS/. mORMot does not strip that, so this
  does. }
function DefaultDataFolder: string;
const
  BUNDLE = '.app' + PathDelim + 'Contents' + PathDelim + 'MacOS' + PathDelim;
var
  p: SizeInt;
begin
  result := Executable.ProgramFilePath;
  p := Pos(BUNDLE, result);
  if p > 0 then
    { .../bin/name.app/Contents/MacOS/ -> .../bin/ }
    result := ExtractFilePath(copy(result, 1, p - 1));
end;

{ Which driver a profile's target needs. The profile table decides it - a
  database name is ODBC, a file name is SQLite - so the two drop-downs cannot
  end up meaning different databases. }
function ProfileEngine(const Profile: TSqlProfile): TEditorEngine;
begin
  if Profile.TargetDatabase <> '' then
    result := engOdbcString
  else
    result := engSQLite;
end;

{ And which spelling that profile's database wants, for the drop-down's
  starting value. Same table, same two cases - and unlike the driver above
  this one is only a suggestion: the statement is generated for whichever
  database the person picks, connected or not. }
function ProfileDialect(const Profile: TSqlProfile): TDdlDialect;
begin
  if Profile.TargetDatabase <> '' then
    result := ddMSSQL
  else
    result := ddSQLite;
end;

{ LCL strings are UTF-8 encoded, and so is RawUtf8, so this is a copy and not
  a conversion. It exists to make the assignment explicit rather than to do
  work. }
function U(const Text: RawUtf8): string;
begin
  result := Text;
end;

{ TFormEditor }

procedure TFormEditor.FormCreate(Sender: TObject);
var
  k: TBoundKind;
  d: TDdlDialect;
  i: PtrInt;
begin
  Application.OnException := @AppException;
  fDb := TEditorDb.Create;
  fStore := TTemplateStore.Create('');
  ComboEngine.Items.Clear;
  ComboEngine.Items.Add('SQLite file');
  ComboEngine.Items.Add('ODBC connection string');
  ComboEngine.ItemIndex := 0;
  ComboBoundKind.Items.Clear;
  for k := low(TBoundKind) to high(TBoundKind) do
    ComboBoundKind.Items.Add(U(SQLPARAM_NAME[k]));
  ComboBoundKind.ItemIndex := ord(bkText);
  ComboBoundKindChange(nil);
  { absolute, and next to the executable rather than relative to the working
    directory: started from the IDE the working directory is the project
    folder, and a bare 'demo.sqlite' would be looked for in the wrong place }
  { which database a generated create table is spelled for. Filled from the
    same table that spells it, so the list and the statement cannot disagree
    about how many dialects there are }
  ComboDialect.Items.Clear;
  for d := low(TDdlDialect) to high(TDdlDialect) do
    ComboDialect.Items.Add(U(DDL_DIALECTS[d].Name));
  ComboDialect.ItemIndex := ord(ddSQLite);
  { the profiles, from the same table the server and the client read: picking
    one points the editor at that profile's templates AND at the database
    those templates run against - the two belong together, and editing the
    one set against the other database is the mistake this prevents }
  ComboProfile.Items.BeginUpdate;
  try
    for i := 0 to high(SQL_PROFILES) do
      ComboProfile.Items.Add(string(SQL_PROFILES[i].Description));
  finally
    ComboProfile.Items.EndUpdate;
  end;
  ComboProfile.ItemIndex := 0;
  ComboProfileChange(nil);
  ShowConnection;
  MemoLog.Clear;
  PagesResult.ActivePage := TabLog;
  Log('Template editor. Connect to a database, then load the template list.');
  Log('Writes are rolled back while the Rollback box is ticked - untick it ' +
      'and a write that runs stays in the database.');
  Log('Point this at a development database, not at production.');
  RefreshBoundsJson;
  fLastJson := '[]';
  fLastRecordJson.InitFast(dvObject);
  RenderJson;
end;

procedure TFormEditor.FormDestroy(Sender: TObject);
begin
  { closing the window closes the connection, and closing a connection whose
    server is no longer there is exactly what raises. There is no form left to
    show a message on by now, and nothing to decide: the program is ending }
  try
    FreeAndNil(fStore);
  except
    ;
  end;
  try
    FreeAndNil(fDb);
  except
    ;
  end;
end;

{ Both places that drop a connection go through here, because both are reached
  after the tunnel went down: switching profile and pressing "Trennen". }
procedure TFormEditor.DropConnection;
begin
  fDb.Disconnect;
  ShowConnection;
  ButtonConnect.Caption := 'Verbinden';
  if fDb.LastCleanupError <> '' then
    { FormatUtf8 and not a "+": a literal with an umlaut concatenated onto a
      string is folded by the compiler into the default ansi codepage, and one
      Latin-1 byte in a Cocoa control ends the process - see SafeText }
    Log(FormatUtf8('Beim Schließen der Verbindung: %', [fDb.LastCleanupError]));
end;

{ What the LCL would otherwise do with it - and what it does depends on where
  the exception came from, which is why this exists. A message in the log and
  a box on screen, and the editor stays up: nothing here is worth losing an
  unsaved template over. }
procedure TFormEditor.AppException(Sender: TObject; E: Exception);
var
  msg, advice: RawUtf8; // not "hint": TControl has one
begin
  msg := FormatUtf8('% %', [E.ClassType, E.Message]);
  advice := ConnectionHint(msg);
  if advice <> '' then
    msg := msg + #13#10 + advice;
  try
    Log('Unerwartete Ausnahme: ' + msg);
    PagesResult.ActivePage := TabLog;
    Say('Unerwartete Ausnahme - der Grund steht im Log.', stBad);
  except
    { the form may be half gone by now: the box below is what matters }
    ;
  end;
  MessageDlg('Unerwartete Ausnahme', U(msg), mtError, [mbOK], 0);
end;

{ Text on its way into a Cocoa control, made safe first.

  A memo on macOS takes UTF-8 and nothing else: NSString.stringWithUTF8String
  answers nil for a byte sequence that is not one, and insertText: with nil
  ends the process - SIGABRT, and no exception to catch on the way.

  Most of what this window shows, it did not write: a driver's message, a
  server's answer, the contents of a column, the bytes of a JSON field. One
  bad byte in any of them must not take the editor down, so it is escaped to
  <XX> and shown rather than handed on. Seeing the byte is also the only way
  to find out where it came from. }
function SafeText(const Msg: RawUtf8): string;
var
  i: PtrInt;
  clean: RawUtf8;
begin
  if IsValidUtf8(Msg) then
  begin
    result := U(Msg);
    exit;
  end;
  clean := '';
  for i := 1 to length(Msg) do
    if Msg[i] < #128 then
      clean := clean + Msg[i]
    else
      clean := clean + '<' + RawUtf8(IntToHex(ord(Msg[i]), 2)) + '>';
  result := U(clean);
end;

procedure TFormEditor.Log(const Msg: RawUtf8);
begin
  MemoLog.Lines.Add(SafeText(Msg));
end;

{ mORMot's message names the driver, the statement and the version before the
  reason. All of that belongs in the log; the status line wants the last part,
  which is what the database actually said. }
function ShortReason(const Msg: RawUtf8): RawUtf8;
var
  p, last: PtrInt;
begin
  result := Msg;
  last := 0;
  p := PosEx(' - ', result);
  while p > 0 do
  begin
    last := p;
    p := PosEx(' - ', result, p + 1);
  end;
  if last > 0 then
    result := copy(result, last + 3, maxInt);
end;

{ The connection belongs in the title bar. On the form it was a label in the
  top row, where it lay over the profile box on a narrow window - and the row
  has nothing left to give. The title has room, is never covered, and says
  what this window is about, which is exactly what a connection is here. }
procedure TFormEditor.ShowConnection;
var
  title: string;
begin
  if fDb.Connected then
    title := EDITOR_TITLE + ' - ' + U(fDb.ShortDescription)
  else
    title := EDITOR_TITLE + ' - nicht verbunden';
  if not cbRollback.Checked then
    title := U(FormatUtf8('% - ROLLBACK AUS, Schreibvorgänge bleiben stehen',
      [RawUtf8(title)]));
  { the title bar is a Cocoa string like any other, and it is the one that is
    set while nothing is being logged - so it goes through the same guard }
  Caption := SafeText(RawUtf8(title));
end;

{ The box is ticked when the editor is what it has always been: a test
  changes nothing. Unticked, a write that runs stays in the database - the
  point being to go and look at the row with something else. Nothing else in
  the editor reads the box, so this is the whole of that decision. }
function TFormEditor.WriteEnding: TWriteEnd;
begin
  if cbRollback.Checked then
    result := weRollback
  else
    result := weCommit;
end;

procedure TFormEditor.cbRollbackChange(Sender: TObject);
begin
  { in the title, because a window that writes for real should say so where
    nothing can cover it up - the same place the connection is named }
  ShowConnection;
  if cbRollback.Checked then
    Log('Rollback an: ein Testlauf wird zurückgerollt, wie immer.')
  else
    Log('Rollback AUS: ein Schreib-Statement, das durchläuft, bleibt in ' +
        'der Datenbank stehen. Gilt für Testen und für Record-Werte.');
end;

procedure TFormEditor.Say(const Msg: RawUtf8; Level: TStatusLevel);
const
  { amber, which is neither "wrong" nor "nothing to see here" - and readable
    on both a light and a dark window }
  HINT_COLOR = TColor($0000A0FF);
begin
  LabelStatus.Caption := SafeText(Msg);
  case Level of
    stBad:
      LabelStatus.Font.Color := clRed;
    stHint:
      LabelStatus.Font.Color := HINT_COLOR;
  else
    LabelStatus.Font.Color := clDefault;
  end;
end;

function TFormEditor.TemplateFile: TFileName;
begin
  result := Trim(EditTemplates.Text);
end;

function TFormEditor.CurrentRec: TSqlRec;
begin
  result := default(TSqlRec);
  result.ActionKey := Trim(RawUtf8(EditKey.Text));
  { with the statement generated there is nothing to store in the Sql column,
    and storing what is greyed out would be worse than storing nothing }
  if CheckGenerateSql.Checked then
    result.Sql := ''
  else
    result.Sql := Trim(RawUtf8(MemoSql.Lines.Text));
  result.ParamTypes := Trim(RawUtf8(EditParamTypes.Text));
  { only a record write has one, and it is a type name, not a value }
  result.RecordType := Trim(RawUtf8(EditRecordType.Text));
  { and its fields, when the type is not compiled into the server. Newlines
    out: mORMot's textual RTTI reads a single run of text, and a row that
    carries line breaks makes the .sql export harder to read for nothing }
  result.RecordDecl := TrimU(StringReplaceChars(
    Trim(RawUtf8(MemoRecordDecl.Lines.Text)), #10, ' '));
  result.KeyField := Trim(RawUtf8(EditKeyField.Text));
  result.CallerScope := Trim(RawUtf8(EditCallerScope.Text));
  { the where clause of a generated list, and its order - the shape of the
    filter belongs to the template, which is the point of it being here and
    not in anything a caller sends }
  result.Rules := Trim(RawUtf8(EditRules.Text));
  result.TestBounds := Trim(RawUtf8(EditTestBounds.Text));
  result.Filter := Trim(RawUtf8(EditFilter.Text));
  result.OrderBy := Trim(RawUtf8(EditOrderBy.Text));
  result.ReadGroups := GetInt64(pointer(RawUtf8(Trim(EditReadGroups.Text))));
  result.WriteGroups := GetInt64(pointer(RawUtf8(Trim(EditWriteGroups.Text))));
end;

// -- picking a file -----------------------------------------------------------

function PickSqlite(const Current: string; out Chosen: string): boolean;
var
  dlg: TOpenDialog;
begin
  dlg := TOpenDialog.Create(nil);
  try
    dlg.Title := 'SQLite-Datei wählen';
    dlg.Filter := 'SQLite|*.sqlite;*.db;*.sqlite3|Alle Dateien|*';
    dlg.FileName := Current;
    if Current <> '' then
      dlg.InitialDir := ExtractFilePath(Current);
    result := dlg.Execute;
    if result then
      Chosen := dlg.FileName
    else
      Chosen := '';
  finally
    dlg.Free;
  end;
end;

procedure TFormEditor.ButtonBrowseTargetClick(Sender: TObject);
var
  chosen: string;
begin
  if PickSqlite(Trim(EditTarget.Text), chosen) then
    EditTarget.Text := chosen;
end;

procedure TFormEditor.ButtonBrowseTemplatesClick(Sender: TObject);
var
  chosen: string;
begin
  if PickSqlite(Trim(EditTemplates.Text), chosen) then
    EditTemplates.Text := chosen;
end;

// -- the parameters -----------------------------------------------------------

function TFormEditor.ReadBounds(out Bounds: TBoundArray): boolean;
var
  msg: RawUtf8;
begin
  result := TextToBounds(RawUtf8(MemoBounds.Lines.Text), Bounds, msg);
  if not result then
    Log(msg);
end;

procedure TFormEditor.RefreshBoundsJson;
var
  bounds: TBoundArray;
  v: variant;
  msg: RawUtf8;
begin
  if not ReadBounds(bounds) then
  begin
    EditBoundsJson.Text := '?';
    exit;
  end;
  if BoundsToVariant(bounds, v, msg) then
    { what a client would actually put on the wire - the point of showing it
      is that a typed value and its JSON are not always the same thing }
    EditBoundsJson.Text := U(BoundsToJson(v))
  else
    EditBoundsJson.Text := U(msg);
end;

function TFormEditor.CheckDeclaration(out Msg: RawUtf8): boolean;
var
  kinds: TSqlParamKinds;
  decl: RawUtf8;
  wanted: integer;
begin
  decl := Trim(RawUtf8(EditParamTypes.Text));
  result := ParseParamTypes(decl, kinds, Msg);
  if not result then
    exit;
  wanted := ParamCount(RawUtf8(Trim(MemoSql.Lines.Text)));
  if decl = '' then
  begin
    { allowed on purpose: a template that declares nothing is handed on
      untouched, which is what keeps everything written before this column
      existed working }
    if wanted > 0 then
      Msg := FormatUtf8('No types declared for % parameter(s). They will be ' +
        'bound as whatever JSON made of them - declare "date" if one is a ' +
        'date.', [wanted])
    else
      Msg := 'No parameters, none declared.';
    exit;
  end;
  if length(kinds) <> wanted then
  begin
    Msg := FormatUtf8('The declaration has % entries, the statement % ' +
      'parameter(s).', [length(kinds), wanted]);
    exit(false);
  end;
  Msg := FormatUtf8('Declared: %.', [ParamTypesToText(kinds)]);
end;

procedure TFormEditor.ComboBoundKindChange(Sender: TObject);
var
  k: TBoundKind;
begin
  k := TBoundKind(ComboBoundKind.ItemIndex);
  LabelBoundHint.Caption := U(SQLPARAM_HINT[k]);
  EditBoundValue.Enabled := k <> bkNull;
end;

procedure TFormEditor.ButtonAddBoundClick(Sender: TObject);
var
  k: TBoundKind;
begin
  { one value at a time, appended - the list is the model and the memo is
    both its display and, if someone prefers typing, its input }
  k := TBoundKind(ComboBoundKind.ItemIndex);
  MemoBounds.Lines.Add('[' + U(SQLPARAM_NAME[k]) + '] ' + Trim(EditBoundValue.Text));
  EditBoundValue.Text := '';
  EditBoundValue.SetFocus;
end;

procedure TFormEditor.ButtonClearBoundsClick(Sender: TObject);
begin
  MemoBounds.Lines.Clear;
end;

procedure TFormEditor.MemoBoundsChange(Sender: TObject);
var
  bounds: TBoundArray;
  decl, msg: RawUtf8;
begin
  RefreshBoundsJson;
  { fill the declaration from the parameters, but only while it is empty: the
    kind was already chosen when the value was entered, and asking for it a
    second time is how the two come to disagree. Overwriting something typed
    deliberately would be a different matter, so that needs the button }
  if Trim(EditParamTypes.Text) <> '' then
    exit;
  if TextToBounds(RawUtf8(MemoBounds.Lines.Text), bounds, msg) and
     BoundsToParamTypes(bounds, decl, msg) then
    EditParamTypes.Text := U(decl);
end;

procedure TFormEditor.ButtonTypesFromBoundsClick(Sender: TObject);
var
  bounds: TBoundArray;
  decl, msg: RawUtf8;
begin
  if not ReadBounds(bounds) then
    exit;
  if BoundsToParamTypes(bounds, decl, msg) then
  begin
    EditParamTypes.Text := U(decl);
    Say(msg, stOk);
  end
  else
    Say(msg, stBad);
  Log(msg);
end;

// -- connection ---------------------------------------------------------------

procedure TFormEditor.ButtonConnectClick(Sender: TObject);
var
  msg: RawUtf8;
begin
  if fDb.Connected then
  begin
    DropConnection;
    Log('Disconnected.');
    exit;
  end;
  if fDb.Connect(TEditorEngine(ComboEngine.ItemIndex),
       RawUtf8(Trim(EditTarget.Text)), RawUtf8(Trim(EditUser.Text)),
       RawUtf8(EditPassword.Text), msg) then
    ButtonConnect.Caption := 'Trennen';
  ShowConnection;
  Log(msg);
  PagesResult.ActivePage := TabLog;
end;

{ Switching profile points BOTH edits somewhere else: the templates file and
  the database its statements run against. A live connection is dropped, since
  it is the connection to the other database. }
procedure TFormEditor.ComboProfileChange(Sender: TObject);
var
  i: integer;
begin
  i := ComboProfile.ItemIndex;
  if i < 0 then
    exit;
  if fDb.Connected then
    DropConnection;
  EditTemplates.Text := DefaultDataFolder +
                        string(SQL_PROFILES[i].TemplateFile);
  EditServer.Text := 'localhost:' + string(SQL_PROFILES[i].Port);
  fSyncingBoxes := true;
  try
    ComboEngine.ItemIndex := ord(ProfileEngine(SQL_PROFILES[i]));
  finally
    fSyncingBoxes := false;
  end;
  { preselected, not decided: a create table is an artefact to hand on, and
    the database it is meant for is regularly not the one connected here.
    The profile is the better guess than nothing, and it stays a guess }
  ComboDialect.ItemIndex := ord(ProfileDialect(SQL_PROFILES[i]));
  if SQL_PROFILES[i].TargetDatabase <> '' then
  begin
    { before anything touches the driver: OpenSSL is initialised once, and a
      server offering TLS 1.0 only is refused after that }
    SetupOpenSslForLegacyTls;
    EditTarget.Text := string(
      SqlServerConnectionString(SQL_PROFILES[i].TargetDatabase));
  end
  else
    { absolute, and next to the executable rather than relative to the working
      directory: started from the IDE the working directory is the project
      folder, and a bare 'demo.sqlite' would be looked for in the wrong place }
    EditTarget.Text := DefaultDataFolder + string(SQL_PROFILES[i].TargetFile);
  { the list on screen belongs to the profile that was selected before }
  ListKeys.Items.Clear;
  fListLoaded := false;
end;

{ The driver box follows the profile, so it may as well lead it too: picking
  a driver moves the profile to one that runs on it, and the target and the
  templates file come along. Choosing the connection string and leaving a
  SQLite path in Ziel is otherwise a connection attempt that hangs rather than
  fails - the one thing the user must not be left to remember. }
procedure TFormEditor.ComboEngineChange(Sender: TObject);
var
  wanted: TEditorEngine;
  i: integer;
begin
  if fSyncingBoxes or
     (ComboEngine.ItemIndex < 0) then
    exit;
  wanted := TEditorEngine(ComboEngine.ItemIndex);
  i := ComboProfile.ItemIndex;
  if (i >= 0) and
     (ProfileEngine(SQL_PROFILES[i]) = wanted) then
    exit; // the profile on screen already runs on this driver
  for i := 0 to high(SQL_PROFILES) do
    if ProfileEngine(SQL_PROFILES[i]) = wanted then
    begin
      ComboProfile.ItemIndex := i;
      { the LCL does not raise OnChange for a programmatic ItemIndex, and the
        profile has to be applied whether it does or not }
      ComboProfileChange(nil);
      Log(FormatUtf8('Profile switched to % - target and templates file ' +
        'belong to the driver, and a mismatched pair is what hangs.',
        [SQL_PROFILES[i].Name]));
      exit;
    end;
end;

// -- the template list --------------------------------------------------------

procedure TFormEditor.ButtonLoadListClick(Sender: TObject);
var
  msg: RawUtf8;
begin
  fStore.FileName := TemplateFile;
  fListLoaded := fStore.Load(fRecs, msg);
  { the filter box keeps what it holds: a reload after a save should leave the
    maintainer where they were, not throw them back to the whole file }
  FillKeyList;
  Log(msg);
end;

{ The list on screen, from what was loaded and from the filter box.

  Thirty keys fit on the screen; a real set does not, and scrolling for one
  name is what the box is for. It matches anywhere in the key and ignores
  case, so "kunde" finds AddKunde as well as GetKundenByCity.

  What it costs is the identity between the row and the record: once a line
  can be hidden, the fifth row is no longer the fifth template. Each line
  therefore carries its own position in fRecs, and the selection reads it
  there instead of counting rows. }
procedure TFormEditor.FillKeyList;
var
  i: PtrInt;
  filter, key: string;
begin
  filter := LowerCase(Trim(EditKeyFilter.Text));
  ListKeys.Items.BeginUpdate;
  try
    ListKeys.Items.Clear;
    if fListLoaded then
      for i := 0 to high(fRecs) do
      begin
        key := U(fRecs[i].ActionKey);
        if (filter = '') or
           (Pos(filter, LowerCase(key)) > 0) then
          ListKeys.Items.AddObject(key, TObject(PtrInt(i)));
      end;
  finally
    ListKeys.Items.EndUpdate;
  end;
end;

procedure TFormEditor.EditKeyFilterChange(Sender: TObject);
begin
  FillKeyList;
end;

procedure TFormEditor.ListKeysSelectionChange(Sender: TObject; User: boolean);
var
  i: integer;
begin
  i := ListKeys.ItemIndex;
  if i < 0 then
    exit;
  { the row says which template it is - see FillKeyList }
  i := PtrInt(ListKeys.Items.Objects[i]);
  if (i < 0) or
     (i > high(fRecs)) then
    exit;
  EditKey.Text := U(fRecs[i].ActionKey);
  MemoSql.Lines.Text := SafeText(fRecs[i].Sql);
  CheckGenerateSql.Checked := (fRecs[i].Sql = '') and
                              (fRecs[i].RecordType <> '');
  CheckGenerateSqlChange(nil);
  EditParamTypes.Text := U(fRecs[i].ParamTypes);
  EditRecordType.Text := U(fRecs[i].RecordType);
  MemoRecordDecl.Lines.Text := SafeText(fRecs[i].RecordDecl);
  EditKeyField.Text := U(fRecs[i].KeyField);
  EditCallerScope.Text := U(fRecs[i].CallerScope);
  EditRules.Text := U(fRecs[i].Rules);
  EditTestBounds.Text := U(fRecs[i].TestBounds);
  EditFilter.Text := U(fRecs[i].Filter);
  EditOrderBy.Text := U(fRecs[i].OrderBy);
  EditReadGroups.Text := IntToStr(fRecs[i].ReadGroups);
  EditWriteGroups.Text := IntToStr(fRecs[i].WriteGroups);
  EditTypeName.Text := U(SuggestTypeName(fRecs[i].ActionKey));
end;

procedure TFormEditor.ButtonNewClick(Sender: TObject);
begin
  ListKeys.ItemIndex := -1;
  EditKey.Text := '';
  MemoSql.Lines.Clear;
  CheckGenerateSql.Checked := false;
  CheckGenerateSqlChange(nil);
  EditParamTypes.Text := '';
  EditRecordType.Text := '';
  MemoRecordDecl.Lines.Clear;
  EditKeyField.Text := '';
  EditCallerScope.Text := '';
  EditRules.Text := '';
  EditTestBounds.Text := '';
  EditFilter.Text := '';
  EditOrderBy.Text := '';
  EditReadGroups.Text := '0';
  EditWriteGroups.Text := '0';
  MemoBounds.Lines.Clear;
  EditTypeName.Text := '';
  MemoDto.Clear;
  EditKey.SetFocus;
end;

// -- checking and running -----------------------------------------------------

procedure TFormEditor.ButtonCheckClick(Sender: TObject);
var
  msg, firstBad, firstHint: RawUtf8;
  rec: TSqlRec;
  probe: TSqlRecArray;
  bounds: TBoundArray;
  v: variant;
  i, found: PtrInt;

  { every step logs its full wording; the status line carries the first thing
    that was wrong, because that is the one the user has to fix }
  procedure Step(Ok: boolean; const Text: RawUtf8);
  begin
    Log(Text);
    if (not Ok) and
       (firstBad = '') then
      firstBad := Text;
  end;

  { the same, for what is worth knowing rather than wrong: it never turns the
    line red, and it is only shown when nothing actually failed }
  procedure Hint(Ok: boolean; const Text: RawUtf8);
  begin
    Log(Text);
    if (not Ok) and
       (firstHint = '') then
      firstHint := Text;
  end;

begin
  PagesResult.ActivePage := TabLog;
  Log('--- check ---');
  firstBad := '';
  firstHint := '';
  if not ReadBounds(bounds) then
  begin
    Say('The parameter list cannot be read - see the messages.', stBad);
    exit;
  end;
  { first the statement on its own: the rules that need no database }
  Step(StaticCheck(RawUtf8(Trim(MemoSql.Lines.Text)), length(bounds), msg), msg);
  { then the declaration: it has to parse, and it has to have one entry per ? }
  Step(CheckDeclaration(msg), msg);
  { then the record side, with the server's own code: the type has to resolve
    - from the fields in its row when it is not compiled in - and a generated
    statement is printed, which is the only way to see it before it runs }
  Step(CheckRecordType(msg), msg);
  { then whether the values would survive the trip a real client makes. A
    hint and not a failure: nothing is wrong with the template - it is the
    test values that would arrive as another type over JSON, so a green run
    here says a little less than it looks like }
  if BoundsToVariant(bounds, v, msg) then
    Hint(JsonRoundTrip(v, msg), msg)
  else
    Step(false, msg);
  { then the Rules column: what it says has to parse, has to name parameters
    that exist, and the values in the memo have to pass it }
  Step(RulesHold(CurrentRec, bounds, msg), msg);
  { then the whole set as it would be after saving, through the very check
    the server runs on ReloadTemplates }
  rec := CurrentRec;
  if rec.ActionKey = '' then
  begin
    { say so rather than stopping quietly: the lines above would otherwise
      read as "everything checked" }
    Step(false, 'The action key is empty, so the set was not checked. ' +
      'A template without a key cannot be saved.');
    Say(firstBad, stBad);
    exit;
  end;
  if not fListLoaded then
    Step(false, 'The template list was never loaded, so the set below is ' +
      'this one entry alone. Press "Liste laden" to check against what is ' +
      'really in the file.');
  probe := copy(fRecs);
  found := -1;
  for i := 0 to high(probe) do
    if IdemPropNameU(probe[i].ActionKey, rec.ActionKey) then
      found := i;
  if found >= 0 then
  begin
    { Save does insert-or-replace, so an existing key is overwritten without
      a further question - which is right for editing and worth saying out
      loud when it was not intended }
    Log(FormatUtf8('"%" exists already: saving would REPLACE it.',
      [rec.ActionKey]));
    probe[found] := rec;
  end
  else
  begin
    Log(FormatUtf8('"%" is new: saving would add it.', [rec.ActionKey]));
    SetLength(probe, length(probe) + 1);
    probe[high(probe)] := rec;
  end;
  Step(CheckSet(probe, msg), msg);
  if firstBad <> '' then
    Say(firstBad, stBad)
  else if firstHint <> '' then
    Say('Hinweis: ' + firstHint, stHint)
  else
    Say('Checked, nothing to report.', stOk);
end;

{ The whole file in one press.

  "Prüfen" answers for the template in front of the maintainer; this answers
  for the set, which is the question before a commit: after a renamed column
  or an edited record type, WHICH key stopped working? The checks run on every
  template, the run needs the TestBounds column, and a template without one is
  reported as open rather than counted as passed.

  Always rolled back, whatever the Rollback box says: that box is about the
  one statement being looked at, and a sweep that writes rows is not what
  anybody presses this for. }
procedure TFormEditor.ButtonCheckAllClick(Sender: TObject);
var
  rows: TSweepRows;
  i: PtrInt;
  execute, writes: boolean;
  firstBad, summary, who: RawUtf8;
  reads, wr: Int64;
  secs, open: integer;
begin
  PagesResult.ActivePage := TabLog;
  Log('--- alle prüfen ---');
  if not fListLoaded then
  begin
    Say('Die Liste ist nicht geladen - erst "Liste laden".', stBad);
    exit;
  end;
  if cbViaServer.Checked then
  begin
    { the same sweep, but every call goes where a client's would - so the
      masks, the caller's identity and the rules all apply, and the one row
      that was always "offen" (a scoped template) finally runs }
    writes := HasServerWrites(fRecs) and
      (MessageDlg('Alle prüfen über den Server',
        'Der Server rollt nichts zurück. Sollen die Schreibvorgänge ' +
        'wirklich ausgeführt werden?'#13#10 +
        'Nein lässt sie aus und prüft nur die Lesezugriffe.',
        mtWarning, [mbYes, mbNo], 0) = mrYes);
    if not ServerConnect then
      exit;
    try
      Log('Über den Server: mit Rechtemaske, Caller-Scope und Regeln.');
      if not writes then
        Log('Schreibvorgänge werden ausgelassen - der Server rollt nichts ' +
            'zurück.');
      { one login for the whole sweep, asked before the first refusal }
      if AuthTool.WhoAmI(who, reads, wr, secs) = sqlNeedsLogin then
        if not ServerLogin then
        begin
          Say('Ohne Anmeldung antwortet der Server auf nichts.', stBad);
          exit;
        end;
      Screen.Cursor := crHourGlass;
      try
        rows := SweepTemplates(nil, fRecs, {execute=}true, smServer, writes);
      finally
        Screen.Cursor := crDefault;
      end;
    finally
      DisconnectClient;
    end;
  end
  else
  begin
    execute := (fDb <> nil) and
               fDb.Connected;
    if execute then
      Log('Verbunden: Templates mit TestBounds werden ausgeführt, ' +
          'Schreibvorgänge in einer Transaktion, die zurückgerollt wird.')
    else
      Log('Nicht verbunden: geprüft wird, ausgeführt nichts.');
    Screen.Cursor := crHourGlass;
    try
      rows := SweepTemplates(fDb, fRecs, execute);
    finally
      Screen.Cursor := crDefault;
    end;
  end;
  firstBad := '';
  open := 0;
  for i := 0 to high(rows) do
  begin
    Log(FormatUtf8('%  %  %',
      [SWEEP_MARK[rows[i].Outcome], rows[i].ActionKey, rows[i].Message]));
    if rows[i].Outcome = swSkipped then
      inc(open);
    if (rows[i].Outcome = swBad) and
       (firstBad = '') then
      firstBad := FormatUtf8('%: %', [rows[i].ActionKey, rows[i].Message]);
  end;
  summary := SweepSummary(rows);
  Log(summary);
  if firstBad <> '' then
    Say(summary + ' Zuerst: ' + firstBad, stBad)
  else if open > 0 then
    { nothing is wrong, and nothing pretends the set is proven either }
    Say(summary, stHint)
  else
    Say(summary, stOk);
end;

{ The JSON that would go out, into the column the sweep runs from.

  The values were typed once, with their kinds, and this is the same array a
  client would send - so the column is filled from it rather than typed a
  second time and made to disagree. }
procedure TFormEditor.ButtonTestBoundsFromJsonClick(Sender: TObject);
begin
  EditTestBounds.Text := EditBoundsJson.Text;
  Say('TestBounds übernommen - "Speichern" schreibt sie in die Datei.', stOk);
end;

{ The Rules column, read and run exactly as the domain layer does it.

  Two differences from the server, both said out loud rather than papered
  over: a record write has no parameter positions, so a rule on one is a
  template the server refuses - and it is refused here before it can be
  saved; and the caller's own value is not bound in this tool, so a scoped
  template is checked with a null in that last place. }
function TFormEditor.RulesHold(const Rec: TSqlRec; const Bounds: TBoundArray;
  out Msg: RawUtf8): boolean;
var
  rules: TSqlParamRules;
  fault: TSqlRuleFault;
  v: variant;
  arr: TDocVariantData;
  scoped: RawUtf8;
begin
  Msg := '';
  if Rec.Rules = '' then
  begin
    Msg := 'Keine Regeln - geprüft wird nur der Typ der Parameter.';
    exit(true);
  end;
  if (Rec.RecordType <> '') and
     (RecordKindFromActionKey(Rec.ActionKey) in [raInsert, raUpdate]) then
  begin
    Msg := 'Regeln nennen Parameterpositionen, ein Record-Schreibvorgang ' +
           'hat keine. Der Server lehnt eine solche Vorlage ab.';
    exit(false);
  end;
  if not ParseParamRules(Rec.Rules, rules, Msg) then
    exit(false);
  if not BoundsToVariant(Bounds, v, Msg) then
    exit(false);
  scoped := '';
  if Rec.CallerScope <> '' then
  begin
    { the server appends its own value to the last ?, and this tool does not
      bind one at all - so the position is filled with a null here, and a
      rule about it is answered on a value that will not be the real one }
    arr.InitArray([], JSON_FAST_FLOAT);
    arr.AddFrom(v); { the Variant overload is the one both mORMot lines have }
    arr.AddItem(Null);
    v := variant(arr);
    scoped := ' Der gescopte letzte Parameter wurde als null geprüft.';
  end;
  result := CheckParamRules(Rec.Rules, v, fault, Msg);
  if result then
    Msg := FormatUtf8('% Regel(n) geprüft, alle erfüllt.%',
      [length(rules), scoped])
  else if fault = rfTemplate then
    Msg := 'Regel-Spalte: ' + Msg + ' Der Server antwortet darauf sqlFailed.'
  else
    Msg := 'Regel verletzt: ' + Msg + ' Der Server antwortet sqlBadParams.';
end;

{ The record side of a template, through the very functions the server uses.
  A type that is compiled into the server always wins; RecordDecl is for the
  ones that are not, and registering it here is what lets this tool show the
  fields and the generated statement at all.

  Note what is NOT checked when the set is checked: whether RecordDecl parses.
  That check needs the infrastructure layer, and the registry is in dom, which
  must not see it. So it lives here - earlier than the server anyway. }
function TFormEditor.CheckRecordType(out Msg: RawUtf8): boolean;
var
  rec: TSqlRec;
  rc: TRttiCustom;
  sql, fields: RawUtf8;
  i: PtrInt;
begin
  Msg := '';
  rec := CurrentRec;
  if rec.RecordType = '' then
  begin
    if rec.RecordDecl <> '' then
    begin
      Msg := 'Record-Felder ohne Record-Typ: unter welchem Namen sollen ' +
             'sie registriert werden? Der Server lehnt den Satz ab.';
      exit(false);
    end;
    Msg := 'Kein Record-Typ - eine gewöhnliche Abfrage mit ? und Parametern.';
    exit(true);
  end;
  result := ResolveRecordType(rec, rc, Msg) = rbOk;
  if not result then
    exit;
  fields := '';
  for i := 0 to rc.Props.Count - 1 do
  begin
    if fields <> '' then
      fields := fields + ', ';
    fields := fields + rc.Props.List[i].Name + ': ' +
      { qualified: SqlStatus has a ToText of its own, and it is the one in
        scope here }
      RawUtf8(mormot.core.rtti.ToText(rc.Props.List[i].Value.Parser)^);
  end;
  Msg := FormatUtf8('%: % Feld(er) - %', [rc.Name, rc.Props.Count, fields]);
  if rec.Sql <> '' then
    exit; // a written statement with :Names - there is nothing to generate
  Log(Msg);
  result := GeneratedSqlFor(rec, sql, Msg) = rbOk;
  if result then
    Msg := 'erzeugtes SQL: ' + sql;
end;

{ The generated statement, handed over to be edited.

  A generated template says everything in three words, and stops there: the
  convention has no room for a second condition, a join, a column the record
  does not carry. Writing the statement instead is the way out and always
  was - but for a record with thirty fields that means typing thirty column
  names that already exist, which is why it was rarely the way out in
  practice.

  So: generate it, put it in the box, and untick the checkbox. From that
  moment the template carries a statement of its own, and the consequence is
  worth saying out loud rather than discovering later - it no longer follows
  the record type. A field added to the record reaches a generated statement
  by itself and this one not at all. }
procedure TFormEditor.ButtonSqlFromRecordClick(Sender: TObject);
var
  rec: TSqlRec;
  sql, msg: RawUtf8;
begin
  PagesResult.ActivePage := TabLog;
  rec := CurrentRec;
  if rec.RecordType = '' then
  begin
    Say('Kein Record-Typ: erzeugt wird aus Action-Key und Record-Typ, und ' +
      'ohne den zweiten gibt es nichts zu erzeugen.', stBad);
    exit;
  end;
  if EditableSqlFor(rec, sql, msg) <> rbOk then
  begin
    Log(msg);
    Say(ShortReason(msg), stBad);
    exit;
  end;
  MemoSql.Lines.Text := SafeText(sql);
  CheckGenerateSql.Checked := false;
  CheckGenerateSqlChange(nil);
  Log(FormatUtf8('Erzeugt und übernommen: %', [sql]));
  case RecordKindFromActionKey(rec.ActionKey) of
    raInsert,
    raUpdate:
      Log('Die :Namen sind die Felder des Records - der Server füllt sie ' +
          'beim Aufruf. Ein geschriebenes Record-Statement mit ? wird ' +
          'abgelehnt, deshalb stehen sie hier und keine Fragezeichen.');
    raRetrieve,
    raList:
      Log('Spaltenliste und Tabelle kommen aus dem Record-Typ, das where ' +
          'schreibst du: Bedingung mit ? anhängen, für jedes ? einen ' +
          'Parameter anlegen, dann Testen.');
    raDelete:
      Log('Das where steht schon da - ein Delete ohne where ist einen ' +
          'Tastendruck von einer leeren Tabelle entfernt. Das ? ist der ' +
          'Schlüssel und kommt beim Testen aus der Parameterliste.');
  end;
  Say('Das Template trägt jetzt ein eigenes Statement und folgt dem ' +
    'Record-Typ nicht mehr. Speichern nicht vergessen.', stOk);
end;

{ The table this record type would need - composed, not run.

  That is the whole feature and the restraint is the point: the statement is
  put where it can be read and nothing is executed. A tool that creates
  tables on a keystroke is one nobody dares point at a database that
  matters, and this one is meant to be pointed at whatever you have.

  So it lands in the log and on the clipboard, and creating the table stays
  something somebody does with their eyes open.

  Which database it is spelled for is the drop-down next to it, and NOT the
  open connection. The profile only preselects it: the case this is for is
  the schema you hand to somebody who has the rights you do not, and being
  logged into that server is exactly what you are not. Nothing here touches
  the database, so it works unconnected. }
procedure TFormEditor.ButtonCreateTableClick(Sender: TObject);
var
  rec: TSqlRec;
  sql, msg: RawUtf8;
begin
  PagesResult.ActivePage := TabLog;
  rec := CurrentRec;
  if rec.RecordType = '' then
  begin
    Say('Kein Record-Typ: die Spalten werden aus den Feldern des Records ' +
      'beschrieben, und ohne Record gibt es keine.', stBad);
    exit;
  end;
  { the box is filled in FormCreate and set again with every profile, so
    this is belt and braces - but an ItemIndex of -1 cast to the enum is a
    range error rather than a wrong dialect, and that is worth one line }
  if ComboDialect.ItemIndex < 0 then
    ComboDialect.ItemIndex := ord(ddSQLite);
  if CreateTableSqlFor(rec, TDdlDialect(ComboDialect.ItemIndex),
       sql, msg) <> rbOk then
  begin
    Log(msg);
    Say(ShortReason(msg), stBad);
    exit;
  end;
  Log(msg);
  Log(sql);
  Log('Was hier NICHT steht, sagt der Record-Typ auch nicht: not null, ' +
      'Vorgabewerte, Indizes, Fremdschlüssel. Die schreibst du dazu, bevor ' +
      'du das Statement ausführst.');
  Clipboard.AsText := SafeText(sql);
  Say('Create-Table steht im Log und auf der Zwischenablage. Ausgeführt ' +
    'wird nichts - die Tabelle legst du selbst an.', stOk);
end;

procedure TFormEditor.ButtonTestClick(Sender: TObject);
var
  res: TRunResult;
  bounds: TBoundArray;
  mode: TRunMode;
  rec: TSqlRec;
  ruleMsg, recJson, recMsg: RawUtf8;
begin
  if not ReadBounds(bounds) then
  begin
    PagesResult.ActivePage := TabLog;
    exit;
  end;
  rec := CurrentRec;
  if (rec.RecordType <> '') and
     (RecordKindFromActionKey(rec.ActionKey) in [raInsert, raUpdate]) then
  begin
    { An insert or an update of a record takes its values from the record and
      never from the list below the statement: the generated statement carries
      :Names, and a written one with ? is refused by the domain layer. That is
      a statement about where the values come from, not about whether this can
      be tested - so the record is looked for where the window shows it, and
      the run is the same one the dialog makes. }
    PagesResult.ActivePage := TabLog;
    if not RecordJsonToTest(rec, recJson, recMsg) then
    begin
      Say(recMsg, stBad);
      exit;
    end;
    Log(recMsg);
    if cbViaServer.Checked then
      RunRecordThroughServer(rec, recJson)
    else
      ShowResult(RunRecord(fDb, rec, recJson, WriteEnding));
    exit;
  end;
  if cbViaServer.Checked then
  begin
    { the other way round entirely: the server resolves the key, checks the
      mask, binds the caller and applies the rules - so nothing of the
      editor's own checking runs first, or it would answer questions the
      server is about to answer better }
    PagesResult.ActivePage := TabLog;
    RunThroughServer(rec, bounds);
    exit;
  end;
  { the rules come before the statement here as they do in the domain layer,
    so a value this template refuses is refused in the same place }
  if not RulesHold(rec, bounds, ruleMsg) then
  begin
    PagesResult.ActivePage := TabLog;
    Log(ruleMsg);
    Say(ruleMsg, stBad);
    exit;
  end;
  if (rec.Sql = '') and
     (rec.RecordType <> '') then
  begin
    { Nothing in the SQL box and a record type named: the statement is the
      one the key and the type make, and it is made where it will be made in
      the server. This is how a retrieve and a delete are tested - they carry
      no statement of their own, so there was nothing to test before. }
    if CheckInline.Checked then
      Log('Gegenprobe übersprungen: sie setzt Werte in ein Statement ein, ' +
          'und hier gibt es keines - es entsteht erst beim Ausführen.');
    ShowResult(RunGenerated(fDb, rec, bounds, WriteEnding));
    exit;
  end;
  if CheckInline.Checked then
    mode := rmInlined
  else
    mode := rmBound;
  res := Run(fDb, RawUtf8(Trim(EditKey.Text)),
    RawUtf8(Trim(MemoSql.Lines.Text)), bounds, mode, WriteEnding);
  ShowResult(res);
end;

procedure TFormEditor.ShowResult(const Res: TRunResult);
begin
  fLastJson := Res.Json;
  Log('--- run ---');
  Log(FormatUtf8('% - %', [ToText(Res.Status), Res.Message]));
  if Res.ExecutedSql <> '' then
    Log('executed: ' + Res.ExecutedSql);
  RenderJson;
  FillGrid(Res.Json);
  if Succeeded(Res.Status) or
     (Res.Status = sqlNoRows) then
  begin
    Say(Res.Message, stOk);
    if Res.Kind = skSelect then
      PagesResult.ActivePage := TabJson
    else
      PagesResult.ActivePage := TabLog;
  end
  else
  begin
    { a failure must never leave an empty JSON tab in front with the reason
      hidden behind another one }
    Say(ShortReason(Res.Message), stBad);
    PagesResult.ActivePage := TabLog;
  end;
end;

procedure TFormEditor.RenderJson;
begin
  if CheckRawJson.Checked then
    { exactly the bytes the server would put on the wire - reformatting is a
      convenience, not the thing itself }
    MemoJson.Lines.Text := SafeText(fLastJson)
  else
    MemoJson.Lines.Text := SafeText(JsonReformat(fLastJson, jsonHumanReadable));
end;

procedure TFormEditor.CheckRawJsonChange(Sender: TObject);
begin
  RenderJson;
end;

{ A record write whose statement is generated has none to edit, so the memo is
  greyed out rather than left inviting. It used to be that the editor could
  not show the generated statement either - that needed the record type
  compiled into this binary, and the editor is not the server. With the fields
  in the RecordDecl column it can: "Prüfen" registers the type from that text
  and prints exactly what the server would run. }
procedure TFormEditor.CheckGenerateSqlChange(Sender: TObject);
begin
  MemoSql.Enabled := not CheckGenerateSql.Checked;
  if CheckGenerateSql.Checked then
  begin
    MemoSql.Color := clBtnFace;
    if Trim(MemoSql.Lines.Text) <> '' then
      { it is greyed out, not emptied, so it still reads as if it were part
        of the template - and Speichern would store an empty statement }
      Say('Das Statement im SQL-Feld wird so nicht gespeichert: angehakt ' +
        'heißt, dass die Spalte leer bleibt und beim Aufruf erzeugt wird.',
        stHint);
    Log(RawUtf8('Das SQL wird beim Aufruf aus Action-Key und Record-Typ ' +
      'erzeugt: Add.../Insert... oder Update..., Tabelle aus dem Typnamen ' +
      'ohne TDto und Row, Schlüsselspalte aus dem Feld "Schlüssel" - leer ' +
      'heißt ID.'));
  end
  else
    MemoSql.Color := clDefault;
end;

procedure TFormEditor.FillGrid(const Json: RawUtf8);
var
  doc: variant;
  rows, row: PDocVariantData;
  names: TRawUtf8DynArray;
  r, c, idx: PtrInt;
  v: RawUtf8;
begin
  names := nil;
  GridResult.BeginUpdate;
  try
    GridResult.Clear;
    GridResult.FixedRows := 0;
    GridResult.FixedCols := 0;
    GridResult.RowCount := 1;
    GridResult.ColCount := 1;
    doc := _Json(Json, JSON_FAST_FLOAT);
    rows := _Safe(doc);
    if not rows^.IsArray or
       (rows^.Count = 0) then
      exit;
    { the column set is the union over all rows, in the order they first
      appear - the same rule the type generator uses, so the table and the
      generated record cannot disagree }
    for r := 0 to rows^.Count - 1 do
    begin
      row := _Safe(rows^.Values[r]);
      for c := 0 to row^.Count - 1 do
        if FindRawUtf8(names, row^.Names[c], true) < 0 then
          AddRawUtf8(names, row^.Names[c]);
    end;
    if names = nil then
      exit;
    GridResult.ColCount := length(names);
    GridResult.RowCount := rows^.Count + 1;
    GridResult.FixedRows := 1;
    for c := 0 to high(names) do
      GridResult.Cells[c, 0] := U(names[c]);
    for r := 0 to rows^.Count - 1 do
    begin
      row := _Safe(rows^.Values[r]);
      for c := 0 to high(names) do
      begin
        idx := row^.GetValueIndex(names[c]);
        if (idx < 0) or
           VarIsNull(row^.Values[idx]) then
          v := '' // an empty cell reads better than the text "null"
        else
          v := VariantToUtf8(row^.Values[idx]);
        GridResult.Cells[c, r + 1] := U(v);
      end;
    end;
    GridResult.AutoSizeColumns;
  finally
    GridResult.EndUpdate;
  end;
end;

// -- saving -------------------------------------------------------------------

procedure TFormEditor.ButtonSaveClick(Sender: TObject);
var
  msg: RawUtf8;
begin
  PagesResult.ActivePage := TabLog;
  fStore.FileName := TemplateFile;
  if fStore.Save(CurrentRec, msg) then
  begin
    Log(msg);
    Say(msg, stOk);
    AutoExport;
    ButtonLoadListClick(nil); // the list is what is in the file, always
  end
  else
  begin
    Log('Not saved: ' + msg);
    Say('Not saved: ' + msg, stBad);
  end;
end;

procedure TFormEditor.ButtonDeleteClick(Sender: TObject);
var
  msg: RawUtf8;
  key: string;
begin
  key := Trim(EditKey.Text);
  if key = '' then
    exit;
  if MessageDlg('Löschen',
       U(FormatUtf8('Template "%" aus % löschen?',
         [RawUtf8(key), RawUtf8(TemplateFile)])), mtConfirmation,
       [mbYes, mbNo], 0) <> mrYes then
    exit;
  PagesResult.ActivePage := TabLog;
  fStore.FileName := TemplateFile;
  fStore.Delete(RawUtf8(key), msg);
  Log(msg);
  AutoExport;
  ButtonLoadListClick(nil);
  ButtonNewClick(nil);
end;

{ The .sql is written here and nowhere else, after every save and every
  delete. There is no button for it on purpose: two files that are supposed
  to say the same thing should not need anybody to remember the second one,
  and a button called "export" next to one called "save" is read as a step
  the save does not do. }
procedure TFormEditor.AutoExport;
var
  msg: RawUtf8;
begin
  if not fStore.ExportSql(ChangeFileExt(TemplateFile, '.sql'), msg) then
    { a failed export must not look like a failed save - the template IS in
      the database. It is the copy in version control that is now behind }
    Log('SQL export FAILED, the .sql file is now behind: ' + msg)
  else
    Log(msg);
end;

procedure TFormEditor.ButtonGenerateClick(Sender: TObject);
var
  src, warn, typeName: RawUtf8; // not 'Name': TComponent.Name is in scope
begin
  typeName := RawUtf8(Trim(EditTypeName.Text));
  if typeName = '' then
  begin
    typeName := SuggestTypeName(RawUtf8(Trim(EditKey.Text)));
    EditTypeName.Text := U(typeName);
  end;
  MemoDto.Clear;
  if GenerateDto(typeName, fLastJson, src, warn) then
    MemoDto.Lines.Text := SafeText(src);
  if warn <> '' then
    Log(warn);
  PagesResult.ActivePage := TabDto;
end;

procedure TFormEditor.ButtonCopyDtoClick(Sender: TObject);
begin
  if MemoDto.Lines.Count = 0 then
    exit;
  Clipboard.AsText := MemoDto.Lines.Text;
  Log('The generated type is on the clipboard.');
end;

// -- the running server -------------------------------------------------------

{ The record direction, tried out before anything is saved.

  Three steps, and the middle one is the point: the type is resolved exactly
  as the server resolves it, the dialog is built from whatever fields that
  turns out to have, and what comes back is the JSON a client would send. It
  then runs through BindRecordJson and the rollback transaction - so this
  tests the path that will run, not a second one written for the editor. }
procedure TFormEditor.ButtonRecordDialogClick(Sender: TObject);
var
  rec: TSqlRec;
  rc: TRttiCustom;
  json, msg, remembered: RawUtf8;
  row: variant;
  key: string;
  res: TRunResult;
begin
  PagesResult.ActivePage := TabLog;
  rec := CurrentRec;
  if rec.RecordType = '' then
  begin
    Say('Kein Record-Typ: dieser Schlüssel nimmt eine Werteliste, keinen ' +
      'Record.', stBad);
    exit;
  end;
  if not (RecordKindFromActionKey(rec.ActionKey) in [raInsert, raUpdate]) then
  begin
    { a retrieve and a delete send the key and nothing else - the values
      below the statement are the ordinary test values, not a record }
    Say(FormatUtf8('% nimmt keinen Record: Add/Insert und Update tun das, ' +
      'Retrieve und Delete bekommen nur den Schlüssel als Testwert.',
      [rec.ActionKey]), stBad);
    exit;
  end;
  if ResolveRecordType(rec, rc, msg) <> rbOk then
  begin
    Log(msg);
    Say(ShortReason(msg), stBad);
    exit;
  end;
  SetVariantNull(row);
  remembered := fLastRecordJson.U[rec.ActionKey];
  if RecordKindFromActionKey(rec.ActionKey) = raUpdate then
  begin
    { An update is about a row that is already there, so the honest starting
      point is that row and not an empty form. The key is asked for rather
      than guessed, and left empty it opens on defaults - which is what an
      update of a row one knows by heart wants. }
    key := '';
    if InputQuery('Zeile laden',
         U(FormatUtf8('Wert von % - leer lassen für leere Felder:',
           [KeyFieldOf(rec)])), key) and
       (Trim(key) <> '') then
      if LoadRecordRow(fDb, rec, RawUtf8(Trim(key)), row, msg) then
        Log('Vorbelegt aus: ' + msg)
      else
      begin
        { not found, not connected, nothing readable - all three are reasons
          to stop rather than to open a form that pretends to hold a row }
        Log(msg);
        Say(ShortReason(msg), stBad);
        exit;
      end;
  end;
  if VarIsEmptyOrNull(row) and
     (remembered <> '') then
  begin
    { nothing came from the database - an insert never asks, an update was
      given no key - and the same record was entered before in this session.
      Retyping it is the thing the dialog exists to spare }
    row := _Json(remembered, JSON_FAST_FLOAT);
    Log('Vorbelegt aus der letzten Eingabe zu diesem Schlüssel.');
  end;
  if not EditRecordValues(rec, rc, row, json) then
    exit; // cancelled, and nothing was touched
  Log('Record: ' + json);
  { what was typed is kept for the next time the dialog opens on this key,
    and shown as what would travel: a record template sends this object, and
    "JSON als TestBounds" puts it in the column from there }
  fLastRecordJson.U[rec.ActionKey] := json;
  EditBoundsJson.Text := U(json);
  Log('Das Record-JSON steht jetzt unter "so würde es reisen" - ' +
      '"JSON als TestBounds" schreibt es in die Spalte, dann läuft es im ' +
      'Sammellauf und über den Server mit.');
  if cbViaServer.Checked then
  begin
    { the same JSON, but sent instead of executed here: the server checks the
      mask, resolves the type and generates the statement itself }
    RunRecordThroughServer(rec, json);
    exit;
  end;
  res := RunRecord(fDb, rec, json, WriteEnding);
  ShowResult(res);
end;

{ The editor speaks to the server in exactly one place - "Server neu laden" -
  and this is what that needs when the server demands a token.

  The window is the client's, from src/ui: two programs asking for the same
  two fields, and no reason for two windows to drift apart. The connection is
  already open when this is called, which is why it does not open one. }
procedure TFormEditor.cbViaServerChange(Sender: TObject);
begin
  if not cbViaServer.Checked then
  begin
    Log('Testen läuft wieder direkt auf der Verbindung: Rechte, ' +
        'Caller-Scope und Regeln greifen dabei nicht.');
    exit;
  end;
  Log('Testen geht jetzt über den Server: nur gespeicherte Schlüssel, ' +
      'dafür mit Rechtemaske, Caller-Scope und Regeln - also mit der ' +
      'Antwort, die auch ein Client bekäme.');
  Log('Achtung: der Server rollt nichts zurück. Ein Schreibvorgang wird ' +
      'vor dem Ausführen noch einmal bestätigt.');
end;

function TFormEditor.ServerConnect: boolean;
var
  host, port: string;
  p: integer;
begin
  host := Trim(EditServer.Text);
  port := string(APPSQL_PORT);
  p := Pos(':', host);
  if p > 0 then
  begin
    port := Copy(host, p + 1, MaxInt);
    host := Copy(host, 1, p - 1);
  end;
  result := ConnectClient(RawUtf8(host), RawUtf8(port));
  if not result then
    Log('No server at ' + RawUtf8(EditServer.Text) + '.');
end;

{ The run a client would make, from the editor.

  Everything the editor's own run cannot answer is answered here, because the
  call goes through the whole server: is this key registered at all, does the
  caller's mask meet the template's, does CallerScope bind an identity, do
  the rules hold. What is given up for that is the draft: an unsaved
  statement has no key on the server, and giving the server a method to run
  one would throw away the property the sample exists to show.

  And the rollback promise does not hold here - the server commits. That is
  not something to paper over with a checkbox, so a write asks first. }
procedure TFormEditor.RunThroughServer(const Rec: TSqlRec;
  const Bounds: TBoundArray);
var
  res: TRunResult;
  values: variant;
  msg: RawUtf8;
  status: TSqlStatus;
  write: boolean;
begin
  res := default(TRunResult);
  res.Status := sqlFailed;
  res.Json := '[]';
  if Rec.ActionKey = '' then
  begin
    Say('Ohne Action-Key kann der Server nichts ausführen.', stBad);
    exit;
  end;
  if (Rec.RecordType <> '') and
     (RecordKindFromActionKey(Rec.ActionKey) in [raInsert, raUpdate]) then
  begin
    { a record write has no parameter list to send - it goes through
      RunRecordThroughServer, which "Testen" picks for this kind of key
      before it ever gets here }
    Say('Record-Schreibvorgang: die Werte kommen aus dem Record, nicht aus ' +
      'der Parameterliste - "Testen" nimmt dafür den Record-Weg.', stHint);
    exit;
  end;
  if Rec.Sql <> '' then
    write := KindOf(Rec.Sql) = skWrite
  else
    write := RecordKindFromActionKey(Rec.ActionKey) = raDelete;
  if write then
    { the one promise this tool makes, and the one place it cannot keep it }
    if MessageDlg('Über den Server ausführen',
         'Der Server führt diesen Schreibvorgang wirklich aus und rollt ' +
         'nichts zurück.'#13#10 + 'Die Zeilen bleiben so, wie sie danach ' +
         'sind. Fortfahren?',
         mtWarning, [mbYes, mbNo], 0) <> mrYes then
    begin
      Say('Abgebrochen - nichts ausgeführt.', stOk);
      exit;
    end;
  if not BoundsToVariant(Bounds, values, msg) then
  begin
    Say(msg, stBad);
    exit;
  end;
  if not ServerConnect then
    exit;
  try
    try
      res.Json := '[]';
      if write then
        status := SqlTool.WriteDataForAction(Rec.ActionKey, values)
      else
        status := SqlTool.GetJsonFromAction(Rec.ActionKey, values, res.Json);
      { the server was started with "token": ask once, then run it again }
      if status = sqlNeedsLogin then
        if ServerLogin then
          if write then
            status := SqlTool.WriteDataForAction(Rec.ActionKey, values)
          else
            status := SqlTool.GetJsonFromAction(Rec.ActionKey, values,
              res.Json);
      res.Status := status;
      if write then
        res.Kind := skWrite
      else
        res.Kind := skSelect;
      res.ExecutedSql := '';
      res.Message := FormatUtf8('Über den Server: % -> %',
        [Rec.ActionKey, ToText(status)]);
      if status = sqlNotAllowed then
        res.Message := res.Message +
          ' (die Maske des Templates gegen die des angemeldeten Kontos)';
      if status = sqlNeedsLogin then
        res.Message := res.Message + ' (nicht angemeldet)';
      if status = sqlUnknownKey then
        res.Message := FormatUtf8('% - der Server kennt diesen Schlüssel ' +
          'nicht. Erst speichern und "Server neu laden".', [res.Message]);
    except
      on E: Exception do
      begin
        res.Status := sqlFailed;
        res.Message := FormatUtf8('% %', [E.ClassType, E.Message]);
      end;
    end;
  finally
    DisconnectClient;
  end;
  ShowResult(res);
end;

{ Where a "Testen" on a record write finds its record.

  Three places, in the order the window itself reads. The JSON box first,
  because that is what the maintainer is looking at when they press the
  button - and it is editable, so a value can be changed there without
  reopening the dialog. Then what the dialog last produced for this key, which
  survives an edit to the parameter list rewriting the box. Then the
  TestBounds column, so a template that carries its own test record can be run
  without typing anything at all.

  An array in any of them is not a record: a record write has no positional
  parameters, and taking a value list for one would be exactly the confusion
  this is here to end. }
function TFormEditor.RecordJsonToTest(const Rec: TSqlRec; out Json: RawUtf8;
  out Msg: RawUtf8): boolean;

  function IsRecordJson(const Text: RawUtf8): boolean;
  begin
    result := (Text <> '') and
              _Safe(_Json(Text, JSON_FAST_FLOAT))^.IsObject;
  end;

var
  box, kept: RawUtf8;
begin
  result := true;
  box := Trim(RawUtf8(EditBoundsJson.Text));
  kept := fLastRecordJson.U[Rec.ActionKey];
  if IsRecordJson(box) then
  begin
    Json := box;
    Msg := 'Record aus "geht als JSON raus".';
    exit;
  end;
  if IsRecordJson(kept) then
  begin
    Json := kept;
    Msg := 'Record aus der letzten Eingabe im Dialog.';
    exit;
  end;
  if IsRecordJson(Rec.TestBounds) then
  begin
    Json := Rec.TestBounds;
    Msg := 'Record aus der Spalte TestBounds.';
    exit;
  end;
  result := false;
  Json := '';
  Msg := FormatUtf8('% schreibt einen Record, und es liegt keiner vor: ' +
    '"Record-Werte eingeben..." erzeugt ihn, oder die Spalte TestBounds ' +
    'trägt einen.', [Rec.ActionKey]);
end;

{ The record direction, through the server.

  A record write carries no parameter list, so it cannot take the same road as
  RunThroughServer: what goes on the wire is the one JSON object the dialog
  produced, and the server does the rest - mask, type resolution, statement.
  That is the whole reason to run it this way: the generator under test is the
  server's, reached the way a client reaches it, and not a second call to the
  same code from inside this process.

  The server commits, so this asks first, exactly as the value-list path
  does. }
procedure TFormEditor.RunRecordThroughServer(const Rec: TSqlRec;
  const Json: RawUtf8);
var
  res: TRunResult;
  status: TSqlStatus;
begin
  res := default(TRunResult);
  res.Status := sqlFailed;
  res.Json := '[]';
  res.Kind := skWrite;
  if Rec.ActionKey = '' then
  begin
    Say('Ohne Action-Key kann der Server nichts ausführen.', stBad);
    exit;
  end;
  if MessageDlg('Über den Server ausführen',
       'Der Server führt diesen Record-Schreibvorgang wirklich aus und ' +
       'rollt nichts zurück.'#13#10 + 'Die Zeile bleibt so, wie sie danach ' +
       'ist. Fortfahren?',
       mtWarning, [mbYes, mbNo], 0) <> mrYes then
  begin
    Say('Abgebrochen - nichts ausgeführt.', stOk);
    exit;
  end;
  if not ServerConnect then
    exit;
  try
    try
      status := SqlTool.WriteRecordForAction(Rec.ActionKey, Json);
      { the server was started with "token": ask once, then run it again }
      if status = sqlNeedsLogin then
        if ServerLogin then
          status := SqlTool.WriteRecordForAction(Rec.ActionKey, Json);
      res.Status := status;
      { the statement was made in the server, so there is none to show here -
        an empty box is honest, a locally generated one would not be }
      res.ExecutedSql := '';
      res.Message := FormatUtf8('Über den Server: % -> %',
        [Rec.ActionKey, ToText(status)]);
      if status = sqlNotAllowed then
        res.Message := res.Message +
          ' (die Maske des Templates gegen die des angemeldeten Kontos)';
      if status = sqlNeedsLogin then
        res.Message := res.Message + ' (nicht angemeldet)';
      if status = sqlUnknownKey then
        res.Message := FormatUtf8('% - der Server kennt diesen Schlüssel ' +
          'nicht. Erst speichern und "Server neu laden".', [res.Message]);
    except
      on E: Exception do
      begin
        res.Status := sqlFailed;
        res.Message := FormatUtf8('% %', [E.ClassType, E.Message]);
      end;
    end;
  finally
    DisconnectClient;
  end;
  ShowResult(res);
end;

function TFormEditor.ServerLogin: boolean;
var
  user, pass, msg: RawUtf8;
begin
  result := false;
  user := ClientUser; // the name comes back, the password never does
  pass := '';
  if not AskForLogin(RawUtf8(Trim(EditServer.Text)), user, pass) then
    exit;
  result := LoginClient(user, pass, msg);
  if result then
    Log('Angemeldet als ' + user + '.')
  else
    Log(msg);
end;

procedure TFormEditor.ButtonReloadServerClick(Sender: TObject);
var
  status: TSqlStatus;
begin
  PagesResult.ActivePage := TabLog;
  if not ServerConnect then
    exit;
  try
    try
      status := SqlTool.ReloadTemplates;
      { the server was started with "token": a reload is an administrative
        call like any other and needs one. Ask once, then try again }
      if status = sqlNeedsLogin then
        if ServerLogin then
          status := SqlTool.ReloadTemplates;
      if status = sqlOk then
        Log('Server reloaded its templates.')
      else if status = sqlNeedsLogin then
        Log('Der Server verlangt eine Anmeldung, und es wurde keine gemacht.')
      else
        Log('The server refused the set (' + ToText(status) +
            ') and kept the templates it had.');
    except
      on E: Exception do
        { the call reaches the server and the server is the one that fails -
          its own database may be behind the same tunnel this editor is }
        Log(FormatUtf8('Der Server hat den Reload nicht beantwortet: % %',
          [E.ClassType, E.Message]));
    end;
  finally
    DisconnectClient;
  end;
end;

end.
