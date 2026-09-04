#!/usr/bin/env python3
"""Linux-Checks für Backup-JSON, Sortierung und Projektdateien (ohne Xcode)."""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DEPTS = [
    "vor", "obst", "brot", "bedienung", "kuehlung", "tiefkuehl",
    "trocken", "suess", "getraenke", "drogerie", "sonstiges", "nach",
]


def fail(msg: str) -> None:
    print(f"FAIL: {msg}", file=sys.stderr)
    sys.exit(1)


def extract_braced(src: str, start: int, what: str) -> str:
    brace = src.find("{", start)
    if brace < 0:
        fail(f"{what} missing opening brace")
    depth = 0
    for j in range(brace, len(src)):
        if src[j] == "{":
            depth += 1
        elif src[j] == "}":
            depth -= 1
            if depth == 0:
                return src[start : j + 1]
    fail(f"{what} is unclosed")
    return ""


def extract_some_view(src: str, name: str) -> str:
    """Body of `var <name>: some View { ... }` including nested braces."""
    m = re.search(rf"(?:private\s+)?var {re.escape(name)}\s*:\s*some View\s*\{{", src)
    if not m:
        fail(f"Watch widget missing {name} view")
    return extract_braced(src, m.start(), f"Watch widget {name} view")


def extract_watch_eye_bar(watch: str) -> str:
    """Watch hide-completed chrome above the title (HStack + Spacer, not toolbar)."""
    if re.search(r"ToolbarItem\(placement:\s*\.topBarLeading\)", watch) or "topBarLeading" in watch:
        fail("Watch hide toggle must not sit in topBarLeading (clips Einkauf oo/xx/yy)")
    if "ToolbarItem" in watch:
        fail("Watch must not put the eye in a ToolbarItem")
    for m in re.finditer(r"HStack(?:\s*\([^)]*\))?\s*\{", watch):
        block = extract_braced(watch, m.start(), "Watch eye HStack")
        if "hideCompleted.toggle" in block and "eye.slash" in block:
            if "Spacer()" not in block:
                fail("Watch eye HStack must use Spacer() so the eye is leading above the title")
            btn_pos = block.find("Button")
            spacer_pos = block.find("Spacer()")
            if btn_pos < 0 or spacer_pos < btn_pos:
                fail("Watch eye HStack must be { Button…; Spacer() } (leading, not trailing)")
            if "ForEach" in block or "walkListRows" in block:
                fail("Watch eye must not live inside a walk-list row")
            return block
    fail("Watch hide toggle must sit in an HStack { Button; Spacer() } above the title")
    return ""


LARGE_PROGRESS_FONT = re.compile(r"\.(largeTitle|title[23]?|headline)\b")


def assert_no_large_progress_text(view_src: str, name: str) -> None:
    if LARGE_PROGRESS_FONT.search(view_src):
        fail(
            f"{name} must not use large system text (.title/.title2/.title3) "
            "on progressLabel — watchOS draws !"
        )
    for size in (int(n) for n in re.findall(r"\.system\(size:\s*(\d+)", view_src)):
        if size > 13:
            fail(f"{name} system size {size}pt is too large for accessory (use ~11–13pt)")


def assert_corner_count_larger_than_label(corner: str) -> None:
    """Corner: open-count ~18–20pt, store widgetLabel caption/~11–12pt."""
    count_m = re.search(r"compactCountText[\s\S]*?\.system\(size:\s*(\d+)", corner)
    if not count_m:
        fail("corner compactCountText must use explicit system size (18–20pt)")
    count_pt = int(count_m.group(1))
    if count_pt < 18 or count_pt > 20:
        fail(f"corner compactCountText is {count_pt}pt; expected ~18–20pt, larger than the store label")
    if "minimumScaleFactor" not in corner:
        fail("corner must keep minimumScaleFactor so erledigt can shrink")
    label_start = corner.find("widgetLabel")
    if label_start < 0:
        fail("corner must keep store name in widgetLabel")
    label = corner[label_start:]
    caption_style = ".caption" in label or re.search(r"\.system\(size:\s*1[12]\b", label)
    if not caption_style:
        fail("corner widgetLabel must use caption / ~11–12pt so the count reads larger")
    label_sizes = [int(n) for n in re.findall(r"\.system\(size:\s*(\d+)", label)]
    if label_sizes and label_sizes[0] >= count_pt:
        fail("corner widgetLabel must be smaller than compactCountText")


def sanitized_layout(layout: list[str]) -> list[str]:
    seen: set[str] = set()
    middle: list[str] = []
    for d in layout:
        if d not in DEPTS or d in seen:
            continue
        seen.add(d)
        if d in ("vor", "nach"):
            continue
        middle.append(d)
    return ["vor"] + middle + ["nach"]


def groups(items: list[dict], layout: list[str]) -> list[str]:
    layout = sanitized_layout(layout)
    in_layout = set(layout)
    by: dict[str, list[dict]] = {}
    for it in items:
        d = it.get("dept") if it.get("dept") in DEPTS else "sonstiges"
        by.setdefault(d, []).append(it)
    for d in by:
        by[d].sort(key=lambda it: (it.get("ord") if isinstance(it.get("ord"), (int, float)) else 0, it.get("added") or 0, it.get("name") or ""))
    used = set()
    out = []

    def push(d: str) -> None:
        if d in used or d not in by or not by[d]:
            return
        out.append(d)
        used.add(d)

    for d in layout:
        if d != "nach":
            push(d)
    for d in DEPTS:
        if d not in in_layout:
            push(d)
    push("nach")
    return out


def test_store_switch_changes_group_order() -> None:
    items = [
        {"name": "Äpfel", "dept": "obst", "ord": 1, "added": 1},
        {"name": "Milch", "dept": "kuehlung", "ord": 1, "added": 1},
        {"name": "Seife", "dept": "drogerie", "ord": 1, "added": 1},
    ]
    edeka = [
        "vor", "obst", "bedienung", "brot", "kuehlung", "tiefkuehl",
        "trocken", "suess", "getraenke", "drogerie", "sonstiges", "nach",
    ]
    dm = ["vor", "drogerie", "trocken", "getraenke", "sonstiges", "nach"]
    edeka_ids = groups(items, edeka)
    dm_ids = groups(items, dm)
    if edeka_ids == dm_ids:
        fail(f"store switch should change group order, both {edeka_ids}")
    if edeka_ids != ["obst", "kuehlung", "drogerie"]:
        fail(f"edeka groups {edeka_ids}")
    if dm_ids != ["drogerie", "obst", "kuehlung"]:
        fail(f"dm groups {dm_ids}")
    print("store switch groups: ok")


def test_walk_lines_screenshot_items() -> None:
    items = [
        {"name": "Kinderschokolade", "dept": "suess", "ord": 1, "added": 1},
        {"name": "Toilettenpapier", "dept": "drogerie", "ord": 1, "added": 1},
        {"name": "AXE", "dept": "sonstiges", "ord": 1, "added": 1},
    ]
    edeka = [
        "vor", "obst", "bedienung", "brot", "kuehlung", "tiefkuehl",
        "trocken", "suess", "getraenke", "drogerie", "sonstiges", "nach",
    ]
    dm = ["vor", "drogerie", "trocken", "getraenke", "sonstiges", "nach"]
    edeka_ids = groups(items, edeka)
    dm_ids = groups(items, dm)
    if edeka_ids != ["suess", "drogerie", "sonstiges"]:
        fail(f"edeka walk headers {edeka_ids}")
    if dm_ids != ["drogerie", "sonstiges", "suess"]:
        fail(f"dm walk headers {dm_ids}")
    print("walk lines screenshot items: ok")


def test_sonstiges_follows_layout_position() -> None:
    items = [
        {"name": "AXE", "dept": "sonstiges", "ord": 1, "added": 1},
        {"name": "Äpfel", "dept": "obst", "ord": 1, "added": 2},
    ]
    a = groups(items, ["vor", "sonstiges", "obst", "nach"])
    b = groups(items, ["vor", "obst", "sonstiges", "nach"])
    if a != ["sonstiges", "obst"]:
        fail(f"store A sonstiges first: {a}")
    if b != ["obst", "sonstiges"]:
        fail(f"store B obst first: {b}")
    dm = ["vor", "drogerie", "trocken", "getraenke", "sonstiges", "nach"]
    dm_ids = groups(
        [
            {"name": "Toilettenpapier", "dept": "drogerie", "ord": 1, "added": 1},
            {"name": "AXE", "dept": "sonstiges", "ord": 1, "added": 2},
        ],
        dm,
    )
    if dm_ids != ["drogerie", "sonstiges"]:
        fail(f"dm seed should keep sonstiges before nach: {dm_ids}")
    print("sonstiges layout position: ok")


def test_fixtures() -> None:
    full = json.loads((ROOT / "Fixtures/einkauf-backup.json").read_text())
    if full.get("kind") != "einkauf-backup":
        fail("Fixture kind")
    if "staples" not in full:
        fail("main fixture should include staples")
    unknown = [i for i in full["items"] if i.get("dept") == "nicht-da"]
    if not unknown:
        fail("expected unknown dept item")
    store = next(s for s in full["stores"] if s["id"] == full["currentStoreId"])
    ids = groups(full["items"], store["layout"])
    if ids[0] != "vor" or ids[-1] != "nach":
        fail(f"vor/nach order: {ids}")
    expected = ["vor", "obst", "bedienung", "brot", "kuehlung", "tiefkuehl", "trocken", "suess", "getraenke", "drogerie", "sonstiges", "nach"]
    if ids != expected:
        fail(f"edeka groups {ids} != {expected}")
    # unknown dept lands in sonstiges
    sonst = [i["name"] for i in full["items"] if (i["dept"] if i["dept"] in DEPTS else "sonstiges") == "sonstiges"]
    if "Unbekannte Abteilung" not in sonst or "Batterien" not in sonst:
        fail(f"sonstiges items: {sonst}")

    minimal = json.loads((ROOT / "Fixtures/einkauf-backup-ohne-staples.json").read_text())
    if "staples" in minimal:
        fail("minimal fixture should omit staples")
    if minimal["kind"] != "einkauf-backup":
        fail("minimal kind")
    store = next(s for s in minimal["stores"] if s["id"] == minimal["currentStoreId"])
    ids = groups(minimal["items"], store["layout"])
    if ids[0] != "vor" or ids[-1] != "nach":
        fail(f"minimal vor/nach: {ids}")

    todo_fix = json.loads((ROOT / "Fixtures/todo-v3-json.json").read_text())
    if todo_fix.get("format") != "todo-v3-json":
        fail("todo fixture must use format todo-v3-json")
    if todo_fix.get("kind") in ("einkauf-backup", "einkauf-local"):
        fail("todo fixture must not use einkauf kind")
    if "stores" in todo_fix or "items" in todo_fix:
        fail("todo fixture must not look like einkauf-backup")
    if not isinstance(todo_fix.get("tasks"), list) or not todo_fix["tasks"]:
        fail("todo fixture needs a tasks array")
    print("fixtures: ok", expected if False else ids, "and full", groups(full["items"], next(s for s in full["stores"] if s["id"] == "edeka")["layout"]))


