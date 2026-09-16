unit RecordDialog;

{$I mormot.defines.inc}
{ The source of this unit is UTF-8, and its literals carry umlauts. Without
  this the compiler reads them as the system codepage and re-encodes them on
  the way into a RawUtf8 parameter, which turns "Ü" into "Ã" on screen. }
{$codepage UTF8}

{ One dialog for every record there will ever be.

  The same idea as everything else here: no form per type. The record type is
  resolved - compiled in, or registered from the RecordDecl column - and its
  fields become the rows of a dialog that is built when it is opened and torn
  down when it closes. A record with a field more needs nothing here.

  Which is also why it is built in code rather than designed: an LFM would
  have to name controls that only exist once a type has been read.

  It produces JSON and nothing else. That is deliberate - the JSON is exactly
  what a client would put on the wire, so what the editor tests below it is
  the path the server runs, not a second one written for the editor. }

interface

uses
  SysUtils, Classes, Controls, Forms, StdCtrls, Graphics, Dialogs,
  mormot.core.base,
  mormot.core.text,
  mormot.core.unicode, // for IdemPropNameU and StringReplaceChars
  mormot.core.json,    // for QuotedStrJson
  mormot.core.rtti,
  mormot.core.datetime,
  mormot.core.variants, // for _Safe, reading the row that was preset
  SqlTemplateTypes;

/// let the user fill the fields of a record, and hand back its JSON
// - false when the dialog was cancelled; Json is then untouched
// - the values are typed the way the field is: a number goes in unquoted, so
// the server binds an integer as an integer and not as text - the whole
// point of sending a record rather than a list of strings
// - Preset fills the fields it names and nothing else: a row read back from
// the database, or null to open on defaults. It is a plain document, not a
// connection - this unit never learns that a database exists
function EditRecordValues(const Rec: TSqlRec; rc: TRttiCustom;
  const Preset: variant; out Json: RawUtf8): boolean;

implementation

{ what to put in an empty field, so the dialog opens on something valid }
function DefaultFor(pt: TRttiParserType): string;
begin
  case pt of
    ptBoolean:
      result := 'false';
    ptByte, ptCardinal, ptInt64, ptInteger, ptQWord, ptWord:
      result := '0';
    ptCurrency, ptDouble, ptExtended, ptSingle:
      result := '0';
    ptDateTime, ptDateTimeMS:
      result := string(DateTimeToIso8601Text(Now));
  else
    result := '';
  end;
end;

{ the one place that decides how a typed value is written into JSON }
function ValueToJson(pt: TRttiParserType; const Text: string;
  out Value: RawUtf8; out Msg: string): boolean;
var
  u: RawUtf8;
  i: Int64;
  d: double;
begin
  result := true;
  Msg := '';
  u := TrimU(RawUtf8(Text));
  case pt of
    ptBoolean:
      if (u = '') or
         IdemPropNameU(u, 'false') or
         (u = '0') then
        Value := 'false'
      else if IdemPropNameU(u, 'true') or
              (u = '1') then
        Value := 'true'
      else
      begin
        Msg := 'true oder false';
        result := false;
      end;
    ptByte, ptCardinal, ptInt64, ptInteger, ptQWord, ptWord:
      begin
        if u = '' then
          u := '0';
        if ToInt64(u, i) then
          Value := u
        else
        begin
          Msg := 'eine ganze Zahl';
          result := false;
        end;
      end;
    ptCurrency, ptDouble, ptExtended, ptSingle:
      begin
        if u = '' then
          u := '0';
        { a comma is what a German keyboard produces, and JSON wants a point.
          Accepting it here beats a puzzling refusal }
        u := StringReplaceChars(u, ',', '.');
        if ToDouble(u, d) then
          Value := u
        else
        begin
          Msg := 'eine Zahl';
          result := false;
        end;
      end;
  else
    { everything else travels as a JSON string - a date included: the record
      reads it back as a TDateTime, which is what restores the type }
    Value := QuotedStrJson(u);
  end;
end;

function EditRecordValues(const Rec: TSqlRec; rc: TRttiCustom;
  const Preset: variant; out Json: RawUtf8): boolean;
