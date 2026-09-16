# SQL-Templates als SOA-Dienst — die Langfassung

> Der kurze Überblick steht in [README-de.md](../README-de.md). Hier dasselbe
> ausführlich: die vollständige Messung, der Editor, deklarierte
> Parametertypen, die Rechtemaske, und was bewusst weggelassen wurde.

Ein mORMot-2-Beispiel: statt einer Interface-Methode je Abfrage deklariert der
Dienst insgesamt, für alle Abfragen, nur **zwei**. Die jeweiligen Abfragen werden durch einen Parameter benannt. Dieser Parameter dient serverseitig als Schlüssel bzw. Index, um die gewünschte Abfrage auszuwählen und auszuführen.

```pascal
IAppSqlTool = interface(IInvokable)
  function GetJsonFromAction(const Action: RawUtf8; const Bounds: variant;
    var Json: RawUtf8): TSqlStatus;
  function WriteDataForAction(const Action: RawUtf8;
    const Bounds: variant): TSqlStatus;
  ...
end;
```

`Action` ist ein Schlüssel in der Registry. Die Werte sind Records, die neben SQL-Templates auch Codes für Rechte, Regeln etc. enthalten. Eine
Abfrage hinzuzufügen heißt: eine Anweisung (als Teil eines Records) und einen Schlüssel eintragen. Keine Erweiterung der Api für jede neue Abfrage, keine weitere Interface-Methode, kein Implementierungsrumpf, kein DTO auf dem Server, keine Änderung (wie Konvertierungen von Typen etc.) in irgendeiner Schicht dazwischen. Und auch keine ORM-Ausführung bzw. neu konstruiertes SQL im Pascal-Code. 

## Was aufgegeben wird, was bleibt

Aufgegeben wird die typisierte Signatur: der Compiler prüft nicht mehr, ob ein
Aufrufer für eine bestimmte Abfrage die richtige Zahl und Art von Parametern
übergibt (Allerdings kann dies nur Laufzeit ergänzt werden und ein dezidierter Rückgabewert gegeben werden). 

Erhalten bleibt das typisierte **Ergebnis** im Client. Der Client übergibt die RTTI des Typs
, den er möchte, und bekommt genau diesen typisierten Pascal-Objekt-Array zurück. Der folgende Code funktioniert für alle Typen. Statt wie im Beispiel 'TDtoCustomerArray' kann beim Aufruf entsprechend ein anderer Typ eingesetzt werden.

```pascal
Customers := nil;
status := ParseDynArray('GetCustomersByCity', _Arr(['Wegberg']),
  Customers, TypeInfo(TDtoCustomerArray));
// Customers[0].City — ein Record, den der Server nie gesehen hat
```

Das gilt fürs Lesen, worum es hier hauptsächlich geht. Für das Schreiben eines
ganzen Records gilt es nicht, und es kann nicht gelten — siehe *Einen ganzen
Record schreiben* weiter unten.

`ParseDynArray` hat 16 Zeilen, wird einmal geschrieben und bedient jede
Abfrage, die der Server je anbieten wird — dieselbe Aufrufform für jeden
Action-Key und jede Zeilenform. `ClientTests` zeigt das an zwei Records, die
nichts miteinander zu tun haben, `TDtoCustomer` und `TDtoTurnover`; jeder
Block nennt den Typ, in den geparst wurde. Das DTO existiert nur im Client.
Nichts muss über App-, Domain- und Persistenzschicht gespiegelt werden, und es
gibt keine Konverter, die zwischen diesen Fassungen Feld für Feld kopieren.

Das ist kein Ersatz für interface-basiertes SOA. Es zielt auf den Teil einer
Anwendung, den das ORM nicht erreicht: Auswertungen, Aggregate, Joins mit
Bedingung auf dem Aggregat — die Abfragen, die ohnehin als handgeschriebenes
SQL enden. Der Tausch ist bewusst, und sein Geltungsbereich auch.

## Was das kostet, gemessen

Verglichen wird mit einer produktiven, typisierten mORMot-Anwendung —
nachfolgend *der typisierte Dienst* — an einer Abfrage, die es in beiden Welten
gibt: eine Nachschlagetabelle liefern — ein Select über zwei Spalten, ohne
Parameter. Dort eine Kategorie-Nachschlagetabelle, hier `GetAllCustomers`.

Gezählt sind nur produktive Zeilen: keine Leerzeilen, keine Kommentare, keine
Tests.

Server und Client werden **getrennt gezählt**, denn strittig ist nur eine der
beiden Seiten. Ein Aufrufer will so oder so ein Pascal-Array von Records, der
Record muss also so oder so existieren. Der Unterschied liegt darin, worum der
Server wachsen muss, um eine Frage mehr zu beantworten.

### Was der Server je Abfrage kostet

**Der konventionelle Weg — eine Methode je Abfrage**

| was | Zeilen | wo |
|---|---:|---|
| Domain-Persistenz-Interface, Deklaration | 1 | Domain-Schicht, Persistenz-Unit |
| Persistenzklasse, Deklaration | 1 | Infra-Schicht, SQLite-Unit |
| Persistenz-Rumpf: Statement und Zeilenschleife | 21 | Infra-Schicht, SQLite-Unit |
| Domain-DTO, sein Array und seine RTTI-Registrierung | 7 | App-Schicht, DTO-Unit |
| Service-Interface, Deklaration | 1 | App-Schicht, Service-Unit |
| Service-Klasse, Deklaration | 1 | App-Schicht, Service-Implementierung |
| Service-Rumpf: Feld für Feld in das zweite DTO kopieren | 17 | App-Schicht, Service-Implementierung |
| **Summe** | **49** | **5 Dateien** |

**Der Action-Key**

| was | Zeilen | Datei |
|---|---:|---|
| die Anweisung und ihr Schlüssel | 0 | eine Zeile in `templates.sqlite` |
| **Summe** | **0** | **überhaupt kein Pascal** |

**49 gegen nichts.** Kein Neubau, kein Neustart, und der laufende Server nimmt
den Schlüssel von selbst an. Hier stand einmal eine zweite Spalte für eine
Variante mit einkompilierten Anweisungen — drei Zeilen in zwei Dateien —, und
die ist bewusst entfallen: zwei Herkünfte für dieselbe Anweisung laufen
auseinander, und diese hier ist die Herkunft.

Der Abstand wächst mit der Zeilenbreite. Jede weitere Spalte kostet den
konventionellen Weg zwei Kopierzeilen — einmal aus dem Ergebnis heraus, einmal
zwischen den DTOs — plus je ein Feld in beiden Records. Auf der Action-Key-Seite
kostet eine weitere Spalte im Server überhaupt nichts: sie steht schon im
Statement.

### Was der Client je Zeilenform kostet

| | Zeilen | wo |
|---|---:|---|
| konventionell | 7 | App-Schicht, DTO-Unit, mit dem Server geteilt |
| Action-Key | 5 | `src/client/ClientDtos.pas`, nur im Client |

Die beiden sind fast gleich, und genau das ist der Punkt: diese Arbeit fällt in
beiden Welten an, sie gehört also nicht in den Vergleich darüber. Die zwei
Zeilen Unterschied sind der `RegisterFromText`-Aufruf, den dieses Beispiel nicht
mehr braucht (siehe den Typgenerator des Editors), während der typisierte Dienst
je DTO einen davon trägt.

Auf den Ort lohnt aber ein Blick. Dort liegt der Record im App-Layer, wird in
den Server einkompiliert und reist durch den Dienstvertrag; dieselben Daten gibt
es eine Schicht tiefer ein zweites Mal, mit einem Konverter dazwischen. Hier
gibt es sie einmal, im Client, und der Server hat nie von ihnen gehört.

### Im Maßstab einer ganzen Anwendung

In dem typisierten Dienst heute:

- **50 Methoden** in den Interfaces des App-Layers (26 und 24 in zwei
  Interfaces). Jede existiert noch einmal im Domain-Interface und noch einmal
  in zwei Implementierungsklassen.
- **32 DTO-Records** und **33 RTTI-Registrierungen** in einer einzigen Unit —
  die Anwendungs- und die Domain-Fassung derselben Daten nebeneinander.
- **134 Zeilen** in der Service-Implementierung, die nichts tun, als ein Feld
  des einen Records in den Record der nächsten Schicht zu kopieren. Der größte
  einzelne Konverter hat **174 Zeilen**.

Dem gegenüber steht alles, was dieses Beispiel im Server braucht — Registry,
beide Loader, Ausführung, App-Layer, Vertrag, Start —, zusammen **1109
Zeilen**, davon **1058 Festkosten**: einmal bezahlt und unverändert, wenn eine
Abfrage hinzukommt.

**Was der Vergleich nicht behauptet.** Die Rümpfe dort tun etwas mehr als holen: sie gehen über das ORM und tragen eine Umschaltung zwischen eingebetteter
und entfernter Persistenz. Die ORM-Klassen sind nicht gezählt, da das Schema
ohnehin gebraucht wird. Die 3327 Zeilen Testcode des typisierten Dienstes bleiben auf
beiden Seiten außen vor — sie sind nur genannt, weil ihre Pflege der teuerste
Teil war und weil auch sie je Methode geschrieben werden.

Und was der konventionelle Weg für seine 49 Zeilen kauft, ist eine vom Compiler
geprüfte Parameterliste. Genau der oben beschriebene Tausch, hier mit Preis.

## Aufbau

```
src/common/     SqlStatus.pas               die Aufzählung TSqlStatus
                SqlParamTypes.pas           deklarierte Parametertypen, Umwandlung
src/commonserv/ SqlTemplateTypes.pas        TSqlRec - der Typ, nichts was darauf handelt
src/app/        AppSqlServices.pas          der Dienstvertrag nach außen
                WriteDtos.pas               die Records, die BEIDE Seiten brauchen
                AppCallerToken.pas          JWT aus dem Header -> TSqlCaller
                AppSqlImplementation.pas    der HTTP-Rand: weiterreichen, sonst nichts
src/dom/        DomSqlServices.pas          was die App-Schicht von hier braucht
                DomSqlImplementation.pas    auflösen, Rechte, Regeln - die Entscheidungen
                SqlTemplateRegistry.pas     Action-Key -> TSqlRec
src/infra/      InfraSqlServices.pas        was die Schicht darüber von hier braucht
                InfraSqlImplementation.pas  einzige Stelle, die SQL ausführt
                SqlRecordBind.pas           ein Record -> Anweisung und gebundene Werte
                SqlTemplatesFromDb.pas      die einzige Quelle: eine Template-Datei
src/serv/app/   ServSqlTemplates.pas        Start — sieht alles
src/client/     ClientDtos.pas              nur Lese-Records, nur clientseitig
                AppSqlClient.pas            Verbindung
                u_client_parsing.pas        ParseDynArray, WriteRecord
src/clienttests/ ClientTests.pas            der Machbarkeitsnachweis
src/clientlaz/  u_main.pas / .lfm           ein Knopf, ein Memo
src/editor/     EditorDb.pas                die eigene Verbindung des Editors
                SqlBounds.pas               typisierte Parameter und Einsetzen
                EditorExec.pas              ausführen und zurückrollen
                TemplateStore.pas           templates.sqlite, öffnen und schließen
                DtoCodeGen.pas              Ergebnis -> Record-Deklaration
                u_editormain.pas / .lfm     das Editorfenster
```

### Drei Schichten, eine Aufgabe je Schicht

| Schicht | tut | weiß nichts von |
|---|---|---|
| App | Token aus dem HTTP-Header holen, `TSqlCaller` bauen, weiterreichen | Templates, Rechten, SQL |
| Dom | Action auflösen (ggf. neu laden), Rechte prüfen, Sanity-Regeln | HTTP, Verbindungen, SQL |
| Infra | Werte angleichen, SQL erzeugen oder füllen, binden, ausführen | wer fragt, ob er darf |

Ein Aufruf läuft in dieser Reihenfolge durch `TDomSqlTool.Resolve`:
eingeloggt → Action vorhanden → Rechte gegen die *konkrete* Action → Regeln.
Der Login-Check steht zuerst, weil sonst ein beliebiger Aufrufer den Reload
darunter auslösen könnte.

