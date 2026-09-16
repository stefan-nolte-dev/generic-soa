unit SqlParamTypes;

{$I mormot.defines.inc}

{ The seven kinds a template can declare for its parameters, and the coercion
  into them.

  JSON carries four types, a database column has many more, and the difference
  is what a declaration closes: a date arrives as a string and would be bound
  as text, which is where dates go wrong against SQL Server.

  An empty declaration passes the values through untouched - every template
  written before this existed still runs. }

interface

uses
  SysUtils,
  Variants,
  mormot.core.base,
  mormot.core.text,
  mormot.core.unicode,
  mormot.core.datetime,
  mormot.core.variants;

type
  /// the kinds a parameter may be declared as
  // - spkNull is a value a caller may send, never a kind a template declares:
  // a parameter that is always null is a mistake, not a design
  TSqlParamKind = (
    spkNull,
    spkBool,
    spkInt,
    spkInt64,
    spkDouble,
    spkCurrency,
    spkDate,
    spkText);
  TSqlParamKinds = array of TSqlParamKind;

const
  SQLPARAM_NAME: array[TSqlParamKind] of RawUtf8 = (
    'null', 'bool', 'int', 'int64', 'double', 'currency', 'date', 'text');

  SQLPARAM_HINT: array[TSqlParamKind] of RawUtf8 = (
    'no value',
    'true or false',
    'whole number, 32 bit',
    'whole number, 64 bit',
    'decimal point, e.g. 1234.5',
    'decimal point, 4 decimals kept',
    'ISO-8601, e.g. 2026-08-30 or 2026-08-30T14:00:00',
    'any text');

/// the kind of that name
function SqlParamKindFromName(const Name: RawUtf8;
  out Kind: TSqlParamKind): boolean;

/// read a declaration such as 'text,int,date'
// - an empty declaration is valid and yields no kinds: a template that
// declares nothing is coerced not at all, which is what lets templates
// written before this column existed keep working
function ParseParamTypes(const Declaration: RawUtf8;
  out Kinds: TSqlParamKinds; out Msg: RawUtf8): boolean;

/// render kinds back into a declaration
function ParamTypesToText(const Kinds: TSqlParamKinds): RawUtf8;

/// convert one value to its declared kind
// - a null stays null whatever the declaration: SQL NULL is valid anywhere,
// and forcing it into a type would invent a value the caller did not send
function CoerceValue(const Value: variant; Kind: TSqlParamKind;
  out Coerced: variant; out Msg: RawUtf8): boolean;

/// convert a whole parameter array to what the template declares
// - Bounds unchanged and true when the template declares nothing
// - false with Msg set when the count does not match or a value will not
// convert; the caller turns that into a refusal, never into a guess
function CoerceBounds(const Declaration: RawUtf8; const Bounds: variant;
  out Coerced: variant; out Msg: RawUtf8): boolean;

implementation

function SqlParamKindFromName(const Name: RawUtf8;
  out Kind: TSqlParamKind): boolean;
var
  k: TSqlParamKind;
  want: RawUtf8;
begin
  want := LowerCase(Trim(Name));
  for k := low(TSqlParamKind) to high(TSqlParamKind) do
    if SQLPARAM_NAME[k] = want then
    begin
      Kind := k;
      exit(true);
    end;
  Kind := spkText;
  result := false;
end;

function ParseParamTypes(const Declaration: RawUtf8;
  out Kinds: TSqlParamKinds; out Msg: RawUtf8): boolean;
var
  parts: TRawUtf8DynArray;
  i, n: PtrInt;
  k: TSqlParamKind;
begin
  Kinds := nil;
  Msg := '';
  result := true;
  if Trim(Declaration) = '' then
    exit; // declares nothing, coerces nothing
  parts := nil;
  CsvToRawUtf8DynArray(pointer(Declaration), parts, ',', {trim=}true);
  n := 0;
  SetLength(Kinds, length(parts));
  for i := 0 to high(parts) do
  begin
    if parts[i] = '' then
      continue;
    if not SqlParamKindFromName(parts[i], k) then
    begin
      Kinds := nil;
      Msg := FormatUtf8('Parameter %: unknown type "%".', [i + 1, parts[i]]);
      exit(false);
    end;
    if k = spkNull then
    begin
      Kinds := nil;
      Msg := FormatUtf8('Parameter %: "null" is a value, not a declared type.',
        [i + 1]);
      exit(false);
    end;
    Kinds[n] := k;
    inc(n);
  end;
  SetLength(Kinds, n);
