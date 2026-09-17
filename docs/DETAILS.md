# SQL templates as a SOA service — the long version

> The short overview is [README.md](../README.md). This is the same design in
> full: the whole measurement, the editor, declared parameter types, the rights
> mask, and what is deliberately left out.

A mORMot 2 sample: instead of declaring one interface method per query, the
service declares a handful, and the query is named by a parameter.

```pascal
IAppSqlTool = interface(IInvokable)
  function GetJsonFromAction(const Action: RawUtf8; const Bounds: variant;
    var Json: RawUtf8): TSqlStatus;
  function WriteDataForAction(const Action: RawUtf8;
    const Bounds: variant): TSqlStatus;
  ...
end;
```

`Action` is a key into a registry of named SQL statements. Adding a query means
adding a statement and a key — no interface method, no implementation body, no
DTO on the server, and no change in any layer between.

## What is given up, and what is kept

Given up is the typed signature: the compiler no longer checks that a caller
passes the right number and kind of parameters for a particular query.

Kept is the typed **result**. The client passes the RTTI of the array it wants
and gets that array back:

```pascal
Customers := nil;
status := ParseDynArray('GetCustomersByCity', _Arr(['Wegberg']),
  Customers, TypeInfo(TDtoCustomerArray));
// Customers[0].City — a record the server has never heard of
```

That holds for reading, which is what this sample is mostly about. For writing
a whole record it does not, and it cannot: see *Writing a whole record* below.

`ParseDynArray` is 16 lines, written once, and serves every query the server
will ever offer — the same call site shape for every action key and every row
shape. `ClientTests` shows it twice over on records that have nothing in
common, `TDtoCustomer` and `TDtoTurnover`, and each block names the type it
parsed into. The DTO lives in the client only. Nothing has to be mirrored
across an application layer, a domain layer and a persistence layer, and there
are no field-by-field converters between them.

This is not a replacement for interface-based SOA. It is meant for the part of
an application where the ORM does not reach: reports, aggregates, joins with
conditions on the aggregate — the queries that end up as hand-written SQL
anyway. The trade is deliberate, and so is its scope.

## What this costs, measured

The comparison is against a typed mORMot application in production —
*the typed service* below — on a query that exists in both worlds: return a
lookup table — a select of two columns, no parameter. A category lookup
there, `GetAllCustomers` here.

Counted are productive lines only: no blank lines, no comments, no tests.

The two sides are counted **separately for server and client**, because only
one of them is actually in dispute. A caller wants a Pascal array of records
either way, so the record has to exist either way. What differs is what the
server has to grow to answer one more question.

### What the server costs, per query

**The conventional route — one method per query**

| what | lines | where |
|---|---:|---|
| domain persistence interface, declaration | 1 | domain layer, persistence unit |
| persistence class, declaration | 1 | infrastructure layer, SQLite unit |
| persistence body: statement and row loop | 21 | infrastructure layer, SQLite unit |
| domain DTO, its array and its RTTI registration | 7 | application layer, DTO unit |
| service interface, declaration | 1 | application layer, service unit |
| service class, declaration | 1 | application layer, service implementation |
| service body: field-by-field copy into the second DTO | 17 | application layer, service implementation |
| **total** | **49** | **5 files** |

**The action key**

| what | lines | file |
|---|---:|---|
| the statement and its key | 0 | one row in `templates.sqlite` |
| **total** | **0** | **no Pascal at all** |

**49 against nothing.** No rebuild, no restart, and the running server picks
the key up by itself. There used to be a second column here for a variant with
the statements compiled in — three lines in two files — and it was dropped on
purpose: two origins for the same statement drift apart, and this one is the
origin.

The gap widens with the row. Each additional column costs the conventional
route two copy lines — once out of the result set, once between the DTOs —
plus a field in each of its two records. On the action-key side an extra
column costs nothing on the server at all: it is already in the statement.

### What the client costs, per row shape

| | lines | where |
|---|---:|---|
| conventional | 7 | application layer, DTO unit, shared with the server |
| action key | 5 | `src/client/ClientDtos.pas`, client only |