Was über die Grenze geht, ist nicht die Sitzung, sondern ein `TSqlCaller`: ein
schlichter Record aus Benutzer, Name und Gruppenmaske. Unterhalb der
App-Schicht weiß nichts mehr, dass es eine HTTP-Anfrage, einen Header oder ein
Token gibt — die Rechteprüfung lässt sich damit prüfen, indem man einen Record
ausfüllt, statt eine Sitzung nachzustellen.

### Sichtbarkeit

Die Ordner sind das, was jedes Projekt auf seinen Unit-Suchpfad setzt:

| Projekt | sieht |
|---|---|
| Client | `common`, `app`, `client`, `clienttests`, `clientlaz` |
| Server | `common`, `commonserv`, `infra`, `dom`, `app`, `serv/app` |
| Editor | `common`, `commonserv`, `infra`, `dom`, `app`, `client`, `editor` |

Der Suchpfad ist aber nur die grobe Zusage. Die genaue steht in den
uses-Klauseln, und zwei Aufteilungen sind allein dafür da:

- **`TSqlRec` wohnt nicht bei der Registry.** Der Typ steht in
  `commonserv/SqlTemplateTypes.pas`, die Registry in
  `dom/SqlTemplateRegistry.pas`. Die Infrastrukturschicht bekommt ein Template
  gereicht und kann keins nachschlagen — nachzulesen in der uses-Klausel von
  `InfraSqlImplementation`, die `SqlTemplateTypes` nennt und die Registry nicht.
- **Profiltabelle und Verbindung liegen in verschiedenen Ordnern.** In
  `common/SqlProfiles.pas` stehen Namen, Ports und Dateinamen, weil Server,
  Client und Editor sie alle drei lesen und nicht auseinanderlaufen dürfen,
  was `mssql` bedeutet. In `commonserv/SqlServerConn.pas` stehen Host,
  Treiber und Verbindungszeichenfolge, weil der Editor sie braucht und ein
  Client keinen Hostnamen in seinem Kompilat mit sich herumtragen muss.
  `SqlProfiles` nennt den Datenbanknamen und sonst nichts.
- **`WriteDtos` steht in keiner uses-Klausel unterhalb von `app`.** Der
  Recordtyp wird zur Laufzeit über `Rtti.FindName` an seinem Namen aus der
  Spalte `RecordType` gefunden; bekannt gemacht wird er von der
  `initialization` in `WriteDtos`, die allein der Starter hereinzieht. Wer
  einwendet, die Infrastrukturschicht sähe hier Anwendungstypen: sie sieht
  einen String und ein `PRttiInfo`. Nimm `app` aus ihrem Suchpfad, sie baut.

Eine ehrliche Einschränkung bleibt: der Ordner ist ein grobes Werkzeug. In
`app` liegt der Vertrag, den der Client sehen muss, und die Implementierung,
die er nicht sehen muss — ein Suchpfad kann beides nicht auseinanderhalten.
Was einen Client von `AppSqlImplementation` fernhält, ist dessen uses-Klausel.

Und die Durchsetzung selbst ist nur so gut wie die Suchpfade: es gibt keinen
Compilerzwang, jedes Projekt trägt seine eigene Liste. Was das prüfbar macht,
ist ein Bau je Schicht mit abgeschnittenem Pfad — Infra mit
`common commonserv infra`, App mit `common commonserv dom app` und ohne
`infra`. Nicht das Diagramm zeigt die Trennung, sondern dieser Bau.

## Bauen

```
lazbuild src/proj/soa_sql_templates_server.lpi
lazbuild src/projclientlaz/soa_sql_templates_client.lpi
lazbuild src/projeditor/soa_sql_templates_editor.lpi
```

Beides landet in `bin/`. Die Demo-Datenbank `demo.sqlite` wird beim ersten
Start angelegt und gefüllt; zum Zurücksetzen einfach löschen. Maßgeblich ist
der Code, der sie füllt — `bin/demo.sql` ist derselbe Stand als Skript, lesbar
im Diff und mit `sqlite3 demo.sqlite < demo.sql` wieder einspielbar.

## Starten

Die Templates kommen aus einer Template-Datei neben dem Programm, und aus
keiner anderen Quelle — keine Anweisung dieser Anwendung ist einkompiliert.
Welche Datei, entscheidet das Profil; ohne Argument ist es das Demo:

```
./soa_sql_templates_server
```

Danach den Client starten und den Knopf drücken.

`templates.sqlite` und ihr Textexport `templates.sql` liegen beide in der
Versionsverwaltung. Fehlt die binäre Datei einmal, baut der Server sie beim
Start aus dem Export wieder auf: der trägt sein eigenes `create table` und ist
ein gewöhnliches SQL-Skript, `sqlite3 templates.sqlite < templates.sql` tut
von Hand dasselbe. Fehlt beides, startet der Dienst nicht und nennt die zwei
Dateien, nach denen er gesucht hat — besser, als einen leeren Satz zu
bedienen.

### Eine Datenbank je Dienst

Ein Dienst spricht mit einer Datenbank, und die Templates dieser Datenbank
liegen in einer Datei daneben. Zwei Datenbanken sind zwei Dienste, zwei
Template-Dateien, zwei Historien — das hält auch den Merge klein. Das Beispiel
bringt zwei Profile mit, benannt auf der Kommandozeile:

```
./soa_sql_templates_server          # demo:   templates.sqlite -> demo.sqlite
./soa_sql_templates_server mssql   # mssql: templates_mssql.sqlite -> SoaSample
```

Ein Profil entscheidet zwei Dinge und sonst nichts: welche Verbindung und
welche Datei. `Props` ist eine `TSqlDBConnectionProperties`, also kann keine
Schicht unterhalb der Startunit SQLite von SQL Server unterscheiden — und die
Action-Keys des einen Profils sind im anderen schlicht unbekannt. Ein Profil
hinzuzufügen ist ein Zweig in `StartServer` und eine zweite Template-Datei;
sonst bewegt sich nichts.

Das Profil `mssql` verbindet sich über unixODBC mit dem SQL Server und
authentifiziert sich mit Kerberos — `Trusted_Connection=yes`, also steht kein
Kennwort im Quelltext, in der Umgebung oder in einer Konfigurationsdatei. Es
braucht ein Ticket (`kinit`), einen Weg zum Server und — gegen einen Server,
der nur TLS 1.0 anbietet — `openssl-tls1.cnf` neben der Programmdatei. Die vier
macOS-Eigenheiten stehen als Kommentar in `src/commonserv/SqlServerConn.pas` —
in `commonserv`, weil der Editor sich mit demselben Server verbindet und ein
Client keinen Hostnamen kennen muss.

Beide Server dürfen gleichzeitig laufen: jedes Profil hat seinen eigenen Port
(8890 und 8891). Client und Editor haben je ein Auswahlfeld *Profil* — der
Client wechselt den Port und holt die Schlüsselliste über `AvailableActions`,
der Editor wechselt Template-Datei und Zieldatenbank zusammen.

## Eine Abfrage ohne Neubau hinzufügen

Bei laufendem Server:

```sh
sqlite3 bin/templates.sqlite \
  "insert into SqlTemplate (ActionKey, Sql) values \
   ('GetCustomerCount', 'select count(*) as Anzahl from Customer;');"

curl -s -X POST \
  http://127.0.0.1:8890/sqltemplates/AppSqlTool.ReloadTemplates -d '[]'
```

Der Schlüssel antwortet unmittelbar danach — ohne Neustart, ohne Neubau.

Für einen *neuen* Schlüssel braucht es das ausdrückliche Nachladen gar nicht:
bevor der Server einen unbekannten Schlüssel abweist, fragt er die Quelle, ob
sich die Datei geändert hat, und liest sie dann neu. `ReloadTemplates` bleibt
für den anderen Fall — eine **geänderte** Anweisung unter einem Schlüssel, den
der Server schon kennt.

Die Tabelle wird beim Start gelesen, bei `ReloadTemplates`, und bei einem
unbekannten Action-Key, falls sich die Datei seither geändert hat — nie
pro Anfrage: ein Nachschlagen je Aufruf würde jeder Anfrage eine
Datenbankabfrage hinzufügen und hieße, dass sich die Templates eines laufenden
Servers unter ihm ändern können.

Ein Nachladen baut den neuen Bestand vollständig auf und prüft ihn, bevor der
laufende ersetzt wird. Ein Bestand mit doppeltem Schlüssel, leerem Schlüssel
oder leerer Anweisung wird abgelehnt, `ReloadTemplates` liefert `sqlFailed`,
und der Server bedient weiter, was er vorher bediente.

## Der Template-Editor

Ein drittes Programm, `soa_sql_templates_editor`, bearbeitet eine
Template-Datei, testet ein Statement und schreibt die Record-Deklaration,
die das Ergebnis aufnimmt. Es ist ein Entwicklerwerkzeug und gehört nicht
neben den Client auf einen Arbeitsplatz.

Welche Template-Datei, entscheidet das Profilfeld — und es setzt im selben
Zug die Zieldatenbank: `demo` heißt `templates.sqlite` gegen `demo.sqlite`,
`mssql` heißt `templates_mssql.sqlite` gegen die SQL-Server-Datenbank über ODBC.
Die beiden gehören zusammen; die Templates des einen Profils gegen die Datenbank
des anderen zu bearbeiten ist genau der Fehler, den das verhindert. Beim
Umschalten wird eine bestehende Verbindung getrennt, denn sie gehörte zur
anderen Datenbank.

Es hat seine eigene Verbindung zur Datenbank — seine eigene, nicht die des
Servers: der Editor spricht mit dem SQL Server, ohne dass ein Server läuft, und
braucht dafür einen Weg dorthin und ein Ticket, nicht einen Prozess auf Port
8891. Das Profil
belegt diese Verbindung vor, die oberste Zeile kann sie überschreiben, in einer
von zwei Formen: eine SQLite-Datei oder eine vollständige
ODBC-Verbindungszeichenfolge. Derselbe Editor arbeitet damit gegen dieses
Beispiel und gegen den SQL Server, denn darunter liegt dieselbe
`TSqlDBConnectionProperties` wie im Server.

Treiberfeld und Profilfeld ziehen einander nach, in beide Richtungen: die
Profiltabelle sagt, welchen Treiber ein Ziel braucht, also wählt ein Treiber
das Profil, das auf ihm läuft, und Ziel und Template-Datei kommen mit. Getrennt
können die beiden auseinanderlaufen, und genau diese eine Kombination — eine
ODBC-Verbindungszeichenfolge mit einem SQLite-Pfad als Ziel — bleibt im Treiber
hängen, statt zu scheitern. Aus demselben Grund gibt es den Eintrag
ODBC-Datenquelle nicht mehr: ein DSN ist ein Name, den unixODBC in einer Datei
nachschlägt, die dieses Beispiel nicht mitbringt, und ein Treiber, der ihn
nicht findet, wartet, statt es zu sagen.

Über der Schlüsselliste steht ein Suchfeld. Es filtert die Liste, während man
tippt, ohne Rücksicht auf Groß- und Kleinschreibung und an jeder Stelle des
Schlüssels. Dreißig Namen passen noch auf den Schirm, ein gewachsener Satz
nicht mehr, und für einen Namen zu scrollen ist genau das, was das Feld
erspart. Bezahlt wird es damit, dass eine Zeile nicht mehr das n-te Template
ist, sobald etwas ausgeblendet sein kann — jede Zeile trägt deshalb ihre
Position mit sich, statt gezählt zu werden.

**Getestet wird nicht über den Server.** Der Server hat keine Methode, die
unregistriertes SQL ausführt, und ihm eine zu geben würde die Eigenschaft
zerstören, auf der das Beispiel beruht. Der Editor führt das Statement also
selbst aus — aber mit `TSqlTemplateExec`, dem Ausführungscode des Servers,
über einen ad hoc gebauten `TSqlRec`. Was hier getestet wird, ist das, was
dort laufen wird, bis hinunter zum JSON.

**Ein Test verändert keine Daten, solange das Feld *Rollback* angehakt ist —
und es ist angehakt, bis jemand den Haken entfernt.** Eine Wegwerfkopie der
Datenbank gibt es hier nicht, weil es sie gegen den SQL Server nicht geben
könnte. Was schützt, ist die Transaktion: ein Schreib-Statement läuft darin
und wird auf jedem Weg aus `EditorExec` heraus zurückgerollt — auf jedem außer
dem einen, den das Feld öffnet. Das deckt insert, update und delete ab.

