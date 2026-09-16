# Handoff: soa_sql_templates

> Übergabedokument, um an diesem Beispiel auf einer anderen Maschine weiterzuarbeiten.
> Stand: 2026-09-02 (nach der Anbindung des SQL Servers über Profile).

## 1. Was das Projekt ist

Ein mORMot-2-Beispiel für das **Action-Key-Muster**: *eine* generische SOA-Methode je
Richtung, die benannte SQL-Templates ausführt, statt einer Interface-Methode je Abfrage.
Gedacht als Diskussionsgrundlage für Kollegen und für die mORMot-Runde — deshalb gibt es
[README.md](README.md) auf Englisch und [README-de.md](README-de.md) auf Deutsch, beide
kurz und inhaltlich gleich. Die Langfassungen liegen in
[docs/DETAILS.md](docs/DETAILS.md) bzw. [docs/DETAILS-de.md](docs/DETAILS-de.md).

Drei Programme, alle unter `bin/`:

| | |
|---|---|
| `soa_sql_templates_server` | der Dienst; Templates ausschließlich aus der Datei des gewählten Profils |
| `soa_sql_templates_client` | LCL-Client: anmelden, Profil wählen, Aktionen vom Server holen, eine davon ausführen |
| `soa_sql_templates_editor` | Entwicklerwerkzeug: Templates bearbeiten, SQL testen, Record-Deklaration erzeugen |

## 2. Was gesichert ist und was nicht

**Das Repo hat ein Remote:** `Generic.Soa`,
`https://github.com/stefan-nolte-dev/Generic.Soa.git`. Feature-Arbeit läuft auf eigenen
Zweigen und kommt über einen Pull Request nach `main`.

**Der Stand ist gepusht und in `main` gemergt** (zuletzt PR #2: ORM-Entsprechung um
KeyField, RecordDecl, Retrieve/Delete, den Record-Dialog und `bin/demo.sql`). Der Merksatz
bleibt für den nächsten Schwung: ein Commit auf einem lokalen Zweig ist kein Backup — erst
der Push sichert.

**Die Templates liegen im Repo, die Daten nicht.** In `.gitignore` steht `bin/*` mit
Ausnahmen; ein ausgeschlossenes *Verzeichnis* (`bin/`) ginge nicht, git schaut dann gar nicht
hinein.

| im Repo | nicht im Repo |
|---|---|
| `bin/templates.sqlite` + `bin/templates.sql` (23 Templates) | `bin/demo.sqlite` |
| `bin/templates_mssql.sqlite` + `bin/templates_mssql.sql` (6) | die drei Programme |
| `bin/demo.sql` (Schema und Daten der Demo) | Logs |
| `bin/openssl-tls1.cnf` | |

Je Datenbank ein Paar: die binäre Datei ist der Bestand, der `.sql`-Export daneben ist der
lesbare Diff im Commit. Der Editor schreibt ihn nach jedem Speichern und Löschen neu, ohne
Zeitstempel — ein unveränderter Satz erzeugt keinen Diff.

`bin/demo.sqlite` fehlt mit Absicht: der Server legt sie beim ersten Start an, mitsamt
`Customer`, `Invoice`, `Artikel` und den drei Tabellen mit je hundert Zeilen. Die Daten
entstehen aus dem Schleifenindex, ohne `Random` — zwei Maschinen bekommen dieselben Zeilen.
Maßgeblich ist dieser Code (`CreateDemoDatabase`, `CreateBulkDemoTables`), nicht die Datei.
`bin/demo.sql` ist derselbe Stand als Skript: lesbar im Diff und mit
`sqlite3 demo.sqlite < demo.sql` wieder einspielbar. Beim Start liest ihn niemand — er wird
von Hand nachgezogen, wenn sich der Seed-Code ändert.

Fehlt umgekehrt eine `templates.sqlite`, baut `SeedTemplateDb` sie beim Start aus dem
`.sql`-Export daneben wieder auf; der trägt sein eigenes `create table`. Eine vorhandene Datei
wird nie angefasst.

Die Projektdateien enthalten **keine absoluten Pfade** — alle Suchpfade sind relativ. Der
Ordner darf also beliebig hinwandern, solange Punkt 3 stimmt.

## 3. Bauen

Gebaut wird mit der fpcupdeluxe-Installation, **nicht** mit `/Applications/Lazarus` (deren
Konfiguration kennt mormot2 nicht) und nicht mit `/usr/local/bin/fpc` (3.2.2):

```
D=<fpcupdeluxe-installation>   # der Ordner mit lazarus/ und config_lazarus/
$D/lazarus/lazbuild --pcp=$D/config_lazarus src/proj/soa_sql_templates_server.lpi
$D/lazarus/lazbuild --pcp=$D/config_lazarus src/projclientlaz/soa_sql_templates_client.lpi
$D/lazarus/lazbuild --pcp=$D/config_lazarus src/projeditor/soa_sql_templates_editor.lpi
```

Ohne `--pcp` bricht es mit *"Broken dependency: mormot2"* ab.

**Auf einer neuen Maschine:** Die `.lpi` verweisen auf das Paket `mormot2` nur über den Namen.
Es genügt, mORMot 2.4-stable zu holen (der Clone-Befehl steht im README) und dessen
`packages/lazarus/mormot2.lpk` einmal in der IDE zu öffnen — damit ist es registriert. Ein Eintrag
im Projekt ist nicht nötig, die Anforderung steht schon in den `.lpi`. Einen Neubau der IDE
verlangt es auch nicht: `mormot2` ist ein reines Laufzeitpaket, es installiert nichts in die
Entwurfszeit.

Einmal **übersetzt** werden muss das Paket aber, in genau dieser Konfiguration (FPC-Version,
Ziel-CPU/OS, Modus):

```
$D/lazarus/lazbuild --pcp=$D/config_lazarus <mORMot>/packages/lazarus/mormot2.lpk
# <mORMot> ist der ausgepackte 2.4-stable-Baum
```

In der IDE nimmt das die Paketverwaltung ab; auf der Kommandozeile ist es diese eine Zeile
(hier 578105 Zeilen in knapp 17 Sekunden). `lazbuild` auf ein *Projekt* zieht ein Paket **nicht**
nach: fehlt dessen Ausgabe, bricht es mit *"Can't find unit mormot.core.json"* ab, statt sie zu
erzeugen. Auf einer frischen Maschine ist `packages/lazarus/lib/` leer — also ist das der erste
Schritt, vor den drei Projekten.

Nur eines dabei beachten: Der Paketname `mormot2` ist nicht eindeutig. Liegen mehrere mORMot-Bäume
auf der Maschine und ist mehr als einer registriert, entscheidet die IDE-Konfiguration
(`config_lazarus/packagefiles.xml`), gegen welchen Stand gebaut wird — nicht das Projekt. Hier war
das eine Zeitlang so: neben dem Release-Archiv `mORMot2-2.4-stable` (`2.4.13372`, Januar 2026) war
der Clone `dev/mormot2` (`2.4.14117`, März 2026, eigener Zweig) unter demselben Namen eingetragen.
Der zweite Eintrag ist am 12.09.2026 herausgenommen worden; der Ordner selbst liegt unangetastet
daneben. Wer die `.lpk` darin öffnet, trägt sie wieder ein.

Das Release-Archiv ist übrigens nicht dasselbe wie `git clone --branch 2.4-stable`: derselbe
Quelltext, aber ohne Historie, `git describe` gibt es dort nicht. Die statischen Bibliotheken
darin gehören zum Tag (`static/dev.sha256` vom 12.01.2026) und nicht zum „immer neuesten" Stand
von synopse.info — wovor das README ausdrücklich warnt.