These two are almost the same, and that is the point: this is the work you do
either way, so it does not belong in the comparison above. The difference of
two lines is the `RegisterFromText` call, which this sample no longer needs
(see the editor's type generator) while the typed service still carries one per
DTO.

Note where the file lives, though. The typed service's record sits in the application
layer, is compiled into the server, and travels through the service contract;
the same data also exists as a second record one layer down, with a converter
between them. Here it exists once, in the client, and the server has never
heard of it.

### At the scale of a whole application

In the typed service today:

- **50 methods** in the application-layer interfaces (26 and 24 across two).
  Each exists again in the domain interface and again in two implementation
  classes.
- **32 DTO records** and **33 RTTI registrations** in one unit — the
  application and domain versions of the same data, side by side.
- **134 lines** in the service implementation that do nothing but copy one
  record's field into the next layer's record. The largest single converter is
  **174 lines**.

Against that, everything this sample needs on the server — registry, both
loaders, execution, application layer, contract, startup — is **1109 lines**,
and **1058 of them are fixed cost**: paid once, and unchanged when a query is
added.

**What the comparison does not claim.** The typed service's bodies do a little more than
fetch: they go through the ORM and they carry a fallback between embedded and
remote persistence. Its ORM classes are not counted, since the schema is
needed regardless. The typed service's 3327 lines of test code are left out on
both sides — they are named only because they are the part that was most
expensive to maintain, and because they too are written per method.

And what the conventional route buys for its 49 lines is a compiler-checked
parameter list. That is the trade described above, priced.

## Layout

```
src/common/     SqlStatus.pas               the TSqlStatus enumeration
                SqlParamTypes.pas           declared parameter kinds, and coercion
src/commonserv/ SqlTemplateTypes.pas        TSqlRec - the type, nothing acting on it
src/app/        AppSqlServices.pas          the service contract, outward
                WriteDtos.pas               the records BOTH sides need
                AppCallerToken.pas          JWT from the header -> TSqlCaller
                AppSqlImplementation.pas    the HTTP edge: forward, and nothing else
src/dom/        DomSqlServices.pas          what the layer above needs from here
                DomSqlImplementation.pas    resolve, rights, rules - the decisions
                SqlTemplateRegistry.pas     action key -> TSqlRec
src/infra/      InfraSqlServices.pas        what the layer above needs from here
                InfraSqlImplementation.pas  the only place SQL runs
                SqlRecordBind.pas           one record -> statement and bound values
                SqlTemplatesFromDb.pas      the only source: a templates file
src/serv/app/   ServSqlTemplates.pas        startup — sees everything
src/client/     ClientDtos.pas              read-only records, client side only
                AppSqlClient.pas            connection
                u_client_parsing.pas        ParseDynArray, WriteRecord
src/clienttests/ ClientTests.pas           the proof of concept
src/clientlaz/ u_main.pas / .lfm           one button, one memo
src/editor/     EditorDb.pas                the editor's own connection
                SqlBounds.pas               typed parameters, and inlining them
                EditorExec.pas              run a statement, roll it back
                TemplateStore.pas           templates.sqlite, open and close
                DtoCodeGen.pas              result set -> record declaration
                u_editormain.pas / .lfm     the editor window
```

### Three layers, one job each

| layer | does | knows nothing about |
|---|---|---|
| app | take the token out of the HTTP header, build a `TSqlCaller`, forward | templates, rights, SQL |
| dom | resolve the action (reloading if need be), check rights, check rules | HTTP, connections, SQL |
| infra | coerce the values, generate or fill the statement, bind, execute | who is asking, or whether they may |

A call goes through `TDomSqlTool.Resolve` in this order: authenticated → action
known → rights against the *concrete* action → rules. The authentication check
is first, because otherwise any caller at all could reach the reload below it.

What crosses the boundary in place of a session is a `TSqlCaller`: a plain
record of user, name and group mask. Below the application layer nothing knows
that there is an HTTP request, a header or a token — so the rights check can be
tested by filling in a record instead of by faking a session.

### Visibility

The folders are what each project puts on its unit search path:

| project | sees |
|---|---|
| client | `common`, `app`, `client`, `clienttests`, `clientlaz` |
| server | `common`, `commonserv`, `infra`, `dom`, `app`, `serv/app` |
| editor | `common`, `commonserv`, `infra`, `dom`, `app`, `client`, `editor` |

The search path is only the coarse promise. The exact one is in the uses
clauses, and two splits exist for that alone:

- **`TSqlRec` does not live with the registry.** The type is in
  `commonserv/SqlTemplateTypes.pas`, the registry in
  `dom/SqlTemplateRegistry.pas`. The infrastructure layer is handed a template
  and cannot look one up — readable in the uses clause of
  `InfraSqlImplementation`, which names `SqlTemplateTypes` and not the registry.
- **The profile table and the connection are in different folders.**
  `common/SqlProfiles.pas` holds the names, ports and file names, because the
  server, the client and the editor all three read them and must not disagree
  about what `mssql` means. `commonserv/SqlServerConn.pas` holds the host,
  the driver and the connection string, because the editor needs them and a
  client has no business carrying a host name in its binary. `SqlProfiles`
  names the database and nothing more.
- **`WriteDtos` appears in no uses clause below `app`.** The record type is
  found at run time through `Rtti.FindName`, by the name in the `RecordType`
  column; what makes it findable is the `initialization` in `WriteDtos`, which
  only the startup unit pulls in. To the objection that the infrastructure
  layer here sees application types: it sees a string and a `PRttiInfo`. Take
  `app` off its search path and it builds.

One honest qualification remains: the folder is a blunt instrument. `app` holds
the contract, which the client must see, and the implementation, which it need
not — and one search path cannot tell the two apart. What keeps a client out of
`AppSqlImplementation` is its uses clause.

And the enforcement is only as good as those search paths: there is no compiler
rule, and every project carries its own list. What makes it checkable is a
build per layer with the path cut down — infra with `common commonserv infra`,
app with `common commonserv dom app` and no `infra`. The separation is shown by
that build, not by a diagram.

## Build

```
lazbuild src/proj/soa_sql_templates_server.lpi
lazbuild src/projclientlaz/soa_sql_templates_client.lpi
lazbuild src/projeditor/soa_sql_templates_editor.lpi
```

Both land in `bin/`. The demo database `demo.sqlite` is created and filled on
first start; delete it to start over. The seeding code is what defines it —
`bin/demo.sql` is that same state written out, to read in a diff and to
restore from with `sqlite3 demo.sqlite < demo.sql`.

## Run

The templates come from a templates file next to the binary, and from nowhere
else — no statement of this application is compiled in. Which file is what the
profile decides; without an argument it is the demo:

```
./soa_sql_templates_server
```

Then start the client and press the button.

Both `templates.sqlite` and its text export `templates.sql` are in version
control. Should the binary one ever be missing, the server rebuilds it from
the export at startup: that file carries its own `create table` and is a plain
SQL script, so `sqlite3 templates.sqlite < templates.sql` does the same by
hand. Is neither there, the server refuses to start and says which two files
it looked for - better than serving an empty set.

### One database per service

A service talks to one database, and the templates of that database live in
one file next to it. Two databases are two services, two template files, two
histories - which is also what keeps a merge small. The sample carries two
profiles, named on the command line:

```
./soa_sql_templates_server          # demo:   templates.sqlite -> demo.sqlite
./soa_sql_templates_server mssql   # mssql: templates_mssql.sqlite -> SoaSample
```

A profile decides two things and nothing else: which connection, and which
file. `Props` is a `TSqlDBConnectionProperties`, so no layer below the startup
unit can tell SQLite from SQL Server - and the action keys of one profile are
simply unknown in the other. Adding a profile is a branch in `StartServer` and
a second templates file; nothing else moves.

The `mssql` profile connects to SQL Server over unixODBC, authenticating with
Kerberos - `Trusted_Connection=yes`, so no credential is in the source, in the
environment or in a configuration file. It needs a ticket (`kinit`), a route
to the server, and, against a server that offers TLS 1.0 only,
`openssl-tls1.cnf` next to the binary. `src/commonserv/SqlServerConn.pas` carries the four macOS
specifics as a comment - it sits in commonserv because the editor connects
to the same server, and a client has no business knowing a host name.

Both servers may run at once: each profile has its own port (8890 and 8891).
The client and the editor each have a profile box - the client switches port
and reloads the key list from `AvailableActions`, the editor switches the
templates file and the target database together.

## Adding a query without rebuilding

With the server running:

```sh
sqlite3 bin/templates.sqlite \
  "insert into SqlTemplate (ActionKey, Sql) values \
   ('GetCustomerCount', 'select count(*) as Anzahl from Customer;');"

curl -s -X POST \
  http://127.0.0.1:8890/sqltemplates/AppSqlTool.ReloadTemplates -d '[]'
```

The key answers immediately afterwards — no restart, no rebuild.

For a *new* key the explicit reload is not even needed: the server refuses a key
it does not know, but before it does it asks the source whether the file has
changed, and reads it again if so. `ReloadTemplates` remains for the other case
— a statement that was **edited** under a key the server already knows.

The table is read at startup, on `ReloadTemplates`, and on an unknown action
key if the file has changed since — never per
request: a lookup per call would add a query to every request and would mean
the templates a running server uses can change under it.

A reload builds and checks the new set before touching the live one. A set with
a duplicate key, an empty key or an empty statement is refused, `ReloadTemplates`
returns `sqlFailed`, and the server keeps serving what it served before.

## The template editor

A third program, `soa_sql_templates_editor`, edits a templates file, tests a
statement, and writes the record declaration that will receive the result. It
is a developer tool. It does not belong next to the client on a user's
machine.

Which templates file is decided by the profile box, and it sets the target
database in the same move - `demo` means `templates.sqlite` against
`demo.sqlite`, `mssql` means `templates_mssql.sqlite` against the SQL Server
database over ODBC. The two belong together: editing one profile's
statements against the other profile's database is the mistake this
prevents. Switching drops a live connection, because that connection was to
the other database.

It has its own connection to the data database - its own, and not the
server's: the editor talks to the SQL Server with no server running, and
needs a route there and a ticket for it, not a process on port 8891. The
profile presets that connection and the top row can override it, in one of
two forms: a SQLite file or a full ODBC connection string. The same editor
therefore works against this sample and against SQL Server, because
underneath it is a `TSqlDBConnectionProperties` like the server's.

The driver box and the profile box move together, either way round: the
profile table says which driver a target needs, so picking a driver picks the
profile that runs on it, and the target and templates file follow. Left apart
they can disagree, and that particular disagreement - an ODBC connection
string with a SQLite path as the target - hangs in the driver instead of
failing. An ODBC data source entry is gone for the same reason: a DSN is a
name unixODBC looks up in a file this sample does not ship, and a driver
asked for one it cannot find waits rather than says so.

A search box sits above the key list. It filters the list while you type, case
insensitively and anywhere in the key. Thirty names still fit on the screen; a
set that has grown does not, and scrolling for one name is exactly what the box
saves. What it costs is the identity between a row and a record: once a line
can be hidden, the fifth row is no longer the fifth template, so each line
carries its own position rather than being counted.

**Testing does not go through the server.** The server has no method that runs
unregistered SQL, and giving it one would undo the property the sample is
built on. So the editor runs the statement itself — but through
`TSqlTemplateExec`, the server's own execution code, on an ad hoc `TSqlRec`.
What you test is what will run, down to the JSON.

**A test changes no data while the Rollback box is ticked, and it is ticked
until someone unticks it.** There is no throwaway copy of the database here,
because against SQL Server there could not be one. What protects the data is
the transaction: a write is wrapped in one and rolled back on every path out
of `EditorExec` - every path but the one the box opens. That covers insert,
update and delete.

Unticked, a write that ran is committed and the row stays in the database,
which is the point: some things can only be judged by looking at them with
something else. The switch is deliberately hard to be unaware of - the window
title says `ROLLBACK AUS` for as long as it is off, the log says so the moment
it is flipped, and the run's own message says `COMMITTED` rather than the
usual "rolled back". Two things still never commit: a statement that failed,
and a run that raised - a commit that raises itself ends as a rollback. The
default of `TWriteEnd` is `weRollback`, so a caller that says nothing gets the
old behaviour, and the editor's box is the only thing in the sample that ever
says otherwise.

Which makes deciding what counts as a write part of the protection, not a
detail of the display. A common table expression is not a statement kind:
`with x as (...) delete from x` is as legal as the select that usually follows
a `with`, and classified as a select it would run outside the transaction and
commit. The first keyword cannot decide it, so the rest of the text does - a
write verb standing anywhere outside a string literal makes the whole thing a
write. An alias that merely reads like `update` costs the row display; the
confusion in the other direction costs data. It does not cover everything — DDL is not transactional on every
engine, identity and sequence counters do not roll back, and a trigger with an
effect outside the database is out of reach. Point the editor at a development
database.

| button | what it does |
|---|---|
| Record-Werte eingeben… | for an `OrmAdd…`/`OrmUpdate…` key: a dialog built from the fields of its record type — for an update, filled from the row that key names — and the record it produces run through the server's own binding, in the same transaction the Rollback box decides the end of |
| Prüfen | the checks that need no database: parameter count against the `?` in the statement (ignoring any inside a string literal), a `where` in every update and delete wherever the verb stands - after a common table expression it is in the middle, which is where a missing `where` is easiest to overlook - a recognisable first keyword — then the whole set through `TSqlTemplateRegistry.Reload`, the same check the server applies on `ReloadTemplates`. What the editor accepts, the server accepts. |
| Testen | runs it, on whichever of the two paths the checkbox selects. With nothing in the SQL box and a record type named, there is a third: the record goes down with an empty statement and the server's own code generates it - `SelectJson` for an `OrmRetrieve…`, `Execute` for an `OrmDelete…` - with the one bound value as the key. The kind is read off the action key, because there is no text to read it off yet. Selects show as JSON - reformatted, or exactly as it goes on the wire - and as a generically built table; writes are rolled back unless the Rollback box is unticked, and then they are committed and said to be. The `?` are counted before any driver is touched: a missing value is a NULL and no rows on SQLite and an exception with no recoverable reason on ODBC, and the count is the reason. A failure carries the driver's own words - the reason infra kept on the way out, or `Connection.LastErrorMessage` for a statement the driver refused outright - not a pointer to a log you cannot see, and brings the messages to the front rather than leaving an empty JSON tab there. |
| aus Parametern übernehmen | fills `ParamTypes` from the kinds already chosen for the test values - the declaration and the values then cannot disagree. It fills itself while the field is empty; the button overwrites |
| Typ aus Ergebnis erzeugen | the record and its array, ready to paste into `ClientDtos.pas` |
| In die Zwischenablage | that source, on the clipboard |
| Speichern / Löschen | one template in `templates.sqlite`, and `templates.sql` rewritten right after - the readable half of a binary file cannot fall behind if nobody has to remember it. There is no export button: one next to Speichern reads as a step Speichern does not take |
| Server neu laden | `ReloadTemplates` on a running server — the new key answers without a restart |

### Parameters have declared types

The values are not typed by guessing what their text looks like. Each one is
entered with a type from the dropdown and appended to the list, one at a time:

```
[text] Wegberg
[int] 500
[date] 2026-08-30
[null]
```

That list is both the display and, for anyone who would rather type, the
input. A line without brackets is taken as `[text]`.

The eight types are not a matter of taste. `Bounds` is a `variant` in the
service contract, and mORMot's `VariantToVarRec` wraps every value as
`vtVariant` *by reference*, so the open array `Bind` receives is a list of
variant references and `BindVariant` dispatches on the **variant's** type -
`varDate` to `BindDateTime`, `varCurrency` to `BindCurrency`. The list is
exactly what `BindVariant` distinguishes; anything else would be a fiction.

Next to the list stands the JSON those values become. That is what a client
actually puts on the wire, and it is worth looking at, because JSON knows only
null, boolean, number and string. A `[date]` travels as a string and is bound
as a string on the other side — so "Prüfen" re-reads the JSON with
`JSON_FAST_FLOAT`, which is what `TInterfaceFactory` sets for a variant
argument, and names every parameter whose type would change on the way. That
is the server's own parsing, not an approximation of it.

### The counter-check

Sharing the server's execution code buys fidelity and costs blindness: if the
fault were in the binding — a value that never arrives, an order quietly
wrong — the editor would reproduce it and report success. Nothing in a shared
path can reveal a fault in the shared path.

The checkbox **Gegenprobe** answers that. It writes the values into the
statement as SQL literals and binds nothing, so the two runs have no code in
common where the fault could hide. Same result, and the binding delivered what
the literal says. Different, and you know where to look.

Three things it does not promise. The literal rendering can itself be wrong,
which gives a false alarm — the safe direction, but not a free one. Dates and
floating point do not necessarily round-trip through a literal bit for bit, so
a difference is a reason to look rather than a verdict. And this path builds
SQL by concatenation, which is precisely what the registry exists to avoid: it
lives in the editor, on a development database, and must never become
reachable from the server.

### The generated type

The generator infers the field types from the JSON that came back, not from
the database schema. That is on purpose: SQLite reports nothing useful for an
expression such as `count(i.ID)` before the first row is read, and what the
record has to match is what arrives over the wire anyway. Every returned row
is inspected, so a null in the first row does not decide a type on its own. It
is a starting point and says so: a column that was null in every row cannot be
typed, and a numeric column that happened to hold whole numbers only will come
out as `integer`.

It gets right the thing that is easy to get wrong by hand: the field names
have to match the column names of the statement. Run it on
`GetTurnoverPerCustomer` and it reproduces the `TDtoTurnover` in
`ClientDtos.pas` character for character.

It also emits an `Rtti.RegisterFromText` call, **commented out**. mORMot gates
extended record RTTI as `HASEXTRECORDRTTI`, which covers Delphi 2010 and later
and FPC trunk 3.3/3.4 - measured here with the same record and the same JSON,
**FPC 3.3.1 parses correctly without it and FPC 3.2.3 parses nothing**. So the
client needs the record and the call and nothing else, unless it is built with
FPC 3.2, and then that line is there to be uncommented. Its field order is the
**declaration** order, because it describes the memory layout and not the JSON.

On Delphi there is a second condition, which mORMot flags in its own source at
`mormot.core.rtti.delphi.inc`: reading the field table "may need `$RTTI
EXPLICIT FIELDS([vcPublic])`" in the unit. That is untested here, for want of
a Delphi.

Every template operation opens `templates.sqlite` and closes it again, the way
the server's loader does, so the editor and a running server never fight over
the file.

`templates.sqlite` is the origin, and the editor keeps its readable twin in
step: every save and every delete rewrites `templates.sql` next to it. Both are
in version control - the binary one so a clone can just start, the text one so
a commit has a diff that can be read and a backup the whole set restores from.
The export carries no timestamp on purpose: an unchanged set has to produce an
unchanged file, or every commit shows a diff that means nothing.

## Who does what

The application layer is the edge: it takes the token out of the header, builds
a `TSqlCaller` and forwards. It decides nothing. The domain layer resolves the
action key to its `TSqlRec`, checks the rights against that concrete action and
applies the rules. The infrastructure layer coerces the values, generates or
fills the statement, binds and executes.

Refusing is one layer's job, running is another's:

| layer | answers |
|---|---|
| `AppSqlImplementation` | nothing of its own — it forwards |
| `DomSqlImplementation` | `sqlEmptyKey`, `sqlUnknownKey`, `sqlNotAllowed`, `sqlNeedsLogin` |
| `InfraSqlImplementation` | `sqlOk`, `sqlNoRows`, `sqlNothingWritten`, `sqlFailed`, `sqlBadParams` |

Resolving once and passing the record down is deliberate: looking the key up
again in the lower layer would leave a window in which a reload between the
check and the execution swaps the record, so the rule of the old one is checked
and the statement of the new one runs.

The cost is that the lower layer no longer enforces that only registered
statements run — it executes what it is handed. `TSqlRec` is only ever issued
by the registry, and the registry is in `dom`, where the infrastructure layer
cannot see it. `ISqlTemplateExec` is created in `ServSqlTemplates` and handed to
nobody but `TDomSqlTool`. Do not widen those methods to take a plain statement.

Both downward contracts — `DomSqlServices` and `InfraSqlServices` — are
declared with the provider and not with the consumer: the consumer states what
it needs, the layer below implements it, and the dependency points upwards.
They sit in their own folders all the same, because a client has no business
seeing them. `DomSqlImplementation` sees `ISqlTemplateExec` and not
`TSqlTemplateExec`, and cannot reach past it into SQLite or connection
properties. Only `ServSqlTemplates`, which wires everything together, knows the
classes.

### Where the templates come from

The domain layer owns the registry and has an `ISqlTemplateSource` fill it —
`TDbTemplateSource`, reading the profile's templates file. Nothing below it knows that a
registry exists at all. The interface stays even with one implementation: it
is what keeps the registry in dom and gives infra nothing but the file.

An unknown action key is the interesting case: it is either a typo, or a
template someone added while the server was running. So the source is asked
first, not the database — `TDbTemplateSource.Changed` compares the file's
timestamp *and* its size against the last load (both, because a filesystem
timestamp has one second of resolution). Only on a real change is the file read
and the registry replaced.

A new template therefore costs no restart, and a typo in a loop costs a `stat`
call rather than a query. Measured over HTTP: ten misses in a row with one
inserted row in between, and the log holds exactly two reload lines — startup,
and the real change.

## What a template declares

`TSqlRec` started as a key and a statement. It now carries ten more fields,
each fed from a column in `templates.sqlite`, and **nothing above the registry
had to move to add them** — which is the claim the table was there to make.

| column | what it does | unset means |
|---|---|---|
| `ParamTypes` | `text,int,date` — one entry per `?` | no coercion; values are bound as JSON made them |
| `Rules` | named checks on the parameters, `2:plz;3:email` | nothing is checked beyond the type |
| `TestBounds` | sample values for a test run, `["Wegberg"]` | the template is checked but never run |
| `ReadGroups` | bitmask of session groups that may read | see below |
| `WriteGroups` | the same for writing | see below |
| `RecordType` | the record a record write expects, by name | not a record write |
| `RecordDecl` | the fields of that record, as mORMot's textual RTTI | the type has to be compiled into the server |
| `KeyField` | the key column of a generated statement | `ID` |
| `CallerScope` | bind the caller's identity to the last parameter | client sets every value |
| `Filter` | the where clause of a generated list, without the word `where` | every row |
| `OrderBy` | its order, without the words `order by` | whatever order the database gives |

With `RecordType` set, `Sql` may be **empty** — that is the one case an empty
statement is allowed, and it means *generate it on arrival*.

A template file written before these columns existed keeps its rows and gains
them as NULL, which every reader treats as *not declared*. Verified on a
two-column file: the rows survive and the old keys still answer.

### Why a parameter needs a declared type

A client sends its parameters as JSON, and JSON knows null, boolean, number
and string. A date therefore arrives as a string, and mORMot binds it as a
string, because `BindVariant` dispatches on the variant's type and the variant
says text. That is where dates go wrong against SQL Server — not in the
statement, in the binding.

Declaring `date` moves the decision out of the value, where JSON keeps losing
it, and into the template, where it survives. `GetInvoicesSince` in this sample
is exactly that case:

```pascal
ParseDynArray('GetInvoicesSince', _Arr(['2026-01-01']),
  Invoices, TypeInfo(TDtoInvoiceArray));   // a string leaves the client
```

The application layer turns it into a `varDate` before the record goes down, so
the driver is asked for `BindDateTime`. A value that will not convert is
refused with `sqlBadParams` and never guessed at — `'31. August'` comes back as
a status, not as a wrong result and not as an exception.

A declaration that does not parse is refused when the **set** is loaded, not
when the key is called: a bad `ParamTypes` fails `ReloadTemplates` and the
server keeps the templates it had.

### Rules on the parameters

`ParamTypes` says what a value **is**. It has nothing to say about what shape
it has to have: `text` is happy with an empty string, and `int` with a postcode
of 4711. The `Rules` column is that second question, and it is answered the
same way everything else here is — the checks are code, naming them is data:

```
Rules = '1:notempty;2:plz;3:email'
```

The position comes first, so a template with twelve parameters and one rule
names one position instead of counting commas; several rules on one parameter
are several entries. `SqlParamRules` ships with `notempty`, `plz`, `email`,
`len:min[,max]`, `range:min,max` and `oneof:a,b,c`, and a new **kind** of check
is a function registered in Pascal — a new **use** of one is a row.

A null passes every rule but `notempty`: SQL NULL is valid in any column, and
refusing it because it is not a postcode would refuse a value the caller may
well be entitled to send.

The check runs in `TDomSqlTool.CheckRules`, after the caller's own value has
been bound — so a rule can be about the value the client never sent — and
before the statement is composed. Two answers, and the difference matters:

- a **value** that does not pass is `sqlBadParams`, like any other bad
  parameter, and the reason goes to the log as a warning
- a **declaration** that is itself wrong — an unknown rule name, a position no
  `?` exists at — is the template's mistake, not the caller's: it is logged as
  an error and answered `sqlFailed`, and nothing about the declaration is sent
  outside

Measured against the demo over HTTP: `AddKontakt` with `41844` and
`a@b.de` writes the row (`sqlOk`), with `4184`, with `a.b.de` or with a blank
name it is refused (`sqlBadParams`) and the log names the parameter;
`GetKontakteByPlz` with `abcde` never reaches the database. A row whose rule
names parameter 4 of a one-parameter statement answers `sqlFailed`.

One limit, said rather than hidden: the positions are the statement's `?`, and
a **record** write has none — its values are fields with names. A record
template that declares rules is refused (`sqlFailed`, logged), and the editor
says so before it can be saved. Rules by field name are the obvious next step.

### Checking the whole set at once

`Prüfen` answers for the template in front of the maintainer. `Alle prüfen`
answers for the file, which is the question before a commit: after a renamed
column, an edited record type or a new rights mask, **which** of the
twenty-nine keys stopped working?

Two halves, and the difference is deliberate. The checks need no database and
run on every template — the declaration parses, statement and parameters
agree, a `delete` has its `where`, the record type resolves, the rules read.
Running needs the `TestBounds` column: the values a client would send, as the
JSON a client would send them as. An array goes to the statement, an object is
one record's own JSON and goes down the record path — so a generated insert is
tested the same way as an ordinary select, from a column and without a line of
test code.

A template with no `TestBounds` is reported as **open**, never counted as
passed. So is a scoped one: the server binds the caller's value to the last
`?` and this tool binds no caller at all, so a green line there would be a lie
about the very template that most needs one.

Every run is rolled back, whatever the Rollback box says — that box is about
the one statement being looked at.

Measured on the demo, connected to `demo.sqlite`: 29 templates, 28 run, one
open (`GetMeineRechnungen`, scoped), nothing reported; the dump of the database
before and after is identical. And with seven rows deliberately broken in a
copy, seven findings, each naming the reason — a column that does not exist
(`no such column: Nmae`), two values where one is expected, a declaration of
two types for one parameter, a postcode rule on a department name, an unknown
record type, rules on a record write, and a `delete` without a `where`.

Nothing on the server reads `TestBounds`. It is carried in `TSqlRec` like
every other column and ignored there, which is what makes a generic test run
cost no server code at all.

With *über den Server ausführen* ticked, the same sweep goes through the
server instead, and the two lines that were always open close: a scoped
template **runs**, because the server binds the identity — `GetMeineRechnungen`
answers `sqlOk` there while the direct sweep can only report it as open. A
template the logged-in account may not use is reported as open with that
reason rather than red: a refusal by the mask is the correct answer, and a red
line for it would teach the reader to ignore red.

Writes are left out unless the sweep is told otherwise, and it asks once
before it starts — the server commits, so a sweep that writes is a sweep that
changes the database. A record write counts as a write here like any other: an
object in `TestBounds` goes out as one record's JSON through
`WriteRecordForAction`, and the server resolves the type and generates the
statement, so what is under test is the generator that will actually run.

Measured against `token strict`, 30 templates: as `user`, 15 run and 15 are
open — writes left out, `GetGehaelter` open because group 2 is not theirs; as
`admin` with writes allowed, all 30 run. The one finding in that run is
`OrmAddTDtoArtikelRow` on the second sweep in a row: its `TestBounds` names a
fixed `ArtNr`, and the unique index says so. A sweep that writes leaves rows
behind, which is the point of asking first.

### What an unset rights mask means

One flag, `StrictRights` in `DomSqlImplementation`, and nothing else:

- **false** — the default here — an unset mask lets the call through. That is
  what a proof of concept needs, and what every template written before these
  columns relies on.
- **true** — an unset mask refuses. The setting for a deployment that has
  finished stating its rules.

It is deliberately one flag rather than a default written per key. A permissive
gap then cannot hide in one forgotten row, and turning it strict is one line
rather than an audit. It is also the flip side named earlier: get that one line
wrong and every key is wrong at once.

**Every template in this file states one.** Two groups do the whole job: group
1 reads, group 2 writes. So a select carries `ReadGroups = 1`, an insert,
update or delete carries `WriteGroups = 2`, and the one query nobody but an
administrator should see — `GetGehaelter`, the salary list — carries
`ReadGroups = 2` instead. The two accounts fall out of that: `admin` is in both
groups both ways (3/3), `user` reads group 1 and writes nothing (1/0).

Which makes `strict` a sensible way to run the sample rather than a trap: with
every row stating its rule, an unset mask really does mean *somebody forgot*.

Measured with `token strict`: `user` reads `GetAllCustomers`, is refused
`GetGehaelter` and refused every write, by value list and by record alike;
`admin` is answered on all three. Without a token, all of them are
`sqlNeedsLogin`.

### Scoping a query to the caller

The rights mask answers *may you run this action*. It does not answer *which
rows do you get* — that lives in the parameters, and those come from the
client. A template `select … from Invoice where CustomerID = ?` lets any
caller who may run it pass **any** `CustomerID`, their own or someone else's.
In a trusted intranet that is fine; over the internet it is a data leak (the
one *hard* rule of the patterns Generic.Soa would otherwise break: *scope
every read to the caller*).

`CallerScope` closes it, in the shape a hardcoded method has for free. Set it
to `'userid'`, and the server binds `Caller.UserID` to the statement's **last**
`?` — a value the client never sends and cannot set:

```
ActionKey   = 'GetMeineRechnungen'
Sql         = 'select ID, Amount, InvoiceDate from Invoice where CustomerID = ? …'
CallerScope = 'userid'
```

The client sends **one value fewer** (here: none), and the server appends the
identity as the last bound value. A client that sends the full count is
refused with `sqlBadParams` — its value would land on the last `?` and the
scope would be lost, so this is a hard refusal, not a silent overwrite. The
count is `CountSqlParams(Sql) − 1`, checked in `TDomSqlTool.ApplyCallerScope`.

Measured against `demo.sqlite`, all through the domain layer with a test
caller: caller 2 gets invoices 4 and 5 (its own), caller 4 gets 7–9 (its own),
the same action key — and caller 2 sending `[3]` to force a foreign id is
refused. For contrast, the un-scoped `AmountDateCustomer4OfInvoice` lets
caller 2 read caller 3's rows: exactly what `CallerScope` prevents.

This is the parity proof: the generic approach scopes a read to the caller
just as a hand-written `GetMyInvoices` method would — the identity is server
set, only as a row in a column instead of a line of Pascal. The append variant
carries one `userid`; a composite scope (a second value, or a named position)
would be the same mechanism widened.

Where `Caller.UserID` comes from is the token, and without one a caller gets
`UserID` 0 — a scoped template then returns nothing at all, which is the right
default: empty beats someone else's. To try it out without a token, the server
takes a `caller=<id>` argument and hands every untokened caller that identity:

    ./soa_sql_templates_server demo caller=2

Measured over HTTP, with not one value sent by the client: `caller=2` returns
invoices 4 and 5, `caller=4` returns 7–9, `caller=3` returns 6, and no argument
returns nothing. A screw for trying it out, not authentication — it claims every
anonymous caller is that one user, and says so in brown at startup.

The editor cannot show this: its "Testen" runs the statement straight on the
connection, not through the domain layer. `CallerScope` does not apply there and
the last `?` carries whatever was typed. With a caller scope set the editor now
says so in front of the status message — a green run there proves nothing about
scoping.

### Who the caller is: the token

`AppCallerToken` is the only place in the server that reads the HTTP request,
and what leaves it is a `TSqlCaller` — user, name, and the two masks. What
fills that record is a payload:

```pascal
TAuthPayload = record
  UserID: integer;
  UserName: RawUtf8;
  Reads: Int64;
  Writes: Int64;
end;
```

The record lives in `src/common/SqlAuthTypes.pas`, so server, client and editor
mean the same thing by it. Two masks and not one: the templates have carried
`ReadGroups` and `WriteGroups` since masks existed, and a caller with one mask
for both could not express half of that. `CanExecute` asks whichever the
direction calls for.

The token itself is a **JWT**, signed and verified with HMAC-SHA256 by mORMot's
own `TJwtHS256` — signature, issuer and expiry are its business, and this unit
reads four claims out of what it accepts. Nothing here rolls its own crypto,
and nothing here checks an expiry by hand: a hand-written check that reads the
claim and forgets to compare it looks exactly like one that works.

The signing secret is a **GUID drawn at startup** and kept in memory. Nothing
to check in, nothing to leak from a configuration file — and every token dies
with the process, which is the crudest possible revocation and the only one a
sample needs. The auth service this sample belongs beside does the same, down
to the 300 minutes a token is good for.

### Logging in

`IAppAuthTool` is a second interface next to `IAppSqlTool`, because an
interface that runs queries should not also hand out identities:

```pascal
function Login(const UserName, Password: RawUtf8;
  out Token: TSessionToken): TSqlStatus;
function WhoAmI(out UserName: RawUtf8; out Reads, Writes: Int64;
  out SecondsLeft: integer): TSqlStatus;
```

`Login` is the one method that answers without a token, and it needs no
exception list to be reachable: the refusal lives in the domain layer, behind
the template registry, and a login never goes there. It is registered with
`optNoLogInput, optNoLogOutput`, so neither the password nor the token it
returns is ever written to a log.

An unknown user, a wrong password and a blocked account are **one answer**,
`sqlNeedsLogin`; the difference is only ever useful to somebody who is
guessing, and it goes to the server's log instead. A name that does not exist
also pays for a PBKDF2 round, so it cannot be told from a wrong password by a
stopwatch.

The accounts are in `bin/auth.sqlite`, its own file and shared by both
profiles: the target database hangs off the profile, the people do not. Two are
created on the first start — `admin` (both masks 3, so groups 1 and 2) and
`user` (reads group 1, writes nothing), password `demo` for both. Their
`UserID` is a customer of the demo database, which is what makes a scoped
template show something. No password is stored: a per-account salt from the
CSPRNG, PBKDF2-HMAC-SHA256 over it, the round count in the row next to it, and
a constant-time comparison of the digests.

Two switches turn the demo from *shows how rights would work* into *refuses
without them*, both off by default:

    ./soa_sql_templates_server token strict

`token` refuses a call without a usable token and prints the login command at
startup; `strict` makes an unset rights mask refuse instead of admit.

Measured over HTTP with `token strict`. `Login` as `admin` returns a JWT whose
payload reads `{"uid":2,"name":"admin","rd":3,"wr":3,"iss":"soa_sql_templates",
"exp":…}`; a wrong password and an unknown name both answer `sqlNeedsLogin`
with an empty token, and the log says which it was. `WhoAmI` answers
`admin, 3, 3, 18000` — five hours left. With the two tokens side by side:
`admin` reads `GetGehaelter` (`ReadGroups = 2`), `user` is refused
(`sqlNotAllowed`); on the scoped `GetMeineRechnungen` **the same template
returns different rows** — `user` (UserID 1) gets customer 1's three invoices,
`admin` (UserID 2) gets customer 2's two, and neither client sent a value. A
token with one character changed is refused, as is any token after a restart,
because the secret is gone with the process. Blocking `user` in `auth.sqlite`
ends their next login; clearing the flag lets them back in. No password appears
anywhere in the log.

Without the switches nothing of this applies: no token is demanded, the caller
is anonymous in group 1, and a template naming another mask still refuses.

### What the client does with it

`AppSqlClient` keeps the token in a variable of its own unit rather than in the
connection: this client connects and disconnects around every single call, and
the token has to outlive that. It goes in once per connect:

```pascal
Client.SessionHttpHeader := AuthorizationBearer(ClientToken);
```

That is mORMot's own place for *"your own header, e.g. a JWT as authentication
bearer"*, and from then on **every** call of that connection carries it without
a single call site knowing that it exists.

The window has an *Anmelden…* button that turns into *Abmelden*, and the login
state is in the title bar — name, masks and remaining minutes, from `WhoAmI`,
so from the server rather than guessed out of the token. When a call comes back
`sqlNeedsLogin`, the client asks once and repeats that same call: this is what
separating that status from `sqlNotAllowed` was for, because "log in" is
something a program can act on and "not yours" is not.

The login window is built at run time (`u_logindialog` in `src/ui`), without an
LFM: it is three controls, and a form file for that is more to keep in step
than to gain. The editor uses the same unit — two programs asking for the same
two fields, and no reason for two windows to drift apart. There it answers
*Server neu laden*, which asks once when the server says `sqlNeedsLogin` and
then repeats the call.

Reloading is administrative, and since a token can now say so, `CanReload`
demands a caller with a non-empty `Writes` mask: re-reading the set is how a
new template takes effect, which is closer to writing than to reading. Measured
with `token strict`: no token `sqlNeedsLogin`, `user` (writes nothing)
`sqlNotAllowed`, `admin` `sqlOk`.

### Testing through the server

The editor's own *Testen* runs the statement straight on its database
connection. That is what makes it useful on a draft — and it is why it cannot
answer half the questions this document is about: rights masks, `CallerScope`
and the rules all live in the domain layer, and that run goes past it.

The checkbox *über den Server ausführen* turns the run around: the same button
calls `GetJsonFromAction` or `WriteDataForAction` like any client, so the
answer that comes back is the real one, mask and scope and rules included. It
asks for a login when the server says `sqlNeedsLogin`, and repeats the call.

What it costs is the draft. The server runs registered templates and has no
method for anything else — giving it one would throw away the property this
whole sample exists to show — so an unsaved key answers `sqlUnknownKey`, and
the editor says *save first, then reload the server*.

One thing the mode states rather than hides: the server **commits**. The
rollback promise the editor makes everywhere else cannot hold on a call it
does not own, so a write asks once more before it goes.

A record write goes the same way, through the dialog it has always gone
through. *Record-Werte eingeben…* produces one record's JSON, and with the box
ticked that JSON is sent to `WriteRecordForAction` instead of executed here —
the type is resolved and the statement generated in the server, so the box for
the executed SQL stays empty. It is empty honestly: the statement was made
somewhere else, and showing a locally generated one would be showing a
different statement than the one that ran.

## Writing a whole record

Reading and writing are not symmetric in this sample, and the asymmetry is
worth naming rather than papering over.

Reading, the server produces JSON and the client decides what shape to read it
as. The type can live in the client alone, because the server never has to
name it. Writing a record, someone has to turn JSON back into typed values,
and that someone is the server — so there the type has to be **shared**. It
lives in `src/app/WriteDtos.pas`, next to the service contract — visible to
exactly whoever the contract is visible to.

And it is declared **once**. `TDtoCustomer` is read through `ParseDynArray`
and written through `WriteRecord`, the same three fields either way; two
declarations would be two names for one shape, with one of them going stale
unnoticed. Where the shapes genuinely differ they stay apart: the Invoice a
client reads carries the customer's name from the join, the one it writes
carries the `CustomerID`, so those are two records and always were.

What is *not* shared is any code. The server names none of these records:

```pascal
// client — one function for every record there will ever be
status := WriteRecord('OrmUpdateTDtoCustomer', cust, TypeInfo(TDtoCustomer));
```

```
-- templates.sqlite: the whole row. There is no statement.
ActionKey  = 'OrmUpdateTDtoCustomer'
Sql        = ''
RecordType = 'TDtoCustomer'
```

The server looks the type up by name through `Rtti.FindName`, loads the JSON
into it, walks its fields and puts the statement together:

```sql
update Customer set Name = ?, City = ? where ID = ?
```

Adding a record means adding it to `WriteDtos` and a row to `templates.sqlite`
— no method, no body, no converter, and no statement either. `SqlRecordBind`
is the whole mechanism and it is written once.

### A record that lives only in its row

`WriteDtos` is compiled by the server, so a record declared there costs a
rebuild. It does not have to: the `RecordDecl` column holds the same fields as
mORMot's textual RTTI, and the type is registered from that text the first
time a call needs it.

```
ActionKey  = 'OrmUpdateTDtoArtikelRow'
Sql        = ''
RecordType = 'TDtoArtikelRow'
RecordDecl = 'ArtNr: integer; ArtName: RawUtf8; Kind: RawUtf8'
KeyField   = 'ArtNr'
```

```sql
update Artikel set ArtName = ?, Kind = ? where ArtNr = ?
```

Measured over HTTP: that row alone — no Pascal anywhere naming the type —
inserts and updates, and the `currency` and `TDateTime` of a text-declared
record are bound as themselves, exactly as a compiled one is.

The shipped set has three of these to try, and no Pascal names any of their
types: `OrmAddTDtoProjektRow` for a table with no DTO at all, and the pair above,
`OrmAddTDtoArtikelRow` and `OrmUpdateTDtoArtikelRow`, which differ in one column —
the insert leaves `KeyField` empty, so `ArtNr` is written like any other
field, and the update names it, so it moves into the `where`. Measured: the
insert adds a row with a database-assigned `ID`, the update changes it, and an
update on an `ArtNr` that is not there answers `sqlNothingWritten` rather than
failing.

**A compiled type always wins.** `Rtti.FindName` is asked first, and only a
name this server registered from text is ever redefined. The alternative would
be a row silently reshaping a Pascal type the rest of the code relies on:
`Rtti.RegisterFromText` replaces the fields of an existing record type, so the
order of those two lookups is the whole safety property. Measured: a bogus
`RecordDecl` beside the compiled `TDtoCustomer` is ignored, and the insert
still names `Name` and `City`.

Editing a declaration does take effect, though — on the next reload the text
is compared against the one it was registered from, and only a changed one is
registered again. Measured: `'Name: RawUtf8'` generates an insert that fails
on the `not null` of `Customer.City`; after the row is widened to
`'Name: RawUtf8; City: RawUtf8'` and reloaded, the same key writes both.

A declaration that does not parse leaves nothing behind when the name is new,
but a *typo in an already registered one* is worse than it looks:
`Rtti.RegisterFromText` clears the fields before it parses, so the failure
leaves the type half defined — measured, a `RawUtf8` field it never reached
stays 8 bytes short, and the next call would find that half through
`Rtti.FindName` and read it as valid. So the text that last parsed is kept and
registered again when a new one fails; the damaged shape never outlives the
call that caused it.

What is *not* checked when a set is reloaded is whether `RecordDecl` parses:
that check needs the infrastructure layer, and the registry is in `dom`, which
must not see it. It sits in the editor instead — earlier than the server
anyway — and at run time a declaration that does not parse is one refused call
with the reason in the log, not a broken server.

### The conventions it rests on

Four, each one constant and one function, so they are one place to change
rather than a rule scattered about. The first two live in `SqlTemplateTypes`
and not in `SqlRecordBind`: the domain layer reads the same mark to decide
which call fits which key, and it must not see the unit that composes SQL:

| | |
|---|---|
| the mark | the action key starts with `Orm`, and nothing that is not one of these does |
| the verb | after the mark: `Add`/`Insert`, `Update`, `Retrieve`/`Get`, `List`/`Select` or `Delete` |
| the table | the record type without its `TDto` prefix and `Row` suffix — `TDtoCustomerRow` → `Customer`, `TDtoArtikel` → `Artikel` |
| the key | the column `KeyField` names, and `ID` when it names none: a generated insert leaves it to the database, a generated update puts it in the `where` |

The key column was `ID` and nothing else until `KeyField` was added. The
convention held in this sample and holds almost nowhere real: in a grown
database the
key is `Artikel_ID`, `Artikelname_ID`, `Adressen_ID`. Left empty the column
still means `ID`, so no existing row had to change.

A record without the key field can be inserted but not updated: a generated
update with no `where` clause would rewrite the whole table, so it is refused
rather than run. That is also how a natural key is written — leave `KeyField`
empty for the insert, and the field is bound like any other.

**This does not turn the service into "send me any SQL".** Every name in the
generated text comes from the record's own RTTI or from its type name. Nothing
from the caller reaches it, and the values are bound as before.

### Two verbs that send no record

`Retrieve` and `Delete` are not the mirror image of `Add` and `Update`, and
that is the interesting part. Nothing travels but the key:

```
OrmRetrieveTDtoCustomer + TDtoCustomer  ->  select ID, Name, City from Customer where ID = ?
OrmDeleteTDtoCustomer   + TDtoCustomer  ->  delete from Customer where ID = ?
```

Which columns to read is the record type's business, and the server knows the
type from the template — so a subset never has to be described by the caller.
That is what an ORM does too: `Retrieve` sends an ID and, for a subset, a list
of field names — never a record.

For the key column the difference goes one step further. An update takes its
key **out of the record**, so the record has to carry that field; a retrieve
and a delete take it from the caller, so `KeyField` may name a column the
record type does not have at all and the `where` clause still holds.

And because the one value is an ordinary bound value, these two need no new
call: a retrieve is `GetJsonFromAction` and a delete is `WriteDataForAction`,
the same two methods every hand-written statement uses. The service contract
did not change. What did change is one guard in the domain layer, which used
to refuse any key that names a record type on the value-list path — a
generated delete is exactly that and is now let through, by name.

### The list: many rows, filtered by the template

`OrmList…` is the retrieve for more than one row. mORMot's `RetrieveList` takes
its where clause from the **caller**; here it sits in the template, in the
`Filter` column, and the caller fills its `?` and nothing else:

```
OrmListTDtoCustomer + TDtoCustomer + Filter 'City = ?' + OrderBy 'Name'
  ->  select ID, Name, City from Customer where (City = ?) order by Name;
```

Which splits the roles where they belong: **the shape of the query is the
template's, the values are the caller's.** Nothing a client sends is ever read
as SQL, so the property this sample rests on is untouched - and the useful half
of the ORM is still there: the column list comes from the record type, and the
result loads into a `TDtoCustomerArray`.

The filter goes in **parenthesised**, which is not cosmetic. The domain layer
appends its own condition with `and` when `CallerScope` is set, and `and` binds
tighter than `or`: an unparenthesised `City = ? or Name = ?` would let half the
table past the scope. How many values such a template expects is known before
the statement exists - `ExpectedParamCount` counts the `?` of the filter the
way it otherwise counts those of the statement.

| | sends | returns | method |
|---|---|---|---|
| `OrmAdd…` / `OrmUpdate…` | the whole record | a status | `WriteRecordForAction` |
| `OrmRetrieve…` | the key | the row, into the same record type | `GetJsonFromAction` |
| `OrmList…` | the filter's values | the rows, as an array of that type | `GetJsonFromAction` |
| `OrmDelete…` | the key | a status | `WriteDataForAction` |

Measured, all four against `demo.sqlite`: insert, update, retrieve into a
`TDtoCustomer` (`ID 29 / Rekord GmbH / Drolshagen`), delete. A retrieve on a
key that is not there answers `sqlNoRows` and leaves the record untouched; a
delete on one answers `sqlNothingWritten`. Sending a record into a retrieve is
refused, and so is a record key without the `Orm` mark — *"takes a record but
does not start with ORM"* in the log.

### When the convention does not fit

A different table name, a composite key, an extra condition, an insert that
has to name its `ID` — then write the statement, with **named** placeholders:

```sql
update Customer set Name = :Name, City = :City where ID = :ID;
```

The server replaces each `:Name` by `?` and binds the field of that name.
Reordering the fields of the record cannot silently shift the values, a
placeholder may appear more than once, and expanding `:Name` to `?` is a
substitution inside a statement that was already registered.

The editor's *SQL ins Feld erzeugen* gives that statement its first draft: the
button writes the generated statement into the SQL box and unticks *generate
on arrival*. For a record with thirty fields that is the difference between
"this way out exists" and "this way out gets taken". What comes out is a draft to go on writing, not a finished sentence. For a
retrieve and a list it stops where the writing starts:

```sql
select ID, Name, City from Customer
```

The column list and the table come from the record type - the part nobody
wants to type - and the where clause is the part being written, so it is not
put there and does not have to be deleted again. Every `?` that ends up in it
gets a parameter, and then *Testen* runs it.

An insert and an update come out whole, in the `:Name` form rather than with
`?` - a written record statement carrying question marks is refused, because
nothing could say which field goes with which. A delete keeps its where
clause, and that is not an inconsistency: `delete from Customer` as a starting
point sits one keystroke away from an emptied table.

From then on the template carries its own statement and no longer follows the
record type - a field added to the record reaches a generated statement by
itself and this one not at all. The editor says so when handing it over,
rather than leaving it to be found out later.

`OrmUpdateCustomerRecord` in this sample is that longer way, next to the three
generated keys, so both are visible side by side.

**The types survive.** `TDtoInvoiceRow.InvoiceDate` is a real `TDateTime` and
`Amount` a real `currency`, and both are bound as such. This is the reason the
parameter travels as `RawUtf8` JSON and not as a variant: a `TDateTime` put
into a variant array arrives as a plain string and is bound as text — measured,
`["2026-08-30T14:30:00"]` comes out the other end as a string variant, exactly
the case *Why a parameter needs a declared type* is about. Loaded back into the
declared record it is a date again. Measured on the demo database:

```
10|6|1234.56|2026-08-31T14:30:00
```

So a record write needs no `ParamTypes` declaration at all — the record
already said what its fields are.

Calling the wrong method for a key is answered, not raised: a value list sent
to a record key and a record sent to a value-list key both come back
`sqlBadParams`.

What this does **not** do is replace the ORM. It covers the case the ORM
covers worst — a record whose fields are a subset of a table's columns, named
alike — without a `TOrm` descendant, a model or a table registration, and it
does it with the machinery that was already there.

## Outcomes are values, not exceptions

`TSqlStatus` (in `src/common`) replaces the boolean the two methods used to
return:

| value | meaning |
|---|---|
| `sqlOk` | rows returned, or at least one row written |
| `sqlEmptyKey` | the action key was empty |
| `sqlUnknownKey` | not registered on this server |
| `sqlNotAllowed` | the caller is known, and their mask does not meet the template's |
| `sqlNeedsLogin` | nobody is calling: no token, or one that is not valid |
| `sqlNoRows` | the select ran and matched nothing |
| `sqlNothingWritten` | the write ran and changed nothing |
| `sqlFailed` | the statement itself failed — reason in the server log |
| `sqlBadParams` | the values do not match what the template declares |

An unknown action key is an ordinary answer, not a catastrophe. Only wiring
mistakes still raise, so a normal run raises nothing and a debugger stops on
nothing.

A status has no room for a sentence, though, and the editor needs one: a
statement being drafted is wrong most of the time, and `sqlFailed` alone sends
its author guessing. So infra leaves the driver's words behind on the way out,
in `LastSqlError` - a threadvar, because one `TSqlTemplateExec` serves every
request of the server at once and a shared string would be a race. The
contract is untouched and the server never reads it. Without it the reason is
lost for everything that fails *after* a successful prepare - binding,
executing, converting - because mORMot leaves the connection's error message
set only when the prepare itself was refused.

The client makes the same choice for the connection: a server that is not
there raises in the socket layer and again in the service factory, neither
message naming the address that was tried. `ConnectClient` catches both and
returns false with the reason in `LastConnectError`.

## Measured against the recommended patterns

Against [mORMot2-SAD-Recommended-Patterns.md](https://github.com/synopse/mORMot2/blob/master/docs/mORMot2-SAD-Recommended-Patterns.md).
Part A is all but identical: `RawUtf8` over `string`, `variant` bounds,
`TSynDictionary`, `sicShared`, packed records, logging through `TSynLog`. The
departure is from part B, at one point from which everything else follows: the
variance lives in data instead of in Pascal interfaces. Using no ORM is not a
breach of A.5 — `ISqlTemplateExec` delivers substitutability and mockability
just the same, one level down.

Three points deserve an explicit answer, because otherwise they read as
omissions.

**The void model is the prescribed shape, not the absence of one.** A.6.2:
*"Void model => no TOrm classes => no ORM REST routes can exist at all"*, and
the document sets `TRestServerFullMemory.Create(EdgeModel)` as *"the public
edge with a void model, exposing only context-scoped services"* against
`TRestServerDB.Create(Model, 'data.db')` as *"the private system of record
owning business tables"*. This server is that edge, and is built without a
`TOrmModel` for that reason — not because one was forgotten.

The second tier is missing, though, and deliberately so: what would be a
`TRestServerDB` with ORM tables there is `TSqlDBConnectionProperties` and the
templates here. The same job, a different answer, at the price stated under
"What is given up". Tick the pattern off literally and you find a missing half
where a replaced one stands.

**"Scope every read to the caller" is demonstrated, not met.** The rule is
stated as a cross-cutting one — a logged-in end user must retrieve only their
own rows, filtered at the service boundary — and `ApplyCallerScope` sits
exactly there. Every one of this file's 30 templates now states a rights mask,
so `strict` is a usable way to run it; but **one** of them uses `CallerScope`.
The mask answers *may you run this*, the scope answers *which rows do you get*,
and only the first is stated everywhere. As a parity proof — the mechanism can
do both, see "Scoping a query to the caller" — that holds. As a statement about
this template file, the second half would be false.

**Authentication is there, behind a switch.** A.6.1 asks for *"Authentication:
enable it explicitly (JWT / mORMot auth)"*, leaving the choice between the two
open. Started as `token`, this sample takes the JWT road: a login against its
own account file, a signed token, and every later call refused without one.
What it does not do is demand it by default — see *Deliberately left out*.

## Deliberately left out

**A verified token.** There is a token, and it is read: the payload, the
groups, the identity, an expiry that is honoured — see *Who the caller is*.
What there is not is a signature, so the payload is only as trustworthy as the
port it arrived on. `VerifyToken` is where that is added, and nothing else
changes when it is.

And what runs by default is not worth dressing up: `RequireToken` is `false`,
so every call without a token goes through. `AnonymousReads` and
`AnonymousWrites` put it in group 1, `AnonymousUserID` (0 as shipped, settable with `caller=<id>`) becomes
its identity, and `StrictRights = false` admits every template that states no
mask. A caller here gets everything except what explicitly names another group.
Started as `token strict`, none of that is so — which is the point of having
the two switches rather than a paragraph promising it would work.

Turning on mORMot's own sessions would fill `UserID` and `Groups` by itself —
`CurrentCaller` already reads them, and nothing in this layer would change. It
carries only **one** group per user, though (`User.GroupRights.ID`). For a model
with separate read and write rights per service, a JWT carrying a list of groups
is the better fit.

**Sanity rules at run time.** Counting the `?` in a statement against the
number of bounds, requiring a `where` in every update and delete. The server
does not do this, because these are cheaper to check when a template is
written than on every request - which is where they now live, behind the
editor's "Prüfen" button. Value ranges per key would still belong on the
server, and would be a field on `TSqlRec`.

**Server-generated field values.** A record arrives with its fields and is
written as it stands. There is no point between "the record has arrived" and
"the statement runs" at which the server could fill a field in itself. Some
schemas want exactly that: a key handed out by the process rather than by the
database, a created-at stamp that must not come from the client, a tenant id
taken from the caller instead of sent along with the rest.

The shape it would take is already here. `CallerScope` does this for a bound
parameter - the client sends one value less and the domain layer supplies it -
and `ApplyCallerScope` is the one place that happens. A `Generator` column
beside it, naming the field and where its value comes from, would be the same
move for a record field, and would be read by the same layer. Left out because
the records in this sample do not need it, not because it does not fit.

**Tests.** Left out on purpose so the comparison stays honest: no test code is
counted on either side.

## Known limitations

`demo.sqlite` stays locked while the server runs — mORMot's statically linked
SQLite holds the file, and setting `LockingMode := lmNormal` does not release
it. Stop the server, or copy the file, to look inside. `templates.sqlite` does
not have this problem: it is opened to be read and closed again, so it can be
edited in a viewer while the server runs.

The editor can now test a record template too, and it does it without
breaking the rule that this tool never commits. *Record-Werte eingeben…*
resolves the record type the way the server resolves it, builds a dialog from
whatever fields that turns out to have — one row per field, with the type it
will be bound as beside it — and hands back the JSON a client would send. That
JSON goes through `BindRecordJson` and into the same rolled-back transaction
every other write test uses. What runs is the server's path, not a second one
written for the editor: the log shows the record, the generated statement and
the outcome.

Numbers go in unquoted and strings quoted, decided per field from its parser
type, which is what makes the test worth anything — a record whose integer
arrived as text would bind differently from the real call. A value that does
not fit its field reopens the dialog with everything still typed in.

An **update** starts from the row it is about to overwrite. The editor asks
for the key, fetches that row and opens the dialog on it, so what is edited is
what is there. The statement it fetches with is not a second rule: it is the
retrieve branch of the same generator, asked for by name — `RetrieveSqlFor`
ignores the template's own verb and composes a select over the same record
type and the same key column. An `OrmUpdateTDtoArtikelRow` is therefore looked
up by `where ArtNr = ?`, exactly the column its update matches on. Left empty,
the key prompt opens the dialog on defaults; a key that matches nothing stops
with that as the reason, rather than showing a form that pretends to hold a
row. An insert is not asked for a key at all.

Measured: `OrmUpdateTDtoCustomer` on `ID` 2 loads
`{"ID":2,"Name":"Ostwald Holzbearbeitung","City":"Detmold"}`, the edited
record goes back through the generated update — and afterwards the row in
`demo.sqlite` is unchanged, because the transaction was rolled back.

What was typed survives twice over. The dialog remembers the record per action
key for the session and opens on it next time rather than on empty fields —
for an update only when no row came from the database. And the JSON then
stands in the *what would travel* box: for a record template that object is
exactly what a client sends, and *JSON als TestBounds* puts it into the column
in one press, where the sweep and the run through the server pick it up again.

It does not go into the parameter list, and that is deliberate. The generated
write carries `:Names`, not question marks; the server fills those from the
record, and a record template with `?` is refused by the domain layer. Values
in a list this run never reads would be a field that promises something it
does not keep.

That says where the values come from, not that such a template cannot be
tested. *Testen* therefore looks for the record where the window shows it: the
*what would travel* box first, then the last record entered in the dialog for
this key, then the `TestBounds` column. What it finds takes the same road the
dialog takes — through the server with the box ticked, over the editor's own
connection without. An array in any of the three does not count: a record
write has no positional parameters, and taking a value list for one would be
exactly the confusion this ends.

Since the editor links `WriteDtos`, this works for the types compiled into the
server as well as for the ones a `RecordDecl` column declares. The two verbs
that send no record are refused here by name, and say why: their key is an
ordinary test value, entered where all the other bound values are.

`SeedTemplateDb` no longer seeds anything from Pascal - it only rebuilds a
*missing* `templates.sqlite` from the `.sql` export. A file that exists is
never touched, so new templates are added in the editor or inserted as rows.

The templates are a startup dependency. A broken set means the service does
not start - there is no compiled fallback any more, on purpose. What softens
it: a *missing* `templates.sqlite` is rebuilt from `templates.sql` next to it,
and a bad set offered to a *running* server is refused, leaving it on the one
it already had. Only a broken file at startup is fatal, and then loudly.

One process per target database. Two profiles may run side by side - they have
their own ports and their own databases - but a second server on the same
SQLite *target* file fails at startup, and reports the header-not-a-database
error described above. It now says what that usually means instead of aborting
with the driver's wording alone. The templates file is not affected - it is
read and closed again, see above - and against SQL Server the case does not
arise at all: a second process on the same database is the normal thing there.
