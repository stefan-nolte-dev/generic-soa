# The template editor — how to use it

A short guide to `soa_sql_templates_editor`. Why the fields are what they are
is in [DETAILS.md](DETAILS.md); this is the handling only. The labels below are
quoted as they appear in the window.

The editor is a developer tool: it edits `templates.sqlite`, runs statements on
a database it connects to **itself**, and writes the record declaration that
receives the result. It does not belong next to the client on a user's machine,
and it belongs on a development database.

---

## Start and connect

1. Run `bin/soa_sql_templates_editor`.
2. Pick the **Profile** (`demo` or `mssql`). That sets the target and the
   templates file together — never change them separately, they belong to each
   other.
3. Press **Connect**. The title bar then shows the connection.
4. Press **Load list**. The action keys appear on the left.

Without a connection everything works except *Test* and the running half of
*Check all*.

| Field on top | Meaning |
|---|---|
| **DB** | driver: SQLite, or an ODBC connection string |
| **Target** | file name (SQLite) or the full ODBC connection string |
| **User / Passwort** | ODBC only; leave empty for Kerberos |
| **Templates** | the `.sqlite` holding the templates |
| **Search** (bottom left) | filters the key list while you type |

---

## Adding a query

1. Press **New**.
2. Enter the **Action key**, e.g. `GetKundenByCity`.
3. Type the **SQL**, one `?` per parameter:
   `select ID, Name from Kunde where City = ?`
4. Fill in **Parameters**: pick the kind (`text`, `int`, `date` …), type the
   value, press **Add**. One per `?`, in the statement's order.
5. **Types** fills itself as you go; otherwise press
   **Take from parameters**.
6. Set **Rights read/write** (a bitmask per group, `1` = group 1). `0`
   means "no rule" and is refused by a server started with `strict`.
7. **Check** — reports everything that can be told without a database.
8. **Test** — runs it; a write is rolled back while **Rollback** is ticked.
9. **Save**. Then **Reload server**, or a running server will not know
   the key.

Looking at the result: tab **Table** (rows), **JSON** (what goes out),
**Messages** (the log), **Type** (generate the record declaration).

---

## Adding a record template (add/update)

The action key decides the kind. It reads `Orm<Record-Typ><Verb>[Name]`: the
record type spelled out in full, then `Add`, `Update`, `Retrieve` or `Delete`,
then a name of your own if one type needs more than one key of that verb —
`OrmTDtoKundeAdd`, `OrmTDtoKundeRetrieveByCity`. The line under the SQL box
shows which kind the key reads as, and the statement the server will build.

1. **New**, **Action key** `OrmTDtoKundeAdd`, **Record type** `TDtoKunde`.
2. Fill in **Record fields** unless the type is compiled into the server (one
   field per line, as in Pascal).
3. Set **Key** if the key column is not `ID` — update and delete use it.
4. Set **Table** if the table is not the record type's name without `TDto`
   and `Row` — e.g. a record of two fields writing into `Customer` is a
   partial update. There is nothing to write in the SQL box: an Orm key's
   statement is always generated, and the line under the box shows it.
5. **Enter record values…** opens a form built from the type's fields. After
   *OK* the write runs at once — rolled back if the box is ticked.
6. **Save**, **Reload server**.

About the record dialog:

* For an **update** the key value is asked for first, that row is fetched and
  the form opens on it. Left empty, it opens on defaults.
* The JSON entered then stands in **sent as JSON** and is remembered per
  key, so the form opens on it next time.
* For a record write, **Test** uses exactly that JSON (in this order: the
  *sent as JSON* box, then the last entry in the dialog, then the
  *TestBounds* column). The **parameter list** is never read for it — a
  record's values come from the record.
* An **add** answers with the row the database stored — the key it gave and
  every default it filled. It stands in the **Table** tab, rolled back or
  not, and a client gets the same row back through `AddRecord`.

---

## Adding a retrieve

A retrieve is a where clause and an order, nothing else: the select around
them always comes from the record type.

