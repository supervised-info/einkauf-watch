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
    """Watch hide-completed chrome under the title (HStack + Spacer, not toolbar)."""
    if re.search(r"ToolbarItem\(placement:\s*\.topBarLeading\)", watch) or "topBarLeading" in watch:
        fail("Watch hide toggle must not sit in topBarLeading (clips Einkauf xx/yy)")
    if "ToolbarItem" in watch:
        fail("Watch must not put the eye in a ToolbarItem")
    for m in re.finditer(r"HStack(?:\s*\([^)]*\))?\s*\{", watch):
        block = extract_braced(watch, m.start(), "Watch eye HStack")
        if "hideCompleted.toggle" in block and "eye.slash" in block:
            if "Spacer()" not in block:
                fail("Watch eye HStack must use Spacer() so the eye is leading under the title")
            btn_pos = block.find("Button")
            spacer_pos = block.find("Spacer()")
            if btn_pos < 0 or spacer_pos < btn_pos:
                fail("Watch eye HStack must be { Button…; Spacer() } (leading, not trailing)")
            if "ForEach" in block or "walkListRows" in block:
                fail("Watch eye must not live inside a walk-list row")
            return block
    fail("Watch hide toggle must sit in an HStack { Button; Spacer() } below the title")
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
    codec = (ROOT / "Sources/Shared/BackupCodec.swift").read_text()
    if "savedLists" not in codec:
        fail("backup codec must mention savedLists")
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
    if "url.scheme == \"einkauf\"" not in content:
        fail("ContentView onOpenURL must ignore widget tap einkauf:// URLs")
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
    if "Build 16" not in desc or "CURRENT_PROJECT_VERSION" not in desc:
        fail("Description.md must name Build 16 / CURRENT_PROJECT_VERSION")
    if "einkauf.watch.hideCompleted" not in desc or "einkauf.iphone.hideCompleted" not in desc:
        fail("Description.md must document separate Watch and iPhone hide-completed AppStorage keys")
    if "Erledigte ausgeblendet" not in desc:
        fail("Description.md must document Erledigte ausgeblendet empty line")
    if "eye.slash" not in desc:
        fail("Description.md must document the Watch eye.slash glyph")
    if not re.search(r"unter de[mn] Titel", desc):
        fail("Description.md must place the Watch eye under the title")
    watch_sec = desc[desc.find("## Watch"):desc.find("### Watch-Complication")]
    if "links" not in watch_sec:
        fail("Description.md must left-align the Watch eye under the title")
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
    watch = (ROOT / "Sources/Watch/WatchListView.swift").read_text()
    if "Picker" in watch:
        fail("Watch should not have a store picker")
    if "deleteStore" in watch:
        fail("Watch must not delete stores")
    if list_id not in watch:
        fail("Watch list must .id(currentStoreId|layout) so store switch rebuilds")
    if "Section {" in watch:
        fail("Watch list must not use List+Section")
    if "ForEach(store.groups)" in watch:
        fail("Watch must not ForEach groups as List sections")
    if "walkListRows(hidingCompleted" not in watch:
        fail("Watch list must use walkListRows(hidingCompleted:) so done items can be filtered")
    if "ForEach(visibleWalkRows)" not in watch and "ForEach(store.walkListRows" not in watch:
        fail("Watch list must ForEach walk list rows (flat store+position ids)")
    if "navigationTitle(store.state.watchTitle)" not in watch:
        fail("Watch navigationTitle must bind to watchTitle")
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
    if "Spacer()" not in eye_bar:
        fail("Watch eye must be leading via Spacer() after the Button under the title")
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
        fail("Watch must use VStack(spacing: 0) so the eye sits tight under the title")
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
    if "Erledigte ausblenden" not in watch or "Erledigte einblenden" not in watch:
        fail("Watch hide toggle missing accessibility labels")
    if "Erledigte ausgeblendet." not in watch:
        fail("Watch must show Erledigte ausgeblendet. when every item is hidden")
    if "fileExporter" in watch or "fileImporter" in watch:
        fail("Watch must not import/export backups")
    if "hideCompleted" in (ROOT / "Sources/Shared/BackupCodec.swift").read_text():
        fail("hideCompleted must not enter BackupCodec / einkauf-backup")
    models = (ROOT / "Sources/Shared/Models.swift").read_text()
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
    if "ForEach(store.editRows)" not in content:
        fail("iPhone Bearbeiten must still ForEach the full editRows")
    if "einkauf.iphone.hideCompleted" not in content:
        fail("iPhone Geh-Modus must persist hideCompleted separately from Watch")
    if "testUserMappingBeatsKeyword" not in tests or "testUserMappingBeatsSpecialRules" not in tests:
        fail("tests must cover user mapping beating keywords and special rules")
    if "testWalkListRowsHidingCompletedDropsDoneItemsAndEmptyHeaders" not in tests:
        fail("tests must cover walkListRows hidingCompleted dropping done items and empty headers")
    if "testWalkListRowsHidingCompletedEmptyWhenAllDone" not in tests:
        fail("tests must cover walkListRows hidingCompleted empty when all done")
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
    if "CURRENT_PROJECT_VERSION = 16" not in pbx:
        fail("CURRENT_PROJECT_VERSION must be 16")
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
    if "CURRENT_PROJECT_VERSION: 16" not in yml:
        fail("project.yml CURRENT_PROJECT_VERSION must be 16")
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
    for key in ("kind", "v", "currentStoreId", "stores", "items"):
        if key not in raw:
            fail(f"missing {key}")
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
    if "progressLabel" not in widget:
        fail("complication must show progressLabel xx/yy")
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
    if "Watch-Complication" not in desc or "accessoryCircular" not in desc:
        fail("Description.md must document the Watch complication families")
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
    if "testEmptyListIsZeroOverZeroNotHidden" not in tests:
        fail("tests must cover empty complication 0/0")
    if "testProgressMatchesWatchTitleAndIncludesVorNach" not in tests:
        fail("tests must cover complication progress including vor/nach")
    if "testGaugeProgressIsZeroWhenEmptyAndFractionOtherwise" not in tests:
        fail("tests must cover Gauge progress 0…1 including empty = 0")
    if "DEVELOPMENT_TEAM = WV26CSTDDR" not in pbx:
        fail("DEVELOPMENT_TEAM must stay WV26CSTDDR")
    if pbx.count("CURRENT_PROJECT_VERSION = 16") < 8:
        fail("all app/extension targets need CURRENT_PROJECT_VERSION 16")
    circular = extract_some_view(widget, "circular")
    corner = extract_some_view(widget, "corner")
    assert_no_large_progress_text(circular, "circular")
    assert_no_large_progress_text(corner, "corner")
    if "Gauge" not in circular:
        fail("circular must use Gauge (0…1) so compact circular families fit")
    if "entry.snapshot.progress" not in circular:
        fail("circular Gauge must use snapshot progress 0…1")
    if "progressLabel" not in circular:
        fail("circular must still expose progressLabel (Gauge label or center)")
    if "containerBackground" not in widget:
        fail("complication view needs containerBackground for watchOS 10")
    if "var progress: Double" not in models:
        fail("ComplicationSnapshot must expose progress 0…1 for the circular Gauge")
    ios_info = (ROOT / "Sources/iOS/Info.plist").read_text()
    if "widgetkit-extension" in ios_info:
        fail("iPhone Info.plist must not declare a WidgetKit extension")
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
        fail("iPhone widget must show progressLabel xx/yy")
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


def main() -> None:
    test_fixtures()
    test_store_switch_changes_group_order()
    test_walk_lines_screenshot_items()
    test_sonstiges_follows_layout_position()
    test_backup_codec_python()
    test_sources()
    test_watch_complication()
    test_iphone_widget()
    print("ALL OK")


if __name__ == "__main__":
    main()
