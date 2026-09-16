# Based on mORMot 2. A kind of generic SOA service.

No query-specific code is needed on the server to run a query. Only for the ORM-like operations is code for a DTO type needed, naturally. That code handles every DTO regardless of its type. Rights management, sanity rules and generic tests use general code as well.
<br><br>On the client side a convenience DTO type can be declared (generated at the press of a button in the editor, see below). All that is then needed is to declare a variable and pass it (plus TypeInfo(...)). Parsing happens automatically, independent of the type.

*The long version — the full measurement, the editor in detail, the known limitations: [docs/DETAILS.md](docs/DETAILS.md) — auf Deutsch: [README-de.md](README-de.md).*

*Handling, step by step: [docs/EDITOR.md](docs/EDITOR.md) for the template
editor, [docs/SERVER-CLIENT.md](docs/SERVER-CLIENT.md) for the server together
with the test client.*

## Building

**mORMot 2 — pinned to the `2.4-stable` tag.** mORMot changes almost daily, and some of those changes break the API. So that the project builds the same way for everyone, a fixed version is named here rather than a branch:

```bash
git clone --branch 2.4-stable --depth 1 https://github.com/synopse/mORMot2.git
```

Not `master`, which moves under your feet. And not `lts-2.3`: that branch was cut before changes this project relies on — `RecordLoadJsonInPlace`, for one, does not exist there.

**The static libraries** — the precompiled `.o` files for SQLite3 and the other C parts — are not in the mORMot repository, `static/*/` is ignored there. They belong to the version and have to match it. That is what `static/dev.sha256` in the checkout is for: the checksums of exactly the archives that go with this revision.

Do not take the archive from `https://synopse.info/files/mormot2static.7z` — that is always the latest state, not the one belonging to the tag. Instead open the `2.4-stable` release under https://github.com/synopse/mORMot2/releases and take the archive attached there: `mormot2static.tgz` on Linux and macOS (smaller and more native), `mormot2static.7z` on Windows. Put the archive into `static/`, verify it, unpack it:

```bash
cd <mORMot2>/static
sha256sum -c dev.sha256 --ignore-missing
tar xf mormot2static.tgz        # Windows: 7z x mormot2static.7z
```

The check must report `OK`. If it reports `FAILED`, the archive belongs to a different version and came from the wrong place. After unpacking there is `static/aarch64-linux/` and the other target directories; the Lazarus package looks for them there by itself.

**Toolchain.** Verified with Lazarus 4.9 and FPC 3.3.1 on aarch64-linux. The same three programs also build and run on Windows 11 ARM, Windows 10 (x64), Ubuntu ARM and MX Linux (x64, built on Debian) — each with FPC 3.3.1 and Lazarus from trunk, each with server, client and editor, including logging in against `token strict` and the editor on a database. The compiler is the second moving dependency: on the 2.3 LTS revision, `mormot.lib.pkcs11` fails in the assembler with this FPC — a code generation bug on aarch64, not one of mORMot's. With the tag above it does not occur.

**The build itself.** Register the mORMot package once, then the three projects:

```bash
lazbuild --add-package-link <mORMot2>/packages/lazarus/mormot2.lpk
lazbuild src/proj/soa_sql_templates_server.lpi
lazbuild src/projeditor/soa_sql_templates_editor.lpi
lazbuild src/projclientlaz/soa_sql_templates_client.lpi
```

The `lazbuild` help prints that option with an equals sign, but it is only accepted with a space in front of the file. In the IDE it is enough to open `mormot2.lpk` once and compile it; the three projects then pull the package in as a dependency. The binaries land in `bin/`.

**The demo database.** `bin/demo.sqlite` is not under version control. The server creates it on first start — `CreateDemoDatabase` and `CreateBulkDemoTables` in `src/serv/app/ServSqlTemplates.pas`; starting it once is enough, and no further tool is needed for that. That holds for starting it from the IDE without parameters as well. On Linux, Lazarus shows a console program's output in `xterm`: if that package is missing, no window appears even though the server is running — then `sudo apt install xterm`, name another terminal program in the IDE's environment options, or simply start the server from a shell. To get exactly the written-out state instead, apply `bin/demo.sql`:

```bash
cd bin
sqlite3 demo.sqlite < demo.sql
```

That is the only thing `sqlite3` has to be installed for (Debian/Ubuntu: `sudo apt install sqlite3`). Without the command line tool, Python does the job just as well, as it ships with SQLite:

```bash
cd bin
python3 -c "import sqlite3,io; sqlite3.connect('demo.sqlite').executescript(io.open('demo.sql',encoding='utf-8').read())"
```

SQLite as a system library, on the other hand, is needed nowhere: the programs link it in statically through `mormot.db.raw.sqlite3.static`, from the static libraries above.

## Idea
Instead of implementing queries in code, information about the queries is simply stored in a small SQLite database. One table per service could be maintained. For adding, editing, testing and so on there is an editor, see below.<br><br>
The table holds these columns: <br>
1. ActionKey | key<br>
2. Sql | SQL template (not needed for updating and adding whole DTOs)<br>
3. ParamTypes | needed for generic tests<br>
4. RecordType | for RTTI in the ORM-like operations <br>
5. RecordDecl | the fields of that record as text, when the type is not compiled into the server<br>
6. KeyField | the key column of a generated statement. Empty means ID<br>
7. ReadGroups | rights as an integer <br>
8. WriteGroups | rights as an integer<br>
9. Rules | named sanity checks, assigned per parameter position - `2:plz;3:email`. Per field name is still open.<br>
10. TestBounds | sample values for a generic test run - `["Wegberg"]`, or the record's own JSON. The expected result shape is still open.<br>
11. CallerScope | `userid`: the server binds the last parameter itself, with the caller's own id; the client sends no value for it<br>
... etc ...<br><br>
At run time the entries are loaded into a TSynDictionary, for faster processing. The entries are passed to the existing methods as parameters where needed. There is no code for specific queries, only for the general logic. Thanks to mORMot the whole logic takes relatively few lines.
# Server


## Three layers: App, Dom, Infra.
The layers compile independently of one another. A change in the implementation of one layer does not affect the others.
## App
App does the HTTP work: receiving and sending data, and extracting the payload of the HTTP header token. Forwarding to Dom through an interface that belongs to Dom.
## Dom
The rights check happens here (logged in, and the specific rights), and the reading of the dictionary that holds the table from templates.sqlite. The value behind the action key is loaded into a TSqlRec. That TSqlRec holds the values of the selected row.
## Infra
Here, for an ORM-like add or update of a whole DTO, the statement is generated with all the values and types it needs. For SQL, the statement from the TSqlRec is executed.
# Client
A simple test client. Demonstrates the call and the parsing on the client side.
# Editor
New entries can be made here, and existing ones edited. Implemented so far: connecting to a database, testing SQL, showing the result as JSON or as a table. Generating a matching Pascal TDTO from the JSON result array. That declaration can be used in the client by copy and paste. Recompile, declare a variable of the type and use it directly, because the call requires no particular type. It is parsed back into that particular type automatically all the same. Beyond that: entering record values in a form, running any template through the server instead of directly — the way a client would, with the rights mask and the rules — and checking the whole set in one run. The handling is in [docs/EDITOR.md](docs/EDITOR.md).

# Licence
The files in this repository are under the MIT licence, see [LICENSE](LICENSE).
mORMot 2 is not part of them. It is fetched separately (see *Toolchain*) and
carries its own licence: MPL 1.1 / GPL 2.0 / LGPL 2.1, whichever the user picks.
