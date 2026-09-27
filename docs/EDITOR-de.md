# Der Template-Editor — Bedienung

Kurzanleitung zu `soa_sql_templates_editor`. Warum die Felder so heißen und was
dahintersteckt, steht in [DETAILS-de.md](DETAILS-de.md); hier stehen nur die
Handgriffe. Das Fenster ist englisch beschriftet; die Beschriftungen stehen
unten so, wie sie dort erscheinen.

Der Editor ist ein Entwicklerwerkzeug: er bearbeitet `templates.sqlite`, führt
Statements auf einer Datenbank aus, mit der er sich **selbst** verbindet, und
schreibt die Record-Deklaration für das Ergebnis. Er gehört nicht neben den
Client auf einen Arbeitsplatz, und er gehört an eine Entwicklungsdatenbank.

---

## Starten und verbinden

1. `bin/soa_sql_templates_editor` starten.
2. **Profile** wählen (`demo` oder `mssql`). Das setzt Ziel und Templates-Datei
   zusammen — nie einzeln ändern, sie gehören zueinander.
3. **Connect** drücken. Die Titelzeile zeigt danach die Verbindung.
4. **Load list** drücken. Links stehen die Action-Keys.

Ohne Verbindung geht alles außer *Test* und *Check all* mit Ausführung.

| Feld oben | Bedeutung |
|---|---|
| **DB** | Treiber: SQLite oder ODBC-Verbindungszeichenfolge |
| **Target** | Dateiname (SQLite) oder vollständige ODBC-Zeichenfolge |
| **User / Passwort** | nur für ODBC; bei Kerberos leer lassen |
| **Templates** | die `.sqlite` mit den Templates |
| **Search** (unten links) | filtert die Schlüsselliste beim Tippen |

---

## Eine Abfrage anlegen

1. **New** drücken.
2. **Action key** eintragen, z. B. `GetKundenByCity`.
3. **SQL** eintippen, ein `?` je Parameter:
   `select ID, Name from Kunde where City = ?`
4. Unter **Parameters** anlegen: Art wählen (`text`, `int`, `date` …), Wert eintippen,
   **Add**. Je `?` einer, in der Reihenfolge des Statements.
5. **Types** füllt sich dabei selbst; sonst **Take from parameters**.
6. **Rights read/write** setzen (Bitmaske je Gruppe, `1` = Gruppe 1).
   `0` heißt „keine Regel" und wird von einem Server mit `strict` abgelehnt.
7. **Check** — meldet, was ohne Datenbank feststellbar ist.
8. **Test** — führt aus; ein Schreibvorgang wird zurückgerollt, solange
   **Rollback** angehakt ist.
9. **Save**. Danach **Reload server**, sonst kennt ein laufender Server
   den Schlüssel nicht.

Ergebnis ansehen: Reiter **Table** (Zeilen), **JSON** (was rausgeht),
**Messages** (Log), **Type** (Record-Deklaration erzeugen).

---

## Ein Record-Template anlegen (Add/Update)

Der Action-Key entscheidet über die Art. Er lautet
`Orm<Record-Typ><Verb>[Name]`: der Record-Typ voll ausgeschrieben, dann `Add`,
`Update`, `Retrieve` oder `Delete`, dahinter ein eigener Name, wenn ein Typ
mehr als einen Schlüssel dieses Verbs braucht — `OrmTDtoKundeAdd`,
`OrmTDtoKundeRetrieveByCity`. Die Zeile unter dem SQL-Feld zeigt, als welche
Art der Schlüssel gelesen wird und welches Statement der Server daraus baut.

1. **New**, **Action key** `OrmTDtoKundeAdd`, **Record type** `TDtoKunde`.
2. **Record fields** ausfüllen, falls der Typ nicht im Server einkompiliert ist
   (eine Feldzeile je Zeile, wie in Pascal).
