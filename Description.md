# Regenerationsspec: native Einkauf (iPhone + Watch)

Stand der nativen App: 2026-09-03 (Build 9, `CURRENT_PROJECT_VERSION`). Nur **diese eine** Spec-Datei im Repo-Root (`Description.md`, kein zweites `Description_index.md`). Swift-Quellen sind die Wahrheit: bei Widerspruch den Code prüfen, nichts erfinden, die Website nicht scrapen.

Begleit-App zur HTML-PWA [einkauf](https://supervised-info.github.io/einkauf/). HTML-Spec: Pages `einkauf/Description_index.md`. Brücke ist **nur** die Backup-JSON-Datei (`kind: "einkauf-backup"`). Kein Live-localStorage-Sync, kein Netz für Wörterbuch oder Liste.

## Zweck

Einkaufsliste nach Ladenweg auf **iPhone** (Geh-Modus + Bearbeiten inkl. abteilungsübergreifendem Ziehen) und **Apple Watch** (nur Geh-Modus). Dieselbe Liste, Abhaken über WatchConnectivity. Seeds plus eigene Läden, Stamm, gespeicherte Anlass-Listen, lokales Keyword-Wörterbuch, Backup-JSON und Listen-PDF mit **leeren quadratischen** Kästchen.

TestFlight ist nicht Voraussetzung. v1 ist nicht für den App-Store-Submit gedacht.

## Datei-Ort, Targets, Bundle

| | |
|---|---|
| iPhone | Target `Einkauf`, Bundle `net.tschelle.einkauf`, Display-Name Einkauf, Portrait, nur iPhone (`TARGETED_DEVICE_FAMILY` 1), kein Mac Catalyst |
| Watch | Target `EinkaufWatch`, Bundle `net.tschelle.einkauf.watchkitapp`, eingebettet (`embed: true`), Companion `net.tschelle.einkauf`, `WKRunsIndependentlyOfCompanionApp` YES |
| Watch-Complication | Target `EinkaufWatchWidgets`, Bundle `net.tschelle.einkauf.watchkitapp.widgets`, WidgetKit (watchOS 10, **kein ClockKit**), eingebettet in die Watch-App (`Embed Foundation Extensions`). Nicht auf dem iPhone. |
| Geteilter Code | `Sources/Shared` in beiden App-Targets (`ConnectivitySync.swift` nur Apple-Targets, nicht im SPM-Paket). Complication lädt `einkauf-local.json` über `Persistence` (ohne `ShoppingStore` / WatchConnectivity im Widget-Prozess). |
| iOS-UI | `Sources/iOS` — `EinkaufApp`, `ContentView`, `SettingsSheet`, `KeywordDictionaryView`, `ListPDF`, `ShareSheet`, `AppearanceSettings` |
| Watch-UI | `Sources/Watch` — `EinkaufWatchApp`, `WatchListView`, `WatchComplicationReload` |
| Watch-Complication | `Sources/WatchWidgets` — `EinkaufWatchWidgets` (WidgetKit `StaticConfiguration`) |
| Persistenz | Application Support `Einkauf/einkauf-local.json` auf dem iPhone; auf der Watch dieselbe Datei zusätzlich im App Group `group.net.tschelle.einkauf` (Complication), Envelope `kind: "einkauf-local"`. Kein iCloud. |
| Backup-Dokumenttyp | JSON, UTType `net.tschelle.einkauf.backup` |
| Xcode | 15+, iOS 17, watchOS 10, Sprache de, Marketing 1.0 |
| Projekt | `Einkauf.xcodeproj` / `project.yml`; optional `Scripts/generate-xcodeproj.sh` |
| Fixtures | `Fixtures/einkauf-backup.json`, `Fixtures/einkauf-backup-ohne-staples.json` |
| Linux-Check | `python3 Scripts/verify_core.py`; Swift-Tests `swift test` (Mac) |

Watch-UI-Änderung: Build-Nummer hochzählen, sonst bleibt die alte Companion-App. Zeigt die Watch weiter die alte UI: Einkauf auf der Watch löschen und unter Verfügbare Apps neu installieren. Complication folgt derselben Build-Nummer; nach Install die Komplikation auf dem Zifferblatt neu wählen, falls sie fehlt.

## Chrome / iPhone-Hauptansicht

`NavigationStack`, Titel **Einkaufsliste** (inline). Hintergrund Theme-Papier. Leere Liste: `ContentUnavailableView` „Noch nichts auf der Liste.“ + „Artikel hinzufügen oder ein Backup importieren.“

Toolbar:

- Links: **Ladenwahl**-Menü (`accessibilityLabel` „Laden“) — alle `stores`, aktueller mit Checkmark. Nur iPhone.
- Rechts: Umschalter **Geh-Modus** / **Bearbeiten** (zeigt den jeweils anderen Modus, wie die PWA). `walkMode` persistiert und liegt im Backup.
- Rechts: Overflow **…** (`ellipsis.circle`, Label „Mehr“).

Unten Add-Leiste: Placeholder „Milch, Äpfel, Klopapier…“, Submit **Hinzufügen**. Trim + Whitespace-Normalisierung; leer = no-op. Abteilung per `DepartmentGuesser.guess`.

Thema und Palette **nicht** in der Toolbar — nur in Einstellungen.

### Geh-Modus (iPhone + Watch)

Große Checkbox + Name, Durchstreichen wenn `done`. Tippen toggelt. Kein Grip, kein Dept-Select, kein Löschen, Name nicht editierbar. Flache `ForEach`-Zeilen (`WalkListRow` / `WalkLine`): Überschrift dann Artikel. **Keine** SwiftUI-`Section` — die verschluckt die Abteilungsreihenfolge beim Ladenwechsel. Zeilen-IDs enthalten Laden und Position (`storeId|index|…`). List-`.id` aus `currentStoreId` + Layout-Join.

### Bearbeiten (nur iPhone)

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

Import: `fileImporter` JSON, ersetzt den Stand (kein Confirm). `onOpenURL` dasselbe. Unbekannte Felder ignorieren. Fehlende `staples` / `savedLists` → `[]`.

Export: `fileExporter`, Defaultname `einkauf-backup`.

Backup teilen: Temp-Datei `yyyyMMdd_HHmm-einkauf-backup.json` (`BackupShare.stampedFilename`), System-Share-Sheet (`.sheet(item:)`, immer existierende URL).

Liste teilen: A4-PDF (`ListPDF`), Dateiname `yyyyMMdd_HHmm-einkauf-{storeSlug}.pdf`. Light-Tokens der gewählten Palette (`dark: false`). Checkboxen: **leeres Quadrat** (Stroke ~1.75pt, `roundedRect` radius 2.5, kein Fill, kein Häkchen) — `done` gilt nur für Durchstreichen/Farbe. Leere Liste: „Noch nichts auf der Liste.“

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
9. **Wörterbuch** — NavigationLink, nur lesen, lokal `KeywordDictionary.source`, Suche „Wort suchen“. Footer: Zuordnung nur lokal; Sonderregeln (TK, Eistee, Schorle, Chips, Eis) stehen nicht in dieser Liste. Kein Netz, keine Bearbeitung.

Kein Theme in der Watch-App. Watch-Root: Palette Vintage + System-`colorScheme` (iPhone-Darstellung synct nicht).

## Watch

Nur Geh-Modus. Navigation-Titel **eine Zeile**: gekürzter Ladenname + zwei Leerzeichen + `Einkauf xx/yy` (`AppState.watchTitle`). Limit 6 Zeichen vor „Einkauf xx/yy“; länger: 5 Zeichen + `…`. Edeka/Aldi/Rewe/Lidl/dm ungekürzt; „Eigenes Layout“ → `Eigen…`. Zähler inkl. `vor`/`nach` (`doneCount/items.count`).

Kein Store-Picker, kein Bearbeiten, kein Share, kein Backup, kein Speichern, kein Wörterbuch, kein Löschen von Läden. Digital Crown scrollt die `List`. Leer: „Noch nichts auf der Liste.“

### Watch-Complication (WidgetKit, watchOS 10)

Nur auf der **Apple Watch**, nicht auf dem iPhone-Sperrbildschirm. Kein ClockKit (`CLKComplicationDataSource` nicht vorhanden). Tippen öffnet die Watch-App (Geh-Modus-Liste, `widgetURL` `einkauf://list`).

Anzeige wie der Watch-Titel: Fortschritt `doneCount/items.count` als `xx/yy` (`AppState.progressLabel` / `ComplicationSnapshot`). Kurzer Ladenname (`clippedWatchStoreName`) nur, wenn die Family Platz hat. Leere Liste: `0/0` (weiter antippbar); VoiceOver sagt „leer“.

Familien, die auf gängigen watchOS-10-Zifferblättern und im Smart Stack vorkommen:

| Family | Inhalt |
|---|---|
| `accessoryCircular` | nur `xx/yy` |
| `accessoryRectangular` | Ladenname + `xx/yy` |
| `accessoryInline` | Laden + `xx/yy`, sonst nur `xx/yy` (`ViewThatFits`) |
| `accessoryCorner` | `xx/yy`, Ladenname im `widgetLabel` |

Datenquelle: dieselbe lokale Datei `einkauf-local.json` (`Persistence`, Envelope `kind: "einkauf-local"`). Watch-App und Complication teilen sie über App Group `group.net.tschelle.einkauf` (kein iCloud). Die Watch-App schreibt bei jeder `AppState`-Änderung (Artikel, Häkchen, Laden) und ruft `WidgetCenter.reloadTimelines` auf. iPhone-Änderungen kommen wie bisher per WatchConnectivity in die Watch-App und von dort in Datei + Complication. Fallback-Timeline alle 30 Minuten, falls ein Reload ausbleibt.

Kein Store-Picker, kein Bearbeiten, kein Share, kein Wörterbuch in der Complication.

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

1. Sonderregeln: TK / `tiefkuhl` → `tiefkuehl`; Eistee / ice tea → `getraenke`; Schorle / Saft-Ende → `getraenke`; chips → `suess`; eis (nicht eisberg) → `tiefkuehl`
2. Keywords aus `KeywordDictionary.source` (längstes Trefferwort)
3. **danach** `mappings[mappingKey(name)]`, falls bekannte Dept
4. sonst `sonstiges`

`mappingKey`: canon (ä→a, ö→o, ü→u, ß→ss, ae/oe/ue falten) + Mengen strippen. Select, Cross-Dept-Drop, Stamm-Dept und Rename (wenn der Key wechselt) schreiben denselben Key. Mappings kommen **nach** den Keywords, sie überschreiben einen Wörterbuch-Treffer nicht.

Wörterbuch-UI: Gruppen nach `Department.title`, Wörter je Abteilung alphabetisch de, Duplikate/Leer raus. `vor`/`nach`/`sonstiges` haben keine `source`-Keys.

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

`ConnectivitySync`: `updateApplicationContext`; wenn erreichbar `sendMessage`, sonst `transferUserInfo`. Payload `kind: "einkauf-sync"` + `blob` (lokales JSON). Toggle zusätzlich `kind: "einkauf-toggle"` (`id`, `done`, `at`). Watch pull: `kind: "einkauf-pull"`.

Merge (`StateMerge`): Listenstruktur folgt höherer `listRevision`; `done` je Artikel über `doneChangedAt`. Ohne Stempel und Konflikt: erledigt gewinnt. iPhone und Watch müssen sich einmal sehen (Bluetooth, Apps kurz aktiv).

## Theme-Tokens

Creme = vintage, Blau = navy. RGB wie HTML `:root` / `data-theme` / `data-palette` (`ThemeRGB.tokens`). Oxide = Akzent. Nur Einstellungen stellen um.

## Delta vs HTML (bewusst, nicht schließen)

HTML-Spec: Pages `einkauf/Description_index.md` (Stand 2026-09-02/03, SW `einkauf-offline-v17`). Regeneratoren der nativen App dürfen HTML-only nicht nachbauen; Regeneratoren der PWA dürfen Native-only nicht ins HTML ziehen.

**Gemeinsame Slice** (HTML und Native, Stand 2026-09-02/03):

- `savedLists` — Name+Dept-Snapshot, Apply **füllt** statt zu ersetzen; Backup-Feld; alte Backups `[]`
- Sonstiges-Slot im Ladenweg — `sonstiges` bleibt an der Layout-Position; Extra-Depts mit Items nach dem letzten Nicht-`nach`-Gang; `item.dept` nicht nach `sonstiges` umschreiben
- Wörterbuch — nur lesen, lokal aus `KeywordDictionary.source` / `DICT_SRC`, kein Netz
- Settings-Reihenfolge (gemeinsames Gerüst): **Aktueller Laden → Neuer Laden → Ladenweg → Stamm → Gespeicherte Listen → Wörterbuch**

Native stellt **Darstellung** (Hell/Dunkel/System, Creme/Blau) davor. HTML hat **kein** Darstellung-Block im Sheet; Theme/Palette bleiben am Site-Mast. HTML schiebt **Alle Läden** JSON (`kind: "einkauf-laeden"`) zwischen Neuer Laden und Ladenweg — nur HTML.

**Nur HTML / in der PWA behalten:** Markdown kopieren / Datei / teilen; Import `.md`/`.txt`; nach Bring; nach Erinnerungen; extra Läden-JSON `kind: "einkauf-laeden"` (zwischen Neuer Laden und Ladenweg); Site-Mast Theme + Palette (`theme-btn`, `#paletteBtn`) und Shared Keys `supervised-info.theme` / `supervised-info.palette`; PWA Service Worker (`sw.js`, Cache-Bump, aktuell v17).

**Nur native / nicht ins HTML:** Watch (Geh-Modus, Titel gekürzter Laden + Einkauf xx/yy, WidgetKit-Complication `xx/yy`, kein Picker/Edit/Share); **PDF Liste teilen** mit leeren quadratischen Kästchen; Erscheinungsbild **System** (folgt iPhone-Appearance) plus Hell/Dunkel und Creme/Blau **nur in Einstellungen**, nicht in der Toolbar. TestFlight nicht erforderlich.

**Brücke:** nur Backup-JSON-Datei (inkl. `savedLists`). Kein Live-localStorage-Sync. Unbekannte Felder jeweils ignorieren. App scrapt die Website nicht.

## Nicht ändern

- Bundle-IDs `net.tschelle.einkauf` / `.watchkitapp`
- Builtin-Laden-IDs und DEPT-IDs
- Backup-`kind` `einkauf-backup` und Export-Shape (ohne interne Keys, inkl. `savedLists`)
- `ListGrouping`: `sonstiges` folgt dem Layout; Extra-Depts behalten `item.dept` (geteilt mit HTML, nicht vor `nach` kleben)
- Guesser: Keywords vor Mappings; lokal
- Watch bleibt Geh-Modus ohne Picker/Edit/Share
- Complication nur Watch/WidgetKit, nicht iPhone, kein ClockKit, kein iCloud
- Theme nur in Einstellungen
- PDF-Kästchen leer (kein Fill, kein Häkchen)
- Bewusstes Rest-Delta zur HTML-PWA (Watch, PDF Liste teilen, System-Appearance in Einstellungen vs. Markdown/Bring/Erinnerungen/`einkauf-laeden`/Mast/SW) nicht angleichen
- Gemeinsame Slice (savedLists, Sonstiges-Slot, Wörterbuch, Settings-Gerüst) nicht als Native-only oder HTML-only führen

## Akzeptanzkriterien

- [ ] Bundle `net.tschelle.einkauf`, Watch eingebettet, Geh-Modus Watch, iPhone Geh + Bearbeiten mit Cross-Dept-Drag.
- [ ] Seeds + Custom; Neuer Laden kopiert das Layout des ausgewählten Ladens; Swipe-Delete nur Custom in Einstellungen → Aktueller Laden; Builtins nie weg.
- [ ] Settings-Reihenfolge: Darstellung (Hell/Dunkel/System, Creme/Blau) → Aktueller Laden → Neuer Laden → Ladenweg (`sonstiges` movable, `vor`/`nach` locked) → Abteilungen hinzufügen → Reset → Stamm → Gespeicherte Listen (Apply + Swipe-Delete) → Wörterbuch.
- [ ] `ListGrouping` sanitized inkl. `sonstiges`-Position; Rest-Depts mit Items nach dem letzten Nicht-`nach`-Gang; kein Remap von `item.dept` nach `sonstiges`.
- [ ] `DepartmentGuesser` + `KeywordDictionary.source` lokal, kein Netz; Mappings nach Keywords.
- [ ] Gespeicherte Listen: Name+Dept-Snapshot, füllen nicht ersetzen, Backup-Feld `savedLists`.
- [ ] Backup `einkauf-backup` mit stores, items, staples, savedLists, walkMode, …; Backup teilen; Liste teilen PDF mit leeren Quadrat-Kästchen.
- [ ] Watch-Titel: gekürzter Ladenname + Einkauf xx/yy; kein Picker/Edit/Share auf der Watch; WatchConnectivity.
- [ ] Watch-Complication (WidgetKit, watchOS 10): `xx/yy` inkl. vor/nach, Ladenname wo Platz, Tap öffnet Geh-Modus; Update aus `einkauf-local.json` / WatchConnectivity; nicht auf dem iPhone.
- [ ] Theme nur in Einstellungen; HTML-Delta bleibt: kein Markdown/Bring/Erinnerungen/`einkauf-laeden`/PWA-SW/Mast-Theme in der nativen App; kein Watch/PDF/System-Appearance im HTML. Gemeinsame Slice (Listen, Sonstiges-Slot, Wörterbuch, Settings-Gerüst) nicht als Native-only führen.