end;

function ParamTypesToText(const Kinds: TSqlParamKinds): RawUtf8;
var
  i: PtrInt;
begin
  result := '';
  for i := 0 to high(Kinds) do
  begin
    if result <> '' then
      result := result + ',';
    result := result + SQLPARAM_NAME[Kinds[i]];
  end;
end;

function CoerceValue(const Value: variant; Kind: TSqlParamKind;
  out Coerced: variant; out Msg: RawUtf8): boolean;
var
  i64: Int64;
  d: double;
  c: currency;
  b: boolean;
  txt: RawUtf8;
  dt: TDateTime;
begin
  Msg := '';
  result := true;
  VarClear(Coerced);
  if VarIsNull(Value) or
     VarIsEmpty(Value) then
  begin
    { a null is valid for any column; making it a 0 or an empty string would
      be inventing a value the caller did not send }
    Coerced := Null;
    exit;
  end;
  case Kind of
    spkBool:
      if VariantToBoolean(Value, b) then
        Coerced := b
      else
        result := false;
    spkInt,
    spkInt64:
      if VariantToInt64(Value, i64) then
        if (Kind = spkInt) and
           ((i64 < low(integer)) or
            (i64 > high(integer))) then
        begin
          Msg := 'does not fit in 32 bits - declare it as int64';
          result := false;
        end
        else if Kind = spkInt then
          Coerced := integer(i64)
        else
          Coerced := i64
      else
        result := false;
    spkDouble:
      if VariantToDouble(Value, d) then
        Coerced := d
      else
        result := false;
    spkCurrency:
      if VariantToCurrency(Value, c) then
        Coerced := c
      else
        result := false;
    spkDate:
      begin
        { this is the case the whole column exists for: what arrived is a
          string, because JSON has no date, and it has to become a varDate so
          BindVariant calls BindDateTime instead of binding text }
        if TVarData(Value).VType = varDate then
          Coerced := Value
        else
        begin
          txt := VariantToUtf8(Value);
          dt := Iso8601ToDateTime(txt);
          if dt = 0 then
          begin
            Msg := 'is not an ISO-8601 date';
            result := false;
          end
          else
            Coerced := VarFromDateTime(dt);
        end;
      end;
    spkText:
      begin
        txt := VariantToUtf8(Value);
        RawUtf8ToVariant(txt, Coerced);
      end;
  else
    Coerced := Value;
  end;
  if not result then
  begin
    Coerced := Null;
    if Msg = '' then
      Msg := FormatUtf8('is not a %', [SQLPARAM_NAME[Kind]]);
  end;
end;

function CoerceBounds(const Declaration: RawUtf8; const Bounds: variant;
  out Coerced: variant; out Msg: RawUtf8): boolean;
var
  kinds: TSqlParamKinds;
  src: PDocVariantData;
  arr: TDocVariantData;
  one: variant;
  i: PtrInt;
  why: RawUtf8;
begin
  Coerced := Bounds;
  if not ParseParamTypes(Declaration, kinds, Msg) then
    exit(false);
  if kinds = nil then
    exit(true); // nothing declared: hand the values on untouched
  src := _Safe(Bounds);
  if not src^.IsArray and
     (src^.Count <> 0) then
  begin
    Msg := 'The parameters are not an array.';
    exit(false);
  end;
  if src^.Count <> length(kinds) then
  begin
    Msg := FormatUtf8('The template declares % parameter(s), % were sent.',
      [length(kinds), src^.Count]);
    exit(false);
  end;
  arr.InitArray([], JSON_FAST_FLOAT);
  for i := 0 to high(kinds) do
  begin
    if not CoerceValue(src^.Values[i], kinds[i], one, why) then
    begin
      Msg := FormatUtf8('Parameter % %.', [i + 1, why]);
      exit(false);
    end;
    arr.AddItem(one);
  end;
  Coerced := variant(arr);
  Msg := FormatUtf8('% parameter(s) coerced.', [length(kinds)]);
  result := true;
end;

end.