Ohne Haken bleibt ein durchgelaufenes Schreib-Statement stehen, und genau
darum geht es: manches lässt sich nur beurteilen, wenn man die Zeile mit
etwas anderem ansieht. Der Schalter ist mit Absicht schwer zu übersehen — die
Titelleiste trägt `ROLLBACK AUS`, solange er aus ist, das Log sagt es beim
Umschalten, und die Meldung des Laufs sagt `COMMITTED` statt des gewohnten
*„rolled back"*. Zwei Dinge committen weiterhin nie: ein gescheitertes
Statement und ein Lauf, der eine Ausnahme geworfen hat — ein Commit, der
selbst scheitert, endet als Rollback. Die Vorgabe von `TWriteEnd` ist
`weRollback`; ein Aufrufer, der nichts sagt, bekommt also das alte Verhalten,
und das Feld im Editor ist das Einzige im Beispiel, das je etwas anderes
sagt.

Damit gehört die Frage, was als Schreibvorgang gilt, zum Schutz und ist keine
Frage der Anzeige. Ein CTE ist keine Statement-Art: `with x as (...) delete
from x` ist genauso gültig wie das Select, das einem `with` gewöhnlich folgt —
als Select eingestuft liefe es außerhalb der Transaktion und würde committen.
Das erste Wort kann das nicht entscheiden, also entscheidet es der übrige
Text: steht irgendwo außerhalb eines Stringliterals ein Schreibverb, gilt das
Ganze als Schreibvorgang. Ein Alias, der bloß wie `update` klingt, kostet die
Zeilenanzeige; die Verwechslung in die andere Richtung kostet Daten. Es deckt nicht alles ab — DDL ist nicht
auf jeder Engine transaktional, Identity- und Sequenzzähler laufen nicht
zurück, und ein Trigger mit Wirkung außerhalb der Datenbank ist außer
Reichweite. Den Editor auf eine Entwicklungsdatenbank richten.

| Knopf | was er tut |
|---|---|
| Record-Werte eingeben… | bei einem `OrmAdd…`/`OrmUpdate…`-Schlüssel: ein Dialog aus den Feldern seines Recordtyps — beim Update gefüllt aus der Zeile, die der Schlüssel nennt — und der entstandene Record durch die Bindung des Servers, in derselben Transaktion, deren Ende das Feld *Rollback* bestimmt |
| Prüfen | die Prüfungen ohne Datenbank: Zahl der Parameter gegen die `?` im Statement (die in Stringliteralen zählen nicht mit), ein `where` in jedem update und delete, gleich wo das Verb steht — nach einem CTE steht es in der Mitte, und gerade dort rutscht ein fehlendes `where` am ehesten durch —, ein erkennbares erstes Schlüsselwort — danach der ganze Satz durch `TSqlTemplateRegistry.Reload`, dieselbe Prüfung, die der Server bei `ReloadTemplates` anwendet. Was der Editor annimmt, nimmt der Server an. |
| Testen | führt aus, auf dem Pfad, den die Checkbox wählt. Steht im SQL-Feld nichts und ist ein Record-Typ genannt, gibt es einen dritten: der Satz geht mit leerem Statement nach unten und der Code des Servers erzeugt es — `SelectJson` bei einem `OrmRetrieve…`, `Execute` bei einem `OrmDelete…` —, der eine gebundene Wert ist der Schlüssel. Die Art steht am Action-Key, denn einen Text, an dem man sie ablesen könnte, gibt es noch nicht. Selects erscheinen als JSON - lesbar aufbereitet oder genau so, wie es über die Leitung geht - und als generisch aufgebaute Tabelle; Schreibvorgänge werden zurückgerollt, solange das Feld *Rollback* angehakt ist — ohne Haken werden sie committet, und die Meldung sagt es. Die `?` werden gezählt, bevor ein Treiber angefasst wird: ein fehlender Wert ist bei SQLite ein NULL und keine Zeile, bei ODBC eine Ausnahme ohne abfragbaren Grund — die Zahl ist der Grund. Ein Fehlschlag trägt die Worte des Treibers selbst — den Grund, den Infra auf dem Weg nach draußen abgelegt hat, oder `Connection.LastErrorMessage` für ein Statement, das der Treiber rundheraus abgelehnt hat —, statt eines Verweises auf ein Protokoll, das man nicht sieht, und holt die Meldungen nach vorn, statt einen leeren JSON-Reiter stehen zu lassen. |
| aus Parametern übernehmen | füllt `ParamTypes` aus den Typen, die für die Testwerte schon gewählt wurden — Deklaration und Werte können dann nicht auseinanderlaufen. Solange das Feld leer ist, füllt es sich von selbst; der Knopf überschreibt |
| Typ aus Ergebnis erzeugen | der Record und sein Array, fertig zum Einfügen in `ClientDtos.pas` |
| In die Zwischenablage | dieser Quelltext, in der Zwischenablage |
| Speichern / Löschen | ein Template in `templates.sqlite`, und gleich danach `templates.sql` neu — die lesbare Hälfte einer Binärdatei kann nicht zurückfallen, wenn sich niemand an sie erinnern muss. Einen Export-Knopf gibt es nicht: neben *Speichern* liest er sich wie ein Schritt, den *Speichern* nicht tut |
| Server neu laden | `ReloadTemplates` auf einem laufenden Server — der neue Key antwortet ohne Neustart |

### Parameter haben angegebene Typen

Die Werte werden nicht danach typisiert, wie ihr Text aussieht. Jeder wird mit
einem Typ aus dem Auswahlfeld eingegeben und einzeln an die Liste angehängt:

```
[text] Wegberg
[int] 500
[date] 2026-08-30
[null]
```

Diese Liste ist zugleich die Anzeige und, für den, der lieber tippt, die
Eingabe. Eine Zeile ohne Klammern gilt als `[text]`.

Die acht Typen sind keine Geschmacksfrage. `Bounds` ist im Dienstvertrag ein
`variant`, und mORMots `VariantToVarRec` verpackt jeden Wert nur als
`vtVariant` *als Referenz*; das offene Array, das `Bind` bekommt, ist also eine
Liste von Variant-Referenzen, und `BindVariant` entscheidet nach dem VType des
**Variants** — `varDate` zu `BindDateTime`, `varCurrency` zu `BindCurrency`.
Die Liste ist genau das, was `BindVariant` unterscheidet; alles andere wäre
eine Fiktion.

Neben der Liste steht das JSON, zu dem diese Werte werden. Das ist es, was ein
Client tatsächlich auf die Leitung gibt, und es lohnt den Blick, denn JSON
kennt nur null, bool, Zahl und Text. Ein `[date]` reist als Zeichenkette und
wird drüben als Zeichenkette gebunden — deshalb liest „Prüfen" das JSON mit
`JSON_FAST_FLOAT` wieder ein, also mit dem, was `TInterfaceFactory` für ein
Variant-Argument einstellt, und nennt jeden Parameter, dessen Typ sich
unterwegs ändern würde. Das ist die Auswertung des Servers selbst, keine
Nachbildung davon.

### Die Gegenprobe

Den Ausführungscode des Servers zu teilen bringt Treue und kostet Blindheit:
läge der Fehler in der Bindung — ein Wert, der nie ankommt, eine Reihenfolge,
die still danebengeht —, würde der Editor ihn getreu nachvollziehen und Erfolg
melden. Nichts an einem geteilten Pfad kann einen Fehler im geteilten Pfad
zeigen.

Dafür ist die Checkbox **Gegenprobe** da. Sie schreibt die Werte als
SQL-Literale in die Anweisung und bindet nichts, sodass die beiden Läufe an
keiner Stelle denselben Code benutzen, an der der Fehler sitzen könnte.
Gleiches Ergebnis heißt: die Bindung hat geliefert, was das Literal sagt.
Unterschiedliches Ergebnis sagt, wo zu suchen ist.

Drei Dinge verspricht sie nicht. Die Literal-Erzeugung kann selbst falsch sein,
was einen Fehlalarm gibt — die harmlose Richtung, aber keine kostenlose. Datum
und Fließkomma gehen als Literal nicht unbedingt bitgleich hin und zurück, ein
Unterschied ist also ein Anlass hinzusehen und kein Urteil. Und dieser Pfad
baut SQL durch Verkettung zusammen, genau das, wofür es die Registry gibt: er
bleibt im Editor, auf einer Entwicklungsdatenbank, und darf nie vom Server aus
erreichbar werden.

### Der erzeugte Typ

Die Feldtypen leitet der Generator aus dem zurückgekommenen JSON ab, nicht aus
dem Datenbankschema. Das ist Absicht: SQLite meldet für einen Ausdruck wie
`count(i.ID)` vor der ersten gelesenen Zeile nichts Brauchbares, und der
Record muss ohnehin zu dem passen, was über die Leitung kommt. Jede
zurückgegebene Zeile wird angesehen, damit ein null in der ersten Zeile den
Typ nicht allein entscheidet. Es ist ein Ausgangspunkt, und er sagt das auch:
eine Spalte, die in jeder Zeile null war, lässt sich nicht typisieren, und
eine Zahlenspalte, die in diesen Daten zufällig nur ganze Zahlen enthielt,
kommt als `integer` heraus.

Das, was von Hand leicht schiefgeht, macht er richtig: die Feldnamen müssen
den Spaltennamen der Anweisung entsprechen. Auf `GetTurnoverPerCustomer`
angewandt erzeugt er den `TDtoTurnover` aus `ClientDtos.pas` Zeichen für
Zeichen.

Einen `Rtti.RegisterFromText`-Aufruf schreibt er ebenfalls — **auskommentiert**.
mORMot schaltet erweitertes Record-RTTI über `HASEXTRECORDRTTI` frei, und das
gilt für Delphi 2010 und neuer sowie FPC-Trunk 3.3/3.4. Hier mit demselben
Record und demselben JSON gemessen: **FPC 3.3.1 parst korrekt ohne die Zeile,
FPC 3.2.3 parst gar nichts.** Der Client braucht also den Record und den
Aufruf, sonst nichts — es sei denn, er wird mit FPC 3.2 gebaut, und dann steht
die Zeile bereit. Ihre Feldreihenfolge ist die **Deklarationsreihenfolge**,
weil sie das Speicherlayout beschreibt und nicht das JSON.

Unter Delphi kommt eine zweite Bedingung hinzu, die mORMot im eigenen Quelltext
vermerkt, in `mormot.core.rtti.delphi.inc`: das Auslesen der Feldtabelle
„may need `$RTTI EXPLICIT FIELDS([vcPublic])`" in der Unit. Das ist hier
ungetestet, mangels Delphi.

Jede Template-Operation öffnet `templates.sqlite` und schließt sie wieder, so
wie der Lader im Server, damit der Editor und ein laufender Server sich nicht
um die Datei streiten.

`templates.sqlite` ist der Ursprung, und der Editor hält den lesbaren Zwilling
im Gleichschritt: jedes Speichern und jedes Löschen schreibt `templates.sql`
daneben neu. Beide liegen in der Versionsverwaltung — die binäre, damit ein
Klon einfach starten kann, die textliche, damit ein Commit einen lesbaren Diff
hat und der ganze Satz daraus wiederherstellbar ist. Der Export trägt
absichtlich keinen Zeitstempel: ein unveränderter Satz muss eine unveränderte
Datei ergeben, sonst zeigt jeder Commit einen Diff, der nichts bedeutet.

## Wer wofür zuständig ist

Die App-Schicht ist der Rand: sie holt das Token aus dem Header, baut daraus
einen `TSqlCaller` und reicht weiter. Sie entscheidet nichts. Die Dom-Schicht
löst den Action-Key zu seinem `TSqlRec` auf, prüft die Rechte gegen die
konkrete Action und wendet die Regeln an. Die Infra-Schicht gleicht die Werte
an die Deklaration an, erzeugt oder füllt die Anweisung, bindet und führt aus.

Ablehnen ist Sache der einen Schicht, Ausführen der anderen:

| Schicht | antwortet mit |
|---|---|
| `AppSqlImplementation` | nichts eigenes — sie reicht durch |
| `DomSqlImplementation` | `sqlEmptyKey`, `sqlUnknownKey`, `sqlNotAllowed`, `sqlNeedsLogin` |
| `InfraSqlImplementation` | `sqlOk`, `sqlNoRows`, `sqlNothingWritten`, `sqlFailed`, `sqlBadParams` |

