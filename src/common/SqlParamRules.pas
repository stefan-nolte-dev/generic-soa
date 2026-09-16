unit SqlParamRules;

{$I mormot.defines.inc}

{ The named checks a template may put on its parameters, and the reading of
  the Rules column that names them.

  ParamTypes says what a value IS - int, date, text - and stops there: 'text'
  is happy with an empty string, and 'int' with a postcode of 4711. What a
  column of a real database also wants is a shape, and that is what this is:
  checks with names, registered in Pascal, named by a template as data.

    Rules = '2:plz;3:email'

  Read it as: parameter 2 has to be a postcode, parameter 3 an e-mail. One
  entry per rule and the position in front, so a template with twelve
  parameters and one rule names one position instead of counting commas.
  Several rules on one parameter are several entries.

  The checks are code and the naming of them is data, which is the whole
  arrangement: adding a rule to a query is a row, adding a KIND of rule is a
  unit like this one. Nothing a client sends is ever read as a rule.

  An empty declaration is valid and checks nothing - every template written
  before this column existed still runs. }

interface

uses
  SysUtils,
  Variants,
  mormot.core.base,
  mormot.core.text,
  mormot.core.unicode,
  mormot.core.variants;

type
  /// one check, as it stands in the column
  TSqlParamRule = record
    /// which parameter it is about, 1 for the first ?
    Position: integer;
    /// the registered name, lowercase, e.g. 'plz'
    Name: RawUtf8;
    /// what followed the name, e.g. '1,100' of 'range:1,100' - may be empty
    Args: RawUtf8;
  end;
  TSqlParamRules = array of TSqlParamRule;

  /// whose mistake a failed check is
  // - rfTemplate: the declaration itself is wrong - an unknown rule name, a
  // position no ? exists at. The caller could not have caused it and cannot
  // fix it, so it is logged and answered as a failure, not as bad parameters
  // - rfValue: the declaration is fine and a value does not pass, which is
  // exactly what the column is for
  TSqlRuleFault = (
    rfNone,
    rfTemplate,
    rfValue);

  /// what a registered check is
  // - Value is the parameter as it will be bound, after coercion; Args is
  // what the template wrote after the rule name
  // - ArgsOnly asks the check to look at its Args and at nothing else, and
  // to say true when they are usable. That is how a declaration can be found
  // wrong while it is written instead of when a value arrives - and it is
  // why a rule reads its Args first and the value afterwards
  // - Msg says what is wrong, without naming the position: the caller of the
  // check puts that in front, so every rule reads the same way
  TSqlRuleCheck = function(const Value: variant; const Args: RawUtf8;
    ArgsOnly: boolean; out Msg: RawUtf8): boolean;

/// make a check nameable from a template
// - false when that name is taken: a rule name means one thing everywhere,
// and silently replacing one would change what every existing row means
function SqlRuleRegister(const Name: RawUtf8; Check: TSqlRuleCheck): boolean;

/// every registered name, comma separated, for a message or a hint
function SqlRuleNames: RawUtf8;

/// read a declaration such as '2:plz;3:email'
// - syntax and names only: whether a position exists is a question about a
// statement, and this unit does not see one
function ParseParamRules(const Declaration: RawUtf8;
  out Rules: TSqlParamRules; out Msg: RawUtf8): boolean;

/// run every declared check against the values that would be bound
// - Bounds is the array as it goes to the statement, caller scope included:
// the positions here are the statement's ?, so a scoped template's last rule
// is about the value the server appended
// - true and Fault = rfNone when everything passed, or nothing was declared
function CheckParamRules(const Declaration: RawUtf8; const Bounds: variant;
  out Fault: TSqlRuleFault; out Msg: RawUtf8): boolean;

implementation

{ ---------- the registry ---------- }

var
  Names: TRawUtf8DynArray;
  Checks: array of TSqlRuleCheck;

function IndexOfRule(const Name: RawUtf8): PtrInt;
begin
  for result := 0 to high(Names) do
    if Names[result] = Name then
      exit;
  result := -1;
end;

function SqlRuleRegister(const Name: RawUtf8; Check: TSqlRuleCheck): boolean;
var
  want: RawUtf8;
  n: PtrInt;
begin
  want := LowerCase(Trim(Name));
  result := (want <> '') and
            (@Check <> nil) and
            (IndexOfRule(want) < 0);
  if not result then
    exit;
  n := length(Names);
  SetLength(Names, n + 1);
  SetLength(Checks, n + 1);
  Names[n] := want;
  Checks[n] := Check;
end;

function SqlRuleNames: RawUtf8;
var
  i: PtrInt;
begin
  result := '';
  for i := 0 to high(Names) do
  begin
    if result <> '' then
      result := result + ', ';
    result := result + Names[i];
  end;
end;

{ ---------- the checks that ship with the sample ---------- }