FPC 3.3.1 statt 3.2.x ist nicht beliebig: mORMot liest das Record-Layout aus erweiterter
Record-RTTI, die es selbst als `HASEXTRECORDRTTI` absichert — Delphi 2010+ und FPC-Trunk
3.3/3.4, aber **nicht** FPC 3.2.x. Hier gemessen mit demselben Record und demselben JSON:
3.3.1 liest korrekt, 3.2.3 liest nichts. Unter Delphi kommt eine zweite Bedingung dazu, die in
mORMots eigenem Quelltext vermerkt ist: das Feld-Table zu lesen *"may need `$RTTI EXPLICIT
FIELDS([vcPublic])`"*. Ungeprüft — auf dieser Maschine gibt es kein Delphi.

## 4. Laufen lassen

```
cd bin
./soa_sql_templates_server                 # Profil demo   auf Port 8890
./soa_sql_templates_server mssql          # Profil mssql auf Port 8891
./soa_sql_templates_server caller=2        # jeder Aufrufer ohne Token ist UserID 2
./soa_sql_templates_server token strict    # ohne Token abweisen, Maske verlangen
```

Die Schalter stehen in beliebiger Reihenfolge neben dem Profil: `caller=<id>` gibt jedem
Aufrufer ohne Token diese Identität, `token` lehnt ohne brauchbares Token ab (und druckt beim
Start den Anmeldebefehl), `strict` lässt eine nicht gesetzte Rechtemaske ablehnen. Alle drei
sind aus, wenn man sie nicht nennt, und sagen beim Start braun, dass sie an sind.

Anmelden geht so — die Demo-Konten sind `admin` und `user`, das Passwort ist `demo`:

```
curl -s -X POST http://localhost:8890/sqltemplates/AppAuthTool.Login -d '["admin","demo",""]'
```

Was zurückkommt, ist das Token für `-H "Authorization: Bearer <token>"`.

**Profile.** Ein Dienst spricht mit einer Datenbank, und die Templates dieser Datenbank liegen
in einer eigenen Datei daneben. Zwei Datenbanken sind zwei Dienste, zwei Template-Dateien, zwei
Historien — das hält auch den Merge klein.

| Profil | Port | Templates | Ziel |
|---|---|---|---|
| `demo` | 8890 | `bin/templates.sqlite` | `bin/demo.sqlite` |
| `mssql` | 8891 | `bin/templates_mssql.sqlite` | eine Datenbank auf dem SQL Server |

**Ein Prozess bedient ein Ziel.** Beide gleichzeitig heißt: beide starten. Jedes Profil hat
seinen eigenen Port, also stören sie einander nicht — gemessen, beide gleichzeitig, jeder
liefert seinen Satz und kennt die Schlüssel des anderen nicht (`sqlUnknownKey`).

Die Tabelle steht in `src/common/SqlProfiles.pas` — dem einzigen Ordner, den Server, Client und
Editor alle drei sehen. Deshalb kann keiner der drei eine andere Vorstellung davon haben, was
`mssql` bedeutet. Der Server nimmt die Datei, der Client den Port, der Editor beides.

**Umschalten.** Client und Editor haben je ein Auswahlfeld *Profil*. Im Client setzt es den
Server-Port und leert die Aktionsliste; *Aktionen vom Server holen* füllt sie aus
`AvailableActions`, dann läuft jeder Schlüssel über *Aktion ausführen* mit den Bounds als
JSON-Liste (`[]`, `[100]`, `["Fr%"]`). Im Editor setzt es Template-Datei **und** Zieldatenbank
zusammen — bei `mssql` auf ODBC-Verbindungsstring — und trennt eine bestehende Verbindung,
weil sie zur anderen Datenbank gehörte. Die Templates einer Datenbank gegen eine andere zu
bearbeiten ist genau der Fehler, den das verhindert.

Unterhalb von `ServSqlTemplates` weiß keine Schicht, dass es Profile gibt: `Props` ist dort
eine `TSqlDBConnectionProperties`.

Für `mssql` müssen drei Dinge stehen, sonst scheitert der Start mit der Meldung des Treibers:

| | |
|---|---|
| Weg zum Server | eine Route dorthin (VPN, Tunnel), `<host>:1433` erreichbar |
| Anmeldung | Kerberos-Ticket (`kinit <benutzer>@<REALM>` oder Ticket Viewer, `klist` zeigt es) oder ein SQL-Login in den Feldern des Editors |
| `bin/openssl-tls1.cnf` | senkt `MinProtocol` auf TLS 1.0 — nötig gegen ältere Server, die nichts anderes können |

Kein Kennwort steht im Code, in der Umgebung oder in einer Konfigurationsdatei:
`Trusted_Connection=yes` holt sich das Ticket. Die Templates dieses Profils lesen nur.
Einzelheiten samt der vier macOS-Eigenheiten stehen als Kommentar in
`src/commonserv/SqlServerConn.pas`.

**Der Editor braucht den Server nicht** — auch nicht für `mssql`. Er hat seine eigene
Verbindung: bei `demo` über SQLite auf die Datei, bei `mssql` über unixODBC auf den SQL
Server, mit denselben drei Voraussetzungen wie oben. Nur *Server neu laden* spricht mit dem
Dienst, und wenn keiner läuft, steht *"No server at …"* im Log und sonst passiert nichts.
Vom Server abhängig ist allein der Client: er kennt vom Profil nur den Port.

**Das Feld *DB* wählt der Editor selbst.** Es hat zwei Einträge — *SQLite file* und
*ODBC connection string* —, und wer eines davon wählt, bekommt das Profil dazu: die
Profiltabelle sagt, welchen Treiber ein Ziel braucht, also stellen sich Profilfeld, *Ziel*
und *Templates* mit um. Der Treiber ist damit nicht mehr getrennt vom Ziel einstellbar, und
das ist Absicht: *ODBC connection string* mit einem SQLite-Pfad im Feld *Ziel* ist ein
Verbindungsversuch, der **hängt** statt zu scheitern. Der frühere dritte Eintrag *ODBC data
source* ist aus demselben Grund weg — ein DSN ist ein Name, den unixODBC in einer Datei
nachschlägt, die es hier nicht gibt, und der Treiber wartet darauf, statt es zu sagen.

Der Server schreibt jetzt ein Log neben die Programmdatei und spiegelt Fehler auf die Konsole.
Das ist der Weg zu jeder Fehlerursache — ohne das Log bleibt nur der Debugger.

**Eine Stolperfalle, die dreimal Zeit gekostet hat:** SQLite meldet eine von einem anderen
Prozess gehaltene Datei nicht als belegt, sondern als **`SQLITE_NOTADB`**, also als beschädigten
Dateikopf. Drei Wege hinein: der Editor hängt an `demo.sqlite` und der Server startet, umgekehrt
genauso, oder ein *zweiter* Server desselben Profils. Editor und Server hängen inzwischen beide
einen Satz an, was das gewöhnlich bedeutet. `templates.sqlite` ist nicht betroffen — sie wird
zum Lesen geöffnet und wieder geschlossen, weshalb der Editor sie bei laufendem Server
bearbeiten kann.

**Die zweite Stolperfalle, und sie sieht aus wie ein Absturz:** ein Testlauf gegen `mssql`
mit einem falschen Parameterwert — Text, wo das Statement `int` erwartet — lässt den Editor
**im Debugger stehen**, nicht hängen. Der SQL Server meldet den Konvertierungsfehler, mORMot
wirft `EOdbcException`, `TSqlTemplateExec.SelectJson` fängt sie und macht daraus die rote
Meldung — aber der Debugger hält vorher an, beim `raise`, und sein Dialog liegt im
IDE-Fenster hinter dem Editor. Gemessen: `sample` auf den Prozess zeigt den Hauptthread in
`FPC_RAISEEXCEPTION`, 0 % CPU, Elternprozess `debugserver`; headless durchgespielt liefert
derselbe Lauf dreimal hintereinander in je ~100 ms eine saubere Statusmeldung. Deshalb steht
`EOdbcException` jetzt neben `ESqlite3Exception` in der Ignorierliste des Projekts
(`<Debugging><Exceptions>` in `soa_sql_templates_editor.lpi`) — die SQLite-Seite war längst
drin, was erklärt, warum nur `mssql` „einfror". Aus dem Finder gestartet gab es das nie.

Für kopflose Testprogramme muss `fpc` die Konfigurationsdatei **ausdrücklich** bekommen, sonst
bricht es mit *"Can't find unit system"* ab:

```
$D/fpc/bin/aarch64-darwin/fpc @$D/fpc/bin/aarch64-darwin/fpc.cfg -MObjFPC -Sh \
  -Fu$M/src/core -Fu$M/src/db -Fu$M/src/rest -Fu$M/src/net -Fu$M/src/orm \
  -Fu$M/src/soa -Fu$M/src/lib -Fu$M/src/crypt -Fu$M/src/app -I$M/src \
  -Fu<projektordner> -FU<tmp>/units -o<tmp>/prog <tmp>/prog.lpr
