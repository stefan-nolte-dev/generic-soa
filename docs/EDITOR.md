# The template editor — how to use it

A short guide to `soa_sql_templates_editor`. Why the fields are what they are
is in [DETAILS.md](DETAILS.md); this is the handling only. The window itself is
German, so the labels below are quoted as they appear.

The editor is a developer tool: it edits `templates.sqlite`, runs statements on
a database it connects to **itself**, and writes the record declaration that
receives the result. It does not belong next to the client on a user's machine,
and it belongs on a development database.

---

## Start and connect

1. Run `bin/soa_sql_templates_editor`.
2. Pick the **Profil** (`demo` or `mssql`). That sets the target and the
   templates file together — never change them separately, they belong to each
   other.
3. Press **Verbinden**. The title bar then shows the connection.
4. Press **Liste laden**. The action keys appear on the left.

Without a connection everything works except *Testen* and the running half of
*Alle prüfen*.

| Field on top | Meaning |
|---|---|
| **DB** | driver: SQLite, or an ODBC connection string |
| **Ziel** | file name (SQLite) or the full ODBC connection string |
| **User / Passwort** | ODBC only; leave empty for Kerberos |
| **Templates** | the `.sqlite` holding the templates |
| **Suche** (bottom left) | filters the key list while you type |

---

## Adding a query

1. Press **Neu**.
2. Enter the **Action-Key**, e.g. `GetKundenByCity`.
3. Type the **SQL**, one `?` per parameter:
   `select ID, Name from Kunde where City = ?`
4. Add the **Parameter**: pick the kind (`text`, `int`, `date` …), type the
   value, press **Hinzufügen**. One per `?`, in the statement's order.
5. **Typen** fills itself as you go; otherwise press
   **aus Parametern übernehmen**.
6. Set **Rechte lesen/schreiben** (a bitmask per group, `1` = group 1). `0`
   means "no rule" and is refused by a server started with `strict`.
7. **Prüfen** — reports everything that can be told without a database.
8. **Testen** — runs it; a write is rolled back while **Rollback** is ticked.
9. **Speichern**. Then **Server neu laden**, or a running server will not know
   the key.

Looking at the result: tab **Tabelle** (rows), **JSON** (what goes out),
**Meldungen** (the log), **Typ** (generate the record declaration).

---

## Adding a record template (add/update)

The action key decides the kind: `OrmAdd…`, `OrmUpdate…`, `OrmRetrieve…`,
`OrmList…`, `OrmDelete…`.

1. **Neu**, **Action-Key** `OrmAddTDtoKunde`, **Record-Typ** `TDtoKunde`.
2. Fill in **Record-Felder** unless the type is compiled into the server (one
   field per line, as in Pascal).
3. Set **Schlüssel** (e.g. `ID`) — update, retrieve and delete need it.
4. Either tick **SQL beim Aufruf erzeugen** (no statement of its own) or press
   **SQL ins Feld erzeugen** and edit the draft.
5. **Record-Werte eingeben…** opens a form built from the type's fields. After
   *OK* the write runs at once — rolled back if the box is ticked.
6. **Speichern**, **Server neu laden**.

About the record dialog:

* For an **update** the key value is asked for first, that row is fetched and
  the form opens on it. Left empty, it opens on defaults.
* The JSON entered then stands in **geht als JSON raus** and is remembered per
  key, so the form opens on it next time.
* For a record write, **Testen** uses exactly that JSON (in this order: the
  *geht als JSON raus* box, then the last entry in the dialog, then the
  *TestBounds* column). The **parameter list** is never read for it — a
  record's values come from the record.

---

## Rules, caller scope, TestBounds

| Field | Example | Effect |
|---|---|---|
| **Regeln** | `1:notempty;2:plz;3:email` | checks parameters *before* the statement; available: `notempty`, `plz`, `email`, `len:min:max`, `range:min:max`, `oneof:a:b` |
| **Caller-Scope** | `userid` | the **last** `?` is bound by the server with the caller's own id; the client sends no value for it |
| **Filter / Sortierung** | `City = ?` / `Name` | for `OrmList…` only: the `where` and the `order by` |
| **TestBounds** | `["Wegberg"]` or `{"ID":1,…}` | test values for *Alle prüfen*; an array is a value list, an object is a record |

**JSON als TestBounds** copies whatever stands in *geht als JSON raus* into the
column. Then **Speichern**.

---

## Checking the whole set

**Alle prüfen** walks every template:

* Without a connection: the checks only, nothing runs.
* With one: templates carrying **TestBounds** run as well, always in a
  transaction that is rolled back — whatever the Rollback box says.
* Per line: `ok`, `offen` (checked, not run — with the reason) or `FEHLER`,
  plus one summary line.

---

## Going through the server

The box **über den Server ausführen (mit Anmeldung)** at the bottom:

* **Testen** and **Alle prüfen** then call the server the way a client would —
  with the rights mask, the caller scope and the rules.
* Only **saved** keys can go: the server runs registered templates and has no
  method for anything else. A draft answers `sqlUnknownKey` — *Speichern*
  first, then *Server neu laden*.
* The server **rolls nothing back**. A write is therefore confirmed first; for
  *Alle prüfen*, once for the whole run.
* If the server demands a token, the login window appears (demo accounts:
  `admin` and `user`, password `demo`).
* **Server** is the field beside it, `localhost:8890` by default.

---

## What each button does

| Button | Does |
|---|---|
| **Prüfen** | everything without a database: declaration, parameter count, record type, rules, whether the server would accept the set |
| **Testen** | runs it — directly or through the server, depending on the box |
| **Speichern** | writes the template to the file and exports `templates.sql` beside it |
| **Alle prüfen** | the same check over every template |
| **Server neu laden** | the server re-reads its templates |
| **Create-Table-SQL erzeugen** | describes the table the record type needs, in the dialect of the drop-down beside it — the result goes to the log and the clipboard. It only composes, it runs nothing, and it needs no connection: this is for the schema you hand to somebody who has the rights on the target server |
| **Neu / Löschen** | add or remove a template |
| **Typ aus Ergebnis erzeugen** | builds a record declaration from the last result (tab *Typ*) |
| **Gegenprobe** | puts the values into the text instead of binding them — to look at only, nothing runs that way in production |

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
