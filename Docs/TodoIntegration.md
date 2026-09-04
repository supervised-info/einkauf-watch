# Plan: To-Do als zweiter Reiter (native Einkauf)

Stand: 2026-09-04. Phasen 1–6 plus Liste-teilen-PDF: Plan, `TodoStore`/`todo-local.json`, iPhone-`TabView` mit CRUD plus Person/Prio/Datum, Abgeschlossen-Toggle, To-Do-Backup `todo-v3-json`, **Liste teilen** (PDF folgt dem Auge), Watch-Tab Geh-Modus, gemergter WatchConnectivity-Context, To-Do-Complication `TodoProgress`, Siri **Todo** (ein Wort). Volle HTML-Parity (Reopen/Suche/MD/CSV) fehlt. Volle Spec in `Description.md` erst Phase 9.

Begleit-Leser: Menschen und Regeneratoren. Swift-Quellen der **Einkaufs**-App bleiben die Wahrheit für Einkauf. Für To-Do-Produktverhalten gilt die HTML-PWA, nicht diese Datei.

---

## Ziel

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
| Native Einkauf | dieses Repo, `Description.md` — **ändert sich durch To-Do nicht**, bis Phase 9 |

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
  changedBy: string   // HTML-UI setzt "TS/NA"
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
  tasks: [ /* Task-Shape ohne runtime id */ ]
}
```

Import HTML: Array **oder** Objekt `{ tasks, nextUid }`. Native muss beides lesen.

Native **darf nicht** teilen:

- `ShoppingStore`
- `AppState` / `Item` (Einkauf)
- Datei `einkauf-local.json`
- Envelope `kind: "einkauf-local"` / `kind: "einkauf-backup"`
- WatchConnectivity-`kind` `einkauf-sync` / `einkauf-toggle` / `einkauf-pull`
- Fixture-Importpfad, der `BackupCodec.looksLikeBackup` auf To-Do-JSON anwendet

`BackupCodec.looksLikeBackup` erkennt `kind == "einkauf-backup"` **oder** (`v == 1` und `items`+`stores` Arrays). `todo-v3-json` hat weder `stores` noch Einkauf-`items` — trotzdem: Import-Router muss **zuerst** `format` / `kind` prüfen, nie To-Do-JSON in `BackupCodec.decode` schieben.

---

## Architektur-Skizze

### iPhone

Heute: `EinkaufApp` → `EinkaufRoot` → `ContentView` (`NavigationStack`, Titel „Einkaufsliste“).

Ziel:

```
EinkaufApp
  ShoppingStore          // unverändert
  TodoStore              // neu, eigener ObservableObject
  TabView
    Tab 1 „Einkauf“ → bestehende ContentView / EinkaufRoot
    Tab 2 „To-Do“   → Todo-UI (eigene NavigationStack)
```

Tab-Labels **Einkauf | To-Do**. SF-Symbols vorschlagen: `basket` / `checklist` (final in der UI-Phase). Bestehende Einkaufs-Toolbar, Overflow, Einstellungen, Add-Leiste bleiben **im Einkaufs-Tab**. To-Do hat ein **eigenes** Overflow (Import/Export), kein gemeinsames „…“ das beide Domains anfasst.

`onOpenURL`: heute importiert jeder Nicht-`einkauf://`-URL-JSON als Einkauf-Backup. Spätere Phasen: am Envelope entscheiden (`einkauf-backup` vs `todo-v3-json` / `todo-backup`). Widget-URL `einkauf://list` bleibt Einkaufs-Tab. Optional später `einkauf://todo`.

### Watch (v1)

Heute: `EinkaufWatchApp` → `WatchListView` (nur Geh-Modus).

Ziel v1: ebenfalls **zwei Reiter** (oder gleichwertige Tab-Leiste) **Einkauf | To-Do**.

To-Do auf der Watch **nur Geh-Modus**:

- offene Aufgaben anzeigen (Text; Person/Prio/Datum nur als kompakte Nebeninfo, falls Platz — Details in der UI-Phase)
- Tippen toggelt `completed` (wie Einkauf-Checkbox)
- **kein** volles Edit, kein Prio-Picker, keine Reopen-Ketten, kein Import/Export, keine Suche

Erledigte ausblenden: eigenes Flag (`todo.watch.hideCompleted`), **nicht** `einkauf.watch.hideCompleted`, nicht im Backup, nicht zum iPhone.

Complication / iPhone-Widget für To-Do: **nicht v1** (Phase später, explizit Non-Goal).

### Store und Persistenz

Neuer Store, Name kann variieren; Vorschlag: `TodoStore` + `TodoState` + `TodoTask`.