{ they are deliberately plain: a postcode is five digits here because that is
  what German ones are, and a template that means another country's needs
  another rule name rather than an option nobody can see in the column }

function IsBlank(const Value: variant): boolean;
begin
  result := VarIsNull(Value) or
            VarIsEmpty(Value) or
            (Trim(VariantToUtf8(Value)) = '');
end;

function RuleNotEmpty(const Value: variant; const Args: RawUtf8;
  ArgsOnly: boolean; out Msg: RawUtf8): boolean;
begin
  Msg := 'is empty';
  result := ArgsOnly or
            not IsBlank(Value);
end;

function RulePlz(const Value: variant; const Args: RawUtf8;
  ArgsOnly: boolean; out Msg: RawUtf8): boolean;
var
  txt: RawUtf8;
  i: PtrInt;
begin
  Msg := '';
  if ArgsOnly or
     IsBlank(Value) then
    exit(true); // a null is a value the column may hold; notempty says otherwise
  txt := Trim(VariantToUtf8(Value));
  result := length(txt) = 5;
  if result then
    for i := 1 to 5 do
      if not (txt[i] in ['0'..'9']) then
      begin
        result := false;
        break;
      end;
  if not result then
    Msg := 'is not a postcode: five digits expected';
end;

function RuleEmail(const Value: variant; const Args: RawUtf8;
  ArgsOnly: boolean; out Msg: RawUtf8): boolean;
var
  txt: RawUtf8;
  at, dot: PtrInt;
begin
  Msg := '';
  if ArgsOnly or
     IsBlank(Value) then
    exit(true);
  txt := Trim(VariantToUtf8(Value));
  { structural, and no more than that: an address is valid because a mail to
    it arrives, which no expression can tell. What this catches is the typo
    and the empty-ish string, and it lets nothing through that has no @ }
  at := PosExChar('@', txt);
  dot := 0;
  if at > 0 then
    dot := PosEx('.', txt, at + 2);
  result := (at > 1) and
            (dot > at + 1) and
            (dot < length(txt)) and
            (PosExChar('@', copy(txt, at + 1, maxInt)) = 0) and
            (PosExChar(' ', txt) = 0);
  if not result then
    Msg := 'is not an e-mail address';
end;

function RuleLen(const Value: variant; const Args: RawUtf8;
  ArgsOnly: boolean; out Msg: RawUtf8): boolean;
var
  txt: RawUtf8;
  parts: TRawUtf8DynArray;
  min, max, len: integer;
begin
  Msg := '';
  parts := nil;
  CsvToRawUtf8DynArray(pointer(Args), parts, ',', {trim=}true);
  if (length(parts) < 1) or
     (length(parts) > 2) then
  begin
    Msg := 'len wants a length or two, e.g. len:1,60';
    exit(false);
  end;
  min := GetInteger(pointer(parts[0]));
  if length(parts) = 2 then
    max := GetInteger(pointer(parts[1]))
  else
    max := min;
  if ArgsOnly or
     IsBlank(Value) then
    exit(true);
  txt := VariantToUtf8(Value);
  len := Utf8ToUnicodeLength(pointer(txt));
  result := (len >= min) and
            (len <= max);
  if not result then
    if min = max then
      Msg := FormatUtf8('is % character(s) long, % expected', [len, min])
    else
      Msg := FormatUtf8('is % character(s) long, between % and % expected',
        [len, min, max]);
end;

function RuleRange(const Value: variant; const Args: RawUtf8;
  ArgsOnly: boolean; out Msg: RawUtf8): boolean;
var
  parts: TRawUtf8DynArray;
  min, max: double;
  d: double;
begin
  Msg := '';
  d := 0;
  parts := nil;
  CsvToRawUtf8DynArray(pointer(Args), parts, ',', {trim=}true);
  if length(parts) <> 2 then
  begin
    Msg := 'range wants two numbers, e.g. range:1,100';
    exit(false);
  end;
  min := GetExtended(pointer(parts[0]));
  max := GetExtended(pointer(parts[1]));
  if ArgsOnly or
     IsBlank(Value) then
    exit(true);
  if not VariantToDouble(Value, d) then
  begin
    Msg := 'is not a number';
    exit(false);
  end;
  result := (d >= min) and
            (d <= max);
  if not result then
    Msg := FormatUtf8('is outside % .. %', [parts[0], parts[1]]);
end;

function RuleOneOf(const Value: variant; const Args: RawUtf8;
  ArgsOnly: boolean; out Msg: RawUtf8): boolean;
var
  parts: TRawUtf8DynArray;
  txt: RawUtf8;
  i: PtrInt;
