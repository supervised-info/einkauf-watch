# To-Do als zweiter Reiter (native Einkauf)

Stand: 2026-09-04, Build 55. Phasen 1–10 **geliefert** (MD/CSV volle Liste, benannte Listen). `Description.md` beschreibt den ausgelieferten Stand inkl. **Edit**-Labels und Listenfilter. HTML-Listen sind ein Follow-up auf demselben `todo-v3-json`-Schema.

Begleit-Leser: Menschen und Regeneratoren. Swift-Quellen bleiben die Wahrheit. HTML-PWA [todo](https://supervised-info.github.io/todo/) ist die Produktreferenz für Task-Shape und JSON-Brücke; natives To-Do-Verhalten steht in `Description.md`.

---

## Ziel (geliefert)

Zweiter Reiter in der bestehenden nativen App **Einkauf** (Bundle `net.tschelle.einkauf`):

**Einkauf | To-Do**

Muster wie Einkauf: iPhone (Liste + Bearbeitung) und Apple Watch (**nur Geh-Modus**). Daten, Persistenz, Backup und Sync sind **strikt getrennt** von der Einkaufsliste.

Nicht das Ziel: eine zweite App, ein zweites Bundle, ein zweites App Group, oder To-Do in `ShoppingStore` / `AppState` / `einkauf-local.json` zu mischen.

---

## Quelle der Wahrheit (Produkt)

| | |
|---|---|
| HTML-PWA | [todo](https://supervised-info.github.io/todo/) |
| Spec | Pages-Repo `supervised-info/supervised-info.github.io`, Datei [`todo/Description_index.md`](https://github.com/supervised-info/supervised-info.github.io/blob/main/todo/Description_index.md) |
| Native Einkauf + To-Do | dieses Repo, `Description.md` (gelieferter Stand, Build 53) |

Native scrapt die Website nicht. Brücke ist eine **eigene** JSON-Datei (siehe Backup), analog zur Einkauf-Brücke `kind: "einkauf-backup"`.

Kein Live-localStorage-Sync. Kein Netz für Aufgaben.

### localStorage der HTML-PWA (`todo-v3*`)

| Key | Wert |
|---|---|
| `todo-v3` | JSON-Array der Tasks |
| `todo-v3-file` | letzter Import-Dateiname |
| `todo-v3-show-completed` | `'true'` / `'false'` |
| `todo-v3-completed-expanded` | `'true'` / `'false'` (Default expanded, solange nicht `'false'`) |
| `todo-v3-next-uid` | String-Zahl |
| `todo-v3-collapsed-chains` | JSON-Array von Chain-Keys |

Native darf diese Key-Namen **nicht** in `UserDefaults` der Einkaufs-App als Einkaufsdaten ablegen. UI-Flags analog lokal halten (`todo.iphone.showCompleted` o. ä.), nicht ins Einkauf-Backup, nicht mit Einkauf-Flags mischen.

### Task-Shape (Speicher + JSON-Export)

Runtime-HTML hat zusätzlich `id` (Number, DOM-Key) — **nicht** im JSON-Export.

```
{
  uid: number,
  text: string,
  completed: boolean,
  prioA: "A"–"Z" | "",
  prioB: "1"–"9" | "",
  dueDate: "YYYY-MM-DD" | "",
  completedDate: "YYYY-MM-DD" | "",
  person: string,
  reopenedFromUid, reopenedToUid: number | "",
  reopenedAt: "YYYY-MM-DD" | "",
  createdAt, updatedAt: ISO-Timestamp,
  changedBy: string,   // HTML-UI setzt "TS/NA"
  listId: string | "" | null   // optional, Phase 10; fehlt/leer = unassigned / Alle
}
```

`normalizeTasks`: fehlende UIDs aus `nextUid`; `nextUid = max+1`.

### JSON-Brücke HTML ↔ Native

HTML-Export (`exportJSON`): Datei `todo-liste.json`, **nicht** `einkauf-backup`.

```
{
  format: "todo-v3-json",
  exportedAt: ISO,
  nextUid: number,
  lists: [ { id: String, name: String } ],   // optional, fehlt → []
  tasks: [ /* Task-Shape ohne runtime id; optionales listId */ ]
}
```

`lists` und `listId` (Phase 10): fehlend/null/leer = keine Listen / Aufgabe unassigned (**Alle**). Decode ignoriert unbekannte Felder. Alte Dateien ohne diese Keys laden unverändert. HTML-Follow-up soll dasselbe Schema schreiben.

Import HTML: Array **oder** Objekt `{ tasks, nextUid, lists? }`. Native muss beides lesen.

Native **darf nicht** teilen:

- `ShoppingStore`
- `AppState` / `Item` (Einkauf)
- Datei `einkauf-local.json`
- Envelope `kind: "einkauf-local"` / `kind: "einkauf-backup"`
- WatchConnectivity-`kind` `einkauf-sync` / `einkauf-toggle` / `einkauf-pull`
- Fixture-Importpfad, der `BackupCodec.looksLikeBackup` auf To-Do-JSON anwendet

`BackupCodec.looksLikeBackup` erkennt `kind == "einkauf-backup"` **oder** (`v == 1` und `items`+`stores` Arrays). `todo-v3-json` hat weder `stores` noch Einkauf-`items` — trotzdem: Import-Router muss **zuerst** `format` / `kind` prüfen, nie To-Do-JSON in `BackupCodec.decode` schieben.

---

## Architektur (geliefert)

### iPhone

```
EinkaufApp
  ShoppingStore
  TodoStore
  TabView
    Tab 1 „Einkauf“ → ContentView / EinkaufRoot
    Tab 2 „To-Do“   → TodoListView (eigene NavigationStack)
```

Tab-Labels **Einkauf | To-Do**, SF-Symbols `basket` / `checklist`. Einkaufs-Toolbar, Overflow, Einstellungen, Add-Leiste bleiben **im Einkaufs-Tab**. To-Do hat ein **eigenes** Overflow (Import/Export/Liste teilen), kein gemeinsames „…“ das beide Domains anfasst.

`onOpenURL` auf `EinkaufRoot` (`IncomingJSON`): Envelope entscheidet (`einkauf-backup` vs `todo-v3-json`). Widget-URL `einkauf://list` = Einkaufs-Tab, `einkauf://todo` = To-Do-Tab.

### Watch (v1, geliefert)

Zwei Reiter **Einkauf | To-Do**. To-Do auf der Watch **nur Geh-Modus**:

- offene und (per Auge) erledigte Aufgaben: Text; Person/Prio/Datum als kompakte Nebeninfo
- Tippen toggelt `completed` (wie Einkauf-Checkbox)
- **kein** volles Edit, kein Prio-Picker, keine Reopen-Ketten, kein Import/Export, keine Suche, kein Sort

Erledigte ausblenden: eigenes Flag (`todo.watch.hideCompleted`), **nicht** `einkauf.watch.hideCompleted`, nicht im Backup, nicht zum iPhone.

Watch-To-Do-Complication `TodoProgress` (Label **To Do**, offene Anzahl / „erledigt“) ist gelandet. Kein To-Do-Homescreen-Widget.

### Store und Persistenz

Neuer Store: `TodoStore` + `TodoState` + `TodoTask`.

| | Einkauf (bleibt) | To-Do (neu) |
|---|---|---|
| Store | `ShoppingStore` | `TodoStore` |
| Datei | `einkauf-local.json` | `todo-local.json` |
| Ordner | App Group `Einkauf/` | **derselbe** Ordner |
| Local envelope | `kind: "einkauf-local"` | `kind: "todo-local"` |
| Backup | `kind: "einkauf-backup"` | siehe unten |
| Notification | `.einkaufStateDidChangeOnDisk` | eigene, z. B. `.todoStateDidChangeOnDisk` |

`Persistence` heute hart verdrahtet auf `einkauf-local.json`. **Nicht** die Einkaufs-API umbiegen, sodass sie zwei Dateien schreibt. Eigene Persistenz (`TodoPersistence`) oder klar getrennte Methoden. Ein verwechselter `fileName` würde die Einkaufsliste überschreiben.

### Warum dieselbe App Group OK ist

App Group bleibt `group.net.tschelle.einkauf`.

Gründe:

1. iPhone-App, Watch-App und (später) Widgets müssen denselben Container sehen — zweite Group brächte neue Entitlements, Provisioning und ändert nichts an Watch-Paarung.
2. Isolation ist **Dateiname + Envelope-`kind`**, nicht der Container. `einkauf-local.json` und `todo-local.json` liegen nebeneinander; Decoder lehnen fremdes `kind` ab.
3. UserDefaults-Suite derselben Group ist schon für Siri-Pending (`einkauf.siriPendingAdds`) in Gebrauch — To-Do-Keys mit Präfix `todo.` namespaced halten, Einkaufs-Keys nicht anfassen.
4. Kein iCloud. Kein zweites Bundle.

Nicht OK: To-Do-Array in `AppState.items` oder ein gemeinsames JSON-Objekt „alles in einer Datei“.

### Backup-Envelope

Zwei Ebenen, nicht vermischen:

1. **HTML-Brücke** (Pflicht für Roundtrip mit der PWA): `format: "todo-v3-json"` wie oben. Native Export/Import schreibt und liest das (Defaultname analog `todo-liste` / gestempelt `yyyyMMdd_HHmm-todo-liste.json`).
2. **Native-lokales Extra** (optional, intern): `kind: "todo-backup"` darf interne Sync-Felder tragen, **solange** der PWA-Export weiterhin `todo-v3-json` ohne Einkauf-Felder ist.

Öffentlicher Dateiexport = **genau** `todo-v3-json` (HTML-parity). `kind: "todo-backup"` nur wenn native-only Felder nötig sind; dann beide erkennen, nie `einkauf-backup`.

Import-Menü **nur im To-Do-Tab**. Einkaufs-Overflow bleibt bei Einkauf-Backups. `BackupError.notABackup` („Keine gültige Einkauf-Backup-Datei.“) darf To-Do-JSON nicht als Einkauf schlucken und nicht als Erfolg importieren.

`Info.plist` deklariert die App als Owner von `public.json` + `net.tschelle.einkauf.backup`. Share-Sheet-Öffnen einer `todo-liste.json` trifft die Einkaufs-App; Router nach `format`/`kind`; fremdes Format → Fehlertext, kein stilles No-op auf die Einkaufsliste.

### WatchConnectivity

`WCSession.applicationContext` ist **ein** Dictionary — letzter Schreiber gewinnt. To-Do darf denselben Slot nicht mit einem eigenen Payload überschreiben.

Gelandertes Envelope (Phase 6):

```
applicationContext = {
  einkauf: { kind: "einkauf-sync", v, blob },
  todo:    { kind: "todo-sync",    v, blob }
}
```

Beim Senden einer Domain: `session.applicationContext` lesen (`WatchSyncEnvelope.merging`), nur den eigenen Key setzen, zurückschreiben. Backward-compat: top-level `kind == "einkauf-sync"` gilt weiter als Einkauf-only.

Message-Kinds:

- `einkauf-sync` / `einkauf-toggle` / `einkauf-pull` (unverändert)
- `todo-sync` / `todo-toggle` (`uid` Int64 oder NSNumber) / `todo-pull`

To-Do-Blob = `TodoCodec.encodeLocal` / `decodeLocal` (`kind: "todo-local"`). `BackupCodec.decodeLocal` darf To-Do-Blobs nicht als `AppState` schlucken.

`WatchSessionActor` bleibt Singleton am `WCSession.default`. `attach` (`ConnectivitySync`) und `attachTodo` (`TodoConnectivitySync`) — kein zweites Delegate. Einkaufs-Pfad unverändert, außer dass `updateApplicationContext` merget.

Toggle-Merge analog Einkauf: Zeitstempel `updatedAt`; ohne Stempel: erledigt gewinnt. Listenstruktur: `revision` / `nextUid`, nicht `listRevision` von Einkauf.

### Siri

Einkauf: Utterance mit App-Namen + **besorgen** (`EinkaufAddItemsIntent`). Das Wort nicht umdeuten.

To-Do-Siri: `TodoAddItemsIntent`, Phrasen **Todo** (ein Token, nicht `To Do` — Siri begrenzt zwei Phrase-Tokens auf zwei Wörter Capture), optional **Aufgaben**, `shortTitle` **Todo**. iPhone-Nachfrage **„o“** (`requestValueDialog`); watchOS **ohne** `requestValueDialog` (generische Freitext-Nachfrage). `parameterSummary` **ein Token** `Todo \(.$items)`. Spoken: **„Hey Siri, Einkauf Todo“**. Nach Update Shortcut löschen/neu und **„Auf Apple Watch anzeigen“** erneut. Beide Shortcuts in **einem** `EinkaufShortcuts` (`AppShortcutsProvider`) — Apple erlaubt nur eine Conformance. Keine zweite Phrase mit „besorgen“.

### Theme

HTML-To-Do teilt Site-Keys `supervised-info.theme` / `supervised-info.palette`. Native Einkauf hat eigene Keys `einkauf.theme` / `einkauf.palette` in Einstellungen.

To-Do-Tab in der nativen App: **dieselbe** native Darstellung wie Einkauf (`AppearanceSettings`), kein zweites Theme, keine HTML-Keys. Watch: weiter Vintage + System-`colorScheme` (Einkauf-Spec).

---

## Phasierter Ablaufplan (Reihenfolge, gelandet 1–8)

Jeder Schritt war ein eigener PR gegen `main`. #65 war Phase 1 (Plan). Phasen 1–7 plus Liste-teilen-PDF und Siri-Fixes sind auf `main` (Build 52). Phase 8 (MD/CSV) ist in diesem Branch (Build 53). Phase 10 (Listen) bleibt geplant.

### 1. Branch + dieser Plan — erledigt

- Datei `Docs/TodoIntegration.md`
- kurzer Verweis in `Description.md` (damals unter **Geplant / WIP**; Spec beschreibt To-Do jetzt als geliefert)
- zunächst docs-only, danach Phase 2 im selben Branch/PR

### 2. Models + Persistenz + `TodoStore` — erledigt (keine UI)

Gelandet:

- `Sources/Shared/TodoModels.swift` — `TodoTask` / `TodoState`, `uid`/`nextUid` als `Int64`
- `Sources/Shared/TodoCodec.swift` — Envelope `kind: "todo-local"`; lehnt `einkauf-local` / `einkauf-backup` ab; `normalizeTasks`
- `Sources/Shared/TodoPersistence.swift` — `todo-local.json` im Ordner `Einkauf/` derselben App Group; Notification `.todoStateDidChangeOnDisk`; schreibt nicht `einkauf-local.json`
- `Sources/Shared/TodoStore.swift` — `@MainActor` ObservableObject, `enableSync` startet `TodoConnectivitySync` (Phase 6); `add` / `toggle` / `delete` / `update`
- Tests: `Tests/EinkaufCoreTests/TodoStoreTests.swift`
- Widgets schließen `TodoStore.swift` aus (`project.yml`), analog `ShoppingStore`

Noch nicht in Phase 2 (kam später): TabView, Backup-UI, Watch-Sync, MD/CSV.

### 3. iPhone-Tab-Shell + grundlegendes Listen-CRUD — erledigt

Gelandet:

- iPhone `TabView`: Tab **Einkauf** = unveränderte `ContentView`; Tab **To-Do** = `TodoListView` in eigener `NavigationStack`
- `EinkaufApp` hält `ShoppingStore` und `TodoStore` (`environmentObject`)
- To-Do v1: Text anlegen, Toggle `completed`, Tippen benennt um; Swipe-Löschen erst im Edit-Modus (Build 50; Toolbar-Label **Edit**)
- SF-Symbols `basket` / `checklist`
- Person / Prio / Datum leer (Phase 4)
- **Kein** Watch-Tab, **kein** Backup-Menü, **kein** To-Do-WatchConnectivity
- Build-Nummer 42 (iPhone-UI)

Einkaufs-Tab bleibt `ContentView` ohne `TodoStore`.

### 4. Person / Prio A–B / dueDate + Abgeschlossen-Toggle — erledigt (Build 43)

Gelandet:

- Add-Form: Person, Prio A (A–Z oder „– Prio“), Prio B (1–9 oder leer), Datum, Text + Hinzufügen; kompakt, Einkauf-Theme
- Zeile: Person / Prio / Datum als Nebeninfo, wenn gesetzt; Overdue `dueDate < heute` (lokal) und nicht `9999*` in `theme.oxide`
- Bearbeiten: Sheet (Text, Person, Prio, Datum) über `TodoStore.update`
- „Abgeschlossen einblenden“: `AppStorage` / UserDefaults `todo.iphone.showCompleted` (Default an). Aus = erledigte in der Liste verstecken, bleiben in `todo-local.json`. **Nicht** im Envelope, **nicht** Watch, **nicht** `einkauf.iphone.hideCompleted`
- Anzeige-Sortierung (`TodoOrdering`): Person asc, offen zuerst, Prio `prioA + (prioB || "9")`, fehlendes `prioA` zuletzt (`U+FFFF`)
- Tests: Overdue / Prio-Key / Sort
- Build 43 (iPhone-UI)

Noch nicht in Phase 4 (kam später): Watch (Phase 6), Reopen/Suche/volle Sort-Header (Phase 7).

### 5. Backup Import/Export JSON (eigenes Menü im To-Do-Tab) — erledigt (Build 44)

Gelandet:

- Export `format: "todo-v3-json"` (`TodoCodec.encodeBackup`), Defaultname `todo-liste` / gestempelt `yyyyMMdd_HHmm-todo-liste.json`. Nicht `kind: einkauf-backup`, nicht `BackupCodec`
- Import Array oder `{format, nextUid, tasks}` (Extra-Felder egal); leer → direkt setzen; sonst Bestätigung **Anhängen** / **Ersetzen**. Kollidierende UIDs über `normalizeTasks`
- Eigenes Overflow **…** nur im To-Do-Tab (`ellipsis.circle`, „Mehr“): Backup importieren / exportieren / teilen, Erledigte löschen (`TodoStore.clearCompleted`). Einkaufs-Overflow unverändert, kein MD/CSV, kein Geh-Modus
- Toolbar trailing wie Einkauf-Chrome: Auge `eye` / `eye.slash` (`todo.iphone.showCompleted`, Accessibility „Abgeschlossene ausblenden“ / „einblenden“) plus **…** — kein Text-Toggle
- `onOpenURL` an `EinkaufRoot`: Peek JSON — `todo-v3-json` / To-Do-Shape → `TodoStore` + To-Do-Tab; `einkauf-backup` / `looksLikeBackup` → Einkauf; sonst klarer Fehler, nie still ins falsche Store
- Fixture `Fixtures/todo-v3-json.json`; Tests Roundtrip, Einkauf-JSON an To-Do abgelehnt, To-Do-JSON an `looksLikeBackup` abgelehnt
- Build 44

Noch nicht in Phase 5 (kam später): Watch (Phase 6), Reopen/Suche (Phase 7), MD/CSV (Phase 8).

### Liste teilen (PDF) — erledigt (Build 45)

Gelandet (kein eigener Phasen-Slot im ursprünglichen Plan; iPhone-only):

- Overflow **Liste teilen** (`list.bullet.rectangle`) nach Backup teilen, vor Erledigte löschen
- `TodoListPDF` (iOS, analog `ListPDF`, Einkauf-PDF unangetastet): A4, Light-`ThemeRGB`, leere Quadrat-Kästchen, Durchstreichen für sichtbare Erledigte
- Folgt `todo.iphone.showCompleted`: ausgeblendet → nur offene; sichtbar → alle. Gruppierung nach Person (leer → „Keine Person“), Sortierung wie die Liste
- Meta `oo/xx/yy` der **gedruckten** Aufgaben; Dateiname `yyyyMMdd_HHmm-todo-liste.pdf` (`ListShare.stampedTodoFilename`)
- Leere gefilterte Liste: deutscher Hinweis, kein leeres PDF
- Share-Sheet wie Einkauf (`BackupShareItem` / `ShareSheet`)
- **Kein** Watch, kein MD/CSV

### 6. Watch Geh-Modus + Sync + Complication + Siri — erledigt (Build 46)

Gelandet:

- Watch-`TabView` **Einkauf | To-Do** (`WatchListView` + `WatchTodoListView`); Labels/Symbole `basket` / `checklist`
- To-Do nur Geh-Modus: Text (+ kompakte Person/Prio/Datum); Tippen toggelt `completed`; Auge `todo.watch.hideCompleted` (eigenes Flag)
- Application Context gemergt (`WatchSyncEnvelope`); Kinds `todo-sync` / `todo-toggle` / `todo-pull`; Legacy `einkauf-sync` top-level bleibt lesbar
- `TodoStore.enableSync` startet `TodoConnectivitySync` am selben `WatchSessionActor`
- Eigene Complication `TodoProgress` (Label **To Do**, offene Anzahl / „erledigt“, `todo-local.json`, `einkauf://todo`)
- Siri `TodoAddItemsIntent` in `EinkaufShortcuts` (kein zweiter Provider): Phrasen **To Do**, Nachfrage **„o“**; Watch-Queue `todo.siriPendingAdds`; Einkauf-„besorgen“ unverändert
- Build 46 (Watch-UI)

### iPhone Edit + Siri „o“ — erledigt (Build 47)

- `TodoAddItemsIntent.requestValueDialog` **„o“** (wie `EinkaufAddItemsIntent`); Phrasen bleiben **To Do**
- iPhone-Toolbar zwischen Auge und **…**: **Edit** / **Fertig** (Label **Edit**, nicht „Bearbeiten“; `@State`, Default Liste)
- Listen-Modus: Checkbox toggelt `completed`; **kein** Swipe-Löschen (`.deleteDisabled`, trailing `EmptyView()`, `.id("todo-browse")`). Text-Tipp und Swipe **Edit** öffnen `TodoEditSheet`
- Edit-Modus: Swipe-Löschen nur via `.onDelete` (`.id("todo-edit")`); Zeile öffnet dasselbe Sheet (Text, Person, Prio A/B, Datum) über `todos.update`; Chevron-Affordance; Add-Leiste Person/Prio bleibt
- `TodoTask` ist `Identifiable`/`Hashable` über `uid` für `.sheet(item:)`
- Build 47 (iPhone-UI + Siri-Dialog)

### To-Do Siri Mehrwort-Aufgaben — erledigt (Build 48)

- `parameterSummary` `Todo \(.$items)` (ein Token, analog Einkauf `Besorgen \(.$items)`)
- Entdeckungs-Phrasen unverändert **To Do**, Nachfrage **„o“**
- `strippingTodoTriggerPrefix` streicht auch `Aufgaben:` / `Todo` (Siri-Echo von Summary/Parameter-Titel)
- Split weiter nur an `,;` / `und` / `sowie` — „Rechnung bezahlen“ bleibt eine Aufgabe
- Build 48

### To-Do Siri Phrase ein Token — erledigt (Build 49)

- Entdeckungs-Phrasen **Todo** (ein Wort), analog Besorgen; nicht `To Do` mit Leerzeichen (Siri-2-Token-Limit: Aufgabe blieb sonst bei genau 2 Wörtern)
- Optional „{App} Aufgaben“
- `shortTitle` war noch „To Do“ (Kurzbefehle-Anzeige; Build 51: **Todo**)
- `parameterSummary` weiter `Todo \(.$items)`, Nachfrage **„o“**
- Spoken **„Hey Siri, Einkauf Todo“**
- Build 49

### Swipe-Löschen nur im Edit-Modus — erledigt (Build 50)

- iPhone-To-Do Listen-Modus: kein `.onDelete`, Zeilen `.deleteDisabled(true)`, trailing `EmptyView()`, List-`.id` `todo-browse`
- Edit: `.onDelete`, List-`.id` `todo-edit` — Umschalten tauscht die List-Identität, damit SwiftUI keine löschbaren Zeilen wiederverwendet
- Leading-Swipe **Edit** bleibt in beiden Modi
- Einkauf Geh-Modus analog: `.deleteDisabled`, kein trailing Delete, List-`.id` `walk|…` vs `edit|…`
- Build 50

### Watch-Siri Todo Mehrwort — erledigt (Build 51)

- `shortTitle` **Todo** (ein Token; nicht `To Do` — Watch-Siri keyed oft auf `shortTitle`)
- watchOS `TodoAddItemsIntent`: `@Parameter` mit `IntentInputOptions` **ohne** `requestValueDialog` (generische Freitext-Nachfrage)
- iPhone behält `requestValueDialog` **„o“**
- Nach Update: Shortcut löschen/neu und **„Auf Apple Watch anzeigen“** erneut
- Spoken weiter **„Hey Siri, Einkauf Todo“**
- Build 51 (Watch-UI / Siri)

Noch nicht: To-Do-Homescreen-Widget

### 7. Reopen-Ketten, Sort, Suche — erledigt (Build 52)

- iPhone **Wieder öffnen**: Confirm wie HTML; Original bleibt `completed` + `reopenedToUid`; offene Kopie mit neuem `uid`, gleichem Text/Person/Prio/Datum, `reopenedFromUid`, `reopenedAt` = heute ISO; `TodoStore.reopen(uid)`; Swipe/Context/Edit-Sheet; Ketten-Hinweis `von #` / `→ #`
- Sort iPhone-Toolbar: person (Default), prioA, text, dueDate, completed, completedDate; `AppStorage` `todo.iphone.sortKey` (nicht im Backup, nicht Watch)
- Suche iPhone: Lupen-Drawer, Placeholder **Person oder Text …**, filtert Person oder Text; Escape/Clear schließt; liegt über showCompleted + Sort
- Watch bleibt Geh-Modus — kein Reopen/Suche/Sort-UI
- Build 52 (iPhone-UI)

### 8. MD/CSV-Export/Import — erledigt (Build 53)

Gelandet (iPhone-only, HTML-Parity `todo/Description_index.md`):

- Shared `TodoMarkdown` / `TodoCSV`; Router `TodoImport` (JSON unverändert `todo-v3-json`)
- MD `todo-liste.md`: `# To-Do Liste`, `Exportiert am:` de-DE, offene `## Person` / `(Keine Person)`, dann `---`, `## Abgeschlossen` mit `### Person`; Comment-Meta `#uid | TS/NA | erstellt … | geändert … | von #x am … | → #y am …`; Alt-Meta `<!-- todo: uid=N … -->`
- CSV BOM+Semikolon, quoted; Kopf Person, Prio A/B, Aufgabe, Enddatum, Abgeschlossen am, UID, Reopened From/To UID, Reopened At, Erstellt/Geändert am, Geändert von. Offen zuerst, Zeile `## Abgeschlossen`, dann erledigt. Datetimes UTC `DD.MM.YYYY HH:MM`
- **Volle Liste** unabhängig vom Auge (Backup-artig). PDF folgt weiter `todo.iphone.showCompleted`
- Overflow nach JSON-Backup: **MD exportieren…** / **MD teilen** / **CSV exportieren…** / **CSV teilen**. `fileImporter` `.json,.md,.markdown,.csv`; nicht leer → Anhängen/Ersetzen. Einkauf-Dateien abgelehnt, deutsche Fehler
- **Kein** Watch-MD/CSV, kein JSON-Backup-Bruch
- Fixtures `Fixtures/todo-liste.md` / `todo-liste.csv`; Tests Roundtrip
- Build 53 (iPhone-UI)

### 9. `Description.md` — geliefert, optionale Politur

`Description.md` beschreibt To-Do als **geliefertes** Produkt: TabView, getrennte Dateien/`kind`s, iPhone-Felder/Auge/**Edit** vs Listen (Swipe-Löschen nur Edit-Modus), Reopen/Sort/Suche, **MD/CSV** (`TodoMarkdown` / `TodoCSV`, volle Liste), Watch-Geh-To-Do, Complication **To Do**, WC `{einkauf, todo}`, Siri (besorgen+o / Todo ein Token, iPhone o, Watch ohne `requestValueDialog`, ein Provider, Zwei-Wort-Cap). Akzeptanzkriterien um To-Do ergänzt, Einkaufs-Häkchen unverändert.

Weitere Spec-Politur ist optional, kein Blocker.

### 10. Listen — erledigt (Build 55)

Backward-compatible optionales `lists` / `listId` auf `format: "todo-v3-json"` (kein Format-Bump):

- Envelope: `lists: [{ id: String, name: String }]` — fehlt → `[]`. Stabile UUID-String-IDs. Decode ignoriert unbekannte Felder.
- `TodoTask.listId: String?` — fehlt/null/leer = unassigned, sichtbar unter **Alle**.
- UX: `todo.iphone.currentListId` (leer = **Alle**, ungefiltert). Nicht im Backup. Filter zuerst Liste, dann Auge / Suche / Sort.
- Liste anlegen / umbenennen / löschen (Confirm). Löschen leert `listId`, löscht keine Aufgaben.
- Neue Aufgaben (Add-Leiste + Siri **Todo**) → aktuelle Liste; **Alle** → `listId` leer. Edit-Sheet kann zuordnen.
- PDF **Liste teilen** folgt Liste **und** Auge; MD/CSV bleiben voller Dump (optionale Liste-Spalte / Comment-Meta). Import ohne Listeninfo gültig; Fixtures `todo-liste.md` / `.csv` unverändert. JSON-Anhängen merget `lists` per `id`.
- Watch Geh-Modus + Complication: gleicher Filter. `currentListId` als Geschwisterfeld im WC-`todo-sync`-Payload (nicht im Blob), Watch schreibt App-Group `todo.currentListId`. Einkauf-Multiplex `{einkauf, todo}` unverändert.
- **Kein** Listen-UI auf der Watch. **Kein** HTML in diesem PR — Schema hier, Pages-Follow-up separat.
- Build 55

---

## Historisch: Non-Goals für Phase 3

(Damaliger Schnitt; Watch, Backup, Person/Prio kamen in späteren Phasen.)

- Kein Watch-To-Do-Tab, kein WatchConnectivity für To-Do
- Kein Backup-Import/Export in der UI, kein MD/CSV
- Keine Person/Prio/dueDate-UI (Phase 4)
- `ShoppingStore` / `AppState` / `Item` / `BackupCodec.looksLikeBackup` unverändert
- `Description.md` behauptet kein volles HTML-Parity; WIP durfte den iPhone-Tab nennen

---

## Non-Goals für To-Do-v1 (weiterhin)

- To-Do-Homescreen-Widget, Sperrbildschirm (Watch-To-Do-Complication ist in Phase 6 gelandet)
- To-Do-Siri verdünnt nicht „besorgen“ (ein `AppShortcutsProvider`; gelandet in Phase 6)
- Edit / Prio / Reopen auf der Watch
- iCloud, CloudKit, gemeinsames JSON mit Einkauf
- HTML Theme-Mast / Service Worker / Shared-Keys in der nativen App
- Listen-Verwaltung / Edit auf der Watch (Phase 10 filtert nur)
- App-Store-Submit, Display-Name-Änderung (App bleibt **Einkauf**)

---

## Landminen (weiterhin gültig)

1. **`Persistence.fileName`** ist `"einkauf-local.json"` — To-Do braucht eine zweite Datei, keine Parameter-Verwechslung.
2. **`BackupCodec.looksLikeBackup`**: heuristisch `v==1` + `items`+`stores`. To-Do-JSON darf dort nie landen; Router zuerst.
3. **`ContentView.onOpenURL`**: erledigt in Phase 5 — Router sitzt auf `EinkaufRoot` (`IncomingJSON`).
4. **`Info.plist` `public.json`**: eine geöffnete `todo-liste.json` trifft die Einkaufs-App. Router oder eigener UTType `net.tschelle.einkauf.todo-backup`.
5. **`WatchSessionActor.shared` + ein `ConnectivitySync.store: ShoppingStore?`**: Multiplex, nicht zweites `WCSession.delegate`.
6. **Application Context last-write-wins**: To-Do darf den Einkaufs-Snapshot nicht verdrängen.
7. **`makeID` / `Int64`**: Watch `arm64_32` — UIDs als `Int64`/`UInt64`, nicht 32-bit `Int` aus Epoch-Millis.
8. **Siri `AppShortcutsProvider`**: nur eine Conformance pro App; To-Do-Phrasen in `EinkaufShortcuts`, keine zweite Phrase mit „besorgen“.
9. **Tests `EinkaufCoreTests`**: Fixtures und `kind: einkauf-backup`-Asserts nicht für To-Do umbiegen; neue Test-Datei.

---

## Dateien

```
Sources/Shared/TodoModels.swift
Sources/Shared/TodoPersistence.swift
Sources/Shared/TodoStore.swift
Sources/Shared/TodoCodec.swift
Sources/Shared/TodoMarkdown.swift
Sources/Shared/TodoCSV.swift
Sources/Shared/TodoImport.swift
Sources/iOS/TodoListView.swift
Sources/Watch/WatchTodoListView.swift
Sources/Shared/WatchSyncEnvelope.swift
Sources/WatchWidgets/TodoWatchWidgets.swift
Sources/Shared/TodoAddItemsIntent.swift
Sources/Shared/TodoSiriPendingAdds.swift
Fixtures/todo-v3-json.json              // Phase 5
Fixtures/todo-liste.md                  // Phase 8
Fixtures/todo-liste.csv                 // Phase 8
Tests/EinkaufCoreTests/TodoStoreTests.swift
```

Trennung von `ShoppingStore` / `BackupCodec` / `einkauf-*.json` nicht aufweichen.

---

## Akzeptanz

- [x] Plan liegt unter `Docs/TodoIntegration.md` (Deutsch).
- [x] `Description.md` beschreibt To-Do als geliefertes Produkt (Build 53), nicht als WIP.
- [x] Phase 2: Models, `todo-local.json`, `TodoStore` ohne WC.
- [x] Phase 3: iPhone-Tab Einkauf | To-Do, Text-CRUD, Einkaufs-`ContentView` unverändert.
- [x] Phase 4: Person/Prio/Datum, Overdue, Abgeschlossen-Toggle (`todo.iphone.showCompleted`), Build 43.
- [x] Phase 5: To-Do-Backup `todo-v3-json`, eigenes Overflow, `onOpenURL`-Router, Build 44.
- [x] Liste teilen PDF folgt dem Auge (`todo.iphone.showCompleted`), Build 45.
- [x] Phase 6: Watch-Tab, gemergter WC-Context, To-Do-Complication, Siri To Do, Build 46.
- [x] iPhone **Edit** / **Fertig** + Siri-Nachfrage **„o“**, Build 47 (Toolbar-Label später **Edit**, nicht „Bearbeiten“).
- [x] To-Do-Siri Mehrwort-Aufgaben: ein-tokeniges `parameterSummary`, Build 48.
- [x] To-Do-Siri Phrase ein Token (`Todo`), gesprochen „Hey Siri, Einkauf Todo“, Build 49.
- [x] Swipe-Löschen nur im Edit-Modus (To-Do Listen-Modus + Einkauf Geh-Modus), Build 50.
- [x] Watch-Siri Todo Mehrwort: `shortTitle` Todo, watchOS ohne `requestValueDialog`, Build 51.
- [x] Phase 7: iPhone Wieder öffnen, Sort, Suche; Watch ohne Reopen/Suche/Sort-UI, Build 52.
- [x] Phase 8: iPhone MD/CSV Export/Import (volle Liste), Watch ohne MD/CSV-UI, Build 53.
- [x] Phase 9: `Description.md` auf den gelieferten Stand inkl. **Edit**-Labels; optionale weitere Politur kein Blocker.
- [x] Phase 10: benannte Listen `lists`/`listId`, Filter Alle, PDF+Siri+Watch, Build 55. Isolation bleibt (eigene Datei, eigenes `kind`/`format`, eigener Store, WC-Diskriminator).
