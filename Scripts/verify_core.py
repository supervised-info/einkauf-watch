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


def groups(items: list[dict], layout: list[str]) -> list[str]:
    layout = [d for d in layout if d in DEPTS and d not in ("vor", "nach", "sonstiges")]
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

    push("vor")
    for d in layout:
        push(d)
    for d in DEPTS:
        if d not in ("vor", "nach", "sonstiges"):
            push(d)
    push("sonstiges")
    push("nach")
    return out


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
        "Sources/iOS/ContentView.swift",
        "Sources/iOS/SettingsSheet.swift",
        "Sources/iOS/ShareSheet.swift",
        "Sources/iOS/AppearanceSettings.swift",
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
    if "func setWalkMode" not in store:
        fail("walkMode not persisted via setWalkMode")
    editing = (ROOT / "Sources/Shared/ItemEditing.swift").read_text()
    if "func moveRows" not in editing:
        fail("ItemEditing missing cross-dept moveRows")
    if "Backup teilen" not in content:
        fail("overflow menu missing Backup teilen")
    if "sheet(item:" not in content:
        fail("Backup teilen must use sheet(item:) with a file URL")
    if "showShare" in content or "if let shareURL" in content:
        fail("Backup teilen still uses isPresented + optional URL")
    if "Text(\"Hell\")" in content or "Text(\"Creme\")" in content:
        fail("theme/palette controls must not be in the list toolbar (ContentView)")
    settings = (ROOT / "Sources/iOS/SettingsSheet.swift").read_text()
    for needle in ("Hell", "Dunkel", "System", "Creme", "Blau", "Darstellung"):
        if needle not in settings:
            fail(f"Einstellungen missing {needle}")
    if "iPhone-Einstellung" not in settings:
        fail("Darstellung hint should mention iPhone-Einstellung for System")
    if "Aktueller Laden" not in settings:
        fail("Einstellungen missing Aktueller Laden picker")
    if "setStore" not in settings:
        fail("Einstellungen store picker must call setStore")
    if "ForEach(store.stores)" not in settings:
        fail("Einstellungen picker must list all stores")
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
    store_src = (ROOT / "Sources/Shared/ShoppingStore.swift").read_text()
    if "func createStore" not in store_src or "func deleteStore" not in store_src:
        fail("ShoppingStore missing createStore/deleteStore")
    watch = (ROOT / "Sources/Watch/WatchListView.swift").read_text()
    if "Picker" in watch:
        fail("Watch should not have a store picker")
    if not re.search(r'navigationTitle\("Einkauf \\\(store\.state\.progressLabel\)"\)', watch):
        fail("Watch navigationTitle must interpolate progressLabel")
    if "topBarTrailing" in watch:
        fail("Watch counter must not use topBarTrailing (clipped under the clock)")
    if "safeAreaInset" in watch:
        fail("Watch must not use a duplicate safeAreaInset header for the counter")
    if re.search(r'Text\("Einkauf"\)', watch):
        fail("Watch must not duplicate Einkauf in a custom header HStack")
    if "toolbar(.hidden)" in watch:
        fail("Watch must not hide the system navigation bar")
    models = (ROOT / "Sources/Shared/Models.swift").read_text()
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
    watch = (ROOT / "Sources/Watch/WatchListView.swift").read_text()
    if "Picker" in watch or "onMove" in watch:
        fail("Watch UI should stay Geh-Modus only")
    for wfile in (ROOT / "Sources/Watch").glob("*.swift"):
        wtxt = wfile.read_text()
        if "Backup teilen" in wtxt or "UIActivityViewController" in wtxt or "ShareSheet" in wtxt:
            fail("Watch should not have backup share UI")
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
    test_backup_codec_python()
    test_sources()
    print("ALL OK")


if __name__ == "__main__":
    main()