```

Drei Kleinigkeiten, die jedes Mal wieder aufhalten: es muss `-I$M/src` heißen, mit `-Fi` wird
`mormot.defines.inc` nicht gefunden; das Verzeichnis hinter `-FU` muss **vorher existieren**,
sonst *"unable to open output file"*; und wer `mormot.db.raw.sqlite3.static` einbindet, muss
aus einem Verzeichnis übersetzen, von dem aus `../../static/` erreichbar ist — der Pfad zu
`sqlite3.o` steht relativ im Quelltext und wird gegen das Arbeitsverzeichnis aufgelöst.

## 5. Aufbau

Drei Schichten, nach der hier üblichen Konvention (Services/Implementation je Schicht, Starter in
`serv/app`). Ein Aufruf läuft durch alle drei, und jede tut genau eine Sache:

| Schicht | Ordner | Aufgabe |
|---|---|---|
| App | `app` | HTTP-Rand: Token aus dem Header, `TSqlCaller` bauen, weiterreichen. Entscheidet nichts. |
| Dom | `dom` | Existiert die Action (ggf. Reload)? Darf dieser Aufrufer? Halten die Sanity-Regeln? |
| Infra | `infra` | Werte an die Deklaration angleichen, SQL erzeugen bzw. füllen, binden, ausführen. |

Die Reihenfolge in `TDomSqlTool.Resolve` ist: eingeloggt → Action auflösen → Rechte gegen die
konkrete Action → Regeln. Der Login-Check steht zuerst, weil er sonst hinter dem Reload läge.

**Sichtbarkeit steht in den uses-Klauseln, nicht nur im Suchpfad.** Deshalb ist der Typ
`TSqlRec` (`commonserv/SqlTemplateTypes.pas`) von der Registry
(`dom/SqlTemplateRegistry.pas`) getrennt: Infra bekommt ein Template gereicht und kann keins
nachschlagen. Wer die Trennung anzweifelt, sieht sie in zwei Zeilen — die uses-Klausel von
`InfraSqlImplementation` nennt `SqlTemplateTypes` und nicht die Registry.

Ebenso: **`WriteDtos` steht in keiner uses-Klausel unterhalb von `app`.** Der Record-Typ wird
zur Laufzeit über `Rtti.FindName` an seinem Namen aus der `RecordType`-Spalte gefunden; bekannt
gemacht wird er von der `initialization` in `WriteDtos`, die allein der Starter hereinzieht.

Was jedes Projekt auf seinen Suchpfad setzt:

| Projekt | sieht |
|---|---|
| Client | `common`, `app`, `client`, `clienttests`, `clientlaz` |
| Server | `common`, `commonserv`, `infra`, `dom`, `app`, `serv/app` |
| Editor | `common`, `commonserv`, `infra`, `dom`, `app`, `client`, `editor` |

Der Editor sieht absichtlich alles: er ist ein Entwicklerwerkzeug und braucht die Registry als
Probe (`TemplateStore`) und die Infra-Schicht zum Testlauf (`EditorExec`).

Die zwei Units der Profile liegen deshalb in verschiedenen Ordnern:

| Unit | Ordner | warum dort |
|---|---|---|
| `SqlProfiles.pas` | `common` | Server, Client und Editor lesen alle drei dieselbe Tabelle — sonst könnten sie darüber auseinanderlaufen, was `mssql` bedeutet. Enthält nur Name, Port, Dateiname, Datenbankname. |
| `SqlServerConn.pas` | `commonserv` | Host, Treiber, Verbindungszeichenfolge und die OpenSSL-Einstellung. Der Editor braucht sie, der Client sieht `commonserv` nicht — ein Hostname gehört nicht in ein Client-Kompilat. |

Die vollständige Dateiliste steht in [docs/DETAILS-de.md](docs/DETAILS-de.md) unter *Aufbau*.

## 6. Was funktioniert, gemessen

- **Erzeugtes SQL als Anfang eines geschriebenen** (06.09.): der Knopf *SQL ins Feld erzeugen*
  schreibt das erzeugte Statement ins SQL-Feld und nimmt den Haken bei *SQL beim Aufruf
  erzeugen* weg — der Ausweg „dann schreib es eben" war bei einem Record mit dreißig Feldern
  bisher theoretisch. Insert und Update kommen in der `:Namen`-Form heraus, nicht mit `?`:
  ein geschriebenes Record-Statement mit Fragezeichen wird abgelehnt (`rbQuestionMark`).
  Bei einem Retrieve und einer Liste ist es ein Entwurf, der aufhört, wo das Schreiben
  anfängt: Spaltenliste und Tabelle, kein `where` — das schreibt man selbst, statt es erst
  wegzulöschen. Gemessen für alle fünf Arten von `TDtoCustomer`:
  `insert into Customer (Name, City) values (:Name, :City)`,
  `update Customer set Name = :Name, City = :City where ID = :ID`,
  `select ID, Name, City from Customer` (Retrieve **und** Liste),
  `delete from Customer where ID = ?` — das Delete behält sein `where`, weil
  `delete from Customer` als Anfang einen Tastendruck neben einer geleerten Tabelle liegt.
  Kein abschließendes Semikolon: an einem Entwurf wird weitergeschrieben. Das übernommene
  Update läuft anschließend als
  geschriebenes Template durch `RunRecord` (zurückgerollt, `executed: update Customer set
  Name = ?, City = ? where ID = ?`). Der Editor sagt beim Übernehmen, dass das Template ab
  dann dem Recordtyp nicht mehr folgt.
- **`OrmList…`: die Liste zum Retrieve** (06.09., über HTTP gegen `demo.sqlite` gemessen):
  ein fünftes Verb, dessen Statement aus Recordtyp **und** zwei neuen Template-Spalten
  entsteht — `Filter` (die Where-Klausel ohne das Wort `where`) und `OrderBy`. Der Aufrufer
  füllt nur die `?` des Filters; die Form der Abfrage bleibt im Template, anders als bei
  mORMots `RetrieveList`, das sie vom Client nimmt. Gemessen mit
  `OrmListTDtoCustomer` (`Filter = 'City = ?'`, `OrderBy = 'Name'`): über den gewöhnlichen
  Client-Aufruf `ParseDynArray` liefert `['Wegberg']` eine Zeile in ein `TDtoCustomerArray`
  (`1 | Bergmann Werkzeuge | Wegberg`), `['Goslar']` die andere, ohne Wert `sqlBadParams`
  samt Warnung im Log. Contract und Client blieben unverändert — die Liste ist
  `GetJsonFromAction` wie jede andere Abfrage. Im Editor läuft sie über *Testen*:
  `select ID, Name, City from Customer where (City = ?) order by Name;`. Der Filter steht
  **geklammert** im Statement, damit ein `or` darin die Bedingung nicht aushebeln kann, die
  `CallerScope` mit `and` anhängt; wie viele Werte ein erzeugtes Template erwartet, sagt
  jetzt `ExpectedParamCount`, das die `?` des Filters zählt, wenn es noch keinen Text gibt.
- **Templates ohne eigenes Statement sind jetzt testbar** (05.09.): steht im SQL-Feld nichts
  und ist ein Record-Typ genannt, gibt *Testen* den ganzen Satz mit leerem `Sql` nach unten und
  lässt ihn dort erzeugen, wo er auch im Server entsteht — `SelectJson` für ein `OrmRetrieve…`,
  `Execute` für ein `OrmDelete…` (`RunGenerated` in `EditorExec`). Die Art liest der Editor am
  Schlüssel ab, nicht am Text, den es noch nicht gibt. Gemessen auf einer Kopie von
  `demo.sqlite`: Retrieve mit `[int] 1` liefert
  `[{"ID":1,"Name":"Bergmann Werkzeuge","City":"Wegberg"}]` zu
  `select ID, Name, City from Customer where ID = ?;`; Delete auf `3` wird mit Haken
  zurückgerollt (Zeile bleibt) und ohne Haken committet (Zeile weg). Zwei Fälle werden mit Grund
  abgelehnt: kein oder mehr als ein Wert („nimmt genau einen Wert — den Schlüssel"), und ein
  `OrmAdd…`/`OrmUpdate…`, das einen Record braucht und auf den Dialog verwiesen wird.
- **Rollback ist jetzt abschaltbar** (05.09.): das Feld *Rollback* auf der Editor-Form
  entscheidet, was am Ende der Transaktion steht. Angehakt — die Vorgabe — bleibt alles wie
  bisher; ohne Haken wird ein durchgelaufenes Schreib-Statement committet, damit man die Zeile
  mit einem anderen Werkzeug ansehen kann. Gemessen auf einer Kopie von `demo.sqlite`, dasselbe
  Update zweimal: mit Haken steht danach `Wegberg` in der Datei, ohne Haken `Probe` — auch von
  außen mit `sqlite3` gelesen. Zwei Dinge committen weiterhin nie: ein gescheitertes Statement
  und ein Lauf, der eine Ausnahme geworfen hat. Sichtbar ist der Zustand in der Titelleiste
  (`ROLLBACK AUS`), im Log beim Umschalten und in der Meldung des Laufs (`COMMITTED`).
- **Die beiden Auswahlfelder des Editors hängen zusammen** (05.09.): *DB* und *Profil* sind
  zwei Sichten auf dieselbe Entscheidung, also zieht jedes das andere nach — bisher nur das
  Profil den Treiber, jetzt auch der Treiber das Profil. Anlass war ein Einfrieren: *ODBC
  connection string* gewählt, Profil `demo` stehen gelassen, verbinden — der Treiber wartet
  auf einen Pfad, den er nicht deuten kann. *ODBC data source* ist ganz entfallen, weil es
  auf demselben Weg hängt (`engOdbcDsn` in `EditorDb.pas` ist mit weg).
- **Lesen:** `ParseDynArray(<key>, <bounds>, <array>, TypeInfo(<arraytyp>))` — eine Funktion
  für jede Abfrage, die es je geben wird. Der Recordtyp lebt im Client.
- **Schreiben ganzer Records:** `WriteRecord(<key>, <rec>, TypeInfo(<typ>))`. Der Server kennt
  den Typ nur als Namen aus der Spalte `RecordType` und findet ihn über `Rtti.FindName`.
- **Erzeugtes SQL:** Ist die Spalte `Sql` leer, baut der Server Insert oder Update aus
  Recordtyp und Action-Key. Drei Konventionen, alle in `SqlRecordBind`: Schlüssel beginnt mit
  `Add`/`Insert` oder `Update`, Tabelle ist der Recordtyp ohne `TDto` und ohne `Row`,
  Schlüsselspalte heißt `ID`. Alles davon vergleicht ohne Rücksicht auf Groß-/Kleinschreibung.
- **Typen überleben:** `TDtoInvoiceRow.InvoiceDate` ist ein echtes `TDateTime`, `Amount` echtes
  `currency`, beide werden als solche gebunden. In `demo.sqlite` gelandet:
  `1234.56 | 2026-08-31T14:30:00`. Der Grund, warum der Parameter als `RawUtf8`-JSON reist und
  nicht als Variant: ein `TDateTime` in einem Variant kommt beim Empfänger als String an.
- **Nur noch eine Herkunft.** `sqls.pas` und `SqlTemplatesFromCode.pas` sind gelöscht;
  keine Anweisung dieser Anwendung ist einkompiliert. Fehlt `bin/templates.sqlite`, baut
  der Server sie beim Start aus `bin/templates.sql` auf (gemessen: 23 Templates, Abfrage
  läuft danach). Fehlt beides, startet er nicht und nennt beide Pfade.
- **Der Export kann nicht mehr veralten.** Der Editor schreibt `templates.sql` nach jedem
  Speichern und Löschen neu. Rundlauf gemessen: 23 Templates raus, Feld für Feld identisch
  wieder herein, auch mit verschachtelten Anführungszeichen — und `sqlite3 datei.sqlite <
  templates.sql` tut dasselbe ohne Pascal.
- **Reload ohne Neustart, und ohne Scheunentor** (01.09. über HTTP gemessen): ein unbekannter
  Action-Key wird abgewiesen; wird während des Laufs eine Zeile in `templates.sqlite`
  eingefügt, beantwortet der nächste Aufruf denselben Key. Im Log stehen dabei genau **zwei**
  Reload-Zeilen — Start und echte Dateiänderung. Zehn Fehlversuche dazwischen kosteten keinen:
  `TDbTemplateSource.Changed` vergleicht Zeitstempel *und* Größe, und wird vor dem Laden
  gefragt. Ein Tippfehler in einer Schleife kostet damit einen `stat`-Aufruf, keine Abfrage.
- **SQL Server über dasselbe Infra** (02.09. über HTTP gemessen): Profil `mssql` auf Port
  8891, `TOdbcConnectionProperties` statt SQLite, Kerberos über `Trusted_Connection` — kein
  Kennwort im Quelltext, in der Umgebung oder in einer Konfigurationsdatei. Sechs nur lesende
  Templates gegen eine gewachsene Datenbank, Umlaute in den Ergebnissen korrekt, `money` mit
  `null`, eine Gruppierung über mehrere tausend Zeilen. Beide Profile liefen dabei
  gleichzeitig; ein Demo-Schlüssel gegen 8891 gibt `sqlUnknownKey`. Voraussetzung sind ein Weg
  zum Server und eine Anmeldung, siehe Punkt 4.
- **Fehler kommen als Meldung an.** Sechs Fälle gegen den SQL Server durchgespielt, keiner mit
  Ausnahme: Tippfehler im Schlüsselwort, fehlende Spalte, fehlende Tabelle, Konvertierung, die
  erst beim Ausführen scheitert, fehlender Parameter, korrekt. Der Grund steht jeweils in den
  Worten des Servers. Vorher stand bei allem, was *nach* einem geglückten Prepare scheiterte,
  nur *"No reason reported by the driver"* — mORMot hinterlässt die Meldung an der Verbindung
  nur bei abgelehntem Prepare, alles danach ging bloß ins Log. Jetzt legt Infra sie in
  `LastSqlError` ab, einer threadvar, ohne das Contract anzufassen.
- **Ein Recordtyp braucht kein Pascal mehr** (02.09. über HTTP gegen `demo.sqlite` gemessen):
  die Spalte `RecordDecl` trägt die Felder als textuelle RTTI, `Rtti.RegisterFromText`
  registriert den Typ beim ersten Aufruf unter dem Namen aus `RecordType`. `TDtoArtikelRow` —
  nirgends in Pascal deklariert — fügt ein und aktualisiert. Drei Zusicherungen mitgemessen:
  ein einkompilierter Typ gewinnt (`Rtti.FindName` zuerst; ein unsinniges `RecordDecl` neben
  `TDtoCustomer` wird ignoriert, der Insert nennt weiter `Name` und `City`), eine *geänderte*
  Deklaration wirkt beim nächsten Reload (`'Name: RawUtf8'` scheitert am `not null` von
  `Customer.City`, nach dem Erweitern schreibt derselbe Schlüssel beide Spalten), und eine
  Deklaration, die nicht parst, ist ein abgelehnter Aufruf mit dem Grund im Log.
- **Die Schlüsselspalte steht in der Zeile** (dasselbe Datum, derselbe Weg): `KeyField`, leer
  heißt weiter `ID`. `OrmUpdateTDtoArtikelRow` mit `KeyField = 'ArtNr'` erzeugt
  `update Artikel set ArtName = ?, Kind = ? where ArtNr = ?` und trifft die Zeile. Ein Update,
  dessen Schlüsselspalte gar kein Feld des Records ist, wird abgelehnt statt ohne `where`
  ausgeführt — die Meldung nennt Typ und Spalte.
- **Retrieve und Delete, ohne neuen Contract** (03.09. über HTTP gegen `demo.sqlite`
  gemessen): `OrmRetrieveTDtoCustomer` erzeugt `select ID, Name, City from Customer where
  ID = ?` und `OrmDeleteTDtoCustomer` `delete from Customer where ID = ?`. Beide schicken
  nur den Schlüssel — die Spaltenliste ist Sache des Recordtyps, den der Server aus dem
  Template kennt, genau wie ein ORM eine Feldnamenliste schickt und keinen Record. Deshalb
  laufen sie über `GetJsonFromAction` und `WriteDataForAction`, also über die vorhandenen
  Methoden; `IAppSqlTool` blieb unverändert. Gemessen: Retrieve in einen `TDtoCustomer`
  (`ID 29 / Rekord GmbH / Drolshagen`), Retrieve auf eine fehlende Zeile `sqlNoRows` mit
  unangetastetem Record, Delete `sqlOk` und beim zweiten Mal `sqlNothingWritten`.
- **Die ORM-Schlüssel tragen jetzt eine Marke**: sie beginnen mit `Orm`, und nur sie. Der
  Verb-Präfix allein war für einen Leser der Schlüsselliste nicht eindeutig —
  `DeleteCustomer` (Wertliste) und `OrmDeleteTDtoCustomer` (erzeugt) stehen jetzt
  nebeneinander und sind am Namen zu unterscheiden. Die Konvention liegt in
  `SqlTemplateTypes`, nicht in `SqlRecordBind`: die Domänenschicht liest dieselbe Marke,
  um ein erzeugtes Delete auf den Wertelisten-Pfad zu lassen, und darf `SqlRecordBind`
  nicht sehen. Neun vorhandene Zeilen wurden umbenannt; ein Record-Schlüssel ohne Marke
  wird abgelehnt (*"takes a record but does not start with ORM"*).
- **Caller-Scoping als Paritätsbeispiel** (03.09. über die Domänenschicht gegen `demo.sqlite`
  gemessen): Spalte `CallerScope='userid'` bindet `Caller.UserID` ans letzte `?`. Demo
  `GetMeineRechnungen`: Kunde 2 bekommt nur die Rechnungen 4/5, Kunde 4 nur 7–9 — derselbe
  Action-Key, der Client schickt keine ID. Kunde 2, der `[3]` schickt, um eine fremde ID zu
  erzwingen, wird mit `sqlBadParams` abgewiesen (Zählprüfung: `CountSqlParams−1`). Zum Kontrast
  liest das ungescopte `AmountDateCustomer4OfInvoice` frei fremde Zeilen. Das grobe Gruppen-
  modell braucht das nicht (die Maske deckt es), es zeigt nur die Parität zum hardgecodeten Weg.
- **Ausprobieren ohne Token** (04.09., über HTTP gegen den laufenden Server gemessen): der
  Token-Stub liefert keine Identität, also ist `Caller.UserID` ohne Token 0 und ein gescoptes
  Template liefert leer — das war beim ersten Testen die Verwirrung, denn `TokenToCaller`
  steigt bei leerem Bearer aus, bevor es irgendetwas setzt, und der Client schickt gar keinen.
  Der greifende Zweig ist der anonyme in `CurrentCaller`; er nimmt jetzt `AnonymousUserID`
  (neben `AnonymousReads`/`AnonymousWrites`), zu setzen über das Server-Argument `caller=<id>`, in beliebiger
  Reihenfolge zum Profil. Gemessen: `caller=2` → 4/5, `caller=3` → 6, `caller=4` → 7–9,
  ohne Argument leer, und `[3]` mitgeschickt → `sqlBadParams`. Ein Schalter zum Ausprobieren,
  keine Authentifizierung — der Start sagt das braun auf der Konsole.
- **Abgleich mit den Patterns steht jetzt in DETAILS** (04.09., beide Sprachen, Abschnitt
  „Abgleich mit den empfohlenen Patterns" vor „Bewusst weggelassen"). Anlass: die Demo soll
  gegen die SAD-Recommended-Patterns geprüft werden, und drei Stellen sahen wie Versäumnisse
  aus. Beantwortet mit Zitat: das **leere Modell** ist die vorgesehene Edge-Form (A.6.2,
  *„Void model => no TOrm classes …"*, `TRestServerFullMemory` als *„public edge"* gegen
  `TRestServerDB` als *„private system of record"*) — der Server hier *ist* dieser Edge; die
  **zweite Ebene** ist ersetzt (Templates statt ORM-Tabellen), nicht vergessen; und *„scope
  every read to the caller"* ist **gezeigt, nicht erfüllt** — 1 von 24 Templates nutzt
  `CallerScope`, 23 nennen keine Maske und sind mit `StrictRights = false` erlaubt.
  (Der zweite Teil gilt seit dem 07.09. nicht mehr: alle Templates nennen jetzt eine Maske.)
  Der Absatz „Authentifizierung" unter „Bewusst weggelassen" war **sachlich falsch** („ohne
  Sitzung ist jede Gruppe 0, sodass ein Key mit Maske alle ablehnt") und ist korrigiert:
  `AnonymousReads`/`AnonymousWrites` auf 1, `StrictRights = false`. Neu als TODO **A5**: Authentifizierung
  überhaupt einschalten — die Patterns verlangen es ausdrücklich, die Demo erfüllt es nicht.
- **Der Editor kann Caller-Scoping nicht testen** und sagt es jetzt: sein „Testen" führt
  direkt auf der Verbindung aus (`TSqlTemplateExec` auf `Db.Props`), nicht über die Domänen-
  schicht, also greift `CallerScope` dort nicht. Bei gesetztem Caller-Scope steht *„Ungescopt
  getestet"* vor der Statusmeldung, damit ein grüner Lauf nicht als Nachweis durchgeht.
- **Der Record-Dialog im Editor** (03.09.): *Record-Werte eingeben…* baut aus den Feldern
  des aufgelösten Recordtyps einen Dialog — zur Laufzeit, nicht als LFM, weil die Steuer-
  elemente erst feststehen, wenn der Typ gelesen ist — und schickt das entstandene JSON
  durch `BindRecordJson` in dieselbe zurückgerollte Transaktion wie jeder Schreibtest.
  Gemessen: alle fünf Record-Schlüssel erzeugen ihr Statement und melden *"Write ran, and
  was rolled back"*; danach steht in `demo.sqlite` Zeile für Zeile dasselbe wie vorher,
  auch beim Update auf `Customer` 1. `OrmRetrieve…` und `AddCustomer` werden mit Grund
  abgelehnt. Der Editor bindet dafür jetzt `WriteDtos` mit, sonst könnte er über die
  einkompilierten Typen nichts sagen — die alte Grenze ist damit weg.
  Bei einem `OrmUpdate…` fragt er vorher nach dem Schlüssel und belegt den Dialog aus der
  Zeile vor, geholt über `RetrieveSqlFor` — den Retrieve-Zweig desselben Erzeugers, beim
  Namen gerufen, also über dieselbe Schlüsselspalte, auf die das Update passt
  (`OrmUpdateTDtoArtikelRow` sucht über `where ArtNr = ?`). Gemessen: `ID` 2 lädt
  `{"ID":2,"Name":"Ostwald Holzbearbeitung","City":"Detmold"}`, der geänderte Record
  läuft durch das Update, danach steht die Zeile unverändert da.
- **Ein `with` ist keine Statement-Art.** `with x as (...) delete from x` galt im Editor als
  Select und wäre damit außerhalb des Rollback-Rahmens gelaufen — hätte also committet, das
  eine, was dieses Werkzeug zusagt nie zu tun. Entscheidend ist jetzt das Verb im übrigen Text.
  Gemessen: das CTE-Select liefert Zeilen, das CTE-Delete wird zurückgerollt.
- **Die Schichtung hält, einzeln übersetzt.** Jede Schicht baut mit abgeschnittenem Suchpfad:
  Infra mit `common commonserv infra`, Dom zusätzlich ohne `app`, App mit
  `common commonserv dom app` und *ohne* `infra`. Das ist der grüne Build, den man statt eines
  Diagramms vorlegen kann.

- **Die `Rules`-Spalte ist da** (06.09.): benannte Prüfungen in `src/common/SqlParamRules.pas`
  (`notempty`, `plz`, `email`, `len`, `range`, `oneof`), im Template als Daten genannt und
  je Parameterposition, die Position vorn: `1:notempty;2:plz;3:email`. Gelaufen in
  `TDomSqlTool.CheckRules`, also nach `ApplyCallerScope` und vor dem Statement.
  Zwei Antworten, und der Unterschied ist der Punkt: ein Wert, der nicht besteht, ist
  `sqlBadParams` (Warnung im Log), eine falsche Deklaration — unbekannter Regelname, eine
  Position ohne `?` — ist der Fehler der Vorlage und wird `sqlFailed` (Fehler im Log, nach
  außen kein Wort über die Deklaration).
  Gemessen: 28 Fälle im Konsolen-Harness grün (`plz`, `email`, `len`, `range`, `oneof`,
  Null-Werte, doppelte Regel auf einer Position, und sechs kaputte Deklarationen). Über HTTP
  gegen die Demo: `AddKontakt` mit `["Test GmbH","41844","a@b.de"]` → `0`, mit `4184` →
  `7`, mit `a.b.de` → `7`, mit leerem Namen → `7`; `GetKontakteByPlz` mit `abcde` → `7`,
  mit `41844` → zwei Zeilen; eine Zeile, deren Regel Parameter 4 eines Statements mit einem
  `?` nennt → `6`. Das Log nennt jedes Mal den Parameter.
  Neu dafür: die Tabelle `Kontakt` in der Demo (vier Zeilen, in `CreateBulkDemoTables`) und
  die beiden Templates `AddKontakt` und `GetKontakteByPlz`. Der Editor hat ein Feld
  *Regeln*, prüft es unter „Prüfen" mit und lehnt einen Testlauf ab, den der Server
  ablehnen würde — mit demselben Wortlaut.
  Eine Grenze, ausgesprochen: Positionen sind die `?` des Statements, ein Record-Schreiben
  hat keine. Ein Record-Template mit Regeln wird abgelehnt (`sqlFailed`), im Editor schon
  vor dem Speichern.

- **„Alle prüfen" und die Spalte `TestBounds`** (06.09.): `src/editor/EditorSweep.pas` prüft
  jedes Template — Deklaration, Statement gegen Parameterzahl, `where` bei Delete,
  Record-Typ, Regeln — und führt die aus, die Beispielwerte tragen. `TestBounds` ist das
  JSON, das ein Client schicken würde: ein Array geht ans Statement, ein Objekt ist das JSON
  eines Records und geht den Record-Weg. Ohne `TestBounds` gilt ein Template als *offen*,
  nie als bestanden; ein gescoptes ebenso, weil der Editor keine Identität bindet.
  Jeder Lauf wird zurückgerollt, unabhängig von der Rollback-Box.
  Gemessen gegen `demo.sqlite`: 29 Templates, 28 ausgeführt, eines offen
  (`GetMeineRechnungen`), kein Befund — und der `.dump` der Datenbank ist vorher und
  nachher Byte für Byte gleich. Mit sieben absichtlich kaputten Zeilen in einer Kopie:
  sieben Befunde mit Grund, darunter `no such column: Nmae`, zwei Werte statt einem, zwei
  Typen für einen Parameter, ein unbekannter Record-Typ und ein `delete` ohne `where`.
  Im Editor: Knopf *Alle prüfen* neben *Prüfen*, Feld *TestBounds* in der Zeile mit
  *Caller-Scope* und *Regeln*, und *JSON als TestBounds* übernimmt die Werte aus der
  Parameterliste, damit die beiden nicht auseinanderlaufen.

- **Das Token trägt eine Payload** (06.09., am 07.09. durch das JWT unten ersetzt): `TTokenPayload` (UserID, UserName, Groups,
  Expires) in `AppCallerToken`, gefüllt aus einem Entwickler-Token `dev.<base64url(json)>`.
  `VerifyToken` prüft Präfix, Kodierung, JSON und **Ablauf** — ein gelesener und ignorierter
  Ablauf wäre schlimmer als keiner, er sähe aus wie eine Prüfung. Eine Payload ohne Gruppe
  wird abgelehnt. Was fehlt, ist die Signatur, und die Stelle dafür ist markiert.
  Zwei neue Startschalter, beide aus: `token` (ohne brauchbares Token wird abgelehnt, und der
  Start druckt eines zum Ausprobieren) und `strict` (`StrictRights`). Sie stehen in beliebiger
  Reihenfolge neben Profil und `caller=<id>`; die Konsolentexte sind englisch und ohne
  Umlaute, weil die Codepage einer umgeleiteten Konsole sonst Fragezeichen daraus macht.
  Neues Template `GetGehaelter` mit `ReadGroups = 2` — das erste, an dem eine Maske sichtbar
  ablehnt.
  Gemessen über HTTP, ohne Schalter: ohne Token `GetGehaelter` → `3` (sqlNotAllowed), mit
  `rd:2` → Zeilen; Token `uid:1` auf `GetMeineRechnungen` → genau die drei Rechnungen von
  Kunde 1, ohne einen Wert vom Client. Mit `token strict`: kein Token, abgelaufenes Token,
  Müll-Token, Gruppe-2-Token auf Maske 1 und jedes Template ohne Maske → alle `3`; das vom
  Server gedruckte Token liest beide Templates mit Maske; `AvailableActions` ohne Token leer.
  Regression: `caller=1` ohne Token scopt weiter wie bisher, und der Sammellauf über alle
  30 Templates bleibt ohne Befund.

- **Getrennte Masken und ein eigener Status fürs Anmelden** (07.09.): `TSqlCaller` trägt
  `Reads` und `Writes` statt eines gemeinsamen `Groups` — die Templates tragen die Trennung
  seit es Masken gibt, und der Payload des `auth`-Dienstes trägt sie auch (`Reads`/`Writes`
  in `TPayLoadRec`). `CanExecute` fragt je nach Richtung die passende. Neuer Wert
  `sqlNeedsLogin` in `TSqlStatus`, angehängt, damit die Ordinalzahlen der anderen auf der
  Leitung gleich bleiben: `Resolve` und `CanReload` antworten damit, wenn gar niemand ruft,
  und `sqlNotAllowed` heißt wieder genau *angemeldet, aber nicht berechtigt* — der
  Unterschied, an dem ein Client später entscheidet, ob er das Login-Fenster zeigt.
  Neu: `src/common/SqlAuthTypes.pas` mit `TSessionToken`, `TAuthPayload` und den
  Claim-Namen, gesehen von allen drei Programmen.
  Gemessen mit `token`: ohne Token → `8`, Token `rd:1 wr:0` liest (`0`) und wird auf einem
  Template mit `WriteGroups = 2` abgelehnt (`3`), Token `rd:1 wr:2` schreibt (`0`), ein
  Payload ohne jede Maske → `8`. Die Maske dafür wurde nur für die Messung gesetzt und ist
  wieder zurückgenommen; `templates.sqlite` ist inhaltlich wie im Commit.

- **Die Konten liegen in `bin/auth.sqlite`** (07.09.): eigene Datei, nicht `demo.sqlite` und
  nicht `templates.sqlite` — die Zieldatenbank hängt am Profil, die Menschen nicht. Beide
  Profile teilen sie. `src/infra/AuthAccountsFromDb.pas` legt sie beim ersten Start an und
  rührt sie danach nie wieder an; enthalten sind `admin` (rd/wr = 3, also Gruppe 1 und 2)
  und `user` (rd = 1, wr = 0), Passwort `demo` für beide.
  Kein Passwort wird gespeichert: pro Konto ein Salt aus dem CSPRNG und
  PBKDF2-HMAC-SHA256 darüber, die Rundenzahl steht in der Zeile daneben, damit sie später
  erhöht werden kann, ohne die vorhandenen Zeilen ungültig zu machen. Verglichen wird mit
  `IsEqual` über die Digests, also zeitkonstant. `Blocked` ist die Antwort auf „wie nimmt man
  ein Token zurück": das Konto wird gesperrt, das laufende Token stirbt am Ablauf, und danach
  gibt es keine Anmeldung mehr.
  Gemessen im Konsolen-Harness: 20 von 20 grün — Datei entsteht, beide Konten da, unbekannter
  Name findet nichts, kein Klartext im Hash, verschiedene Salts trotz gleichem Passwort,
  richtiges/falsches/leeres Passwort, gesperrtes Konto kommt auch mit richtigem Passwort
  nicht durch, zweiter Start überschreibt nichts. Eine Prüfung kostet 83 ms bei 60000 Runden —
  gewollt, das ist der Sinn von PBKDF2.

- **Anmeldung mit JWT** (07.09.): `IAppAuthTool.Login` prüft gegen `auth.sqlite` und gibt ein
  von mORMot signiertes JWT zurück (`TJwtHS256`, Issuer `soa_sql_templates`, 300 Minuten —
  wie der `auth`-Dienst nebenan, samt GUID-Geheimnis beim Start). `VerifyToken` prüft
  Signatur, Aussteller und Ablauf in einem Aufruf; das Entwickler-Token samt `dev.`-Präfix
  ist weg, es gibt nur noch einen Weg. `WhoAmI` sagt Name, Masken und Restzeit.
  `Login` ist die einzige Methode ohne Token und braucht dafür keine Ausnahmeliste: die
  Ablehnung sitzt in der Domänenschicht, und eine Anmeldung kommt dort nie hin. Registriert
  mit `optNoLogInput, optNoLogOutput` — im Log steht kein Passwort und kein Token.
  Unbekannter Benutzer, falsches Passwort und gesperrtes Konto sind **eine** Antwort
  (`sqlNeedsLogin`); der Grund steht im Serverprotokoll, und ein Name, den es nicht gibt,
  zahlt trotzdem eine PBKDF2-Runde.
  Gemessen mit `token strict`: `Login` als `admin` → JWT mit
  `{"uid":2,"name":"admin","rd":3,"wr":3,"iss":"soa_sql_templates","exp":…}`; falsches
  Passwort und unbekannter Name → `8` mit leerem Token; `WhoAmI` → `admin, 3, 3, 18000`.
  `admin` liest `GetGehaelter`, `user` wird abgelehnt (`3`). Auf `GetMeineRechnungen`
  liefert dasselbe Template verschiedene Zeilen: `user` (UserID 1) die Rechnungen 1–3,
  `admin` (UserID 2) die 4–5, ohne dass ein Client einen Wert schickt. Token mit einem
  geänderten Zeichen → `8`, jedes Token nach einem Neustart → `8`, `user` gesperrt → keine
  Anmeldung mehr, Sperre weg → wieder. Ohne Schalter ist alles wie vorher.
  `AuthAccount` hat dafür eine Spalte `UserID` bekommen (mit Migration wie bei den
  Templates); `admin` ist Kunde 2, `user` Kunde 1.

- **Der Client meldet sich an** (07.09.): `LoginClient`/`LogoutClient`/`LoggedIn` in
  `AppSqlClient`, das Token in einer Variablen der Unit und nicht in der Verbindung — dieser
  Client verbindet und trennt um jeden einzelnen Aufruf herum, und das Token muss das
  überleben. Gesetzt wird es einmal je Connect über `Client.SessionHttpHeader :=
  AuthorizationBearer(...)`, danach trägt es jeder Aufruf, ohne dass eine Aufrufstelle davon
  weiß. `ConnectClient` löst jetzt beide Schnittstellen auf.
  Neu `src/clientlaz/u_logindialog.pas`: das Anmeldefenster zur Laufzeit gebaut, ohne LFM —
  drei Steuerelemente, und eine Formulardatei dafür wäre mehr Pflege als Gewinn; so wandert
  die Unit außerdem ohne Ressource in den Editor. Passwortfeld mit `emPassword`, und nichts
  darin behält eine Kopie.
  Im Fenster: Knopf *Anmelden…*, der zu *Abmelden* wird, und der Anmeldestand im Titel
  (Name, Masken, Restminuten aus `WhoAmI`) — die obere Zeile hat keinen Platz mehr, und ein
  Zustand nur im Log scrollt genau dann weg, wenn er zählt. Kommt `sqlNeedsLogin` zurück,
  fragt der Client einmal nach und wiederholt denselben Aufruf; eine leere Aktionsliste wird
  über `WhoAmI` daraufhin geprüft, ob sie am fehlenden Token liegt.
  Gemessen im Konsolen-Harness (`src/clienttests/ClientTests.pas`, ruft `AppSqlClient` und
  den Server direkt — das Fenster kommt darin nicht vor) gegen `token strict`: 19 von 19 —
  ohne Token abgelehnt,
  falsches Passwort abgelehnt, `user` angemeldet (`rd=1 wr=0`, 18000 s), `user` auf Maske 2
  abgelehnt, `user` und `admin` auf demselben gescopten Template mit **verschiedenen Zeilen**,
  abgemeldet wieder abgelehnt, und das Token gilt auch nach `DisconnectClient` +
  `ConnectClient`.

- **Jedes Template nennt jetzt eine Rechtemaske** (07.09.): Gruppe 1 liest, Gruppe 2
  schreibt — Selects bekommen `ReadGroups = 1`, Schreibvorgänge `WriteGroups = 2`, und
  `GetGehaelter` behält `ReadGroups = 2`. Anlass war der Test: mit `strict` gestartet
  antworteten 28 von 30 Templates `sqlNotAllowed`, weil sie überhaupt keine Maske nannten —
  richtig nach der Regel, aber als Demo eine Falle. Jetzt ist `strict` eine brauchbare
  Betriebsart, und eine fehlende Maske heißt wirklich, dass jemand etwas vergessen hat.
  Gesetzt über die Store-Klasse des Editors, also mit `templates.sql` im Gleichschritt.
  Gemessen mit `token strict`: `user` liest `GetAllCustomers`, wird bei `GetGehaelter` und
  bei jedem Schreibvorgang abgelehnt (Werteliste wie Record), `admin` bekommt alles;
  ohne Token alles `sqlNeedsLogin`. Der Sammellauf des Editors bleibt bei 29 ausgeführt,
  1 offen, kein Befund — er geht direkt auf die Verbindung, an den Masken vorbei.

- **Der Editor meldet sich an** (07.09.): *Server neu laden* fragt bei `sqlNeedsLogin` nach
  und wiederholt den Aufruf. Das Fenster ist dasselbe wie im Client — `u_logindialog` ist
  nach `src/ui` gewandert, damit zwei Programme, die nach denselben zwei Feldern fragen,
  nicht zwei Fenster pflegen; beide Projekte haben den Pfad und den Unit-Eintrag.
  Dabei ist eine Lücke aufgefallen und geschlossen: `CanReload` verlangte nur, dass
  überhaupt jemand angemeldet ist. Ein Reload ist aber der Weg, mit dem ein neues Template
  wirksam wird — näher am Schreiben als am Lesen. Jetzt verlangt es eine nicht-leere
  `Writes`-Maske. Ohne Token ändert das nichts (`AnonymousWrites`), mit Token ist es genau
  der Unterschied zwischen den beiden Konten.
  Gemessen gegen `token strict`: Reload ohne Token → `sqlNeedsLogin`, als `user` (wr=0) →
  `sqlNotAllowed`, als `admin` → `sqlOk`.

- **Häkchen „über den Server ausführen"** (07.09.): *Testen* nimmt damit den Weg eines
  Clients — `GetJsonFromAction` bzw. `WriteDataForAction` statt der eigenen Verbindung.
  Damit beantwortet der Knopf endlich die Fragen, die der Editor sonst nicht stellen kann:
  Rechtemaske, `CallerScope`, `CheckRules`, und ob der Server den Schlüssel überhaupt kennt.
  Der Preis steht daneben: nur **gespeicherte** Schlüssel, denn der Server hat keine Methode
  für fremdes SQL und soll keine bekommen — ein Entwurf antwortet `sqlUnknownKey` (gemessen:
  `2`), und die Meldung sagt „erst speichern und Server neu laden".
  Zwei Dinge sagt der Modus ausdrücklich, statt sie zu verschweigen: der Server **rollt
  nichts zurück**, deshalb wird ein Schreibvorgang vorher noch einmal bestätigt (die
  Rollback-Box gilt dort nicht). Ein Record-Schreibvorgang nimmt denselben Weg über den
  Record-Dialog — siehe den Eintrag vom 08.09.
  Bei `sqlNeedsLogin` fragt er nach und wiederholt den Aufruf, wie *Server neu laden*.
  Gemessen über HTTP, was der Modus durchreicht: unbekannter Schlüssel → `2`, `user` auf
  `GetMeineRechnungen` → die Rechnungen von Kunde 1, `user` auf `DeleteCustomer` → `3`.
  Das Fenster ist dafür um eine Zeile gewachsen (Knopfleiste 72 → 100, Formularhöhe
  800 → 828), das Häkchen steht unter *Testen*.

- **Der Sammellauf kann über den Server** (07.09.): mit angehaktem Häkchen nimmt *Alle
  prüfen* denselben Weg wie ein Client, `EditorSweep` hat dafür `TSweepMode`. Damit schließt
  sich die Zeile, die immer offen war: `GetMeineRechnungen` läuft, weil der Server die
  Identität bindet — der gescopte Aufruf schickt einen Wert weniger, wie jeder Client.
  Eine Ablehnung durch die Maske gilt als *offen* mit Grund und nicht als Befund; eine rote
  Zeile dafür würde beibringen, Rot zu übersehen. Schreibvorgänge bleiben draußen, wenn man
  nicht vorher ausdrücklich zustimmt — der Server committet.
  Die Werte gehen **uncoerciert** raus: ein Client schickt, was JSON tragen kann, und der
  Server macht daraus, was das Template deklariert. Bei einem gescopten Template wäre eine
  Umwandlung gegen die volle Deklaration hier auch um einen Parameter daneben.
  Gemessen gegen `token strict`, 30 Templates: als `user` 15 gelaufen, 15 offen, kein
  Befund; als `admin` 16 gelaufen (`GetGehaelter` kommt dazu); mit erlaubten
  Schreibvorgängen 21 gelaufen, kein Befund — dafür wurde `demo.sqlite` vorher gesichert
  und danach zurückgespielt, weil der Server nichts zurückrollt.

- **Record-Schreibvorgänge über den Server** (08.09.): der letzte Weg, der noch am Server
  vorbeilief. Der Record-Dialog erzeugt das JSON wie bisher; mit gesetztem Häkchen geht es
  an `SqlTool.WriteRecordForAction` statt in `RunRecord`
  (`TFormEditor.RunRecordThroughServer`), mit derselben Rückfrage vor dem Schreiben und
  demselben Nachfragen bei `sqlNeedsLogin`. Das Feld für das ausgeführte SQL bleibt dabei
  leer, und zwar ehrlich: Typ und Statement entstehen im Server, ein hier erzeugtes wäre
  ein anderes. Im Sammellauf ist ein Objekt in `TestBounds` jetzt ein Schreibvorgang wie
  jeder andere (`HasServerWrites` zählt ihn mit, `RunOneOnServer` schickt ihn), und ein
  Objekt auf einem Schlüssel, der kein Insert/Update ist, ist ein Befund.
  Gemessen gegen `token strict`, 30 Templates: als `admin` mit erlaubten Schreibvorgängen
  laufen **alle 30** (vorher 21), als `user` 15 gelaufen und 15 offen, kein Befund.
  Der eine Befund im zweiten Lauf hintereinander ist `OrmAddTDtoArtikelRow`: feste `ArtNr`
  in `TestBounds` gegen den eindeutigen Index — ein schreibender Sammellauf lässt Zeilen
  zurück, deshalb die Rückfrage. `demo.sqlite` war gesichert und ist zurückgespielt.

- **Suchfeld über der Schlüsselliste** (08.09.): filtert beim Tippen, ohne Rücksicht auf
  Groß-/Kleinschreibung, an jeder Stelle des Schlüssels (`FillKeyList`,
  `EditKeyFilterChange`). Weil eine Zeile jetzt ausgeblendet sein kann, ist der Listenindex
  nicht mehr der Index in `fRecs` — jede Zeile trägt ihre Position in `Items.Objects[]`, und
  `ListKeysSelectionChange` liest sie dort. Ein Neuladen nach dem Speichern behält den
  Filter. Dafür sind Häkchen und Statuszeile in der Knopfleiste nach rechts gerückt
  (Left 120 → 266 bzw. 12 → 266), das Suchfeld steht links darüber, bündig zur Liste.

- **Umlaute, zweiter Teil: der Absturz beim Rollback-Häkchen** (08.09.): `{$codepage UTF8}`
  allein war nicht die ganze Antwort. Gemessen an einem Testprogramm, je Ausdrucksform:

  | Form | ohne Direktive | mit `{$codepage UTF8}` |
  |---|---|---|
  | Zuweisung an `RawUtf8` | `C3 83 C2 A4` (doppelt) | `C3 A4` ✓ |
  | Literal als `FormatUtf8`-Format | `C3 83 C2 A4` (doppelt) | `C3 A4` ✓ |
  | Literal **mit `+` an eine Variable** | `C3 A4` ✓ | **`E4` — kein gültiges UTF-8** |

  Das letzte Feld ist der Absturz: `title := title + ' … Schreibvorgänge …'` in
  `ShowConnection` erzeugte ein Latin-1-Byte, und ein Cocoa-Control beendet darauf den
  Prozess (`stringWithUTF8String` → nil → `insertText:` → SIGABRT). Der Compiler faltet
  einen solchen Ausdruck in die Standard-Ansi-Codepage, unabhängig von der Laufzeit —
  `DefaultSystemCodePage` ist hier 65001, das ändert daran nichts.
  Die sechs betroffenen Stellen sind jetzt `FormatUtf8` statt `+` (gegengeprüft: keine
  4104/4105-Warnung mehr), und die Titelzeile geht zusätzlich durch `SafeText`.
  **Regel für neue Meldungen: ein Literal mit Umlaut nie mit `+` an eine Variable hängen,
  sondern `FormatUtf8('… %', [x])`.** Geprüft wird das von `tools/check_literals.py`
  (Details im Docstring): zwei Quellregeln — jede Datei mit Umlaut-Literalen deklariert
  `{$codepage UTF8}`, und kein solches Literal hängt mit `+` an etwas, das keine Konstante
  ist — plus ein optionaler Durchgang über die gebauten Programme. Beide Regeln sind
  Eigenschaften der Quelle, gelten also für Windows und Linux genauso.
  Gegengeprüft am Detektor selbst: mit absichtlich zurückgebautem `+` und einer Datei ohne
  Direktive meldet er beides, danach wieder 0 Fundstellen. Ein `#13#10` in der Kette ist
  keine Fundstelle — reine Konstantenketten faltet der Compiler richtig (gemessen).

