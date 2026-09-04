# Regenerationsspec: native Einkauf (iPhone + Watch)

Stand der nativen App: 2026-09-04 (Build 37, `CURRENT_PROJECT_VERSION`). Nur **diese eine** Spec-Datei im Repo-Root (`Description.md`, kein zweites `Description_index.md`). Swift-Quellen sind die Wahrheit: bei Widerspruch den Code prüfen, nichts erfinden, die Website nicht scrapen.

Begleit-App zur HTML-PWA [einkauf](https://supervised-info.github.io/einkauf/). HTML-Spec: Pages `einkauf/Description_index.md`. Brücke ist **nur** die Backup-JSON-Datei (`kind: "einkauf-backup"`). Kein Live-localStorage-Sync, kein Netz für Wörterbuch oder Liste.

## Zweck

Einkaufsliste nach Ladenweg auf **iPhone** (Geh-Modus + Bearbeiten inkl. abteilungsübergreifendem Ziehen) und **Apple Watch** (nur Geh-Modus). Dieselbe Liste, Abhaken über WatchConnectivity. Seeds plus eigene Läden, Stamm, gespeicherte Anlass-Listen, lokales Keyword-Wörterbuch, Backup-JSON und Listen-PDF mit **leeren quadratischen** Kästchen.

TestFlight ist nicht Voraussetzung. v1 ist nicht für den App-Store-Submit gedacht.

## Datei-Ort, Targets, Bundle

| | |
|---|---|
| iPhone | Target `Einkauf`, Bundle `net.tschelle.einkauf`, Display-Name Einkauf, Portrait, nur iPhone (`TARGETED_DEVICE_FAMILY` 1), kein Mac Catalyst, App Group `group.net.tschelle.einkauf` |
| Watch | Target `EinkaufWatch`, Bundle `net.tschelle.einkauf.watchkitapp`, eingebettet (`embed: true`), Companion `net.tschelle.einkauf`, `WKRunsIndependentlyOfCompanionApp` YES |
| Watch-Complication | Target `EinkaufWatchWidgets`, Bundle `net.tschelle.einkauf.watchkitapp.widgets`, WidgetKit (watchOS 10, **kein ClockKit**), eingebettet in die Watch-App (`Embed Foundation Extensions`). Nicht auf dem iPhone. |
| iPhone-Widget | Target `EinkaufWidgets`, Bundle `net.tschelle.einkauf.widgets`, WidgetKit (iOS 17), Homescreen `systemSmall`/`systemMedium`, eingebettet in die iPhone-App. Nicht auf der Watch, nicht Sperrbildschirm. |
| Geteilter Code | `Sources/Shared` in beiden App-Targets (`ConnectivitySync.swift` nur Apple-Targets, nicht im SPM-Paket). **Siri:** `SpeechItemSplitter.swift` + `SiriPendingAdds.swift` + `EinkaufAddItemsIntent.swift` (`AppIntent` + `AppShortcutsProvider`) in iPhone- und Watch-App, nicht in den Widgets, Intent nicht im SPM-Paket. Widgets laden `einkauf-local.json` über `Persistence` (ohne `ShoppingStore` / WatchConnectivity im Widget-Prozess). |
| iOS-UI | `Sources/iOS` — `EinkaufApp`, `ContentView`, `SettingsSheet`, `KeywordDictionaryView`, `ListPDF`, `ShareSheet`, `AppearanceSettings`, `HomeWidgetReload` |
| Watch-UI | `Sources/Watch` — `EinkaufWatchApp`, `WatchListView`, `WatchComplicationReload` |
| Watch-Complication | `Sources/WatchWidgets` — `EinkaufWatchWidgets` (WidgetKit `StaticConfiguration`) |
| iPhone-Widget | `Sources/iOSWidgets` — `EinkaufWidgets` (WidgetKit `StaticConfiguration`) |
| Persistenz | `einkauf-local.json` im App Group `group.net.tschelle.einkauf` (iPhone-App + iPhone-Widget bzw. Watch-App + Complication; Geräte-Container getrennt). Fallback Application Support `Einkauf/einkauf-local.json` beim ersten Umzug. Envelope `kind: "einkauf-local"`. Kein iCloud. |
| Backup-Dokumenttyp | JSON, UTType `net.tschelle.einkauf.backup` |
| Xcode | 15+, iOS 17, watchOS 10, Sprache de, Marketing 1.0 |
| Projekt | `Einkauf.xcodeproj` / `project.yml`; optional `Scripts/generate-xcodeproj.sh` |
| Fixtures | `Fixtures/einkauf-backup.json`, `Fixtures/einkauf-backup-ohne-staples.json` |
| Linux-Check | `python3 Scripts/verify_core.py`; Swift-Tests `swift test` (Mac) |

Watch-UI-Änderung: Build-Nummer hochzählen, sonst bleibt die alte Companion-App. Zeigt die Watch weiter die alte UI: Einkauf auf der Watch löschen und unter Verfügbare Apps neu installieren. Complication folgt derselben Build-Nummer; nach Install die Komplikation auf dem Zifferblatt neu wählen, falls sie fehlt.

## Chrome / iPhone-Hauptansicht

`NavigationStack`, Titel **Einkaufsliste** (inline). Hintergrund Theme-Papier. Leere Liste: `ContentUnavailableView` „Noch nichts auf der Liste.“ + „Artikel hinzufügen oder ein Backup importieren.“

Toolbar:

- Links: **Ladenwahl**-Menü (`accessibilityLabel` „Laden“) — alle `stores`, aktueller mit Checkmark. Nur iPhone. Das Auge ersetzt dieses Menü **nicht**.
- Rechts: Auge `eye` / `eye.slash` (Accessibility „Erledigte ausblenden“ / „Erledigte einblenden“) neben dem Umschalter **Geh-Modus** / **Bearbeiten**. Tippen blendet abgehakte Artikel **nur im iPhone-Geh-Modus** aus; Bearbeiten zeigt weiter alle. Artikel bleiben auf der Liste und im Backup. Abteilungen ohne sichtbare Artikel verschwinden. Alles erledigt und ausgeblendet: kurze Zeile „Erledigte ausgeblendet.“ Flag nur iPhone (`UserDefaults` / `AppStorage` `einkauf.iphone.hideCompleted`), **nicht** im einkauf-backup, **nicht** zur Watch.
- Rechts: Umschalter **Geh-Modus** / **Bearbeiten** (zeigt den jeweils anderen Modus, wie die PWA). `walkMode` persistiert und liegt im Backup.
- Rechts: Overflow **…** (`ellipsis.circle`, Label „Mehr“).

Unten Add-Leiste: Placeholder „Milch, Äpfel, Klopapier…“, Submit **Hinzufügen**. Trim + Whitespace-Normalisierung; leer = no-op. Abteilung per `DepartmentGuesser.guess`.

Thema und Palette **nicht** in der Toolbar — nur in Einstellungen.

### Geh-Modus (iPhone + Watch)

Große Checkbox + Name, Durchstreichen wenn `done`. Tippen toggelt. Kein Grip, kein Dept-Select, kein Löschen, Name nicht editierbar. Flache `ForEach`-Zeilen (`WalkListRow` / `WalkLine`): Überschrift dann Artikel. **Keine** SwiftUI-`Section` — die verschluckt die Abteilungsreihenfolge beim Ladenwechsel. Zeilen-IDs enthalten Laden und Position (`storeId|index|…`). List-`.id` aus `currentStoreId` + Layout-Join.

iPhone-Geh-Modus kann Erledigte ausblenden (Auge, `einkauf.iphone.hideCompleted`). Watch-Geh-Modus hat denselben Toggle mit **eigenem** Flag (`einkauf.watch.hideCompleted`). Die Flags synct nichts, Backup enthält sie nicht. Bearbeiten auf dem iPhone filtert nicht — erledigte Artikel bleiben editierbar.

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

Liste teilen: A4-PDF (`ListPDF`), Dateiname `yyyyMMdd_HHmm-einkauf-{storeSlug}.pdf`. Light-Tokens der gewählten Palette (`dark: false`). Meta-Zeile `progressLabel` als `oo/xx/yy` (`openCount`/`doneCount`/`items.count`). Checkboxen: **leeres Quadrat** (Stroke ~1.75pt, `roundedRect` radius 2.5, kein Fill, kein Häkchen) — `done` gilt nur für Durchstreichen/Farbe. Leere Liste: „Noch nichts auf der Liste.“

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

Nur Geh-Modus. Navigationsleiste **ausgeblendet** (`.toolbar(.hidden, for: .navigationBar)`): `.navigationTitle("")` reserviert die Bar weiter und lässt eine Lücke unter der Uhr. Die **Systemuhr** bleibt Status und sichtbar. Inhalt direkt darunter (`VStack(spacing: 0)`): zuerst die Augen-Leiste, darunter die Titelzeile **eine Zeile** (`Text(store.state.watchTitle)`): gekürzter Ladenname + zwei Leerzeichen + `Einkauf oo/xx/yy` (`AppState.watchTitle`). Limit 6 Zeichen vor „Einkauf oo/xx/yy“; länger: 5 Zeichen + `…`. Edeka/Aldi/Rewe/Lidl/dm ungekürzt; „Eigenes Layout“ → `Eigen…`. Zähler inkl. `vor`/`nach` (`openCount/doneCount/items.count`). **Nicht** `.navigationTitle(watchTitle)`.

Kein Store-Picker, kein Bearbeiten, kein Share, kein Backup, kein Speichern, kein Wörterbuch, kein Löschen von Läden. Digital Crown scrollt die `List`. Leer: „Noch nichts auf der Liste.“ **Kein** In-App-Mikrofon, **kein** Diktat-Panel, **kein** `Speech.framework` / AVFoundation-Speech, **kein** `TextFieldLink` / `presentTextInputController`.

**Siri / App Intents** (iPhone-App `Einkauf` und Watch-App `EinkaufWatch`): App-Shortcut-**Utterance** muss **genau einmal** den App-Namen enthalten (`\(.applicationName)`). Apple erlaubt in Shortcut-Phrasen nur `AppEntity` und `AppEnum` — **kein** freies `String` (`items`) in der Phrase. Entdeckungs-Phrasen ausschließlich mit dem Trigger **besorgen** (nicht Bring-typisch „Artikel hinzufügen“, nicht „Einkauf“ allein als Cue): „{App} besorgen“, „Besorgen mit {App}“, „{App} zum Besorgen“ (`shortTitle` „Besorgen“, `cart.badge.plus`). Beispiel: Nutzer sagt „Hey Siri, Einkauf besorgen“ (App-Display-Name + besorgen) → Siri fragt „ok“ (`requestValueDialog` „ok“) → Antwort „Milch, Butter und Eier“. iOS kann das Wort **nicht** OS-weit reservieren; die markante Phrase ist Best Effort gegenüber Bring. Parameter-Titel **Artikel**. Führendes `Einkauf:` / `Einkauf` / `Besorgen:` / `Besorgen` im Parameter wird in `perform()` abgestreift (`SpeechItemSplitter.strippingTriggerPrefix`). Getippt darf die Dialog-Antwort weiter mit `Einkauf:` beginnen. Split wie `SpeechItemSplitter`: Komma, Semikolon, Zeilenumbruch, ` und `, ` sowie `; trimmen; Mengenwörter bleiben am Namen („zwei Eier“). Jeder Teil derselbe Pfad wie getipptes Hinzufügen (`DepartmentGuesser` + `mappings`). **iPhone:** `ShoppingStore(enableSync: true)` + `addItems(fromSpeech:)` (Persist + WatchConnectivity); `openAppWhenRun = false`. Siri-Dialog: „1 Artikel hinzugefügt.“ / „3 Artikel hinzugefügt.“ / leer → „Keine Artikel erkannt.“ `perform()` wirft nicht; Fehler → Dialog „Speichern fehlgeschlagen.“ **Watch:** Intent konstruiert **keinen** `ShoppingStore` und schreibt **keinen** vollen `AppState` (`Persistence.write`). `openAppWhenRun = false` (wie iPhone) — Siri startet die Watch-App nicht, sonst bricht der Lauf oft still ab, sobald der Artikel erkannt ist. `perform()` auf watchOS gibt ein schlichtes `IntentResult` **ohne** `ProvidesDialog` / `throws` zurück: zuerst `SiriPendingAdds.enqueue`, dann `return .result()`. Pending-Queue **primär** in `UserDefaults(suiteName: Persistence.appGroupId)` — `suiteName` ist genau `group.net.tschelle.einkauf`, Key `einkauf.siriPendingAdds` (zuverlässiger zwischen Siri- und App-Prozess als eine Seitendatei). Datei `einkauf-siri-pending.json` nur als Spiegel unter der **expliziten App-Group-Container-URL** (`Persistence.appGroupContainerURL` / `Einkauf/`), nie Application Support eines anderen Prozesses. Ist die Suite `nil`, Fallback nur auf diese Container-Datei. Die Watch-App drain't `consumeSiriPendingAdds()` bei `scenePhase == .active` **und** bei `WatchListView.onAppear` / Root-`.task`: `addItems(fromSpeech:)` auf dem **live** Store, Persist+Sync, Complication-Reload. Nach Siri die Watch-App einmal öffnen, falls die Phase verpasst wurde. `makeID` (Item/SavedList/StoreCatalog) kodiert Epoch-Millis als `Int64` — watchOS `arm64_32` hat 32-bit `Int`; `Int(Date().timeIntervalSince1970 * 1000)` crasht sonst fatal beim Anlegen (Siri-Queue und jedes neue Item). `parameterSummary` darf `$items` zeigen (Intent-UI, nicht Utterance).

Auge **zuerst über der Titelzeile**, links (`HStack { Button…; Spacer() }`, Chrome über `watchTitle` und der `List` — **nicht** in `.topBarLeading`; **nicht** `.topBarTrailing`, die Uhr überdeckt das; **nicht** in der Toolbar, Navigationsleiste ausgeblendet): kleines SF-Symbol `eye` wenn Erledigte sichtbar, `eye.slash` wenn ausgeblendet — **plain Icon**, kein gefüllter runder watchOS-Button. Schrift `.font(.caption)` / ca. 14–16pt, `.imageScale(.small)`, `.buttonStyle(.plain)`. Glyph **grün** (`theme.good`, wie die erledigten Häkchen) wenn Erledigte sichtbar (`eye`); **grau** (`theme.muted`, wie Abteilungsüberschriften) wenn ausgeblendet (`eye.slash`). **Kompakte Zeile ~18–20pt**: **kein** `.frame(minHeight: 44)` / 44pt-Tapziel auf dem Image — das erzeugt leere Bänder zwischen Auge, Titel und erstem Listenartikel. Tap-Fläche eher horizontal über `contentShape`/Padding, ohne vertikale Totfläche. Darunter die Titelzeile kompakt, eine Zeile, lesbar (`theme.ink`). List: Top-`contentMargins` 0, erster Artikel direkt unter der Titelzeile; Leerzustände ohne allseitiges `.padding()`. Accessibility „Erledigte ausblenden“ / „Erledigte einblenden“. Tippen blendet abgehakte Artikel **nur in der Watch-Gehliste** aus; die Artikel bleiben auf der Liste und im Backup. Abteilungen ohne sichtbare Artikel verschwinden. Alles erledigt und ausgeblendet: kurze Zeile „Erledigte ausgeblendet.“ (Auge bleibt oben, Titel darunter). Flag nur auf der Watch (`UserDefaults` / `AppStorage` `einkauf.watch.hideCompleted`), **nicht** im einkauf-backup, **nicht** zum iPhone (das iPhone hat `einkauf.iphone.hideCompleted`). `watchTitle` und Complication zeigen weiter `oo/xx/yy` der vollen Liste.

### Watch-Complication (WidgetKit, watchOS 10)

Nur auf der **Apple Watch**, nicht auf dem iPhone-Sperrbildschirm. Kein ClockKit (`CLKComplicationDataSource` nicht vorhanden). Tippen öffnet die Watch-App (Geh-Modus-Liste, `widgetURL` `einkauf://list`).

Anzeige wie der Watch-Titel: Fortschritt `openCount/doneCount/items.count` als `oo/xx/yy` (`AppState.progressLabel` / `ComplicationSnapshot`). Kurzer Ladenname (`clippedWatchStoreName`) nur, wenn die Family Platz hat. Leere Liste: `0/0/0` (weiter antippbar); VoiceOver sagt „leer“.

`accessoryCircular` darf **kein** großes System-`Text` (`.title2` / `.title3` / `.title`) für `progressLabel` nutzen: auf der physischen Watch passt das in Infograph/Modular compact nicht, `minimumScaleFactor` rettet accessory-Families oft nicht, und watchOS zeichnet dann ein alleinstehendes **!** statt zu kürzen. Stattdessen Gauge 0…1 (`done/total`, leer = 0) mit kleinem Zentrum (`caption`/`caption2`/ca. 8–10pt, drei Zeilen `oo` / `xx` / `yy`). `accessoryCorner` ebenso kleine Schrift; Ladenname bleibt im `widgetLabel`. Alle Families: `.containerBackground` (watchOS 10).

Familien, die auf gängigen watchOS-10-Zifferblättern und im Smart Stack vorkommen:

| Family | Inhalt |
|---|---|
| `accessoryCircular` | Gauge 0…1 (`done/total`), kleines `oo`/`xx`/`yy` gestapelt (kein großes Text → sonst „!“) |
| `accessoryRectangular` | Ladenname + `oo/xx/yy` |
| `accessoryInline` | Laden + `oo/xx/yy`, sonst nur `oo/xx/yy` (`ViewThatFits`) |
| `accessoryCorner` | kleines `oo/xx/yy`, Ladenname im `widgetLabel` |

Datenquelle: dieselbe lokale Datei `einkauf-local.json` (`Persistence`, Envelope `kind: "einkauf-local"`). Watch-App und Complication teilen sie über App Group `group.net.tschelle.einkauf` (kein iCloud). Die Watch-App schreibt bei jeder `AppState`-Änderung (Artikel, Häkchen, Laden) und ruft `WidgetCenter.reloadTimelines` auf. iPhone-Änderungen kommen wie bisher per WatchConnectivity in die Watch-App und von dort in Datei + Complication. Fallback-Timeline alle 30 Minuten, falls ein Reload ausbleibt.

Kein Store-Picker, kein Bearbeiten, kein Share, kein Wörterbuch in der Complication.

### iPhone-Widget (WidgetKit, iOS 17)

Nur auf dem **iPhone-Homescreen**, nicht auf der Watch und nicht auf dem Sperrbildschirm. Tippen öffnet die iPhone-App auf der Einkaufsliste (`widgetURL` `einkauf://list`). Leere Liste: `0/0/0`, weiter antippbar.

Anzeige: Fortschritt `openCount/doneCount/items.count` als `oo/xx/yy` (wie `AppState.watchTitle` / `ComplicationSnapshot`, inkl. `vor`/`nach`). Ladenname ungekürzt (`currentStore.name`). Medium zusätzlich die nächsten **offenen** Artikelnamen in Geh-Modus-Reihenfolge (`ListGrouping`, erledigte ausgelassen).

| Family | Inhalt |
|---|---|
| `systemSmall` | Ladenname + `oo/xx/yy` |
| `systemMedium` | Ladenname + `oo/xx/yy` + nächste offene Artikel |

Datenquelle: dieselbe lokale Datei `einkauf-local.json` über App Group `group.net.tschelle.einkauf` (kein iCloud, kein Netz). Die iPhone-App tritt der Group bei und schreibt dort; nach Artikel/Häkchen/Laden `WidgetCenter.reloadTimelines`. Fallback-Timeline alle 30 Minuten.

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

`ConnectivitySync`: `updateApplicationContext`; wenn erreichbar `sendMessage`, sonst `transferUserInfo`. Payload `kind: "einkauf-sync"` + `blob` (lokales JSON). Toggle zusätzlich `kind: "einkauf-toggle"` (`id`, `done`, `at`). Watch pull: `kind: "einkauf-pull"`.

Merge (`StateMerge`): Listenstruktur folgt höherer `listRevision`; `done` je Artikel über `doneChangedAt`. Ohne Stempel und Konflikt: erledigt gewinnt. iPhone und Watch müssen sich einmal sehen (Bluetooth, Apps kurz aktiv).

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

**Nur native / nicht ins HTML:** Watch (Geh-Modus, Titel gekürzter Laden + Einkauf oo/xx/yy, Erledigte ausblendbar, WidgetKit-Complication `oo/xx/yy`, kein Picker/Edit/Share, **kein** In-App-Mikro); iPhone-Geh-Modus mit eigenem Auge (Bearbeiten ungefiltert); **iPhone-Homescreen-Widget** (`systemSmall`/`systemMedium`, Tap öffnet Einkaufsliste); **Siri / App Intents** (Utterance App-Name + **besorgen**, danach Siri fragt nach Artikel; getippt optional `Einkauf:` / `Besorgen:`); **PDF Liste teilen** mit leeren quadratischen Kästchen; Erscheinungsbild **System** (folgt iPhone-Appearance) plus Hell/Dunkel und Creme/Blau **nur in Einstellungen**, nicht in der Toolbar. TestFlight nicht erforderlich. Native-`guess` wertet Nutzer-Mappings vor Sonderregeln/Keywords aus (HTML-Reihenfolge kann abweichen).

**Brücke:** nur Backup-JSON-Datei (inkl. `savedLists`). Kein Live-localStorage-Sync. Unbekannte Felder jeweils ignorieren. App scrapt die Website nicht.

## Nicht ändern

- Bundle-IDs `net.tschelle.einkauf` / `.watchkitapp` / `.watchkitapp.widgets` / `.widgets`
- Builtin-Laden-IDs und DEPT-IDs
- Backup-`kind` `einkauf-backup` und Export-Shape (ohne interne Keys, inkl. `savedLists`)
- `ListGrouping`: `sonstiges` folgt dem Layout; Extra-Depts behalten `item.dept` (geteilt mit HTML, nicht vor `nach` kleben)
- Guesser: Nutzer-Mapping vor Sonderregeln und Keywords; `KeywordDictionary.source` unverändert; lokal
- Watch bleibt Geh-Modus ohne Picker/Edit/Share (Auge blendet Erledigte nur an, löscht sie nicht); iPhone-Auge nur Geh-Modus, Bearbeiten ungefiltert; Flags geräte-lokal, nicht im Backup
- Kein Watch-in-App-Mikrofon, kein `Speech.framework`; Siri-Utterance mit App-Namen + **besorgen**, danach Nachfrage **Artikel** (getippt optional `Einkauf:` / `Besorgen:`)
- Complication nur Watch/WidgetKit, nicht iPhone, kein ClockKit, kein iCloud
- iPhone-Widget nur Homescreen (`systemSmall`/`systemMedium`), nicht Watch, nicht Sperrbildschirm, kein iCloud
- Theme nur in Einstellungen
- PDF-Kästchen leer (kein Fill, kein Häkchen)
- Bewusstes Rest-Delta zur HTML-PWA (Watch, PDF Liste teilen, System-Appearance in Einstellungen vs. Markdown/Bring/Erinnerungen/`einkauf-laeden`/Mast/SW) nicht angleichen
- Gemeinsame Slice (savedLists, Sonstiges-Slot, Wörterbuch, Settings-Gerüst) nicht als Native-only oder HTML-only führen

## Akzeptanzkriterien

- [ ] Bundle `net.tschelle.einkauf`, Watch eingebettet, Geh-Modus Watch, iPhone Geh + Bearbeiten mit Cross-Dept-Drag.
- [ ] Seeds + Custom; Neuer Laden kopiert das Layout des ausgewählten Ladens; Swipe-Delete nur Custom in Einstellungen → Aktueller Laden; Builtins nie weg.
- [ ] Settings-Reihenfolge: Darstellung (Hell/Dunkel/System, Creme/Blau) → Aktueller Laden → Neuer Laden → Ladenweg (`sonstiges` movable, `vor`/`nach` locked) → Abteilungen hinzufügen → Reset → Stamm → Gespeicherte Listen (Apply + Swipe-Delete) → Wörterbuch.
- [ ] `ListGrouping` sanitized inkl. `sonstiges`-Position; Rest-Depts mit Items nach dem letzten Nicht-`nach`-Gang; kein Remap von `item.dept` nach `sonstiges`.
- [ ] `DepartmentGuesser` + `KeywordDictionary.source` lokal, kein Netz; Nutzer-Mapping vor Sonderregeln/Keywords.
- [ ] Wörterbuch **Meine Zuordnungen**: View/Edit/Delete von `mappings` (Picker, Swipe-Delete, optional Hinzufügen); mitgelieferte Liste nur lesen; Backup-Feld bleibt `mappings`.
- [ ] Gespeicherte Listen: Name+Dept-Snapshot, füllen nicht ersetzen, Backup-Feld `savedLists`.
- [ ] Backup `einkauf-backup` mit stores, items, staples, savedLists, walkMode, …; Backup teilen; Liste teilen PDF mit leeren Quadrat-Kästchen.
- [ ] Watch-Titel: gekürzter Ladenname + Einkauf oo/xx/yy; Auge blendet Erledigte nur in der Watch-Gehliste aus (`einkauf.watch.hideCompleted`, nicht Backup); iPhone-Geh-Modus hat dasselbe Auge mit `einkauf.iphone.hideCompleted`; Bearbeiten ungefiltert; kein Picker/Edit/Share auf der Watch; WatchConnectivity.
- [ ] Siri / App Intents: Utterance mit genau einem App-Namen + **besorgen** (kein `String`/`$items` in der Phrase; keine Bring-ähnlichen „hinzufügen“-Phrasen); Siri fragt nach Artikel; getippte Antwort darf mit `Einkauf:` / `Besorgen:` beginnen; Splitter wie Sprache, Guesser+Mappings; iPhone Persistenz+WatchConnectivity, Watch-Siri schreibt nur eine Pending-Queue in App-Group-`UserDefaults` (`group.net.tschelle.einkauf`, kein `ShoppingStore` / kein volles `AppState`-Encode im Intent; `openAppWhenRun = false`; App übernimmt beim Aktivwerden **und** `onAppear` / `.task` — Watch-App ggf. einmal öffnen); leerer Text = freundliches No-op; kein Watch-Mikro, kein Speech.framework. iOS reserviert „besorgen“ nicht OS-weit (Best Effort vs Bring).
- [ ] Watch-Complication (WidgetKit, watchOS 10): `oo/xx/yy` inkl. vor/nach, Ladenname wo Platz, Tap öffnet Geh-Modus; Update aus `einkauf-local.json` / WatchConnectivity; nicht auf dem iPhone.
- [ ] iPhone-Widget (WidgetKit, iOS 17): `systemSmall` Laden + `oo/xx/yy`, `systemMedium` plus offene Artikel in Geh-Modus-Reihenfolge; Tap öffnet Einkaufsliste; App Group `group.net.tschelle.einkauf`; nicht auf der Watch.
- [ ] Theme nur in Einstellungen; HTML-Delta bleibt: kein Markdown/Bring/Erinnerungen/`einkauf-laeden`/PWA-SW/Mast-Theme in der nativen App; kein Watch/PDF/System-Appearance im HTML. Gemeinsame Slice (Listen, Sonstiges-Slot, Wörterbuch, Settings-Gerüst) nicht als Native-only führen.
