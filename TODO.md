# TODO — Generic.Soa

> Stand: 2026-09-04. Abgeleitet aus dem Abgleich mit
> [mORMot2-SAD-Recommended-Patterns.md](https://github.com/synopse/mORMot2/blob/master/docs/mORMot2-SAD-Recommended-Patterns.md).
> Sortiert nach dem, was der Ansatz *braucht*, um als Diskussionsgrundlage zu tragen —
> nicht nach Aufwand.

Die Punkte sind in drei Klassen geteilt: **A** schließt echte Lücken, **B** sind Hebel,
die einen bekannten Einwand nicht nur mildern, sondern auflösen, **C** ist Politik und
Geltungsbereich — Entscheidungen, kein Code.

---

## A. Lücken (blockierend für „Internet-fähig")

### A1. Caller-Scoping in die Bounds — **erledigt am 03.09.2026 (als Beispiel)**
Ursprünglich als höchste Priorität und harte Pattern-Verletzung geführt. Beim Bauen zeigte
sich die richtige Einordnung: für das grobe Rechtemodell (Service-Gruppen × read/read-write)
deckt die vorhandene Maskenprüfung (`CanExecute`) den Fall schon — jeder in der Gruppe sieht
die ganze Tabelle, und das ist im Intranet gewollt. Zeilen-Scoping auf die einzelne Identität
wird erst nötig, wenn ein Service Zeilen pro Endnutzer/Kunde trennt (Metrica-artige Accounts,
Publikumsverkehr). A1 ist damit weniger dringende Lücke als **Paritätsnachweis**: der Beleg,
dass der generische Ansatz sicheres Scoping genauso kann wie eine hardgecodete Methode.

Gebaut als **Anhängen-Variante** (Vorschlag aus der Diskussion, schlanker als das ursprüngliche
`CallerParams` mit Positionen): Spalte `CallerScope` auf `TSqlRec` (leer = aus; `'userid'` =
`Caller.UserID` wird ans letzte `?` gebunden). Der Client schickt einen Wert weniger; wer die
volle Anzahl schickt, wird abgelehnt (`sqlBadParams`), sonst rutschte die ID an die falsche
Stelle. Sitz: `SqlTemplateTypes` (Feld + `CountSqlParams`), `DomSqlImplementation`
(`ApplyCallerScope` in `SelectJson`), Editor (Feld). Demo: `GetMeineRechnungen`. Gemessen.

Offen geblieben, bewusst:
- nur der Lese-Pfad (`SelectJson`). Ein scoped Write/Delete wäre dieselbe Hilfsfunktion in
  `WriteData` — nicht gebaut, weil das Beispiel den kanonischen „scope every read"-Fall zeigt.
- nur eine `userid`. Ein zusammengesetzter Scope (mehrere Werte, benannte Positionen) wäre die
  Erweiterung, die das ursprüngliche `CallerParams` vorsah.
- die Identität kommt noch aus dem Token-Stub, nicht aus echter Prüfung — A1 ist deren
  Verbraucher, siehe „echte Token-Prüfung" in HANDOFF Abschnitt 7. Damit man das Scoping
  trotzdem laufen sieht, nimmt der Server seit 04.09. `caller=<id>` und gibt jedem Aufrufer
  ohne Token diese `UserID` (`AnonymousUserID` neben dem schon vorhandenen `AnonymousGroups`).
  Ohne das Argument bleibt es bei 0, und ein gescoptes Template liefert nichts.

### A2. Rechteprüfung fertigstellen
`CanExecute` prüft die Masken bereits, `CheckRules` ist eine leere Hülle.
Was eine unbesetzte Maske bedeutet, ist ein Flag in der Domain-Schicht
(`StrictRights`) — **dokumentiert** seit 04.09. in DETAILS („Abgleich mit den
empfohlenen Patterns" und „Bewusst weggelassen"), samt der Zahl, die dazugehört:
23 der 24 Demo-Templates nennen keine Maske, sind mit `StrictRights = false`
also erlaubt. Offen bleibt der Test, der das festnagelt.

### A3. Generische Tests aus `ParamTypes` / `Test`
Aktuell null Regressionsabdeckung pro Query. Der Aufwand liegt einmalig, nicht pro
Query — also derselbe Hebel wie beim Rest des Ansatzes.

- `Test`-Spalte auf `TSqlRec`: Beispiel-Bounds + erwartete Form des Ergebnisses
- ein Testlauf, der jede Zeile der Datei ausführt: bindet sie, läuft sie, liefert sie
  die deklarierte Spaltenzahl/-typen
- als eigenes Programm neben Server/Client/Editor, damit CI es aufrufen kann

### A4. Sanity-Rules zur Laufzeit (das, was nicht in den Editor gehört)
Wertebereiche pro Key gehören auf den Server (`Rules`-Spalte). Zählen der `?` gegen die
Bounds-Anzahl und „jedes Update/Delete braucht ein `where`" bleiben im Editor —
billiger beim Schreiben als bei jedem Request.

> **Grenze für `Rules` — bewusst festhalten:** solange es *Parametervalidierung* ist
> (Bereiche, Formate, benannte Checks als kompiliertes Pascal, in der Zeile nur
> referenziert), ist es die natürliche Fortsetzung. Sobald dort Bedingungen über
> mehrere Werte oder Tabellen landen, ist es eine selbstgebaute Regel-DSL mit
> Interpreter — dann lieber der klassische Weg daneben. Siehe C2.

### A5. Authentifizierung überhaupt einschalten
Die Patterns verlangen es ausdrücklich (A.6.1: *„Authentication: enable it
explicitly (JWT / mORMot auth)"*) und lassen die Wahl des Verfahrens frei. Die
Demo erfüllt das heute nicht: `RequireToken = false`, `TokenToCaller` ist ein
Stub, `AnonymousGroups = 1`, und `caller=<id>` verteilt eine Identität an jeden.
Seit 04.09. steht das so in DETAILS, statt zwischen den Zeilen zu liegen — das
entschärft die Kritik, erledigt sie aber nicht.

Vor dem Bauen zu klären (vier Fragen, im Team, nicht hier):
Signaturverfahren (HMAC gegen asymmetrisch), wer ausstellt, welche Claims,
und wie eine Gruppenliste auf die 64-Bit-Maske von `TSqlCaller` abgebildet wird.
mORMots eigene Sessions wären der kürzere Weg (`CurrentCaller` liest sie schon),
tragen aber nur **eine** Gruppe je Benutzer — für getrennte Lese- und
Schreibrechte je Dienst zu wenig.

---

## B. Hebel (lösen einen Einwand auf, statt ihn zu mildern)

### B1. Getypte Client-Wrapper aus dem Editor generieren
Der prominenteste Einwand ist „der Compiler prüft die Parameterliste nicht mehr".
Der Editor erzeugt den DTO bereits aus dem Result — derselbe Generator kann pro
Action-Key eine Wrapper-Funktion ausgeben:

```pascal
function GetCustomersByCity(const City: RawUtf8;
  out Rows: TDtoCustomerArray): TSqlStatus;   // ruft intern ParseDynArray
```

Damit hat der Aufrufer wieder eine geprüfte Signatur, der Server bleibt generisch,
und die Signatur ist per Konstruktion mit dem Template synchron statt handgepflegt.
Aus einem Trade wird eine Werkzeugfrage.

- Quelle: `ParamTypes` (Parameter) + generierter DTO (Ergebnis)
- Sitz: `DtoCodeGen.pas`, neben der bestehenden Record-Erzeugung

### B2. Schreibseite symmetrisch machen — **erledigt am 02.09.2026**
`WriteDtos` musste von Server *und* Client kompiliert werden — die einzige Stelle,
an der ein Typ doch wieder durch den Server reiste. Erledigt über eine Spalte
`RecordDecl`: die Felder als textuelle RTTI, `Rtti.RegisterFromText` beim ersten Aufruf,
registriert unter dem Namen aus `RecordType`. Gemessen; siehe HANDOFF, Punkt 6.

Offen geblieben ist dabei absichtlich:

- die gemeinsame Unit fällt nicht *weg*, sie wird nur überflüssig. `WriteDtos` bleibt der
  Weg für einen Typ, den der Server-Code selbst anfasst, und gewinnt gegen die Spalte
- die Konvention „Feldname = Spaltenname" trägt unverändert weiter, nur heißt „Feldname"
  jetzt auch „was in der Zeile steht"
- ein Editor-Dialog, der die Felder aus `RecordDecl` als Eingabemaske baut — der nächste
  Schritt, siehe HANDOFF unter *Vorgeschlagen*

Mit derselben Änderung kam die Spalte `KeyField` (leer heißt `ID`), ohne die die
Konvention „Schlüsselspalte heißt `ID`" gegen eine gewachsene Datenbank nicht trägt.

### B2b. Retrieve und Delete — **erledigt am 03.09.2026**
Die Leseseite der ORM-Entsprechung. `OrmRetrieveXxx` erzeugt den `select` über die Felder
des Recordtyps, `OrmDeleteXxx` das `delete` — beide nehmen nur den Schlüssel, beide laufen
über die vorhandenen Methoden `GetJsonFromAction` und `WriteDataForAction`. Der Contract
blieb unangetastet. Im Client: `RetrieveRecord` und `DeleteRecord` in `u_client_parsing`.

Zugleich tragen ORM-Schlüssel jetzt die Marke `Orm` am Anfang, und nur sie. Der
Verb-Präfix allein war nicht eindeutig: `DeleteCustomer` ist eine gewöhnliche Anweisung
mit gebundenem Wert und muss eine bleiben. Die Konvention sitzt in `SqlTemplateTypes`,
weil die Domänenschicht sie mitliest und `SqlRecordBind` nicht sehen darf.

Offen geblieben, bewusst:

- eine `Orm`-Marke *erzwingt* nichts über den Recordtyp hinaus: ein Schlüssel darf `Orm`
  heißen und keinen Recordtyp nennen, dann ist er eine gewöhnliche Anweisung mit einem
  irreführenden Namen. Der Editor könnte das anmerken
- `Retrieve` liefert immer alle Felder des Typs. Eine Teilmenge wäre eine zweite Zeile mit
  einem zweiten Recordtyp — was in mORMot die CSV-Feldliste löst, hier aber eine neue
  Spalte oder einen neuen Parameter bräuchte

### B2c. Modaler Record-Dialog im Editor — **erledigt am 03.09.2026**
`RecordDialog.pas`, zur Laufzeit gebaut statt als LFM entworfen: welche Steuerelemente es
gibt, steht erst fest, wenn der Recordtyp aufgelöst ist. Der Dialog liefert JSON, und das
läuft durch `BindRecordJson` und die Rollback-Transaktion — also den Weg des Servers.
Damit ist der Editor auch für die Schreibseite ein Prüfstand und nicht nur ein Formular.

Das Vorbelegen aus einer vorhandenen Zeile kam am selben Tag dazu: bei einem
`OrmUpdate…` fragt der Editor nach dem Schlüssel und öffnet den Dialog auf der Zeile, die
er nennt. Geholt wird sie über `RetrieveSqlFor` — der Retrieve-Zweig desselben Erzeugers,
beim Namen gerufen, also über dieselbe Schlüsselspalte, auf die das Update passt.

Offen geblieben, bewusst:

- **kein Schreiben ohne Rollback.** Bleibt so: das Werkzeug committet nicht
- **kein Vorbelegen für einen Insert** — und das ist auch nicht gemeint, wenn es hier
  einmal aufgegriffen wird. Ein Insert ist ein neuer Datensatz; vorbelegt wird er bereits
  sinnvoll, nämlich mit den Vorgaben aus dem Feldtyp (`DefaultFor`): `0` für Zahlen,
  `false`, leerer String, heutiges Datum. Zufallswerte oder uninitialisierten Speicher
  sieht der Dialog nie — er liest keinen Record, er baut die Felder aus der RTTI.
  Die einzige bewusste Abweichung vom Record-Default ist das Datum: ein genullter
  `TDateTime` wäre der 30.12.1899, und den in einem Eingabefeld vorzufinden hilft niemandem.

  Was offen bleibt, ist etwas anderes und heißt besser **„Zeile als Vorlage übernehmen"**:
  eine vorhandene Zeile laden, ein, zwei Felder ändern und als neue einfügen. Zwei Fälle
  sprechen dafür — Duplizieren in der Datenpflege, und Fremdschlüssel, die es geben muss
  (`OrmAddTDtoInvoiceRow` braucht eine `CustomerID`, die existiert; der Dialog schlägt `0`
  vor, und der Test scheitert dann an etwas, das mit dem Template nichts zu tun hat).

  Falls es je gebaut wird, dann **nicht** als Abfrage bei jedem Add — das bremst den
  häufigen Fall für den seltenen —, sondern als ausdrücklicher zweiter Griff im Dialog.
  Bis das beim Arbeiten wirklich stört, bleibt es liegen; die `CustomerID` einmal zu
  tippen ist billiger als der Knopf.

### B3. Templates in die Build-Kette holen
SQL verlässt heute Build und Review. Weitgehend Prozess, kein Code:

- `templates.sql` ist die versionierte Quelle, `templates.sqlite` das Artefakt
- CI: seeden, gegen ein Schema validieren, A3-Testlauf ausführen
- `ReloadTemplates` hinter Admin-Recht (`CanReload` steht schon) plus Audit-Log
- Hot-Reload bleibt Feature — aber als Profil-Entscheidung, nicht als Standardweg

---

## C. Geltungsbereich und Politik (keine Tickets, Beschlüsse)

### C1. Den Geltungsbereich schriftlich festnageln
DETAILS.md sagt es bereits („not a replacement for interface-based SOA"), aber es sollte
die *erste* Aussage sein, nicht eine unter vielen: Generic.Soa ist die Query-Seite —
Reports, Listen, Auswertungen. Alles, was Zustand ändert oder Fachregeln trägt, geht
weiterhin den Blueprint-Weg. Das ist die stärkere Position, nicht die schwächere.

### C2. Fachlogik hat in dieser Architektur keinen Ort — so lassen
`dom/` enthält Rechteprüfung und Registry, keine Domäne. Das ist konsistent, solange C1
gilt. Der Reflex, „nur noch diese eine Regel" in die Daten zu legen, ist die Stelle, an
der der Ansatz kippt.

### C3. Abgleich mit den Patterns dokumentieren — **erledigt am 04.09.2026**
Abschnitt „Abgleich mit den empfohlenen Patterns" in DETAILS.md und DETAILS-de.md,
vor „Bewusst weggelassen". Er beantwortet ausdrücklich die drei Punkte, die sonst
wie Versäumnisse aussehen: das leere Modell (ist die vorgesehene Edge-Form, A.6.2
wörtlich zitiert), die fehlende zweite Ebene (ersetzt, nicht vergessen) und
„scope every read to the caller" (gezeigt an einem von 24 Templates — Nachweis,
nicht Erfüllung). Der Ton ist bewusst der einer Selbstauskunft und nicht der einer
Konformitätsbehauptung.

Darüber steht, was schon vorher galt: Teil A ist praktisch deckungsgleich
(`RawUtf8`, `variant`-Bounds, `TSynDictionary`, `sicShared`, packed records,
Logging), abgewichen wird von Teil B an einer einzigen Stelle, aus der alles
folgt — die Varianz liegt in Daten statt in Pascal-Interfaces. Kein ORM zu
benutzen ist dabei keine Verletzung von A.5: `ISqlTemplateExec` leistet
Austauschbarkeit und Mockbarkeit genauso, nur eine Ebene tiefer.

Was der Abgleich als *offen* stehen lässt, ist kein Doku-Punkt mehr, sondern
A5 (Authentifizierung einschalten) und A2 (Test für `StrictRights`).

### C4. Privates Projekt, Veröffentlichung vor Übernahme — Beschluss vom 09.09.2026
Generic.Soa ist ein privates Projekt: in privater Zeit und auf privatem Konto entstanden.
Es soll unter einer Open-Source-Lizenz erscheinen, **bevor** es intern übernommen oder
weiterentwickelt wird. Grund ist nicht Besitz, sondern Stand: ein halb übernommener Ansatz
kommt als halbe Idee an, und dafür gibt es intern bereits einen Präzedenzfall: eine
generische SQL-Schicht, die auf halbem Weg wieder ausgebaut wurde. Weitergabe nur mit
ausdrücklicher Zustimmung; der Hinweis dazu steht oben in beiden READMEs.

Vor der Veröffentlichung fällig, bewusst **nicht** vorher:

- ~~Eine Lizenz wählen und hinterlegen~~ — **erledigt am 16.09.2026**: MIT, siehe
  `LICENSE`. Das Projekt ist ein Lehrbeispiel, es soll abgeschrieben werden dürfen;
  Copyleft arbeitet gegen diesen Zweck. Mormot2 selbst steht unter MPL/GPL/LGPL, liegt
  aber nicht im Repository, gibt also nichts weiter. Beide READMEs sagen das jetzt am
  Ende und im Hinweis oben.

- ~~Das zweite Profil, der Hostname und die Verweise auf das interne Netz~~ —
  **erledigt am 15.09.2026**. Aus dem zweiten Profil wurde `mssql`: es zeigt auf einen
  SQL Server, den der Leser selbst stellt, Host und Datenbankname sind Platzhalter, und
  `bin/templates_mssql_schema.sql` legt die vier Tabellen dafür an — die Datei war bis
  dahin nicht einmal eingecheckt. Der Messvergleich in DETAILS spricht jetzt vom
  *typisierten Dienst*, die Meldungen des Editors von „einem Weg zum Server" und
  `kinit <benutzer>@<REALM>`.
- Historie kappen: Kopie in einen neuen Ordner statt `git filter`. Nimmt zugleich die
  lokale Autorenkennung aus den Commits und macht ältere Stände der
  `templates_mssql.sqlite` unwiederbringlich.
- Den Hinweis oben in den READMEs entfernen — er gilt genau bis dahin.

---

## D. Bekanntes, nicht dringend

- `demo.sqlite` bleibt gesperrt, solange der Server läuft (statisch gelinktes SQLite)
- der Editor kann Record-Templates weder testen noch das erzeugte Statement zeigen —
  dazu müsste der Record-Typ in die Editor-Binary kompiliert sein
- ein zweiter Server auf derselben Templates-Datei scheitert beim Start (Meldung ist
  inzwischen verständlich)
- kein `AppXxxClient/Local/Remote`-Muster (Patterns A.6): die Topologie ist fest
  verdrahtet, In-Process-Nutzung geht nur über HTTP. Relevant erst, wenn jemand den
  Dienst einbetten will
