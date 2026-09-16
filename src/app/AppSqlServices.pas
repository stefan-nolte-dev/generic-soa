unit AppSqlServices;

{ The service contract - four methods, for every query there will ever be.

  The usual style declares one method per query, so the contract grows with
  the application. Here the query is named by a parameter instead of by a
  method, and the contract stays the size it is now.

  Given up is the typed signature. Kept is the typed result: the client passes
  the RTTI of what it wants and gets that back - see ParseDynArray and
  WriteRecord in u_client_parsing. The type stays with the consumer instead of
  travelling through every layer. }
interface

uses
  mormot.core.base,
  mormot.core.interfaces,
  SqlAuthTypes, // TSessionToken: what a login hands back
  SqlStatus;

type

  { IAppSqlTool }

  IAppSqlTool = interface(IInvokable)
    ['{E6F9868C-ACDF-403D-8175-CBACEE71CC1D}']
    /// run a registered select and return its rows as JSON
    // - Bounds is a variant array, one value per ? in the statement
    function GetJsonFromAction(const Action: RawUtf8; const Bounds: variant;
      var Json: RawUtf8): TSqlStatus;
    /// run a registered insert, update or delete
    function WriteDataForAction(const Action: RawUtf8;
      const Bounds: variant): TSqlStatus;
    // Funktioniert ähnlich wie ORM, aber man müsste es RRM nennen (Record Relational Mapping)
    // Param: action: gibt Information über zu erledigendes Add oder Update an Hand des Präfixes.
    // Über den Namen nach dem Präfix kann RTTI abgefragt werden.
    // Param Json: Ein gewöhnlicher Record wird im Server mit Hilfe von Mormot zu Json serialisiert
    // und erscheint hier als zweiter Parameter.
    // Action und Json liefern: Keys, Values und die Pascal-Typen der Felder.
    // So hat man alle Informationen beisammen um ein
    // Insert- oder Updatestatement zu generieren. Dieser Ansatz funktioniert für alle Typen,
    // so dass neben dem Record-Typ kein weiterer Typ wie TORM und auch kein
    // weiterer Code notwendig ist.
    function WriteRecordForAction(const Action: RawUtf8;
      const Json: RawUtf8): TSqlStatus;
    /// the action keys this server is able to answer
    // - costs nothing: the registry knows its own keys
    function AvailableActions: TRawUtf8DynArray;
    /// re-read the templates from wherever they came from
    // - the point of keeping them outside the binary: a new statement without
    // a rebuild. A bad set leaves the server on the one it had
    // - administrative: in a real deployment this belongs behind a rule
    function ReloadTemplates: TSqlStatus;
  end;

  { IAppAuthTool

    Logging in, and nothing else - separate from IAppSqlTool, because an
    interface that runs queries should not also hand out identities. The same
    split the auth service next door makes between IGlobAuth and
    IAuthorizationManager.

    Login is the one method that answers without a token. It needs no
    exception list to be reachable: the refusal lives in the domain layer,
    behind the template registry, and a login never goes there. }
  IAppAuthTool = interface(IInvokable)
    ['{5C1B7A93-6D42-4E58-9F31-2A7E0C4D86B5}']
    /// log in and receive a token to carry on every later call
    // - sqlNeedsLogin for an unknown user, a wrong password and a blocked
    // account alike: which of the three it was is not the caller's business
    // - the token goes into the Authorization header of the client, and
    // nothing else here ever sees it again
    function Login(const UserName, Password: RawUtf8;
      out Token: TSessionToken): TSqlStatus;
    /// who is calling, and for how much longer
    // - so a client can show its user and its remaining time instead of
    // finding both out by being refused
    function WhoAmI(out UserName: RawUtf8; out Reads, Writes: Int64;
      out SecondsLeft: integer): TSqlStatus;
  end;

const
  APPSQL_ROOT = 'sqltemplates';
  { the fallback port, and the demo profile's - each profile has its own, so
    two of them can run at the same time. The table is in SqlProfiles.pas;
    this one exists because a default parameter needs a plain constant }
  APPSQL_PORT = '8890';

implementation

initialization
  TInterfaceFactory.RegisterInterfaces([
    TypeInfo(IAppSqlTool),
    TypeInfo(IAppAuthTool)]);

end.