Einmal auflösen und den Record weiterreichen ist Absicht: ein erneutes
Nachschlagen in der unteren Schicht ließe ein Zeitfenster offen, in dem ein
Reload zwischen Prüfung und Ausführung den Datensatz austauscht — die Regel des
alten wäre geprüft, das SQL des neuen liefe.

Der Preis: die untere Schicht erzwingt nicht mehr selbst, dass nur registrierte
Anweisungen laufen — sie führt aus, was ihr gereicht wird. `TSqlRec` stellt nur
die Registry aus, und die steht in `dom`, wo die Infra-Schicht sie nicht sieht.
`ISqlTemplateExec` wird in `ServSqlTemplates` erzeugt und an niemanden außer
`TDomSqlTool` gegeben. Diese Methoden nicht auf eine blanke Anweisung
erweitern.

Beide Dienstverträge nach unten — `DomSqlServices` und `InfraSqlServices` —
stehen beim Erbringer und nicht beim Verbraucher: der Verbraucher legt fest,
was er braucht, die Schicht darunter erfüllt es, die Abhängigkeit zeigt nach
oben. Im jeweiligen Ordner stehen sie trotzdem, weil ein Client sie nicht sehen
soll. `DomSqlImplementation` sieht `ISqlTemplateExec` und nicht
`TSqlTemplateExec` und kommt so an keine Verbindung und kein SQLite heran. Nur
`ServSqlTemplates`, das alles zusammensteckt, kennt die Klassen.

### Woher die Templates kommen

Die Dom-Schicht besitzt die Registry und lässt sie von einer
`ISqlTemplateSource` füllen — `TDbTemplateSource`, aus der Template-Datei des Profils.
Unterhalb weiß damit nichts mehr, dass es überhaupt eine Registry gibt. Die
Schnittstelle bleibt trotz nur einer Implementierung: an ihr hängt, dass Dom
die Registry besitzt und Infra bloß die Datei liest.

Ein unbekannter Action-Key ist der interessante Fall: er kann ein Tippfehler
sein oder ein Template, das jemand angelegt hat, während der Server lief.
Gefragt wird deshalb zuerst die Quelle, nicht die Datenbank —
`TDbTemplateSource.Changed` vergleicht Zeitstempel *und* Größe der Datei gegen
den letzten Ladevorgang (beides, weil ein Dateizeitstempel nur sekundengenau
ist). Erst wenn sich wirklich etwas geändert hat, wird gelesen und die Registry
ersetzt.

Damit kostet ein neues Template keinen Neustart, und ein Tippfehler in einer
Schleife keine Abfrage, sondern einen `stat`-Aufruf. Gemessen über HTTP: zehn
Fehlversuche hintereinander, dazwischen eine eingefügte Zeile — im Log stehen
genau zwei Reload-Zeilen, Start und echte Änderung.

## Was ein Template deklariert

`TSqlRec` begann als Schlüssel und Anweisung. Er trägt jetzt zehn Felder mehr,
jedes aus einer Spalte in `templates.sqlite` gespeist, und **oberhalb der
Registry musste sich dafür nichts bewegen** — genau das, was diese Tabelle
belegen sollte.

| Spalte | wofür | nicht gesetzt heißt |
|---|---|---|
| `ParamTypes` | `text,int,date` — ein Eintrag je `?` | keine Umwandlung; gebunden wird, was JSON daraus gemacht hat |
| `Rules` | benannte Prüfungen der Parameter, `2:plz;3:email` | außer dem Typ wird nichts geprüft |
| `TestBounds` | Beispielwerte für einen Testlauf, `["Wegberg"]` | das Template wird geprüft, aber nie ausgeführt |
| `ReadGroups` | Bitmaske der Sitzungsgruppen, die lesen dürfen | siehe unten |
| `WriteGroups` | dasselbe fürs Schreiben | siehe unten |
| `RecordType` | der Record, den ein Record-Schreiben erwartet, als Name | kein Record-Schreiben |
| `RecordDecl` | die Felder dieses Records, als textuelle RTTI von mORMot | der Typ muss im Server einkompiliert sein |
| `KeyField` | die Schlüsselspalte eines erzeugten Statements | `ID` |
| `CallerScope` | bindet die Identität des Aufrufers ans letzte `?` | der Client setzt jeden Wert |
| `Filter` | die Where-Klausel einer erzeugten Liste, ohne das Wort `where` | jede Zeile |
| `OrderBy` | ihre Sortierung, ohne die Worte `order by` | die Reihenfolge der Datenbank |

Ist `RecordType` gesetzt, darf `Sql` **leer** sein — der einzige Fall, in dem
eine leere Anweisung zulässig ist, und er bedeutet: *beim Aufruf erzeugen*.

Eine Template-Datei aus der Zeit vor diesen Spalten behält ihre Zeilen und
bekommt sie als NULL, was jeder Leser als *nicht deklariert* auffasst. An einer
Zweispalten-Datei geprüft: die Zeilen bleiben, die alten Keys antworten weiter.

### Warum ein Parameter einen deklarierten Typ braucht

Ein Client schickt seine Parameter als JSON, und JSON kennt null, bool, Zahl
und Text. Ein Datum kommt also als Zeichenkette an, und mORMot bindet es als
Zeichenkette, weil `BindVariant` nach dem VType des Variants entscheidet und
der Variant Text sagt. Genau dort gehen Datumswerte gegen den SQL Server
schief — nicht im Statement, sondern beim Binden.

Die Deklaration `date` verlagert die Entscheidung aus dem Wert, wo JSON sie
verliert, in das Template, wo sie überlebt. `GetInvoicesSince` ist in diesem
Beispiel genau dieser Fall:

```pascal
ParseDynArray('GetInvoicesSince', _Arr(['2026-01-01']),
  Invoices, TypeInfo(TDtoInvoiceArray));   // eine Zeichenkette verlässt den Client
```

Der App-Layer macht daraus ein `varDate`, bevor der Record nach unten geht, und
der Treiber wird nach `BindDateTime` gefragt. Ein Wert, der sich nicht wandeln
lässt, wird mit `sqlBadParams` abgelehnt und nie geraten — `'31. August'` kommt
als Status zurück, nicht als falsches Ergebnis und nicht als Ausnahme.

Eine Deklaration, die sich nicht lesen lässt, wird beim Laden des **Satzes**
abgelehnt, nicht beim Aufruf des Keys: ein kaputtes `ParamTypes` lässt
`ReloadTemplates` scheitern, und der Server behält, was er hatte.

### Regeln für die Parameter

`ParamTypes` sagt, was ein Wert **ist**. Welche Gestalt er haben muss, sagt es
nicht: `text` ist mit einer leeren Zeichenkette zufrieden und `int` mit einer
Postleitzahl 4711. Die Spalte `Rules` ist diese zweite Frage, beantwortet wie
alles andere hier — die Prüfungen sind Code, ihre Benennung ist Daten:

```
Rules = '1:notempty;2:plz;3:email'
```

Die Position steht vorn, damit ein Template mit zwölf Parametern und einer
Regel eine Position nennt statt Kommas zu zählen; mehrere Regeln auf einem
Parameter sind mehrere Einträge. `SqlParamRules` bringt `notempty`, `plz`,
`email`, `len:min[,max]`, `range:min,max` und `oneof:a,b,c` mit — eine neue
**Art** von Prüfung ist eine in Pascal registrierte Funktion, eine neue
**Verwendung** ist eine Zeile.

Ein Null besteht jede Regel außer `notempty`: SQL NULL ist in jeder Spalte
zulässig, und es abzulehnen, weil es keine Postleitzahl ist, würde einen Wert
ablehnen, den der Aufrufer durchaus schicken darf.

Geprüft wird in `TDomSqlTool.CheckRules`, nachdem der Wert des Aufrufers
gebunden wurde — eine Regel kann also über den Wert sprechen, den der Client
nie geschickt hat — und bevor das Statement entsteht. Zwei Antworten, und der
Unterschied zählt:

- ein **Wert**, der nicht besteht, ist `sqlBadParams` wie jeder andere schlechte
  Parameter, und der Grund steht als Warnung im Log
- eine **Deklaration**, die selbst falsch ist — ein unbekannter Regelname, eine
  Position, an der es kein `?` gibt — ist der Fehler des Templates und nicht
  der des Aufrufers: sie wird als Fehler protokolliert, mit `sqlFailed`
  beantwortet, und nach außen geht nichts über die Deklaration

Gegen die Demo über HTTP gemessen: `AddKontakt` mit `41844` und `a@b.de`
schreibt die Zeile (`sqlOk`), mit `4184`, mit `a.b.de` oder mit leerem Namen
wird abgelehnt (`sqlBadParams`), und das Log nennt den Parameter;
`GetKontakteByPlz` mit `abcde` erreicht die Datenbank nicht. Eine Zeile, deren
Regel Parameter 4 eines Statements mit einem `?` nennt, antwortet `sqlFailed`.

Eine Grenze, ausgesprochen statt versteckt: die Positionen sind die `?` des
Statements, und ein **Record**-Schreibvorgang hat keine — seine Werte sind
Felder mit Namen. Ein Record-Template mit Regeln wird abgelehnt (`sqlFailed`,
protokolliert), und der Editor sagt es, bevor es gespeichert werden kann.
Regeln über Feldnamen sind der naheliegende nächste Schritt.

### Den ganzen Satz auf einmal prüfen

„Prüfen" beantwortet die Frage für das Template, das der Bearbeiter vor sich
hat. „Alle prüfen" beantwortet sie für die Datei, und das ist die Frage vor
einem Commit: nach einer umbenannten Spalte, einem geänderten Record-Typ oder
einer neuen Rechtemaske — **welcher** der neunundzwanzig Schlüssel geht nicht
mehr?

Zwei Hälften, und der Unterschied ist Absicht. Die Prüfungen brauchen keine
Datenbank und laufen über jedes Template: die Deklaration liest sich, Statement
und Parameter passen zusammen, ein `delete` hat sein `where`, der Record-Typ
löst auf, die Regeln lesen sich. Das Ausführen braucht die Spalte
`TestBounds`: die Werte, die ein Client schicken würde, als das JSON, als das
er sie schicken würde. Ein Array geht ans Statement, ein Objekt ist das JSON
eines Records und geht den Record-Weg — ein erzeugtes Insert wird also genauso
getestet wie ein gewöhnliches Select, aus einer Spalte und ohne eine Zeile
Testcode.

Ein Template ohne `TestBounds` gilt als **offen**, nie als bestanden. Ebenso
ein gescoptes: der Server bindet den Wert des Aufrufers ans letzte `?`, dieses
Werkzeug bindet gar keinen — eine grüne Zeile wäre dort eine Lüge über genau
das Template, das eine am nötigsten hat.

Jeder Lauf wird zurückgerollt, was immer die Rollback-Box sagt; die gilt dem
einen Statement, das gerade betrachtet wird.

An der Demo gemessen, verbunden mit `demo.sqlite`: 29 Templates, 28 ausgeführt,
eines offen (`GetMeineRechnungen`, gescopt), kein Befund; der Dump der
Datenbank ist vorher und nachher gleich. Und mit sieben absichtlich kaputten
Zeilen in einer Kopie: sieben Befunde, jeder mit Grund — eine Spalte, die es
nicht gibt (`no such column: Nmae`), zwei Werte statt einem, zwei Typen für
einen Parameter, eine Postleitzahl-Regel auf einem Abteilungsnamen, ein
unbekannter Record-Typ, Regeln auf einem Record-Schreibvorgang und ein `delete`
ohne `where`.

Auf dem Server liest `TestBounds` niemand. Es wird in `TSqlRec` mitgeführt wie
jede andere Spalte und dort ignoriert — genau das macht einen generischen
Testlauf ohne eine Zeile Servercode möglich.

Mit angehaktem *über den Server ausführen* nimmt derselbe Sammellauf den Weg
über den Server, und die Zeile, die immer offen war, schließt sich: ein
gescoptes Template **läuft**, weil der Server die Identität bindet —
`GetMeineRechnungen` antwortet dort `sqlOk`, während der direkte Lauf es nur
als offen melden kann. Ein Template, das dem angemeldeten Konto nicht gehört,
gilt als offen mit genau diesem Grund und nicht als Befund: eine Ablehnung
durch die Maske ist die richtige Antwort, und eine rote Zeile dafür würde
beibringen, Rot zu übersehen.

