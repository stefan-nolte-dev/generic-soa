unit SqlBounds;

{ Typed parameter values for the editor, and the two ways into a statement.

  Why a variant and not an array of const: the contract carries
  Bounds: variant, and that is not a matter of style. VariantToVarRec wraps
  every value as vtVariant by reference, so BindVariant dispatches on the
  VARIANT's type - varDate to BindDateTime, varCurrency to BindCurrency.
  Building the const array here would let the editor express values no client
  could send. So it builds the variant, exactly as a client would.

  Which is why JsonRoundTrip matters. A real client sends JSON, and JSON knows
  null, boolean, number and string. A varDate travels as an ISO-8601 string, a
  varCurrency as a number, so a bound set that works here can be a different
  set by the time the server binds it. The editor serialises the values, reads
  them back and names the ones that changed. }
{$I mormot.defines.inc}
interface

uses
  SysUtils,
  Variants,
  mormot.core.base,
  mormot.core.text,
  mormot.core.unicode,
  mormot.core.datetime,
  mormot.core.variants,
  SqlParamTypes;

type
  /// the value kinds a variant can carry into BindVariant
  // - the list itself now lives in SqlParamTypes, in common, because the
  // application layer needs the same one to coerce what a client sent. Two
  // lists that had to agree would eventually not
  TBoundKind = TSqlParamKind;

  /// one parameter, as the user entered it
  TBound = packed record
    Kind: TBoundKind;
    /// the value as typed; ignored for bkNull
    Text: RawUtf8;
  end;
  TBoundArray = array of TBound;

const
  bkNull      = spkNull;
  bkBool      = spkBool;
  bkInt       = spkInt;
  bkInt64     = spkInt64;
  bkDouble    = spkDouble;
  bkCurrency  = spkCurrency;
  bkDate      = spkDate;
  bkText      = spkText;

/// the kind whose name this is, or false when there is no such kind
function BoundKindFromName(const Name: RawUtf8; out Kind: TBoundKind): boolean;

/// the editable form: one parameter per line, as [kind] value
function BoundsToText(const Bounds: TBoundArray): RawUtf8;

/// read that form back
// - a line without brackets is taken as [text], so a quick edit still works
function TextToBounds(const Text: RawUtf8; out Bounds: TBoundArray;
  out Msg: RawUtf8): boolean;

/// build the variant array a client would send
// - values are appended one at a time, which is also how the form's
// "add" button grows the list
function BoundsToVariant(const Bounds: TBoundArray; out Value: variant;
  out Msg: RawUtf8): boolean;

/// what would actually travel: the JSON of that variant
function BoundsToJson(const Value: variant): RawUtf8;

/// name the parameters whose type would not survive the trip as JSON
// - returns true when nothing changes, so a false is worth reading
// - the check is faithful and not an approximation: it re-reads with
// JSON_FAST_FLOAT, which is what TInterfaceFactory sets as fDocVariantOptions
// for a variant argument, so this is the server's own parsing
function JsonRoundTrip(const Value: variant; out Msg: RawUtf8): boolean;

/// the declaration these values imply, e.g. 'text,int'
// - the kind was already chosen once, when the value was entered, so making
// the maintainer type it a second time into the declaration field is asking
// for the two to disagree
// - false when a value is [null]: a null is a value a caller may send, never
// a kind a template can declare, so that position cannot be derived
function BoundsToParamTypes(const Bounds: TBoundArray;
  out Declaration, Msg: RawUtf8): boolean;

/// put the values into the statement as SQL literals, binding nothing
// - the counter-check: if this and the bound run disagree, the binding is
// where to look
// - THIS BUILDS SQL BY CONCATENATION. It exists so a developer can compare
// two paths on a development database, and it must never become reachable
// from the server - that is the whole point of the template registry
function InlineBounds(const Sql: RawUtf8; const Bounds: TBoundArray;
  out Inlined, Msg: RawUtf8): boolean;

implementation

function BoundKindFromName(const Name: RawUtf8; out Kind: TBoundKind): boolean;
begin
  result := SqlParamKindFromName(Name, Kind);
end;

function BoundsToText(const Bounds: TBoundArray): RawUtf8;
var
  i: PtrInt;
begin
  result := '';
  for i := 0 to high(Bounds) do
    result := result + FormatUtf8('[%] %'#13#10,
      [SQLPARAM_NAME[Bounds[i].Kind], Bounds[i].Text]);