def test_sources() -> None:
    sync = (ROOT / "Sources/Shared/ConnectivitySync.swift").read_text()
    for needle in [
        "WCSession",
        "updateApplicationContext",
        "sendMessage",
        "transferUserInfo",
        "didReceiveApplicationContext",
        "didReceiveMessage",
        "didReceiveUserInfo",
    ]:
        if needle not in sync:
            fail(f"sync missing {needle}")
    if "TODO" in sync and "stub" in sync.lower():
        fail("sync looks stubbed")
    envelope = (ROOT / "Sources/Shared/WatchSyncEnvelope.swift").read_text()
    if "WatchSyncEnvelope.merging" not in sync:
        fail("WatchSessionActor must merge applicationContext via WatchSyncEnvelope")
    if 'einkaufKey = "einkauf"' not in envelope or 'todoKey = "todo"' not in envelope:
        fail("merged application context must keep einkauf and todo keys")
    if "todo-sync" not in envelope or "todo-toggle" not in envelope or "todo-pull" not in envelope:
        fail("WatchSyncEnvelope must name todo-sync / todo-toggle / todo-pull")
    if "einkauf-sync" not in envelope or "einkauf-toggle" not in envelope or "einkauf-pull" not in envelope:
        fail("WatchSyncEnvelope must keep einkauf-sync / einkauf-toggle / einkauf-pull")
    if "attachTodo" not in sync:
        fail("WatchSessionActor must attach TodoConnectivitySync without a second WCSession.delegate")
    store = (ROOT / "Sources/Shared/ShoppingStore.swift").read_text()
    if "func toggle" not in store:
        fail("no toggle")
    codec = (ROOT / "Sources/Shared/BackupCodec.swift").read_text()
    if "savedLists" not in codec:
        fail("backup codec must mention savedLists")
    if '"mappings": state.mappings' not in codec:
        fail("backup export must keep the mappings field")
    if '"learnedMappings"' in codec or '"userMappings"' in codec or '"meineZuordnungen"' in codec:
        fail("backup codec must not invent a second mappings field")
    pbx = (ROOT / "Einkauf.xcodeproj/project.pbxproj").read_text()
    if "net.tschelle.einkauf" not in pbx:
        fail("bundle id missing")
    if "net.tschelle.einkauf.watchkitapp" not in pbx:
        fail("watch bundle id missing")
    if "Embed Watch Content" not in pbx:
        fail("watch not embedded")
    if "WatchConnectivity.framework" not in pbx:
        fail("WatchConnectivity not linked")
    needed = [
        "Sources/Shared/BackupCodec.swift",
        "Sources/Shared/StoreLayout.swift",
        "Sources/Shared/StapleApply.swift",
        "Sources/Shared/ItemEditing.swift",
        "Sources/Shared/Theme.swift",
        "Sources/Shared/BackupShare.swift",
        "Sources/Shared/ListShare.swift",
        "Sources/iOS/ContentView.swift",
        "Sources/iOS/SettingsSheet.swift",
        "Sources/iOS/KeywordDictionaryView.swift",
        "Sources/iOS/ShareSheet.swift",
        "Sources/iOS/ListPDF.swift",
        "Sources/iOS/TodoListPDF.swift",
        "Sources/iOS/AppearanceSettings.swift",
        "Sources/Shared/KeywordDictionary.swift",
        "Sources/Shared/KeywordDictionaryBrowse.swift",
        "Sources/Shared/SpeechItemSplitter.swift",
        "Sources/Shared/EinkaufAddItemsIntent.swift",
        "Sources/Shared/TodoAddItemsIntent.swift",
        "Sources/Shared/TodoSiriPendingAdds.swift",
        "Sources/Shared/TodoModels.swift",
        "Sources/Shared/TodoCodec.swift",
        "Sources/Shared/TodoPersistence.swift",
        "Sources/Shared/TodoStore.swift",
        "Sources/Shared/IncomingJSON.swift",
        "Sources/Shared/WatchSyncEnvelope.swift",
        "Sources/iOS/TodoListView.swift",
        "Sources/Watch/WatchTodoListView.swift",
        "Sources/WatchWidgets/TodoWatchWidgets.swift",
        "Sources/Watch/WatchListView.swift",
        "Sources/Watch/WatchComplicationReload.swift",
        "Sources/iOS/HomeWidgetReload.swift",
        "Sources/iOSWidgets/EinkaufWidgets.swift",
        "Sources/Watch/EinkaufWatch.entitlements",
        "Sources/WatchWidgets/EinkaufWatchWidgets.swift",
        "Sources/WatchWidgets/Info.plist",
        "Sources/WatchWidgets/EinkaufWatchWidgets.entitlements",
        "Sources/iOS/Assets.xcassets/AppIcon.appiconset/AppIcon.png",
        "Sources/Watch/Assets.xcassets/AppIcon.appiconset/AppIcon.png",
    ]
    for rel in needed:
        if not (ROOT / rel).exists():
            fail(f"missing {rel}")
    content = (ROOT / "Sources/iOS/ContentView.swift").read_text()
    if "Beispiel-Liste" in content or "loadSampleFromBundle" in content:
        fail("sample list still offered in UI")
    einkauf_app = (ROOT / "Sources/iOS/EinkaufApp.swift").read_text()
    if "url.scheme == \"einkauf\"" not in einkauf_app:
        fail("EinkaufRoot onOpenURL must ignore widget tap einkauf:// URLs")
    if "url.host == \"todo\"" not in einkauf_app:
        fail("einkauf://todo must select the To-Do tab")
    if ".onOpenURL" in content:
        fail("onOpenURL must live on EinkaufRoot, not ContentView")
    if "Einstellungen" not in content:
        fail("Einstellungen menu missing")
    if "Geh-Modus" not in content or "Bearbeiten" not in content:
        fail("walk/edit toggle labels missing")
    if "moveItems(in:" in content:
        fail("Bearbeiten still uses per-section onMove")
    if "moveEditRows" not in content or "moveDisabled(true)" not in content:
        fail("Bearbeiten needs flattened list with immovable headers")
    if "Section {" in content:
        fail("ContentView must not use List+Section (store switch keeps old section order)")
    if "ForEach(store.groups)" in content:
        fail("ContentView must not ForEach groups as List sections")
    if "walkListRows(hidingCompleted" not in content:
        fail("iPhone Geh-Modus must use walkListRows(hidingCompleted:) so done items can be filtered")
    if "ForEach(visibleWalkRows)" not in content and "ForEach(store.walkListRows" not in content:
        fail("ContentView walkList must ForEach walk list rows (flat store+position ids)")
    if "ForEach(store.editRows)" not in content:
        fail("Bearbeiten must ForEach the full editRows list")
    if "AppStorage" not in content or "einkauf.iphone.hideCompleted" not in content:
        fail("iPhone hide-completed must persist via AppStorage einkauf.iphone.hideCompleted")
    if "einkauf.watch.hideCompleted" in content:
        fail("iPhone must not reuse the Watch AppStorage key")
    if '"eye"' not in content or "eye.slash" not in content:
        fail("iPhone hide toggle must use eye / eye.slash")
    if "Erledigte ausblenden" not in content or "Erledigte einblenden" not in content:
        fail("iPhone hide toggle missing accessibility labels")
    if "Erledigte ausgeblendet." not in content:
        fail("iPhone must show Erledigte ausgeblendet. when every walk item is hidden")
    if "store.walkLines" in content and "ForEach(store.walkLines)" in content:
        fail("walk ForEach must use walkListRows so ids include position")
    walk_list_id = '.id("walk|\\(store.state.currentStoreId)|\\(store.state.currentStore.layout.joined())")'
    edit_list_id = '.id("edit|\\(store.state.currentStoreId)|\\(store.state.currentStore.layout.joined())")'
    if walk_list_id not in content or edit_list_id not in content:
        fail("ContentView walkList/editList must .id(walk|… / edit|…) plus currentStoreId|layout so Geh-Modus does not reuse swipe-delete")
    walk_list = extract_some_view(content, "walkList")
    if ".onDelete" in walk_list:
        fail("ContentView walkList must not attach onDelete (swipe-delete only in Bearbeiten)")
    if 'role: .destructive' in walk_list or 'Label("Löschen"' in walk_list:
        fail("ContentView walkList must not attach a trailing delete swipeAction")
    if walk_list.count("deleteDisabled(true)") < 2:
        fail("ContentView walk header and item rows must deleteDisabled(true)")
    if walk_list.count("swipeActions(edge: .trailing") < 2 or walk_list.count("EmptyView()") < 2:
        fail("ContentView walk rows must suppress system delete with trailing EmptyView swipeActions")
    if 'id(store.walkMode ? "einkauf-walk" : "einkauf-edit")' not in content:
        fail("ContentView list must change identity when toggling Geh-Modus / Bearbeiten")
    edit_list = extract_some_view(content, "editList")
    if ".onDelete" not in edit_list or "onMove" not in edit_list:
        fail("ContentView editList must keep onDelete swipe and onMove reorder")
    if re.search(r'Picker\(\s*"Laden"', content):
        fail("toolbar must not use Picker for store selection")
    if "store.setStore(s.id)" not in content:
        fail("ContentView store Menu must call store.setStore(s.id)")
    laden_idx = content.find('accessibilityLabel("Laden")')
    store_menu = content[max(0, laden_idx - 900):laden_idx] if laden_idx >= 0 else ""
    if "Menu" not in store_menu or "ForEach(store.stores)" not in store_menu:
        fail("ContentView store selection must be a Menu of store buttons")
    if "checkmark" not in store_menu:
        fail("ContentView store Menu must checkmark the selected store")
    leading = content[content.find("placement: .topBarLeading"):content.find("placement: .topBarTrailing")]
    if 'accessibilityLabel("Laden")' not in leading:
        fail("store Menu must stay topBarLeading")
    if "eye.slash" in leading or "hideCompleted.toggle" in leading:
        fail("eye toggle must not replace the store Menu")
    if content.find("hideCompleted.toggle") < 0 or content.find("hideCompleted.toggle") > content.find('Button(store.walkMode ? "Bearbeiten"'):
        fail("iPhone eye toggle must sit near the Geh-Modus / Bearbeiten control")
    if "func setWalkMode" not in store:
        fail("walkMode not persisted via setWalkMode")
    editing = (ROOT / "Sources/Shared/ItemEditing.swift").read_text()
    if "func moveRows" not in editing:
        fail("ItemEditing missing cross-dept moveRows")
    if "Backup teilen" not in content:
        fail("overflow menu missing Backup teilen")
    if "Liste teilen" not in content:
        fail("overflow menu missing Liste teilen")
    backup_btn = content.find('Button("Backup teilen"')
    list_btn = content.find('Button("Liste teilen"')
    if backup_btn < 0 or list_btn < 0 or list_btn < backup_btn:
        fail("Liste teilen must come after Backup teilen")
    if content[backup_btn:list_btn].count("Button(") != 1:
        fail("Liste teilen must come immediately after Backup teilen")
    if "Einkaufsliste speichern" not in content:
        fail("overflow menu missing Einkaufsliste speichern")
    if 'Button("Liste speichern"' in content or '.alert("Liste speichern"' in content:
        fail("overflow menu still uses Liste speichern")
    if '.alert("Einkaufsliste speichern"' not in content:
        fail("save-list alert title must be Einkaufsliste speichern")
    desc = (ROOT / "Description.md").read_text()
    if "Build 51" not in desc or "CURRENT_PROJECT_VERSION" not in desc:
        fail("Description.md must name Build 51 / CURRENT_PROJECT_VERSION")
    if "einkauf.watch.hideCompleted" not in desc or "einkauf.iphone.hideCompleted" not in desc:
        fail("Description.md must document separate Watch and iPhone hide-completed AppStorage keys")
    list_share_sec = desc[desc.find("Liste teilen:"):desc.find("Einkaufsliste speichern:")]
    if "einkauf.iphone.hideCompleted" not in list_share_sec or "visibleGroups" not in list_share_sec:
        fail("Description.md Liste teilen must document the eye filter via visibleGroups")
    if "n/0/n" not in list_share_sec:
        fail("Description.md Liste teilen must document n/0/n when only open items print")
    if "Erledigte ausgeblendet" not in desc:
        fail("Description.md must document Erledigte ausgeblendet empty line")
    if "eye.slash" not in desc:
        fail("Description.md must document the Watch eye.slash glyph")
    if re.search(r"Auge \*\*eine Zeile unter dem Titel\*\*", desc):
        fail("Description.md still places the Watch eye under the navigation title")
    watch_sec = desc[desc.find("## Watch"):desc.find("### Watch-Complication")]
    if "links" not in watch_sec:
        fail("Description.md must left-align the Watch eye")
    if "Text(store.state.watchTitle)" not in watch_sec:
        fail("Description.md must place watchTitle as Text below the eye bar")
    if "über der Titelzeile" not in watch_sec and "zuerst über" not in watch_sec:
        fail("Description.md must place the Watch eye above the title line")
    if "navigationTitle(watchTitle)" not in watch_sec and ".navigationTitle(watchTitle)" not in watch_sec:
        fail("Description.md must forbid navigationTitle(watchTitle)")
    if "toolbar(.hidden" not in watch_sec:
        fail("Description.md must hide the Watch navigation bar with toolbar(.hidden)")
    if "Systemuhr" not in watch_sec:
        fail("Description.md must keep the system clock visible under a hidden nav bar")
    if "Navigation-Titel leer" in watch_sec:
        fail("Description.md still says empty navigation title instead of hiding the bar")
    if "theme.good" not in watch_sec:
        fail("Description.md must document Watch eye as theme.good when completed are visible")
    if "theme.muted" not in watch_sec and "grau" not in watch_sec.lower():
        fail("Description.md must document Watch eye.slash as muted grey when completed are hidden")
    if "Tinte/Akzent" in watch_sec:
        fail("Description.md still documents Watch eye as Tinte/Akzent")
    if "immer dieselbe Farbe" in watch_sec or "immer grau" in watch_sec:
        fail("Description.md still says both Watch eye states share one colour")
    if re.search(r"Auge.{0,80}rechts", watch_sec) or "rechts (`HStack" in watch_sec:
        fail("Description.md still right-aligns the Watch eye")
    if re.search(r"Toolbar \*\*links\*\*", desc):
        fail("Description.md still places the Watch eye in the leading toolbar")
    if not re.search(r"nicht.{0,80}topBarLeading|topBarLeading.{0,80}nicht", desc, re.S):
        fail("Description.md must say the Watch eye is not in topBarLeading")
    if not re.search(r"18\s*[–-]\s*20", desc):
        fail("Description.md must specify a compact ~18–20pt Watch eye bar")
    if re.search(r"mindestens.{0,20}44", desc):
        fail("Description.md must not require a 44pt Watch eye tap target")
    if "minHeight: 44" not in desc:
        fail("Description.md must forbid .frame(minHeight: 44) on the Watch eye")
    if ".buttonStyle(.plain)" not in desc:
        fail("Description.md must require Watch Auge .buttonStyle(.plain)")
    if "gefüll" not in desc:
        fail("Description.md must say Watch Auge is not a filled circular button")
    if "Nutzerkorrektur gewinnt" not in desc:
        fail("Description.md guess order must say user correction wins")
    if "Mappings nach Keywords" in desc or "Keywords vor Mappings" in desc:
        fail("Description.md still documents the old guess order (keywords before mappings)")
    if "Artikelnamen (ohne Menge)" not in desc:
        fail("Description.md Wörterbuch footer must mention item-name corrections")
    if "Meine Zuordnungen" not in desc:
        fail("Description.md must document Meine Zuordnungen")
    if "Backup als `mappings`" not in desc and "Backup-Feld `mappings`" not in desc:
        fail("Description.md must say eigene Zuordnungen use backup field mappings")
    if "5. Einkaufsliste speichern" not in desc:
        fail("Description.md overflow menu must list Einkaufsliste speichern")
    if "Alert „Einkaufsliste speichern“" not in desc:
        fail("Description.md must document Einkaufsliste speichern alert title")
    if "Gespeicherte Listen" not in content:
        fail("overflow menu missing Gespeicherte Listen")
    save_btn = content.find('Button("Einkaufsliste speichern"')
    saved_menu = content.find('Menu("Gespeicherte Listen"')
    if save_btn < 0 or save_btn < list_btn:
        fail("Einkaufsliste speichern must come after Liste teilen")
    if saved_menu < 0 or saved_menu < save_btn:
        fail("Gespeicherte Listen must come after Einkaufsliste speichern")
    saved_foreach = content.find("ForEach(store.savedLists)")
    if saved_foreach < 0 or saved_foreach < saved_menu:
        fail("saved list names must sit in the Gespeicherte Listen submenu, not as top-level overflow actions")
    if "sheet(item:" not in content:
        fail("Backup teilen must use sheet(item:) with a file URL")
    if "showShare" in content or "if let shareURL" in content:
        fail("Backup teilen still uses isPresented + optional URL")
    if "shareList" not in content or "ListPDF.render" not in content:
        fail("Liste teilen must render a PDF via ListPDF")
    share_m = re.search(r"private func shareList\(\)\s*\{", content)
    if not share_m:
        fail("missing shareList")
    share_fn = extract_braced(content, share_m.start(), "shareList")
    if "visibleGroups" not in share_fn or "hidingCompleted" not in share_fn:
        fail("Liste teilen must build PDF groups via visibleGroups(hidingCompleted:)")
    if "store.state.progressLabel" in share_fn:
        fail("Liste teilen must recompute progressLabel from printed groups, not the full list")
    if "ListGrouping.progressLabel" not in share_fn:
        fail("Liste teilen must pass progressLabel for the printed groups")
    if "hideCompleted" not in share_fn:
        fail("Liste teilen must follow the iPhone eye hideCompleted flag")
    if "list.bullet.rectangle" not in content:
        fail("Liste teilen should use a distinct SF Symbol")
    if "Text(\"Hell\")" in content or "Text(\"Creme\")" in content:
        fail("theme/palette controls must not be in the list toolbar (ContentView)")
    settings = (ROOT / "Sources/iOS/SettingsSheet.swift").read_text()
    for needle in ("Hell", "Dunkel", "System", "Creme", "Blau", "Darstellung"):
        if needle not in settings:
            fail(f"Einstellungen missing {needle}")
    if "iPhone-Einstellung" not in settings:
        fail("Darstellung hint should mention iPhone-Einstellung for System")
    if "Aktueller Laden" not in settings:
        fail("Einstellungen missing Aktueller Laden")
    if re.search(r'Picker\(\s*"Aktueller Laden"', settings):
        fail("Aktueller Laden must not be a Picker")
    if "store.setStore(s.id)" not in settings:
        fail("Einstellungen store list must call store.setStore(s.id)")
    if "ForEach(store.stores)" not in settings:
        fail("Einstellungen must list all stores")
    if 'Image(systemName: "checkmark")' not in settings:
        fail("Einstellungen current store must show a checkmark")
    if "Neuer Laden" not in settings or "Name des Ladens" not in settings:
        fail("Einstellungen missing Neuer Laden")
    if "Übernimmt das Layout des ausgewählten Ladens." not in settings:
        fail("Neuer Laden footer must mention selected store layout")
    if "Übernimmt das aktuelle Layout." in settings:
        fail("old Neuer Laden footer still present")
    if "Ladenweg ·" not in settings:
        fail("Ladenweg header should name the store")
    if ".onMove" not in settings:
        fail("Ladenweg should support onMove drag")
    if "Laden löschen" not in settings:
        fail("Einstellungen missing Laden löschen confirmation")
    if "pendingDeleteStoreId" not in settings:
        fail("Aktueller Laden swipe delete must track pendingDeleteStoreId")
    if "wirklich löschen?" not in settings:
        fail("store delete must use the confirmationDialog")
    if 'if !store.state.currentStore.builtin' in settings:
        fail("standalone Laden löschen section must be removed; swipe on the list instead")
    section_order = [
        "Darstellung",
        "Aktueller Laden",
        "Neuer Laden",
        "Ladenweg ·",
        "Abteilungen hinzufügen",
        "Layout zurücksetzen",
        "Stamm-Artikel",
        "Gespeicherte Listen",
        "Wörterbuch",
    ]
    section_pos = [settings.find(label) for label in section_order]
    if any(p < 0 for p in section_pos) or section_pos != sorted(section_pos):
        fail("Einstellungen section order must be Darstellung, Aktueller Laden, Neuer Laden, Ladenweg, Stamm-Artikel, Gespeicherte Listen, Wörterbuch")
    neuer_idx = settings.find("Neuer Laden")
    ladenweg_idx = settings.find("Ladenweg ·")
    store_list_start = settings.find("ForEach(store.stores)")
    if store_list_start < 0 or store_list_start > neuer_idx:
        fail("Aktueller Laden ForEach must sit before Neuer Laden")
    store_list = settings[store_list_start:neuer_idx]
    if ".onDelete" not in store_list:
        fail("Aktueller Laden must support onDelete swipe for custom stores")
    if "deleteDisabled" not in store_list or "builtin" not in store_list:
        fail("builtin stores must not be swipe-deletable (deleteDisabled)")
    zwischen = settings[neuer_idx:ladenweg_idx]
    if 'Button("Laden löschen"' in zwischen:
        fail("no standalone Laden löschen button; swipe on the list instead")
    footer_idx = settings.find("Übernimmt das Layout des ausgewählten Ladens.")
    if footer_idx < 0 or not (neuer_idx < footer_idx < ladenweg_idx):
        fail("Neuer Laden footer must sit with Neuer Laden, before Ladenweg")
    if "pendingDeleteSavedListId" not in settings:
        fail("Gespeicherte Listen swipe delete must confirm via pendingDeleteSavedListId")
    if "removeSavedList" not in settings:
        fail("Einstellungen must delete saved lists via removeSavedList")
    if "applySavedList" not in settings:
        fail("Einstellungen saved list rows must applySavedList")
    if "Wörterbuch" not in settings:
        fail("Einstellungen missing Wörterbuch")
    if "KeywordDictionaryView" not in settings:
        fail("Einstellungen Wörterbuch row must open KeywordDictionaryView")
    if "NavigationLink" not in settings:
        fail("Wörterbuch must be a NavigationLink in Einstellungen, not the overflow menu")
    if "Wörterbuch" in content:
        fail("Wörterbuch must not be in the overflow menu")
    dict_view = (ROOT / "Sources/iOS/KeywordDictionaryView.swift").read_text()
    if "KeywordDictionary.source" not in dict_view:
        fail("Wörterbuch view must read KeywordDictionary.source")
    if re.search(r"URLSession|https?://|github\.io", dict_view):
        fail("Wörterbuch must not fetch the web")
    if "Artikelnamen (ohne Menge)" not in dict_view or "Wörterbuch selbst ändert sich nicht" not in dict_view:
        fail("Wörterbuch footer must say corrections stick to the item name and the dictionary does not change")
    if "@EnvironmentObject" not in dict_view or "ShoppingStore" not in dict_view:
        fail("KeywordDictionaryView needs ShoppingStore EnvironmentObject")
    if "Meine Zuordnungen" not in dict_view:
        fail("Wörterbuch must show Meine Zuordnungen")
    empty_copy = "Noch keine eigenen Zuordnungen. Abteilung im Bearbeiten-Modus ändern — dann erscheint der Name hier."
    if empty_copy not in dict_view:
        fail("Wörterbuch empty mappings copy missing")
    if "setMapping" not in dict_view or "removeMapping" not in dict_view:
        fail("Wörterbuch must edit/delete via setMapping/removeMapping")
    if ".onDelete" not in dict_view:
        fail("Meine Zuordnungen must swipe-delete")
    if "Picker" not in dict_view or "Department.allCases" not in dict_view:
        fail("Meine Zuordnungen rows need a Department Picker")
    if "learnedMappings" not in dict_view or "matching: query" not in dict_view:
        fail("search query must filter Meine Zuordnungen")
    if "groups(from: KeywordDictionary.source, matching: query)" not in dict_view:
        fail("search query must still filter canned Wörterbuch groups")
    meine_idx = dict_view.find("Meine Zuordnungen")
    canned_idx = dict_view.find("ForEach(groups)")
    if meine_idx < 0 or canned_idx < 0 or meine_idx > canned_idx:
        fail("Meine Zuordnungen must sit above canned KeywordDictionary groups")
    if "Wortliste ist fest" not in dict_view or "Backup als mappings" not in dict_view:
        fail("Wörterbuch footer must say canned list is fixed and eigene Zuordnungen live in backup mappings")
    if "learnedMappings" in dict_view and re.search(r'"(learnedMappings|userMappings|meineZuordnungen)"', dict_view):
        fail("Wörterbuch must not invent a second backup field name")
    browse = (ROOT / "Sources/Shared/KeywordDictionaryBrowse.swift").read_text()
    if "Department.title" not in browse:
        fail("Wörterbuch groups must use Department.title")
    if "Locale(identifier: \"de\")" not in browse:
        fail("Wörterbuch words must sort with de locale")
    if "func learnedMappings" not in browse:
        fail("KeywordDictionary.learnedMappings missing")
    kd = (ROOT / "Sources/Shared/KeywordDictionary.swift").read_text()
    if "static let source" not in kd:
        fail("KeywordDictionary.source missing")
    if "Do not scrape" not in kd:
        fail("KeywordDictionary must stay local (no website scrape)")
    guesser = (ROOT / "Sources/Shared/DepartmentGuesser.swift").read_text()
    guess_idx = guesser.find("static func guess")
    if guess_idx < 0:
        fail("DepartmentGuesser.guess missing")
    guess_body = guesser[guess_idx:]
    end = guess_body.find("private static func matchesTK")
    if end > 0:
        guess_body = guess_body[:end]
    map_pos = guess_body.find("mappings[mk]")
    rule_pos = guess_body.find("tiefkuhl")
    kw_pos = guess_body.find("for kw in keywords")
    if map_pos < 0:
        fail("guess must consult mappings[mk]")
    if rule_pos < 0 or map_pos > rule_pos:
        fail("user mapping must win before special rules")
    if kw_pos < 0 or map_pos > kw_pos:
        fail("user mapping must win before keywords")
    if re.search(r"KeywordDictionary\.source\s*=", guesser):
        fail("DepartmentGuesser must not rewrite KeywordDictionary.source")
    store_src = (ROOT / "Sources/Shared/ShoppingStore.swift").read_text()
    if "func createStore" not in store_src or "func deleteStore" not in store_src:
        fail("ShoppingStore missing createStore/deleteStore")
    if "StoreCatalog.delete" not in store_src:
        fail("ShoppingStore.deleteStore must use StoreCatalog.delete")
    setstore = re.search(r"func setStore\(_ id: String\) \{.*?\n    \}", store_src, re.S)
    if not setstore:
        fail("ShoppingStore missing setStore")
    body = setstore.group(0)
    if "var next = state" not in body or "next.currentStoreId" not in body or "state = next" not in body:
        fail("setStore must copy AppState, set currentStoreId, assign state = next")
    if "listRevision += 1" not in body:
        fail("setStore must bump listRevision before persistAndSync")
    if body.find("state = next") > body.find("persistAndSync"):
        fail("setStore must assign state (and bump revision) before persistAndSync")
    setmap_idx = store_src.find("func setMapping")
    if setmap_idx < 0:
        fail("ShoppingStore missing setMapping")
    setmap = extract_braced(store_src, setmap_idx, "setMapping")
    if "mappingKey" not in setmap:
        fail("setMapping must write DepartmentGuesser.mappingKey")
    if "Department.isKnown" not in setmap:
        fail("setMapping must reject unknown depts")
    if "persistAndSync" not in setmap:
        fail("setMapping must persistAndSync like other state changes")
    if "listRevision" not in setmap:
        fail("setMapping must bump listRevision")
    rmmap_idx = store_src.find("func removeMapping")
    if rmmap_idx < 0:
        fail("ShoppingStore missing removeMapping")
    rmmap = extract_braced(store_src, rmmap_idx, "removeMapping")
    if "removeValue" not in rmmap:
        fail("removeMapping must drop the key from mappings")
    if "persistAndSync" not in rmmap:
        fail("removeMapping must persistAndSync like other state changes")
    if "listRevision" not in rmmap:
        fail("removeMapping must bump listRevision")
    watch = (ROOT / "Sources/Watch/WatchListView.swift").read_text()
    if "Picker" in watch:
        fail("Watch should not have a store picker")
    if "deleteStore" in watch:
        fail("Watch must not delete stores")
    watch_list_id = '.id("\\(store.state.currentStoreId)|\\(store.state.currentStore.layout.joined())")'
    if watch_list_id not in watch:
        fail("Watch list must .id(currentStoreId|layout) so store switch rebuilds")
    if "Section {" in watch:
        fail("Watch list must not use List+Section")
    if "ForEach(store.groups)" in watch:
        fail("Watch must not ForEach groups as List sections")
    if "walkListRows(hidingCompleted" not in watch:
        fail("Watch list must use walkListRows(hidingCompleted:) so done items can be filtered")
    if "ForEach(visibleWalkRows)" not in watch and "ForEach(store.walkListRows" not in watch:
        fail("Watch list must ForEach walk list rows (flat store+position ids)")
    if "navigationTitle(store.state.watchTitle)" in watch:
        fail("Watch must not put watchTitle in navigationTitle (that places it above the eye)")
    if "Text(store.state.watchTitle)" not in watch:
        fail("Watch must show watchTitle as Text below the eye bar")
    if "toolbar(.hidden, for: .navigationBar)" not in watch:
        fail("Watch must hide the navigation bar (.toolbar(.hidden, for: .navigationBar))")
    if "AppStorage" not in watch or "einkauf.watch.hideCompleted" not in watch:
        fail("Watch hide-completed must persist via AppStorage einkauf.watch.hideCompleted")
    if "einkauf.iphone.hideCompleted" in watch:
        fail("Watch must not reuse the iPhone AppStorage key")
    if "topBarLeading" in watch:
        fail("Watch hide toggle must not sit in topBarLeading (clips the navigation title)")
    if "ToolbarItem" in watch:
        fail("Watch must not put the eye in a ToolbarItem")
    if '"eye"' not in watch or "eye.slash" not in watch:
        fail("Watch hide toggle must use eye / eye.slash")
    eye_bar = extract_watch_eye_bar(watch)
    if ".buttonStyle(.plain)" not in eye_bar:
        fail("Watch eye Button must use .buttonStyle(.plain) (watchOS otherwise draws a huge filled circle)")
    if LARGE_PROGRESS_FONT.search(eye_bar):
        fail("Watch eye Image must not use a large font (.title/.headline) — keep caption / ~14–16pt")
    for size in (int(n) for n in re.findall(r"\.system\(size:\s*(\d+)", eye_bar)):
        if size > 16:
            fail(f"Watch eye system size {size}pt is too large (use caption or ~14–16pt)")
    if "hideCompleted.toggle" not in eye_bar:
        fail("Watch eye Button must still toggle hideCompleted")
    if "theme.ink" in eye_bar:
        fail("Watch eye must not use theme.ink")
    if "theme.good" not in eye_bar:
        fail("Watch eye (visible completed) must use theme.good like done checkmarks")
    if "theme.muted" not in eye_bar:
        fail("Watch eye.slash (hidden completed) must use theme.muted")
    if not re.search(
        r"hideCompleted\s*\?\s*theme\.muted\s*:\s*theme\.good", eye_bar
    ):
        fail("Watch eye colour must be muted when hidden, good when visible")
    if "Spacer()" not in eye_bar:
        fail("Watch eye must be leading via Spacer() after the Button above the title")
    if eye_bar.find("Spacer()") < eye_bar.find("Button"):
        fail("Watch eye HStack must be { Button…; Spacer() }, not trailing")
    if re.search(r"minHeight:\s*44", eye_bar) or re.search(r"minWidth:\s*44", eye_bar):
        fail("Watch eye must not use a 44pt min frame (creates empty bands under the title)")
    hide_bar = extract_some_view(watch, "hideCompletedBar")
    if re.search(r"minHeight:\s*44", hide_bar) or re.search(r"minWidth:\s*44", hide_bar):
        fail("Watch hideCompletedBar must not use a 44pt min frame")
    if not re.search(r"frame\(height:\s*(1[89]|20)\)", hide_bar) and not re.search(
        r"maxHeight:\s*(1[89]|20)", hide_bar
    ):
        fail("Watch hideCompletedBar must be a compact ~18–20pt row")
    if "VStack(spacing: 0)" not in watch:
        fail("Watch must use VStack(spacing: 0) so eye, title, and list stack tightly")
    if ".contentMargins(.top, 0" not in watch:
        fail("Watch List must zero top contentMargins so the first item sits under the eye")
    if re.search(r"\.padding\(\)", watch):
        fail("Watch empty states must not use all-around .padding() (adds a gap under the eye)")
    body_m = re.search(r"var body:\s*some View", watch)
    list_m = re.search(r"List \{", watch)
    if not body_m or not list_m:
        fail("Watch body must keep a List")
    body_to_list = watch[body_m.start():list_m.start()]
    if "hideCompletedBar" not in body_to_list and "hideCompleted.toggle" not in body_to_list:
        fail("Watch eye chrome must sit above the List / empty states")
    eye_pos = body_to_list.find("hideCompletedBar")
    if eye_pos < 0:
        eye_pos = body_to_list.find("hideCompleted.toggle")
    title_pos = body_to_list.find("Text(store.state.watchTitle)")
    if title_pos < 0:
        fail("Watch title Text must sit in the body below the eye bar (before the List)")
    if eye_pos >= 0 and title_pos < eye_pos:
        fail("Watch title Text must sit below the eye bar")
    if "Erledigte ausblenden" not in watch or "Erledigte einblenden" not in watch:
        fail("Watch hide toggle missing accessibility labels")
    if "Erledigte ausgeblendet." not in watch:
        fail("Watch must show Erledigte ausgeblendet. when every item is hidden")
    if "fileExporter" in watch or "fileImporter" in watch:
        fail("Watch must not import/export backups")
    if "hideCompleted" in (ROOT / "Sources/Shared/BackupCodec.swift").read_text():
        fail("hideCompleted must not enter BackupCodec / einkauf-backup")
    models = (ROOT / "Sources/Shared/Models.swift").read_text()
    layout = (ROOT / "Sources/Shared/StoreLayout.swift").read_text()
    if "Int(Date().timeIntervalSince1970 * 1000)" in models or "Int(Date().timeIntervalSince1970 * 1000)" in layout:
        fail("makeID must not cast epoch millis to Int (watchOS arm64_32 overflows)")
    if models.count("Int64(Date().timeIntervalSince1970 * 1000)") < 2:
        fail("Item/SavedList.makeID must use Int64 for epoch millis")
    if "Int64(Date().timeIntervalSince1970 * 1000)" not in layout:
        fail("StoreCatalog.makeID must use Int64 for epoch millis")
    if "hideCompleted" in models:
        fail("hideCompleted must not live in AppState / Models (device-local AppStorage)")
    if "var dept: String" not in models:
        fail("DeptGroup must keep a raw dept field")
    if r"\(storeId)|\(dept)" not in models:
        fail("DeptGroup.id must include storeId and dept")
    if re.search(r"var title: String \{ Department\.title\(for: id\) \}", models):
        fail("DeptGroup.title must use dept, not id")
    if ".header(group.id)" in editing:
        fail("ItemEditing must not treat group.id as a dept")
    if ".header(storeId: group.storeId, dept: group.dept)" not in editing:
        fail("ItemEditing headers must use group.storeId and group.dept")
    if r"\(storeId)|h:\(dept)" not in editing:
        fail("edit row header id must include storeId")
    if r"\(storeId)|i:\(item.id)" not in editing:
        fail("edit row item id must include storeId")
    if re.search(r"var groups: \[DeptGroup\] \{", store_src):
        fail("groups must not be a computed property")
    if "@Published private(set) var groups: [DeptGroup]" not in store_src:
        fail("groups must be @Published stored")
    if "func rebuildDerived" not in store_src:
        fail("ShoppingStore missing rebuildDerived")
    if "groups = state.grouped()" not in store_src:
        fail("rebuildDerived must use state.grouped() (currentStore layout)")
    tests = (ROOT / "Tests/EinkaufCoreTests/EinkaufCoreTests.swift").read_text()
    if "ShoppingStore(state: seed, enableSync: false)" not in tests:
        fail("tests must construct ShoppingStore(enableSync: false)")
    if "store.deleteStore" not in tests:
        fail("tests must delete custom stores via ShoppingStore.deleteStore")
    if "testDeleteBuiltinIsNoOp" not in tests:
        fail("tests must assert builtin store delete is a no-op")
    if "testCannotDeleteBuiltin" not in tests:
        fail("tests must assert StoreCatalog.delete refuses builtins")
    if "testDeleteCustomFallsBackToEdeka" not in tests:
        fail("tests must assert StoreCatalog.delete custom falls back to edeka")
    if 'setStore("dm")' not in tests or 'setStore("edeka")' not in tests:
        fail("tests must setStore dm then edeka")
    if r"groups.map(\.dept)" not in tests:
        fail(r"tests must assert groups.map(\.dept) after setStore")
    if "func walkLines" not in models:
        fail("ListGrouping missing walkLines helper")
    if "func openItemNames" not in models:
        fail("ListGrouping missing openItemNames for the iPhone widget")
    if "struct HomeWidgetSnapshot" not in models:
        fail("Models missing HomeWidgetSnapshot")
    if "enum WalkLine" not in models:
        fail("Models missing WalkLine")
    if "walkListRows" not in models:
        fail("ListGrouping missing walkListRows (store + position ids)")
    if "hidingCompleted" not in models:
        fail("ListGrouping.walkListRows must accept hidingCompleted")
    if "func visibleGroups" not in models:
        fail("ListGrouping missing visibleGroups for Geh-Modus and Liste teilen")
    if "func progressLabel(groups:" not in models:
        fail("ListGrouping missing progressLabel(groups:) for printed PDF rows")
    if "ForEach(store.editRows)" not in content:
        fail("iPhone Bearbeiten must still ForEach the full editRows")
    if "einkauf.iphone.hideCompleted" not in content:
        fail("iPhone Geh-Modus must persist hideCompleted separately from Watch")
    if "testUserMappingBeatsKeyword" not in tests or "testUserMappingBeatsSpecialRules" not in tests:
        fail("tests must cover user mapping beating keywords and special rules")
    if "testLearnedMappingsSearch" not in tests:
        fail("tests must cover Meine Zuordnungen search filter")
    if "testSetMappingWritesMappingKey" not in tests:
        fail("tests must cover setMapping writing mappingKey")
    if "testRemoveMappingDropsKey" not in tests:
        fail("tests must cover removeMapping")
    if "testExportKeepsMappingsField" not in tests or "testFixtureKeepsMappingsAndExportUsesSameField" not in tests:
        fail("tests must cover backup still containing mappings (not a second field)")
    if "testWalkListRowsHidingCompletedDropsDoneItemsAndEmptyHeaders" not in tests:
        fail("tests must cover walkListRows hidingCompleted dropping done items and empty headers")
    if "testWalkListRowsHidingCompletedEmptyWhenAllDone" not in tests:
        fail("tests must cover walkListRows hidingCompleted empty when all done")
    if "testVisibleGroupsHidingCompletedDropsDoneItemsAndEmptyDepartments" not in tests:
        fail("tests must cover visibleGroups dropping done items and empty departments")
    if "testVisibleGroupsHidingCompletedEmptyWhenAllDone" not in tests:
        fail("tests must cover visibleGroups empty when all done")
    if 'progressLabel(groups: hidden), "2/0/2"' not in tests:
        fail("tests must cover PDF progress n/0/n for open-only groups")
    if "testWalkLinesEdekaSuessThenDrogerieDmReversed" not in tests:
        fail("tests must cover walkLines header order edeka suess then drogerie vs dm reversed")
    if 'headerDept), ["suess", "drogerie"' not in tests and '["suess", "drogerie", "sonstiges"]' not in tests:
        fail("walkLines test must assert edeka header suess then drogerie")
    if '["drogerie", "sonstiges", "suess"]' not in tests:
        fail("walkLines leftover aisles stay extra headers after sonstiges layout slot")
    if "testSonstigesFollowsStoreLayoutPosition" not in tests:
        fail("tests must cover sonstiges following store layout position")
    if '["vor", "sonstiges", "obst", "nach"]' not in tests or '["vor", "obst", "sonstiges", "nach"]' not in tests:
        fail("tests must use layouts with sonstiges before vs after obst")
    if 'layout.removeAll { $0 == "vor" || $0 == "nach" || $0 == "sonstiges" }' in models:
        fail("ListGrouping.groups must not strip sonstiges from the layout")
    if "StoreLayout.sanitized(store.layout)" not in models:
        fail("ListGrouping.groups must walk StoreLayout.sanitized")
    if "shown = aisles.contains" in models or 'shown = aisles.contains(home) ? home : "sonstiges"' in models:
        fail("groups must not remap leftover depts into sonstiges")
    if "CURRENT_PROJECT_VERSION = 51" not in pbx:
        fail("CURRENT_PROJECT_VERSION must be 51")
    if "CURRENT_PROJECT_VERSION = 50" in pbx:
        fail("stale CURRENT_PROJECT_VERSION 50 still in pbxproj")
    if "CURRENT_PROJECT_VERSION = 49" in pbx:
        fail("stale CURRENT_PROJECT_VERSION 49 still in pbxproj")
    if "CURRENT_PROJECT_VERSION = 48" in pbx:
        fail("stale CURRENT_PROJECT_VERSION 48 still in pbxproj")
    if "CURRENT_PROJECT_VERSION = 47" in pbx:
        fail("stale CURRENT_PROJECT_VERSION 47 still in pbxproj")
    if "CURRENT_PROJECT_VERSION = 46" in pbx:
        fail("stale CURRENT_PROJECT_VERSION 46 still in pbxproj")
    if "CURRENT_PROJECT_VERSION = 45" in pbx:
        fail("stale CURRENT_PROJECT_VERSION 45 still in pbxproj")
    if "CURRENT_PROJECT_VERSION = 44" in pbx:
        fail("stale CURRENT_PROJECT_VERSION 44 still in pbxproj")
    if "CURRENT_PROJECT_VERSION = 43" in pbx:
        fail("stale CURRENT_PROJECT_VERSION 43 still in pbxproj")
    if "CURRENT_PROJECT_VERSION = 42" in pbx:
        fail("stale CURRENT_PROJECT_VERSION 42 still in pbxproj")
    if "CURRENT_PROJECT_VERSION = 41" in pbx:
        fail("stale CURRENT_PROJECT_VERSION 41 still in pbxproj")
    if "CURRENT_PROJECT_VERSION = 40" in pbx:
        fail("stale CURRENT_PROJECT_VERSION 40 still in pbxproj")
    if "CURRENT_PROJECT_VERSION = 39" in pbx:
        fail("stale CURRENT_PROJECT_VERSION 39 still in pbxproj")
    if "CURRENT_PROJECT_VERSION = 38" in pbx:
        fail("stale CURRENT_PROJECT_VERSION 38 still in pbxproj")
    if "CURRENT_PROJECT_VERSION = 37" in pbx:
        fail("stale CURRENT_PROJECT_VERSION 37 still in pbxproj")
    if "CURRENT_PROJECT_VERSION = 36" in pbx:
        fail("stale CURRENT_PROJECT_VERSION 36 still in pbxproj")
    if "CURRENT_PROJECT_VERSION = 35" in pbx:
        fail("stale CURRENT_PROJECT_VERSION 35 still in pbxproj")
    if "CURRENT_PROJECT_VERSION = 34" in pbx:
        fail("stale CURRENT_PROJECT_VERSION 34 still in pbxproj")
    if "CURRENT_PROJECT_VERSION = 33" in pbx:
        fail("stale CURRENT_PROJECT_VERSION 33 still in pbxproj")
    if "CURRENT_PROJECT_VERSION = 32" in pbx:
        fail("stale CURRENT_PROJECT_VERSION 32 still in pbxproj")
    if "CURRENT_PROJECT_VERSION = 31" in pbx:
        fail("stale CURRENT_PROJECT_VERSION 31 still in pbxproj")
    if "CURRENT_PROJECT_VERSION = 30" in pbx:
        fail("stale CURRENT_PROJECT_VERSION 30 still in pbxproj")
    if "CURRENT_PROJECT_VERSION = 29" in pbx:
        fail("stale CURRENT_PROJECT_VERSION 29 still in pbxproj")
    if "CURRENT_PROJECT_VERSION = 28" in pbx:
        fail("stale CURRENT_PROJECT_VERSION 28 still in pbxproj")
    if "CURRENT_PROJECT_VERSION = 27" in pbx:
        fail("stale CURRENT_PROJECT_VERSION 27 still in pbxproj")
    if "CURRENT_PROJECT_VERSION = 26" in pbx:
        fail("stale CURRENT_PROJECT_VERSION 26 still in pbxproj")
    if "CURRENT_PROJECT_VERSION = 25" in pbx:
        fail("stale CURRENT_PROJECT_VERSION 25 still in pbxproj")
    if "CURRENT_PROJECT_VERSION = 24" in pbx:
        fail("stale CURRENT_PROJECT_VERSION 24 still in pbxproj")
    if "CURRENT_PROJECT_VERSION = 23" in pbx:
        fail("stale CURRENT_PROJECT_VERSION 23 still in pbxproj")
    if "CURRENT_PROJECT_VERSION = 22" in pbx:
        fail("stale CURRENT_PROJECT_VERSION 22 still in pbxproj")
    if "CURRENT_PROJECT_VERSION = 21" in pbx:
        fail("stale CURRENT_PROJECT_VERSION 21 still in pbxproj")
    if "CURRENT_PROJECT_VERSION = 20" in pbx:
        fail("stale CURRENT_PROJECT_VERSION 20 still in pbxproj")
    if "CURRENT_PROJECT_VERSION = 19" in pbx:
        fail("stale CURRENT_PROJECT_VERSION 19 still in pbxproj")
    if "CURRENT_PROJECT_VERSION = 18" in pbx:
        fail("stale CURRENT_PROJECT_VERSION 18 still in pbxproj")
    if "CURRENT_PROJECT_VERSION = 17" in pbx:
        fail("stale CURRENT_PROJECT_VERSION 17 still in pbxproj")
    if "CURRENT_PROJECT_VERSION = 16" in pbx:
        fail("stale CURRENT_PROJECT_VERSION 16 still in pbxproj")
    if "CURRENT_PROJECT_VERSION = 15" in pbx:
        fail("stale CURRENT_PROJECT_VERSION 15 still in pbxproj")
    if "CURRENT_PROJECT_VERSION = 14" in pbx:
        fail("stale CURRENT_PROJECT_VERSION 14 still in pbxproj")
    if "CURRENT_PROJECT_VERSION = 13" in pbx:
        fail("stale CURRENT_PROJECT_VERSION 13 still in pbxproj")
    if "CURRENT_PROJECT_VERSION = 12" in pbx:
        fail("stale CURRENT_PROJECT_VERSION 12 still in pbxproj")
    if "CURRENT_PROJECT_VERSION = 11" in pbx:
        fail("stale CURRENT_PROJECT_VERSION 11 still in pbxproj")
    if "CURRENT_PROJECT_VERSION = 10" in pbx:
        fail("stale CURRENT_PROJECT_VERSION 10 still in pbxproj")
    if "CURRENT_PROJECT_VERSION = 9" in pbx:
        fail("stale CURRENT_PROJECT_VERSION 9 still in pbxproj")
    if "CURRENT_PROJECT_VERSION = 8" in pbx:
        fail("stale CURRENT_PROJECT_VERSION 8 still in pbxproj")
    yml = (ROOT / "project.yml").read_text()
    if "CURRENT_PROJECT_VERSION: 51" not in yml:
        fail("project.yml CURRENT_PROJECT_VERSION must be 51")
    if "CURRENT_PROJECT_VERSION: 50" in yml:
        fail("stale CURRENT_PROJECT_VERSION 50 still in project.yml")
    if "CURRENT_PROJECT_VERSION: 49" in yml:
        fail("stale CURRENT_PROJECT_VERSION 49 still in project.yml")
    if "CURRENT_PROJECT_VERSION: 48" in yml:
        fail("stale CURRENT_PROJECT_VERSION 48 still in project.yml")
    if "CURRENT_PROJECT_VERSION: 47" in yml:
        fail("stale CURRENT_PROJECT_VERSION 47 still in project.yml")
    if "CURRENT_PROJECT_VERSION: 46" in yml:
        fail("stale CURRENT_PROJECT_VERSION 46 still in project.yml")
    if "CURRENT_PROJECT_VERSION: 45" in yml:
        fail("stale CURRENT_PROJECT_VERSION 45 still in project.yml")
    if "CURRENT_PROJECT_VERSION: 44" in yml:
        fail("stale CURRENT_PROJECT_VERSION 44 still in project.yml")
    if "CURRENT_PROJECT_VERSION: 43" in yml:
        fail("stale CURRENT_PROJECT_VERSION 43 still in project.yml")
    if "CURRENT_PROJECT_VERSION: 42" in yml:
        fail("stale CURRENT_PROJECT_VERSION 42 still in project.yml")
    if "CURRENT_PROJECT_VERSION: 41" in yml:
        fail("stale CURRENT_PROJECT_VERSION 41 still in project.yml")
    if "CURRENT_PROJECT_VERSION: 40" in yml:
        fail("stale CURRENT_PROJECT_VERSION 40 still in project.yml")
    if "CURRENT_PROJECT_VERSION: 39" in yml:
        fail("stale CURRENT_PROJECT_VERSION 39 still in project.yml")
    if "CURRENT_PROJECT_VERSION: 38" in yml:
        fail("stale CURRENT_PROJECT_VERSION 38 still in project.yml")
    if "CURRENT_PROJECT_VERSION: 37" in yml:
        fail("stale CURRENT_PROJECT_VERSION 37 still in project.yml")
    if "CURRENT_PROJECT_VERSION: 36" in yml:
        fail("stale CURRENT_PROJECT_VERSION 36 still in project.yml")
    if "CURRENT_PROJECT_VERSION: 35" in yml:
        fail("stale CURRENT_PROJECT_VERSION 35 still in project.yml")
    if "CURRENT_PROJECT_VERSION: 34" in yml:
        fail("stale CURRENT_PROJECT_VERSION 34 still in project.yml")
    if "CURRENT_PROJECT_VERSION: 33" in yml:
        fail("stale CURRENT_PROJECT_VERSION 33 still in project.yml")
    if "CURRENT_PROJECT_VERSION: 32" in yml:
        fail("stale CURRENT_PROJECT_VERSION 32 still in project.yml")
    if "CURRENT_PROJECT_VERSION: 31" in yml:
        fail("stale CURRENT_PROJECT_VERSION 31 still in project.yml")
    if "CURRENT_PROJECT_VERSION: 30" in yml:
        fail("stale CURRENT_PROJECT_VERSION 30 still in project.yml")
    if "CURRENT_PROJECT_VERSION: 29" in yml:
        fail("stale CURRENT_PROJECT_VERSION 29 still in project.yml")
    if "CURRENT_PROJECT_VERSION: 28" in yml:
        fail("stale CURRENT_PROJECT_VERSION 28 still in project.yml")
    if "CURRENT_PROJECT_VERSION: 27" in yml:
        fail("stale CURRENT_PROJECT_VERSION 27 still in project.yml")
    if "CURRENT_PROJECT_VERSION: 26" in yml:
        fail("stale CURRENT_PROJECT_VERSION 26 still in project.yml")
    if "CURRENT_PROJECT_VERSION: 25" in yml:
        fail("stale CURRENT_PROJECT_VERSION 25 still in project.yml")
    if "CURRENT_PROJECT_VERSION: 24" in yml:
        fail("stale CURRENT_PROJECT_VERSION 24 still in project.yml")
    if "CURRENT_PROJECT_VERSION: 23" in yml:
        fail("stale CURRENT_PROJECT_VERSION 23 still in project.yml")
    if "CURRENT_PROJECT_VERSION: 22" in yml:
        fail("stale CURRENT_PROJECT_VERSION 22 still in project.yml")
    if "CURRENT_PROJECT_VERSION: 21" in yml:
        fail("stale CURRENT_PROJECT_VERSION 21 still in project.yml")
    if "CURRENT_PROJECT_VERSION: 20" in yml:
        fail("stale CURRENT_PROJECT_VERSION 20 still in project.yml")
    if "CURRENT_PROJECT_VERSION: 19" in yml:
        fail("stale CURRENT_PROJECT_VERSION 19 still in project.yml")
    if "CURRENT_PROJECT_VERSION: 18" in yml:
        fail("stale CURRENT_PROJECT_VERSION 18 still in project.yml")
    if "CURRENT_PROJECT_VERSION: 17" in yml:
        fail("stale CURRENT_PROJECT_VERSION 17 still in project.yml")
    if "CURRENT_PROJECT_VERSION: 16" in yml:
        fail("stale CURRENT_PROJECT_VERSION 16 still in project.yml")
    if "CURRENT_PROJECT_VERSION: 15" in yml:
        fail("stale CURRENT_PROJECT_VERSION 15 still in project.yml")
    if "CURRENT_PROJECT_VERSION: 14" in yml:
        fail("stale CURRENT_PROJECT_VERSION 14 still in project.yml")
    if "CURRENT_PROJECT_VERSION: 13" in yml:
        fail("stale CURRENT_PROJECT_VERSION 13 still in project.yml")
    if "CURRENT_PROJECT_VERSION: 12" in yml:
        fail("stale CURRENT_PROJECT_VERSION 12 still in project.yml")
    if "CURRENT_PROJECT_VERSION: 11" in yml:
        fail("stale CURRENT_PROJECT_VERSION 11 still in project.yml")
    if "CURRENT_PROJECT_VERSION: 10" in yml:
        fail("stale CURRENT_PROJECT_VERSION 10 still in project.yml")
    if "CURRENT_PROJECT_VERSION: 9" in yml:
        fail("stale CURRENT_PROJECT_VERSION 9 still in project.yml")
    if "CURRENT_PROJECT_VERSION: 8" in yml:
        fail("stale CURRENT_PROJECT_VERSION 8 still in project.yml")
    title_has_store = "currentStore.name" in watch or (
        "watchTitle" in watch and "var watchTitle" in models and "currentStore.name" in models
    )
    title_has_progress = "progressLabel" in watch or (
        "watchTitle" in watch and "var watchTitle" in models and "progressLabel" in models
    )
    if not title_has_store:
        fail("Watch title must include currentStore.name")
    if not title_has_progress:
        fail("Watch title must include progressLabel")
    if "watchTitle" in watch and not re.search(r'Einkauf \\\(progressLabel\)', models):
        fail("watchTitle must keep Einkauf plus progressLabel")
    if "topBarTrailing" in watch:
        fail("Watch counter must not use topBarTrailing (clipped under the clock)")
    if "safeAreaInset" in watch:
        fail("Watch must not use a duplicate safeAreaInset header for the counter")
    if re.search(r'Text\("Einkauf"\)', watch):
        fail("Watch must not duplicate Einkauf in a custom header HStack")
    if "toolbar(.hidden, for: .navigationBar)" not in watch:
        fail("Watch must hide the navigation bar so the eye sits under the clock")
    if "var openCount" not in models or "var doneCount" not in models or "var progressLabel" not in models:
        fail("AppState missing openCount/doneCount/progressLabel")
    if r'"\(openCount)/\(doneCount)/\(items.count)"' not in models:
        fail("progressLabel must be openCount/doneCount/items.count")
    if "preferredColorScheme" not in (ROOT / "Sources/iOS/EinkaufApp.swift").read_text():
        fail("preferredColorScheme not applied from setting")
    theme = (ROOT / "Sources/Shared/Theme.swift").read_text()
    for token in ("0xF3EEE4", "0x1C1814", "0x9C3424", "0xD2C8B8", "0x14110E", "0xE07060", "0xF0F4FF", "0x2060DF"):
        if token not in theme:
            fail(f"theme missing {token}")
    share = (ROOT / "Sources/Shared/BackupShare.swift").read_text()
    if "yyyyMMdd_HHmm" not in share:
        fail("BackupShare missing stamped filename")
    list_share = (ROOT / "Sources/Shared/ListShare.swift").read_text()
    if "yyyyMMdd_HHmm" not in list_share or "-einkauf-" not in list_share or ".pdf" not in list_share:
        fail("ListShare missing stamped PDF filename")
    pdf = (ROOT / "Sources/iOS/ListPDF.swift").read_text()
    if "UIGraphicsPDFRenderer" not in pdf:
        fail("ListPDF must use UIGraphicsPDFRenderer")
    if "Noch nichts auf der Liste." not in pdf:
        fail("ListPDF missing empty-list copy")
    if "checkmark.circle.fill" in pdf:
        fail("ListPDF checkbox must not use checkmark.circle.fill")
    box_fn = re.search(r"func drawCheckbox\([^)]*\) \{.*?\n        \}", pdf, re.S)
    if not box_fn:
        fail("ListPDF missing drawCheckbox")
    box = box_fn.group(0)
    if "setFill" in box or ".fill(" in box or "path.fill" in box:
        fail("ListPDF checkbox must not fill (empty square for pen ticks)")
    if "checkmark" in box.lower() or "systemName" in box:
        fail("ListPDF checkbox must not draw a checkmark or SF Symbol")
    if "done" in box:
        fail("ListPDF checkbox must ignore done (same empty box for every item)")
    if not re.search(r"roundedRect|addRect|\.stroke\(|strokePath", box):
        fail("ListPDF checkbox must stroke an empty square/rect")
    if "stroke" not in box:
        fail("ListPDF checkbox must be stroke-only")
    if "ovalIn" in box or "circle" in box:
        fail("ListPDF checkbox must be a square/rect, not a circle")
    watch = (ROOT / "Sources/Watch/WatchListView.swift").read_text()
    if "Picker" in watch or "onMove" in watch:
        fail("Watch UI should stay Geh-Modus only")
    for wdir in (ROOT / "Sources/Watch", ROOT / "Sources/WatchWidgets"):
        for wfile in wdir.glob("*.swift"):
            wtxt = wfile.read_text()
            if "Backup teilen" in wtxt or "Liste teilen" in wtxt or "UIActivityViewController" in wtxt or "ShareSheet" in wtxt or "ListPDF" in wtxt:
                fail("Watch should not have share UI")
            if "Liste speichern" in wtxt or "Einkaufsliste speichern" in wtxt or "Gespeicherte Listen" in wtxt:
                fail("Watch should not have saved list UI")
            if "Wörterbuch" in wtxt or "KeywordDictionaryView" in wtxt:
                fail("Watch should not have Wörterbuch UI")
            if "deleteStore" in wtxt:
                fail("Watch must not delete stores")
            if "import ClockKit" in wtxt or "CLKComplication" in wtxt:
                fail("Watch complication must use WidgetKit, not ClockKit")
    print("sources: ok")