Schreibvorgänge bleiben außen vor, wenn man es nicht ausdrücklich anders sagt —
gefragt wird einmal vor dem Start, denn der Server committet, und ein
Sammellauf, der schreibt, ist einer, der die Datenbank ändert. Ein
Record-Schreibvorgang zählt dabei als Schreibvorgang wie jeder andere: ein
Objekt in `TestBounds` geht als JSON eines Records über
`WriteRecordForAction` hinaus, und der Server löst den Typ auf und erzeugt das
Statement — geprüft wird also der Generator, der später wirklich läuft.

Gegen `token strict` gemessen, 30 Templates: als `user` laufen 15 und 15 sind
offen — Schreibvorgänge ausgelassen, `GetGehaelter` offen, weil Gruppe 2 nicht
seine ist; als `admin` mit erlaubten Schreibvorgängen laufen alle 30. Der eine
Befund dort stammt vom zweiten Lauf hintereinander: `OrmAddTDtoArtikelRow`
nennt in `TestBounds` eine feste `ArtNr`, und der eindeutige Index sagt das
auch. Ein Sammellauf, der schreibt, lässt Zeilen zurück — deshalb wird vorher
gefragt.

### Was eine nicht gesetzte Rechtemaske bedeutet

Ein Schalter, `StrictRights` in `DomSqlImplementation`, und sonst nichts:

- **false** — hier die Voreinstellung — eine nicht gesetzte Maske lässt durch.
  Das braucht ein Machbarkeitsnachweis, und darauf beruht jedes Template, das
  vor diesen Spalten geschrieben wurde.
- **true** — eine nicht gesetzte Maske lehnt ab. Die Einstellung für eine
  Installation, die mit dem Aufstellen ihrer Regeln fertig ist.

Bewusst ein Schalter statt einer Voreinstellung je Schlüssel. Eine
großzügige Lücke kann sich dann nicht in einer vergessenen Zeile verstecken,
und das Umstellen ist eine Zeile statt einer Durchsicht. Es ist zugleich die
schon genannte Kehrseite: diese eine Zeile falsch, und jeder Key ist auf einmal
falsch.

**Jedes Template dieser Datei nennt eine.** Zwei Gruppen erledigen das Ganze:
Gruppe 1 liest, Gruppe 2 schreibt. Ein Select trägt also `ReadGroups = 1`, ein
Insert, Update oder Delete `WriteGroups = 2`, und die eine Abfrage, die
niemand außer einem Administrator sehen soll — `GetGehaelter`, die
Gehaltsliste — trägt stattdessen `ReadGroups = 2`. Die beiden Konten fallen
daraus: `admin` ist in beiden Gruppen und beiden Richtungen (3/3), `user` liest
Gruppe 1 und schreibt nichts (1/0).

Damit ist `strict` eine vernünftige Betriebsart und keine Falle mehr: wenn jede
Zeile ihre Regel nennt, heißt eine fehlende Maske wirklich *da hat jemand etwas
vergessen*.

Mit `token strict` gemessen: `user` liest `GetAllCustomers`, wird bei
`GetGehaelter` abgelehnt und bei jedem Schreibvorgang ebenso — über Werteliste
wie über Record; `admin` bekommt alle drei beantwortet. Ohne Token sind alle
drei `sqlNeedsLogin`.

### Eine Abfrage auf den Aufrufer einschränken

Die Rechtemaske beantwortet *darfst du diese Aktion*. Sie beantwortet nicht
*welche Zeilen bekommst du* — das steckt in den Parametern, und die kommen vom
Client. Ein Template `select … from Invoice where CustomerID = ?` lässt jeden
Aufrufer, der es ausführen darf, **jede** `CustomerID` durchreichen, die eigene
oder eine fremde. Im vertrauenswürdigen Intranet in Ordnung; über das Internet
ein Datenleck (die eine *harte* Regel der Patterns, gegen die Generic.Soa sonst
verstößt: *scope every read to the caller*).

`CallerScope` schließt es, in der Form, die eine hardgecodete Methode gratis
hat. Auf `'userid'` gesetzt, bindet der Server `Caller.UserID` an das
**letzte** `?` des Statements — ein Wert, den der Client nie schickt und nicht
setzen kann:

```
ActionKey   = 'GetMeineRechnungen'
Sql         = 'select ID, Amount, InvoiceDate from Invoice where CustomerID = ? …'
CallerScope = 'userid'
```

Der Client schickt **einen Wert weniger** (hier: keinen), der Server hängt die
Identität als letzten gebundenen Wert an. Ein Client, der die volle Anzahl
schickt, wird mit `sqlBadParams` abgelehnt — sein Wert landete sonst auf dem
letzten `?` und der Scope wäre verloren, also eine harte Ablehnung und kein
stilles Überschreiben. Die Anzahl ist `CountSqlParams(Sql) − 1`, geprüft in
`TDomSqlTool.ApplyCallerScope`.

Gegen `demo.sqlite` gemessen, über die Domänenschicht mit einem Test-Aufrufer:
Kunde 2 bekommt die Rechnungen 4 und 5 (seine), Kunde 4 die 7–9 (seine),
derselbe Action-Key — und Kunde 2, der `[3]` schickt, um eine fremde ID zu
erzwingen, wird abgelehnt. Zum Kontrast lässt das ungescopte
`AmountDateCustomer4OfInvoice` den Kunden 2 die Zeilen von Kunde 3 lesen:
genau das, was `CallerScope` verhindert.

Das ist der Paritätsnachweis: der generische Ansatz schränkt einen Read auf den
Aufrufer ein, genau wie eine handgeschriebene `GetMeineRechnungen`-Methode — die
Identität ist server-gesetzt, nur als Zeile in einer Spalte statt als Zeile
Pascal. Die Anhängen-Variante trägt eine `userid`; ein zusammengesetzter Scope
(ein zweiter Wert oder eine benannte Position) wäre derselbe Mechanismus,
erweitert.

Woher `Caller.UserID` kommt, ist das Token, und ohne eines bekommt ein Aufrufer
die `UserID` 0 — ein gescoptes Template liefert dann gar nichts, was die
richtige Vorgabe ist: lieber leer als fremd. Zum Ausprobieren ohne Token nimmt
der Server ein Argument `caller=<id>` und gibt jedem Aufrufer ohne Token diese
Identität:

    ./soa_sql_templates_server demo caller=2

Über HTTP gemessen, ohne einen einzigen Wert vom Client: `caller=2` liefert die
Rechnungen 4 und 5, `caller=4` die 7–9, `caller=3` die 6, ohne Argument nichts.
Ein Schalter zum Ausprobieren, keine Authentifizierung — er behauptet, jeder
anonyme Aufrufer sei dieser eine Benutzer, und sagt das beim Start auch braun
auf der Konsole.

Der Editor kann das nicht zeigen: sein „Testen" führt das Statement direkt auf
der Verbindung aus, nicht über die Domänenschicht. `CallerScope` greift dort
also nicht, und das letzte `?` trägt den eingetippten Wert. Bei gesetztem
Caller-Scope schreibt der Editor das jetzt vor die Statusmeldung — ein grüner
Lauf dort ist kein Nachweis für das Scoping.

### Wer der Aufrufer ist: das Token

`AppCallerToken` ist die einzige Stelle im Server, die den HTTP-Request liest,
und was sie verlässt, ist ein `TSqlCaller` — Benutzer, Name und die zwei
Masken. Gefüllt wird der aus einer Payload:

```pascal
TAuthPayload = record
  UserID: integer;
  UserName: RawUtf8;
  Reads: Int64;
  Writes: Int64;
end;
```

Der Record steht in `src/common/SqlAuthTypes.pas`, damit Server, Client und
Editor dasselbe darunter verstehen. Zwei Masken und nicht eine: die Templates
tragen `ReadGroups` und `WriteGroups`, seit es Masken gibt, und ein Aufrufer mit
einer Maske für beides konnte die Hälfte davon nicht ausdrücken. `CanExecute`
fragt je nach Richtung die eine oder die andere.

Das Token selbst ist ein **JWT**, signiert und geprüft mit HMAC-SHA256 durch
mORMots eigenes `TJwtHS256` — Signatur, Aussteller und Ablauf sind dessen
Sache, und diese Unit liest vier Claims aus dem heraus, was es durchlässt.
Nichts hier baut eigene Kryptografie, und nichts hier prüft einen Ablauf von
Hand: eine handgeschriebene Prüfung, die den Claim liest und den Vergleich
vergisst, sieht genauso aus wie eine, die funktioniert.

Das Signier-Geheimnis ist ein **GUID, beim Start gezogen** und nur im Speicher.
Nichts einzuchecken, nichts aus einer Konfigurationsdatei zu verlieren — und
jedes Token stirbt mit dem Prozess, was die gröbste mögliche Rücknahme ist und
die einzige, die eine Demo braucht. Der Auth-Dienst nebenan macht es genauso,
bis hin zu den 300 Minuten, die ein Token gilt.

### Anmelden

`IAppAuthTool` ist eine zweite Schnittstelle neben `IAppSqlTool`, weil eine
Schnittstelle, die Abfragen ausführt, nicht auch Identitäten ausstellen soll:

```pascal
function Login(const UserName, Password: RawUtf8;
  out Token: TSessionToken): TSqlStatus;
function WhoAmI(out UserName: RawUtf8; out Reads, Writes: Int64;
  out SecondsLeft: integer): TSqlStatus;
```

`Login` ist die einzige Methode, die ohne Token antwortet, und sie braucht dafür
keine Ausnahmeliste: die Ablehnung sitzt in der Domänenschicht, hinter der
Template-Registry, und eine Anmeldung kommt dort nie hin. Registriert wird sie
mit `optNoLogInput, optNoLogOutput`, damit weder das Passwort noch das
zurückgegebene Token je in einem Log landet.

Ein unbekannter Benutzer, ein falsches Passwort und ein gesperrtes Konto sind
**eine** Antwort, `sqlNeedsLogin`; der Unterschied nützt nur dem, der rät, und
steht stattdessen im Serverprotokoll. Ein Name, den es nicht gibt, zahlt
außerdem eine PBKDF2-Runde, damit man ihn nicht mit der Stoppuhr von einem
falschen Passwort unterscheiden kann.

Die Konten liegen in `bin/auth.sqlite`, einer eigenen Datei, die sich beide
Profile teilen: die Zieldatenbank hängt am Profil, die Menschen nicht. Beim
ersten Start entstehen zwei — `admin` (beide Masken 3, also Gruppe 1 und 2) und
`user` (liest Gruppe 1, schreibt nichts), Passwort `demo` für beide. Ihre
`UserID` ist ein Kunde der Demo-Datenbank, damit ein gescoptes Template etwas zu
zeigen hat. Gespeichert wird kein Passwort: ein Salt je Konto aus dem CSPRNG,
PBKDF2-HMAC-SHA256 darüber, die Rundenzahl in derselben Zeile und ein
zeitkonstanter Vergleich der Digests.

Zwei Schalter machen aus der Demo *„zeigt, wie Rechte gingen"* ein *„lehnt ohne
sie ab"*, beide standardmäßig aus:

    ./soa_sql_templates_server token strict

`token` lehnt jeden Aufruf ohne brauchbares Token ab und druckt beim Start den
Anmeldebefehl; `strict` lässt eine nicht gesetzte Rechtemaske ablehnen statt
zulassen.

Über HTTP gemessen, mit `token strict`. `Login` als `admin` liefert ein JWT,
dessen Payload `{"uid":2,"name":"admin","rd":3,"wr":3,"iss":"soa_sql_templates",
"exp":…}` lautet; falsches Passwort und unbekannter Name antworten beide
`sqlNeedsLogin` mit leerem Token, und das Log sagt, welches von beidem es war.
`WhoAmI` antwortet `admin, 3, 3, 18000` — fünf Stunden Rest. Mit den zwei Tokens
nebeneinander: `admin` liest `GetGehaelter` (`ReadGroups = 2`), `user` wird
abgelehnt (`sqlNotAllowed`); auf dem gescopten `GetMeineRechnungen` liefert
**dasselbe Template verschiedene Zeilen** — `user` (UserID 1) bekommt die drei
Rechnungen von Kunde 1, `admin` (UserID 2) die zwei von Kunde 2, und keiner der
beiden hat einen Wert geschickt. Ein Token mit einem geänderten Zeichen wird
abgelehnt, ebenso jedes Token nach einem Neustart, weil das Geheimnis mit dem
Prozess weg ist. `user` in `auth.sqlite` gesperrt heißt: keine Anmeldung mehr;
Sperre weg, Anmeldung wieder da. Im Log steht nirgends ein Passwort.