begin
  Msg := '';
  parts := nil;
  CsvToRawUtf8DynArray(pointer(Args), parts, ',', {trim=}true);
  if parts = nil then
  begin
    Msg := 'oneof wants the allowed values, e.g. oneof:open,done';
    exit(false);
  end;
  if ArgsOnly or
     IsBlank(Value) then
    exit(true);
  txt := Trim(VariantToUtf8(Value));
  for i := 0 to high(parts) do
    if IdemPropNameU(parts[i], txt) then
      exit(true);
  result := false;
  Msg := FormatUtf8('is none of %', [Args]);
end;

{ ---------- reading the column ---------- }

function ParseParamRules(const Declaration: RawUtf8;
  out Rules: TSqlParamRules; out Msg: RawUtf8): boolean;
var
  entries: TRawUtf8DynArray;
  one, pos, name, why: RawUtf8;
  i, n, colon: PtrInt;
begin
  Rules := nil;
  Msg := '';
  result := true;
  if Trim(Declaration) = '' then
    exit; // declares nothing, checks nothing
  entries := nil;
  CsvToRawUtf8DynArray(pointer(Declaration), entries, ';', {trim=}true);
  n := 0;
  SetLength(Rules, length(entries));
  for i := 0 to high(entries) do
  begin
    one := Trim(entries[i]);
    if one = '' then
      continue;
    colon := PosExChar(':', one);
    if colon < 2 then
    begin
      Msg := FormatUtf8('Rule "%": the position and a colon come first, ' +
        'e.g. 2:plz.', [one]);
      Rules := nil;
      exit(false);
    end;
    pos := copy(one, 1, colon - 1);
    Rules[n].Position := GetInteger(pointer(pos));
    if Rules[n].Position < 1 then
    begin
      Msg := FormatUtf8('Rule "%": "%" is not a parameter position; ' +
        'the first ? is 1.', [one, pos]);
      Rules := nil;
      exit(false);
    end;
    one := Trim(copy(one, colon + 1, maxInt));
    { what follows the name, if anything, is the rule's own business: split
      once more and hand the rest over untouched }
    colon := PosExChar(':', one);
    if colon = 0 then
    begin
      name := one;
      Rules[n].Args := '';
    end
    else
    begin
      name := Trim(copy(one, 1, colon - 1));
      Rules[n].Args := Trim(copy(one, colon + 1, maxInt));
    end;
    name := LowerCase(name);
    if IndexOfRule(name) < 0 then
    begin
      Msg := FormatUtf8('Rule "%" is not registered. Known: %.',
        [name, SqlRuleNames]);
      Rules := nil;
      exit(false);
    end;
    { the rule reads its own arguments, so a "range:1" is caught here and
      not when a value arrives - the declaration is what is wrong }
    if not Checks[IndexOfRule(name)](Null, Rules[n].Args, {argsonly=}true, why) then
    begin
      Msg := FormatUtf8('Rule "%": %.', [name, why]);
      Rules := nil;
      exit(false);
    end;
    Rules[n].Name := name;
    inc(n);
  end;
  SetLength(Rules, n);
end;

function CheckParamRules(const Declaration: RawUtf8; const Bounds: variant;
  out Fault: TSqlRuleFault; out Msg: RawUtf8): boolean;
var
  rules: TSqlParamRules;
  src: PDocVariantData;
  i, r: PtrInt;
  why: RawUtf8;
begin
  Fault := rfNone;
  result := ParseParamRules(Declaration, rules, Msg);
  if not result then
  begin
    Fault := rfTemplate;
    exit;
  end;
  if rules = nil then
    exit; // nothing declared
  src := _Safe(Bounds);
  for i := 0 to high(rules) do
  begin
    if rules[i].Position > src^.Count then
    begin
      Fault := rfTemplate;
      Msg := FormatUtf8('Rule "%:%" names parameter %, but % value(s) ' +
        'are bound.', [rules[i].Position, rules[i].Name, rules[i].Position,
        src^.Count]);
      exit(false);
    end;
    r := IndexOfRule(rules[i].Name);
    if r < 0 then
    begin
      Fault := rfTemplate;
      Msg := FormatUtf8('Rule "%" is not registered.', [rules[i].Name]);
      exit(false);
    end;
    if not Checks[r](src^.Values[rules[i].Position - 1], rules[i].Args,
         {argsonly=}false, why) then
    begin
      { the position is put in front here and not in the check, so every rule
        reads the same way whoever wrote it }
      Fault := rfValue;
      Msg := FormatUtf8('Parameter % %.', [rules[i].Position, why]);
      exit(false);
    end;
  end;
end;

initialization
  SqlRuleRegister('notempty', @RuleNotEmpty);
  SqlRuleRegister('plz', @RulePlz);
  SqlRuleRegister('email', @RuleEmail);
  SqlRuleRegister('len', @RuleLen);
  SqlRuleRegister('range', @RuleRange);
  SqlRuleRegister('oneof', @RuleOneOf);

end.
