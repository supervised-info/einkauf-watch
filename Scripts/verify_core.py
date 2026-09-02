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
    store = (ROOT / "Sources/Shared/ShoppingStore.swift").read_text()
    if "func toggle" not in store:
        fail("no toggle")
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
        "Sources/iOS/AppearanceSettings.swift",
        "Sources/Shared/KeywordDictionary.swift",
        "Sources/Shared/KeywordDictionaryBrowse.swift",
        "Sources/Watch/WatchListView.swift",
        "Sources/iOS/Assets.xcassets/AppIcon.appiconset/AppIcon.png",
        "Sources/Watch/Assets.xcassets/AppIcon.appiconset/AppIcon.png",
    ]
    for rel in needed:
        if not (ROOT / rel).exists():
            fail(f"missing {rel}")
    content = (ROOT / "Sources/iOS/ContentView.swift").read_text()
    if "Beispiel-Liste" in content or "loadSampleFromBundle" in content:
        fail("sample list still offered in UI")
    if "Gesamtliste" not in content:
        fail("Stamm menu missing Gesamtliste")
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
    if "ForEach(store.walkListRows)" not in content:
        fail("ContentView walkList must ForEach walkListRows (flat store+position ids)")
    if "store.walkLines" in content and "ForEach(store.walkLines)" in content:
        fail("walk ForEach must use walkListRows so ids include position")
    list_id = '.id("\\(store.state.currentStoreId)|\\(store.state.currentStore.layout.joined())")'
    if content.count(list_id) < 2:
        fail("ContentView walkList and editList must .id(currentStoreId|layout) so store switch rebuilds")
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
    if "sheet(item:" not in content:
        fail("Backup teilen must use sheet(item:) with a file URL")
    if "showShare" in content or "if let shareURL" in content:
        fail("Backup teilen still uses isPresented + optional URL")
    if "shareList" not in content or "ListPDF.render" not in content:
        fail("Liste teilen must render a PDF via ListPDF")
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
        fail("Einstellungen missing Laden löschen")
    if "!store.state.currentStore.builtin" not in settings:
        fail("Laden löschen must be limited to custom stores")
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
    browse = (ROOT / "Sources/Shared/KeywordDictionaryBrowse.swift").read_text()
    if "Department.title" not in browse:
        fail("Wörterbuch groups must use Department.title")
    if "Locale(identifier: \"de\")" not in browse:
        fail("Wörterbuch words must sort with de locale")
    kd = (ROOT / "Sources/Shared/KeywordDictionary.swift").read_text()
    if "static let source" not in kd:
        fail("KeywordDictionary.source missing")
    if "Do not scrape" not in kd:
        fail("KeywordDictionary must stay local (no website scrape)")
    store_src = (ROOT / "Sources/Shared/ShoppingStore.swift").read_text()
    if "func createStore" not in store_src or "func deleteStore" not in store_src:
        fail("ShoppingStore missing createStore/deleteStore")
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
    watch = (ROOT / "Sources/Watch/WatchListView.swift").read_text()
    if "Picker" in watch:
        fail("Watch should not have a store picker")
    if list_id not in watch:
        fail("Watch list must .id(currentStoreId|layout) so store switch rebuilds")
    if "Section {" in watch:
        fail("Watch list must not use List+Section")
    if "ForEach(store.groups)" in watch:
        fail("Watch must not ForEach groups as List sections")
    if "ForEach(store.walkListRows)" not in watch:
        fail("Watch list must ForEach walkListRows (flat store+position ids)")
    if "navigationTitle(store.state.watchTitle)" not in watch:
        fail("Watch navigationTitle must bind to watchTitle")
    models = (ROOT / "Sources/Shared/Models.swift").read_text()
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
    if 'setStore("dm")' not in tests or 'setStore("edeka")' not in tests:
        fail("tests must setStore dm then edeka")
    if r"groups.map(\.dept)" not in tests:
        fail(r"tests must assert groups.map(\.dept) after setStore")
    if "func walkLines" not in models:
        fail("ListGrouping missing walkLines helper")
    if "enum WalkLine" not in models:
        fail("Models missing WalkLine")
    if "walkListRows" not in models:
        fail("ListGrouping missing walkListRows (store + position ids)")
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
    if "CURRENT_PROJECT_VERSION = 7" not in pbx:
        fail("CURRENT_PROJECT_VERSION must be 7")
    if not re.search(r'\.navigationTitle\(', watch):
        fail("Watch must use navigationTitle")
    title_has_store = "currentStore.name" in watch or (
        "watchTitle" in watch and "var watchTitle" in models and "currentStore.name" in models
    )
    title_has_progress = "progressLabel" in watch or (
        "watchTitle" in watch and "var watchTitle" in models and "progressLabel" in models
    )
    if not title_has_store:
        fail("Watch navigationTitle must include currentStore.name")
    if not title_has_progress:
        fail("Watch navigationTitle must include progressLabel")
    if "watchTitle" in watch and not re.search(r'Einkauf \\\(progressLabel\)', models):
        fail("watchTitle must keep Einkauf plus progressLabel")
    if "topBarTrailing" in watch:
        fail("Watch counter must not use topBarTrailing (clipped under the clock)")
    if "safeAreaInset" in watch:
        fail("Watch must not use a duplicate safeAreaInset header for the counter")
    if re.search(r'Text\("Einkauf"\)', watch):
        fail("Watch must not duplicate Einkauf in a custom header HStack")
    if "toolbar(.hidden)" in watch:
        fail("Watch must not hide the system navigation bar")
    if "var doneCount" not in models or "var progressLabel" not in models:
        fail("AppState missing doneCount/progressLabel")
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
    for wfile in (ROOT / "Sources/Watch").glob("*.swift"):
        wtxt = wfile.read_text()
        if "Backup teilen" in wtxt or "Liste teilen" in wtxt or "UIActivityViewController" in wtxt or "ShareSheet" in wtxt or "ListPDF" in wtxt:
            fail("Watch should not have share UI")
        if "Wörterbuch" in wtxt or "KeywordDictionaryView" in wtxt:
            fail("Watch should not have Wörterbuch UI")
    print("sources: ok")


def test_backup_codec_python() -> None:
    """Sanity: Export-Shape ohne interne Felder."""
    raw = json.loads((ROOT / "Fixtures/einkauf-backup.json").read_text())
    for key in ("kind", "v", "currentStoreId", "stores", "items"):
        if key not in raw:
            fail(f"missing {key}")
    for item in raw["items"]:
        for key in ("id", "name", "dept", "done", "added", "ord"):
            if key not in item:
                fail(f"item missing {key}")
    print("backup shape: ok")


def main() -> None:
    test_fixtures()
    test_store_switch_changes_group_order()
    test_walk_lines_screenshot_items()
    test_sonstiges_follows_layout_position()
    test_backup_codec_python()
    test_sources()
    print("ALL OK")


if __name__ == "__main__":
    main()
