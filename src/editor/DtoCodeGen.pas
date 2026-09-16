unit DtoCodeGen;

{ Turn a result set into the Pascal source of the record that receives it.

  The one piece of hand work the action key approach leaves in the client, and
  the one that is easy to get subtly wrong: the field names have to match the
  column names of the statement. Mechanical, so it is generated here.

  The types are inferred from the JSON the server actually returned, not from
  the database metadata, on purpose: SQLite reports no useful type for an
  expression such as count(i.ID) before the first row, and what the record has
  to match is what arrives over the wire anyway. Every returned row is
  inspected, so a null in the first one does not decide the type.

  Inference is a starting point, not an authority. A column that was null in
  every row cannot be typed at all, and a numeric column holding whole numbers
  only in the sample data comes out as an integer. The generator says so in
  its warnings rather than pretending otherwise. }
{$I mormot.defines.inc}
interface

uses
  SysUtils,
  Variants,
  mormot.core.base,
  mormot.core.text,
  mormot.core.unicode,
  mormot.core.variants;

/// build a record declaration and its RTTI registration from a result set
// - Json is the array of objects a select returned
// - TypeName is the record type name, e.g. TDtoCustomer
// - Source is ready to paste into a client unit; Warnings is empty when there
// is nothing to say, and is never a reason to withhold the source
// - returns false only when there is nothing to generate from
function GenerateDto(const TypeName, Json: RawUtf8;
  out Source, Warnings: RawUtf8): boolean;

/// a reasonable record name for an action key, e.g. GetAllCustomers -> TDtoAllCustomers
function SuggestTypeName(const ActionKey: RawUtf8): RawUtf8;

implementation

type
  { the lattice the inference walks up: a column takes the highest kind any
    of its values needed, and text absorbs everything }
  TColKind = (
    ckNone,
    ckBool,
    ckInt,
    ckInt64,
    ckDouble,
    ckText);

const
  PASCAL_TYPE: array[TColKind] of RawUtf8 = (
    'RawUtf8', 'boolean', 'integer', 'Int64', 'double', 'RawUtf8');

  { lower case, checked against a lower cased column name }
  RESERVED: array[0..40] of RawUtf8 = (
    'and', 'array', 'as', 'begin', 'case', 'class', 'const', 'div', 'do',
    'downto', 'else', 'end', 'file', 'for', 'function', 'goto', 'if',
    'implementation', 'in', 'inherited', 'interface', 'is', 'label', 'mod',
    'nil', 'not', 'object', 'of', 'or', 'packed', 'procedure', 'program',
    'record', 'repeat', 'set', 'shl', 'shr', 'string', 'then', 'to', 'type');

function IsReserved(const Name: RawUtf8): boolean;
var
  low: RawUtf8;
  i: PtrInt;
begin
  low := LowerCase(Name);
  for i := 0 to high(RESERVED) do
    if RESERVED[i] = low then
      exit(true);
  result := false;
end;

function IsPascalIdent(const Name: RawUtf8): boolean;
var
  i: PtrInt;
begin
  result := false;
  if Name = '' then
    exit;
  if not (Name[1] in ['A'..'Z', 'a'..'z', '_']) then
    exit;
  for i := 2 to length(Name) do
    if not (Name[i] in ['A'..'Z', 'a'..'z', '0'..'9', '_']) then
      exit;
  result := true;
end;

function KindOf(const Value: variant): TColKind;
var
  i64: Int64;
begin
  case TVarData(Value).VType of
    varEmpty, varNull:
      result := ckNone;
    varBoolean:
      result := ckBool;
    varShortInt, varSmallint, varInteger, varByte, varWord, varLongWord:
      result := ckInt;
    varInt64, varQWord:
      begin
        i64 := Value;
        if (i64 >= low(integer)) and (i64 <= high(integer)) then
          result := ckInt
        else
          result := ckInt64;
      end;
    varSingle, varDouble, varCurrency:
      result := ckDouble;
  else
    result := ckText;
  end;
end;

function SuggestTypeName(const ActionKey: RawUtf8): RawUtf8;
var
  s: RawUtf8;
begin
  s := ActionKey;
  if IdemPChar(pointer(s), 'GET') then
    delete(s, 1, 3);
  if s = '' then
    s := 'Row';
  result := 'TDto' + s;
end;

function GenerateDto(const TypeName, Json: RawUtf8;
  out Source, Warnings: RawUtf8): boolean;