def test_backup_codec_python() -> None:
    """Sanity: Export-Shape ohne interne Felder."""
    raw = json.loads((ROOT / "Fixtures/einkauf-backup.json").read_text())
    for key in ("kind", "v", "currentStoreId", "stores", "items", "mappings"):
        if key not in raw:
            fail(f"missing {key}")
    if "learnedMappings" in raw or "userMappings" in raw or "meineZuordnungen" in raw:
        fail("backup must not invent a second mappings field")
    if not isinstance(raw["mappings"], dict):
        fail("backup mappings must be an object")
    for item in raw["items"]:
        for key in ("id", "name", "dept", "done", "added", "ord"):
            if key not in item:
                fail(f"item missing {key}")
    print("backup shape: ok")


def test_watch_complication() -> None:
    pbx = (ROOT / "Einkauf.xcodeproj/project.pbxproj").read_text()
    yml = (ROOT / "project.yml").read_text()
    desc = (ROOT / "Description.md").read_text()
    widget = (ROOT / "Sources/WatchWidgets/EinkaufWatchWidgets.swift").read_text()
    models = (ROOT / "Sources/Shared/Models.swift").read_text()
    persist = (ROOT / "Sources/Shared/Persistence.swift").read_text()
    store = (ROOT / "Sources/Shared/ShoppingStore.swift").read_text()
    reload = (ROOT / "Sources/Watch/WatchComplicationReload.swift").read_text()
    tests = (ROOT / "Tests/EinkaufCoreTests/EinkaufCoreTests.swift").read_text()
    watch_ent = (ROOT / "Sources/Watch/EinkaufWatch.entitlements").read_text()
    widget_ent = (ROOT / "Sources/WatchWidgets/EinkaufWatchWidgets.entitlements").read_text()
    widget_plist = (ROOT / "Sources/WatchWidgets/Info.plist").read_text()

    if "net.tschelle.einkauf.watchkitapp.widgets" not in pbx or "net.tschelle.einkauf.watchkitapp.widgets" not in yml:
        fail("widget bundle id missing")
    if "EinkaufWatchWidgets" not in pbx or "EinkaufWatchWidgets" not in yml:
        fail("widget target missing")
    if "Embed Foundation Extensions" not in pbx:
        fail("widget extension not embedded in Watch app")
    if "com.apple.widgetkit-extension" not in pbx and "com.apple.widgetkit-extension" not in widget_plist:
        fail("NSExtensionPointIdentifier must be WidgetKit")
    if "CLKComplication" in pbx or "ClockKit.framework" in pbx:
        fail("must not add ClockKit")
    if "WidgetKit" not in widget or "StaticConfiguration" not in widget:
        fail("complication must be WidgetKit StaticConfiguration")
    for family in ("accessoryCircular", "accessoryRectangular", "accessoryInline", "accessoryCorner"):
        if family not in widget:
            fail(f"complication missing family {family}")
    if "CLKComplication" in widget or "import ClockKit" in widget:
        fail("widget source must not use ClockKit")
    if "Picker" in widget:
        fail("complication must not have a store picker")
    if "widgetURL" not in widget:
        fail("complication tap must set widgetURL")
    if "compactCountText" not in widget:
        fail("complication must show compactCountText (open count / erledigt)")
    if re.search(r"Text\(entry\.snapshot\.progressLabel\)", widget):
        fail("complication families must not display full progressLabel")
    if "struct ComplicationSnapshot" not in models:
        fail("Models missing ComplicationSnapshot")
    if "static let widgetKind" not in models:
        fail("ComplicationSnapshot missing widgetKind")
    if "func make(from state: AppState)" not in models:
        fail("ComplicationSnapshot must be built from AppState")
    if "clippedWatchStoreName" not in models or "storeName" not in models:
        fail("ComplicationSnapshot must reuse clipped watch store name")
    if "group.net.tschelle.einkauf" not in persist:
        fail("Persistence must use App Group for Watch widget")
    if "NSUbiquitous" in persist or "ubiquityContainer" in persist or "CKContainer" in persist:
        fail("Persistence must not use iCloud")
    if "group.net.tschelle.einkauf" not in watch_ent or "group.net.tschelle.einkauf" not in widget_ent:
        fail("Watch app and widget must share App Group entitlements")
    if "icloud" in watch_ent.lower() or "icloud" in widget_ent.lower():
        fail("entitlements must not add iCloud")
    if "WatchComplicationReload" not in store or "os(watchOS)" not in store:
        fail("ShoppingStore must reload Watch complications after persist")
    if "WidgetCenter" not in reload or "reloadTimelines" not in reload:
        fail("WatchComplicationReload must call WidgetCenter.reloadTimelines")
    if "EinkaufProgress" not in models:
        fail("widget kind EinkaufProgress missing from ComplicationSnapshot")
    if "ComplicationSnapshot.widgetKind" not in widget and "EinkaufProgress" not in widget:
        fail("widget must use ComplicationSnapshot.widgetKind")
    if "os(iOS)" in widget and "Widget" in widget and "TARGETED_DEVICE_FAMILY = 1" in widget:
        fail("complication must not ship as iPhone widget")
    if "watchkitapp.widgets" not in yml:
        fail("project.yml missing widget bundle")
    if "EinkaufWatchWidgets" not in yml:
        fail("project.yml missing widget target")
    if "oo/xx/yy" not in desc or "0/0/0" not in desc:
        fail("Description.md must document progress as oo/xx/yy (empty 0/0/0)")
    if "openCount/doneCount/items.count" not in desc:
        fail("Description.md must document progress as openCount/doneCount/items.count")
    if "var openText" not in models:
        fail("ComplicationSnapshot must expose openText for three-part labels")
    if "var compactCountText" not in models:
        fail("ComplicationSnapshot must expose compactCountText")
    if '"erledigt"' not in models:
        fail("ComplicationSnapshot compactCountText must use erledigt when open is 0")
    if "Watch-Complication" not in desc or "accessoryCircular" not in desc:
        fail("Description.md must document the Watch complication families")
    comp_sec = desc[desc.find("### Watch-Complication"):desc.find("### iPhone-Widget")]
    if "compactCountText" not in comp_sec:
        fail("Description.md complication must name compactCountText")
    if "erledigt" not in comp_sec:
        fail("Description.md complication must document erledigt when open is 0")
    if "19pt" not in comp_sec and "18–20pt" not in comp_sec and "18-20pt" not in comp_sec:
        fail("Description.md must document accessoryCorner count larger than the store widgetLabel")
    if '"erledigt"' not in tests:
        fail("tests must cover complication compactCountText erledigt")
    if "nicht auf dem iPhone" not in desc.lower() and "Nicht auf dem iPhone" not in desc:
        fail("Description.md must say the complication is not on iPhone")
    if "WidgetKit" not in desc or "ClockKit" not in desc:
        fail("Description.md must name WidgetKit and exclude ClockKit")
    if "einkauf-local.json" not in desc:
        fail("Description.md must name einkauf-local.json as complication data source")
    if "title2" not in desc or "!" not in desc:
        fail("Description.md must warn circular must not use title2 (risk of !)")
    if "Gauge" not in desc or "containerBackground" not in desc:
        fail("Description.md must document circular Gauge and containerBackground")
    if '"0/0/0"' not in tests:
        fail("tests must assert empty progress 0/0/0")
    if '"1/2/3"' not in tests:
        fail("tests must assert open/done/total 1/2/3")
    if 'progressLabel, "0/0"' in tests or 'progressLabel, "2/3"' in tests:
        fail("tests still assert two-part progress labels")
    if "testEmptyListIsZeroOverZeroNotHidden" not in tests:
        fail("tests must cover empty complication 0/0/0")
    if "testProgressMatchesWatchTitleAndIncludesVorNach" not in tests:
        fail("tests must cover complication progress including vor/nach")
    if "testGaugeProgressIsZeroWhenEmptyAndFractionOtherwise" not in tests:
        fail("tests must cover Gauge progress 0…1 including empty = 0")
    if "DEVELOPMENT_TEAM = WV26CSTDDR" not in pbx:
        fail("DEVELOPMENT_TEAM must stay WV26CSTDDR")
    if pbx.count("CURRENT_PROJECT_VERSION = 51") < 8:
        fail("all app/extension targets need CURRENT_PROJECT_VERSION 51")
    circular = extract_some_view(widget, "circular")
    rectangular = extract_some_view(widget, "rectangular")
    inline = extract_some_view(widget, "inline")
    corner = extract_some_view(widget, "corner")
    assert_no_large_progress_text(circular, "circular")
    assert_corner_count_larger_than_label(corner)
    if "Gauge" not in circular:
        fail("circular must use Gauge (0…1) so compact circular families fit")
    if "entry.snapshot.progress" not in circular:
        fail("circular Gauge must use snapshot progress 0…1")
    if "compactCountText" not in circular:
        fail("circular center must show compactCountText (open count / erledigt)")
    if "doneText" in circular or "totalText" in circular:
        fail("circular must not stack three-part oo/xx/yy labels")
    if "progressLabel" in circular:
        fail("circular must not display progressLabel")
    for name, view in (("rectangular", rectangular), ("inline", inline), ("corner", corner)):
        if "compactCountText" not in view:
            fail(f"{name} must show compactCountText")
        if "progressLabel" in view:
            fail(f"{name} must not display progressLabel")
    if "containerBackground" not in widget:
        fail("complication view needs containerBackground for watchOS 10")
    if "var progress: Double" not in models:
        fail("ComplicationSnapshot must expose progress 0…1 for the circular Gauge")
    ios_info = (ROOT / "Sources/iOS/Info.plist").read_text()
    if "widgetkit-extension" in ios_info:
        fail("iPhone Info.plist must not declare a WidgetKit extension")

    todo_widget = (ROOT / "Sources/WatchWidgets/TodoWatchWidgets.swift").read_text()
    todo_models = (ROOT / "Sources/Shared/TodoModels.swift").read_text()
    todo_store = (ROOT / "Sources/Shared/TodoStore.swift").read_text()
    if "TodoComplication()" not in widget:
        fail("Watch WidgetBundle must include TodoComplication alongside EinkaufComplication")
    if "struct TodoComplication" not in todo_widget:
        fail("TodoComplication must live in WatchWidgets, separate from EinkaufComplication")
    if "TodoProgress" not in todo_models:
        fail("TodoComplicationSnapshot widgetKind must be TodoProgress")
    if 'labelText = "To Do"' not in todo_models:
        fail("To-Do complication label must be exactly To Do")
    if "einkauf://todo" not in todo_models:
        fail("To-Do complication openURL must be einkauf://todo")
    if "TodoPersistence.load" not in todo_widget:
        fail("To-Do complication must read TodoPersistence / todo-local.json")
    if "einkauf-local.json" in todo_widget or re.search(r"(?<![A-Za-z])Persistence\.load", todo_widget):
        fail("To-Do complication must never read einkauf-local.json")
    if "ShoppingStore" in todo_widget or "AppState" in todo_widget:
        fail("To-Do complication must not mix ShoppingStore / AppState")
    if '"erledigt"' not in todo_models:
        fail("TodoComplicationSnapshot compactCountText must use erledigt when open is 0")
    if "todoTimelines" not in reload:
        fail("WatchComplicationReload must reload TodoProgress separately")
    if "WatchComplicationReload.todoTimelines" not in todo_store:
        fail("TodoStore persist must reload the To-Do complication")
    if "WatchComplicationReload.timelines()" in todo_store.replace("WatchComplicationReload.todoTimelines()", ""):
        fail("TodoStore must not reload the Einkauf complication")
    todo_circular = extract_some_view(todo_widget, "circular")
    todo_corner = extract_some_view(todo_widget, "corner")
    assert_no_large_progress_text(todo_circular, "todo circular")
    assert_corner_count_larger_than_label(todo_corner)
    if "Gauge" not in todo_circular:
        fail("To-Do circular must use Gauge")
    if "TodoComplicationSnapshot.labelText" not in todo_corner and '"To Do"' not in todo_corner:
        fail("To-Do corner widgetLabel must be To Do")
    print("watch complication: ok")


