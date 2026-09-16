# Server and test client — how to use them

A short guide to `soa_sql_templates_server` and `soa_sql_templates_client`
together. The reasoning is in [DETAILS.md](DETAILS.md), the editor in
[EDITOR.md](EDITOR.md). The client's window is German, so its labels are quoted
as they appear.

---

## Building

```bash
D=<fpcupdeluxe-installation>   # the folder holding lazarus/ and config_lazarus/
$D/lazarus/lazbuild --pcp=$D/config_lazarus src/proj/soa_sql_templates_server.lpi
$D/lazarus/lazbuild --pcp=$D/config_lazarus src/projclientlaz/soa_sql_templates_client.lpi
```

The programs land in `bin/`.

---

## Starting the server

```bash
cd bin
./soa_sql_templates_server                 # profile demo   on port 8890
./soa_sql_templates_server mssql          # profile mssql on port 8891
./soa_sql_templates_server token strict    # with login and rights masks
./soa_sql_templates_server caller=2        # every untokened caller is UserID 2
```

The switches combine and may stand in any order after the profile. Stop it with
**Enter** in the same window — do not send it to the background, or its
messages go unseen.

| Switch | Effect |
|---|---|
| *(none)* | open operation: every caller counts as group 1, no token needed |
| `token` | without a valid bearer token every call is refused with `sqlNeedsLogin` |
| `strict` | a template with no rights mask set answers `sqlNotAllowed` |
| `caller=N` | untokened callers are given UserID `N` — to watch caller scoping without logging in |

On startup it reports the port, the templates file, how many actions and their
names, the profile, the database and the path of its log file (`bin/*.log`).

| Profile | Port | Templates | Database |
|---|---|---|---|
| `demo` | 8890 | `bin/templates.sqlite` | `bin/demo.sqlite` |
| `mssql` | 8891 | `bin/templates_mssql.sqlite` | a SQL Server database over ODBC (needs a route there and a login) |

`templates_mssql_schema.sql` beside it creates the four tables that profile's
templates read, with a few made-up rows — nothing in the project creates them,
so the profile has something to run against. Point `SQLSERVER_HOST` in
`src/commonserv/SqlServerConn.pas` at your own server and `TargetDatabase` in
`src/common/SqlProfiles.pas` at your own database first; both carry a
placeholder.

Both profiles can run at the same time — their own port, their own database.

---

## Using the test client

1. Run `bin/soa_sql_templates_client`.
2. Pick the **Profil**; **Server** is filled in from it (`localhost:8890`).
3. **Aktionen vom Server holen** — the **Aktion** list fills with what the
   server knows.
4. Pick an **Aktion**.
5. Enter the **Bounds**: the parameters as a JSON array, e.g. `["Wegberg"]` or
   `[2]`. Leave it empty when there are none.
6. **Aktion ausführen**.
7. **Ansicht** switches between **Tabelle** and **JSON**; the messages are
   below.

Two details:

* A template with a **caller scope** takes one value **less** — the server
  binds the identity.
* **Typisierter Test (demo)** runs a fixed sequence of typed calls against the
  `demo` profile and writes the outcome to the log. It writes rows too, so it
  belongs on a test database only.

---

## Logging in

With the server started as `token`, everything answers `sqlNeedsLogin` until
the client has logged in.

1. Press **Anmelden…**.
2. Enter user and password — the demo accounts:

   | Account | Password | Reads | Writes |
   |---|---|---|---|
   | `admin` | `demo` | groups 1 and 2 | groups 1 and 2 |
   | `user` | `demo` | group 1 | — |

3. The title bar then shows the user and how long the token still has (300
   minutes).
4. The same button now reads **Abmelden**.

The token travels in the `Authorization` header on every call. It dies with the
server process, so log in again after a server restart.

Without the client, the same with `curl`:

```bash
curl -s -X POST http://localhost:8890/sqltemplates/AppAuthTool.Login -d '["admin","demo",""]'
```

The answer carries the token, and with it:

```bash
curl -s -X POST http://localhost:8890/sqltemplates/AppSqlTool.GetJsonFromAction -H "Authorization: Bearer <token>" -d '["GetGehaelter",[],""]'
```

---

## What the status values mean

| Value | Means |
|---|---|
| `sqlOk` | it ran |
| `sqlNoRows` | it ran and found nothing — not an error |
| `sqlNothingWritten` | it ran and matched no row |
| `sqlUnknownKey` | the server does not know this action key |
| `sqlBadParams` | the count, a type or a rule does not fit |
| `sqlNotAllowed` | logged in, but the rights mask does not match |
| `sqlNeedsLogin` | no token, or none that verifies |
| `sqlFailed` | the database refused — the reason is in the server log |

---

## Putting a new template into service

1. Create it in the **editor**, test it, **Speichern**.
2. Press **Server neu laden** there — or restart the server.
3. In the client, **Aktionen vom Server holen**; the new key is in the list.

The server does not accept a broken set and keeps the one it had. Only a broken
file **at startup** is fatal — then it says so and does not come up.

---

## When something does not work

| What you see | Cause |
|---|---|
| the client says there is no server | it is not running, wrong port, or profile and port do not match |
| everything answers `sqlNeedsLogin` | the server runs with `token` — log in, and again after a server restart |
| everything answers `sqlNotAllowed` | the server runs with `strict` and the template has no mask, or the account does not match it |
| a new key is unknown | saved in the editor, but *Server neu laden* was not pressed |
| profile `mssql` hangs | no route to the server (VPN, tunnel), or the Kerberos ticket expired (`kinit`) |
| the server does not start | the templates file is missing or broken — the console names the reason |