Ohne die Schalter gilt nichts davon: es wird kein Token verlangt, der Aufrufer
ist anonym in Gruppe 1, und ein Template mit einer anderen Maske lehnt weiterhin
ab.

### Wie der Client damit umgeht

`AppSqlClient` hält das Token in einer Variablen der Unit und nicht in der
Verbindung — der Testclient verbindet und trennt um jeden einzelnen Aufruf
herum, und das Token muss das überleben. Gesetzt wird es einmal je Connect:

```pascal
Client.SessionHttpHeader := AuthorizationBearer(ClientToken);
```

Das ist mORMots eigene Stelle für *„dein eigener Header, etwa ein JWT als
Bearer"*, und danach trägt **jeder** Aufruf dieser Verbindung das Token, ohne
dass eine einzige Aufrufstelle davon weiß.

Im Fenster gibt es einen Knopf *Anmelden…*, der zu *Abmelden* wird, und der
Anmeldestand steht im Titel — Name, Masken und Restminuten, aus `WhoAmI`, also
vom Server und nicht aus dem Token geraten. Kommt bei einem Aufruf
`sqlNeedsLogin` zurück, fragt der Client einmal nach und wiederholt denselben
Aufruf; genau dafür ist dieser Status von `sqlNotAllowed` getrennt worden, denn
„du musst dich anmelden" ist etwas, worauf ein Programm reagieren kann, „du
darfst das nicht" nicht.

Das Anmeldefenster ist zur Laufzeit gebaut (`u_logindialog` in `src/ui`), ohne
LFM: es sind drei Steuerelemente, und eine Formulardatei dafür wäre mehr zu
pflegen als zu gewinnen. Der Editor nimmt dieselbe Unit — zwei Programme, die
nach denselben zwei Feldern fragen, sollen nicht zwei Fenster pflegen. Dort
bedient sie *Server neu laden*: kommt `sqlNeedsLogin`, wird einmal gefragt und
der Aufruf wiederholt.

Ein Reload ist administrativ, und seit ein Token das sagen kann, verlangt
`CanReload` eine nicht-leere `Writes`-Maske: das Neulesen des Satzes ist der
Weg, auf dem ein neues Template wirksam wird, und das ist näher am Schreiben
als am Lesen. Mit `token strict` gemessen: ohne Token `sqlNeedsLogin`, als
`user` (schreibt nichts) `sqlNotAllowed`, als `admin` `sqlOk`.

### Testen über den Server

Das eigene *Testen* des Editors führt das Statement direkt auf seiner
Datenbankverbindung aus. Genau das macht es an einem Entwurf brauchbar — und
genau deshalb kann es die Hälfte der Fragen nicht beantworten, um die es in
diesem Dokument geht: Rechtemasken, `CallerScope` und die Regeln liegen in der
Domänenschicht, und dieser Lauf geht daran vorbei.

Das Häkchen *über den Server ausführen* dreht den Lauf um: derselbe Knopf ruft
`GetJsonFromAction` bzw. `WriteDataForAction` wie jeder Client, und die Antwort
ist damit die echte — mit Maske, Scope und Regeln. Kommt `sqlNeedsLogin`, wird
gefragt und der Aufruf wiederholt.

Was es kostet, ist der Entwurf. Der Server führt registrierte Templates aus und
hat für alles andere keine Methode — ihm eine zu geben hieße, die Eigenschaft
wegzuwerfen, für die dieses Beispiel existiert. Ein ungespeicherter Schlüssel
antwortet also `sqlUnknownKey`, und der Editor sagt: erst speichern, dann den
Server neu laden.

Eines spricht der Modus aus, statt es zu verstecken: der Server **committet**.
Das Rollback-Versprechen, das der Editor sonst überall gibt, kann er bei einem
Aufruf, der ihm nicht gehört, nicht halten — deshalb wird ein Schreibvorgang
vorher noch einmal bestätigt.

Ein Record-Schreibvorgang nimmt denselben Weg, über den Dialog, über den er
immer schon lief. *Record-Werte eingeben…* erzeugt das JSON eines Records, und
mit gesetztem Häkchen wird dieses JSON an `WriteRecordForAction` geschickt
statt hier ausgeführt — Typ und Statement entstehen im Server, weshalb das Feld
für das ausgeführte SQL leer bleibt. Es bleibt ehrlich leer: das Statement ist
anderswo entstanden, und ein hier erzeugtes zu zeigen hieße, ein anderes zu
zeigen als das, das gelaufen ist.

## Einen ganzen Record schreiben

Lesen und Schreiben sind in diesem Beispiel nicht symmetrisch, und diese
Asymmetrie sollte man benennen statt sie zu übertünchen.

Beim Lesen erzeugt der Server JSON, und der Client entscheidet, als welche
Form er es liest. Der Typ kann allein im Client wohnen, weil der Server ihn nie
benennen muss. Beim Schreiben eines Records muss jemand aus JSON wieder
typisierte Werte machen, und dieser jemand ist der Server — der Typ muss dort
also **geteilt** werden. Er wohnt in `src/app/WriteDtos.pas`, neben dem
Dienstvertrag — sichtbar für genau den, für den auch der Vertrag sichtbar ist.

Und er ist **einmal** deklariert. `TDtoCustomer` wird über `ParseDynArray`
gelesen und über `WriteRecord` geschrieben, beide Male dieselben drei Felder;
zwei Deklarationen wären zwei Namen für eine Form, und eine davon veraltet
unbemerkt. Wo die Formen wirklich verschieden sind, bleiben sie getrennt: die
Rechnung, die ein Client liest, trägt den Kundennamen aus dem Join, die er
schreibt die `CustomerID` — das sind zwei Records und waren es immer.

Geteilt wird aber nur die Deklaration, kein Code. Der Server benennt keinen
dieser Records:

```pascal
// Client — eine Funktion für jeden Record, den es je geben wird
status := WriteRecord('OrmUpdateTDtoCustomer', cust, TypeInfo(TDtoCustomer));
```

```
-- templates.sqlite: die ganze Zeile. Ein Statement gibt es nicht.
ActionKey  = 'OrmUpdateTDtoCustomer'
Sql        = ''
RecordType = 'TDtoCustomer'
```

Der Server schlägt den Typ über `Rtti.FindName` am Namen nach, lädt das JSON
hinein, läuft über seine Felder und setzt die Anweisung zusammen:

```sql
update Customer set Name = ?, City = ? where ID = ?
```

Ein Record hinzuzufügen heißt: eine Deklaration in `WriteDtos` und eine Zeile
in `templates.sqlite` — keine Methode, kein Rumpf, kein Konverter und auch
kein Statement. `SqlRecordBind` ist der ganze Mechanismus und wird einmal
geschrieben.

### Ein Record, der nur in seiner Zeile lebt

`WriteDtos` wird vom Server übersetzt, ein dort deklarierter Record kostet also
einen Neubau. Er muss es nicht: die Spalte `RecordDecl` trägt dieselben Felder
als textuelle RTTI von mORMot, und der Typ wird beim ersten Aufruf, der ihn
braucht, aus diesem Text registriert.

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

Über HTTP gemessen: diese Zeile allein — nirgends Pascal, das den Typ nennt —
fügt ein und aktualisiert, und `currency` wie `TDateTime` eines aus Text
deklarierten Records werden als sie selbst gebunden, genau wie bei einem
einkompilierten.

Zum Ausprobieren liegen drei solche Zeilen im ausgelieferten Satz, und zu
keinem ihrer Typen gibt es Pascal: `OrmAddTDtoProjektRow` für eine Tabelle ganz
ohne DTO, und das Paar von oben, `OrmAddTDtoArtikelRow` und
`OrmUpdateTDtoArtikelRow`, die sich in genau einer Spalte unterscheiden — beim
Insert bleibt `KeyField` leer, `ArtNr` wird also geschrieben wie jedes andere
Feld, beim Update steht es dort und wandert damit ins `where`. Gemessen: der
Insert legt eine Zeile mit vergebener `ID` an, das Update ändert sie, und ein
Update auf eine `ArtNr`, die es nicht gibt, antwortet `sqlNothingWritten`
statt zu scheitern.

**Ein einkompilierter Typ gewinnt immer.** Gefragt wird zuerst
`Rtti.FindName`, und neu definiert wird nur ein Name, den dieser Server selbst
aus Text registriert hat. Sonst könnte eine Zeile still einen Pascal-Typ
umformen, auf den sich der übrige Code verlässt: `Rtti.RegisterFromText`
*ersetzt* die Felder eines vorhandenen Recordtyps. Die Reihenfolge dieser
beiden Nachschlagevorgänge ist die ganze Zusicherung. Gemessen: ein unsinniges
`RecordDecl` neben dem einkompilierten `TDtoCustomer` wird ignoriert, der
Insert nennt weiter `Name` und `City`.

Eine *geänderte* Deklaration wirkt dagegen sehr wohl: beim nächsten Reload wird
der Text gegen den verglichen, aus dem registriert wurde, und nur ein anderer
wird erneut registriert. Gemessen: `'Name: RawUtf8'` erzeugt einen Insert, der
am `not null` von `Customer.City` scheitert; nach dem Erweitern der Zeile auf
`'Name: RawUtf8; City: RawUtf8'` und einem Reload schreibt derselbe Schlüssel
beide Spalten.

Eine Deklaration, die nicht parst, hinterlässt bei einem neuen Namen nichts —
ein Tippfehler in einer **bereits registrierten** ist dagegen schlimmer, als er
aussieht: `Rtti.RegisterFromText` löscht die Felder, bevor es parst, und lässt
den Typ halb definiert zurück. Gemessen: ein `RawUtf8`-Feld, das der Parser nie
erreicht hat, bleibt 8 Byte zu kurz, und der nächste Aufruf fände diese Hälfte
über `Rtti.FindName` und hielte sie für gültig. Deshalb wird der zuletzt
geglückte Text gemerkt und wieder registriert, wenn ein neuer scheitert — die
beschädigte Form überlebt den Aufruf nicht, der sie verursacht hat.

Was beim Reload eines Satzes **nicht** geprüft wird, ist, ob `RecordDecl`
überhaupt parst: diese Prüfung braucht die Infrastrukturschicht, und die
Registry liegt in `dom`, das sie nicht sehen darf. Sie sitzt stattdessen im
Editor — ohnehin früher als der Server —, und zur Laufzeit ist eine nicht
parsende Deklaration ein abgelehnter Aufruf mit dem Grund im Log, kein kaputter
Server.

### Worauf es sich stützt

Vier Konventionen, jede eine Konstante und eine Funktion, also je eine Stelle
zum Ändern statt einer verstreuten Regel. Die ersten beiden stehen in
`SqlTemplateTypes` und nicht in `SqlRecordBind`: die Domänenschicht liest
dieselbe Marke, um zu entscheiden, welcher Aufruf zu welchem Schlüssel passt,
und sie darf das Unit, das SQL zusammensetzt, nicht sehen:

| | |
|---|---|
| die Marke | der Action-Key beginnt mit `Orm`, und nichts sonst tut das |
| das Verb | hinter der Marke: `Add`/`Insert`, `Update`, `Retrieve`/`Get`, `List`/`Select` oder `Delete` |
| die Tabelle | der Recordtyp ohne `TDto` vorn und `Row` hinten — `TDtoCustomerRow` → `Customer`, `TDtoArtikel` → `Artikel` |
| der Schlüssel | die Spalte, die `KeyField` nennt, und `ID`, wenn es keine nennt: ein erzeugter Insert überlässt sie der Datenbank, ein erzeugtes Update setzt sie ins `where` |

Bis es `KeyField` gab, hieß die Schlüsselspalte `ID` und sonst nichts. Die
Konvention trug in diesem Beispiel und trägt draußen fast nirgends: in einer
gewachsenen Datenbank heißt der Schlüssel `Artikel_ID`, `Artikelname_ID`,
`Adressen_ID`. Leer bedeutet
die Spalte weiterhin `ID`, also musste keine bestehende Zeile geändert werden.