def test_iphone_widget() -> None:
    pbx = (ROOT / "Einkauf.xcodeproj/project.pbxproj").read_text()
    yml = (ROOT / "project.yml").read_text()
    desc = (ROOT / "Description.md").read_text()
    widget = (ROOT / "Sources/iOSWidgets/EinkaufWidgets.swift").read_text()
    models = (ROOT / "Sources/Shared/Models.swift").read_text()
    persist = (ROOT / "Sources/Shared/Persistence.swift").read_text()
    store = (ROOT / "Sources/Shared/ShoppingStore.swift").read_text()
    reload = (ROOT / "Sources/iOS/HomeWidgetReload.swift").read_text()
    tests = (ROOT / "Tests/EinkaufCoreTests/EinkaufCoreTests.swift").read_text()
    ios_ent = (ROOT / "Sources/iOS/Einkauf.entitlements").read_text()
    widget_ent = (ROOT / "Sources/iOSWidgets/EinkaufWidgets.entitlements").read_text()
    widget_plist = (ROOT / "Sources/iOSWidgets/Info.plist").read_text()
    app = (ROOT / "Sources/iOS/EinkaufApp.swift").read_text()

    if "net.tschelle.einkauf.widgets" not in pbx or "net.tschelle.einkauf.widgets" not in yml:
        fail("iPhone widget bundle id missing")
    if "watchkitapp.widgets" in widget or "EinkaufWatchWidgets" in widget:
        fail("iPhone widget source must not be the Watch complication")
    if "EinkaufWidgets" not in pbx or "EinkaufWidgets" not in yml:
        fail("iPhone widget target missing")
    if "EinkaufWidgets.appex in Embed Foundation Extensions" not in pbx:
        fail("iPhone widget extension not embedded in iPhone app")
    if "com.apple.widgetkit-extension" not in widget_plist:
        fail("iPhone widget NSExtensionPointIdentifier must be WidgetKit")
    if "CLKComplication" in widget or "import ClockKit" in widget:
        fail("iPhone widget must not use ClockKit")
    if "WidgetKit" not in widget or "StaticConfiguration" not in widget:
        fail("iPhone widget must be WidgetKit StaticConfiguration")
    for family in ("systemSmall", "systemMedium"):
        if family not in widget:
            fail(f"iPhone widget missing family {family}")
    for family in ("accessoryCircular", "accessoryRectangular", "accessoryInline", "accessoryCorner"):
        if family in widget:
            fail(f"iPhone widget must not include Lock Screen/Watch family {family}")
    if "systemLarge" in widget:
        fail("iPhone widget must not add systemLarge unless asked")
    if "Picker" in widget:
        fail("iPhone widget must not have a store picker")
    if "widgetURL" not in widget:
        fail("iPhone widget tap must set widgetURL")
    if "progressLabel" not in widget:
        fail("iPhone widget must show progressLabel oo/xx/yy")
    if "openItemNames" not in widget:
        fail("medium widget must list openItemNames")
    if "struct HomeWidgetSnapshot" not in models:
        fail("Models missing HomeWidgetSnapshot")
    if "static let widgetKind" not in models or "EinkaufHome" not in models:
        fail("HomeWidgetSnapshot missing widgetKind EinkaufHome")
    if "func make(from state: AppState)" not in models:
        fail("HomeWidgetSnapshot must be built from AppState")
    if "func openItemNames" not in models:
        fail("ListGrouping must expose openItemNames")
    if "os(iOS)" not in persist or "os(watchOS)" not in persist:
        fail("Persistence App Group must be used on iOS and watchOS")
    if "watchGroupFileURL" in persist:
        fail("Persistence must share appGroupFileURL with iPhone, not Watch-only")
    if "NSUbiquitous" in persist or "ubiquityContainer" in persist or "CKContainer" in persist:
        fail("Persistence must not use iCloud")
    if "group.net.tschelle.einkauf" not in ios_ent or "group.net.tschelle.einkauf" not in widget_ent:
        fail("iPhone app and widget must share App Group entitlements")
    if "icloud" in ios_ent.lower() or "icloud" in widget_ent.lower():
        fail("iPhone entitlements must not add iCloud")
    if "CODE_SIGN_ENTITLEMENTS = Sources/iOS/Einkauf.entitlements" not in pbx:
        fail("iPhone app target must sign with App Group entitlements")
    if "HomeWidgetReload" not in store or "os(iOS)" not in store:
        fail("ShoppingStore must reload iPhone widgets after persist")
    if "WidgetCenter" not in reload or "reloadTimelines" not in reload:
        fail("HomeWidgetReload must call WidgetCenter.reloadTimelines")
    if "HomeWidgetSnapshot.widgetKind" not in reload and "EinkaufHome" not in reload:
        fail("HomeWidgetReload must use HomeWidgetSnapshot.widgetKind")
    if "HomeWidgetReload.timelines()" not in app:
        fail("EinkaufApp must reload the iPhone widget when becoming active")
    if "iPhone-Widget" not in desc or "systemSmall" not in desc or "systemMedium" not in desc:
        fail("Description.md must document the iPhone widget families")
    if "nicht auf der Watch" not in desc.lower() and "Nicht auf der Watch" not in desc:
        fail("Description.md must say the iPhone widget is not on Watch")
    if "App Group `group.net.tschelle.einkauf`" not in desc:
        fail("Description.md must name the App Group for the iPhone widget")
    if "testOpenItemsFollowWalkOrderAndSkipDone" not in tests:
        fail("tests must cover widget open items in Geh-Modus order")
    if "testOpenItemLimitAndFullStoreName" not in tests:
        fail("tests must cover widget open-item limit and full store name")
    if "TARGETED_DEVICE_FAMILY = 1" not in pbx:
        fail("iPhone widget/app must stay iPhone-only")
    print("iphone widget: ok")