- **Umlaute in Meldungen** (08.09.): `Über den Server: …` stand als `Ãber` im Fenster. Die
  Quellen sind UTF-8, aber ohne `{$codepage UTF8}` liest der Compiler ein Literal in der
  Systemcodepage und codiert es auf dem Weg in einen `RawUtf8`-Parameter noch einmal um —
  im Binary stand tatsächlich `C3 83 C2 9C` statt `C3 9C`. Die Direktive steht jetzt in den
  sieben Units mit Umlauten in Literalen (`u_editormain`, `EditorSweep`, `EditorExec`,
  `EditorDb`, `RecordDialog`, `u_logindialog`, `clientlaz/u_main`); LCL-Captions bleiben
  richtig, weil LazUTF8 die `DefaultSystemCodePage` auf UTF-8 stellt. Gegengeprüft im
  gebauten Binary: die doppelte Codierung kommt nicht mehr vor.

- **Der Record-Dialog wirft die Eingabe nicht mehr weg** (08.09.): das JSON wird je
  Action-Key für die Sitzung gemerkt (`fLastRecordJson`), und der Dialog öffnet beim
  nächsten Mal darauf statt auf leeren Feldern — beim Update erst dann, wenn keine Zeile
  aus der Datenbank kam. Danach steht es unter *so würde es reisen*, von wo *JSON als
  TestBounds* es mit einem Druck in die Spalte schreibt; der Sammellauf und der Weg über
  den Server nehmen es dort wieder auf.
  In die **Parameterliste** geht es bewusst nicht: der erzeugte Schreibvorgang trägt
  `:Namen`, die der Server aus dem Record füllt, und ein Record-Template mit `?` lehnt die
  Domänenschicht ab. Werte, die der Lauf nie liest, wären ein Feld, das etwas anderes
  verspricht, als es hält.
  Dazu gehört die zweite Hälfte: *Testen* führte auf einem Record-Insert/Update vorher das
  `:Namen`-Statement mit leerer Parameterliste aus, band also nichts, und SQLite antwortete
  `NOT NULL constraint failed: Artikel.ArtNr` — eine wahre Meldung über die falsche Sache.
  Jetzt sucht `RecordJsonToTest` den Record dort, wo das Fenster ihn zeigt: erst *geht als
  JSON raus* (was man ansieht, und was man dort auch ändern kann), dann die letzte Eingabe
  im Dialog zu diesem Schlüssel, dann die Spalte `TestBounds`; ein Array in einem der drei
  zählt nicht, ein Record-Schreibvorgang hat keine Positionen. Gefunden, läuft *Testen*
  denselben Weg wie der Dialog — mit Häkchen über `RunRecordThroughServer`, ohne über
  `RunRecord`. Erst wenn keiner der drei einen Record trägt, kommt die Absage.
  Gegengeprüft gegen `demo.sqlite`: `{"ID":0,"ArtNr":24,...}` bindet
  `[24,"Schraube","Heimwerken"]` und läuft `sqlOk`, zurückgerollt.

