unit u_logindialog;

{ The login window, built at run time.

  No LFM: it is three controls and a pair of buttons, and a form file for
  that is more to keep in step than to gain. The editor will want the same
  window in its own project, and a unit without a resource travels between
  the two without anything to synchronise.

  It collects a name and a password and hands them on. It does not log in
  itself: whoever opened it holds the connection, and this window knowing
  about servers would put a second place in the program that does. }

{$mode objfpc}{$H+}
{ The source of this unit is UTF-8, and its literals carry umlauts. Without
  this the compiler reads them as the system codepage and re-encodes them on
  the way into a RawUtf8 parameter, which turns "Ü" into "Ã" on screen. }
{$codepage UTF8}

interface

uses
  SysUtils,
  Classes,
  Controls,
  Forms,
  StdCtrls,
  Graphics,
  mormot.core.base;

/// ask for a name and a password
// - false when the window was cancelled; the values are then untouched
// - Server is shown above the fields, because someone with two profiles open
// needs to see which one they are logging into
function AskForLogin(const Server: RawUtf8;
  var UserName, Password: RawUtf8): boolean;

implementation

function AskForLogin(const Server: RawUtf8;
  var UserName, Password: RawUtf8): boolean;
var
  dlg: TForm;
  lblServer, lblUser, lblPass: TLabel;
  edUser, edPass: TEdit;
  btnOk, btnCancel: TButton;
begin
  result := false;
  dlg := TForm.CreateNew(nil);
  try
    dlg.Caption := 'Anmelden';
    dlg.Position := poScreenCenter;
    dlg.BorderStyle := bsDialog;
    dlg.ClientWidth := 360;
    dlg.ClientHeight := 160;

    lblServer := TLabel.Create(dlg);
    lblServer.Parent := dlg;
    lblServer.SetBounds(16, 12, 330, 16);
    lblServer.Caption := 'Server: ' + Utf8ToString(Server);

    lblUser := TLabel.Create(dlg);
    lblUser.Parent := dlg;
    lblUser.SetBounds(16, 48, 80, 16);
    lblUser.Caption := 'Benutzer:';

    edUser := TEdit.Create(dlg);
    edUser.Parent := dlg;
    edUser.SetBounds(104, 44, 240, 24);
    edUser.Text := Utf8ToString(UserName);

    lblPass := TLabel.Create(dlg);
    lblPass.Parent := dlg;
    lblPass.SetBounds(16, 84, 80, 16);
    lblPass.Caption := 'Passwort:';

    edPass := TEdit.Create(dlg);
    edPass.Parent := dlg;
    edPass.SetBounds(104, 80, 240, 24);
    { the one thing this window must get right }
    edPass.EchoMode := emPassword;
    edPass.PasswordChar := '*';

    btnOk := TButton.Create(dlg);
    btnOk.Parent := dlg;
    btnOk.SetBounds(160, 120, 90, 28);
    btnOk.Caption := 'Anmelden';
    btnOk.ModalResult := mrOk;
    btnOk.Default := true;

    btnCancel := TButton.Create(dlg);
    btnCancel.Parent := dlg;
    btnCancel.SetBounds(256, 120, 90, 28);
    btnCancel.Caption := 'Abbrechen';
    btnCancel.ModalResult := mrCancel;
    btnCancel.Cancel := true;

    if edUser.Text = '' then
      dlg.ActiveControl := edUser
    else
      dlg.ActiveControl := edPass;
    if dlg.ShowModal <> mrOk then
      exit;
    UserName := RawUtf8(Trim(edUser.Text));
    Password := RawUtf8(edPass.Text); // never trimmed: a space may be in it
    result := UserName <> '';
  finally
    { and the password goes with it: nothing here keeps a copy }
    dlg.Free;
  end;
end;

end.