def test_siri_app_intents() -> None:
    splitter = (ROOT / "Sources/Shared/SpeechItemSplitter.swift").read_text()
    intent = (ROOT / "Sources/Shared/EinkaufAddItemsIntent.swift").read_text()
    store = (ROOT / "Sources/Shared/ShoppingStore.swift").read_text()
    pending = (ROOT / "Sources/Shared/SiriPendingAdds.swift").read_text()
    tests = (ROOT / "Tests/EinkaufCoreTests/EinkaufCoreTests.swift").read_text()
    desc = (ROOT / "Description.md").read_text()
    pbx = (ROOT / "Einkauf.xcodeproj/project.pbxproj").read_text()
    yml = (ROOT / "project.yml").read_text()
    pkg = (ROOT / "Package.swift").read_text()
    watch = (ROOT / "Sources/Watch/WatchListView.swift").read_text()
    watch_app = (ROOT / "Sources/Watch/EinkaufWatchApp.swift").read_text()
    gen = (ROOT / "Scripts/generate_xcodeproj.py").read_text()

    if "enum SpeechItemSplitter" not in splitter:
        fail("SpeechItemSplitter missing")
    if r"\s+und\s+" not in splitter or r"\s+sowie\s+" not in splitter:
        fail("SpeechItemSplitter must split on und/sowie")
    if "strippingTriggerPrefix" not in splitter:
        fail("SpeechItemSplitter must strip a leading Einkauf trigger")
    if "besorgen" not in splitter:
        fail("SpeechItemSplitter must also strip a leading Besorgen trigger")
    if "Keine Artikel erkannt." not in splitter:
        fail("SpeechItemSplitter must provide empty confirmation copy")
    if "1 Artikel hinzugefügt." not in splitter or "Artikel hinzugefügt." not in splitter:
        fail("SpeechItemSplitter must provide German add confirmation")

    if "import AppIntents" not in intent:
        fail("EinkaufAddItemsIntent must import AppIntents")
    if "struct EinkaufAddItemsIntent: AppIntent" not in intent:
        fail("EinkaufAddItemsIntent missing")
    if 'title: "Artikel"' not in intent:
        fail("Intent parameter title must be Artikel")
    if "AppShortcutsProvider" not in intent:
        fail("AppShortcutsProvider missing")
    if "struct EinkaufShortcuts: AppShortcutsProvider" not in intent:
        fail("EinkaufShortcuts must be the AppShortcutsProvider")
    if intent.count(": AppShortcutsProvider") != 1:
        fail("exactly one AppShortcutsProvider conformance is allowed")
    if "requestValueDialog" not in intent:
        fail("Intent must request Artikel via requestValueDialog")
    phrases_block = intent.split("phrases:", 1)[-1].split("shortTitle", 1)[0]
    if ".$items" in phrases_block:
        fail("App Shortcut phrases must not interpolate String $items (Apple: AppEntity/AppEnum only)")
    if phrases_block.count("applicationName") < 3:
        fail("each App Shortcut phrase must include applicationName")
    if r'"\(.applicationName) besorgen"' not in intent:
        fail("App Shortcut phrase applicationName besorgen missing")
    if r'"Besorgen mit \(.applicationName)"' not in intent:
        fail("App Shortcut phrase Besorgen mit applicationName missing")
    if r'"\(.applicationName) zum Besorgen"' not in intent:
        fail("App Shortcut phrase applicationName zum Besorgen missing")
    if "hinzufügen" in phrases_block or "hinzu" in phrases_block:
        fail("App Shortcut phrases must not use Bring-like hinzufügen vocabulary")
    if "Einkauf" in phrases_block:
        fail("App Shortcut phrases must not use generic Einkauf as the only cue")
    if 'shortTitle: "Besorgen"' not in intent:
        fail("App Shortcut shortTitle must be Besorgen")
    if 'requestValueDialog: "o"' not in intent:
        fail("requestValueDialog should ask o")
    if 'requestValueDialog: "ok"' in intent:
        fail("stale requestValueDialog ok")
    if "Was soll ich besorgen?" in intent:
        fail("stale requestValueDialog Was soll ich besorgen?")
    if "strippingTriggerPrefix" not in intent:
        fail("Intent perform must strip leading Einkauf / Einkauf: / Besorgen:")
    if "os(watchOS)" not in intent:
        fail("Intent must branch watchOS vs iOS")
    if "SiriPendingAdds.enqueue" not in intent:
        fail("watchOS Intent must only enqueue SiriPendingAdds")
    if "ShoppingStore" in intent.split("#if os(watchOS)", 1)[-1].split("#else", 1)[0]:
        fail("watchOS Intent must not construct ShoppingStore")
    if "Persistence.write" in intent:
        fail("Intent must not Persistence.write full AppState")
    if "addItemsFromSiri" in intent or "addItemsFromSiri" in store:
        fail("addItemsFromSiri soft-save path must be gone")
    if "addItems(fromSpeech:" not in intent:
        fail("iOS Intent perform must call addItems(fromSpeech:)")
    if "ShoppingStore(enableSync: true)" not in intent:
        fail("iOS Intent must keep ShoppingStore(enableSync: true)")
    if "ShoppingStore(enableSync: false)" in intent:
        fail("watchOS Intent must not construct ShoppingStore")
    if "Speichern fehlgeschlagen" not in intent:
        fail("Intent must return Speichern fehlgeschlagen instead of throwing")
    if "openAppWhenRun = true" in intent:
        fail("watchOS Intent must not force-launch the Watch app (openAppWhenRun = false)")
    if "openAppWhenRun = false" not in intent:
        fail("Intent must set openAppWhenRun = false on watchOS and iOS")
    if 'IntentDialog(stringLiteral:' in intent:
        fail("prefer IntentDialog(\"…\") over stringLiteral initializer")
    watch_perform = intent.split("#if os(watchOS)", 1)[-1].split("#else", 1)[0]
    if "ProvidesDialog" in watch_perform:
        fail("watchOS perform must not require ProvidesDialog")
    if "throws" in watch_perform:
        fail("watchOS perform must not throw")
    if "return .result()" not in watch_perform:
        fail("watchOS perform must return .result() after enqueue")
    if "SiriPendingAdds.enqueue" not in watch_perform.split("return", 1)[0]:
        fail("watchOS perform must enqueue before returning")

    if "enum SiriPendingAdds" not in pending:
        fail("SiriPendingAdds missing")
    if "einkauf-siri-pending.json" not in pending:
        fail("SiriPendingAdds must keep einkauf-siri-pending.json as file mirror")
    if "UserDefaults(suiteName: Persistence.appGroupId)" not in pending:
        fail("SiriPendingAdds must prefer UserDefaults(suiteName: Persistence.appGroupId)")
    if "group.net.tschelle.einkauf" not in pending and "Persistence.appGroupId" not in pending:
        fail("SiriPendingAdds suite must be Persistence.appGroupId")
    if "einkauf.siriPendingAdds" not in pending:
        fail("SiriPendingAdds must use defaults key einkauf.siriPendingAdds")
    if "appGroupContainerURL" not in pending:
        fail("SiriPendingAdds file fallback must use Persistence.appGroupContainerURL")
    if "applicationSupport" in pending or "fileURL.deletingLastPathComponent" in pending:
        fail("SiriPendingAdds must not fall back to Persistence.fileURL / Application Support")
    if "func enqueue" not in pending or "func drain" not in pending:
        fail("SiriPendingAdds must expose enqueue and drain")
    if "ShoppingStore" in pending or "AppState" in pending:
        fail("SiriPendingAdds must stay a string queue without AppState")

    if "func addItems(fromSpeech" not in store:
        fail("ShoppingStore.addItems(fromSpeech:) missing")
    if "func consumeSiriPendingAdds" not in store:
        fail("ShoppingStore.consumeSiriPendingAdds missing")
    if "appendNewItems" not in store:
        fail("addItems(fromSpeech:) must batch into a single persist")
    if "SpeechItemSplitter.strippingTriggerPrefix" not in store:
        fail("addItems(fromSpeech:) must strip a leading Einkauf prefix")
    consume_start = store.find("func consumeSiriPendingAdds")
    consume_end = store.find("var editRows", consume_start)
    consume_fn = store[consume_start:consume_end if consume_end > 0 else consume_start + 400]
    if "SiriPendingAdds.drain" not in consume_fn:
        fail("consumeSiriPendingAdds must drain the pending queue")
    if "addItems(fromSpeech:" not in consume_fn:
        fail("consumeSiriPendingAdds must add via addItems(fromSpeech:)")

    if "testCommaUndUndKeepsQuantity" not in tests:
        fail("tests must cover SpeechItemSplitter comma/und split")
    if "testAddItemsFromSpeechSplitsAndGuesses" not in tests:
        fail("tests must cover addItems(fromSpeech:)")
    if "testAddItemsFromSpeechStripsTriggerAndPersistsOnce" not in tests:
        fail("tests must cover trigger strip and single persist")
    if "testStripsLeadingBesorgenTrigger" not in tests:
        fail("tests must cover stripping a leading Besorgen trigger")
    if "testAddItemsFromSpeechStripsBesorgenTrigger" not in tests:
        fail("tests must cover addItems stripping Besorgen:")
    if "testEnqueueThenDrainPreservesOrder" not in tests:
        fail("tests must cover SiriPendingAdds enqueue/drain")
    if "testEnqueueStripsTriggerAndSkipsBlank" not in tests:
        fail("tests must cover SiriPendingAdds skipping blanks")
    if "testEnqueueThenDrainViaSuiteDefaults" not in tests:
        fail("tests must cover SiriPendingAdds UserDefaults suite queue")
    if "testMakeIDDoesNotTrapOnEpochMillis" not in tests:
        fail("tests must cover makeID Int64 epoch millis (watchOS arm64_32)")
    if "testConfirmationCopy" not in tests:
        fail("tests must cover Siri confirmation copy")

    if "EinkaufAddItemsIntent.swift" not in pbx:
        fail("pbxproj must compile EinkaufAddItemsIntent.swift")
    if "SpeechItemSplitter.swift" not in pbx:
        fail("pbxproj must compile SpeechItemSplitter.swift")
    if "SiriPendingAdds.swift" not in pbx:
        fail("pbxproj must compile SiriPendingAdds.swift")
    if "AppIntents.framework" not in pbx:
        fail("AppIntents.framework must be linked")
    if "Speech.framework" in pbx:
        fail("Speech.framework must not be linked")
    if "AVFoundation.framework" in pbx:
        fail("AVFoundation.framework must not be linked")
    if "AppIntents.framework" not in yml:
        fail("project.yml must depend on AppIntents.framework")
    if "EinkaufAddItemsIntent.swift" not in yml:
        fail("project.yml widgets must exclude EinkaufAddItemsIntent.swift")
    if "SiriPendingAdds.swift" not in yml:
        fail("project.yml widgets must exclude SiriPendingAdds.swift")
    if "TodoStore.swift" not in yml:
        fail("project.yml widgets must exclude TodoStore.swift")
    if "EinkaufAddItemsIntent.swift" not in pkg:
        fail("Package.swift must exclude EinkaufAddItemsIntent.swift from SPM")
    if "TodoAddItemsIntent.swift" not in pkg:
        fail("Package.swift must exclude TodoAddItemsIntent.swift from SPM")
    if "TodoAddItemsIntent.swift" not in pbx:
        fail("pbxproj must compile TodoAddItemsIntent.swift")
    if "TodoSiriPendingAdds.swift" not in pbx:
        fail("pbxproj must compile TodoSiriPendingAdds.swift")
    if "TodoAddItemsIntent.swift" not in yml:
        fail("project.yml widgets must exclude TodoAddItemsIntent.swift")
    if "TodoSiriPendingAdds.swift" not in yml:
        fail("project.yml widgets must exclude TodoSiriPendingAdds.swift")

    todo_intent = (ROOT / "Sources/Shared/TodoAddItemsIntent.swift").read_text()
    todo_pending = (ROOT / "Sources/Shared/TodoSiriPendingAdds.swift").read_text()
    if "besorgen" in todo_intent:
        fail("To-Do Siri phrases must not use besorgen")
    if "struct TodoShortcuts" in todo_intent or "struct TodoShortcuts" in intent:
        fail("TodoShortcuts must be deleted; only one AppShortcutsProvider is allowed")
    if ": AppShortcutsProvider" in todo_intent:
        fail("TodoAddItemsIntent.swift must not declare AppShortcutsProvider")
    if "intent: TodoAddItemsIntent()" not in intent:
        fail("EinkaufShortcuts must include TodoAddItemsIntent")
    if r'"\(.applicationName) To Do"' in intent or r'"To Do mit \(.applicationName)"' in intent:
        fail("To-Do App Shortcut phrases must use single-token Todo, not two-token To Do")
    if r'"\(.applicationName) zum To Do"' in intent:
        fail("To-Do App Shortcut phrases must use single-token Todo, not two-token To Do")
    if r'"\(.applicationName) Todo"' not in intent:
        fail("To-Do App Shortcut phrase applicationName Todo missing")
    if r'"Todo mit \(.applicationName)"' not in intent:
        fail("To-Do App Shortcut phrase Todo mit applicationName missing")
    if r'"\(.applicationName) zum Todo"' not in intent:
        fail("To-Do App Shortcut phrase applicationName zum Todo missing")
    if r'"\(.applicationName) Aufgaben"' not in intent:
        fail("To-Do App Shortcut alternate phrase applicationName Aufgaben missing")
    todo_shortcut = intent.split("intent: TodoAddItemsIntent()", 1)[-1]
    todo_phrases = todo_shortcut.split("phrases:", 1)[-1].split("shortTitle", 1)[0]
    if "To Do" in todo_phrases:
        fail("To-Do App Shortcut phrases must not contain two-token To Do")
    todo_title_block = todo_shortcut.split("shortTitle", 1)[-1].split("systemImageName", 1)[0]
    if "To Do" in todo_title_block:
        fail("To-Do App Shortcut shortTitle must not contain two-token To Do")
    if '"Todo"' not in todo_title_block:
        fail("To-Do App Shortcut shortTitle must be single-token Todo")
    if todo_phrases.count("applicationName") < 4:
        fail("each To-Do App Shortcut phrase must include applicationName")
    if ".$items" in todo_phrases:
        fail("To-Do App Shortcut phrases must not interpolate String $items")
    if "besorgen" in todo_phrases:
        fail("To-Do App Shortcut phrases must not use besorgen")
    if r'Summary("To Do \(\.$items)")' in todo_intent:
        fail("To-Do parameterSummary must not use multi-word To Do prefix (Siri truncates to first word)")
    if r'Summary("Todo \(\.$items)")' not in todo_intent:
        fail("To-Do parameterSummary must be single-token Todo like Besorgen")
    if "IntentInputOptions" not in intent or "IntentInputOptions" not in todo_intent:
        fail("both intents must set String.IntentInputOptions(capitalizationType: .sentences, multiline: true)")
    if "capitalizationType: .sentences" not in intent or "multiline: true" not in intent:
        fail("EinkaufAddItemsIntent must use sentence capitalization and multiline inputOptions")
    if "capitalizationType: .sentences" not in todo_intent or "multiline: true" not in todo_intent:
        fail("TodoAddItemsIntent must use sentence capitalization and multiline inputOptions")
    if todo_intent.count("#if os(watchOS)") < 2:
        fail("TodoAddItemsIntent must #if os(watchOS) Parameter (no requestValueDialog) and perform")
    todo_watch_param = todo_intent.split("#if os(watchOS)", 1)[-1].split("#else", 1)[0]
    todo_ios_param = todo_intent.split("#if os(watchOS)", 1)[-1].split("#else", 1)[1].split("#endif", 1)[0]
    if "requestValueDialog" in todo_watch_param:
        fail("watchOS Todo Parameter must omit requestValueDialog (generic free-form prompt)")
    if "var items: String" not in todo_watch_param or "IntentInputOptions" not in todo_watch_param:
        fail("watchOS Todo Parameter must keep Aufgaben + IntentInputOptions")
    if 'requestValueDialog: "o"' not in todo_ios_param:
        fail("iPhone Todo Parameter must keep requestValueDialog o")
    if "var items: String" not in todo_ios_param:
        fail("iPhone Todo Parameter must declare items")
    if 'requestValueDialog: "T"' in todo_intent:
        fail("stale To-Do requestValueDialog T")
    if "Nachfrage **„T“**" in desc:
        fail("Description.md still quotes To-Do Siri follow-up T")
    if "requestValueDialog` „T“" in desc or "requestValueDialog „T“" in desc:
        fail("Description.md still quotes requestValueDialog T")
    plan = (ROOT / "Docs/TodoIntegration.md").read_text()
    if "Nachfrage **„T“**" in plan:
        fail("TodoIntegration.md still quotes To-Do Siri follow-up T")
    if "requestValueDialog` „o“" not in desc and "requestValueDialog „o“" not in desc:
        fail("Description.md must document To-Do Siri asking o")
    if 'shortTitle: "To Do"' in intent:
        fail("To-Do App Shortcut shortTitle must not be two-token To Do")
    if 'shortTitle: "Todo"' not in intent:
        fail("To-Do App Shortcut shortTitle must be Todo")
    if "Auf Apple Watch anzeigen" not in desc:
        fail("Description.md must tell users to re-enable Auf Apple Watch anzeigen after shortcut update")
    if "kein** `requestValueDialog`" not in desc and "kein `requestValueDialog`" not in desc:
        fail("Description.md must document watchOS Todo omitting requestValueDialog")
    if "openAppWhenRun = false" not in todo_intent:
        fail("To-Do Intent must set openAppWhenRun = false")
    if "TodoSiriPendingAdds.enqueue" not in todo_intent:
        fail("watchOS To-Do Intent must enqueue TodoSiriPendingAdds")
    todo_watch_perform = todo_intent.rsplit("#if os(watchOS)", 1)[-1].split("#else", 1)[0]
    if "TodoStore" in todo_watch_perform:
        fail("watchOS To-Do Intent must not construct TodoStore")
    if "TodoStore(enableSync: true)" not in todo_intent:
        fail("iOS To-Do Intent must use TodoStore(enableSync: true)")
    if "addItems(fromSpeech:" not in todo_intent:
        fail("iOS To-Do Intent must call addItems(fromSpeech:)")
    if "strippingTodoTriggerPrefix" not in todo_intent:
        fail("To-Do Intent must strip To Do / todo prefix")
    if "ProvidesDialog" in todo_watch_perform or "throws" in todo_watch_perform:
        fail("watchOS To-Do perform must be plain .result() without dialog/throws")
    if "return .result()" not in todo_watch_perform:
        fail("watchOS To-Do perform must return .result()")
    if "todo.siriPendingAdds" not in todo_pending:
        fail("TodoSiriPendingAdds must use defaults key todo.siriPendingAdds")
    if "todo-siri-pending.json" not in todo_pending:
        fail("TodoSiriPendingAdds must use todo-siri-pending.json")
    if "einkauf.siriPendingAdds" in todo_pending or "einkauf-siri-pending.json" in todo_pending:
        fail("TodoSiriPendingAdds must not reuse einkauf Siri queue keys")
    if "ShoppingStore" in todo_pending or "AppState" in todo_pending:
        fail("TodoSiriPendingAdds must stay a string queue")
    if "func addItems(fromSpeech" not in (ROOT / "Sources/Shared/TodoStore.swift").read_text():
        fail("TodoStore.addItems(fromSpeech:) missing")
    if "func consumeSiriPendingAdds" not in (ROOT / "Sources/Shared/TodoStore.swift").read_text():
        fail("TodoStore.consumeSiriPendingAdds missing")
    if "strippingTodoTriggerPrefix" not in splitter:
        fail("SpeechItemSplitter must strip a leading To Do trigger")
    splitter_todo = splitter.split("func strippingTodoTriggerPrefix", 1)[-1].split("static func ", 1)[0]
    if "aufgaben" not in splitter_todo.lower():
        fail("strippingTodoTriggerPrefix must also strip leading Aufgaben")
    if "testStripsLeadingTodoTriggerNotBesorgen" not in tests:
        fail("tests must cover stripping To Do without touching besorgen")
    if "Rechnung bezahlen" not in tests:
        fail("tests must keep multi-word To-Do phrases as one item")
    if "Katze füttern" not in tests:
        fail("tests must keep multi-word To-Do phrases around und")
    if "ein Token" not in desc and "ein-tokenig" not in desc:
        fail("Description.md must document single-token To-Do parameterSummary")
    if "Einkauf Todo" not in desc:
        fail("Description.md must document spoken Hey Siri, Einkauf Todo")
    if "zwei Inhaltstokens" not in desc and "zwei Phrase-Tokens" not in desc:
        fail("Description.md must explain Siri two-token phrase capture limit")

    if "consumeSiriPendingAdds" not in watch_app:
        fail("Watch app must drain Siri pending queue when becoming active")
    if "todos.consumeSiriPendingAdds" not in watch_app:
        fail("Watch app must drain To-Do Siri pending as well as Einkauf")
    if ".task" not in watch_app:
        fail("Watch app root must drain Siri pending queue in .task")
    if "onAppear" not in watch or "consumeSiriPendingAdds" not in watch:
        fail("WatchListView must drain Siri pending queue onAppear")
    if "reloadFromPersistenceIfNewer" not in watch_app:
        fail("Watch app must still reload persistence when becoming active")
    if "import Speech" in watch or "import Speech" in watch_app:
        fail("Watch UI must not import Speech")
    if "presentTextInputController" in watch or "TextFieldLink" in watch:
        fail("Watch must not present dictation / TextFieldLink chrome")
    if "WatchHoldToTalk" in watch or "WatchVoiceAdd" in watch:
        fail("Watch mic UI must stay reverted")
    if (ROOT / "Sources/Watch/WatchHoldToTalk.swift").exists():
        fail("WatchHoldToTalk.swift must not return")
    if "Speech.framework" in gen:
        fail("generate_xcodeproj.py must not link Speech.framework")

    if "Siri" not in desc or "Einkauf:" not in desc:
        fail("Description.md must document Siri Einkauf phrases")
    if "besorgen" not in desc:
        fail("Description.md must document the besorgen Siri trigger")
    if "Einkauf besorgen" not in desc:
        fail("Description.md must document Hey Siri, Einkauf besorgen")
    if "OS-weit" not in desc or "Best Effort" not in desc:
        fail("Description.md must note iOS cannot reserve besorgen OS-wide (best-effort vs Bring)")
    if "applicationName" not in desc:
        fail("Description.md must document applicationName in Siri utterances")
    if "AppEntity" not in desc or "AppEnum" not in desc:
        fail("Description.md must document Apple App Shortcut type restriction")
    if "requestValueDialog" not in desc and "fragt danach" not in desc:
        fail("Description.md must document Siri asking for Artikel after the utterance")
    if "Was soll ich besorgen?" in desc:
        fail("Description.md still quotes old Siri follow-up Was soll ich besorgen?")
    if "fragt „ok“" in desc:
        fail("Description.md still quotes old Siri follow-up ok")
    if "fragt „o“" not in desc:
        fail("Description.md must say Siri asks o")
    if "Pending-Queue" not in desc:
        fail("Description.md must document the Watch-Siri pending queue")
    if "UserDefaults" not in desc or "einkauf.siriPendingAdds" not in desc:
        fail("Description.md must document the App Group UserDefaults pending queue")
    if "onAppear" not in desc or ".task" not in desc:
        fail("Description.md must say the Watch app drains onAppear and .task")
    if "consumeSiriPendingAdds" not in desc and "beim Aktivwerden" not in desc:
        fail("Description.md must say the Watch app drains the queue when becoming active")
    if "Int64" not in desc or "arm64_32" not in desc:
        fail("Description.md must note Watch makeID uses Int64 (arm64_32)")
    if "openAppWhenRun" not in desc:
        fail("Description.md must document openAppWhenRun on Watch vs iOS")
    if "openAppWhenRun = false" not in desc:
        fail("Description.md must set Watch openAppWhenRun = false")
    if "Speech.framework" not in desc:
        fail("Description.md must forbid Speech.framework")
    if "kein Watch-Mikro" not in desc and "Kein** In-App-Mikrofon" not in desc and "kein In-App-Mikro" not in desc:
        fail("Description.md must say there is no Watch mic")
    print("siri app intents: ok")


