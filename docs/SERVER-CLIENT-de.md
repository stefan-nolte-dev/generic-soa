# Server und Test-Client — Bedienung

Kurzanleitung zum Zusammenspiel von `soa_sql_templates_server` und
`soa_sql_templates_client`. Die Begründungen stehen in
[DETAILS-de.md](DETAILS-de.md), der Editor in [EDITOR-de.md](EDITOR-de.md).

---

## Bauen

```bash
D=<fpcupdeluxe-installation>   # der Ordner mit lazarus/ und config_lazarus/
$D/lazarus/lazbuild --pcp=$D/config_lazarus src/proj/soa_sql_templates_server.lpi
$D/lazarus/lazbuild --pcp=$D/config_lazarus src/projclientlaz/soa_sql_templates_client.lpi
```

Die Programme landen in `bin/`.

---

## Server starten

```bash
cd bin
./soa_sql_templates_server                 # Profil demo   auf Port 8890
./soa_sql_templates_server mssql          # Profil mssql auf Port 8891
./soa_sql_templates_server token strict    # mit Anmeldung und Rechtemaske
./soa_sql_templates_server caller=2        # jeder Aufrufer ohne Token ist UserID 2
```

Die Schalter sind kombinierbar und stehen in beliebiger Reihenfolge hinter dem
Profil. Beendet wird mit **Enter** im selben Fenster — den Server nicht in den
Hintergrund schicken, sonst sieht man seine Meldungen nicht.

| Schalter | Wirkung |
|---|---|
| *(keiner)* | offener Betrieb: jeder Aufrufer gilt als Gruppe 1, kein Token nötig |
| `token` | ohne gültiges Bearer-Token wird jeder Aufruf mit `sqlNeedsLogin` abgelehnt |
| `strict` | ein Template ohne gesetzte Rechtemaske antwortet `sqlNotAllowed` |
| `caller=N` | Aufrufer ohne Token bekommen UserID `N` — um Caller-Scope ohne Anmeldung zu sehen |

Beim Start meldet er Port, Templates-Datei, Anzahl und Namen der Aktionen,
Profil, Datenbank und den Pfad der Logdatei (`bin/*.log`).

| Profil | Port | Templates | Datenbank |
|---|---|---|---|
| `demo` | 8890 | `bin/templates.sqlite` | `bin/demo.sqlite` |
| `mssql` | 8891 | `bin/templates_mssql.sqlite` | eine SQL-Server-Datenbank über ODBC (Weg dorthin und Anmeldung nötig) |

`templates_mssql_schema.sql` daneben legt die vier Tabellen an, die die
Templates dieses Profils lesen, mit ein paar erfundenen Zeilen — angelegt wird
im Projekt sonst nichts, also hat das Profil damit überhaupt etwas zu lesen.
Vorher `SQLSERVER_HOST` in `src/commonserv/SqlServerConn.pas` auf den eigenen
Server und `TargetDatabase` in `src/common/SqlProfiles.pas` auf die eigene
Datenbank setzen; beide tragen einen Platzhalter.

Beide Profile können gleichzeitig laufen — eigener Port, eigene Datenbank.

---

## Test-Client bedienen

1. `bin/soa_sql_templates_client` starten.
2. **Profil** wählen; **Server** wird daraus vorbelegt (`localhost:8890`).
3. **Aktionen vom Server holen** — die Liste **Aktion** füllt sich mit dem, was
   der Server kennt.
4. **Aktion** wählen.
5. **Bounds** eintragen: die Parameter als JSON-Array, z. B. `["Wegberg"]` oder
   `[2]`. Ohne Parameter leer lassen.
6. **Aktion ausführen**.
7. **Ansicht** schaltet zwischen **Tabelle** und **JSON**; darunter stehen die
   Meldungen.

Zwei Feinheiten:

* Ein Template mit **Caller-Scope** bekommt einen Wert **weniger** — die
  Identität bindet der Server.
* **Typisierter Test (demo)** läuft eine feste Folge typisierter Aufrufe gegen
  das Profil `demo` und schreibt das Ergebnis ins Log. Er schreibt auch Zeilen,
  gehört also nur an eine Testdatenbank.

---

## Anmelden

Läuft der Server mit `token`, antwortet er auf alles mit `sqlNeedsLogin`, bis
sich der Client angemeldet hat.

1. **Anmelden…** drücken.
2. Benutzer und Passwort eingeben — Demo-Konten:

   | Konto | Passwort | Lesen | Schreiben |
   |---|---|---|---|
   | `admin` | `demo` | Gruppe 1 und 2 | Gruppe 1 und 2 |
   | `user` | `demo` | Gruppe 1 | — |

3. Die Titelzeile zeigt danach den angemeldeten Benutzer und die Restlaufzeit
   des Tokens (300 Minuten).
4. Derselbe Knopf heißt danach **Abmelden**.

Das Token wird bei jedem Aufruf im `Authorization`-Kopf mitgeschickt. Es stirbt
mit dem Serverprozess — nach einem Neustart des Servers also neu anmelden.

Ohne Client geht dasselbe mit `curl`:

```bash
curl -s -X POST http://localhost:8890/sqltemplates/AppAuthTool.Login -d '["admin","demo",""]'
```

Die Antwort enthält das Token; damit dann:

```bash
curl -s -X POST http://localhost:8890/sqltemplates/AppSqlTool.GetJsonFromAction -H "Authorization: Bearer <token>" -d '["GetGehaelter",[],""]'
```

---

## Was die Statuswerte bedeuten

| Wert | Heißt |
|---|---|
| `sqlOk` | gelaufen |
| `sqlNoRows` | gelaufen, nichts gefunden — kein Fehler |
| `sqlNothingWritten` | gelaufen, keine Zeile getroffen |
| `sqlUnknownKey` | der Server kennt diesen Action-Key nicht |
| `sqlBadParams` | Anzahl, Typ oder eine Regel passt nicht |
| `sqlNotAllowed` | angemeldet, aber die Rechtemaske passt nicht |
| `sqlNeedsLogin` | kein oder kein gültiges Token |
| `sqlFailed` | die Datenbank hat abgelehnt — der Grund steht im Serverlog |

---

## Ein neues Template in Betrieb nehmen

1. Im **Editor** anlegen, testen, **Speichern**.
2. Im Editor **Server neu laden** — oder den Server neu starten.
3. Im Client **Aktionen vom Server holen**; der neue Schlüssel steht in der
   Liste.

Der Server nimmt einen kaputten Satz nicht an und behält den alten. Nur eine
kaputte Datei **beim Start** ist tödlich — dann sagt er es und läuft nicht an.

---

## Wenn etwas nicht geht

| Beobachtung | Ursache |
|---|---|
| Client meldet „kein Server" | Server läuft nicht, falscher Port, oder Profil und Port passen nicht zusammen |
| alles antwortet `sqlNeedsLogin` | Server läuft mit `token` — anmelden; nach einem Serverneustart erneut |
| alles antwortet `sqlNotAllowed` | Server läuft mit `strict` und das Template hat keine Maske, oder das Konto passt nicht dazu |
| neuer Schlüssel unbekannt | im Editor gespeichert, aber nicht *Server neu laden* gedrückt |
| Profil `mssql` hängt | kein Weg zum Server (VPN, Tunnel) oder Kerberos-Ticket abgelaufen (`kinit`) |
| Server startet nicht | Templates-Datei fehlt oder ist kaputt — die Konsole nennt den Grund |