- **Bedienungsanleitungen** (08.09.): `docs/EDITOR{,-de}.md` und
  `docs/SERVER-CLIENT{,-de}.md` — knappe Schritt-für-Schritt-Listen für Test-User, in
  beiden Sprachen, von den READMEs aus verlinkt. Sie beschreiben Handgriffe, keine
  Begründungen; das Warum bleibt in DETAILS. Die englischen Fassungen zitieren die
  deutschen Beschriftungen der Fenster, statt sie zu übersetzen — sie stehen so auf dem
  Schirm.

- **Absturz nach der Anmeldung mitten im Aufruf** (15.09.): Server mit `token strict`,
  *Aktionen vom Server holen*, anmelden — danach `EXC_BAD_ACCESS` in
  `SqlTool.AvailableActions`. `LoadActions` hielt die Verbindung, `AskAgain` meldete darin
  an und rief anschließend `ShowLoginState` für die Titelzeile; das verband sich ein zweites
  Mal und gab im `finally` `DisconnectClient` — und das setzt `SqlTool` und `AuthTool` auf
  `nil` und gibt den `TRestHttpClient` frei. Der Aufrufer griff danach auf eine
  nil-Schnittstelle zu. Nur auf dem Erfolgspfad: eine abgelehnte Anmeldung kommt mit `false`
  zurück, und `ShowLoginState` läuft gar nicht erst.
  Dahinter der eigentliche Fehler: `SqlTool`, `AuthTool` und `Client` sind Variablen der
  Unit `AppSqlClient`, Eigentum an der Verbindung war also Vereinbarung, nicht Code.
  `ShowLogin` hat dafür den Parameter `Connected` bekommen, `ShowLoginState` nicht — und
  genau die wurde später aus einem laufenden Aufruf gerufen. `ConnectClient` hätte den
  ersten `Client` dabei ohne Freigabe überschrieben.
  Behoben, ohne eine Prüfung hinzuzufügen: `AskAgain` meldet nur noch an, die Titelzeile
  holen die beiden Knopf-Behandler nach, wenn ihre Verbindung wieder zu ist. Damit verbindet
  und trennt `ShowLoginState` wieder unbedingt, und niemand ruft es mehr von innen. Netto
  +6/−3 Zeilen, davon zwei Kommentar.
  Warum es niemand vorher sah: der Harness vom 07.09. erreicht `clientlaz/u_main.pas` nicht,
  und ein Interface-Aufruf auf `nil` ist für den Compiler einwandfrei. Der Editor hat
  dieselbe Lage richtig gelöst — sein `ServerLogin` ruft nur `LoginClient` und fasst die
  Verbindung nicht an. Gefunden hat es der Benutzer beim Ausprobieren, nicht der Testlauf.

