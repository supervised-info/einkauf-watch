# Regenerationsspec: native Einkauf (iPhone + Watch)

Stand der nativen App: 2026-09-04 (Build 55, `CURRENT_PROJECT_VERSION`). Nur **diese eine** Spec-Datei im Repo-Root (`Description.md`, kein zweites `Description_index.md`). Swift-Quellen sind die Wahrheit: bei Widerspruch den Code prüfen, nichts erfinden, die Website nicht scrapen.

Begleit-App zur HTML-PWA [einkauf](https://supervised-info.github.io/einkauf/) und zur To-Do-PWA [todo](https://supervised-info.github.io/todo/). HTML-Spec Einkauf: Pages `einkauf/Description_index.md`. Brücke Einkauf: Backup-JSON (`kind: "einkauf-backup"`); To-Do: `format: "todo-v3-json"`. Kein Live-localStorage-Sync, kein Netz für Wörterbuch oder Liste.

## Zweck

Zwei Domains in **einer** App **Einkauf** (`TabView` **Einkauf | To-Do**, SF-Symbols `basket` / `checklist`) auf iPhone und Apple Watch:

- **Einkauf:** Liste nach Ladenweg auf **iPhone** (Geh-Modus + Edit inkl. abteilungsübergreifendem Ziehen) und **Watch** (nur Geh-Modus). Dieselbe Liste, Abhaken über WatchConnectivity. Seeds plus eigene Läden, Stamm, gespeicherte Anlass-Listen, lokales Keyword-Wörterbuch, Backup-JSON (`kind: "einkauf-backup"`), Listen-PDF mit **leeren quadratischen** Kästchen.
- **To-Do:** Aufgaben (Text, Person, Prio A/B, Datum) auf **iPhone** (Liste + Edit) und **Watch** (nur Geh-Modus). Eigener Store und eigene Dateien — siehe **To-Do**.

Sprache nur über **Siri App Intents** für **beide** Domains (kein Watch-Mikro, kein `Speech.framework`): Einkauf **besorgen** + Nachfrage **„o“**; To-Do ein Phrase-Token **Todo**, iPhone **„o“**, Watch ohne `requestValueDialog`. Ein `AppShortcutsProvider` `EinkaufShortcuts`. Siehe **Sprach-Eingabe (Siri)**.

TestFlight ist nicht Voraussetzung. v1 ist nicht für den App-Store-Submit gedacht. Changelog der To-Do-Phasen: [`Docs/TodoIntegration.md`](Docs/TodoIntegration.md). Phase 10 (benannte Listen) ist geliefert (Build 55). Diese Datei beschreibt den gelieferten Stand.

## To-Do

Geliefert (Build 55). Begleit-Slice zur HTML-PWA [todo](https://supervised-info.github.io/todo/) (Pages `todo/Description_index.md`). Native scrapt die Website nicht. Brücke: JSON `format: "todo-v3-json"` (`todo-liste.json`) plus MD/CSV (`TodoMarkdown` / `TodoCSV`, Dateien `todo-liste.md` / `todo-liste.csv`, **volle Liste** unabhängig vom Auge und vom Listenfilter). Kein Live-localStorage, kein Netz. **Kein** To-Do-Homescreen-Widget. Benannte Listen (Phase 10) sind nativ gelandet; **Kein** HTML-Parity für Site-Mast — HTML-Listen sind ein separates Follow-up auf derselben JSON-Schema-Erweiterung. Reopen, Sort, Suche, MD/CSV und Listen sind gelandet.

### Isolation (nicht mit Einkauf mischen)

`TabView` **Einkauf | To-Do** auf iPhone (`EinkaufRoot`) und Watch (`WatchRoot`). Einkaufs-Tab bleibt `ContentView` / `WatchListView` ohne `TodoStore` in der Einkaufs-UI.

| | Einkauf | To-Do |
|---|---|---|
| Store | `ShoppingStore` | `TodoStore` |
| Datei | `einkauf-local.json` | `todo-local.json` |
| Ordner | App Group `Einkauf/` | **derselbe** Ordner |
| Local | `kind: "einkauf-local"` | `kind: "todo-local"` |
| Backup | `kind: "einkauf-backup"` | `format: "todo-v3-json"` |
| Disk-Notify | `.einkaufStateDidChangeOnDisk` | `.todoStateDidChangeOnDisk` |
| Siri-Queue | `einkauf.siriPendingAdds` | `todo.siriPendingAdds` |

App Group bleibt `group.net.tschelle.einkauf`. Isolation ist **Dateiname + Envelope-`kind`/`format`**, nicht ein zweites Bundle. Decoder lehnen fremdes `kind` ab. `BackupCodec.looksLikeBackup` darf `todo-v3-json` nicht schlucken; Import-Router (`IncomingJSON` auf `EinkaufRoot`) prüft zuerst `format`/`kind`: To-Do → `TodoStore` + To-Do-Tab; Einkauf → `ShoppingStore` + Einkaufs-Tab; sonst Fehler, nie still ins falsche Store. Widget-URL `einkauf://list` = Einkauf, `einkauf://todo` = To-Do.

To-Do **darf nicht** in `ShoppingStore` / `AppState` / `Item` / `einkauf-local.json` / `kind: einkauf-backup` / Einkauf-WC-Kinds liegen.

### iPhone (`TodoListView`)

`NavigationStack`, Titel **To-Do** (inline). Theme wie Einkauf (`AppearanceSettings`). Eigenes Overflow **…** — Einkaufs-Toolbar bleibt im Einkaufs-Tab.

Felder je Aufgabe: `text`, `person`, `prioA` (A–Z oder leer), `prioB` (1–9 oder leer), `dueDate` (`YYYY-MM-DD`), optionales `listId`. Zeile: Text; Person / Prio / Datum als Nebeninfo, wenn gesetzt. Overdue (`dueDate < heute`, lokal, nicht `9999*`) in `theme.oxide`. Add-Leiste: Person, Prio-Picker („– Prio“ / „–“), Datum, Text „Neue Aufgabe …“, **Hinzufügen**. Neue Aufgaben aus der Add-Leiste und Siri **Todo** landen in der **aktuellen** Liste; bei **Alle** bleibt `listId` leer.

**Aktuelle Liste:** `AppStorage` / UserDefaults `todo.iphone.currentListId` (leerer String = **Alle**, ungefiltert — inkl. Aufgaben ohne `listId`). Nicht im Backup-Envelope, nicht in `todo-local.json`. Toolbar-Menü (leading, nach der Lupe, Creme/native, deutsche Labels): **Alle**, benannte Listen, **Neue Liste…**, **Listen…** (anlegen / umbenennen / löschen mit Confirm). Löschen einer Liste leert `listId` ihrer Aufgaben — die Aufgaben selbst bleiben. Sichtbare Aufgaben = zuerst Listenfilter, dann Auge (`todo.iphone.showCompleted`), Suche, Sort, Personen-Gruppierung. Zähler `oo/xx/yy` der **gefilterten** Sicht (Liste, dann Auge). Edit-Sheet kann die Liste einer Aufgabe ändern.

Toolbar (trailing nach leading-Lupe und Listenmenü):

- Auge `eye` / `eye.slash` (`todo.iphone.showCompleted`, Default an; Accessibility „Abgeschlossene ausblenden“ / „einblenden“). Aus = erledigte in der Liste und in **Liste teilen** (PDF) verstecken; bleiben in `todo-local.json`. **Nicht** im Backup, **nicht** Watch, **nicht** `einkauf.iphone.hideCompleted`. Alles ausgeblendet: „Abgeschlossene ausgeblendet.“
- **Edit** / **Fertig** (`@State`, Default Listen-Modus). Toolbar-Label genau **Edit**, nicht „Bearbeiten“.
- Sort-Menü (`arrow.up.arrow.down`, `todo.iphone.sortKey`, Default Person; nicht Backup, nicht Watch): Person, Prio, Text, Enddatum, Abgeschlossen, Geschlossen.
- Overflow **…** (`ellipsis.circle`, „Mehr“): Backup importieren / exportieren / teilen, **MD exportieren…** / **MD teilen** / **CSV exportieren…** / **CSV teilen**, **Liste teilen**, Erledigte löschen. `fileImporter` `.json,.md,.markdown,.csv`. MD/CSV dump die **volle Liste** aller Aufgaben (`TodoMarkdown` / `TodoCSV`), nicht Auge und nicht Listenfilter; Listenmitgliedschaft optional (MD-Comment `Liste Name | list:id`, CSV-Spalten `Liste` / `List-ID` nur wenn Listen existieren). Import ohne Listeninfo bleibt gültig. PDF **Liste teilen** folgt der **aktuellen Liste und** `todo.iphone.showCompleted`. Kein Geh-Modus.

**Listen-Modus vs Edit (Swipe-Löschen nur im Edit-Modus):**

- Listen-Modus: Checkbox toggelt `completed`; **kein** Swipe-Löschen (`.deleteDisabled` + trailing `EmptyView()`, List-`.id` `todo-browse`). Text-Tipp und Leading-Swipe **Edit** öffnen `TodoEditSheet`.
- Edit-Modus: Swipe-Löschen nur via `.onDelete` (List-`.id` `todo-edit`); Zeile öffnet dasselbe Sheet (Text, Person, Prio A/B, Datum) über `todos.update`; Chevron-Affordance. Umschalten tauscht die List-Identität, damit SwiftUI keine löschbaren Zeilen wiederverwendet. Leading-Swipe **Edit** bleibt in beiden Modi.

`TodoEditSheet`: z. B. nach Siri (Person/Prio leer). `TodoTask` ist `Identifiable`/`Hashable` über `uid` für `.sheet(item:)`.

**Wieder öffnen:** nur erledigt und ohne `reopenedToUid` (`TodoOrdering.canReopen`). Confirm wie HTML: Original bleibt `completed` + `reopenedToUid`; offene Kopie mit neuem `uid`, gleichem Text/Person/Prio/Datum, `reopenedFromUid`, `reopenedAt` = heute ISO (`TodoStore.reopen`). Swipe / Context-Menü / Sheet. Ketten-Hinweis `von #` / `→ #` (Tipp scrollt; erledigte Kette blendet das Auge ein).

**Suche:** Lupe leading; Drawer, Placeholder **Person oder Text …**; filtert Person oder Text (case-insensitive) über Auge + Sort. Escape/Clear schließt. Keine Treffer: „Keine Treffer.“

Backup: Export `format: "todo-v3-json"` (`TodoCodec.encodeBackup`), Defaultname `todo-liste` / `yyyyMMdd_HHmm-todo-liste.json`. Envelope: `{format, exportedAt, nextUid, tasks, lists}`. `lists` ist optional (fehlt → `[]`): `[{id, name}]` mit stabilen String-IDs. Je Task optionales `listId` (fehlt / null / leer = keiner Liste zugeordnet, sichtbar unter **Alle**). Unbekannte Felder ignorieren. Alte Backups ohne `lists`/`listId` laden unverändert. Import Array oder `{format, nextUid, tasks, lists?}`; leer → direkt setzen; sonst **Anhängen** / **Ersetzen**. Anhängen merget `lists` per `id` (lokaler Name gewinnt). Kollidierende UIDs über `normalizeTasks`. Einkauf-JSON abgelehnt.

**MD/CSV** (Phase 8, Build 53; Listen-Meta Phase 10): Export/Import `TodoMarkdown` / `TodoCSV`; Dateiname `todo-liste.md` / `todo-liste.csv` (gestempelt wie JSON). **Volle Liste**, unabhängig vom Auge und vom Listenfilter. Listenmitgliedschaft rückwärtskompatibel (optional). Dateien ohne Listeninfo importieren wie bisher. Roundtrip der Fixtures `todo-liste.md` / `todo-liste.csv` bleibt. Import über denselben `fileImporter` (`.json,.md,.markdown,.csv`) und dieselben Anhängen/Ersetzen-Alerts. Einkauf-Dateien (JSON `einkauf-*`, MD `# Einkauf`, CSV-Kopf `Abteilung`) abgelehnt.

**Liste teilen** (PDF): A4-`TodoListPDF` (Einkauf-PDF unangetastet), Light-`ThemeRGB`, leere Quadrat-Kästchen, Durchstreichen für sichtbare Erledigte. Folgt der aktuellen Liste **und** `todo.iphone.showCompleted`. Gruppierung nach Person (leer → „Keine Person“), Sortierung wie die Liste (Person). Meta `oo/xx/yy` der **gedruckten** (gefilterten) Aufgaben; Dateiname `yyyyMMdd_HHmm-todo-liste.pdf`. Leere gefilterte Liste: deutscher Hinweis („Die Liste ist leer.“ / „Keine Aufgaben in dieser Liste.“ / „Keine offenen Aufgaben. Abgeschlossene sind ausgeblendet.“), kein leeres PDF.

### Watch-To-Do (nur Geh-Modus)

`WatchTodoListView`: Text (+ kompakte Person/Prio/Datum); Tippen toggelt `completed`; Auge `todo.watch.hideCompleted` (nicht `einkauf.watch.hideCompleted`, nicht Backup, nicht iPhone). Geh-Modus filtert auf dieselbe aktuelle Liste wie das iPhone. Titel: Listenname (oder **Alle**) plus `oo/xx/yy` der gefilterten Sicht. **Kein** Edit, kein Prio-Picker, kein Reopen, kein Import/Export, keine Suche, kein Sort, kein PDF/MD/CSV, keine Listen-Verwaltung.

### Complication

Eigene WidgetKit-Complication `TodoProgress` (Label genau **To Do**, Leerzeichen, nicht „To-Do“): offene Anzahl der **aktuellen Liste** bzw. bei 0 **erledigt**. Daten `todo-local.json` plus App-Group-Key `todo.currentListId`. Tap `einkauf://todo`. Details unter **Watch-To-Do-Complication**.

### WC-Context

Ein `applicationContext`-Dictionary, gemergt (`WatchSyncEnvelope`):

```
{ einkauf: { kind: "einkauf-sync", v, blob }, todo: { kind: "todo-sync", v, blob, currentListId } }
```

Beim Senden einer Domain: Context lesen, nur den eigenen Key setzen, zurückschreiben. Legacy top-level `kind == "einkauf-sync"` bleibt Einkauf-only. Messages: `todo-sync` / `todo-toggle` (`uid` `Int64`/`NSNumber`) / `todo-pull`. Ein `WatchSessionActor`. To-Do-Blob = `kind: "todo-local"` (trägt `lists` + je Task `listId`; Revision steigt bei Listen-CRUD und `listId`-Wechsel). Die aktuelle Listenwahl liegt **nicht** im Blob, sondern als Geschwisterfeld `currentListId` im `todo-sync`-Payload (leer = Alle). Die Watch schreibt das nach App-Group `todo.currentListId` (Complication + Geh-Modus). iPhone bleibt Quelle; Einkauf-Keys unangetastet. Siehe **WatchConnectivity**.

### Sprache

Siri `TodoAddItemsIntent` in **einem** `EinkaufShortcuts` (kein zweiter Provider, Phrase nicht „besorgen“). Ein Phrase-Token **Todo** (`shortTitle` **Todo**); iPhone-Nachfrage **„o“**; Watch **kein** `requestValueDialog`. Gesprochen **„Hey Siri, Einkauf Todo“**. Neue Aufgaben landen in der **aktuellen** Liste (`todo.iphone.currentListId` auf dem iPhone, gesynctes `todo.currentListId` auf der Watch). Zwei-Wort-Cap und Watch-Diktat: Phrase-Tokens + Watch-`shortTitle`/Dialog — siehe **Sprach-Eingabe (Siri)** (Verlaufspunkte 8–9).

## Datei-Ort, Targets, Bundle

| | |
|---|---|
| iPhone | Target `Einkauf`, Bundle `net.tschelle.einkauf`, Display-Name Einkauf, Portrait, nur iPhone (`TARGETED_DEVICE_FAMILY` 1), kein Mac Catalyst, App Group `group.net.tschelle.einkauf` |
| Watch | Target `EinkaufWatch`, Bundle `net.tschelle.einkauf.watchkitapp`, eingebettet (`embed: true`), Companion `net.tschelle.einkauf`, `WKRunsIndependentlyOfCompanionApp` YES |
| Watch-Complication | Target `EinkaufWatchWidgets`, Bundle `net.tschelle.einkauf.watchkitapp.widgets`, WidgetKit (watchOS 10, **kein ClockKit**), eingebettet in die Watch-App (`Embed Foundation Extensions`). Nicht auf dem iPhone. |
| iPhone-Widget | Target `EinkaufWidgets`, Bundle `net.tschelle.einkauf.widgets`, WidgetKit (iOS 17), Homescreen `systemSmall`/`systemMedium`, eingebettet in die iPhone-App. Nicht auf der Watch, nicht Sperrbildschirm. |
| Geteilter Code | `Sources/Shared` in beiden App-Targets (`ConnectivitySync.swift` nur Apple-Targets, nicht im SPM-Paket). **Siri:** `SpeechItemSplitter.swift` + `SiriPendingAdds.swift` / `TodoSiriPendingAdds.swift` + `EinkaufAddItemsIntent.swift` / `TodoAddItemsIntent.swift` (`AppIntent` + **ein** `AppShortcutsProvider` `EinkaufShortcuts` mit beiden Shortcuts) in iPhone- und Watch-App, nicht in den Widgets, Intents nicht im SPM-Paket. Widgets laden `einkauf-local.json` über `Persistence` und `todo-local.json` über `TodoPersistence` (ohne `ShoppingStore` / `TodoStore` / WatchConnectivity im Widget-Prozess). |
| iOS-UI | `Sources/iOS` — `EinkaufApp`, `ContentView`, `TodoListView`, `SettingsSheet`, `KeywordDictionaryView`, `ListPDF`, `TodoListPDF`, `ShareSheet`, `AppearanceSettings`, `HomeWidgetReload` |
| Watch-UI | `Sources/Watch` — `EinkaufWatchApp`, `WatchListView`, `WatchTodoListView`, `WatchComplicationReload` |
| Watch-Complication | `Sources/WatchWidgets` — `EinkaufWatchWidgets` + `TodoWatchWidgets` (WidgetKit `StaticConfiguration`, kinds `EinkaufProgress` / `TodoProgress`) |
| iPhone-Widget | `Sources/iOSWidgets` — `EinkaufWidgets` (WidgetKit `StaticConfiguration`) |
| Persistenz | `einkauf-local.json` (`kind: "einkauf-local"`) und `todo-local.json` (`kind: "todo-local"`) im App Group `group.net.tschelle.einkauf`, Ordner `Einkauf/` (iPhone-App + Widgets bzw. Watch-App + Complications; Geräte-Container getrennt). Fallback Application Support beim ersten Umzug. Decoder lehnen fremdes `kind` ab. Kein gemeinsames JSON, kein iCloud. |
| Backup-Dokumenttyp | JSON, UTType `net.tschelle.einkauf.backup` |
| Xcode | 15+, iOS 17, watchOS 10, Sprache de, Marketing 1.0 |
| Projekt | `Einkauf.xcodeproj` / `project.yml`; optional `Scripts/generate-xcodeproj.sh` |
| Fixtures | `Fixtures/einkauf-backup.json`, `Fixtures/einkauf-backup-ohne-staples.json`, `Fixtures/todo-v3-json.json`, `Fixtures/todo-liste.md`, `Fixtures/todo-liste.csv` (To-Do, nicht Einkauf-BackupCodec) |
| Linux-Check | `python3 Scripts/verify_core.py`; Swift-Tests `swift test` (Mac) |

Watch-UI-Änderung: Build-Nummer hochzählen, sonst bleibt die alte Companion-App. Zeigt die Watch weiter die alte UI: Einkauf auf der Watch löschen und unter Verfügbare Apps neu installieren. Complication folgt derselben Build-Nummer; nach Install die Komplikation auf dem Zifferblatt neu wählen, falls sie fehlt.

## Chrome / iPhone-Hauptansicht

`NavigationStack`, Titel **Einkaufsliste** (inline). Hintergrund Theme-Papier. Leere Liste: `ContentUnavailableView` „Noch nichts auf der Liste.“ + „Artikel hinzufügen oder ein Backup importieren.“

Toolbar:

- Links: **Ladenwahl**-Menü (`accessibilityLabel` „Laden“) — alle `stores`, aktueller mit Checkmark. Nur iPhone. Das Auge ersetzt dieses Menü **nicht**.
- Rechts: Auge `eye` / `eye.slash` (Accessibility „Erledigte ausblenden“ / „Erledigte einblenden“) neben dem Umschalter **Edit** / **Geh-Modus**. Tippen blendet abgehakte Artikel **im iPhone-Geh-Modus** und in **Liste teilen** (PDF) aus; Edit zeigt weiter alle. Artikel bleiben auf der Liste und im Backup. Abteilungen ohne sichtbare Artikel verschwinden (Geh-Modus und PDF). Alles erledigt und ausgeblendet: kurze Zeile „Erledigte ausgeblendet.“ Flag nur iPhone (`UserDefaults` / `AppStorage` `einkauf.iphone.hideCompleted`), **nicht** im einkauf-backup, **nicht** zur Watch.
- Rechts: Umschalter **Edit** / **Geh-Modus** (zeigt den jeweils anderen Modus; Toolbar-Label **Edit**, nicht „Bearbeiten“). `walkMode` persistiert und liegt im Backup.
- Rechts: Overflow **…** (`ellipsis.circle`, Label „Mehr“).

Unten Add-Leiste: Placeholder „Milch, Äpfel, Klopapier…“, Submit **Hinzufügen**. Trim + Whitespace-Normalisierung; leer = no-op. Abteilung per `DepartmentGuesser.guess`.

Thema und Palette **nicht** in der Toolbar — nur in Einstellungen.

### Geh-Modus (iPhone + Watch)

Große Checkbox + Name, Durchstreichen wenn `done`. Tippen toggelt. Kein Grip, kein Dept-Select, kein Löschen, Name nicht editierbar. **Kein Swipe-Löschen** (jede Zeile `.deleteDisabled(true)`, kein `.onDelete`, trailing `swipeActions` nur `EmptyView()` gegen das System-Delete). Flache `ForEach`-Zeilen (`WalkListRow` / `WalkLine`): Überschrift dann Artikel. **Keine** SwiftUI-`Section` — die verschluckt die Abteilungsreihenfolge beim Ladenwechsel. Zeilen-IDs enthalten Laden und Position (`storeId|index|…`). List-`.id` `walk|` bzw. `edit|` plus `currentStoreId` + Layout-Join, plus Gruppen-`.id` `einkauf-walk` / `einkauf-edit`, damit Geh-Modus die Edit-Liste (inkl. Swipe-Löschen) nicht wiederverwendet.

iPhone-Geh-Modus kann Erledigte ausblenden (Auge, `einkauf.iphone.hideCompleted`). Dasselbe Flag gilt für **Liste teilen**. Watch-Geh-Modus hat denselben Toggle mit **eigenem** Flag (`einkauf.watch.hideCompleted`). Die Flags synct nichts, Backup enthält sie nicht. Edit auf dem iPhone filtert nicht — erledigte Artikel bleiben editierbar.

### Edit (nur iPhone)

Flache Liste mit Überschriften (nicht verschiebbar, nicht löschbar) und Artikeln. `editMode` active.

Je Artikel: Checkbox, Name (Tipp → Rename; leer/Abbrechen = keine Änderung), Dept-`Picker` (alle `Department.allCases`), Ziehen, Swipe-Löschen.

**Cross-Dept-Drag** (`ItemEditing.moveRows`): Drop in jede sichtbare Abteilung inkl. `vor`/`nach`. Abteilungswechsel setzt `item.dept` und `mappings[mappingKey(name)]`. Gruppenreihenfolge kommt weiter vom Laden-Layout, nicht von der Drop-Reihenfolge der Überschriften. Überschrift als Quelle = no-op.

## Overflow-Menü (Reihenfolge)

1. Backup importieren…
2. Backup exportieren…
3. Backup teilen
4. Liste teilen
5. Einkaufsliste speichern
6. Untermenü **Gespeicherte Listen** (leer: disabled „Keine gespeicherten Listen“; sonst Tippen = `applySavedList`, auffüllen nicht ersetzen)
7. Untermenü **Stamm** — erstes Item immer **Gesamtliste** (`applyAllStaples`); danach ein Eintrag pro Stamm-Artikel (`applyStaple`)
8. Erledigte löschen
9. Divider
10. Einstellungen

Import: `fileImporter` JSON, ersetzt den Stand (kein Confirm). `onOpenURL` sitzt auf `EinkaufRoot` (nicht `ContentView`): Peek JSON — `todo-v3-json` / To-Do-Shape → `TodoStore` und To-Do-Tab; `kind: "einkauf-backup"` / `looksLikeBackup` → Einkauf wie bisher; sonst Fehler, nie still ins falsche Store. Widget-URL `einkauf://list` bleibt Einkaufs-Tab; `einkauf://todo` öffnet den To-Do-Tab. Unbekannte Felder ignorieren. Fehlende `staples` / `savedLists` → `[]`.

Export: `fileExporter`, Defaultname `einkauf-backup`.

Backup teilen: Temp-Datei `yyyyMMdd_HHmm-einkauf-backup.json` (`BackupShare.stampedFilename`), System-Share-Sheet (`.sheet(item:)`, immer existierende URL).

Liste teilen: A4-PDF (`ListPDF`), Dateiname `yyyyMMdd_HHmm-einkauf-{storeSlug}.pdf`. Light-Tokens der gewählten Palette (`dark: false`). Folgt dem Auge (`einkauf.iphone.hideCompleted`): Erledigte ausgeblendet → nur offene Artikel, gleiche Abteilungsreihenfolge wie `store.groups`, erledigte und leere Abteilungen weg (`ListGrouping.visibleGroups`); Erledigte sichtbar → alle Artikel. Meta-Zeile `progressLabel` als `oo/xx/yy` neu aus den **gedruckten** Zeilen (`openCount`/`doneCount` der PDF-Gruppen — nur offen: `n/0/n`). Checkboxen: **leeres Quadrat** (Stroke ~1.75pt, `roundedRect` radius 2.5, kein Fill, kein Häkchen) — `done` gilt nur für Durchstreichen/Farbe; gedruckte Zeilen behalten das leere Quadrat. Leere Liste: „Noch nichts auf der Liste.“

Einkaufsliste speichern: Alert „Einkaufsliste speichern“, Feld „Name, z. B. Grillen“, max 60. Leere aktuelle Liste → „Die Liste ist leer.“ Ungültiger Name → „Bitte einen Namen eingeben.“ Snapshot inkl. erledigter Artikel, nur `name`+`dept`, ohne Häkchen.

## Einstellungen (nur iPhone, Sheet)

Titel **Einstellungen**, Fertig schließt. Native-Sektionen **genau so** (Darstellung ist native-only). Gemeinsames Gerüst mit HTML: Aktueller Laden → Neuer Laden → Ladenweg → Stamm → Gespeicherte Listen → Wörterbuch. HTML schiebt **Alle Läden** JSON zwischen Neuer Laden und Ladenweg; Native hat dort nichts.

1. **Darstellung** — segmented Hell / Dunkel / System; segmented Creme / Blau. Footer: „Creme ist das Vintage-Papier, Blau die Navy-Palette. System folgt der iPhone-Einstellung für Hell und Dunkel.“ UserDefaults `einkauf.theme` / `einkauf.palette` (nicht im Backup).
2. **Aktueller Laden** — `ForEach(store.stores)`, Tippen wählt (`setStore`), Checkmark am aktuellen. **Swipe-Delete nur für `builtin == false`**. Builtin: `deleteDisabled`. Bestätigung: „Laden „{Name}“ wirklich löschen?“ Builtin-Seeds werden nie gelöscht (`StoreCatalog.delete` gibt `nil`). Löschen des aktuellen eigenen Ladens fällt auf `edeka` zurück; Seeds mergen.
3. **Neuer Laden** — Feld „Name des Ladens“ max 60, Anlegen. Footer: „Übernimmt das Layout des ausgewählten Ladens.“ (`StoreCatalog.create` kopiert `currentStore.layout`, `builtin: false`, id `s`+time36+random). Kein separater Knopf „Laden löschen“ zwischen Neuer Laden und Ladenweg.
4. **Ladenweg · {Name}** — `StoreLayout.sanitized`; `vor`/`nach` locked (`moveDisabled`, keine Pfeile/Entfernen). `sonstiges` ist **verschiebbar** (nicht locked) und folgt dem Layout-Slot — **geteilt mit HTML** (`groupItems` / `walkLayout`). `onMove` plus Nach oben / Nach unten / Entfernen für nicht-locked. Footer-Text aktuell: „Vor dem Einkauf immer vorn, Nach dem Einkauf immer hinten, Sonstiges direkt davor.“ — das lockt `sonstiges` **nicht**. HTML-Hinweis: „Sonstiges folgt der Position im Ladenweg.“ Regeneratoren dürfen `sonstiges` nicht an `nach` festkleben.
5. **Abteilungen hinzufügen** — unused laut `StoreLayout.unused`; leer: „Alle Abteilungen sind im Layout.“ Sonst Button je Titel, Insert vor `nach`.
6. **Layout zurücksetzen** — builtin: Seed-Layout; eigener Laden: `["vor", "sonstiges", "nach"]`. Auch für Custom, nicht nur builtin.
7. **Stamm-Artikel** — Name, Dept-Picker, Löschen; Anlegen „Milch, Butter…“. Footer zu Gesamtliste. Kein Hoch/Runter der Stamm-Zeilen.
8. **Gespeicherte Listen** — leer: „Noch keine gespeicherten Listen.“ Sonst Tippen = `applySavedList` (auffüllen). Swipe-Delete mit Confirm „Gespeicherte Liste „{Name}“ wirklich löschen?“ Footer: Anlass-Listen, Tippen füllt auf ohne zu ersetzen, Wischen löscht.
9. **Wörterbuch** — NavigationLink, lokal `KeywordDictionary.source`, Suche „Wort suchen“ filtert **Meine Zuordnungen** und die mitgelieferten Wörter. Oben Sektion **Meine Zuordnungen**: Zeilen aus `state.mappings` (Key = `mappingKey`/Canon ohne Menge + Dept-Picker alle `Department.allCases`). Swipe-Delete ruft `removeMapping`. Leer: „Noch keine eigenen Zuordnungen. Abteilung im Bearbeiten-Modus ändern — dann erscheint der Name hier.“ Optional **Hinzufügen** (Name + Dept → `setMapping` / `mappingKey(name)`). Darunter die mitgelieferten Gruppen nur lesen. Footer: mitgelieferte Wortliste ist fest; eigene Zuordnungen stehen im Backup als `mappings` und gewinnen beim nächsten Eintragen; Sonderregeln (TK, Eistee, Schorle, Chips, Eis) stehen nicht in dieser Liste; Korrekturen unter dem Artikelnamen (ohne Menge); das Wörterbuch selbst ändert sich nicht. Kein Netz. `setMapping` / `removeMapping` persistieren und WatchConnectivity wie andere State-Änderungen (inkl. Home-Widget-Reload).

Kein Theme in der Watch-App. Watch-Root: Palette Vintage + System-`colorScheme` (iPhone-Darstellung synct nicht).

## Watch

`TabView` **Einkauf | To-Do** (`basket` / `checklist`). Einkaufs-Tab: nur Geh-Modus, wie bisher. To-Do-Tab: nur Geh-Modus — Text (+ kompakte Person/Prio/Datum); Tippen toggelt `completed`; Auge `todo.watch.hideCompleted` (nicht `einkauf.watch.hideCompleted`, nicht Backup, nicht iPhone); Filter auf die vom iPhone gesyncte aktuelle Liste (`todo.currentListId`, leer = Alle). Kein Edit, kein Prio-Picker, kein Reopen, kein Import/Export, keine Suche, kein Sort, keine Listen-Verwaltung auf der Watch. iPhone-To-Do: siehe **To-Do**.

Navigationsleiste **ausgeblendet** (`.toolbar(.hidden, for: .navigationBar)`): `.navigationTitle("")` reserviert die Bar weiter und lässt eine Lücke unter der Uhr. Die **Systemuhr** bleibt Status und sichtbar. Inhalt direkt darunter (`VStack(spacing: 0)`): zuerst die Augen-Leiste, darunter die Titelzeile **eine Zeile** (`Text(store.state.watchTitle)`): gekürzter Ladenname + zwei Leerzeichen + `Einkauf oo/xx/yy` (`AppState.watchTitle`). Limit 6 Zeichen vor „Einkauf oo/xx/yy“; länger: 5 Zeichen + `…`. Edeka/Aldi/Rewe/Lidl/dm ungekürzt; „Eigenes Layout“ → `Eigen…`. Zähler inkl. `vor`/`nach` (`openCount/doneCount/items.count`). **Nicht** `.navigationTitle(watchTitle)`.

Kein Store-Picker, kein Edit, kein Share, kein Backup, kein Speichern, kein Wörterbuch, kein Löschen von Läden. Digital Crown scrollt die `List`. Leer: „Noch nichts auf der Liste.“ **Kein** In-App-Mikrofon, **kein** Diktat-Panel, **kein** `Speech.framework` / AVFoundation-Speech, **kein** `TextFieldLink` / `presentTextInputController`. Sprache nur über **Siri App Intents** — siehe **Sprach-Eingabe (Siri)**.

Auge **zuerst über der Titelzeile**, links (`HStack { Button…; Spacer() }`, Chrome über `watchTitle` und der `List` — **nicht** in `.topBarLeading`; **nicht** `.topBarTrailing`, die Uhr überdeckt das; **nicht** in der Toolbar, Navigationsleiste ausgeblendet): kleines SF-Symbol `eye` wenn Erledigte sichtbar, `eye.slash` wenn ausgeblendet — **plain Icon**, kein gefüllter runder watchOS-Button. Schrift `.font(.caption)` / ca. 14–16pt, `.imageScale(.small)`, `.buttonStyle(.plain)`. Glyph **grün** (`theme.good`, wie die erledigten Häkchen) wenn Erledigte sichtbar (`eye`); **grau** (`theme.muted`, wie Abteilungsüberschriften) wenn ausgeblendet (`eye.slash`). **Kompakte Zeile ~18–20pt**: **kein** `.frame(minHeight: 44)` / 44pt-Tapziel auf dem Image — das erzeugt leere Bänder zwischen Auge, Titel und erstem Listenartikel. Tap-Fläche eher horizontal über `contentShape`/Padding, ohne vertikale Totfläche. Darunter die Titelzeile kompakt, eine Zeile, lesbar (`theme.ink`). List: Top-`contentMargins` 0, erster Artikel direkt unter der Titelzeile; Leerzustände ohne allseitiges `.padding()`. Accessibility „Erledigte ausblenden“ / „Erledigte einblenden“. Tippen blendet abgehakte Artikel **nur in der Watch-Gehliste** aus; die Artikel bleiben auf der Liste und im Backup. Abteilungen ohne sichtbare Artikel verschwinden. Alles erledigt und ausgeblendet: kurze Zeile „Erledigte ausgeblendet.“ (Auge bleibt oben, Titel darunter). Flag nur auf der Watch (`UserDefaults` / `AppStorage` `einkauf.watch.hideCompleted`), **nicht** im einkauf-backup, **nicht** zum iPhone (das iPhone hat `einkauf.iphone.hideCompleted`). `watchTitle` zeigt weiter `oo/xx/yy` der vollen Liste. Die Complication zeigt nur die offene Anzahl (bei 0 „erledigt“).

### Watch-Complication (WidgetKit, watchOS 10)

Nur auf der **Apple Watch**, nicht auf dem iPhone-Sperrbildschirm. Kein ClockKit (`CLKComplicationDataSource` nicht vorhanden). Tippen öffnet die Watch-App (Geh-Modus-Liste, `widgetURL` `einkauf://list`).

Zähler **nur** die offenen Artikel (`ComplicationSnapshot.compactCountText`): `"\(openCount)"`. Bei 0 offenen (leere Liste oder alles abgehakt): das Wort **erledigt**, nicht `0` und nicht `oo/xx/yy`. `progressLabel` (`oo/xx/yy` / `0/0/0`) bleibt für Watch-Titel, iPhone-Widget, PDF, HTML. Kurzer Ladenname (`clippedWatchStoreName`) nur, wenn die Family Platz hat (Rechteck-Zeile, Ecken-`widgetLabel`). Weiter antippbar. VoiceOver: „Edeka, 5 offen“ bzw. bei 0 „Edeka, Liste erledigt“.

`accessoryCircular` darf **kein** großes System-`Text` (`.title2` / `.title3` / `.title`) für den Zähler nutzen: auf der physischen Watch passt das in Infograph/Modular compact nicht, `minimumScaleFactor` rettet accessory-Families oft nicht, und watchOS zeichnet dann ein alleinstehendes **!** statt zu kürzen. Stattdessen Gauge 0…1 (`done/total`, leer = 0) mit kleinem Zentrum (`caption`/`caption2`/ca. 11–13pt, **eine** Zeile offene Anzahl bzw. „erledigt“ — kein dreizeiliges `oo`/`xx`/`yy`). `accessoryCorner`: `compactCountText` **größer** als der Ladenname (~19pt semibold rounded vs. Caption/~11pt im `widgetLabel`), damit die offene Anzahl unter dem gebogenen Namen lesbar bleibt; `minimumScaleFactor` für „erledigt“. Rectangular schon großer Zähler (`.title2`). Alle Families: `.containerBackground` (watchOS 10).

Familien, die auf gängigen watchOS-10-Zifferblättern und im Smart Stack vorkommen:

| Family | Inhalt |
|---|---|
| `accessoryCircular` | Gauge 0…1 (`done/total`), kleines Zentrum nur offene Anzahl bzw. „erledigt“ (kein großes Text → sonst „!“) |
| `accessoryRectangular` | Ladenname + offene Anzahl bzw. „erledigt“ |
| `accessoryInline` | Laden + Zähler, sonst nur Zähler (`ViewThatFits`; 0 → „erledigt“) |
| `accessoryCorner` | großer Zähler (~19pt, 0 → „erledigt“), kleiner Ladenname im `widgetLabel` (~11pt) |

Datenquelle: dieselbe lokale Datei `einkauf-local.json` (`Persistence`, Envelope `kind: "einkauf-local"`). Watch-App und Complication teilen sie über App Group `group.net.tschelle.einkauf` (kein iCloud). Die Watch-App schreibt bei jeder `AppState`-Änderung (Artikel, Häkchen, Laden) und ruft `WidgetCenter.reloadTimelines` auf. iPhone-Änderungen kommen wie bisher per WatchConnectivity in die Watch-App und von dort in Datei + Complication. Fallback-Timeline alle 30 Minuten, falls ein Reload ausbleibt.

Kein Store-Picker, kein Edit, kein Share, kein Wörterbuch in der Complication.

### Watch-To-Do-Complication (WidgetKit, watchOS 10)

Eigene Complication `TodoComplication` / kind `TodoProgress` im selben WatchWidgets-Bundle, **neben** `EinkaufComplication` — kein Mix mit `einkauf-local.json`. Tippen: `widgetURL` `einkauf://todo` (Watch-Tab To-Do).

Label-Text genau **To Do** (Leerzeichen, nicht „To-Do“). Zähler nur offene Aufgaben der **aktuellen Liste** (`TodoComplicationSnapshot.make(from:currentListId:)`, `TodoCurrentList.syncedId`); bei 0 **erledigt** (auch wenn andere Listen noch offen sind). Corner: offene Anzahl ~19pt, Label **To Do** ~11pt im `widgetLabel` (wie Einkauf-Ecke). Circular: Gauge, kleines Zentrum, kein `.title2`. Datenquelle `todo-local.json` (`TodoPersistence` / `TodoCodec`, `kind: "todo-local"`) plus App-Group `todo.currentListId`. Reload: `WatchComplicationReload.todoTimelines()` nach `TodoStore`-Persist und nach WC-`currentListId`. Kein To-Do-Homescreen-Widget.

### iPhone-Widget (WidgetKit, iOS 17)

Nur auf dem **iPhone-Homescreen**, nicht auf der Watch und nicht auf dem Sperrbildschirm. Tippen öffnet die iPhone-App auf der Einkaufsliste (`widgetURL` `einkauf://list`). Leere Liste: `0/0/0`, weiter antippbar.

Anzeige: Fortschritt `openCount/doneCount/items.count` als `oo/xx/yy` (wie `AppState.watchTitle` / `AppState.progressLabel`, inkl. `vor`/`nach`). Ladenname ungekürzt (`currentStore.name`). Medium zusätzlich die nächsten **offenen** Artikelnamen in Geh-Modus-Reihenfolge (`ListGrouping`, erledigte ausgelassen).

| Family | Inhalt |
|---|---|
| `systemSmall` | Ladenname + `oo/xx/yy` |
| `systemMedium` | Ladenname + `oo/xx/yy` + nächste offene Artikel |

Datenquelle: dieselbe lokale Datei `einkauf-local.json` über App Group `group.net.tschelle.einkauf` (kein iCloud, kein Netz). Die iPhone-App tritt der Group bei und schreibt dort; nach Artikel/Häkchen/Laden `WidgetCenter.reloadTimelines`. Fallback-Timeline alle 30 Minuten.

## Sprach-Eingabe (Siri)

Sprache ist **kein** In-App-Mikrofon. Es gibt keinen Hold-to-Talk-Button, kein `Speech.framework`, kein `TextFieldLink`, kein `presentTextInputController` und kein In-App-`TextField` zum Diktat — diese Pfade sind bewusst tot. Stimme läuft nur über **Siri App Intents** auf iPhone (`Einkauf`) und Watch (`EinkaufWatch`) für **beide** Domains: `EinkaufAddItemsIntent` (**besorgen**) und `TodoAddItemsIntent` (**Todo**) in **einem** `EinkaufShortcuts` (`AppShortcutsProvider`; Apple erlaubt nur eine Conformance). Die Phrasen bleiben getrennte Ein-Token-Trigger. Shared: `SpeechItemSplitter.swift`, `SiriPendingAdds.swift`, `TodoSiriPendingAdds.swift`, `EinkaufAddItemsIntent.swift`, `TodoAddItemsIntent.swift` — in beiden App-Targets, nicht in den Widgets, Intents nicht im SPM-Paket.

Zwei-Wort-Kappen (Siri begrenzt Capture nach zwei Phrase-Tokens auf zwei Wörter) sind für Einkauf und To-Do gleich gelöst: **ein** Content-Token in der Phrase; To-Do zusätzlich Watch-`shortTitle` **Todo** und Watch ohne `requestValueDialog` — Verlauf unten.

### Was funktioniert

Phrase mit **App-Namen** (`\(.applicationName)`) plus Trigger **besorgen**. Apple erlaubt in Shortcut-Utterances nur `AppEntity` und `AppEnum` — **kein** freies `String` (`items`) in der Phrase; die Utterance muss **genau einmal** den App-Namen enthalten. Entdeckungs-Phrasen ausschließlich **besorgen** (nicht Bring-typisch „Artikel hinzufügen“, nicht „Einkauf“ allein als Cue):

- „{App} besorgen“
- „Besorgen mit {App}“
- „{App} zum Besorgen“

`shortTitle` „Besorgen“, Icon `cart.badge.plus`. Beispiel: „Hey Siri, Einkauf besorgen“ → Siri fragt „o“ (`requestValueDialog` „o“) → Nutzer spricht oder tippt Artikel, z. B. „Milch, Butter und Eier“. Parameter-Titel **Artikel**. iOS reserviert „besorgen“ **nicht** OS-weit; die Phrase ist Best Effort gegenüber Bring/Notizen.

Split wie `SpeechItemSplitter`: Komma, Semikolon, Zeilenumbruch, ` und `, ` sowie `; trimmen; Mengenwörter bleiben am Namen („zwei Eier“). Führendes `Einkauf:` / `Einkauf` / `Besorgen:` / `Besorgen` wird in `perform()` abgestreift (`SpeechItemSplitter.strippingTriggerPrefix`). Getippt darf die Antwort weiter mit `Einkauf:` beginnen. Jeder Teil derselbe Pfad wie getipptes Hinzufügen (`DepartmentGuesser` + `mappings`). `parameterSummary` darf `$items` zeigen (Intent-UI, nicht Utterance). `openAppWhenRun = false` auf beiden Plattformen.

**iPhone:** Intent legt `ShoppingStore(enableSync: true)` an und ruft `addItems(fromSpeech:)` — Persist + WatchConnectivity. Die laufende App zieht den neueren Disk-Stand bei `scenePhase == .active` nach (`reloadFromPersistenceIfNewer`). Siri-Dialog: „1 Artikel hinzugefügt.“ / „3 Artikel hinzugefügt.“ / leer → „Keine Artikel erkannt.“ `perform()` wirft nicht; Fehler → Dialog „Speichern fehlgeschlagen.“

**Watch:** Intent konstruiert **keinen** `ShoppingStore` und schreibt **keinen** vollen `AppState` (`Persistence.write`). `perform()` gibt ein schlichtes `IntentResult` **ohne** `ProvidesDialog` / `throws` zurück: zuerst `SiriPendingAdds.enqueue`, dann `return .result()`. Pending-Queue **primär** in `UserDefaults(suiteName: Persistence.appGroupId)` — Suite genau `group.net.tschelle.einkauf`, Key `einkauf.siriPendingAdds` (zuverlässiger zwischen Siri- und App-Prozess als eine Seitendatei). Datei `einkauf-siri-pending.json` nur als Spiegel unter der **expliziten App-Group-Container-URL** (`Persistence.appGroupContainerURL` / `Einkauf/`), nie Application Support eines anderen Prozesses. Suite `nil` → Fallback nur auf diese Container-Datei. Die Watch-App drain't `consumeSiriPendingAdds()` beim Aktivwerden (`scenePhase == .active`) **und** bei `WatchListView.onAppear` / Root-`.task`: `addItems(fromSpeech:)` auf dem **live** Store, Persist+Sync, Complication-Reload. Nach Siri die Watch-App einmal öffnen, falls die Phase verpasst wurde.

### To-Do Siri (`TodoAddItemsIntent`)

Trigger **Todo** (ein Wort, nicht **To Do** mit Leerzeichen, nicht **besorgen**). Siri-App-Shortcut-Phrasen mit zwei Inhaltstokens (`To Do`) begrenzen die danach gesprochene Aufgabe hart auf zwei Wörter — deshalb dasselbe Muster wie Besorgen: **ein** Content-Token. Phrasen mit genau einem App-Namen:

- „{App} Todo“
- „Todo mit {App}“
- „{App} zum Todo“
- „{App} Aufgaben“ (alternativer Ein-Token-Trigger)

`shortTitle` **„Todo“** (ein Token wie die Phrase — Watch-Siri keyed oft auf `shortTitle`; zwei Tokens `To Do` cappt Diktat auf zwei Wörter). Icon `checklist`. Shortcut in `EinkaufShortcuts` (kein zweiter Provider). iPhone-Nachfrage **„o“** (`requestValueDialog` „o“, wie Einkauf). watchOS: **kein** `requestValueDialog` — Siri nutzt die generische Freitext-Nachfrage (Custom-Dialog filtert/kürzt Free-Form auf der Watch). Parameter-Titel **Aufgaben**. Beispiel: **„Hey Siri, Einkauf Todo“** → iPhone fragt „o“, Watch den generischen Prompt → Aufgabe sprechen. Nach dem Update: Shortcut in Kurzbefehle löschen und neu anlegen, dann **„Auf Apple Watch anzeigen“** erneut aktivieren (sonst bleibt der gecachte Watch-Shortcut). `parameterSummary` ist **ein Token** `Todo \(.$items)` — analog Einkauf `Besorgen \(.$items)`. `openAppWhenRun = false`. Führendes `To Do` / `To-Do` / `todo` / `Todo` / `Aufgaben:` / `Aufgaben` wird abgestreift (`SpeechItemSplitter.strippingTodoTriggerPrefix`). Split wie Einkauf (`und` / Komma), **nicht** an Leerzeichen — „Rechnung bezahlen“ bleibt eine Aufgabe, „Katze füttern und Müll rausbringen“ zwei. iPhone: `TodoStore(enableSync: true)` + `addItems(fromSpeech:)`, Dialog „1 Aufgabe hinzugefügt.“ / „Keine Aufgaben erkannt.“ Person/Prio bleiben leer — auf dem iPhone danach **Edit** / `TodoEditSheet`. Watch: **kein** `TodoStore` im Intent; Queue `todo.siriPendingAdds` / Datei `todo-siri-pending.json` (nicht die Einkauf-Queue); Drain auf dem live Store beim Aktivwerden und `WatchTodoListView.onAppear`. Neue Aufgaben bekommen dasselbe `listId` wie die aktuelle Listenwahl (iPhone `todo.iphone.currentListId`, Watch gesynctes `todo.currentListId`; Alle → kein `listId`).

`makeID` (Item / SavedList / StoreCatalog) kodiert Epoch-Millis als **`Int64`**. watchOS `arm64_32` hat 32-bit `Int`; `Int(Date().timeIntervalSince1970 * 1000)` crasht sonst fatal in `Item.makeID` beim Drain (`consumeSiriPendingAdds`) und bei jedem neuen Item.

### Warum / Verlauf (wie wir es gelöst haben)

1. **Hold-to-Talk + Speech.framework** — Modul / `Speech.h` fehlt in dieser watchOS-Toolchain (Linken, ObjC-Bridge, Swift-`import Speech`: alles gescheitert). Deshalb kein Speech, kein In-App-Mikro.
2. **System-Diktat** (`presentTextInputController`, `TextFieldLink`, In-App-`TextField`) — Watch-Prozess beendet sich nach Fertig / Übernehmen.
3. Deshalb **Siri App Intents** statt In-App-Sprache.
4. Shortcut-Phrasen können kein freies `String` einbetten (Apple: nur `AppEntity` / `AppEnum`). Utterance braucht `applicationName`. Trigger **besorgen**, damit Siri nicht Bring oder Notizen nimmt. Die Nachfrage ist absichtlich **„o“** (`requestValueDialog` „o“) — nicht „ok“ und nicht ein langer Fragesatz; Siri soll nach der Phrase sofort den Artikel entgegennehmen.
5. Der Watch-Intent darf **keinen** `ShoppingStore` / vollen `AppState` bauen, **kein** `openAppWhenRun = true`, keine schweren Dialoge (`ProvidesDialog`) — sonst stiller Abbruch oder Crash, sobald der Artikel erkannt ist.
6. Deshalb Pending-Queue in der App Group; der live Store konsumiert später (`consumeSiriPendingAdds` beim Aktivwerden / `onAppear` / `.task`).
7. `makeID` **muss** Epoch-Millis als **`Int64`** nehmen. Auf der Watch ist `Int` 32-bit (`arm64_32`); ein Cast der Epoch-Millis nach `Int` overflowed und macht `consumeSiriPendingAdds` in `Item.makeID` fatal.
8. **To-Do-Phrase zwei Tokens** — Entdeckungs-Phrasen mit `To Do` (Leerzeichen) cappt Siri die gebundene Aufgabe auf genau zwei Wörter (3/4/5-Wort-Sätze wurden auf 2 gekürzt; `parameterSummary` `Todo \(.$items)` allein hat das nicht gelöst). Fix wie Besorgen: **ein** Phrase-Token `Todo`. Gesprochen **„Hey Siri, Einkauf Todo“**.
9. **Watch-Siri weiter zwei Wörter** — iPhone akzeptierte nach dem Phrase-Fix 3+ Wörter; Watch blieb bei 2. Ursachen: `shortTitle` „To Do“ (zwei Tokens; Watch keyed oft darauf) und watchOS-`requestValueDialog` „o“ (Custom-Dialog filtert Free-Form). Fix: `shortTitle` **Todo**; watchOS lässt `requestValueDialog` weg (generischer Prompt); iPhone behält **„o“**. Nach Install Shortcut löschen/neu und **„Auf Apple Watch anzeigen“** erneut.

## Abteilungen `Department` (IDs nicht ändern)

`vor` Vor dem Einkauf; `obst` Obst & Gemüse; `brot` Brot & Backwaren; `bedienung` Fleisch, Wurst, Käse; `kuehlung` Kühlregal; `tiefkuehl` Tiefkühl; `trocken` Trockenwaren; `suess` Süßwaren & Snacks; `getraenke` Getränke; `drogerie` Drogerie & Haushalt; `sonstiges` Sonstiges; `nach` Nach dem Einkauf.

Unbekannte Dept-ID → `Department.resolved` = `sonstiges` (Decode/Lookup). **`item.dept` beim Gruppieren nicht nach `sonstiges` umschreiben**, wenn die Abteilung bekannt, aber nicht im Layout ist.

### `ListGrouping.groups`

1. Layout = `StoreLayout.sanitized` (`vor` zuerst, `nach` zuletzt, Duplikate/Unbekannt raus; **`sonstiges` bleibt an der Layout-Position**).
2. Nur Gruppen mit Artikeln.
3. Layout-Gänge außer `nach` in Layout-Reihenfolge (inkl. `sonstiges`, wo es steht).
4. Extra-Abteilungen **mit Items**, die nicht im Layout stehen, danach — vor `nach` (`Department.allCases`-Reihenfolge).
5. `nach` zuletzt.
6. Innerhalb: `ord`, dann `added`, dann `localeCompare` de.

**Geteilt mit HTML** (`groupItems` / `walkLayout`, Spec 2026-09-02/03, Cache `einkauf-offline-v17`): Sonstiges bleibt, wo der Laden es platziert hat. Nicht aus dem Layout ziehen und vor `nach` kleben. Extra-Gänge bleiben Extra-Gänge; `item.dept` nicht nach `sonstiges` umschreiben.

Ladenwechsel: `setStore` erhöht `listRevision`, published `groups` neu, List-`.id` wechselt mit. SwiftUI darf Abschnitte nicht an der nackten Dept-ID wiederverwenden (`DeptGroup.id` = `storeId|dept`).

## Seed-Läden `Store.seeds` (builtin, immer mergen)

- edeka: vor, obst, bedienung, brot, kuehlung, tiefkuehl, trocken, suess, getraenke, drogerie, sonstiges, nach
- aldi: vor, obst, brot, kuehlung, tiefkuehl, trocken, suess, getraenke, drogerie, sonstiges, nach
- rewe: vor, obst, brot, bedienung, trocken, suess, kuehlung, tiefkuehl, getraenke, drogerie, sonstiges, nach
- lidl: vor, obst, brot, kuehlung, tiefkuehl, trocken, suess, getraenke, drogerie, sonstiges, nach
- dm: vor, drogerie, trocken, getraenke, sonstiges, nach
- eigenes: vor, sonstiges, nach — Name „Eigenes Layout“

Default `currentStoreId`: `edeka`. `BackupCodec.mergeBuiltinSeeds`: Seeds fehlen nie, `builtin` an Seed-IDs bleibt true, Custom hinten. Leeres `stores` im Backup → Seeds.

## Artikel-Modell

```
{ id, name, dept, done:boolean, added:number, ord:number }
```

`id` = `i` + time36 + random. Intern zusätzlich `doneChangedAt` (Sync); **PWA-/Backup-Export lässt es weg**. Sort in Dept: `sortOrd` (`ord` oder `added`), dann `added`, dann de.

`AppState`: `currentStoreId`, `stores`, `items`, `mappings`, `walkMode`, `staples`, `savedLists`, intern `listRevision`.

## DepartmentGuesser + KeywordDictionary

Lokal, **kein Netz**. `KeywordDictionary.source` ist die mitgelieferte Kopie von PWA `DICT_SRC` (nicht zur Laufzeit von der Website holen).

`guess(name, mappings)` in dieser Reihenfolge:

1. **`mappings[mappingKey(name)]`**, falls bekannte Dept — Nutzerkorrektur gewinnt für genau diesen Mapping-Key
2. Sonderregeln: TK / `tiefkuhl` → `tiefkuehl`; Eistee / ice tea → `getraenke`; Schorle / Saft-Ende → `getraenke`; chips → `suess`; eis (nicht eisberg) → `tiefkuehl`
3. Keywords aus `KeywordDictionary.source` (längstes Trefferwort)
4. sonst `sonstiges`

`mappingKey`: canon (ä→a, ö→o, ü→u, ß→ss, ae/oe/ue falten) + Mengen strippen. Select, Cross-Dept-Drop, Stamm-Dept, Wörterbuch-Picker und Rename (wenn der Key wechselt) schreiben denselben Key. `KeywordDictionary.source` bleibt zur Laufzeit unverändert.

Wörterbuch-UI: zuerst **Meine Zuordnungen** aus `mappings` (edit/delete, optional Hinzufügen), Suche filtert diese und die mitgelieferten Wörter. Darunter Gruppen nach `Department.title`, Wörter je Abteilung alphabetisch de, Duplikate/Leer raus — nur lesen. `vor`/`nach`/`sonstiges` haben keine `source`-Keys. Footer: mitgelieferte Liste fest; eigene Zuordnungen im Backup als `mappings` und gewinnen beim nächsten Eintragen; Korrekturen unter dem Artikelnamen (ohne Menge); das Wörterbuch selbst ändert sich nicht. Kein zweites Backup-Feld.

## Stamm

`staples`: `{ name, dept }[]`. `sanitizeStaples` akzeptiert alte Strings und Objekte; Duplikate via `mappingKey`; ungültiges `dept` → `guess`. `applyStaple` / `applyAllStaples` wie HTML: fehlend anlegen, erledigt wieder öffnen, schon offene zählen/`already`. Anlegen: gleicher `mappingKey` = no-op.

## Gespeicherte Listen

Geteilt mit HTML. `SavedList`: `{ id, name, items: [{ name, dept }] }`. id `l`+time36+random. Name max 60, Duplikat-Namen erlaubt (verschiedene ids). Snapshot der **aktuellen** Artikel inkl. erledigter — nur Name+Abteilung, ohne `done`/`id`. Leere Liste nicht speichern.

Apply = `StapleApply.applyAll` auf die Snapshot-Items: **füllen, nicht ersetzen**. Offene bleiben, Matching per `mappingKey` öffnet erledigte wieder, fehlende kommen dazu.

Backup-Feld `savedLists`. Alte Backups ohne Feld → `[]`. Sanitize: `done` auf Snapshot-Items ignorieren; leere/namenslose Listen verwerfen.

Watch hat keine UI dafür; der Stand liegt in `AppState` und synct mit.

## Backup JSON `kind: "einkauf-backup"`

Gleiche Datei wie die PWA, inkl. geteiltem `savedLists`. Export (`BackupCodec.encodeExport`):

```
{
  kind: "einkauf-backup",
  v: 1,
  currentStoreId,
  stores: [{ id, name, layout[], builtin }],
  mappings,
  items: [{ id, name, dept, done, added, ord }],
  walkMode,
  layoutTrip: 1,
  staples: [{ name, dept }],
  savedLists: [{ id, name, items: [{ name, dept }] }]
}
```

Kein `listRevision`, kein `doneChangedAt` im Export. Pretty + sortedKeys. `kind: "einkauf-laeden"` ist **kein** Backup (`BackupError.notABackup`). `v == 1` plus `items`+`stores` Arrays gelten auch ohne `kind`.

Lokal: `kind: "einkauf-local"` mit internem State (Revision, `doneChangedAt`, `savedLists`).

Import ersetzt den Stand und setzt `listRevision = max(lokal, import) + 1`.

## WatchConnectivity

`WCSession.applicationContext` ist **ein** Dictionary — letzter Schreiber gewinnt. Deshalb gemergtes Envelope (`WatchSyncEnvelope`):

```
{
  einkauf: { kind: "einkauf-sync", v: 1, blob },
  todo:    { kind: "todo-sync",    v: 1, blob }
}
```

Beim Senden einer Domain: aktuellen `session.applicationContext` lesen, nur den eigenen Key setzen, zurückschreiben. Legacy top-level `kind == "einkauf-sync"` weiter als Einkauf-only lesen. Messages bleiben domain-spezifisch: `einkauf-sync` / `einkauf-toggle` / `einkauf-pull` und `todo-sync` / `todo-toggle` (`uid` als `Int64`/`NSNumber`) / `todo-pull`. Ein `WatchSessionActor` (kein zweites `WCSession.delegate`). To-Do-Blob = `kind: "todo-local"` (`TodoCodec`); Einkauf-Blob nie als To-Do dekodieren und umgekehrt.

Einkauf-Merge (`StateMerge`): Listenstruktur folgt höherer `listRevision`; `done` je Artikel über `doneChangedAt`. To-Do-Merge (`TodoMerge`): Struktur über `revision`; `completed` über `updatedAt`. Ohne Stempel: erledigt gewinnt. iPhone und Watch müssen sich einmal sehen (Bluetooth, Apps kurz aktiv).

## Theme-Tokens

Creme = vintage, Blau = navy. RGB wie HTML `:root` / `data-theme` / `data-palette` (`ThemeRGB.tokens`). Oxide = Akzent. Nur Einstellungen stellen um.

## Delta vs HTML (bewusst, nicht schließen)

HTML-Spec: Pages `einkauf/Description_index.md` (Stand 2026-09-02/03, SW `einkauf-offline-v17`). Regeneratoren der nativen App dürfen HTML-only nicht nachbauen; Regeneratoren der PWA dürfen Native-only nicht ins HTML ziehen.

**Gemeinsame Slice** (HTML und Native, Stand 2026-09-02/03):

- `savedLists` — Name+Dept-Snapshot, Apply **füllt** statt zu ersetzen; Backup-Feld; alte Backups `[]`
- Sonstiges-Slot im Ladenweg — `sonstiges` bleibt an der Layout-Position; Extra-Depts mit Items nach dem letzten Nicht-`nach`-Gang; `item.dept` nicht nach `sonstiges` umschreiben
- Wörterbuch — mitgelieferte Liste nur lesen, lokal aus `KeywordDictionary.source` / `DICT_SRC`, kein Netz; eigene Zuordnungen im gemeinsamen Backup-Feld `mappings` (kein zweites Feld)
- Settings-Reihenfolge (gemeinsames Gerüst): **Aktueller Laden → Neuer Laden → Ladenweg → Stamm → Gespeicherte Listen → Wörterbuch**

Native stellt **Darstellung** (Hell/Dunkel/System, Creme/Blau) davor. HTML hat **kein** Darstellung-Block im Sheet; Theme/Palette bleiben am Site-Mast. HTML schiebt **Alle Läden** JSON (`kind: "einkauf-laeden"`) zwischen Neuer Laden und Ladenweg — nur HTML.

**Nur HTML / in der PWA behalten:** Markdown kopieren / Datei / teilen; Import `.md`/`.txt`; nach Bring; nach Erinnerungen; extra Läden-JSON `kind: "einkauf-laeden"` (zwischen Neuer Laden und Ladenweg); Site-Mast Theme + Palette (`theme-btn`, `#paletteBtn`) und Shared Keys `supervised-info.theme` / `supervised-info.palette`; PWA Service Worker (`sw.js`, Cache-Bump, aktuell v17).

**Nur native / nicht ins HTML:** Watch (Geh-Modus, Titel gekürzter Laden + Einkauf oo/xx/yy, Erledigte ausblendbar, WidgetKit-Complication nur offene Anzahl bzw. „erledigt“, kein Picker/Edit/Share, **kein** In-App-Mikro); iPhone-Geh-Modus mit eigenem Auge (Edit ungefiltert); **iPhone-Homescreen-Widget** (`systemSmall`/`systemMedium`, Tap öffnet Einkaufsliste); **Siri / App Intents** für Einkauf (**besorgen** + „o“) und To-Do (**Todo**, iPhone „o“, Watch ohne `requestValueDialog`); **PDF Liste teilen** folgt dem iPhone-Auge (`einkauf.iphone.hideCompleted` bzw. To-Do `todo.iphone.showCompleted`), leere quadratische Kästchen; Erscheinungsbild **System** (folgt iPhone-Appearance) plus Hell/Dunkel und Creme/Blau **nur in Einstellungen**, nicht in der Toolbar; **To-Do**-Tab, Watch-Geh-To-Do, Complication **To Do**. TestFlight nicht erforderlich. Native-`guess` wertet Nutzer-Mappings vor Sonderregeln/Keywords aus (HTML-Reihenfolge kann abweichen).

Native To-Do liefert MD/CSV wie HTML (Phase 8, **volle Liste**) und benannte Listen (Phase 10, Build 55). **Kein** HTML-Parity für Site-Mast; HTML-Listen folgen dem hier definierten `todo-v3-json`-Schema in einem separaten Pages-PR.

**Brücke:** Einkauf nur Backup-JSON (`kind: "einkauf-backup"`, inkl. `savedLists`); To-Do JSON `format: "todo-v3-json"` plus MD/CSV-Dateien (`todo-liste.md` / `todo-liste.csv`). Kein Live-localStorage-Sync. Unbekannte Felder jeweils ignorieren. App scrapt die Website nicht.

## Nicht ändern

- Bundle-IDs `net.tschelle.einkauf` / `.watchkitapp` / `.watchkitapp.widgets` / `.widgets`
- Builtin-Laden-IDs und DEPT-IDs
- Backup-`kind` `einkauf-backup` und Export-Shape (ohne interne Keys, inkl. `savedLists`)
- `ListGrouping`: `sonstiges` folgt dem Layout; Extra-Depts behalten `item.dept` (geteilt mit HTML, nicht vor `nach` kleben)
- Guesser: Nutzer-Mapping vor Sonderregeln und Keywords; `KeywordDictionary.source` unverändert; lokal
- Watch bleibt Geh-Modus ohne Picker/Edit/Share (Auge blendet Erledigte nur an, löscht sie nicht); iPhone-Auge nur Geh-Modus, Edit ungefiltert; Flags geräte-lokal, nicht im Backup
- Kein Watch-in-App-Mikrofon, kein `Speech.framework`; Siri-Utterance mit App-Namen + **besorgen**, danach Nachfrage **„o“** (`requestValueDialog` „o“; Parameter-Titel bleibt **Artikel**; getippt optional `Einkauf:` / `Besorgen:`). To-Do: Phrase-Token **Todo** (nicht `To Do`), `shortTitle` **Todo**, ein `AppShortcutsProvider`; iPhone-Nachfrage **„o“**, Watch **kein** `requestValueDialog`
- Complication nur Watch/WidgetKit, nicht iPhone, kein ClockKit, kein iCloud. To-Do-Complication Label **To Do** (Leerzeichen), Zähler offene Anzahl / **erledigt**, Datei `todo-local.json`
- iPhone-Widget nur Homescreen (`systemSmall`/`systemMedium`), nicht Watch, nicht Sperrbildschirm, kein iCloud; kein To-Do-Homescreen-Widget
- Theme nur in Einstellungen; To-Do-Tab teilt `einkauf.theme` / `einkauf.palette`
- PDF-Kästchen leer (kein Fill, kein Häkchen)
- To-Do Isolation: eigener `TodoStore`, `todo-local.json` / `kind: "todo-local"`, Backup `todo-v3-json`; nie in `ShoppingStore` / `einkauf-local.json` / `kind: einkauf-backup`. WC merget `{einkauf, todo}`
- Swipe-Löschen To-Do **nur** im Edit-Modus (Toolbar **Edit** / **Fertig**); Einkauf Toolbar **Edit** / **Geh-Modus**, Geh-Modus analog ohne Swipe-Löschen
- Listen (Phase 10, Build 55) nativ: optionales `lists`/`listId`, Filter **Alle**, PDF+Siri+Watch folgen `currentListId`; HTML-Site nicht in diesem Repo
- Bewusstes Rest-Delta zur HTML-PWA (Watch, PDF Liste teilen, System-Appearance in Einstellungen vs. Markdown/Bring/Erinnerungen/`einkauf-laeden`/Mast/SW) nicht angleichen
- Gemeinsame Slice (savedLists, Sonstiges-Slot, Wörterbuch, Settings-Gerüst) nicht als Native-only oder HTML-only führen

## Akzeptanzkriterien

- [ ] Bundle `net.tschelle.einkauf`, Watch eingebettet, Geh-Modus Watch, iPhone Geh + Edit mit Cross-Dept-Drag.
- [ ] Seeds + Custom; Neuer Laden kopiert das Layout des ausgewählten Ladens; Swipe-Delete nur Custom in Einstellungen → Aktueller Laden; Builtins nie weg.
- [ ] Settings-Reihenfolge: Darstellung (Hell/Dunkel/System, Creme/Blau) → Aktueller Laden → Neuer Laden → Ladenweg (`sonstiges` movable, `vor`/`nach` locked) → Abteilungen hinzufügen → Reset → Stamm → Gespeicherte Listen (Apply + Swipe-Delete) → Wörterbuch.
- [ ] `ListGrouping` sanitized inkl. `sonstiges`-Position; Rest-Depts mit Items nach dem letzten Nicht-`nach`-Gang; kein Remap von `item.dept` nach `sonstiges`.
- [ ] `DepartmentGuesser` + `KeywordDictionary.source` lokal, kein Netz; Nutzer-Mapping vor Sonderregeln/Keywords.
- [ ] Wörterbuch **Meine Zuordnungen**: View/Edit/Delete von `mappings` (Picker, Swipe-Delete, optional Hinzufügen); mitgelieferte Liste nur lesen; Backup-Feld bleibt `mappings`.
- [ ] Gespeicherte Listen: Name+Dept-Snapshot, füllen nicht ersetzen, Backup-Feld `savedLists`.
- [ ] Backup `einkauf-backup` mit stores, items, staples, savedLists, walkMode, …; Backup teilen; Liste teilen PDF mit leeren Quadrat-Kästchen, respektiert das iPhone-Auge (`einkauf.iphone.hideCompleted`).
- [ ] Watch-Titel: gekürzter Ladenname + Einkauf oo/xx/yy; Auge blendet Erledigte nur in der Watch-Gehliste aus (`einkauf.watch.hideCompleted`, nicht Backup); iPhone-Geh-Modus hat dasselbe Auge mit `einkauf.iphone.hideCompleted`; Edit ungefiltert; kein Picker/Edit/Share auf der Watch; WatchConnectivity.
- [ ] Siri / App Intents: Utterance mit genau einem App-Namen + **besorgen** (kein `String`/`$items` in der Phrase; keine Bring-ähnlichen „hinzufügen“-Phrasen); Siri fragt „o“ (`requestValueDialog` „o“); getippte Antwort darf mit `Einkauf:` / `Besorgen:` beginnen; Splitter wie Sprache, Guesser+Mappings; iPhone Persistenz+WatchConnectivity, Watch-Siri schreibt nur eine Pending-Queue in App-Group-`UserDefaults` (`group.net.tschelle.einkauf`, kein `ShoppingStore` / kein volles `AppState`-Encode im Intent; `openAppWhenRun = false`; App übernimmt beim Aktivwerden **und** `onAppear` / `.task` — Watch-App ggf. einmal öffnen); leerer Text = freundliches No-op; kein Watch-Mikro, kein Speech.framework. iOS reserviert „besorgen“ nicht OS-weit (Best Effort vs Bring).
- [ ] Watch-Complication (WidgetKit, watchOS 10): nur offene Anzahl (`compactCountText`, bei 0 „erledigt“), Ladenname wo Platz, Tap öffnet Geh-Modus; Update aus `einkauf-local.json` / WatchConnectivity; nicht auf dem iPhone.
- [ ] iPhone-Widget (WidgetKit, iOS 17): `systemSmall` Laden + `oo/xx/yy`, `systemMedium` plus offene Artikel in Geh-Modus-Reihenfolge; Tap öffnet Einkaufsliste; App Group `group.net.tschelle.einkauf`; nicht auf der Watch.
- [ ] Theme nur in Einstellungen; HTML-Delta bleibt: kein Markdown/Bring/Erinnerungen/`einkauf-laeden`/PWA-SW/Mast-Theme in der nativen App; kein Watch/PDF/System-Appearance im HTML. Gemeinsame Slice (Listen, Sonstiges-Slot, Wörterbuch, Settings-Gerüst) nicht als Native-only führen.
- [ ] `TabView` **Einkauf | To-Do** auf iPhone und Watch; getrennte Stores/Dateien/Backups (`todo-local.json` / `kind: "todo-local"` / `format: "todo-v3-json"`); WC-Context `{einkauf, todo}`; nie To-Do in `ShoppingStore` / `einkauf-local.json`.
- [ ] iPhone-To-Do: Text, Person, Prio A/B, Datum, optionales `listId`; Auge `todo.iphone.showCompleted`; Listenfilter `todo.iphone.currentListId` (leer = **Alle**); **Edit** / **Fertig** (`TodoEditSheet`); Swipe-Löschen **nur** Edit (`todo-browse` / `todo-edit`); Wieder öffnen; Sort `todo.iphone.sortKey`; Suche **Person oder Text …**; Backup `todo-v3-json` inkl. `lists`; **Liste teilen** PDF `TodoListPDF` folgt Liste + Auge.
- [ ] Watch-To-Do nur Geh-Modus (Toggle, Auge `todo.watch.hideCompleted`); Filter `todo.currentListId` (WC-Feld, leer = Alle); kein Reopen/Suche/Sort/Edit/Listen-UI. Complication `TodoProgress`: Label **To Do**, offene Anzahl der aktuellen Liste / **erledigt**, `todo-local.json` + `todo.currentListId`, Tap `einkauf://todo`.
- [ ] To-Do-Siri: ein Phrase-Token **Todo** (`shortTitle` **Todo**, `parameterSummary` `Todo \(.$items)`), gesprochen **„Hey Siri, Einkauf Todo“**; iPhone `requestValueDialog` **„o“**; Watch **kein** `requestValueDialog`; ein `AppShortcutsProvider` `EinkaufShortcuts` (nicht „besorgen“); neue Aufgaben in die aktuelle Liste. Nach Update Shortcut löschen/neu und **„Auf Apple Watch anzeigen“** erneut. Zwei-Wort-Cap gelöst über Phrase-Tokens + Watch-`shortTitle`/Dialog (siehe Sprach-Eingabe).
- [ ] To-Do-MD/CSV auf dem iPhone (Phase 8 + Listen-Meta Phase 10): `TodoMarkdown` / `TodoCSV`, **volle Liste**, `fileImporter` `.json,.md,.markdown,.csv`. Watch ohne MD/CSV-UI. Kein To-Do-Homescreen-Widget. Benannte Listen Build 55.