3. **Key** setzen, wenn die Schlüsselspalte nicht `ID` heißt — Update
   und Delete verwenden ihn.
4. **Table** setzen, wenn die Tabelle nicht wie der Record-Typ ohne `TDto`
   und `Row` heißt — ein Record aus zwei Feldern, der in `Customer` schreibt,
   ist zum Beispiel ein Teil-Update. Ins SQL-Feld gibt es nichts zu schreiben:
   das Statement eines Orm-Schlüssels wird immer erzeugt, die Zeile unter dem
   Feld zeigt es.
5. **Enter record values…** öffnet ein Formular aus den Feldern des Typs.
   Nach *OK* läuft der Schreibvorgang sofort — mit Rollback, wenn angehakt.
6. **Save**, **Reload server**.

Zum Record-Dialog:

* Bei einem **Update** wird zuerst nach dem Schlüsselwert gefragt; die Zeile
  wird geladen und das Formular darauf geöffnet. Leer lassen öffnet auf
  Vorgabewerten.
* Das eingegebene JSON steht danach unter **sent as JSON** und wird je
  Schlüssel gemerkt — beim nächsten Öffnen ist das Formular vorbelegt.
* **Test** nimmt bei einem Record-Schreibvorgang genau dieses JSON (in dieser
  Reihenfolge: das Feld *sent as JSON*, dann die letzte Eingabe im
  Dialog, dann die Spalte *TestBounds*). Die **Parameterliste** wird dabei nie
  gelesen — die Werte eines Records kommen aus dem Record.
* Ein **Add** antwortet mit der Zeile, die die Datenbank gespeichert hat — dem
  vergebenen Schlüssel und jedem Vorgabewert, den sie eingesetzt hat. Sie
  steht im Reiter **Table**, zurückgerollt oder nicht, und ein Client
  bekommt dieselbe Zeile über `AddRecord` zurück.

---

## Einen Retrieve anlegen

Ein Retrieve ist ein where und eine Sortierung, sonst nichts: das Select drum
herum kommt immer aus dem Record-Typ.

1. **New**, **Action key** `OrmTDtoKundeRetrieveByCity`, **Record type**
   `TDtoKunde`. Sobald Schlüssel und Typ zusammenpassen, heißt das große Feld
   **where:**.
2. Das where ins Feld schreiben, ohne das Wort `where`: `City = ?`. Leer heißt
   alle Zeilen; eine Zeile über ihren Schlüssel ist `ID = ?`.
3. **order by** (weiter unten) nimmt die Sortierung, z. B. `Name`.
4. Die Zeile unter dem Feld zeigt das Statement, das der Server ausführt.
5. Je `?` einen Eintrag unter **Parameters**, dann **Test**. Die Antwort ist immer ein Array.

**Types** und **TestBounds** folgen dem where beim Tippen: ein Eintrag je `?`,
Vorhandenes bleibt stehen, ein fehlender Typ wird `text`, ein fehlender
Testwert `null`. Die Zeile unter dem Feld zeigt auf ein `null`, bis es ersetzt
ist, und **Save** fragt nach, bevor Testwerte gespeichert werden, die
nicht passen — *Check all* ruft jeden gespeicherten Eintrag mit seinen
eigenen Werten auf, also müssen es seine Werte sein.

Ein Select, das einen Join braucht oder Spalten, die der Record nicht hat, ist
kein Retrieve: das wird eine gewöhnliche Abfrage, mit einem Schlüssel ohne
`Orm`. Ein Delete (`Orm…Delete`) hat gar nichts zu schreiben — er geht über den
Schlüssel.

---

## Regeln, Caller-Scope, TestBounds