- **Vier weitere Plattformen** (15.09.): Server, Client und Editor bauen und laufen außerdem
  auf **Windows 11 ARM**, **Windows 10** (x64), **Ubuntu ARM** und **MX Linux** (x64, auf
  Debian aufgesetzt) — überall mit FPC 3.3.1 und Lazarus aus dem Trunk, überall
  einschließlich Anmeldung gegen `token strict` und Editor an einer Datenbank. Die
  Projektdateien tragen keine absoluten Pfade und kein Zielsystem, und nichts davon musste
  für eine der vier angefasst werden.
  Das ist **vom Benutzer auf seinen Maschinen geprüft**, nicht hier gemessen: dieser Rechner
  ist aarch64-darwin, und die Zahlen im Rest dieses Abschnitts stammen von ihm. Zu den
  Toolchains selbst siehe die jeweilige Maschine — auf Windows 11 ARM läuft die
  fpcupdeluxe-Installation emuliert als x86_64 und erzeugt native ARM64-Binaries über das
  Cross-Target `aarch64-win64`, weil FpDebug unter Windows kein ARM64 kann.

## 7. Was offen ist

**Vereinbart, aber nicht begonnen:**

- **Regeln über Feldnamen.** Die `Rules`-Spalte ist gebaut, sie nennt aber Parameter-
  positionen, und ein Record-Schreibvorgang hat keine. Solche Vorlagen werden bis dahin
  abgelehnt statt still nicht geprüft — siehe Abschnitt 6.