Ein Record ohne das Schlüsselfeld lässt sich einfügen, aber nicht
aktualisieren: ein erzeugtes Update ohne `where` würde die ganze Tabelle
überschreiben, also wird es abgelehnt statt ausgeführt. So wird auch ein
natürlicher Schlüssel geschrieben — beim Insert `KeyField` leer lassen, dann
wird das Feld gebunden wie jedes andere.

**Das macht aus dem Dienst kein „schick mir beliebiges SQL".** Jeder Name im
erzeugten Text stammt aus der RTTI des Records oder aus seinem Typnamen. Vom
Aufrufer kommt nichts hinein, und die Werte werden weiter gebunden.

### Zwei Verben, die keinen Record schicken

`Retrieve` und `Delete` sind nicht das Spiegelbild von `Add` und `Update`, und
genau das ist das Interessante daran. Unterwegs ist nur der Schlüssel:

```
OrmRetrieveTDtoCustomer + TDtoCustomer  ->  select ID, Name, City from Customer where ID = ?
OrmDeleteTDtoCustomer   + TDtoCustomer  ->  delete from Customer where ID = ?
```

Welche Spalten zu lesen sind, ist Sache des Recordtyps, und den Typ kennt der
Server aus dem Template — eine Teilmenge muss der Aufrufer also nie
beschreiben. Genau so macht es ein ORM: `Retrieve` schickt eine ID und für
eine Teilmenge eine Liste von Feldnamen, nie einen Record.

Bei der Schlüsselspalte geht der Unterschied noch einen Schritt weiter. Ein
Update nimmt seinen Schlüssel **aus dem Record**, der das Feld also tragen
muss; ein Retrieve und ein Delete bekommen ihn vom Aufrufer, `KeyField` darf
dort also eine Spalte nennen, die der Recordtyp gar nicht hat — das `where`
steht trotzdem.

Und weil dieser eine Wert ein gewöhnlicher gebundener Wert ist, brauchen die
beiden keinen neuen Aufruf: ein Retrieve ist `GetJsonFromAction`, ein Delete
ist `WriteDataForAction`, dieselben zwei Methoden wie für jedes von Hand
geschriebene Statement. Der Contract hat sich nicht geändert. Geändert hat
sich eine Sperre in der Domänenschicht, die bisher jeden Schlüssel mit
Recordtyp vom Wertelisten-Pfad fernhielt — ein erzeugtes Delete ist genau das
und wird jetzt durchgelassen, erkannt am Namen.

### Die Liste: viele Zeilen, gefiltert vom Template

`OrmList…` ist der Retrieve für mehr als eine Zeile. mORMots `RetrieveList`
nimmt seine Where-Klausel vom **Aufrufer**; hier steht sie im Template, in der
Spalte `Filter`, und der Aufrufer füllt nur ihre `?`:

```
OrmListTDtoCustomer + TDtoCustomer + Filter 'City = ?' + OrderBy 'Name'
  ->  select ID, Name, City from Customer where (City = ?) order by Name;
```

Die Rollen sind damit sauber getrennt: **die Form der Abfrage gehört dem
Template, die Werte dem Aufrufer.** Nichts, was ein Client schickt, wird je als
SQL gelesen — die Eigenschaft, die dieses Beispiel trägt, bleibt unangetastet,
und der nützliche Teil des ORM ist trotzdem da: die Spaltenliste kommt aus dem
Recordtyp, das Ergebnis lädt in `TDtoCustomerArray`.

Der Filter wird **geklammert** eingesetzt. Das ist keine Kosmetik: die
Domänenschicht hängt bei `CallerScope` ihre eigene Bedingung mit `and` an, und
`and` bindet stärker als `or` — ein `City = ? or Name = ?` ohne Klammern ließe
die halbe Tabelle am Scoping vorbei. Wie viele Werte ein solches Template
erwartet, weiß der Server, bevor das Statement existiert: `ExpectedParamCount`
zählt die `?` des Filters, so wie es sonst die des Statements zählt.

| | schickt | liefert | Methode |
|---|---|---|---|
| `OrmAdd…` / `OrmUpdate…` | den ganzen Record | einen Status | `WriteRecordForAction` |
| `OrmRetrieve…` | den Schlüssel | die Zeile, in denselben Recordtyp | `GetJsonFromAction` |
| `OrmList…` | die Werte des Filters | die Zeilen, als Array desselben Typs | `GetJsonFromAction` |
| `OrmDelete…` | den Schlüssel | einen Status | `WriteDataForAction` |

Alle vier gegen `demo.sqlite` gemessen: Insert, Update, Retrieve in einen
`TDtoCustomer` (`ID 29 / Rekord GmbH / Drolshagen`), Delete. Ein Retrieve auf
einen Schlüssel, den es nicht gibt, antwortet `sqlNoRows` und lässt den Record
unangetastet; ein Delete darauf antwortet `sqlNothingWritten`. Einen Record in
ein Retrieve zu schicken wird abgelehnt, und ein Record-Schlüssel ohne die
`Orm`-Marke ebenso — *„takes a record but does not start with ORM"* im Log.

### Wenn die Konvention nicht passt

Ein anderer Tabellenname, ein zusammengesetzter Schlüssel, eine zusätzliche
Bedingung, ein Insert, der seine `ID` selbst nennen muss — dann schreibt man
die Anweisung, mit **benannten** Platzhaltern:

```sql
update Customer set Name = :Name, City = :City where ID = :ID;
```

Der Server ersetzt jedes `:Name` durch `?` und bindet das Feld gleichen
Namens. Ein Umsortieren der Record-Felder kann die Werte nicht stillschweigend
verschieben, ein Platzhalter darf mehrfach vorkommen, und `:Name` zu `?` zu
machen ist eine Ersetzung innerhalb einer bereits registrierten Anweisung.

`OrmUpdateCustomerRecord` in diesem Beispiel ist dieser längere Weg, neben den
drei erzeugten Schlüsseln, damit beides nebeneinander zu sehen ist.

Den Anfang macht im Editor *SQL ins Feld erzeugen*: der Knopf schreibt das
erzeugte Statement ins SQL-Feld und nimmt den Haken bei *SQL beim Aufruf
erzeugen* wieder weg. Bei einem Record mit dreißig Feldern ist das der
Unterschied zwischen „diesen Weg gibt es" und „diesen Weg nimmt man auch".
Was dabei herauskommt, ist ein Entwurf zum Weiterschreiben, kein fertiger Satz.
Bei einem Retrieve und einer Liste hört er auf, wo das Schreiben anfängt:

```sql
select ID, Name, City from Customer
```

Spaltenliste und Tabelle stammen aus dem Recordtyp — der Teil, den niemand
tippen will —, das `where` ist der Teil, der geschrieben wird, also steht es
nicht da und muss auch nicht weggelöscht werden. Für jedes `?`, das dabei
entsteht, legt man einen Parameter an, und dann läuft *Testen*.

Für Insert und Update kommt der ganze Satz, in der `:Namen`-Form und nicht mit
`?` — ein geschriebenes Record-Statement mit Fragezeichen wird abgelehnt, weil
niemand sagen könnte, welches Feld an welchem hängt. Ein Delete behält sein
`where`, und das ist keine Unsauberkeit: `delete from Customer` als
Ausgangspunkt liegt einen Tastendruck neben einer geleerten Tabelle.

Ab dann trägt das Template sein eigenes Statement und folgt dem Recordtyp
nicht mehr — ein neues Feld im Record erreicht ein erzeugtes Statement von
selbst und dieses gar nicht. Der Editor sagt das beim Übernehmen, statt es
später herausfinden zu lassen.

**Die Typen überleben.** `TDtoInvoiceRow.InvoiceDate` ist ein echtes
`TDateTime` und `Amount` ein echtes `currency`, und beide werden als solche
gebunden. Genau deshalb reist der Parameter als `RawUtf8`-JSON und nicht als
Variant: ein `TDateTime` in einem Variant-Array kommt als schlichte
Zeichenkette an und wird als Text gebunden — gemessen, aus
`["2026-08-30T14:30:00"]` wird beim Empfänger ein String-Variant, also genau
der Fall aus *Warum ein Parameter einen deklarierten Typ braucht*. In den
deklarierten Record zurückgeladen ist es wieder ein Datum. An der
Demo-Datenbank gemessen:

```
10|6|1234.56|2026-08-31T14:30:00
```

Ein Record-Schreiben braucht deshalb gar keine `ParamTypes`-Deklaration — der
Record hat schon gesagt, was seine Felder sind.

Die falsche Methode für einen Schlüssel wird beantwortet, nicht geworfen: eine
Werteliste an einen Record-Schlüssel und ein Record an einen Werteliste-
Schlüssel kommen beide als `sqlBadParams` zurück.

Was das **nicht** tut, ist das ORM ersetzen. Es deckt den Fall ab, den das ORM
am schlechtesten abdeckt — ein Record, dessen Felder eine namensgleiche
Teilmenge der Tabellenspalten sind — ohne `TOrm`-Nachfahren, ohne Modell, ohne
Tabellenregistrierung, und zwar mit der Maschinerie, die ohnehin schon da war.

## Ergebnisse sind Werte, keine Ausnahmen

`TSqlStatus` (in `src/common`) ersetzt den Boolean, den die beiden Methoden
vorher lieferten:

| Wert | Bedeutung |
|---|---|
| `sqlOk` | Zeilen geliefert bzw. mindestens eine geschrieben |
| `sqlEmptyKey` | der Action-Key war leer |
| `sqlUnknownKey` | auf diesem Server nicht registriert |
| `sqlNotAllowed` | der Aufrufer ist bekannt, seine Maske reicht nicht |
| `sqlNeedsLogin` | es ruft niemand: kein Token, oder keines, das gilt |
| `sqlNoRows` | der Select lief, ohne Treffer |
| `sqlNothingWritten` | der Schreibvorgang lief, ohne Änderung |
| `sqlFailed` | die Anweisung selbst schlug fehl — Grund im Serverprotokoll |
| `sqlBadParams` | die Werte passen nicht zu dem, was das Template deklariert |

Ein unbekannter Action-Key ist eine gewöhnliche Antwort, keine Katastrophe. Nur
Verdrahtungsfehler werfen noch, deshalb wirft ein normaler Durchlauf nichts und
kein Debugger hält an.

In einem Status ist allerdings kein Platz für einen Satz, und der Editor
braucht einen: ein Statement im Entwurf ist meistens falsch, und `sqlFailed`
allein schickt seinen Autor ins Raten. Infra legt die Worte des Treibers
deshalb auf dem Weg nach draußen ab, in `LastSqlError` — einer threadvar, weil
ein `TSqlTemplateExec` im Server alle Anfragen gleichzeitig bedient und ein
geteilter String ein Wettlauf wäre. Am Contract ändert das nichts, der Server
liest es nie. Ohne das ist der Grund für alles verloren, was *nach* einem
geglückten Prepare scheitert — Binden, Ausführen, Konvertieren —, denn mORMot
hinterlässt die Fehlermeldung an der Verbindung nur, wenn schon das Prepare
abgelehnt wurde.

Der Client trifft dieselbe Wahl für die Verbindung: ein nicht erreichbarer
Server wirft in der Socket-Schicht und noch einmal in der Service-Factory, und
keine der beiden Meldungen nennt die versuchte Adresse. `ConnectClient` fängt
beides und gibt false zurück, mit dem Grund in `LastConnectError`.

## Abgleich mit den empfohlenen Patterns

