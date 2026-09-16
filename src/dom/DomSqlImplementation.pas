unit DomSqlImplementation;

{$I mormot.defines.inc}

{ The domain layer - and the single choke point.

  Every request passes through here, and in this order:

    1. is the caller authenticated at all
    2. does the action key exist - and if not, has the source changed
    3. is this caller in the template's group mask
    4. do the sanity rules of this template hold

  Only then is the resolved TSqlRec handed down. Refusing is this layer's
  job; composing and running SQL is the layer below's, and it is handed a
  template rather than a key so that it cannot look one up itself.

  Resolving once and passing the record down also closes a window: looking
  the key up again further down would let a reload between check and
  execution swap the record.

  Because everything comes through one place, a default cannot be forgotten -
  unlike a check repeated in fifty method bodies. }

interface

uses
  SysUtils,
  mormot.core.base,
  mormot.core.os,
  mormot.core.log,
  mormot.core.unicode,  // for IdemPropNameU
  mormot.core.variants, // for the caller value appended to the bounds
  SqlStatus,
  SqlParamRules,
  SqlTemplateTypes,
  SqlTemplateRegistry,
  DomSqlServices,
  InfraSqlServices; // the two interfaces only - no connection, no statement

type

  { TDomSqlTool }

  TDomSqlTool = class(TInterfacedObject, IDomSqlTool)
  private
    fExec: ISqlTemplateExec;
    fSource: ISqlTemplateSource;
    fTemplates: TSqlTemplateRegistry;
    { one reload at a time: two threads missing the same key would otherwise
      both read the source and both replace the registry }
    fReloading: TLightLock;
  protected
    /// resolve an action key and clear it for execution
    // - the one place a key becomes a template: unauthenticated, empty,
    // unknown and refused are all answered here, before anything runs
    function Resolve(const Caller: TSqlCaller; const Action: RawUtf8;
      Write: boolean; out Rec: TSqlRec): TSqlStatus;
    /// may this caller use this key, for reading or for writing
    // - the caller's groups against the template's mask; an unset mask is
    // decided by StrictRights and by nothing else
    function CanExecute(const Caller: TSqlCaller; const Rec: TSqlRec;
      Write: boolean): TSqlStatus; virtual;
    /// the template's own sanity rules
    // - the Rules column, read by SqlParamRules: named checks registered in
    // Pascal, bound to parameter positions as data ('2:plz;3:email')
    // - runs on the values as they will be bound, caller scope included, so
    // a rule can be about the value the client never sent
    // - a declaration that is itself wrong is the template's mistake and not
    // the caller's: it is logged and answered sqlFailed, while a value that
    // does not pass is sqlBadParams like any other bad parameter
    function CheckRules(const Caller: TSqlCaller; const Rec: TSqlRec;
      const Bounds: variant): TSqlStatus; virtual;
    /// bind the caller's identity to the last parameter, when the template
    /// asks for it (CallerScope)
    // - the whole point of A1: a value the client never sent and cannot set.
    // The named value (Caller.UserID) is appended as the last bound value, so
    // the query's last ? is the caller and not the request
    // - Scoped is the bounds to run with: unchanged when CallerScope is empty,
    // one value longer otherwise
    // - refuses a client that did not leave the last ? open (sent the full
    // count): appending would then push the identity past the last ? and the
    // scope would be lost - so this is a hard sqlBadParams, not a silent fix
    function ApplyCallerScope(const Caller: TSqlCaller; const Rec: TSqlRec;
      const Bounds: variant; out Scoped: variant): TSqlStatus; virtual;
    /// may this caller ask for an unconditional reload
    // - administrative, and stricter than any query deserves to be: being
    // logged in is not enough, the caller has to be in some write group.
    // Rereading the set is how a new template takes effect, so it is closer
    // to writing than to reading whatever it says in the URI
    function CanReload(const Caller: TSqlCaller): TSqlStatus; virtual;
    /// re-read the source into the registry
    // - Force skips the Changed() question; returns the new count or -1
    function ReloadFromSource(Force: boolean): integer;
  public
    constructor Create(const aExec: ISqlTemplateExec;
      const aSource: ISqlTemplateSource); reintroduce;
    destructor Destroy; override;
    /// fill the registry for the first time
    // - separate from Create so the startup code can refuse to start on an
    // empty or broken set, which is the one moment where that is still cheap
    function LoadTemplates: integer;
    function SelectJson(const Caller: TSqlCaller; const Action: RawUtf8;
      const Bounds: variant; var Json: RawUtf8): TSqlStatus;
    function WriteData(const Caller: TSqlCaller; const Action: RawUtf8;
      const Bounds: variant): TSqlStatus;
    function WriteRecord(const Caller: TSqlCaller; const Action: RawUtf8;
      const Json: RawUtf8): TSqlStatus;
    function AvailableActions(const Caller: TSqlCaller): TRawUtf8DynArray;
    function ReloadTemplates(const Caller: TSqlCaller): TSqlStatus;
    function TemplateCount: integer;
  end;