- **Ein externer Aussteller.** Heute stellt der Server selbst aus (HS256, GUID beim Start).
  Wenn der `auth`-Dienst ausstellen soll, wird daraus eine Prüfung mit öffentlichem
  Schlüssel: `TJwtES256` statt `TJwtHS256` in `InitTokens`, sonst nichts — mit geteiltem
  Geheimnis könnte jeder, der prüfen darf, auch ausstellen.
- **Die erwartete Ergebnisform** zu `TestBounds`: eine Spalte, gegen die ein Sammellauf
  nicht nur *„ausgeführt"*, sondern *„und das kam heraus"* sagen könnte. Die Werte gibt es
  jetzt, der Soll-Vergleich fehlt.

**Vorgeschlagen, noch nicht entschieden:**

- **Die Wege, die nur im Fenster existieren.** Kein Testlauf erreicht `clientlaz/u_main.pas`
  oder `editor/u_editormain.pas`; der Absturz vom 15.09. lag genau dort. Ein Formular ohne
  Anzeige zu instanzieren und die Klick-Methoden zu rufen wäre machbar, zieht aber die LCL
  in den Testlauf — für eine Demo womöglich mehr Last als Nutzen. Die billigere Hälfte wäre
  eine kurze Liste zum Abhaken vor dem Push: Anmelden mitten im Aufruf, Profil umschalten,
  *Server neu laden*. `docs/SERVER-CLIENT{,-de}.md` beschreibt die Handgriffe schon.