1. **New**, **Action key** `OrmTDtoKundeRetrieveByCity`, **Record type**
   `TDtoKunde`. As soon as key and type agree, the label of the big box turns
   into **where:**.
2. Write the where clause into the box, without the word `where`:
   `City = ?`. Empty means every row; one row by its key is `ID = ?`.
3. **order by** (below) takes the order, e.g. `Name`.
4. The line under the box shows the statement the server will run.
5. One entry under **Parameters** per `?`, then **Test**. The answer is always an array.

**Types** and **TestBounds** follow the where while you type it: an entry per
`?`, kept where it was, a missing type as `text`, a missing test value as
`null`. The line under the box points at a `null` until it is replaced, and
**Save** asks before storing test values that do not fit — *Check all*
runs every saved entry with its own values, so they have to be its values.

A select that needs a join or columns the record does not carry is not a
retrieve: write it as an ordinary query, with a key without `Orm`.
A delete (`Orm…Delete`) has nothing to write at all — it goes by the key.

---

## Rules, caller scope, TestBounds

| Field | Example | Effect |
|---|---|---|
| **Rules** | `1:notempty;2:plz;3:email` | checks parameters *before* the statement; available: `notempty`, `plz`, `email`, `len:min:max`, `range:min:max`, `oneof:a:b` |
| **Caller-Scope** | `userid` | the **last** `?` is bound by the server with the caller's own id; the client sends no value for it |
| **order by** | `Name` | for `Orm…Retrieve…` only: the order; the `where` stands in the big box |
| **TestBounds** | `["Wegberg"]` or `{"ID":1,…}` | test values for *Check all*; an array is a value list, an object is a record |

**JSON as TestBounds** copies whatever stands in *sent as JSON* into the
column. Then **Save**.

---

## Checking the whole set

**Check all** walks every template:

* Without a connection: the checks only, nothing runs.
* With one: templates carrying **TestBounds** run as well, always in a
  transaction that is rolled back — whatever the Rollback box says.
* Per line: `ok`, `open` (checked, not run — with the reason) or `ERROR`,
  plus one summary line.

---

## Going through the server

The box **run through the server (with login)** at the bottom:

* **Test** and **Check all** then call the server the way a client would —
  with the rights mask, the caller scope and the rules.
* Only **saved** keys can go: the server runs registered templates and has no
  method for anything else. A draft answers `sqlUnknownKey` — *Save*
  first, then *Reload server*.
* The server **rolls nothing back**. A write is therefore confirmed first; for
  *Check all*, once for the whole run.
* If the server demands a token, the login window appears (demo accounts:
  `admin` and `user`, password `demo`).
* **Server** is the field beside it, `localhost:8890` by default.

---

## What each button does

| Button | Does |
|---|---|
| **Check** | everything without a database: declaration, parameter count, record type, rules, whether the server would accept the set |
| **Test** | runs it — directly or through the server, depending on the box |
| **Save** | writes the template to the file and exports `templates.sql` beside it |
| **Check all** | the same check over every template |
| **Reload server** | the server re-reads its templates |
| **Generate CREATE TABLE** | describes the table the record type needs, in the dialect of the drop-down beside it — the result goes to the log and the clipboard. It only composes, it runs nothing, and it needs no connection: this is for the schema you hand to somebody who has the rights on the target server |
| **New / Delete** | add or remove a template |
| **Type from result** | builds a record declaration from the last result (tab *Type*) |
| **Cross-check** | puts the values into the text instead of binding them — to look at only, nothing runs that way in production |

---

## When something does not work

| Message | Cause |
|---|---|
| `sqlUnknownKey` through the server | not saved, or the server was not reloaded |
| `sqlNotAllowed` | the template's mask does not match the account logged in |
| `sqlNeedsLogin` | the server runs with `token` and nobody logged in |
| `NOT NULL constraint failed` | a `?` stayed unbound: a parameter is missing |
| "CallerScope: der Editor bindet keine Identität" | not runnable directly — test it through the server |
| the editor hangs on connect | ODBC without the tunnel, or without a Kerberos ticket |