const
  ROW = 28;
  TOP = 52;
var
  form: TForm;
  head: TLabel;
  edits: array of TEdit;
  lab: TLabel;
  ok, cancel: TButton;
  i, y: integer;
  w: RawUtf8;
  msg: string;
  p: PRttiCustomProp;
begin
  result := false;
  Json := '';
  form := TForm.CreateNew(nil);
  try
    form.Caption := 'Record bearbeiten - ' + string(Rec.ActionKey);
    form.BorderStyle := bsDialog;
    form.Position := poScreenCenter;
    form.ClientWidth := 460;
    form.ClientHeight := TOP + rc.Props.Count * ROW + 56;

    head := TLabel.Create(form);
    head.Parent := form;
    head.SetBounds(16, 14, 430, 18);
    if _Safe(Preset)^.Count > 0 then
      head.Caption := Format('%s - %d Feld(er), aus der Datenbank vorbelegt. ' +
        'Die Werte gehen als JSON hinaus, so wie ein Client sie schickt.',
        [string(rc.Name), rc.Props.Count])
    else
      head.Caption := Format('%s - %d Feld(er). Die Werte gehen als JSON ' +
        'hinaus, so wie ein Client sie schickt.',
        [string(rc.Name), rc.Props.Count]);
    head.AutoSize := false;
    head.WordWrap := true;
    head.SetBounds(16, 10, 430, 34);

    SetLength(edits, rc.Props.Count);
    y := TOP;
    for i := 0 to rc.Props.Count - 1 do
    begin
      p := @rc.Props.List[i];
      lab := TLabel.Create(form);
      lab.Parent := form;
      lab.SetBounds(16, y + 4, 130, 18);
      lab.Caption := string(p^.Name);
      edits[i] := TEdit.Create(form);
      edits[i].Parent := form;
      edits[i].SetBounds(150, y, 200, 22);
      { what the row holds for this field, when a row was read - matched by
        name and case insensitively, so the column order cannot shift a value
        into the wrong field }
      if not _Safe(Preset)^.GetAsRawUtf8(p^.Name, w) then
        edits[i].Text := DefaultFor(p^.Value.Parser)
      else
        edits[i].Text := string(w);
      edits[i].TabOrder := i;
      lab := TLabel.Create(form);
      lab.Parent := form;
      lab.SetBounds(360, y + 4, 90, 18);
      { the type the value will be bound as, next to the field it belongs to:
        the same text the Prüfen button lists }
      lab.Caption := string(mormot.core.rtti.ToText(p^.Value.Parser)^);
      lab.Font.Color := clGrayText;
      inc(y, ROW);
    end;

    cancel := TButton.Create(form);
    cancel.Parent := form;
    cancel.SetBounds(230, y + 14, 100, 27);
    cancel.Caption := 'Abbrechen';
    cancel.ModalResult := mrCancel;
    cancel.Cancel := true;
    ok := TButton.Create(form);
    ok.Parent := form;
    ok.SetBounds(340, y + 14, 100, 27);
    ok.Caption := 'Übernehmen';
    ok.ModalResult := mrOk;
    ok.Default := true;

    { a value that does not parse reopens the dialog rather than closing it:
      the form is still alive, so everything typed is still there }
    while form.ShowModal = mrOk do
    begin
      Json := '';
      msg := '';
      for i := 0 to rc.Props.Count - 1 do
      begin
        p := @rc.Props.List[i];
        if not ValueToJson(p^.Value.Parser, edits[i].Text, w, msg) then
        begin
          MessageDlg('Wert passt nicht zum Feld',
            Format('%s erwartet %s.', [string(p^.Name), msg]),
            mtWarning, [mbOK], 0);
          edits[i].SetFocus;
          Json := '';
          break;
        end;
        if Json <> '' then
          Json := Json + ',';
        Json := Json + QuotedStrJson(p^.Name) + ':' + w;
      end;
      if msg = '' then
      begin
        Json := '{' + Json + '}';
        exit(true);
      end;
    end;
  finally
    form.Free;
  end;
end;

end.