| | Einkauf (bleibt) | To-Do (neu) |
|---|---|---|
| Store | `ShoppingStore` | `TodoStore` |
| Datei | `einkauf-local.json` | `todo-local.json` |
| Ordner | App Group `Einkauf/` | **derselbe** Ordner |
| Local envelope | `kind: "einkauf-local"` | `kind: "todo-local"` (vorschlag) |
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

1. **HTML-Brücke** (Pflicht für Roundtrip mit der PWA): `format: "todo-v3-json"` wie oben. Native Export/Import in Phase 5 muss das lesen und schreiben (Defaultname analog `todo-liste` / gestempelt `yyyyMMdd_HHmm-todo-liste.json`).
2. **Native-lokales Extra** (optional, intern): `kind: "todo-backup"` darf interne Sync-Felder tragen, **solange** der PWA-Export weiterhin `todo-v3-json` ohne Einkauf-Felder ist.

Empfehlung: öffentlicher Dateiexport = **genau** `todo-v3-json` (HTML-parity). `kind: "todo-backup"` nur wenn native-only Felder nötig sind; dann beide erkennen, nie `einkauf-backup`.

Import-Menü **nur im To-Do-Tab**. Einkaufs-Overflow bleibt bei Einkauf-Backups. `BackupError.notABackup` („Keine gültige Einkauf-Backup-Datei.“) darf To-Do-JSON nicht als Einkauf schlucken und nicht als Erfolg importieren.

`Info.plist` deklariert die App als Owner von `public.json` + `net.tschelle.einkauf.backup`. Share-Sheet-Öffnen einer `todo-liste.json` landet heute im Einkaufs-Import. Phase 5: Router nach `format`/`kind`; fremdes Format → Fehlertext, kein stilles No-op auf die Einkaufsliste.

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

To-Do-Siri: `TodoAddItemsIntent`, Phrasen **Todo** (ein Token, nicht `To Do` — Siri begrenzt zwei Phrase-Tokens auf zwei Wörter Capture), optional **Aufgaben**, Nachfrage **„o“** (wie Einkauf `requestValueDialog`). `parameterSummary` **ein Token** `Todo \(.$items)`. Spoken: **„Hey Siri, Einkauf Todo“**. Beide Shortcuts in **einem** `EinkaufShortcuts` (`AppShortcutsProvider`) — Apple erlaubt nur eine Conformance. Keine zweite Phrase mit „besorgen“.

### Theme

HTML-To-Do teilt Site-Keys `supervised-info.theme` / `supervised-info.palette`. Native Einkauf hat eigene Keys `einkauf.theme` / `einkauf.palette` in Einstellungen.

To-Do-Tab in der nativen App: **dieselbe** native Darstellung wie Einkauf (`AppearanceSettings`), kein zweites Theme, keine HTML-Keys. Watch: weiter Vintage + System-`colorScheme` (Einkauf-Spec).

---

## Phasierter Ablaufplan (Reihenfolge)

Jeder Schritt ist ein eigener PR gegen `main`, sobald der vorige landet. #65 war nur Phase 1 (Plan). Phase 2+3 folgen in einem neuen PR gegen aktuelles `main`.

### 1. Branch + dieser Plan — erledigt

- Datei `Docs/TodoIntegration.md`
- kurzer Verweis in `Description.md` unter **Geplant / WIP**
- zunächst docs-only, danach Phase 2 im selben Branch/PR

### 2. Models + Persistenz + `TodoStore` — erledigt (keine UI)

Gelandet:

- `Sources/Shared/TodoModels.swift` — `TodoTask` / `TodoState`, `uid`/`nextUid` als `Int64`
- `Sources/Shared/TodoCodec.swift` — Envelope `kind: "todo-local"`; lehnt `einkauf-local` / `einkauf-backup` ab; `normalizeTasks`
- `Sources/Shared/TodoPersistence.swift` — `todo-local.json` im Ordner `Einkauf/` derselben App Group; Notification `.todoStateDidChangeOnDisk`; schreibt nicht `einkauf-local.json`
- `Sources/Shared/TodoStore.swift` — `@MainActor` ObservableObject, `enableSync` startet `TodoConnectivitySync` (Phase 6); `add` / `toggle` / `delete` / `update`
- Tests: `Tests/EinkaufCoreTests/TodoStoreTests.swift`
- Widgets schließen `TodoStore.swift` aus (`project.yml`), analog `ShoppingStore`

Noch nicht in Phase 2: TabView, Backup-UI, Watch-Sync, MD/CSV. (TabView kam in Phase 3.)

