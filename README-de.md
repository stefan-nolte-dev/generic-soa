# Auf Mormot2 basierend. Eine Art generischer Soa-Service. 

Um Abfragen auszuführen wird kein spezifischer Code auf dem Server benötigt. Lediglich bei den ORM-ähnlichen ist selbstverständlich Code für einen DTO-Typ notwendig. Der Code kann alle DTOs unabhängig vom Typ verarbeiten. Rechtemanagement, Sanity-Regeln und generische Tests verwenden ebenfalls allgemeinen Code. 
<br><br>Clientseitig kann man einen Convenience-DTO-Typ deklarieren (Per Knopfdruck generiert in dem Editor, siehe unten). Dann ist nur noch eine Deklaration einer Variable notwendig und sie kann übergeben werden (plus TypeInfo(...)). Parsen geschieht typunabhängig automatisch. 

*Langfassung mit der vollständigen Messung, dem Editor im Detail und den bekannten Einschränkungen: [docs/DETAILS-de.md](docs/DETAILS-de.md) — in English: [README.md](README.md).*

*Bedienung, Schritt für Schritt: [docs/EDITOR-de.md](docs/EDITOR-de.md) für den
Template-Editor, [docs/SERVER-CLIENT-de.md](docs/SERVER-CLIENT-de.md) für den
Server im Zusammenspiel mit dem Test-Client.*

## Bauen

**mORMot 2 — festgelegt auf das Tag `2.4-stable`.** mORMot ändert sich fast täglich, und ein Teil dieser Änderungen bricht die API. Damit das Projekt bei allen gleich baut, ist hier eine feste Version genannt und kein Zweig:

```bash
git clone --branch 2.4-stable --depth 1 https://github.com/synopse/mORMot2.git
```

Nicht `master`, der bewegt sich unter einem weg. Und nicht `lts-2.3`: dieser Zweig ist vor Änderungen abgezweigt, auf denen das Projekt aufsetzt — `RecordLoadJsonInPlace` etwa gibt es dort nicht.

**Die statischen Bibliotheken** — die vorkompilierten `.o`-Dateien für SQLite3 und die übrigen C-Teile — liegen nicht im mORMot-Repository, `static/*/` ist dort ignoriert. Sie gehören zur Version und müssen zu ihr passen. Dafür liegt im Checkout die Datei `static/dev.sha256`: die Prüfsummen genau der Archive, die zu diesem Stand gehören.

Nicht das Archiv von `https://synopse.info/files/mormot2static.7z` nehmen — das ist immer der neueste Stand, nicht der zum Tag gehörende. Stattdessen unter https://github.com/synopse/mORMot2/releases das Release `2.4-stable` öffnen und das dort beigelegte Archiv laden: unter Linux und macOS `mormot2static.tgz` (kleiner und nativer), unter Windows `mormot2static.7z`. Das Archiv nach `static/` legen, prüfen, entpacken:

```bash
cd <mORMot2>/static
sha256sum -c dev.sha256 --ignore-missing
tar xf mormot2static.tgz        # Windows: 7z x mormot2static.7z
```

Die Prüfung muss `OK` melden. Meldet sie `FAILED`, gehört das Archiv zu einer anderen Version — dann stimmt die Herkunft nicht. Nach dem Entpacken gibt es `static/aarch64-linux/` und die übrigen Zielverzeichnisse; das Lazarus-Package sucht sie von selbst dort.

**Toolchain.** Geprüft mit Lazarus 4.9 und FPC 3.3.1 auf aarch64-linux. Dieselben drei Programme bauen und laufen außerdem auf Windows 11 ARM, Windows 10 (x64), Ubuntu ARM und MX Linux (x64, auf Debian aufgesetzt) — jeweils mit FPC 3.3.1 und Lazarus aus dem Trunk, jeweils Server, Client und Editor, samt Anmeldung mit `token strict` und dem Editor an einer Datenbank. Der Compiler ist die zweite bewegliche Abhängigkeit: Auf dem 2.3-LTS-Stand bricht `mormot.lib.pkcs11` mit diesem FPC im Assembler ab — ein Codegen-Fehler auf aarch64, keiner von mORMot. Mit dem Tag oben tritt er nicht auf.

**Der Bau selbst.** Das mORMot-Package einmal registrieren, danach die drei Projekte:

```bash
lazbuild --add-package-link <mORMot2>/packages/lazarus/mormot2.lpk
lazbuild src/proj/soa_sql_templates_server.lpi
lazbuild src/projeditor/soa_sql_templates_editor.lpi
lazbuild src/projclientlaz/soa_sql_templates_client.lpi
```

Die Hilfe von `lazbuild` schreibt die Option mit Gleichheitszeichen, angenommen wird sie aber nur mit Leerzeichen davor. In der IDE genügt es, `mormot2.lpk` einmal zu öffnen und zu kompilieren; die drei Projekte ziehen das Package dann als Abhängigkeit nach. Die Binaries landen in `bin/`.