var
  doc: variant;
  rows, row: PDocVariantData;
  names: TRawUtf8DynArray;
  kinds: array of TColKind;
  fields, decl, warn: RawUtf8;
  arrayName, safeName: RawUtf8;
  r, c, idx, nulls: PtrInt;
  k: TColKind;
begin
  result := false;
  Source := '';
  Warnings := '';
  if TypeName = '' then
  begin
    Warnings := 'No type name given.';
    exit;
  end;
  doc := _Json(Json, JSON_FAST_FLOAT); // doubles as doubles, not as currency
  rows := _Safe(doc);
  if not rows^.IsArray or
     (rows^.Count = 0) then
  begin
    Warnings := 'The result set is empty - there is nothing to infer a type from. ' +
      'Run the statement with parameters that return at least one row.';
    exit;
  end;
  { column order comes from the first row; a later row that carries a column
    the first one did not is appended rather than silently dropped }
  for r := 0 to rows^.Count - 1 do
  begin
    row := _Safe(rows^.Values[r]);
    if not row^.IsObject then
      continue;
    for c := 0 to row^.Count - 1 do
    begin
      idx := FindRawUtf8(names, row^.Names[c], {casesensitive=}true);
      if idx < 0 then
      begin
        idx := AddRawUtf8(names, row^.Names[c]);
        SetLength(kinds, length(names));
        kinds[idx] := ckNone;
      end;
      k := KindOf(row^.Values[c]);
      if k > kinds[idx] then
        kinds[idx] := k;
    end;
  end;
  if names = nil then
  begin
    Warnings := 'The result set holds no named columns.';
    exit;
  end;
  nulls := 0;
  decl := '';
  fields := '';
  for c := 0 to high(names) do
  begin
    safeName := names[c];
    if not IsPascalIdent(safeName) then
    begin
      warn := warn + FormatUtf8(
        '- column "%" is not a Pascal identifier. Give it an alias in the ' +
        'statement (select ... as %) - the field name has to match the ' +
        'column name exactly.'#13#10, [safeName, 'SomeName']);
      continue;
    end;
    if IsReserved(safeName) then
      warn := warn + FormatUtf8(
        '- column "%" is a reserved word. Give it an alias in the statement.'#13#10,
        [safeName]);
    if kinds[c] = ckNone then
    begin
      inc(nulls);
      warn := warn + FormatUtf8(
        '- column "%" was null in every returned row; typed as RawUtf8 as a ' +
        'guess. Check it.'#13#10, [safeName]);
    end;
    decl := decl + FormatUtf8('    %: %;'#13#10, [safeName, PASCAL_TYPE[kinds[c]]]);
    if fields <> '' then
      fields := fields + ';';
    fields := fields + safeName + ':' + PASCAL_TYPE[kinds[c]];
  end;
  if decl = '' then
  begin
    Warnings := warn + 'No usable column left - nothing generated.';
    exit;
  end;
  arrayName := TypeName + 'Array';
  Source := FormatUtf8(
    '  %'#13#10 +                          // the /// comment
    '  % = packed record'#13#10 +
    '%' +                                  // the fields
    '  end;'#13#10 +
    '  % = array of %;'#13#10,
    ['/// rows of this statement', TypeName, decl, arrayName, TypeName]);
  { Nothing else: on Delphi 2010+ and FPC 3.3/3.4 the record layout comes from
    extended record RTTI. Only FPC 3.2.x needs it spelled out, and then it is
    this line, with the fields in DECLARATION order because it describes the
    memory layout and not the JSON. }
  if fields <> '' then
    Source := Source + FormatUtf8(#13#10 +
      '  // Only needed when building with FPC 3.2.x, which carries no field'#13#10 +
      '  // names in record RTTI. Delphi 2010+ and FPC 3.3.1 do not need it.'#13#10 +
      '  // Rtti.RegisterFromText(TypeInfo(%),'#13#10 +
      '  //   ''%'');'#13#10, [TypeName, fields]);
  if warn <> '' then
    warn := 'Check before use:'#13#10 + warn;
  Warnings := warn + FormatUtf8(
    '% column(s) inferred from % returned row(s).'#13#10 +
    'Types come from the values that were returned, not from the database ' +
    'schema: a numeric column that held whole numbers only in this sample ' +
    'comes out as integer.'#13#10, [length(names) - nulls, rows^.Count]);
  result := true;
end;

end.
