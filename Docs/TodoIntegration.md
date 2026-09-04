# Plan: To-Do als zweiter Reiter (native Einkauf)

Stand: 2026-09-04. **Nur Planung** — dieser PR implementiert kein Swift-Feature.
Wenn Verhalten landet: `Description.md` nachziehen (Phase 9), diese Datei nicht als Spec der laufenden App behandeln.

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

`WCSession.applicationContext` ist **ein** Dictionary — letzter Schreiber gewinnt. Wenn To-Do denselben Slot mit einem eigenen Payload überschreibt, verliert die Watch den Einkaufs-Stand bis zum nächsten Einkaufs-Write.

Heutige `kind`-Werte (unverändert lassen, weiter routen):

- `einkauf-sync` + `blob` (lokales Einkauf-JSON)
- `einkauf-toggle` (`id`, `done`, `at`)
- `einkauf-pull`

Pflicht: **Diskriminator**, sodass Payloads nie in den anderen Store laufen.

Vorschlag (Phase 6, nicht dieser PR):

```
applicationContext = {
  einkauf: { kind: "einkauf-sync", v, blob },
  todo:    { kind: "todo-sync",    v, blob }
}
```

oder gleichberechtigte Geschwister-Keys, die `ConnectivitySync.handleIncoming` **ignoriert**, solange `kind` nicht `einkauf-*` ist.

Zusätzlich eigene Message-Kinds:

- `todo-sync` / `todo-toggle` / `todo-pull`

`handleIncoming` heute: unbekanntes `kind` ohne Blob wird ignoriert; mit Blob wird `BackupCodec.decodeLocal` versucht (Catch bei Fehlschlag). To-Do-Blob darf **nicht** zufällig als `AppState` dekodieren. Decoder an `kind: "todo-local"` binden.

`WatchSessionActor` ist ein Singleton am `WCSession.default`. Ein zweiter Delegate geht nicht. Phase 6: denselben Actor um eine zweite `weak var todoStore` (oder einen Multiplexer) erweitern — Einkaufs-Pfad nicht regressieren.

Toggle-Merge analog Einkauf: Zeitstempel (`updatedAt` oder natives `completedChangedAt`); ohne Stempel: erledigt gewinnt. Listenstruktur: `nextUid` / Revision, nicht `listRevision` von Einkauf wiederverwenden.

### Siri

Einkauf: Utterance mit App-Namen + **besorgen** (`EinkaufAddItemsIntent`). Das Wort nicht umdeuten.

To-Do-Siri: **nicht v1**, wenn überhaupt später. Keine zweite Phrase mit „besorgen“. Kein `AppShortcutsProvider`, der Einkaufs-Phrasen verdünnt.

### Theme

HTML-To-Do teilt Site-Keys `supervised-info.theme` / `supervised-info.palette`. Native Einkauf hat eigene Keys `einkauf.theme` / `einkauf.palette` in Einstellungen.

To-Do-Tab in der nativen App: **dieselbe** native Darstellung wie Einkauf (`AppearanceSettings`), kein zweites Theme, keine HTML-Keys. Watch: weiter Vintage + System-`colorScheme` (Einkauf-Spec).

---

## Phasierter Ablaufplan (Reihenfolge)

Jeder Schritt ist ein eigener PR gegen `main`, sobald der vorige landet. Dieser PR ist nur Schritt 1.

### 1. Branch + dieser Plan (dieser PR)

- Datei `Docs/TodoIntegration.md`
- kurzer Verweis in `Description.md` unter **Geplant / WIP**
- kein Feature-Swift

### 2. Models + Persistenz + leerer `TodoStore` (keine UI)

- `TodoTask` / `TodoState` gemäß Task-Shape
- `TodoPersistence` → `todo-local.json` in `group.net.tschelle.einkauf` / `Einkauf/`
- Envelope `kind: "todo-local"`; fremdes `kind` ablehnen
- Tests: Roundtrip, leere Datei, **Einkauf-Datei wird nicht gelesen/geschrieben**
- `project.yml` / Targets: Shared-Quellen, noch keine Views
- Linux: `python3 Scripts/verify_core.py` weiter grün; Swift-Tests auf dem Mac

### 3. iPhone-Tab-Shell + grundlegendes Listen-CRUD

- `TabView` um die bestehende Einkaufs-UI
- To-Do: Text anlegen, abhaken, löschen, umbenennen
- Person / Prio / Datum noch weglassbar oder als leere Felder
- Einkaufs-Tab pixel- und verhaltensgleich (Regression)

### 4. Person / Prio A–B / dueDate + Abgeschlossen-Toggle

- Felder wie HTML-Add-Form
- „Abgeschlossen einblenden“ analog HTML (`todo-v3-show-completed` Verhalten; natives Flag geräte-lokal)
- Overdue-Markierung: `dueDate < heute` und nicht `9999*`
- Prio-Compare-Hinweis: `prioA + (prioB||'9')`, fehlendes `prioA` ans Ende