Gemessen an [mORMot2-SAD-Recommended-Patterns.md](https://github.com/synopse/mORMot2/blob/master/docs/mORMot2-SAD-Recommended-Patterns.md).
Teil A ist praktisch deckungsgleich: `RawUtf8` statt `string`, `variant`-Bounds,
`TSynDictionary`, `sicShared`, packed records, Logging über `TSynLog`.
Abgewichen wird von Teil B, an einer einzigen Stelle, aus der alles Übrige
folgt: die Varianz liegt in Daten statt in Pascal-Interfaces. Kein ORM zu
benutzen ist dabei keine Verletzung von A.5 — `ISqlTemplateExec` leistet
Austauschbarkeit und Mockbarkeit genauso, nur eine Ebene tiefer.

Drei Punkte verdienen eine ausdrückliche Antwort, weil sie sonst wie
Versäumnisse aussehen.

**Das leere Modell ist die vorgesehene Form, nicht das Fehlen einer.** A.6.2:
*„Void model => no TOrm classes => no ORM REST routes can exist at all"*, und
die Doku stellt `TRestServerFullMemory.Create(EdgeModel)` als *„the public edge
with a void model, exposing only context-scoped services"* dem
`TRestServerDB.Create(Model, 'data.db')` als *„the private system of record
owning business tables"* gegenüber. Genau dieser Edge ist der Server hier, und
er ist deshalb ohne `TOrmModel` gebaut — nicht, weil eines vergessen wurde.

Die zweite Ebene fehlt allerdings, und zwar mit Absicht: was dort ein
`TRestServerDB` mit ORM-Tabellen wäre, sind hier `TSqlDBConnectionProperties`
und die Templates. Dieselbe Aufgabe, eine andere Antwort, mit dem Preis, der
oben unter „Was aufgegeben wird" steht. Wer das Muster wörtlich abhakt, findet
eine fehlende Hälfte, wo eine ersetzte steht.

**„Scope every read to the caller" ist gezeigt, nicht erfüllt.** Die Regel
steht als übergreifende Forderung — ein angemeldeter Endnutzer darf nur seine
eigenen Zeilen bekommen, gefiltert an der Dienstgrenze —, und
`ApplyCallerScope` sitzt genau dort. Alle 30 Templates dieser Datei nennen
inzwischen eine Rechtemaske, `strict` ist damit eine brauchbare Betriebsart;
`CallerScope` benutzt aber **eines** davon. Die Maske beantwortet *darfst du
das ausführen*, der Scope *welche Zeilen bekommst du* — und nur das erste steht
überall. Als Paritätsnachweis — der Mechanismus kann beides, siehe „Eine
Abfrage auf den Aufrufer einschränken" — ist das belastbar. Als Aussage über
diese Templates-Datei wäre die zweite Hälfte falsch.

**Authentifizierung gibt es, hinter einem Schalter.** A.6.1 verlangt
*„Authentication: enable it explicitly (JWT / mORMot auth)"* und lässt die Wahl
zwischen beiden Wegen. Mit `token` geht dieses Beispiel den JWT-Weg: Anmeldung
gegen die eigene Kontendatei, ein signiertes Token, und jeder weitere Aufruf
ohne eines wird abgelehnt. Was es nicht tut, ist das von sich aus zu verlangen —
siehe „Bewusst weggelassen".

## Bewusst weggelassen

**Ein geprüftes Token.** Ein Token gibt es, und es wird gelesen: Payload,
Gruppen, Identität, ein Ablauf, der eingehalten wird — siehe „Wer der Aufrufer
ist". Was es nicht gibt, ist die Signatur; die Payload ist also nur so
vertrauenswürdig wie der Port, über den sie kam. `VerifyToken` ist die Stelle,
an der das dazukommt, und sonst ändert sich dabei nichts.

Und was ohne Schalter läuft, ist nicht zu beschönigen: `RequireToken` ist
`false`, also läuft jeder Aufruf ohne Token durch. `AnonymousReads` und
`AnonymousWrites` setzen ihn in Gruppe 1, `AnonymousUserID` (Vorgabe 0, zu setzen über `caller=<id>`)
wird seine Identität, und `StrictRights = false` lässt jedes Template ohne
Maske zu. Mit `token strict` gestartet gilt nichts davon — und genau dafür gibt
es die zwei Schalter statt eines Absatzes, der verspricht, es ginge schon.

mORMots eigene Sessions einzuschalten würde `UserID` und `Groups` von selbst
füllen — `CurrentCaller` liest sie bereits, dafür muss in dieser Schicht nichts
geändert werden. Es reicht allerdings nur **eine** Gruppe je Benutzer durch
(`User.GroupRights.ID`). Für ein Modell mit getrennten Lese- und Schreibrechten
je Dienst ist ein JWT, das eine Gruppenliste trägt, der passendere Weg.

**Sanity-Regeln zur Laufzeit.** Die Zahl der `?` gegen die Zahl der Bounds,
ein verpflichtendes `where` bei Update und Delete. Der Server tut das nicht,
denn das prüft man billiger beim Verfassen eines Templates als bei jeder
Anfrage — und genau dort sitzt es jetzt, hinter dem Knopf „Prüfen" des
Editors. Wertebereiche je Schlüssel gehörten weiterhin auf den Server und
wären ein Feld auf `TSqlRec`.

**Serverseitig erzeugte Feldwerte.** Ein Record kommt mit seinen Feldern an
und wird geschrieben, wie er ist. Zwischen „der Record ist da“ und „das
Statement läuft“ gibt es keine Stelle, an der der Server ein Feld selbst
füllen könnte. Manche Schemata wollen genau das: einen Schlüssel, den nicht
die Datenbank vergibt, sondern der Prozess, einen Anlegezeitpunkt, der nicht
vom Client kommen darf, eine Mandanten-ID, die aus dem Aufrufer stammt statt
mitgeschickt zu werden.

Die Form dafür steht schon da. `CallerScope` tut das für einen gebundenen
Parameter — der Client schickt einen Wert weniger, die Domänenschicht setzt
ihn ein — und `ApplyCallerScope` ist die eine Stelle, an der es passiert. Eine
Spalte `Generator` daneben, die das Feld nennt und sagt, woraus es gefüllt
wird, wäre derselbe Griff für ein Record-Feld und würde von derselben Schicht
gelesen. Weggelassen, weil die Records dieses Beispiels es nicht brauchen —
nicht, weil es nicht passte.

**Tests.** Absichtlich weggelassen, damit der Vergleich ehrlich bleibt: auf
keiner Seite wird Testcode mitgezählt.

## Bekannte Einschränkungen

`demo.sqlite` bleibt gesperrt, solange der Server läuft — die statisch
gebundene SQLite von mORMot hält die Datei, und `LockingMode := lmNormal` löst
die Sperre nicht. Zum Hineinsehen den Server beenden oder die Datei kopieren.
Das trifft auch den Editor: ihn bei laufendem Server auf `demo.sqlite` zu
verbinden schlägt fehl, und SQLite meldet das als beschädigten Dateikopf statt
als belegte Datei — der Editor hängt deshalb einen Hinweis an, was es
gewöhnlich bedeutet. Es ist eine Eigenheit von SQLite und tritt gegen den SQL
Server nicht auf. `templates.sqlite` hat das Problem ebenfalls nicht: sie wird
zum Lesen geöffnet und wieder geschlossen, sodass ein laufender Server, ein
Viewer und der Editor sie gleichzeitig nutzen können.

Der Editor kann ein Record-Template jetzt auch testen, ohne die Zusage zu
brechen, dass dieses Werkzeug nie committet. *Record-Werte eingeben…* löst den
Recordtyp so auf, wie der Server ihn auflöst, baut aus den Feldern, die dabei
herauskommen, einen Dialog — eine Zeile je Feld, daneben der Typ, als der der
Wert gebunden wird — und liefert das JSON zurück, das ein Client schicken
würde. Dieses JSON geht durch `BindRecordJson` und in dieselbe zurückgerollte
Transaktion wie jeder andere Schreibtest. Was läuft, ist der Weg des Servers
und keine zweite, für den Editor geschriebene Fassung: im Log stehen der
Record, die erzeugte Anweisung und das Ergebnis.

Zahlen gehen unquotiert hinein, Strings quotiert, je Feld aus seinem
Parser-Typ entschieden — und genau das macht den Test überhaupt aussagekräftig:
ein Record, dessen Integer als Text ankäme, würde anders gebunden als beim
echten Aufruf. Ein Wert, der nicht zu seinem Feld passt, öffnet den Dialog
wieder, mit allem Getippten darin.

Ein **Update** beginnt bei der Zeile, die es überschreiben wird. Der Editor
fragt nach dem Schlüssel, holt diese Zeile und öffnet den Dialog darauf —
bearbeitet wird also, was dasteht. Womit er sie holt, ist keine zweite Regel:
es ist der Retrieve-Zweig desselben Erzeugers, beim Namen gerufen —
`RetrieveSqlFor` übergeht das eigene Verb des Templates und baut einen Select
über denselben Recordtyp und dieselbe Schlüsselspalte. Ein
`OrmUpdateTDtoArtikelRow` wird deshalb über `where ArtNr = ?` gesucht, genau
die Spalte, auf die sein Update passt. Leer gelassen öffnet die Abfrage den
Dialog auf Vorgabewerten; ein Schlüssel, der nichts trifft, hält mit genau
diesem Grund an, statt ein Formular zu zeigen, das eine Zeile vortäuscht. Ein
Insert wird gar nicht erst nach einem Schlüssel gefragt.

Gemessen: `OrmUpdateTDtoCustomer` auf `ID` 2 lädt
`{"ID":2,"Name":"Ostwald Holzbearbeitung","City":"Detmold"}`, der geänderte
Record geht durch das erzeugte Update — und danach steht die Zeile in
`demo.sqlite` unverändert da, weil die Transaktion zurückgerollt wurde.

Was eingegeben wurde, bleibt zweimal erhalten. Der Dialog merkt sich das
Record je Schlüssel für die Sitzung und öffnet beim nächsten Mal darauf, statt
auf leeren Feldern — beim Update erst, wenn keine Zeile aus der Datenbank kam.
Und das JSON steht danach unter *so würde es reisen*: für ein Record-Template
ist dieses Objekt genau das, was ein Client schickt, und *JSON als TestBounds*
schreibt es mit einem Druck in die Spalte, aus der der Sammellauf und der Weg
über den Server es später wieder nehmen.

In die Parameterliste geht es nicht, und das ist Absicht. Der erzeugte
Schreibvorgang trägt `:Namen`, keine Fragezeichen; die füllt der Server aus dem
Record, und ein Record-Template mit `?` lehnt die Domänenschicht ab. Werte in
einer Liste, die dieser Lauf nie liest, wären ein Feld, das etwas anderes
verspricht, als es hält.

Das sagt, woher die Werte kommen, und nicht, dass so ein Template nicht
testbar wäre. *Testen* sucht den Record deshalb dort, wo das Fenster ihn zeigt:
erst *geht als JSON raus*, dann die letzte Eingabe im Dialog zu diesem
Schlüssel, dann die Spalte `TestBounds`. Was es findet, läuft denselben Weg,
den der Dialog nimmt — mit gesetztem Häkchen über den Server, ohne über die
eigene Verbindung. Ein Array in einem der drei Felder zählt nicht: ein
Record-Schreibvorgang hat keine Positionen, und eine Werteliste dafür zu nehmen
wäre genau die Verwechslung, die das hier beendet.

Weil der Editor `WriteDtos` mitbindet, gilt das für die im Server
einkompilierten Typen genauso wie für die, die eine `RecordDecl`-Spalte
deklariert. Die beiden Verben, die keinen Record schicken, werden hier am
Namen abgelehnt und sagen auch warum: ihr Schlüssel ist ein gewöhnlicher
Testwert und gehört dorthin, wo alle anderen gebundenen Werte stehen.

`SeedTemplateDb` sät nichts mehr aus Pascal — es baut nur eine *fehlende*
`templates.sqlite` aus dem `.sql`-Export wieder auf. Eine vorhandene Datei
wird nie angefasst; neue Templates entstehen im Editor oder als eingefügte
Zeile.

Die Templates sind eine Startvoraussetzung. Ein fehlerhafter Satz heißt, dass
der Dienst nicht startet — es gibt keinen einkompilierten Rückfall mehr, und
das mit Absicht. Was es entschärft: eine *fehlende* `templates.sqlite` wird aus
`templates.sql` daneben wiederhergestellt, und ein schlechter Satz, der einem
*laufenden* Server angeboten wird, wird abgelehnt — er bedient weiter den, den
er hatte. Nur eine kaputte Datei beim Start ist tödlich, dann aber laut.

Ein Prozess je Template-Datei. Zwei Profile dürfen nebeneinander laufen — sie
haben eigene Ports und eigene Datenbanken —, ein zweiter Server auf derselben
SQLite-Datei scheitert aber beim Start und meldet den oben beschriebenen
Fehler vom beschädigten Dateikopf. Er sagt jetzt dazu, was das gewöhnlich
bedeutet, statt mit der Formulierung des Treibers allein abzubrechen.