end;

function TextToBounds(const Text: RawUtf8; out Bounds: TBoundArray;
  out Msg: RawUtf8): boolean;
var
  lines: TRawUtf8DynArray;
  line, name: RawUtf8;
  i, n, close: PtrInt;
  kind: TBoundKind;
begin
  Bounds := nil;
  Msg := '';
  result := true;
  lines := nil;
  CsvToRawUtf8DynArray(pointer(StringReplaceAll(Text, #13#10, #10)),
    lines, #10, {trim=}true);
  n := 0;
  for i := 0 to high(lines) do
  begin
    line := Trim(lines[i]);
    if line = '' then
      continue; // a blank line is not a null parameter, it is nothing
    SetLength(Bounds, n + 1);
    if (line[1] = '[') then
    begin
      close := PosExChar(']', line);
      if close = 0 then
      begin
        Msg := FormatUtf8('Line %: [ without ].', [i + 1]);
        exit(false);
      end;
      name := copy(line, 2, close - 2);
      if not BoundKindFromName(name, kind) then
      begin
        Msg := FormatUtf8('Line %: unknown type "%".', [i + 1, name]);
        exit(false);
      end;
      Bounds[n].Kind := kind;
      Bounds[n].Text := Trim(copy(line, close + 1, maxInt));
    end
    else
    begin
      Bounds[n].Kind := bkText;
      Bounds[n].Text := line;
    end;
    inc(n);
  end;
  SetLength(Bounds, n);
  Msg := FormatUtf8('% parameter(s).', [n]);
end;

function BoundsToVariant(const Bounds: TBoundArray; out Value: variant;
  out Msg: RawUtf8): boolean;
var
  arr: TDocVariantData;
  i: PtrInt;
  v: variant;
  i64: Int64;
  d: double;
  c: currency;
  dt: TDateTime;
  b: TBound;
  err: integer; // GetExtended reports a position, not a flag
begin
  Msg := '';
  result := false;
  arr.InitArray([], JSON_FAST_FLOAT);
  for i := 0 to high(Bounds) do
  begin
    b := Bounds[i];
    VarClear(v);
    case b.Kind of
      bkNull:
        v := Null;
      bkBool:
        if IdemPropNameU(b.Text, 'true') or
           (b.Text = '1') then
          v := true
        else if IdemPropNameU(b.Text, 'false') or
                (b.Text = '0') then
          v := false
        else
        begin
          Msg := FormatUtf8('Parameter %: "%" is not true or false.',
            [i + 1, b.Text]);
          exit;
        end;
      bkInt,
      bkInt64:
        begin
          if not ToInt64(b.Text, i64) then
          begin
            Msg := FormatUtf8('Parameter %: "%" is not a whole number.',
              [i + 1, b.Text]);
            exit;
          end;
          if b.Kind = bkInt then
          begin
            if (i64 < low(integer)) or
               (i64 > high(integer)) then
            begin
              Msg := FormatUtf8('Parameter %: % does not fit in 32 bits - ' +
                'use int64.', [i + 1, b.Text]);
              exit;
            end;
            v := integer(i64);
          end
          else
            v := i64;
        end;
      bkDouble:
        begin
          d := GetExtended(pointer(b.Text), err);
          if err <> 0 then
          begin
            Msg := FormatUtf8('Parameter %: "%" is not a number.',
              [i + 1, b.Text]);
            exit;
          end;
          v := d;
        end;
      bkCurrency:
        begin
          d := GetExtended(pointer(b.Text), err);
          if err <> 0 then
          begin
            Msg := FormatUtf8('Parameter %: "%" is not a number.',
              [i + 1, b.Text]);
            exit;
          end;
          c := d;
          v := c;
        end;
      bkDate:
        begin
          dt := Iso8601ToDateTime(b.Text);
          if dt = 0 then
          begin
            Msg := FormatUtf8('Parameter %: "%" is not an ISO-8601 date.',
              [i + 1, b.Text]);
            exit;
          end;
          v := VarFromDateTime(dt); // varDate, so BindVariant calls BindDateTime
        end;
      bkText:
        RawUtf8ToVariant(b.Text, v);
    end;
    arr.AddItem(v); // one at a time - the same growth the form's button does
  end;
  Value := variant(arr);
  Msg := FormatUtf8('% parameter(s) built.', [length(Bounds)]);
  result := true;
end;

function BoundsToJson(const Value: variant): RawUtf8;
begin
  result := VariantSaveJson(Value, twJsonEscape);
  if result = '' then
    result := '[]';
end;

function JsonRoundTrip(const Value: variant; out Msg: RawUtf8): boolean;
var
  back: variant;
  a, b: PDocVariantData;
  i: PtrInt;
begin
  Msg := '';
  result := true;
  back := _Json(BoundsToJson(Value), JSON_FAST_FLOAT);
  a := _Safe(Value);
  b := _Safe(back);
  if a^.Count <> b^.Count then
  begin
    Msg := 'The values do not survive JSON at all.';
    exit(false);
  end;
  for i := 0 to a^.Count - 1 do
    if TVarData(a^.Values[i]).VType <> TVarData(b^.Values[i]).VType then
    begin
      Msg := Msg + FormatUtf8(
        '- parameter % changes type on the way through JSON, which is what a ' +
        'real client sends. Bound here, it would not be bound that way there.'
        + #13#10, [i + 1]);
      result := false;
    end;
  if result then
    Msg := 'Every value survives JSON unchanged - a client could send this set.';
end;

function BoundsToParamTypes(const Bounds: TBoundArray;
  out Declaration, Msg: RawUtf8): boolean;
var
  i: PtrInt;
  kinds: TSqlParamKinds;
begin
  Declaration := '';
  Msg := '';
  if Bounds = nil then
  begin
    Msg := 'No parameters to derive types from.';
    exit(false);
  end;
  SetLength(kinds, length(Bounds));
  for i := 0 to high(Bounds) do
  begin
    if Bounds[i].Kind = spkNull then
    begin
      Msg := FormatUtf8('Parameter % is [null], which is a value and not a ' +
        'type. Enter it with the type it would have, then declare it.',
        [i + 1]);
      exit(false);
    end;
    kinds[i] := Bounds[i].Kind;
  end;
  Declaration := ParamTypesToText(kinds);
  Msg := FormatUtf8('Types taken from the parameters: %.', [Declaration]);
  result := true;
end;

function SqlLiteral(const Bound: TBound; out Literal, Msg: RawUtf8): boolean;
var
  one: TBoundArray;
  v: variant;
  d: TDateTime;
begin
  Msg := '';
  result := true;
  case Bound.Kind of
    bkNull:
      Literal := 'null';
    bkBool:
      if IdemPropNameU(Bound.Text, 'true') or
         (Bound.Text = '1') then
        Literal := '1'
      else
        Literal := '0';
    bkDate:
      begin
        d := Iso8601ToDateTime(Bound.Text);
        Literal := QuotedStr(DateTimeToIso8601Text(d, ' '));
      end;
    bkText:
      Literal := QuotedStr(Bound.Text);
  else
    begin
      { numbers: go through the same parsing the bound path uses, so a value
        the bound run rejects is not silently accepted here }
      SetLength(one, 1);
      one[0] := Bound;
      if not BoundsToVariant(one, v, Msg) then
        exit(false);
      Literal := VariantToUtf8(_Safe(v)^.Values[0]);
    end;
  end;
end;

function InlineBounds(const Sql: RawUtf8; const Bounds: TBoundArray;
  out Inlined, Msg: RawUtf8): boolean;
var
  i, used: PtrInt;
  inString: boolean;
  lit: RawUtf8;
begin
  Inlined := '';
  Msg := '';
  used := 0;
  inString := false;
  for i := 1 to length(Sql) do
    if (Sql[i] = '?') and
       not inString then
    begin
      if used > high(Bounds) then
      begin
        Msg := FormatUtf8('The statement has more ? than the % value(s) given.',
          [length(Bounds)]);
        exit(false);
      end;
      if not SqlLiteral(Bounds[used], lit, Msg) then
        exit(false);
      Inlined := Inlined + lit;
      inc(used);
    end
    else
    begin
      if Sql[i] = '''' then
        inString := not inString;
      Inlined := Inlined + Sql[i];
    end;
  if used <> length(Bounds) then
  begin
    Msg := FormatUtf8('% value(s) given but only % ? in the statement.',
      [length(Bounds), used]);
    exit(false);
  end;
  Msg := FormatUtf8('% value(s) written into the statement.', [used]);
  result := true;
end;

end.
