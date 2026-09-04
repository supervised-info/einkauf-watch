# Einkauf für iPhone und Apple Watch

Native Begleit-App zur [Einkaufs-PWA](https://supervised-info.github.io/einkauf/) und zur [To-Do-PWA](https://supervised-info.github.io/todo/). Zwei Reiter **Einkauf | To-Do** auf iPhone und Apple Watch. Einkauf: dieselbe Liste, Abhaken über **WatchConnectivity**. To-Do: eigener Store, Datei `todo-local.json`, Backup `todo-v3-json`. Brücke zur jeweiligen PWA ist JSON — die App scrapt die Website nicht.

Mindestens **Xcode 15**, iOS 17, watchOS 10. Im Apple-Developer-Account ein Team wählen. v1 ist nicht für den App-Store-Submit gedacht.

Dieses Repo wurde auf Linux erzeugt. **Simulator und `xcodebuild` wurden hier nicht ausgeführt.** Bitte auf dem Mac öffnen und dort bauen.

## Auf dem Mac öffnen

1. Repo klonen und `Einkauf.xcodeproj` in Xcode öffnen.
2. Target **Einkauf** → Signing & Capabilities → **Team** wählen (Bundle-IDs sind Platzhalter: `net.tschelle.einkauf` / `net.tschelle.einkauf.watchkitapp`).
3. Scheme **Einkauf** wählen.
4. Destination: iPhone (Gerät oder Simulator). Die Watch-App ist eingebettet und wird mitinstalliert.
5. Run (⌘R). Watch-Simulator: Scheme **EinkaufWatch** oder in der Destination das paarige Watch-Gerät wählen.

Nach einer Watch-UI-Änderung ist der Bundle-Bump über diese Build-Nummer automatisch; zeigt die Watch weiter die alte UI, Einkauf auf der Watch löschen und in der iPhone-Watch-App unter **Verfügbare Apps** neu installieren.

Projekt neu erzeugen (optional, Python 3, ohne XcodeGen):

```sh
chmod +x Scripts/generate-xcodeproj.sh
./Scripts/generate-xcodeproj.sh
```

Wenn [XcodeGen](https://github.com/yonaskolb/XcodeGen) installiert ist: `xcodegen generate` (nutzt `project.yml`).

## Backup importieren

Die App versteht PWA-Backups mit `"kind": "einkauf-backup"` (Einkaufs-Tab) und `"format": "todo-v3-json"` (To-Do-Tab). Unbekannte Felder werden ignoriert, fehlende `staples` sind in Ordnung. Der Import-Router entscheidet am Envelope, nie still ins falsche Store.

**In der App**

1. Rechts oben **…** → **Backup importieren…**
2. Datei in Dateien / iCloud wählen (z. B. `einkauf-backup.json`).

**Über die Share Sheet / Dateien**

- Eine `*.json` mit `einkauf-backup` an **Einkauf** übergeben. Die App ist als JSON-Dokumenttyp registriert.

**Export**

- **…** → **Backup exportieren…** schreibt dieselbe Form (`kind`, `v`, `currentStoreId`, `stores`, `items`, `mappings`, `walkMode`, `layoutTrip`, `staples`).
- **…** → **Backup teilen** schickt dieselbe JSON-Datei über das System-Teilen-Menü (`yyyyMMdd_HHmm-einkauf-backup.json`).

Beispiel-Dateien im Repo:

- `Fixtures/einkauf-backup.json` — volle Liste inkl. Stamm-Artikel und einem unbekannten Feld
- `Fixtures/einkauf-backup-ohne-staples.json` — ohne `staples`
- `Fixtures/todo-v3-json.json` — To-Do-Backup (`format: "todo-v3-json"`), nicht Einkauf

To-Do-Backup importiert man im **To-Do**-Tab (**…**), nicht über das Einkaufs-Overflow.

PWA-Export: in der Website Backup speichern/teilen, Datei aufs iPhone legen, hier importieren. Die Watch zeigt die Liste in Laden-/Abteilungsreihenfolge (`vor` zuerst, `nach` zuletzt).

## Bedienung

Zwei Reiter **Einkauf | To-Do** (`TabView`). Getrennte Stores, Dateien und Backups — Einkauf ändert nicht `todo-local.json` und umgekehrt.

**iPhone Einkauf:** **Geh-Modus** (große Checkbox + Name, ohne Ziehen, **kein** Swipe-Löschen) und **Edit** (Ziehen auch in andere Abteilungen, Umbenennen, Abteilungs-Picker, Swipe-Löschen). Toolbar **Edit** / **Geh-Modus** (zeigt den jeweils anderen Modus; nicht „Bearbeiten“); `walkMode` bleibt im Backup. Auge blendet Erledigte im Geh-Modus und in **Liste teilen** (PDF) aus; Edit zeigt weiter alle. Plus Artikel hinzufügen, **Ladenwahl** (eingebaute Seeds plus eigene Läden unter Einstellungen), Stamm, Einstellungen (Hell/Dunkel/System, Creme/Blau), Import/Export/Teilen.

**iPhone To-Do:** Text, Person, Prio A/B, Datum. Auge blendet Abgeschlossene (`todo.iphone.showCompleted`). Toolbar **Edit** / **Fertig**: Swipe-Löschen **nur** im Edit-Modus; Listen-Modus öffnet `TodoEditSheet` per Text oder Swipe **Bearbeiten**. Wieder öffnen, Sort, Suche (**Person oder Text …**), eigenes Backup `todo-v3-json`, **Liste teilen** (PDF folgt dem Auge). Kein MD/CSV.

**Watch (Geh-Modus):** Einkauf: große Checkbox + Name, gruppiert nach Abteilung. To-Do: Text (+ kompakte Person/Prio/Datum); **kein** Edit, kein Reopen, keine Suche. Tippen schaltet erledigt um. Digital Crown scrollt. Titel Einkauf: gekürzter Laden + `Einkauf oo/xx/yy`. Auge blendet Erledigte nur in der jeweiligen Watch-Liste aus (eigene Flags). **Kein** In-App-Mikrofon. **Complication:** Einkauf zeigt offene Anzahl (bei 0 **erledigt**); To-Do-Label genau **To Do** plus offene Anzahl / **erledigt**. Tippen öffnet den passenden Watch-Tab. Scheme **EinkaufWatch** auf die physische Watch installieren, danach Komplikation auf dem Zifferblatt hinzufügen.

**Sprache / Siri:** Kein Watch-Mikro, kein `Speech.framework`. Stattdessen Siri App Intents auf iPhone und Watch in **einem** `AppShortcutsProvider`: „Hey Siri, Einkauf besorgen“ (App-Name + **besorgen**, Nachfrage **„o“**). To-Do: **„Hey Siri, Einkauf Todo“** (ein Wort **Todo**, nicht „To Do“ — Siri begrenzt zwei Phrase-Tokens auf zwei Wörter; `shortTitle` ebenfalls **Todo**). iPhone-To-Do fragt **„o“**; Watch-To-Do nutzt die generische Freitext-Nachfrage (kein `requestValueDialog`, sonst kürzt die Watch Free-Form). Dann Artikel bzw. Aufgabe sprechen (Komma / `und` trennt mehrere, `SpeechItemSplitter`). Nach einem Update: Shortcut in Kurzbefehle löschen/neu und **„Auf Apple Watch anzeigen“** erneut aktivieren. iPhone schreibt sofort in den Store und synct. Watch legt nur in eine App-Group-Queue (`UserDefaults` + Datei-Spiegel); die Watch-App drain't beim Öffnen — ggf. einmal die App antippen. Details und Verlauf: `Description.md` → **Sprach-Eingabe (Siri)**.

**iPhone-Widget:** Homescreen klein (Laden + `oo/xx/yy`) und mittel (plus nächste offene Artikel). Tippen öffnet die App **Einkaufsliste**. Scheme **Einkauf** aufs iPhone; Widget über den Homescreen-Widget-Picker hinzufügen. App Group `group.net.tschelle.einkauf` für App und Widget aktivieren, falls Xcode danach fragt.

**Sync:** Jede Änderung speichert lokal und schickt den Stand per WatchConnectivity (`updateApplicationContext`, bei Erreichbarkeit `sendMessage`, sonst `transferUserInfo`). Abhaken mergen nach Zeitstempel; neue Artikel/Import folgen der höheren Listenrevision. iPhone und Watch müssen sich einmal sehen (typisch: Bluetooth, Apps im Vordergrund oder kurz aktiv).

## Tests

Swift-Paket-Tests (auf dem Mac):

```sh
swift test
```

Ohne Swift, nur Fixture/Projekt-Checks:

```sh
python3 Scripts/verify_core.py
```

## Technik

| | |
|---|---|
| Bundle ID | `net.tschelle.einkauf` (Watch: `.watchkitapp`, Watch-Widget: `.watchkitapp.widgets`, iPhone-Widget: `.widgets`) |
| Geteilter Code | `Sources/Shared` in den App-Targets |
| Persistenz | JSON im App Group `group.net.tschelle.einkauf` (kein iCloud): `einkauf-local.json` und `todo-local.json` |
| Abteilungen / Läden | wie die PWA (`edeka`, `aldi`, `rewe`, `lidl`, `dm`, `eigenes`) |

Stamm-Artikel lassen sich unter **Einstellungen** anlegen, entfernen und einer Abteilung zuordnen. **Stamm → Gesamtliste** setzt alle auf die Einkaufsliste (fehlende ergänzen, erledigte wieder öffnen).
