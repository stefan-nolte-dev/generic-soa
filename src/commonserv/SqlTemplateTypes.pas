unit SqlTemplateTypes;

{$I mormot.defines.inc}

{ What one action key is - the type, and nothing that acts on it.

  A unit of its own so that a layer which only has to carry a template does
  not also see the registry that issues them. The infrastructure layer needs
  TSqlRec to bind and execute; only the domain layer looks templates up. That
  boundary is in the uses clause of each unit, where it can be read, instead
  of in a search path where it cannot.

  Server side only: a client names an action key and never sees this. }

interface

uses
  SysUtils,
  mormot.core.base,
  mormot.core.text, // for ESynException
  mormot.core.unicode; // for IdemPChar, reading the mark off an action key

type
  /// what a generated record statement does
  // - raNone for an action key that names none of them, and for one that is
  // not marked as an ORM action at all
  TRecordActionKind = (
    raNone,
    raInsert,
    raUpdate,
    raRetrieve,
    raList,
    raDelete);
  /// several of them at once, for a caller that accepts more than one
  TRecordActionKinds = set of TRecordActionKind;

  /// raised for wiring mistakes only
  // - anything a caller could have caused is a TSqlStatus, not an exception
  ESqlTemplate = class(ESynException);

  /// everything the server knows about one action key
  // - one field per column of templates.sqlite, and this is the record that
  // grows: the recorded shape of a result would be a field here and nothing
  // else would move
  // - it carries the key as well, so a record travelling on its own - to a
  // rule check, to a log line - needs nothing passed alongside
  TSqlRec = packed record
    /// the action key a client names to run this statement
    ActionKey: RawUtf8;
    /// the statement itself, with ? for every parameter
    // - or with :Name placeholders when RecordType is set
    // - or empty, when RecordType is set and the statement is to be generated
    // from it and from the action key - see SqlRecordBind
    Sql: RawUtf8;
    /// what each ? is, e.g. 'text,int,date' - empty means no coercion
    // - how a date survives the trip as JSON; see SqlParamTypes
    ParamTypes: RawUtf8;
    /// the named checks on the parameters, e.g. '2:plz;3:email'
    // - ParamTypes says what a value is, this says what shape it has to have
    // - the position comes first, so a template with twelve parameters and
    // one rule names one position instead of counting commas
    // - read by SqlParamRules, run by the domain layer's CheckRules, and
    // empty on every template that was written before the column existed
    Rules: RawUtf8;
    /// sample values for a test run, as the JSON a client would send
    // - an array for a template with parameters, '["Wegberg"]', or the
    // record's own JSON object for a generated insert or update
    // - empty means: this template is checked but not run. Nothing on the
    // server reads it - it is what lets a tool run the whole set without a
    // line of test code per key
    TestBounds: RawUtf8;
    /// the record type a record write expects, by name, e.g. 'TDtoCustomer'
    // - empty for the ordinary, variant based calls
    // - resolved through Rtti.FindName at run time, so the name is all that
    // travels: no layer below the application has to see WriteDtos
    RecordType: RawUtf8;
    /// the declaration of RecordType, in mORMot's textual RTTI
    // - e.g. 'ID: integer; Name: RawUtf8; City: RawUtf8'
    // - empty means the type has to be compiled into the server and
    // registered there, which is what WriteDtos is for
    // - set, and the type is registered from this text the first time it is
    // needed: then a new record is a row, like everything else about a query
    // - a name that already resolves to a compiled type is never overwritten
    // from here; see ResolveRecordType
    RecordDecl: RawUtf8;
    /// the where clause of a generated list, without the word "where"
    // - e.g. 'City = ? and Name like ?' - the shape of the filter is the
    // template's, the values are the caller's, which is the whole difference
    // to an ORM that takes a where clause from its caller: nothing a client
    // sends is ever read as SQL here
    // - empty on a list means every row
    // - meaningless for the other kinds: their where clause is the key
    Filter: RawUtf8;
    /// the order of a generated list, without the words "order by"
    // - e.g. 'Name, City' - empty means the database's own order
    OrderBy: RawUtf8;
    /// the key column of a generated statement - empty means ID
    // - an update matches on it, an insert leaves it to the database
    // - the convention held in the demo and holds nowhere else: in a grown
    // database the key is Artikel_ID, Adressen_ID, never ID
    KeyField: RawUtf8;
    /// scope this query to the caller: the named value is bound to the LAST
    /// parameter by the server, so the client cannot set it
    // - empty: no scoping, every bound value comes from the client as before
    // - 'userid': the server binds Caller.UserID to the last ?; the client
    //   sends one value fewer and never sends that parameter at all, so a row
    //   it must not reach is structurally out of its hands
    // - a client that sends the full count is refused: the value would land at
    //   the wrong ? and the scope would be lost. The filling is in TDomSqlTool
    CallerScope: RawUtf8;
    /// bitmask of the session groups that may read through this key
    // - 0 means unset. Whether unset is "everyone" or "nobody" is one flag in
    // the domain layer, not a decision scattered per key
    ReadGroups: Int64;
    /// bitmask of the session groups that may write through this key
    WriteGroups: Int64;
  end;
  TSqlRecArray = array of TSqlRec;

