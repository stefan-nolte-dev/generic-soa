unit AppSqlImplementation;

{$I mormot.defines.inc}

{ The application layer - the edge, and nothing but the edge.

  It does three things: it publishes IAppSqlTool, it turns the HTTP request
  into a TSqlCaller (see AppCallerToken), and it forwards. It decides
  nothing. Whether a key exists, whether this caller may use it and whether
  the values hold up is the domain layer's business; composing and running
  SQL is the infrastructure layer's.

  That is what the thinness is for: everything transport shaped stops here,
  so the layers below can be exercised without an HTTP server. }
interface

uses
  mormot.core.base,
  mormot.core.interfaces,
  AppSqlServices,
  AppCallerToken,
  DomSqlServices, // the interface only - the implementation stays invisible
  SqlStatus;

type

  { TAppSqlTool }

  TAppSqlTool = class(TInterfacedObject, IAppSqlTool)
  private
    fDom: IDomSqlTool;
  public
    constructor Create(const aDom: IDomSqlTool); reintroduce;
    function GetJsonFromAction(const Action: RawUtf8; const Bounds: variant;
      var Json: RawUtf8): TSqlStatus;
    function WriteDataForAction(const Action: RawUtf8;
      const Bounds: variant): TSqlStatus;
    function WriteRecordForAction(const Action: RawUtf8;
      const Json: RawUtf8): TSqlStatus;
    function AvailableActions: TRawUtf8DynArray;
    function ReloadTemplates: TSqlStatus;
  end;

implementation

uses
  SqlTemplateTypes; // for ESqlTemplate

{ TAppSqlTool }

constructor TAppSqlTool.Create(const aDom: IDomSqlTool);
begin
  inherited Create;
  if aDom = nil then
    raise ESqlTemplate.Create('TAppSqlTool.Create(nil)');
  fDom := aDom;
end;

function TAppSqlTool.GetJsonFromAction(const Action: RawUtf8;
  const Bounds: variant; var Json: RawUtf8): TSqlStatus;
begin
  Json := '[]';
  result := fDom.SelectJson(CurrentCaller, Action, Bounds, Json);
end;

function TAppSqlTool.WriteDataForAction(const Action: RawUtf8;
  const Bounds: variant): TSqlStatus;
begin
  result := fDom.WriteData(CurrentCaller, Action, Bounds);
end;

function TAppSqlTool.WriteRecordForAction(const Action: RawUtf8;
  const Json: RawUtf8): TSqlStatus;
begin
  result := fDom.WriteRecord(CurrentCaller, Action, Json);
end;

function TAppSqlTool.AvailableActions: TRawUtf8DynArray;
begin
  result := fDom.AvailableActions(CurrentCaller);
end;

function TAppSqlTool.ReloadTemplates: TSqlStatus;
begin
  result := fDom.ReloadTemplates(CurrentCaller);
end;

end.