| Feld | Beispiel | Wirkung |
|---|---|---|
| **Rules** | `1:notempty;2:plz;3:email` | prüft Parameter *vor* dem Statement; verfügbar: `notempty`, `plz`, `email`, `len:min:max`, `range:min:max`, `oneof:a:b` |
| **Caller-Scope** | `userid` | das **letzte** `?` bindet der Server selbst mit der ID des Aufrufers; der Client schickt dafür keinen Wert |
| **order by** | `Name` | nur für `Orm…Retrieve…`: die Sortierung; das `where` steht im großen Feld |
| **TestBounds** | `["Wegberg"]` oder `{"ID":1,…}` | Testwerte für *Check all*; Array = Werteliste, Objekt = Record |

**JSON as TestBounds** übernimmt das, was gerade unter *sent as JSON*
steht, in die Spalte. Danach **Save**.

---

## Den ganzen Satz prüfen

**Check all** geht jedes Template durch:

* Ohne Verbindung: nur die Prüfungen, nichts wird ausgeführt.
* Mit Verbindung: Templates mit **TestBounds** laufen zusätzlich, immer in
  einer Transaktion, die zurückgerollt wird — unabhängig vom Rollback-Häkchen.
* Ergebnis je Zeile: `ok`, `open` (geprüft, nicht ausgeführt — mit Grund) oder
  `ERROR`, dazu eine Summenzeile.

---

## Über den Server ausführen

Häkchen **run through the server (with login)** unten:

* **Test** und **Check all** rufen dann den Server auf, wie ein Client es
  täte — mit Rechtemaske, Caller-Scope und Regeln.
* Es gehen nur **gespeicherte** Schlüssel: der Server führt registrierte
  Templates aus und hat für nichts anderes eine Methode. Ein Entwurf antwortet
  `sqlUnknownKey` — erst *Save*, dann *Reload server*.
* Der Server **rollt nichts zurück**. Ein Schreibvorgang wird deshalb vorher
  bestätigt; bei *Check all* einmal für den ganzen Lauf.
* Verlangt der Server ein Token, erscheint das Anmeldefenster (Demo-Konten:
  `admin` / `user`, Passwort `demo`).
* **Server** ist das Feld daneben, Vorgabe `localhost:8890`.

---

## Was welcher Knopf tut

| Knopf | Tut |
|---|---|
| **Check** | alles ohne Datenbank: Deklaration, Parameterzahl, Record-Typ, Regeln, ob der Server den Satz annähme |
| **Test** | führt aus — direkt oder über den Server, je nach Häkchen |
| **Save** | schreibt das Template in die Datei und exportiert `templates.sql` daneben |
| **Check all** | derselbe Prüflauf über alle Templates |
| **Reload server** | der Server liest seine Templates neu |
| **Generate CREATE TABLE** | beschreibt die Tabelle, die der Record-Typ braucht, im Dialekt der Auswahlliste daneben — Ergebnis steht im Log und auf der Zwischenablage. Erzeugt nur, führt nichts aus, und braucht keine Verbindung: gedacht für das Schema, das man jemandem gibt, der die Rechte auf dem Zielserver hat |
| **New / Delete** | Template anlegen bzw. entfernen |
| **Type from result** | baut aus dem letzten Ergebnis eine Record-Deklaration (Reiter *Type*) |
| **Cross-check** | setzt Werte in den Text ein, statt sie zu binden — nur zum Ansehen, so läuft nichts in Produktion |

---

## Wenn etwas nicht geht

| Meldung | Ursache |
|---|---|
| `sqlUnknownKey` über den Server | nicht gespeichert oder Server nicht neu geladen |
| `sqlNotAllowed` | die Maske des Templates passt nicht zum angemeldeten Konto |
| `sqlNeedsLogin` | Server läuft mit `token`, es wurde sich nicht angemeldet |
| `NOT NULL constraint failed` | ein `?` blieb ungebunden: Parameter fehlt |
| „CallerScope: der Editor bindet keine Identität" | direkt nicht ausführbar — über den Server testen |
| Editor hängt beim Verbinden | ODBC ohne Tunnel oder ohne Kerberos-Ticket |