def todo_prio_key(task: dict) -> str:
    a = task.get("prioA") or ""
    if not a:
        return "\uffff"
    b = task.get("prioB") or "9"
    return a + b


def todo_pdf_groups(tasks: list[dict], show_completed: bool) -> list[tuple[str, list[dict]]]:
    visible = [t for t in tasks if show_completed or not t.get("completed")]
    visible.sort(
        key=lambda t: (
            t.get("person") or "",
            bool(t.get("completed")),
            todo_prio_key(t),
            t.get("text") or "",
            t.get("uid") or 0,
        )
    )
    groups: list[tuple[str, list[dict]]] = []
    for t in visible:
        title = (t.get("person") or "").strip() or "Keine Person"
        if groups and groups[-1][0] == title:
            groups[-1][1].append(t)
        else:
            groups.append((title, [t]))
    return groups


def todo_progress(groups: list[tuple[str, list[dict]]]) -> str:
    tasks = [t for _, g in groups for t in g]
    done = sum(1 for t in tasks if t.get("completed"))
    return f"{len(tasks) - done}/{done}/{len(tasks)}"


def test_todo_pdf_grouping_python() -> None:
    tasks = [
        {"uid": 1, "text": "done TS", "completed": True, "prioA": "A", "person": "TS"},
        {"uid": 2, "text": "open B", "completed": False, "prioA": "B", "person": "NA"},
        {"uid": 3, "text": "open A2", "completed": False, "prioA": "A", "prioB": "2", "person": "NA"},
        {"uid": 4, "text": "open A1", "completed": False, "prioA": "A", "prioB": "1", "person": "NA"},
        {"uid": 5, "text": "no person", "completed": False, "prioA": "A", "person": ""},
        {"uid": 6, "text": "open TS", "completed": False, "prioA": "", "person": "TS"},
    ]
    shown = todo_pdf_groups(tasks, True)
    if [g[0] for g in shown] != ["Keine Person", "NA", "TS"]:
        fail("todo PDF groups must be Keine Person, then people, sorted")
    if [t["uid"] for t in shown[1][1]] != [4, 3, 2]:
        fail("todo PDF must sort open tasks by prio within a person")
    if [t["uid"] for t in shown[2][1]] != [6, 1]:
        fail("todo PDF must put open tasks before completed within a person")
    if todo_progress(shown) != "5/1/6":
        fail("todo PDF progress must be oo/xx/yy of printed tasks")
    hidden = todo_pdf_groups(tasks, False)
    if [g[0] for g in hidden] != ["Keine Person", "NA", "TS"]:
        fail("hiding completed must drop done rows but keep people with open tasks")
    if any(t.get("completed") for _, g in hidden for t in g):
        fail("hiding completed must omit completed tasks from the PDF")
    if todo_progress(hidden) != "5/0/5":
        fail("open-only PDF progress must be n/0/n")
    only_done = todo_pdf_groups(
        [{"uid": 1, "text": "x", "completed": True, "person": "TS"}],
        False,
    )
    if only_done:
        fail("all-completed + eye closed must yield no PDF groups")