- **„Zeile als Vorlage übernehmen"** beim Insert: eine vorhandene Zeile laden, ein, zwei
  Felder ändern und als neue einfügen. Zwei Fälle sprechen dafür — Duplizieren in der
  Datenpflege, und Fremdschlüssel, die es geben muss (`OrmAddTDtoInvoiceRow` braucht eine
  `CustomerID`, die existiert; der Dialog schlägt sonst `0` vor). Falls gebaut, als
  ausdrücklicher zweiter Griff im Dialog, nicht als Abfrage bei jedem Add. Siehe TODO B2c.
  (Der modale Record-Dialog selbst ist gebaut — die Tippfehler-Falle, vor der hier stand,
  fängt der Dialog jetzt pro Feld ab, statt sie stillschweigend zu `null` zu machen.)

- **Serverseitig erzeugte Feldwerte.** Zwischen „der Record ist da“ und „das Statement
  läuft“ gibt es keinen Haken, an dem der Server ein Feld selbst füllen könnte — ein
  Schlüssel, den der Prozess vergibt und nicht die Datenbank, ein Anlegezeitpunkt, der
  nicht vom Client kommen darf, eine Mandanten-ID aus dem Aufrufer. Die Bauart liegt vor:
  `CallerScope` tut genau das für einen gebundenen Parameter, `ApplyCallerScope` in
  [`src/dom/DomSqlImplementation.pas`](src/dom/DomSqlImplementation.pas) ist die Stelle.
  Eine Spalte `Generator` daneben wäre derselbe Griff für ein Record-Feld: die Spalte, ein
  Zweig in der Domänenschicht, ein Feld im Editor. Ausführlicher unter „Bewusst
  weggelassen“ in [docs/DETAILS-de.md](docs/DETAILS-de.md).

**Bekannte Grenzen:**

- Der Editor testet ein Record-Template jetzt vollständig: *Record-Werte eingeben…* baut den
  Dialog, das JSON läuft durch dasselbe `BindRecordJson` wie im Server, in einer Transaktion,
  die zurückgerollt wird, solange *Rollback* angehakt ist — ohne Haken bleibt die Zeile stehen. Seit der Editor `WriteDtos`
  mitbindet, gilt das auch für die nur im Server einkompilierten Typen; die frühere Grenze
  („nur mit `RecordDecl` testbar") ist damit weg.
- In `src/*/backup/` liegen alte IDE-Kopien, unter anderem eine `ClientDtos.pas` mit einem
  überholten `TDtoCustomer`. Sie stehen auf keinem Suchpfad und sind nicht eingecheckt.

## 8. Einen neuen Schreib-Record hinzufügen

Der ganze Vorgang, weil er die Idee am kürzesten zeigt:

1. Record in [`src/app/WriteDtos.pas`](src/app/WriteDtos.pas) deklarieren und unten in
   `Rtti.RegisterTypes` eintragen. Ohne den zweiten Schritt findet `Rtti.FindName` ihn nicht und
   der Server antwortet `sqlFailed` mit *"unknown record type ... not registered?"* im Log.
   **Oder gar nicht:** stattdessen die Felder in die Spalte `RecordDecl` schreiben
   (`ArtNr: integer; ArtName: RawUtf8; Kind: RawUtf8`), dann kostet der Record keinen Neubau.
   Einkompiliert gewinnt, wenn es beides gibt.
2. Feldnamen = Spaltennamen der Tabelle.
3. Zeile in `templates.sqlite` anlegen, im Editor: Action-Key `OrmAddTDtoXxx` bzw.
   `OrmUpdateTDtoXxx`, Record-Typ `TDtoXxx`, Häkchen bei *SQL beim Aufruf erzeugen*, SQL leer.
   Das `Orm` davor ist Pflicht, nicht Geschmack: ohne die Marke wird der Schlüssel abgelehnt.
4. Im Client aufrufen: `WriteRecord('OrmAddTDtoXxx', rec, TypeInfo(TDtoXxx))`.

Zum Lesen und Löschen genügen zwei weitere Zeilen mit demselben Recordtyp,
`OrmRetrieveTDtoXxx` und `OrmDeleteTDtoXxx`, und im Client
`RetrieveRecord('OrmRetrieveTDtoXxx', key, rec, TypeInfo(TDtoXxx))` bzw.
`DeleteRecord('OrmDeleteTDtoXxx', key)`. Beide schicken nur den Schlüssel.

Für viele Zeilen kommt `OrmListTDtoXxx` dazu: derselbe Recordtyp, dazu die Spalten
*Filter* (`City = ?`, ohne das Wort `where`) und *Sortierung* im Editor. Der Client holt
sie mit dem gewöhnlichen Array-Aufruf
`ParseDynArray('OrmListTDtoXxx', _Arr(['Wegberg']), arr, TypeInfo(TDtoXxxArray))` — die
Werte des Filters kommen vom Aufrufer, seine Form bleibt im Template.

Kein Methodenrumpf, kein Konverter, keine Änderung am Vertrag.
