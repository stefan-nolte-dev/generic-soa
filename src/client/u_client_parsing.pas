unit u_client_parsing;

{$I mormot.defines.inc}

{ The client side of the generic service - all of it, four functions.

  Each is written once for every query and every record there will ever be.
  No generics on purpose: Delphi and Lazarus differ in syntax there, while an
  untyped parameter with PRttiInfo works identically on both.

  This is where the type re-enters. The server sent JSON, the caller named the
  type, and from here on the code is as typed as one method per query would
  be - Customers[0].City, checked by the compiler. }

interface

uses
  mormot.core.base,
  mormot.core.rtti,
  mormot.core.text,     // for UniqueRawUtf8
  mormot.core.unicode,  // for GotoNextNotSpace
  mormot.core.json,
  mormot.core.variants, // for _Arr, wrapping the one key value
  SqlStatus,
  AppSqlClient;

function ParseDynArray(const Action: RawUtf8; const Bounds: variant;
  var arr; TI: PRttiInfo): TSqlStatus;

/// the same, and also hand back what the server actually sent
// - only for showing it: the test client puts it in a memo, and the editor
// shows the same bytes. Nothing in a real client should need this
function ParseDynArrayJson(const Action: RawUtf8; const Bounds: variant;
  var arr; TI: PRttiInfo; out Json: RawUtf8): TSqlStatus;

/// send one whole record to a registered insert or update
// - the mirror image of ParseDynArray and just as generic: an untyped
// parameter and the RTTI of its type
// - the type has to be one the server knows by name - see WriteDtos
function WriteRecord(const Action: RawUtf8; const Rec;
  TI: PRttiInfo): TSqlStatus;

/// fetch one row by its key into a record
// - the counterpart of WriteRecord, and deliberately NOT its mirror image:
// nothing is sent but the key. The columns to read are the fields of the
// record type, and the server knows them from the RecordType column of the
// template - so a subset never has to travel, the way an ORM sends a list of
// field names and not a record
// - the type has to be one the server knows by name: compiled in, see
// WriteDtos, or declared in the template's RecordDecl column
// - Rec is left untouched when nothing matched: the status says which
function RetrieveRecord(const Action: RawUtf8; const Key: variant;
  var Rec; TI: PRttiInfo): TSqlStatus;

/// delete one row by its key
// - takes no record and no type at all: the template names the type, and
// the type only ever contributes the table name here
function DeleteRecord(const Action: RawUtf8; const Key: variant): TSqlStatus;

implementation

function ParseDynArrayJson(const Action: RawUtf8; const Bounds: variant;
  var arr; TI: PRttiInfo; out Json: RawUtf8): TSqlStatus;
begin
  Json := ''; // var parameter on the wire: read on entry, so initialise it
  result := SqlTool.GetJsonFromAction(Action, Bounds, Json);
  if (result = sqlOk) and
     (Json <> '') then
    DynArrayLoadJson(arr, Json, TI);
end;

function ParseDynArray(const Action: RawUtf8; const Bounds: variant;
  var arr; TI: PRttiInfo): TSqlStatus;
var
  json: RawUtf8;
begin
  result := ParseDynArrayJson(Action, Bounds, arr, TI, json);
end;

function WriteRecord(const Action: RawUtf8; const Rec;
  TI: PRttiInfo): TSqlStatus;
begin
  { SaveJson and not a variant, which is the whole trick: a TDateTime put
    into a variant reaches the server as a plain string and is bound as text.
    Serialised from the record and read back into it, it stays a date. }
  result := SqlTool.WriteRecordForAction(Action, SaveJson(Rec, TI));
end;

function RetrieveRecord(const Action: RawUtf8; const Key: variant;
  var Rec; TI: PRttiInfo): TSqlStatus;
var
  json: RawUtf8;
  p: PUtf8Char;
begin
  json := ''; // var parameter on the wire, as in ParseDynArrayJson
  { one value, and it is the key - the same call every ordinary select uses }
  result := SqlTool.GetJsonFromAction(Action, _Arr([Key]), json);
  if result <> sqlOk then
    exit; // sqlNoRows for a key that matched nothing, and Rec stays as it was
  { a select answers with rows, so with an array. A retrieve on a key has one
    row in it, and that row is the record }
  UniqueRawUtf8(json); // InPlace unescapes inside the buffer it is given
  p := GotoNextNotSpace(pointer(json));
  if p^ = '[' then
    p := GotoNextNotSpace(p + 1);
  if (p^ <> '{') or
     (RecordLoadJsonInPlace(Rec, p, TI) = nil) then
    { the server ran the statement and returned a row, so this is the two
      sides disagreeing about the shape of the record - not a failed query }
    result := sqlBadParams;
end;

function DeleteRecord(const Action: RawUtf8; const Key: variant): TSqlStatus;
begin
  { sqlNothingWritten when the key matched nothing, which is the honest
    answer and not an error }
  result := SqlTool.WriteDataForAction(Action, _Arr([Key]));
end;

end.