**Die Demo-Datenbank.** `bin/demo.sqlite` liegt nicht in der Versionsverwaltung. Der Server legt sie beim ersten Start selbst an — `CreateDemoDatabase` und `CreateBulkDemoTables` in `src/serv/app/ServSqlTemplates.pas`; einmal starten genügt, ein weiteres Werkzeug braucht es dafür nicht. Das gilt auch für den Start aus der IDE ohne Parameter. Dabei zeigt Lazarus die Ausgabe eines Konsolenprogramms unter Linux in `xterm`: Fehlt das Paket, erscheint kein Fenster, obwohl der Server läuft — dann `sudo apt install xterm`, ein anderes Terminalprogramm in den Umgebungseinstellungen der IDE eintragen, oder den Server einfach aus einer Shell starten. Wer stattdessen genau den aufgeschriebenen Stand will, spielt `bin/demo.sql` ein:

```bash
cd bin
sqlite3 demo.sqlite < demo.sql
```

Nur dafür muss `sqlite3` auf dem System sein (Debian/Ubuntu: `sudo apt install sqlite3`). Ohne das Kommandozeilenwerkzeug tut es auch Python, das SQLite mitbringt:

```bash
cd bin
python3 -c "import sqlite3,io; sqlite3.connect('demo.sqlite').executescript(io.open('demo.sql',encoding='utf-8').read())"
```

SQLite als Systembibliothek wird dagegen nirgends gebraucht: die Programme binden es über `mormot.db.raw.sqlite3.static` aus den statischen Bibliotheken von oben fest ein.

## Idee
Statt Abfragen in Code zu implementieren, werden einfach Informationen zu Abfragen in einer kleinen SQLite-DB gespeichert. Pro Service könnte man eine Tabelle pflegen. Zum Hinzufügen, Bearbeiten, Testen etc. gibt es einen Editor, siehe unten.<br><br>
Die Tabelle enthält folgende Spalten: <br>
1. ActionKey | key<br> 
2. Sql | SQL-Template (entfällt für das Updaten und Hinzufügen ganzer DTOs)<br>
3.ParamTypes | Braucht man für generische Tests<br> 
4. RecordType | Für RTTI bei ORM-ähnlichen Operationen <br>
5. RecordDecl | Die Felder dieses Records als Text, wenn der Typ nicht im Server einkompiliert ist<br>
6. KeyField | Die Schlüsselspalte eines erzeugten Statements. Leer heißt ID<br>
7. ReadGroups | Rechte als Integer <br>
8. WriteGroups | Rechte als Integer<br>
9. Rules | Benannte Sanity-Regeln, zugewiesen je Parameterposition - `2:plz;3:email`. Je Feldname ist noch offen.<br>
10. TestBounds | Beispielwerte für einen generischen Testlauf - `["Wegberg"]`, oder das JSON des Records. Die erwartete Ergebnisform ist noch offen.<br>
11. CallerScope | `userid`: den letzten Parameter bindet der Server selbst mit der ID des Aufrufers, der Client schickt dafür keinen Wert<br>
... etc ...<br><br>
Zur Laufzeit werden die Einträge wegen schnellerer Verarbeitung in ein TSynDictionary geladen. Die Einträge werden bei Bedarf als Parameter den bestehenden Methoden übergeben. Für spezifische Abfragen existiert kein Code, sondern nur für die generelle Logik. Dank Mormot benötigt die gesamte Logik relativ wenige Zeilen.
# Server


## Drei Schichten: App, Dom, Infra.
Die Schichten kompilieren unabhängig voneinander. Änderungen in der Implementation einer Schicht beeinflussen die anderen Schichten nicht.
## App
In App werden HTTP-Aufgaben erledigt wie Daten Empfangen/Senden und extrahieren des Payload des HTTP-Header-Tokens. Weiterleitung nach Dom über ein Interface aus Dom.
## Dom
Hier Rechteprüfung (Eingeloggt und spezifische Rechte), Lesen des Dictionarys, in dem die Tabelle aus templates.sqlite geladen ist. Der Value des Action-Keys wird in ein TSqlRec geladen. Der TSqlRec enthält die Werte der ausgewählten Zeile. 
## Infra
Hier bei ORM-entsprechendem Add oder Update eines kompletten DTOs die Generierung des Statements mit allen notwendigen Werten und Typen. Bei SQL ausführen des Statements aus dem TSqlRec. 
# Client
Ein einfacher Testclient. Demonstriert Aufruf und das clientseitige Parsing.
# Editor
Hier können neue Einträge vorgenommen werden und bestehende bearbeitet werden. Bisher implementiert: verbinden mit Datenbank, testen von SQL, Darstellen des Ergebnisses als Json, oder Tabelle. Generieren eines passenden Pascal-TDTO aus dem Json-Ergebnisarray. Dieser kann per Copy-Paste im Client verwendet werden. Neukompilieren, Deklarieren einer Variablen des Typs und direkte Verwendung weil der Aufruf keinen bestimmten Typ erfordert. Es wird aber automatisch in den bestimmten Typ zurückgeparst. Dazu: Record-Werte in einem Formular eingeben, jedes Template über den Server ausführen statt direkt — wie ein Client es täte, mit Rechtemaske und Regeln — und den ganzen Satz in einem Lauf prüfen. Die Handgriffe stehen in [docs/EDITOR-de.md](docs/EDITOR-de.md).

# Lizenz
Die Dateien in diesem Repository stehen unter der MIT-Lizenz, siehe
[LICENSE](LICENSE). Mormot2 gehört nicht dazu: es wird separat geholt (siehe
*Toolchain*) und trägt seine eigene Lizenz, MPL 1.1 / GPL 2.0 / LGPL 2.1 nach
Wahl des Nutzers.
