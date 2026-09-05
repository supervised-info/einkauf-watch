# To-Do als zweiter Reiter (native Einkauf)

Stand: 2026-09-05, Build 62. Phasen 1–10 **geliefert**. iPhone-Listen ohne großen Nav-Titel, Toolbar kompakt (`einkaufToolbarChrome`). Natives Verhalten: `Description.md`. HTML-Listen sind ein Follow-up auf demselben `todo-v3-json`-Schema.

Begleit-Leser: Menschen und Regeneratoren. Swift-Quellen bleiben die Wahrheit. HTML-PWA [todo](https://supervised-info.github.io/todo/) ist die Produktreferenz für Task-Shape und JSON-Brücke.

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
| Native Einkauf + To-Do | dieses Repo, `Description.md` (gelieferter Stand, Build 62) |

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
  listId: string | "" | null   // optional; fehlt/leer = unassigned / Alle
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

`lists` und `listId`: fehlend/null/leer = keine Listen / Aufgabe unassigned (**Alle**). Decode ignoriert unbekannte Felder. Alte Dateien ohne diese Keys laden unverändert. HTML-Follow-up soll dasselbe Schema schreiben.

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
    Tab 2 „To-Do“   → TodoListView (eigene NavigationStack, kein Nav-Titel)
```

Tab-Labels **Einkauf | To-Do**, SF-Symbols `basket` / `checklist`. Beide iPhone-Listen: **kein** Navigationstitel (Tab reicht), Toolbar kompakt (`einkaufToolbarChrome`). Einkaufs-Toolbar, Overflow, Einstellungen, Add-Leiste bleiben **im Einkaufs-Tab**. To-Do hat ein **eigenes** Overflow (Import/Export/Liste teilen), kein gemeinsames „…“ das beide Domains anfasst. **Einstellungen** (`SettingsSheet`, geöffnet vom Einkauf-**…**) hat zusätzlich die Sektion **To-Do Backup**: JSON **Backup importieren…** / **exportieren…** / **teilen** über `TodoStore` (`TodoImport.offer` / `importAny`). MD/CSV bleiben nur im To-Do-**…**. Einkauf-JSON wird dort abgelehnt, nie in `ShoppingStore` geschrieben.

`onOpenURL` auf `EinkaufRoot` (`IncomingJSON`): Envelope entscheidet (`einkauf-backup` vs `todo-v3-json`). Widget-URL `einkauf://list` = Einkaufs-Tab, `einkauf://todo` = To-Do-Tab.

### Watch (geliefert)

Zwei Reiter **Einkauf | To-Do**. To-Do auf der Watch **nur Geh-Modus**:

- Filter auf die vom iPhone gesyncte aktuelle Liste (`todo.currentListId`, leer = **Alle**)
- offene und (per Auge) erledigte Aufgaben: kompaktes `#uid` + Text; Person/Prio/Datum als kompakte Nebeninfo; bei erledigt `completedDate` als „geschlossen TT.MM.JJJJ“
- Tippen toggelt `completed` (wie Einkauf-Checkbox)
- **kein** volles Edit, kein Prio-Picker, keine reopen-Pills, kein Import/Export, keine Suche, kein Sort, keine Listen-Verwaltung

Erledigte ausblenden: eigenes Flag (`todo.watch.hideCompleted`), **nicht** `einkauf.watch.hideCompleted`, nicht im Backup, nicht zum iPhone.

Watch-To-Do-Complication `TodoProgress` (Label **To Do**, offene Anzahl der aktuellen Liste / „erledigt“). Kein To-Do-Homescreen-Widget.

### Store und Persistenz

Eigener Store: `TodoStore` + `TodoState` + `TodoTask`.

| | Einkauf | To-Do |
|---|---|---|
| Store | `ShoppingStore` | `TodoStore` |
| Datei | `einkauf-local.json` | `todo-local.json` |
| Ordner | App Group `Einkauf/` | **derselbe** Ordner |
| Local envelope | `kind: "einkauf-local"` | `kind: "todo-local"` |
| Backup | `kind: "einkauf-backup"` | `format: "todo-v3-json"` |
| Notification | `.einkaufStateDidChangeOnDisk` | `.todoStateDidChangeOnDisk` |

`Persistence` bleibt auf `einkauf-local.json`. **Nicht** die Einkaufs-API umbiegen, sodass sie zwei Dateien schreibt. Eigene Persistenz (`TodoPersistence`). Ein verwechselter `fileName` würde die Einkaufsliste überschreiben.

### Warum dieselbe App Group OK ist

App Group bleibt `group.net.tschelle.einkauf`.

1. iPhone-App, Watch-App und Widgets müssen denselben Container sehen — zweite Group brächte neue Entitlements und ändert nichts an der Watch-Paarung.
2. Isolation ist **Dateiname + Envelope-`kind`**, nicht der Container. `einkauf-local.json` und `todo-local.json` liegen nebeneinander; Decoder lehnen fremdes `kind` ab.
3. UserDefaults-Suite derselben Group: Siri-Pending `einkauf.siriPendingAdds` / `todo.siriPendingAdds`. To-Do-Keys mit Präfix `todo.` namespaced halten.
4. Kein iCloud für den Store. Kein zweites Bundle. (Einkauf-Inbox ist eine fremde Drive-Datei, siehe `Description.md` → **iCloud-Inbox**.)

Nicht OK: To-Do-Array in `AppState.items` oder ein gemeinsames JSON-Objekt „alles in einer Datei“.

### Backup-Envelope

Zwei Ebenen, nicht vermischen:

1. **HTML-Brücke** (Pflicht für Roundtrip mit der PWA): `format: "todo-v3-json"`. Native Export/Import schreibt und liest das (Defaultname analog `todo-liste` / gestempelt `yyyyMMdd_HHmm-todo-liste.json`).
2. **Native-lokales Extra** (optional, intern): `kind: "todo-backup"` darf interne Sync-Felder tragen, **solange** der PWA-Export weiterhin `todo-v3-json` ohne Einkauf-Felder ist.

Öffentlicher Dateiexport = **genau** `todo-v3-json` (HTML-parity). `kind: "todo-backup"` nur wenn native-only Felder nötig sind; dann beide erkennen, nie `einkauf-backup`.

Import-Menü **nur im To-Do-Tab** (plus **Einstellungen → To-Do Backup** für JSON). Einkaufs-Overflow bleibt bei Einkauf-Backups. `BackupError.notABackup` („Keine gültige Einkauf-Backup-Datei.“) darf To-Do-JSON nicht als Einkauf schlucken.

`Info.plist` deklariert die App als Owner von `public.json` + `net.tschelle.einkauf.backup`. Share-Sheet-Öffnen einer `todo-liste.json` trifft die Einkaufs-App; Router nach `format`/`kind`; fremdes Format → Fehlertext, kein stilles No-op auf die Einkaufsliste.

### WatchConnectivity

`WCSession.applicationContext` ist **ein** Dictionary — letzter Schreiber gewinnt. To-Do darf denselben Slot nicht mit einem eigenen Payload überschreiben.

```
applicationContext = {
  einkauf: { kind: "einkauf-sync", v, blob },
  todo:    { kind: "todo-sync",    v, blob, currentListId }
}
```

Beim Senden einer Domain: `session.applicationContext` lesen (`WatchSyncEnvelope.merging`), nur den eigenen Key setzen, zurückschreiben. Backward-compat: top-level `kind == "einkauf-sync"` gilt weiter als Einkauf-only.

Message-Kinds:

- `einkauf-sync` / `einkauf-toggle` / `einkauf-pull` (unverändert)
- `todo-sync` / `todo-toggle` (`uid` Int64 oder NSNumber) / `todo-pull`

To-Do-Blob = `TodoCodec.encodeLocal` / `decodeLocal` (`kind: "todo-local"`, trägt `lists` + je Task `listId`). Die aktuelle Listenwahl liegt **nicht** im Blob, sondern als Geschwisterfeld `currentListId` (leer = Alle). Die Watch schreibt das nach App-Group `todo.currentListId`. `BackupCodec.decodeLocal` darf To-Do-Blobs nicht als `AppState` schlucken.

`WatchSessionActor` bleibt Singleton am `WCSession.default`. `attach` (`ConnectivitySync`) und `attachTodo` (`TodoConnectivitySync`) — kein zweites Delegate.

Toggle-Merge analog Einkauf: Zeitstempel `updatedAt`; ohne Stempel: erledigt gewinnt. Listenstruktur: `revision` / `nextUid`, nicht `listRevision` von Einkauf. Import (Ersetzen/Anhängen) setzt `revision = max(lokal, import, nach Normalize) + 1` und `persistAndSync` — sonst überschreibt der Peer eine leere/ältere Liste mit höherer `revision` (HTML-Brücke hat keine `revision`).

### Siri

Einkauf: Utterance mit App-Namen + **besorgen** (`EinkaufAddItemsIntent`). Das Wort nicht umdeuten.

To-Do-Siri: `TodoAddItemsIntent`, Phrasen **Todo** (ein Token, nicht `To Do` — Siri begrenzt zwei Phrase-Tokens auf zwei Wörter Capture), optional **Aufgaben**, `shortTitle` **Todo**. iPhone-Nachfrage **„o“** (`requestValueDialog`); watchOS **ohne** `requestValueDialog` (generische Freitext-Nachfrage). `parameterSummary` **ein Token** `Todo \(.$items)`. Spoken: **„Hey Siri, Einkauf Todo“**. Nach Update Shortcut löschen/neu und **„Auf Apple Watch anzeigen“** erneut. Beide Shortcuts in **einem** `EinkaufShortcuts` (`AppShortcutsProvider`) — Apple erlaubt nur eine Conformance. Keine zweite Phrase mit „besorgen“. Neue Aufgaben landen in der **aktuellen** Liste.

### Theme

HTML-To-Do teilt Site-Keys `supervised-info.theme` / `supervised-info.palette`. Native Einkauf hat eigene Keys `einkauf.theme` / `einkauf.palette` in Einstellungen.

To-Do-Tab in der nativen App: **dieselbe** native Darstellung wie Einkauf (`AppearanceSettings`), kein zweites Theme, keine HTML-Keys. Watch: weiter Vintage + System-`colorScheme` (Einkauf-Spec).

---

## Historie (alle gelandet)

Produktverhalten steht in `Description.md`. Hier nur die gelandeten Schnitte, ohne offenen Plan.

| Schnitt | Build | Was |
|---|---|---|
| 1 Plan | — | diese Datei |
| 2 Models + Persistenz | — | `TodoStore` / `todo-local.json` |
| 3 iPhone-Tab | 42 | **Einkauf \| To-Do**, Text-CRUD |
| 4 Person / Prio / Datum | 43 | Add-Form, Overdue, Auge `todo.iphone.showCompleted` |
| 5 JSON-Backup | 44 | `todo-v3-json`, To-Do-**…**, `onOpenURL`-Router |
| Liste teilen PDF | 45 | folgt Auge |
| 6 Watch + WC + Siri | 46 | Watch-Tab, `{einkauf, todo}`, Complication **To Do**, `TodoAddItemsIntent` |
| iPhone **Edit** + Siri „o“ | 47 | Swipe-Löschen nur Edit (Build 50); Label **Edit** |
| Siri Mehrwort / ein Token | 48–51 | Phrase **Todo**, Watch ohne `requestValueDialog` |
| 7 Reopen / Sort / Suche | 52 | iPhone; Watch bleibt Geh-Modus |
| 8 MD/CSV | 53 | volle Liste, iPhone-only |
| 9 Spec | — | `Description.md` als geliefertes Produkt |
| 10 Listen | 55 | `lists` / `listId`, Filter **Alle**, PDF+Siri+Watch |
| Einstellungen Backup | 56 | **To-Do Backup** JSON |
| Import-`revision`-Floor | 57 | `max(lokal, import) + 1`; „geschlossen …“ |
| `#uid` + reopen-Pills | 58 | iPhone wie HTML; Watch kompaktes `#uid` |
| iPhone-Nav kompakt | 62 | kein Listen-Titel, `einkaufToolbarChrome` |

---

## Non-Goals (weiterhin)

- To-Do-Homescreen-Widget, Sperrbildschirm (Watch-To-Do-Complication ist gelandet)
- To-Do-Siri verdünnt nicht „besorgen“ (ein `AppShortcutsProvider`)
- Edit / Prio / Reopen / Listen-Verwaltung auf der Watch (Watch filtert nur)
- iCloud / CloudKit für den To-Do-Store; gemeinsames JSON mit Einkauf; To-Do-Inbox
- HTML Theme-Mast / Service Worker / Shared-Keys in der nativen App
- App-Store-Submit, Display-Name-Änderung (App bleibt **Einkauf**)

Inbox Phase 4 (concurrent Append) ist **kein** To-Do-Thema — siehe `Description.md` → **iCloud-Inbox (Zweitgerät)**.

---

## Landminen (weiterhin gültig)

1. **`Persistence.fileName`** ist `"einkauf-local.json"` — To-Do braucht eine zweite Datei, keine Parameter-Verwechslung.
2. **`BackupCodec.looksLikeBackup`**: heuristisch `v==1` + `items`+`stores`. To-Do-JSON darf dort nie landen; Router zuerst.
3. **`onOpenURL`**: sitzt auf `EinkaufRoot` (`IncomingJSON`), nicht `ContentView`.
4. **`Info.plist` `public.json`**: eine geöffnete `todo-liste.json` trifft die Einkaufs-App. Router oder eigener UTType `net.tschelle.einkauf.todo-backup`.
5. **`WatchSessionActor.shared`**: Multiplex, nicht zweites `WCSession.delegate`.
6. **Application Context last-write-wins**: To-Do darf den Einkaufs-Snapshot nicht verdrängen; `currentListId` gehört ins `todo-sync`-Payload, nicht in den Blob.
7. **`makeID` / `Int64`**: Watch `arm64_32` — UIDs als `Int64`/`UInt64`, nicht 32-bit `Int` aus Epoch-Millis.
8. **Siri `AppShortcutsProvider`**: nur eine Conformance pro App; To-Do-Phrasen in `EinkaufShortcuts`, keine zweite Phrase mit „besorgen“.
9. **Tests `EinkaufCoreTests`**: Fixtures und `kind: einkauf-backup`-Asserts nicht für To-Do umbiegen.

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
Fixtures/todo-v3-json.json
Fixtures/todo-liste.md
Fixtures/todo-liste.csv
Tests/EinkaufCoreTests/TodoStoreTests.swift
```

Trennung von `ShoppingStore` / `BackupCodec` / `einkauf-*.json` nicht aufweichen.

---

## Akzeptanz

- [x] `Description.md` beschreibt To-Do als geliefertes Produkt (Build 62), nicht als WIP.
- [x] Isolation: eigener Store, `todo-local.json` / `kind: "todo-local"`, Backup `todo-v3-json`, WC `{einkauf, todo}` plus `currentListId`.
- [x] iPhone: Text, Person, Prio, Datum, Listen, `#uid` + reopen-Pills, Auge, **Edit** / **Fertig**, Swipe-Löschen nur Edit, Reopen, Sort, Suche, MD/CSV volle Liste, PDF folgt Liste + Auge.
- [x] iPhone-Nav ohne Listen-Titel, Toolbar kompakt (`einkaufToolbarChrome`).
- [x] Watch nur Geh-Modus (Filter `todo.currentListId`, kompaktes `#uid`, kein Edit/Reopen/Suche/Listen-UI). Complication **To Do**.
- [x] Siri **Todo** (ein Token, iPhone „o“, Watch ohne `requestValueDialog`), ein `AppShortcutsProvider`.
- [x] **Einstellungen → To-Do Backup** (JSON); Import-`revision`-Floor analog Einkauf.
- [x] Phasen 1–10 und Folgearbeit bis Build 62 gelandet. Kein offener To-Do-Plan.