### 3. iPhone-Tab-Shell + grundlegendes Listen-CRUD — erledigt

Gelandet:

- iPhone `TabView`: Tab **Einkauf** = unveränderte `ContentView`; Tab **To-Do** = `TodoListView` in eigener `NavigationStack`
- `EinkaufApp` hält `ShoppingStore` und `TodoStore` (`environmentObject`)
- To-Do v1: Text anlegen, Toggle `completed`, Tippen benennt um; Swipe-Löschen erst im Bearbeiten-Modus (Build 50)
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

Noch nicht: Watch (Phase 6), Reopen/Suche/volle Sort-Header (Phase 7).

### 5. Backup Import/Export JSON (eigenes Menü im To-Do-Tab) — erledigt (Build 44)

Gelandet:

- Export `format: "todo-v3-json"` (`TodoCodec.encodeBackup`), Defaultname `todo-liste` / gestempelt `yyyyMMdd_HHmm-todo-liste.json`. Nicht `kind: einkauf-backup`, nicht `BackupCodec`
- Import Array oder `{format, nextUid, tasks}` (Extra-Felder egal); leer → direkt setzen; sonst Bestätigung **Anhängen** / **Ersetzen**. Kollidierende UIDs über `normalizeTasks`
- Eigenes Overflow **…** nur im To-Do-Tab (`ellipsis.circle`, „Mehr“): Backup importieren / exportieren / teilen, Erledigte löschen (`TodoStore.clearCompleted`). Einkaufs-Overflow unverändert, kein MD/CSV, kein Geh-Modus
- Toolbar trailing wie Einkauf-Chrome: Auge `eye` / `eye.slash` (`todo.iphone.showCompleted`, Accessibility „Abgeschlossene ausblenden“ / „einblenden“) plus **…** — kein Text-Toggle
- `onOpenURL` an `EinkaufRoot`: Peek JSON — `todo-v3-json` / To-Do-Shape → `TodoStore` + To-Do-Tab; `einkauf-backup` / `looksLikeBackup` → Einkauf; sonst klarer Fehler, nie still ins falsche Store
- Fixture `Fixtures/todo-v3-json.json`; Tests Roundtrip, Einkauf-JSON an To-Do abgelehnt, To-Do-JSON an `looksLikeBackup` abgelehnt
- Build 44

Noch nicht: Watch (Phase 6), Reopen/Suche (Phase 7), MD/CSV (Phase 8).

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

### iPhone Bearbeiten + Siri „o“ — erledigt (Build 47)

- `TodoAddItemsIntent.requestValueDialog` **„o“** (wie `EinkaufAddItemsIntent`); Phrasen bleiben **To Do**
- iPhone-Toolbar zwischen Auge und **…**: **Bearbeiten** / **Fertig** (`@State`, Default Liste)
- Listen-Modus: Checkbox toggelt `completed`; **kein** Swipe-Löschen (`.deleteDisabled`, trailing `EmptyView()`, `.id("todo-browse")`). Text-Tipp und Swipe **Bearbeiten** öffnen `TodoEditSheet`
- Bearbeiten-Modus: Swipe-Löschen nur via `.onDelete` (`.id("todo-edit")`); Zeile öffnet dasselbe Sheet (Text, Person, Prio A/B, Datum) über `todos.update`; Chevron-Affordance; Add-Leiste Person/Prio bleibt
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
- `shortTitle` bleibt „To Do“ (Kurzbefehle-Anzeige)
- `parameterSummary` weiter `Todo \(.$items)`, Nachfrage **„o“**
- Spoken **„Hey Siri, Einkauf Todo“**
- Build 49

### Swipe-Löschen nur im Bearbeiten-Modus — erledigt (Build 50)

- iPhone-To-Do Listen-Modus: kein `.onDelete`, Zeilen `.deleteDisabled(true)`, trailing `EmptyView()`, List-`.id` `todo-browse`
- Bearbeiten: `.onDelete`, List-`.id` `todo-edit` — Umschalten tauscht die List-Identität, damit SwiftUI keine löschbaren Zeilen wiederverwendet
- Leading-Swipe **Bearbeiten** bleibt in beiden Modi
- Einkauf Geh-Modus analog: `.deleteDisabled`, kein trailing Delete, List-`.id` `walk|…` vs `edit|…`
- Build 50

Noch nicht: Reopen/Suche (Phase 7), MD/CSV (Phase 8), To-Do-Homescreen-Widget

### 7. Reopen-Ketten, Sort, Suche (HTML-Parity, Stretch)

