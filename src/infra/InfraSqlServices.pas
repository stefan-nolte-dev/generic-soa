unit InfraSqlServices;

{$I mormot.defines.inc}

{ What the domain layer needs from this one, and nothing else.

  The consumer states its requirement, the infrastructure implements it - so
  the dependency points upwards, and DomSqlImplementation sees the two
  interfaces without seeing a connection, a driver or a statement. The unit
  sits in infra all the same, because a client has no business seeing it:
  the folder is what the client's search path leaves out.

  Both interfaces take or return a TSqlRec, never the registry - which is why
  this layer can be handed a template but cannot look one up. }

interface

uses
  mormot.core.base,
  SqlStatus,
  SqlTemplateTypes;

type
  { ISqlTemplateExec

    Every method takes a template the layer above has already resolved and
    cleared, and none of them raises for anything a caller could have caused.

    Do not widen them to take a plain RawUtf8 statement: a TSqlRec is only
    ever issued by the registry, and that is what keeps this from becoming
    "send me any SQL". }
  ISqlTemplateExec = interface
    ['{F671C5BB-B2AA-4808-96C9-40D7711CA980}']
    /// run a resolved select and return its rows as a JSON object array
    // - Json is '[]' for every outcome other than sqlOk, so a caller that
    // ignores the status still gets something DynArrayLoadJson can read
    function SelectJson(const Rec: TSqlRec; const Bounds: variant;
      var Json: RawUtf8): TSqlStatus;
    /// run a resolved insert, update or delete from a list of values
    function Execute(const Rec: TSqlRec; const Bounds: variant): TSqlStatus;
    /// run a resolved insert or update from one serialised record
    // - the statement is generated here, from the record type and the action
    // key, or its :Name placeholders are filled - see SqlRecordBind. Which is
    // why the domain layer hands the JSON down untouched: composing SQL is
    // this layer's business
    function ExecuteRecord(const Rec: TSqlRec;
      const Json: RawUtf8): TSqlStatus;
  end;

  { ISqlTemplateSource

    Where the templates come from - a file, or the compiled statements. The
    domain layer owns the registry and asks a source to fill it, so nothing
    below has to know that a registry exists.

    Changed() is the one that keeps an unknown action key cheap: it is asked
    before a reload, so a mistyped key costs a stat call and not a query. }
  ISqlTemplateSource = interface
    ['{7B5D0E92-4C1A-49F3-A8D6-3E2B9F017C48}']
    /// has the source changed since the last successful Load
    function Changed: boolean;
    /// read every template from the source
    // - false when it could not be read at all; the reason goes to the log
    function Load(out Recs: TSqlRecArray): boolean;
    /// what to call this source in a log line or the startup banner
    function SourceName: RawUtf8;
  end;

implementation

end.
