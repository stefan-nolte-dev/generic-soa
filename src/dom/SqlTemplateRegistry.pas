unit SqlTemplateRegistry;

{$I mormot.defines.inc}

{ The template registry: action key -> TSqlRec.

  A store and nothing else - it opens no file and no connection, and does not
  know where its entries come from. A loader in the infrastructure layer hands
  it a set; swapping one loader for another changes nothing here.

  It lives in dom because looking a key up is the domain layer's job. The
  layer below is handed the TSqlRec it needs and never sees this class - see
  SqlTemplateTypes for why that split is worth a unit.

  Reload() replaces the whole content in one step, after checking it: a broken
  or empty set leaves the running server on the templates it already had. }

interface

uses
  SysUtils,
  mormot.core.base,
  mormot.core.data,
  mormot.core.os,
  mormot.core.text,
  mormot.core.unicode, // for QuickSortRawUtf8
  mormot.core.json,
  SqlParamTypes,
  SqlTemplateTypes;

type

  { TSqlTemplateRegistry }

  TSqlTemplateRegistry = class
  private
    fSafe: TRWLock;
    fMap: TSynDictionary;
    function NewMap: TSynDictionary;
  public
    constructor Create;
    destructor Destroy; override;
    /// register one template, while loading
    // - raises on a duplicate or empty key: a silent overwrite would make two
    // templates of the same name differ by load order
    procedure Add(const Rec: TSqlRec);
    /// look up everything known about an action key
    // - false for an unknown key; the caller must never fall through to
    // executing an empty statement
    function Find(const Action: RawUtf8; var Rec: TSqlRec): boolean;
    /// replace every template in one step, after checking the new set
    // - returns the number now registered, or -1 on refusal, in which case
    // the server goes on serving what it served before
    function Reload(const Recs: TSqlRecArray): integer;
    /// all registered action keys, for introspection
    // - the client can ask what this server can answer, which the
    // one-method-per-query style cannot offer without extra code
    // - sorted, so the answer does not depend on the loader or the load order
    function AllKeys: TRawUtf8DynArray;
    function Count: integer;
  end;

implementation

{ TSqlTemplateRegistry }

function TSqlTemplateRegistry.NewMap: TSynDictionary;
begin
  result := TSynDictionary.Create(
    TypeInfo(TRawUtf8DynArray), TypeInfo(TSqlRecArray), {caseinsens=}true);
end;

constructor TSqlTemplateRegistry.Create;
begin
  inherited Create;
  fSafe.Init;
  fMap := NewMap;
end;

destructor TSqlTemplateRegistry.Destroy;
begin
  fMap.Free;
  inherited Destroy;
end;

procedure TSqlTemplateRegistry.Add(const Rec: TSqlRec);
begin
  if Rec.ActionKey = '' then
    raise ESqlTemplate.Create('SqlTemplates.Add: empty action key');
  if (Rec.Sql = '') and
     (Rec.RecordType = '') then
    { an empty statement is allowed for exactly one reason: a record write
      whose statement is generated from the record type and the action key.
      Without a record type there is nothing to generate it from }
    raise ESqlTemplate.CreateUtf8(
      'SqlTemplates.Add: no SQL for [%]', [Rec.ActionKey]);
  if (Rec.RecordDecl <> '') and
     (Rec.RecordType = '') then
    { a declaration is registered under the name in RecordType. Without one
      there is no name to register it as, and it would sit there doing
      nothing - which reads like a working row and is not }
    raise ESqlTemplate.CreateUtf8(
      'SqlTemplates.Add: RecordDecl without RecordType in [%]',
      [Rec.ActionKey]);
  fSafe.WriteLock;
  try
    if fMap.Exists(Rec.ActionKey) then
      raise ESqlTemplate.CreateUtf8(
        'SqlTemplates.Add: duplicate key [%]', [Rec.ActionKey]);
    fMap.Add(Rec.ActionKey, Rec);
  finally
    fSafe.WriteUnLock;
  end;
end;

function TSqlTemplateRegistry.Find(const Action: RawUtf8;
  var Rec: TSqlRec): boolean;
begin
  fSafe.ReadOnlyLock;
  try
    result := fMap.FindAndCopy(Action, Rec);
  finally
    fSafe.ReadOnlyUnLock;
  end;
end;

function TSqlTemplateRegistry.Reload(const Recs: TSqlRecArray): integer;
var
  fresh: TSynDictionary;
  kinds: TSqlParamKinds;
  msg: RawUtf8;
  i: PtrInt;
begin
  result := -1;
  if Recs = nil then
    exit;
  { build the new set completely before touching the live one }
  fresh := NewMap;
  try
    for i := 0 to high(Recs) do
      if (Recs[i].ActionKey = '') or
         { see Add }
         ((Recs[i].Sql = '') and
          (Recs[i].RecordType = '')) or
         { see Add: a declaration needs the name it is registered under }
         ((Recs[i].RecordDecl <> '') and
          (Recs[i].RecordType = '')) or
         fresh.Exists(Recs[i].ActionKey) or
         { a declaration that does not parse would refuse every call at run
           time; refusing the set is the earlier and louder place }
         not ParseParamTypes(Recs[i].ParamTypes, kinds, msg) then
        exit // fresh is freed below, the running registry stays untouched
      else
        fresh.Add(Recs[i].ActionKey, Recs[i]);
    if fresh.Count = 0 then
      exit;
    fSafe.WriteLock;
    try
      FreeAndNil(fMap);
      fMap := fresh;
      fresh := nil; // now owned by this instance
      result := fMap.Count;
    finally
      fSafe.WriteUnLock;
    end;
  finally
    fresh.Free;
  end;
end;

function TSqlTemplateRegistry.AllKeys: TRawUtf8DynArray;
begin
  result := nil;
  fSafe.ReadOnlyLock;
  try
    fMap.Keys.CopyTo(result);
  finally
    fSafe.ReadOnlyUnLock;
  end;
  QuickSortRawUtf8(result, length(result));
end;

function TSqlTemplateRegistry.Count: integer;
begin
  fSafe.ReadOnlyLock;
  try
    result := fMap.Count;
  finally
    fSafe.ReadOnlyUnLock;
  end;
end;

end.