- Wieder öffnen: Original bleibt `completed` + `reopenedToUid`; Kopie offen mit neuem `uid` + `reopenedFromUid`
- Sort: person (Default), prioA, text, dueDate, completed, completedDate
- Suche Person oder Text
- Ketten-UI einklappbar — auf der Watch weiter weglassen

### 8. MD/CSV-Export optional später

- HTML-Formate aus `todo/Description_index.md` (MD-Comment-Meta, CSV BOM+Semikolon)
- Native muss sie nicht anbieten, um v1 To-Do zu schließen
- Wenn doch: Import-Parität testen, nicht raten

### 9. `Description.md` aktualisieren, wenn Verhalten landet

- Nicht vorher die Regenerationsspec so schreiben, als würde To-Do schon liefern
- Dann: TabView, getrennte Dateien/`kind`s, Watch-Geh-To-Do, Non-Goals (Widgets/Siri)
- Akzeptanzkriterien um To-Do ergänzen, Einkaufs-Häkchen unverändert

---

## Non-Goals für Phase 3

- Kein Watch-To-Do-Tab, kein WatchConnectivity für To-Do
- Kein Backup-Import/Export in der UI, kein MD/CSV
- Keine Person/Prio/dueDate-UI (Phase 4)
- `ShoppingStore` / `AppState` / `Item` / `BackupCodec.looksLikeBackup` unverändert
- `Description.md` behauptet kein volles HTML-Parity; WIP darf den iPhone-Tab nennen

---

## Non-Goals für To-Do-v1 (über diesen PR hinaus)

- To-Do-Homescreen-Widget, Sperrbildschirm (Watch-To-Do-Complication ist in Phase 6 gelandet)
- To-Do-Siri verdünnt nicht „besorgen“ (ein `AppShortcutsProvider`; gelandet in Phase 6)
- Bearbeiten / Prio / Reopen auf der Watch
- iCloud, CloudKit, gemeinsames JSON mit Einkauf
- HTML Theme-Mast / Service Worker / Shared-Keys in der nativen App
- MD/CSV Pflicht
- App-Store-Submit, Display-Name-Änderung (App bleibt **Einkauf**)

---

## Landminen im heutigen Code (für spätere PRs)

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

## Dateien (Phase 2+3)

```
Sources/Shared/TodoModels.swift
Sources/Shared/TodoPersistence.swift
Sources/Shared/TodoStore.swift
Sources/Shared/TodoCodec.swift
Sources/iOS/TodoListView.swift
Sources/Watch/WatchTodoListView.swift
Sources/Shared/WatchSyncEnvelope.swift
Sources/WatchWidgets/TodoWatchWidgets.swift
Sources/Shared/TodoAddItemsIntent.swift
Sources/Shared/TodoSiriPendingAdds.swift
Fixtures/todo-v3-json.json              // Phase 5
Tests/EinkaufCoreTests/TodoStoreTests.swift
```

Trennung von `ShoppingStore` / `BackupCodec` / `einkauf-*.json` nicht aufweichen.

---

## Akzeptanz

- [x] Plan liegt unter `Docs/TodoIntegration.md` (Deutsch).
- [x] `Description.md` verweist unter Geplant/WIP hierher, behauptet To-Do nicht als geliefert.
- [x] Phase 2: Models, `todo-local.json`, `TodoStore` ohne WC.
- [x] Phase 3: iPhone-Tab Einkauf | To-Do, Text-CRUD, Einkaufs-`ContentView` unverändert.
- [x] Phase 4: Person/Prio/Datum, Overdue, Abgeschlossen-Toggle (`todo.iphone.showCompleted`), Build 43.
- [x] Phase 5: To-Do-Backup `todo-v3-json`, eigenes Overflow, `onOpenURL`-Router, Build 44.
- [x] Liste teilen PDF folgt dem Auge (`todo.iphone.showCompleted`), Build 45.
- [x] Phase 6: Watch-Tab, gemergter WC-Context, To-Do-Complication, Siri To Do, Build 46.
- [x] iPhone Bearbeiten / Fertig + Siri-Nachfrage **„o“**, Build 47.
- [x] To-Do-Siri Mehrwort-Aufgaben: ein-tokeniges `parameterSummary`, Build 48.
- [x] To-Do-Siri Phrase ein Token (`Todo`), gesprochen „Hey Siri, Einkauf Todo“, Build 49.
- [x] Swipe-Löschen nur im Bearbeiten-Modus (To-Do Listen-Modus + Einkauf Geh-Modus), Build 50.
- [ ] Folge-PRs halten die Reihenfolge 7→9 und die Isolation (eigene Datei, eigenes `kind`/`format`, eigener Store, WC-Diskriminator).