var
  /// what an unset ReadGroups / WriteGroups mask means
  // - false, the default here: no rule stated yet, let it through
  // - true: no rule stated, so nobody - for a deployment that has finished
  // stating its rules
  // - deliberately one flag rather than a default per key, so a permissive
  // gap cannot hide in one forgotten row and switching it is one line
  StrictRights: boolean = false;

  /// whether an unknown action key may cost a look at the source
  // - the reload is what shows that a new template needs no rebuild and no
  // restart. It is guarded twice: only on a miss, and only when the source
  // says it changed - so a mistyped key in a loop costs a stat call
  // - set to false to pin a running server to the set it started with
  ReloadOnUnknownKey: boolean = true;

implementation

{ TDomSqlTool }

constructor TDomSqlTool.Create(const aExec: ISqlTemplateExec;
  const aSource: ISqlTemplateSource);
begin
  inherited Create;
  if (aExec = nil) or
     (aSource = nil) then
    raise ESqlTemplate.Create('TDomSqlTool.Create(nil)');
  fExec := aExec;
  fSource := aSource;
  fTemplates := TSqlTemplateRegistry.Create;
end;

destructor TDomSqlTool.Destroy;
begin
  fTemplates.Free;
  inherited Destroy;
end;

function TDomSqlTool.ReloadFromSource(Force: boolean): integer;
var
  recs: TSqlRecArray;
begin
  result := -1;
  fReloading.Lock;
  try
    { asked again inside the lock: whoever held it may have just done it }
    if not (Force or fSource.Changed) then
      exit(0);
    if not fSource.Load(recs) then
      exit;
    result := fTemplates.Reload(recs);
    if result < 0 then
      TSynLog.Add.Log(sllError,
        '% refused - registry unchanged', [fSource.SourceName])
    else
      TSynLog.Add.Log(sllInfo,
        '% reloaded: % templates', [fSource.SourceName, result]);
  finally
    fReloading.UnLock;
  end;
end;

function TDomSqlTool.LoadTemplates: integer;
begin
  result := ReloadFromSource({force=}true);
end;

function TDomSqlTool.CanExecute(const Caller: TSqlCaller; const Rec: TSqlRec;
  Write: boolean): TSqlStatus;
var
  mask, has: Int64;