const
  /// what every ORM action key starts with, and no other key does
  // - the mark is in the name because the name is what a reader sees: a list
  // of keys says which of them make a record travel, without opening the
  // RecordType column of each. In front rather than behind, so they sort
  // together in the editor's list
  // - UPPERCASE because IdemPChar wants an uppercase pattern; the key itself
  // is matched case insensitively, as everywhere else here
  RECORDACTION_PREFIX = 'ORM';
  /// what follows the prefix for a generated insert
  // - the rest of the key is free: the RecordType column names the type, not
  // the key, so OrmUpdateTDtoCustomer and OrmUpdateKunde both work
  RECORDACTION_INSERT: array[0..1] of RawUtf8 = (
    'ADD', 'INSERT');
  /// and for a generated update
  RECORDACTION_UPDATE: array[0..0] of RawUtf8 = (
    'UPDATE');
  /// and for a generated select on the key
  // - two spellings for the same reason Add and Insert are both taken
  RECORDACTION_RETRIEVE: array[0..1] of RawUtf8 = (
    'RETRIEVE', 'GET');
  /// and for a generated select of many rows, filtered by the template
  // - the one kind whose statement is not decided by the key alone: the
  // Filter and OrderBy columns shape it, and the caller fills its ?
  RECORDACTION_LIST: array[0..1] of RawUtf8 = (
    'LIST', 'SELECT');
  /// and for a generated delete on the key
  RECORDACTION_DELETE: array[0..0] of RawUtf8 = (
    'DELETE');

/// does this action key claim to be an ORM action at all
// - the RECORDACTION_PREFIX and nothing else decides it. A template that
// names a RecordType without it is refused rather than treated as one: the
// mark is what tells a reader of the key list, and a mark that is sometimes
// missing would tell them nothing
function IsOrmActionKey(const Action: RawUtf8): boolean;

/// raInsert for OrmAddSomething, raUpdate for OrmUpdateSomething,
// raRetrieve for OrmRetrieve/OrmGetSomething, raDelete for OrmDeleteSomething
// - raNone when the prefix is missing, so the verb alone never triggers this
function RecordKindFromActionKey(const Action: RawUtf8): TRecordActionKind;

/// how many bind parameters a statement has: the ? outside string literals
// - schicht-neutral, a plain text property of a statement, so it lives here
// where every layer may ask - the domain layer needs it to know how many
// values a caller-scoped query expects from the client (one fewer than this)
function CountSqlParams(const Sql: RawUtf8): integer;

/// how many values a caller has to send for this template
// - the ? of the statement, and for one that has none yet the ? the
// generated statement will have: a layer that has to count them before
// anything is composed cannot ask the text, because there is no text
function ExpectedParamCount(const Rec: TSqlRec): integer;

implementation

function IsOrmActionKey(const Action: RawUtf8): boolean;
begin
  result := IdemPChar(pointer(Action), RECORDACTION_PREFIX);
end;

{ the verb is read AFTER the mark, never instead of it: DeleteCustomer is an
  ordinary statement with a bound parameter and has to stay one, and
  OrmDeleteCustomer is the generated delete. That is the whole point of the
  prefix - the two can sit next to each other and be told apart by name }
function RecordKindFromActionKey(const Action: RawUtf8): TRecordActionKind;
var
  verb: RawUtf8;
  i: PtrInt;
begin
  result := raNone;
  if not IsOrmActionKey(Action) then
    exit;
  verb := copy(Action, length(RECORDACTION_PREFIX) + 1, MaxInt);
  for i := 0 to high(RECORDACTION_INSERT) do
    if IdemPChar(pointer(verb), pointer(RECORDACTION_INSERT[i])) then
      exit(raInsert);
  for i := 0 to high(RECORDACTION_UPDATE) do
    if IdemPChar(pointer(verb), pointer(RECORDACTION_UPDATE[i])) then
      exit(raUpdate);
  for i := 0 to high(RECORDACTION_RETRIEVE) do
    if IdemPChar(pointer(verb), pointer(RECORDACTION_RETRIEVE[i])) then
      exit(raRetrieve);
  for i := 0 to high(RECORDACTION_LIST) do
    if IdemPChar(pointer(verb), pointer(RECORDACTION_LIST[i])) then
      exit(raList);
  for i := 0 to high(RECORDACTION_DELETE) do
    if IdemPChar(pointer(verb), pointer(RECORDACTION_DELETE[i])) then
      exit(raDelete);
end;

function ExpectedParamCount(const Rec: TSqlRec): integer;
begin
  if Rec.Sql <> '' then
    result := CountSqlParams(Rec.Sql)
  else
    { no statement yet, so the same three things that will make it say how
      many ? it will have: a list gets one per ? of its filter, a retrieve
      and a delete get the one that is the key, and nothing else generates }
    case RecordKindFromActionKey(Rec.ActionKey) of
      raList:
        result := CountSqlParams(Rec.Filter);
      raRetrieve,
      raDelete:
        result := 1;
    else
      result := 0;
    end;
end;

function CountSqlParams(const Sql: RawUtf8): integer;
var
  i: PtrInt;
  inString: boolean;
begin
  result := 0;
  inString := false;
  for i := 1 to length(Sql) do
    case Sql[i] of
      '''':
        inString := not inString; // a doubled '' flips twice: still correct
      '?':
        if not inString then
          inc(result);
    end;
end;


end.
