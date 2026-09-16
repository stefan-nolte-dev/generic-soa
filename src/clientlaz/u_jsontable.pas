unit u_jsontable;

{$mode objfpc}{$H+}

{ The rows the server sent, as a plain text table.

  The same view the editor's grid gives, but without a grid: a TMemo in a
  monospaced font is enough, and this way the test client stays one form and
  two memos.

  Written once, for every action key there will ever be. It is told nothing
  about the query - the column names are read out of the JSON itself, as the
  union over all rows in the order they first appear. That is the rule the
  editor's grid and its type generator use as well, so the three cannot
  disagree about what a result set looks like. }

interface

uses
  SysUtils,
  mormot.core.base;

/// the JSON object array as an aligned table, header row included
// - '(no rows)' when the array is empty, and the JSON itself when it is not
// an array of objects at all: this is a view, it never raises
function JsonAsTextTable(const Json: RawUtf8): string;

/// what the server put on the wire, indented
function JsonPretty(const Json: RawUtf8): string;

implementation

uses
  Variants, // for VarIsNull
  LazUTF8,  // for UTF8Length - a column is as wide as its widest char count
  mormot.core.text,
  mormot.core.unicode, // for FindRawUtf8 and AddRawUtf8
  mormot.core.json,
  mormot.core.variants;

function Pad(const Text: string; Width: PtrInt): string;
var
  n: PtrInt;
begin
  result := Text;
  { byte length would misalign every column holding an umlaut }
  n := Width - UTF8Length(Text);
  if n > 0 then
    result := result + StringOfChar(' ', n);
end;

function JsonAsTextTable(const Json: RawUtf8): string;
var
  doc: variant;
  rows, row: PDocVariantData;
  names: TRawUtf8DynArray;
  width: array of PtrInt;
  cells: array of array of string;
  r, c, idx: PtrInt;
  v: RawUtf8;
  line: string;
begin
  result := '';
  names := nil;
  if Json = '' then
    exit('(nothing returned)');
  doc := _Json(Json, JSON_FAST_FLOAT);
  rows := _Safe(doc);
  if not rows^.IsArray then
    exit(string(Json)); // not a result set - show it as it came
  if rows^.Count = 0 then
    exit('(no rows)');
  { the column set: the union over all rows, in first appearance order }
  for r := 0 to rows^.Count - 1 do
  begin
    row := _Safe(rows^.Values[r]);
    for c := 0 to row^.Count - 1 do
      if FindRawUtf8(names, row^.Names[c], {casesensitive=}true) < 0 then
        AddRawUtf8(names, row^.Names[c]);
  end;
  if names = nil then
    exit(string(Json)); // an array of something other than objects
  SetLength(width, length(names));
  SetLength(cells, rows^.Count, length(names));
  for c := 0 to high(names) do
    width[c] := UTF8Length(string(names[c]));
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
      cells[r, c] := string(v);
      if UTF8Length(cells[r, c]) > width[c] then
        width[c] := UTF8Length(cells[r, c]);
    end;
  end;
  line := '';
  for c := 0 to high(names) do
    line := line + Pad(string(names[c]), width[c]) + '  ';
  result := TrimRight(line) + LineEnding;
  line := '';
  for c := 0 to high(names) do
    line := line + StringOfChar('-', width[c]) + '  ';
  result := result + TrimRight(line) + LineEnding;
  for r := 0 to rows^.Count - 1 do
  begin
    line := '';
    for c := 0 to high(names) do
      line := line + Pad(cells[r, c], width[c]) + '  ';
    result := result + TrimRight(line) + LineEnding;
  end;
end;

function JsonPretty(const Json: RawUtf8): string;
begin
  if Json = '' then
    result := ''
  else
    result := string(JsonReformat(Json, jsonHumanReadable));
end;

end.
