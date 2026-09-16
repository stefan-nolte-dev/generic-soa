unit DomSqlServices;

{$I mormot.defines.inc}

{ What the application layer needs from the domain layer, and nothing else.

  The consumer states its requirement, the domain implements it - the same
  arrangement as InfraSqlServices one layer down. AppSqlImplementation sees
  IDomSqlTool and never TDomSqlTool, the registry or a statement.

  Note what crosses the boundary in place of a session: a TSqlCaller, filled
  by the application layer from the HTTP request. Below this line nothing
  knows that there is an HTTP request, a header or a token at all - so the
  rights check can be tested by handing it a record. }

interface

uses
  mormot.core.base,
  SqlStatus;

type
  /// who is asking - the application layer's answer to "which session"
  // - deliberately a plain record: the domain layer must not have to reach
  // into a REST context to find out who is calling
  TSqlCaller = packed record
    /// false when no valid token was presented
    // - the first thing checked, and the cheapest: an unknown key from an
    // unauthenticated caller is refused before anything is looked up
    Authenticated: boolean;
    /// the session's user, for the log
    UserID: integer;
    /// the session's user name, for the log
    UserName: RawUtf8;
    /// bitmask of the groups this caller may read with, against
    // TSqlRec.ReadGroups
    // - bit 0 is group 1: at most 64 groups, which is what the masks hold
    Reads: Int64;
    /// the same for writing, against TSqlRec.WriteGroups
    // - two masks and not one, because the templates have carried two from
    // the start: a caller who may read a table and not write it is the
    // ordinary case, and one mask for both could not say it
    Writes: Int64;
  end;

  { IDomSqlTool

    One method per shape of call, not per query - the same trade as the
    service contract above it.

    Every method takes the caller: the domain layer decides, so it has to be
    told who is asking, and it must not be able to find out any other way. }
  IDomSqlTool = interface
    ['{2A3F6C41-9E8B-4D77-B1E5-6C0D2F84A913}']
    /// run a registered select and return its rows as JSON
    function SelectJson(const Caller: TSqlCaller; const Action: RawUtf8;
      const Bounds: variant; var Json: RawUtf8): TSqlStatus;
    /// run a registered insert, update or delete from a list of values
    function WriteData(const Caller: TSqlCaller; const Action: RawUtf8;
      const Bounds: variant): TSqlStatus;
    /// run a registered insert or update from one serialised record
    function WriteRecord(const Caller: TSqlCaller; const Action: RawUtf8;
      const Json: RawUtf8): TSqlStatus;
    /// the action keys this caller could name
    function AvailableActions(const Caller: TSqlCaller): TRawUtf8DynArray;
    /// re-read the templates, whether or not the source changed
    // - the unconditional one; the automatic reload on an unknown key is
    // inside the implementation and asks the source first
    function ReloadTemplates(const Caller: TSqlCaller): TSqlStatus;
    /// how many templates are registered, for the startup banner
    function TemplateCount: integer;
  end;

implementation

end.