### 5. Backup Import/Export JSON (eigenes Menü im To-Do-Tab)

- Export `format: "todo-v3-json"`
- Import Array oder `{tasks, nextUid}`; Anhängen vs. Ersetzen wenn Liste nicht leer (HTML-Modal)
- Share-Sheet / `onOpenURL`: Router `einkauf-backup` vs `todo-v3-json`
- **Kein** MD/CSV in dieser Phase (Phase 8)
- Fixtures unter z. B. `Fixtures/todo-v3-json.json` — nicht in `BackupCodec`-Einkaufstests hängen

### 6. Watch Geh-Modus + Sync nur für To-Do

- Watch-Tab To-Do: offene Aufgaben, Toggle done
- WatchConnectivity-Diskriminator; Application-Context **beide** Domains
- Einkaufs-Sync und Complication unverändert
- Build-Nummer hochzählen (Watch-UI)

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

## Non-Goals für diesen PR (Phase 1)

- Kein Swift-Feature-Code, keine leeren Stub-Ordner unter `Sources/`
- Keine TabView, kein `TodoStore`, keine `project.yml`-Änderung
- Keine Watch-UI, keine Widgets/Complications für To-Do
- Keine Siri-/App-Intent-Änderung
- Kein Anfassen von `BackupCodec`, `ConnectivitySync`, `Persistence`, `ShoppingStore`
- Spec `Description.md` nicht umschreiben, als wäre To-Do schon da — nur der WIP-Verweis

---

## Non-Goals für To-Do-v1 (über diesen PR hinaus)

- To-Do-Homescreen-Widget, Watch-Complication, Sperrbildschirm
- To-Do-Siri; keine Kollision mit „besorgen“
- Bearbeiten / Prio / Reopen auf der Watch
- iCloud, CloudKit, gemeinsames JSON mit Einkauf
- HTML Theme-Mast / Service Worker / Shared-Keys in der nativen App
- MD/CSV Pflicht
- App-Store-Submit, Display-Name-Änderung (App bleibt **Einkauf**)

---

## Landminen im heutigen Code (für spätere PRs)

1. **`Persistence.fileName`** ist `"einkauf-local.json"` — To-Do braucht eine zweite Datei, keine Parameter-Verwechslung.
2. **`BackupCodec.looksLikeBackup`**: heuristisch `v==1` + `items`+`stores`. To-Do-JSON darf dort nie landen; Router zuerst.
3. **`ContentView.onOpenURL`**: alles außer `einkauf://` → `store.importBackup`. Muss später branchen.
4. **`Info.plist` `public.json`**: eine geöffnete `todo-liste.json` trifft die Einkaufs-App. Router oder eigener UTType `net.tschelle.einkauf.todo-backup`.
5. **`WatchSessionActor.shared` + ein `ConnectivitySync.store: ShoppingStore?`**: Multiplex, nicht zweites `WCSession.delegate`.
6. **Application Context last-write-wins**: To-Do darf den Einkaufs-Snapshot nicht verdrängen.
7. **`makeID` / `Int64`**: Watch `arm64_32` — UIDs als `Int64`/`UInt64`, nicht 32-bit `Int` aus Epoch-Millis.
8. **Siri `AppShortcutsProvider`**: keine zweite Phrase, die „besorgen“ oder den App-Namen verdünnt.
9. **Tests `EinkaufCoreTests`**: Fixtures und `kind: einkauf-backup`-Asserts nicht für To-Do umbiegen; neue Test-Datei.

---

## Dateivorschläge (ab Phase 2, nicht in diesem PR)

```
Sources/Shared/TodoModels.swift
Sources/Shared/TodoPersistence.swift
Sources/Shared/TodoStore.swift
Sources/Shared/TodoBackupCodec.swift
Sources/iOS/TodoListView.swift          // Phase 3
Sources/Watch/WatchTodoListView.swift   // Phase 6
Fixtures/todo-v3-json.json              // Phase 5
Tests/EinkaufCoreTests/TodoStoreTests.swift
```

Namen dürfen abweichen; die Trennung von `ShoppingStore` / `BackupCodec` / `einkauf-*.json` nicht.

---

## Akzeptanz dieser Planungs-PR

- [x] Plan liegt unter `Docs/TodoIntegration.md` (Deutsch).
- [x] `Description.md` verweist unter Geplant/WIP hierher, behauptet To-Do nicht als geliefert.
- [x] Kein Feature-Swift.
- [ ] Folge-PRs halten die Reihenfolge 2→9 und die Isolation (eigene Datei, eigenes `kind`/`format`, eigener Store, WC-Diskriminator).