def test_todo_store() -> None:
    pbx = (ROOT / "Einkauf.xcodeproj/project.pbxproj").read_text()
    persist = (ROOT / "Sources/Shared/TodoPersistence.swift").read_text()
    codec = (ROOT / "Sources/Shared/TodoCodec.swift").read_text()
    store = (ROOT / "Sources/Shared/TodoStore.swift").read_text()
    models = (ROOT / "Sources/Shared/TodoModels.swift").read_text()
    tests = (ROOT / "Tests/EinkaufCoreTests/TodoStoreTests.swift").read_text()
    desc = (ROOT / "Description.md").read_text()
    content = (ROOT / "Sources/iOS/ContentView.swift").read_text()
    todo_ui = (ROOT / "Sources/iOS/TodoListView.swift").read_text()
    watch = (ROOT / "Sources/Watch/WatchListView.swift").read_text()
    watch_app = (ROOT / "Sources/Watch/EinkaufWatchApp.swift").read_text()
    einkauf_app = (ROOT / "Sources/iOS/EinkaufApp.swift").read_text()

    for name in ("TodoModels.swift", "TodoCodec.swift", "TodoPersistence.swift", "TodoStore.swift", "TodoListView.swift", "IncomingJSON.swift", "TodoListPDF.swift"):
        if name not in pbx:
            fail(f"pbxproj must compile {name}")
    if "todo-local.json" not in persist:
        fail("TodoPersistence must write todo-local.json")
    if "einkauf-local.json" in persist:
        fail("TodoPersistence must never mention einkauf-local.json")
    if "BackupCodec." in persist or "BackupCodec." in store:
        fail("Todo persist/store must not route through BackupCodec")
    if 'kind: "todo-local"' not in codec and 'localKind = "todo-local"' not in codec:
        fail("TodoCodec must use kind todo-local")
    if "ConnectivitySync" not in store or "TodoConnectivitySync" not in store:
        fail("TodoStore must wire TodoConnectivitySync when enableSync")
    if "WCSession" in store:
        fail("TodoStore must not talk to WCSession directly")
    if "TabView" not in einkauf_app:
        fail("iPhone root must use TabView for Einkauf | To-Do")
    if 'Label("Einkauf", systemImage: "basket")' not in einkauf_app:
        fail("Einkauf tab must use basket SF Symbol")
    if 'Label("To-Do", systemImage: "checklist")' not in einkauf_app:
        fail("To-Do tab must use checklist SF Symbol")
    if "TodoStore()" not in einkauf_app or "environmentObject(todos)" not in einkauf_app:
        fail("EinkaufApp must own TodoStore and inject environmentObject")
    if "ShoppingStore()" not in einkauf_app:
        fail("EinkaufApp must keep ShoppingStore")
    if "TodoListView" not in einkauf_app:
        fail("EinkaufApp TabView must host TodoListView")
    if "TabView" in content:
        fail("ContentView must stay the Einkauf tab, not wrap TabView")
    if "TodoListView" in content or "TodoStore" in content:
        fail("ContentView must not host Todo UI")
    if "fileImporter" not in content or "Geh-Modus" not in content:
        fail("Einkauf ContentView must keep backup import and Geh-Modus")
    if "TabView" in watch:
        fail("WatchListView must stay the Einkauf tab, not wrap TabView")
    if "TabView" not in watch_app:
        fail("Watch app must use TabView for Einkauf | To-Do")
    if "WatchTodoListView" not in watch_app:
        fail("Watch TabView must host WatchTodoListView")
    if "TodoStore()" not in watch_app or "environmentObject(todos)" not in watch_app:
        fail("EinkaufWatchApp must own TodoStore and inject environmentObject")
    if 'Label("Einkauf", systemImage: "basket")' not in watch_app:
        fail("Watch Einkauf tab must use basket SF Symbol")
    if 'Label("To-Do", systemImage: "checklist")' not in watch_app:
        fail("Watch To-Do tab must use checklist SF Symbol")
    if "TodoListView" in watch or "TodoStore" in watch:
        fail("WatchListView must not host Todo UI")
    if "fileImporter" not in todo_ui or "fileExporter" not in todo_ui:
        fail("TodoListView must offer backup import/export")
    if "Backup importieren" not in todo_ui or "Backup exportieren" not in todo_ui:
        fail("To-Do overflow must list Backup importieren/exportieren")
    if "todo-liste" not in todo_ui:
        fail("To-Do export default filename must be todo-liste")
    if "Anhängen" not in todo_ui or "Ersetzen" not in todo_ui:
        fail("To-Do import must offer Anhängen vs Ersetzen")
    if "todo-liste" in content or "todo-v3-json" in content:
        fail("Einkauf ContentView must not grow To-Do backup actions")
    if "markdown" in todo_ui.lower() or "todo-liste.csv" in todo_ui or "todo-liste.md" in todo_ui:
        fail("Phase 5 must not add MD/CSV export")
    if "BackupCodec" in todo_ui or "einkauf-backup" in todo_ui:
        fail("To-Do UI must not call BackupCodec or write einkauf-backup")
    if "IncomingJSON.classify" not in einkauf_app or "onOpenURL" not in einkauf_app:
        fail("EinkaufRoot must classify incoming JSON before choosing a store")
    if "encodeBackup" not in codec or "decodeBackup" not in codec or 'backupFormat = "todo-v3-json"' not in codec:
        fail("TodoCodec must encode/decode todo-v3-json")
    if "func importBackup" not in store or "func exportBackup" not in store:
        fail("TodoStore missing importBackup/exportBackup")
    if "NavigationStack" not in todo_ui:
        fail("TodoListView needs its own NavigationStack")
    if "Hinzufügen" not in todo_ui or "Neue Aufgabe" not in todo_ui:
        fail("TodoListView must add tasks via Hinzufügen")
    if "onDelete" not in todo_ui:
        fail("TodoListView must swipe-delete")
    todo_browse = extract_some_view(todo_ui, "browsingList")
    todo_edit = extract_some_view(todo_ui, "editingList")
    if ".onDelete" in todo_browse:
        fail("TodoListView browsingList must not attach onDelete (swipe-delete only in Bearbeiten)")
    if "deleteDisabled(true)" not in todo_browse:
        fail("TodoListView browsingList rows must deleteDisabled(true)")
    if "swipeActions(edge: .trailing" not in todo_browse or "EmptyView()" not in todo_browse:
        fail("TodoListView browsingList must suppress system delete with trailing EmptyView")
    if ".onDelete(perform: delete)" not in todo_edit:
        fail("TodoListView editingList must keep onDelete swipe-delete")
    if "EmptyView()" in todo_edit:
        fail("TodoListView editingList must not suppress trailing delete with EmptyView")
    if '.id(isEditing ? "todo-edit" : "todo-browse")' not in todo_ui:
        fail("TodoListView must change list identity when toggling Bearbeiten")
    if '.id("todo-browse")' not in todo_browse or '.id("todo-edit")' not in todo_edit:
        fail("TodoListView browsingList/editingList must have distinct .id")
    if "todos.toggle" not in todo_ui:
        fail("TodoListView must toggle completed")
    if "todos.update" not in todo_ui:
        fail("TodoListView must rename via todos.update")
    if "todo.iphone.showCompleted" not in todo_ui:
        fail("To-Do show-completed must use AppStorage todo.iphone.showCompleted")
    if "einkauf.iphone.hideCompleted" in todo_ui:
        fail("To-Do must not reuse einkauf.iphone.hideCompleted")
    if 'Toggle("Abgeschlossen einblenden"' in todo_ui:
        fail("To-Do toolbar must use an eye button, not a text Toggle")
    if 'showCompleted ? "eye" : "eye.slash"' not in todo_ui:
        fail("To-Do eye must be eye when showing completed, eye.slash when hidden")
    if "Abgeschlossene ausblenden" not in todo_ui or "Abgeschlossene einblenden" not in todo_ui:
        fail("To-Do eye must use Abgeschlossene ausblenden / einblenden")
    if 'Button(isEditing ? "Fertig" : "Bearbeiten")' not in todo_ui:
        fail("To-Do toolbar must toggle Bearbeiten / Fertig")
    eye_todo = todo_ui.find('showCompleted ? "eye" : "eye.slash"')
    edit_todo = todo_ui.find('Button(isEditing ? "Fertig" : "Bearbeiten")')
    more_todo = todo_ui.find("ellipsis.circle")
    if not (0 <= eye_todo < edit_todo < more_todo):
        fail("To-Do toolbar must be eye, then Bearbeiten/Fertig, then …")
    if "swipeActions" not in todo_ui or 'Label("Bearbeiten"' not in todo_ui:
        fail("To-Do rows need swipe action Bearbeiten")
    if "chevron.right" not in todo_ui:
        fail("To-Do edit mode must show a chevron affordance")
    if ".sheet(item: $editingTask)" not in todo_ui:
        fail("To-Do edit must present TodoEditSheet via sheet(item:)")
    if "person: draftPerson" not in todo_ui or 'TextField("Person"' not in todo_ui:
        fail("To-Do add bar must keep Person/Prio fields")
    if "ellipsis.circle" not in todo_ui or 'accessibilityLabel("Mehr")' not in todo_ui:
        fail("To-Do overflow must be ellipsis.circle labeled Mehr")
    if "Erledigte löschen" not in todo_ui:
        fail("To-Do overflow must offer Erledigte löschen")
    if "func clearCompleted" not in store:
        fail("TodoStore missing clearCompleted")
    if "Geh-Modus" in todo_ui or "Stamm" in todo_ui:
        fail("To-Do toolbar must not copy Einkauf Geh-Modus / Stamm")
    if 'Button("Liste teilen", systemImage: "list.bullet.rectangle")' not in todo_ui:
        fail("To-Do overflow must offer Liste teilen")
    backup_todo = todo_ui.find('Button("Backup teilen"')
    liste_todo = todo_ui.find('Button("Liste teilen"')
    clear_todo = todo_ui.find('Button("Erledigte löschen"')
    if backup_todo < 0 or liste_todo < 0 or clear_todo < 0 or not (backup_todo < liste_todo < clear_todo):
        fail("To-Do Liste teilen must sit after Backup teilen and before Erledigte löschen")
    if todo_ui[backup_todo:liste_todo].count("Button(") != 1:
        fail("To-Do Liste teilen must come immediately after Backup teilen")
    share_todo_m = re.search(r"private func shareList\(\)\s*\{", todo_ui)
    if not share_todo_m:
        fail("TodoListView missing shareList")
    share_todo = extract_braced(todo_ui, share_todo_m.start(), "todo shareList")
    if "TodoListPDF.render" not in share_todo:
        fail("To-Do Liste teilen must render via TodoListPDF")
    if "ListPDF.render" in todo_ui.replace("TodoListPDF.render", ""):
        fail("To-Do PDF must use TodoListPDF, not ListPDF")
    if "TodoListPDF" in content:
        fail("Einkauf share must stay on ListPDF")
    if "showCompleted" not in share_todo:
        fail("To-Do PDF must follow todo.iphone.showCompleted")
    if "einkauf.iphone.hideCompleted" in share_todo:
        fail("To-Do PDF must not use einkauf hideCompleted")
    if "TodoListGrouping.groups" not in share_todo or "TodoListGrouping.progressLabel" not in share_todo:
        fail("To-Do PDF must group via TodoListGrouping and print oo/xx/yy of that set")
    if "dark: false" not in share_todo or "ThemeRGB.tokens" not in share_todo:
        fail("To-Do PDF must use light ThemeRGB like Einkauf")
    if "ListShare.writeTodoTempFile" not in share_todo:
        fail("To-Do PDF temp file must use ListShare.writeTodoTempFile")
    if "Die Liste ist leer." not in share_todo:
        fail("empty To-Do list must show Die Liste ist leer.")
    if "Keine offenen Aufgaben" not in share_todo or "ausgeblendet" not in share_todo:
        fail("hidden-completed empty To-Do PDF must show a German empty-filter error")
    if "BackupShareItem" not in share_todo:
        fail("To-Do Liste teilen must open ShareSheet via BackupShareItem")
    if "markdown" in todo_ui.lower() or "todo-liste.csv" in todo_ui or "todo-liste.md" in todo_ui:
        fail("To-Do Liste teilen must not add MD/CSV export")
    todo_pdf = (ROOT / "Sources/iOS/TodoListPDF.swift").read_text()
    if "UIGraphicsPDFRenderer" not in todo_pdf:
        fail("TodoListPDF must use UIGraphicsPDFRenderer")
    if "To-Do Liste" not in todo_pdf:
        fail("TodoListPDF title must be To-Do Liste")
    if "checkmark.circle.fill" in todo_pdf or "checkmark" in todo_pdf.lower():
        fail("TodoListPDF checkbox must not draw a checkmark")
    todo_box_fn = re.search(r"func drawCheckbox\([^)]*\) \{.*?\n        \}", todo_pdf, re.S)
    if not todo_box_fn:
        fail("TodoListPDF missing drawCheckbox")
    todo_box = todo_box_fn.group(0)
    if "setFill" in todo_box or ".fill(" in todo_box or "path.fill" in todo_box:
        fail("TodoListPDF checkbox must not fill (empty square for pen ticks)")
    if "done" in todo_box or "completed" in todo_box:
        fail("TodoListPDF checkbox must ignore completed (same empty box for every task)")
    if not re.search(r"roundedRect|addRect|\.stroke\(|strokePath", todo_box):
        fail("TodoListPDF checkbox must stroke an empty square/rect")
    if "strikethroughStyle" not in todo_pdf:
        fail("TodoListPDF must strikethrough completed tasks when they print")
    if "guard !groups.isEmpty" not in todo_pdf and "groups.isEmpty" not in todo_pdf:
        fail("TodoListPDF must refuse an empty group list")
    list_share = (ROOT / "Sources/Shared/ListShare.swift").read_text()
    if "todo-liste.pdf" not in list_share or "stampedTodoFilename" not in list_share:
        fail("ListShare must stamp yyyyMMdd_HHmm-todo-liste.pdf without changing einkauf filenames")
    if 'stampedFilename(storeName: "Edeka"' not in (ROOT / "Tests/EinkaufCoreTests/EinkaufCoreTests.swift").read_text():
        fail("Einkauf ListShare tests must keep einkauf-{slug}.pdf")
    if "testPDFGroupsByPersonOpenFirstAndPrio" not in tests:
        fail("tests must cover To-Do PDF person groups")
    if "testPDFHidesCompletedWhenEyeClosed" not in tests:
        fail("tests must cover To-Do PDF eye filter")
    if "testTodoFilenameIsTodoListeStem" not in (ROOT / "Tests/EinkaufCoreTests/EinkaufCoreTests.swift").read_text():
        fail("tests must cover todo-liste.pdf filename")
    if "TodoListPDF" not in desc or "todo.iphone.showCompleted" not in desc:
        fail("Description.md WIP must mention To-Do Liste teilen PDF and the eye key")
    if "TodoListView" in watch or "TodoListPDF" in watch:
        fail("Watch must not get To-Do PDF / Liste teilen")
    if "testClearCompletedRemovesOnlyDone" not in tests:
        fail("tests must cover clearCompleted")
    if "– Prio" not in todo_ui:
        fail("To-Do add form needs – Prio empty option")
    if 'TextField("Person"' not in todo_ui:
        fail("To-Do add form needs Person field")
    if "person: draftPerson" not in todo_ui or "prioA: draftPrioA" not in todo_ui or "dueDate: draftDue" not in todo_ui:
        fail("TodoListView must add with person/prio/due")
    if "TodoOrdering" not in models or "prioSortKey" not in models or "isOverdue" not in models:
        fail("TodoOrdering must expose overdue and prio sort")
    if "TodoListGrouping" not in models or "Keine Person" not in models:
        fail("TodoListGrouping must group by person with Keine Person")
    test_todo_pdf_grouping_python()
    if "testIsOverdueIgnoresTodayFutureEmptyAnd9999" not in tests:
        fail("tests must cover overdue helper")
    if "testPrioSortKeyMissingAGoesLast" not in tests:
        fail("tests must cover prio sort key")
    if "testSortPersonThenOpenFirstThenPrio" not in tests:
        fail("tests must cover person/open/prio sort")
    if "testV3JsonFixtureRoundTripAndIgnoresExtraFields" not in tests:
        fail("tests must cover todo-v3-json roundtrip")
    if "testRejectsEinkaufBackupAndLocal" not in tests:
        fail("tests must reject einkauf JSON in todo import")
    if "testEinkaufLooksLikeBackupRejectsTodoJSON" not in tests:
        fail("tests must reject todo JSON on einkauf looksLikeBackup")
    if "testIncomingJSONRoutesTodoAndEinkaufApart" not in tests:
        fail("tests must cover IncomingJSON routing")
    if "testExportImportReplaceAndAppendRenumbersCollidingUids" not in tests:
        fail("tests must cover append uid renumber")
    einkauf_tests = (ROOT / "Tests/EinkaufCoreTests/EinkaufCoreTests.swift").read_text()
    if 'loadFixture("todo-v3-json.json")' in einkauf_tests:
        fail("todo fixture must not be fed into Einkauf BackupCodec tests")
    if "Int64" not in models:
        fail("Todo uid must be Int64")
    task_decl = models.split("struct TodoTask", 1)[-1].split("struct TodoState", 1)[0]
    if "Identifiable" not in task_decl or "var id: Int64 { uid }" not in task_decl:
        fail("TodoTask must be Identifiable by uid for sheet(item:)")
    if "Hashable" not in task_decl:
        fail("TodoTask must be Hashable for sheet(item:)")
    if "Bearbeiten" not in desc or "Fertig" not in desc or "TodoEditSheet" not in desc:
        fail("Description.md WIP must document To-Do Bearbeiten / Fertig and TodoEditSheet")
    if "func add(" not in store or "func toggle(" not in store or "func delete(" not in store:
        fail("TodoStore missing add/toggle/delete")
    if "testLocalRoundTripPreservesTasksAndNextUid" not in tests:
        fail("tests must cover todo-local roundtrip")
    if "testSaveDoesNotWriteEinkaufLocal" not in tests:
        fail("tests must cover todo persist isolation")
    if "testNormalizeAssignsMissingUidsFromNextUid" not in tests:
        fail("tests must cover normalize missing uids")
    if "kein HTML-Parity" not in desc.lower() and "Kein** HTML-Parity" not in desc and "**Kein** HTML-Parity" not in desc:
        fail("Description.md WIP must not claim full To-Do HTML parity")
    if "TabView" not in desc and "To-Do" not in desc:
        fail("Description.md WIP must mention the To-Do tab")
    watch_todo = (ROOT / "Sources/Watch/WatchTodoListView.swift").read_text()
    if "todo.watch.hideCompleted" not in watch_todo:
        fail("Watch To-Do eye must use AppStorage todo.watch.hideCompleted")
    if "einkauf.watch.hideCompleted" in watch_todo or "todo.iphone.showCompleted" in watch_todo:
        fail("Watch To-Do must not reuse einkauf.watch.hideCompleted or todo.iphone.showCompleted")
    if "todos.toggle" not in watch_todo:
        fail("Watch To-Do rows must toggle completed")
    if "fileImporter" in watch_todo or "TextField" in watch_todo or re.search(r"\bPicker\s*\(", watch_todo):
        fail("Watch To-Do must not offer edit/import/search")
    if "reopenedFromUid" in watch_todo or "Wieder öffnen" in watch_todo:
        fail("Watch To-Do must not offer reopen")
    if "todo-liste.md" in watch_todo or "todo-liste.csv" in watch_todo:
        fail("Watch To-Do must not offer MD/CSV")
    if "toolbar(.hidden, for: .navigationBar)" not in watch_todo:
        fail("Watch To-Do must hide the navigation bar like Einkauf")
    if '"eye"' not in watch_todo or "eye.slash" not in watch_todo:
        fail("Watch To-Do must use eye / eye.slash")
    if "consumeSiriPendingAdds" not in watch_todo:
        fail("WatchTodoListView must drain To-Do Siri pending onAppear")
    if "testMergingTodoIntoLegacyEinkaufContextKeepsEinkaufBlob" not in tests:
        fail("tests must cover merged application context")
    if "testExtractTodoBlobAndUidFromNSNumber" not in tests:
        fail("tests must cover todo payload extract / uid NSNumber")
    if "testOpenCountAndErledigtNeverReadsEinkauf" not in tests:
        fail("tests must cover TodoComplicationSnapshot compactCountText")
    if "testAddItemsFromSpeechAndPendingQueue" not in tests:
        fail("tests must cover To-Do Siri pending queue")
    if "enableSync" not in store or "TodoConnectivitySync" not in store:
        fail("TodoStore.enableSync must start TodoConnectivitySync")
    print("todo store + iphone tab: ok")


def main() -> None:
    test_fixtures()
    test_store_switch_changes_group_order()
    test_walk_lines_screenshot_items()
    test_sonstiges_follows_layout_position()
    test_backup_codec_python()
    test_sources()
    test_watch_complication()
    test_iphone_widget()
    test_siri_app_intents()
    test_todo_store()
    print("ALL OK")


if __name__ == "__main__":
    main()