begin
  if Write then
  begin
    mask := Rec.WriteGroups;
    has := Caller.Writes;
  end
  else
  begin
    mask := Rec.ReadGroups;
    has := Caller.Reads;
  end;
  if mask = 0 then
  begin
    { the whole question lives here and nowhere else - the property worth
      having, and also the risk: one line wrong and every key is wrong }
    if StrictRights then
      exit(sqlNotAllowed)
    else
      exit(sqlOk);
  end;
  { a mask names groups, so a caller in none of them is refused - and the
    direction decides which of the caller's two masks is asked }
  if (has and mask) = 0 then
    exit(sqlNotAllowed);
  result := sqlOk;
end;

function TDomSqlTool.CheckRules(const Caller: TSqlCaller; const Rec: TSqlRec;
  const Bounds: variant): TSqlStatus;
var
  fault: TSqlRuleFault;
  msg: RawUtf8;
begin
  result := sqlOk;
  if Rec.Rules = '' then
    exit; // declares nothing, checks nothing
  if CheckParamRules(Rec.Rules, Bounds, fault, msg) then
    exit;
  if fault = rfTemplate then
  begin
    { nobody outside can fix this and nobody outside should be told what the
      declaration says, so it goes to the log and the caller gets a failure }
    TSynLog.Add.Log(sllError, 'Rules(%): %', [Rec.ActionKey, msg]);
    exit(sqlFailed);
  end;
  TSynLog.Add.Log(sllWarning, 'Rules(%): %', [Rec.ActionKey, msg]);
  result := sqlBadParams;
end;

function TDomSqlTool.CanReload(const Caller: TSqlCaller): TSqlStatus;
begin
  if not Caller.Authenticated then
    result := sqlNeedsLogin
  else if Caller.Writes = 0 then
    { a reader may read what is registered; changing what IS registered is
      not reading. Without a token this is nobody's obstacle - an anonymous
      caller has AnonymousWrites - and with one it is exactly the difference
      between the two demo accounts }
    result := sqlNotAllowed
  else
    result := sqlOk;
end;

function TDomSqlTool.Resolve(const Caller: TSqlCaller; const Action: RawUtf8;
  Write: boolean; out Rec: TSqlRec): TSqlStatus;
begin
  Rec := default(TSqlRec);
  { first, and cheapest: without this an unknown key from anyone at all could
    reach the reload below. Its own status: a caller who is nobody is told to
    log in, which is something they can act on - "not allowed" is not }
  if not Caller.Authenticated then
    exit(sqlNeedsLogin);
  if Action = '' then
    exit(sqlEmptyKey);
  if not fTemplates.Find(Action, Rec) then
  begin
    { the key is not registered - which is either a mistyped key, or a
      template someone added while this server was running. The source is
      asked which of the two it is }
    if not ReloadOnUnknownKey then
      exit(sqlUnknownKey);
    if ReloadFromSource({force=}false) <= 0 then
      exit(sqlUnknownKey);
    if not fTemplates.Find(Action, Rec) then
      exit(sqlUnknownKey);
  end;
  result := CanExecute(Caller, Rec, Write);
end;

function TDomSqlTool.ApplyCallerScope(const Caller: TSqlCaller;
  const Rec: TSqlRec; const Bounds: variant; out Scoped: variant): TSqlStatus;
var
  src: PDocVariantData;
  arr: TDocVariantData;
  want, have, i: integer;
  value: variant;
begin
  Scoped := Bounds;
  result := sqlOk;
  if Rec.CallerScope = '' then
    exit; // not scoped: the client's bounds run as they are
  { which caller value goes in. One name for now; groups or a tenant id would
    be another case of exactly this shape }
  if IdemPropNameU(Rec.CallerScope, 'userid') then
    value := Caller.UserID
  else
  begin
    TSynLog.Add.Log(sllError, 'CallerScope(%): unknown value "%"',
      [Rec.ActionKey, Rec.CallerScope]);
    exit(sqlFailed);
  end;
  { the last ? belongs to the caller, so the client owes one value fewer.
    Exactly one fewer - not "at most": a client that fills the last ? itself
    would have its value bound there and the appended identity ignored }
  { ExpectedParamCount and not CountSqlParams: a template whose statement is
    generated has no text to count, and its ? are known all the same - the
    filter of a list carries them, the key of a retrieve or a delete is one }
  want := ExpectedParamCount(Rec) - 1;
  src := _Safe(Bounds);
  have := src^.Count;
  if have <> want then
  begin
    TSynLog.Add.Log(sllWarning, 'CallerScope(%): % value(s) sent, % expected',
      [Rec.ActionKey, have, want]);
    exit(sqlBadParams);
  end;
  { rebuild rather than mutate: Bounds is const, and the value is appended
    last so it lands on the last ? }
  arr.InitArray([], JSON_FAST_FLOAT);
  for i := 0 to have - 1 do
    arr.AddItem(src^.Values[i]);
  arr.AddItem(value);
  Scoped := variant(arr);
end;

function TDomSqlTool.SelectJson(const Caller: TSqlCaller;
  const Action: RawUtf8; const Bounds: variant; var Json: RawUtf8): TSqlStatus;
var
  rec: TSqlRec;
  scoped: variant;
begin
  Json := '[]';
  result := Resolve(Caller, Action, {write=}false, rec);
  if result <> sqlOk then
    exit;
  { the identity goes in before the rules see the values and before the
    statement runs - so a rule, once there is one, checks the final bounds }
  result := ApplyCallerScope(Caller, rec, Bounds, scoped);
  if result <> sqlOk then
    exit;
  result := CheckRules(Caller, rec, scoped);
  if result <> sqlOk then
    exit;
  result := fExec.SelectJson(rec, scoped, Json);
end;

function TDomSqlTool.WriteData(const Caller: TSqlCaller;
  const Action: RawUtf8; const Bounds: variant): TSqlStatus;
var
  rec: TSqlRec;
begin
  result := Resolve(Caller, Action, {write=}true, rec);
  if result <> sqlOk then
    exit;
  if (rec.RecordType <> '') and
     (RecordKindFromActionKey(rec.ActionKey) <> raDelete) then
  begin
    { this key expects a record, not a value list. It would not prepare
      anyway; saying so beats letting the driver say it.
      A generated DELETE is the exception and the reason this is not a plain
      "names a record type" test: it names one, and takes no record at all -
      its one value is the key, and it arrives here like any other. That the
      key says so is exactly what the Orm prefix is for; the convention lives
      in SqlTemplateTypes, so reading it costs this layer no sight of how a
      statement is composed }
    TSynLog.Add.Log(sllWarning,
      'WriteData(%): expects a % record', [Action, rec.RecordType]);
    exit(sqlBadParams);
  end;
  result := CheckRules(Caller, rec, Bounds);
  if result <> sqlOk then
    exit;
  result := fExec.Execute(rec, Bounds);
end;

{ The record direction: no branch per type here, and nothing to add when the
  next record arrives. The JSON is passed down untouched - what the fields
  are, and what statement they make, is decided one layer below. }
function TDomSqlTool.WriteRecord(const Caller: TSqlCaller;
  const Action: RawUtf8; const Json: RawUtf8): TSqlStatus;
var
  rec: TSqlRec;
begin
  result := Resolve(Caller, Action, {write=}true, rec);
  if result <> sqlOk then
    exit;
  if rec.RecordType = '' then
  begin
    TSynLog.Add.Log(sllWarning,
      'WriteRecord(%): this key names no record type', [Action]);
    exit(sqlBadParams);
  end;
  if rec.Rules <> '' then
  begin
    { the rules name parameter positions, and a record write has none: its
      values are fields with names. Rather than let a declared rule quietly
      check nothing on this one path, the template is refused - the editor
      says the same thing before it can be saved. Rules by field name are
      the obvious next step and are deliberately not smuggled in here }
    TSynLog.Add.Log(sllError, 'WriteRecord(%): Rules "%" name parameter ' +
      'positions, which a record write has none of', [Action, rec.Rules]);
    exit(sqlFailed);
  end;
  result := fExec.ExecuteRecord(rec, Json);
end;

function TDomSqlTool.AvailableActions(const Caller: TSqlCaller): TRawUtf8DynArray;
begin
  result := nil;
  if Caller.Authenticated then
    result := fTemplates.AllKeys;
end;

function TDomSqlTool.ReloadTemplates(const Caller: TSqlCaller): TSqlStatus;
begin
  result := CanReload(Caller);
  if result <> sqlOk then
    exit;
  if ReloadFromSource({force=}true) < 0 then
    // refused: the registry still holds the previous, working set
    result := sqlFailed;
end;

function TDomSqlTool.TemplateCount: integer;
begin
  result := fTemplates.Count;
end;

end.
