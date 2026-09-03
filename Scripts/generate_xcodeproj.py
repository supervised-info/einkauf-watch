#!/usr/bin/env python3
"""Erzeugt Einkauf.xcodeproj (ohne Xcode)."""
from __future__ import annotations

import hashlib
from pathlib import Path
from textwrap import dedent

ROOT = Path(__file__).resolve().parents[1]


def uid(*parts: str) -> str:
    return hashlib.md5("::".join(parts).encode()).hexdigest()[:24].upper()


def entry(ref: str, comment: str) -> str:
    return f"{ref} /* {comment} */"


def main() -> None:
    ios_swifts = sorted((ROOT / "Sources/iOS").glob("*.swift"))
    watch_swifts = sorted((ROOT / "Sources/Watch").glob("*.swift"))
    watch_objs = sorted((ROOT / "Sources/Watch").glob("*.m"))
    watch_headers = sorted((ROOT / "Sources/Watch").glob("*.h"))
    widget_swifts = sorted((ROOT / "Sources/WatchWidgets").glob("*.swift"))
    ios_widget_swifts = sorted((ROOT / "Sources/iOSWidgets").glob("*.swift"))
    shared_swifts = sorted((ROOT / "Sources/Shared").glob("*.swift"))
    widget_shared_names = {
        "BackupCodec.swift",
        "Department.swift",
        "DepartmentGuesser.swift",
        "KeywordDictionary.swift",
        "Models.swift",
        "Persistence.swift",
        "StoreLayout.swift",
    }
    widget_shared = [p for p in shared_swifts if p.name in widget_shared_names]
    fixture = ROOT / "Fixtures/einkauf-backup.json"
    ios_assets = ROOT / "Sources/iOS/Assets.xcassets"
    watch_assets = ROOT / "Sources/Watch/Assets.xcassets"

    project = uid("project")
    project_cfg = uid("project_cfg")
    ios_target = uid("ios_target")
    watch_target = uid("watch_target")
    widget_target = uid("widget_target")
    ios_widget_target = uid("ios_widget_target")
    ios_cfg = uid("ios_cfg")
    watch_cfg = uid("watch_cfg")
    widget_cfg = uid("widget_cfg")
    ios_widget_cfg = uid("ios_widget_cfg")
    ios_debug = uid("ios_debug")
    ios_release = uid("ios_release")
    watch_debug = uid("watch_debug")
    watch_release = uid("watch_release")
    widget_debug = uid("widget_debug")
    widget_release = uid("widget_release")
    ios_widget_debug = uid("ios_widget_debug")
    ios_widget_release = uid("ios_widget_release")
    proj_debug = uid("proj_debug")
    proj_release = uid("proj_release")

    ios_sources_phase = uid("ios_sources")
    watch_sources_phase = uid("watch_sources")
    widget_sources_phase = uid("widget_sources")
    ios_widget_sources_phase = uid("ios_widget_sources")
    ios_resources_phase = uid("ios_resources")
    watch_resources_phase = uid("watch_resources")
    widget_resources_phase = uid("widget_resources")
    ios_widget_resources_phase = uid("ios_widget_resources")
    ios_frameworks_phase = uid("ios_frameworks")
    watch_frameworks_phase = uid("watch_frameworks")
    widget_frameworks_phase = uid("widget_frameworks")
    ios_widget_frameworks_phase = uid("ios_widget_frameworks")
    embed_watch_phase = uid("embed_watch")
    embed_widget_phase = uid("embed_widget")
    embed_ios_widget_phase = uid("embed_ios_widget")
    container_proxy = uid("container_proxy")
    widget_container_proxy = uid("widget_container_proxy")
    ios_widget_container_proxy = uid("ios_widget_container_proxy")
    target_dep = uid("target_dep")
    widget_target_dep = uid("widget_target_dep")
    ios_widget_target_dep = uid("ios_widget_target_dep")

    ios_product = uid("ios_product")
    watch_product = uid("watch_product")
    widget_product = uid("widget_product")
    ios_widget_product = uid("ios_widget_product")
    watch_embed_build = uid("watch_embed_build")
    widget_embed_build = uid("widget_embed_build")
    ios_widget_embed_build = uid("ios_widget_embed_build")

    wc_ref = uid("watchconnectivity_ref")
    wc_ios = uid("watchconnectivity_ios")
    wc_watch = uid("watchconnectivity_watch")
    widgetkit_ref = uid("widgetkit_ref")
    widgetkit_widget = uid("widgetkit_widget")
    widgetkit_watch = uid("widgetkit_watch")
    widgetkit_ios = uid("widgetkit_ios")
    widgetkit_ios_widget = uid("widgetkit_ios_widget")

    group_root = uid("group_root")
    group_ios = uid("group_ios")
    group_watch = uid("group_watch")
    group_widget = uid("group_widget")
    group_ios_widget = uid("group_ios_widget")
    group_shared = uid("group_shared")
    group_fixtures = uid("group_fixtures")
    group_products = uid("group_products")
    group_frameworks = uid("group_frameworks")
    group_tests = uid("group_tests")

    file_refs: dict[Path, str] = {}
    build_files: dict[str, str] = {}

    def ref_for(path: Path) -> str:
        rel = path.relative_to(ROOT).as_posix()
        if path not in file_refs:
            file_refs[path] = uid("ref", rel)
        return file_refs[path]

    def build_for(path: Path, target: str) -> str:
        key = f"{target}:{path}"
        if key not in build_files:
            build_files[key] = uid("build", target, path.as_posix())
        return build_files[key]

    objects: list[str] = []

    # PBXBuildFile
    objects.append("/* Begin PBXBuildFile section */")
    for p in ios_swifts + shared_swifts:
        bid = build_for(p, "ios")
        objects.append(f"\t\t{bid} /* {p.name} in Sources */ = {{isa = PBXBuildFile; fileRef = {ref_for(p)} /* {p.name} */; }};")
    for p in watch_swifts + watch_objs + shared_swifts:
        bid = build_for(p, "watch")
        objects.append(f"\t\t{bid} /* {p.name} in Sources */ = {{isa = PBXBuildFile; fileRef = {ref_for(p)} /* {p.name} */; }};")
    for p in widget_swifts + widget_shared:
        bid = build_for(p, "widget")
        objects.append(f"\t\t{bid} /* {p.name} in Sources */ = {{isa = PBXBuildFile; fileRef = {ref_for(p)} /* {p.name} */; }};")
    for p in ios_widget_swifts + widget_shared:
        bid = build_for(p, "ios_widget")
        objects.append(f"\t\t{bid} /* {p.name} in Sources */ = {{isa = PBXBuildFile; fileRef = {ref_for(p)} /* {p.name} */; }};")
    objects.append(f"\t\t{build_for(ios_assets, 'ios')} /* Assets.xcassets in Resources */ = {{isa = PBXBuildFile; fileRef = {ref_for(ios_assets)} /* Assets.xcassets */; }};")
    objects.append(f"\t\t{build_for(watch_assets, 'watch')} /* Assets.xcassets in Resources */ = {{isa = PBXBuildFile; fileRef = {ref_for(watch_assets)} /* Assets.xcassets */; }};")
    objects.append(f"\t\t{build_for(fixture, 'ios')} /* einkauf-backup.json in Resources */ = {{isa = PBXBuildFile; fileRef = {ref_for(fixture)} /* einkauf-backup.json */; }};")
    objects.append(f"\t\t{wc_ios} /* WatchConnectivity.framework in Frameworks */ = {{isa = PBXBuildFile; fileRef = {wc_ref} /* WatchConnectivity.framework */; }};")
    objects.append(f"\t\t{wc_watch} /* WatchConnectivity.framework in Frameworks */ = {{isa = PBXBuildFile; fileRef = {wc_ref} /* WatchConnectivity.framework */; }};")
    objects.append(f"\t\t{widgetkit_widget} /* WidgetKit.framework in Frameworks */ = {{isa = PBXBuildFile; fileRef = {widgetkit_ref} /* WidgetKit.framework */; }};")
    objects.append(f"\t\t{widgetkit_watch} /* WidgetKit.framework in Frameworks */ = {{isa = PBXBuildFile; fileRef = {widgetkit_ref} /* WidgetKit.framework */; }};")
    objects.append(f"\t\t{widgetkit_ios} /* WidgetKit.framework in Frameworks */ = {{isa = PBXBuildFile; fileRef = {widgetkit_ref} /* WidgetKit.framework */; }};")
    objects.append(f"\t\t{widgetkit_ios_widget} /* WidgetKit.framework in Frameworks */ = {{isa = PBXBuildFile; fileRef = {widgetkit_ref} /* WidgetKit.framework */; }};")
    objects.append(
        f"\t\t{watch_embed_build} /* EinkaufWatch.app in Embed Watch Content */ = {{isa = PBXBuildFile; fileRef = {watch_product} /* EinkaufWatch.app */; settings = {{ATTRIBUTES = (RemoveHeadersOnCopy, ); }}; }};"
    )
    objects.append(
        f"\t\t{widget_embed_build} /* EinkaufWatchWidgets.appex in Embed Foundation Extensions */ = {{isa = PBXBuildFile; fileRef = {widget_product} /* EinkaufWatchWidgets.appex */; settings = {{ATTRIBUTES = (RemoveHeadersOnCopy, CodeSignOnCopy, ); }}; }};"
    )
    objects.append(
        f"\t\t{ios_widget_embed_build} /* EinkaufWidgets.appex in Embed Foundation Extensions */ = {{isa = PBXBuildFile; fileRef = {ios_widget_product} /* EinkaufWidgets.appex */; settings = {{ATTRIBUTES = (RemoveHeadersOnCopy, CodeSignOnCopy, ); }}; }};"
    )
    objects.append("/* End PBXBuildFile section */\n")

    objects.append("/* Begin PBXContainerItemProxy section */")
    objects.append(
        dedent(
            f"""\
            \t\t{container_proxy} /* PBXContainerItemProxy */ = {{
            \t\t\tisa = PBXContainerItemProxy;
            \t\t\tcontainerPortal = {project} /* Project object */;
            \t\t\tproxyType = 1;
            \t\t\tremoteGlobalIDString = {watch_target};
            \t\t\tremoteInfo = EinkaufWatch;
            \t\t}};
            \t\t{widget_container_proxy} /* PBXContainerItemProxy */ = {{
            \t\t\tisa = PBXContainerItemProxy;
            \t\t\tcontainerPortal = {project} /* Project object */;
            \t\t\tproxyType = 1;
            \t\t\tremoteGlobalIDString = {widget_target};
            \t\t\tremoteInfo = EinkaufWatchWidgets;
            \t\t}};
            \t\t{ios_widget_container_proxy} /* PBXContainerItemProxy */ = {{
            \t\t\tisa = PBXContainerItemProxy;
            \t\t\tcontainerPortal = {project} /* Project object */;
            \t\t\tproxyType = 1;
            \t\t\tremoteGlobalIDString = {ios_widget_target};
            \t\t\tremoteInfo = EinkaufWidgets;
            \t\t}};
            """
        ).rstrip()
    )
    objects.append("/* End PBXContainerItemProxy section */\n")

    objects.append("/* Begin PBXCopyFilesBuildPhase section */")
    objects.append(
        dedent(
            f"""\
            \t\t{embed_watch_phase} /* Embed Watch Content */ = {{
            \t\t\tisa = PBXCopyFilesBuildPhase;
            \t\t\tbuildActionMask = 2147483647;
            \t\t\tdstPath = "$(CONTENTS_FOLDER_PATH)/Watch";
            \t\t\tdstSubfolderSpec = 16;
            \t\t\tfiles = (
            \t\t\t\t{watch_embed_build} /* EinkaufWatch.app in Embed Watch Content */,
            \t\t\t);
            \t\t\tname = "Embed Watch Content";
            \t\t\trunOnlyForDeploymentPostprocessing = 0;
            \t\t}};
            \t\t{embed_widget_phase} /* Embed Foundation Extensions */ = {{
            \t\t\tisa = PBXCopyFilesBuildPhase;
            \t\t\tbuildActionMask = 2147483647;
            \t\t\tdstPath = "";
            \t\t\tdstSubfolderSpec = 13;
            \t\t\tfiles = (
            \t\t\t\t{widget_embed_build} /* EinkaufWatchWidgets.appex in Embed Foundation Extensions */,
            \t\t\t);
            \t\t\tname = "Embed Foundation Extensions";
            \t\t\trunOnlyForDeploymentPostprocessing = 0;
            \t\t}};
            \t\t{embed_ios_widget_phase} /* Embed Foundation Extensions */ = {{
            \t\t\tisa = PBXCopyFilesBuildPhase;
            \t\t\tbuildActionMask = 2147483647;
            \t\t\tdstPath = "";
            \t\t\tdstSubfolderSpec = 13;
            \t\t\tfiles = (
            \t\t\t\t{ios_widget_embed_build} /* EinkaufWidgets.appex in Embed Foundation Extensions */,
            \t\t\t);
            \t\t\tname = "Embed Foundation Extensions";
            \t\t\trunOnlyForDeploymentPostprocessing = 0;
            \t\t}};
            """
        ).rstrip()
    )
    objects.append("/* End PBXCopyFilesBuildPhase section */\n")

    def file_type(path: Path) -> str:
        if path.suffix == ".swift":
            return "sourcecode.swift"
        if path.suffix == ".m":
            return "sourcecode.c.objc"
        if path.suffix == ".h":
            return "sourcecode.c.h"
        if path.suffix == ".json":
            return "text.json"
        if path.suffix == ".entitlements":
            return "text.plist.entitlements"
        if path.suffix == ".plist":
            return "text.plist.xml"
        if path.suffix == ".xcassets":
            return "folder.assetcatalog"
        return "text"

    objects.append("/* Begin PBXFileReference section */")
    objects.append(f"\t\t{ios_product} /* Einkauf.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = Einkauf.app; sourceTree = BUILT_PRODUCTS_DIR; }};")
    objects.append(f"\t\t{watch_product} /* EinkaufWatch.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = EinkaufWatch.app; sourceTree = BUILT_PRODUCTS_DIR; }};")
    objects.append(f"\t\t{widget_product} /* EinkaufWatchWidgets.appex */ = {{isa = PBXFileReference; explicitFileType = \"wrapper.app-extension\"; includeInIndex = 0; path = EinkaufWatchWidgets.appex; sourceTree = BUILT_PRODUCTS_DIR; }};")
    objects.append(f"\t\t{ios_widget_product} /* EinkaufWidgets.appex */ = {{isa = PBXFileReference; explicitFileType = \"wrapper.app-extension\"; includeInIndex = 0; path = EinkaufWidgets.appex; sourceTree = BUILT_PRODUCTS_DIR; }};")
    objects.append(f"\t\t{wc_ref} /* WatchConnectivity.framework */ = {{isa = PBXFileReference; lastKnownFileType = wrapper.framework; name = WatchConnectivity.framework; path = System/Library/Frameworks/WatchConnectivity.framework; sourceTree = SDKROOT; }};")
    objects.append(f"\t\t{widgetkit_ref} /* WidgetKit.framework */ = {{isa = PBXFileReference; lastKnownFileType = wrapper.framework; name = WidgetKit.framework; path = System/Library/Frameworks/WidgetKit.framework; sourceTree = SDKROOT; }};")
    for p in ios_swifts + watch_swifts + watch_objs + watch_headers + widget_swifts + ios_widget_swifts + shared_swifts + [fixture, ios_assets, watch_assets]:
        rel = p.relative_to(ROOT).as_posix()
        name = p.name
        objects.append(
            f"\t\t{ref_for(p)} /* {name} */ = {{isa = PBXFileReference; lastKnownFileType = {file_type(p)}; path = {name}; sourceTree = \"<group>\"; }};"
        )
    # Info.plist refs (not compiled, but visible)
    ios_plist = ROOT / "Sources/iOS/Info.plist"
    ios_entitlements = ROOT / "Sources/iOS/Einkauf.entitlements"
    watch_plist = ROOT / "Sources/Watch/Info.plist"
    watch_entitlements = ROOT / "Sources/Watch/EinkaufWatch.entitlements"
    widget_plist = ROOT / "Sources/WatchWidgets/Info.plist"
    widget_entitlements = ROOT / "Sources/WatchWidgets/EinkaufWatchWidgets.entitlements"
    ios_widget_plist = ROOT / "Sources/iOSWidgets/Info.plist"
    ios_widget_entitlements = ROOT / "Sources/iOSWidgets/EinkaufWidgets.entitlements"
    objects.append(f"\t\t{ref_for(ios_plist)} /* Info.plist */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Info.plist; sourceTree = \"<group>\"; }};")
    objects.append(f"\t\t{ref_for(ios_entitlements)} /* Einkauf.entitlements */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.entitlements; path = Einkauf.entitlements; sourceTree = \"<group>\"; }};")
    objects.append(f"\t\t{ref_for(watch_plist)} /* Info.plist */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Info.plist; sourceTree = \"<group>\"; }};")
    objects.append(f"\t\t{ref_for(watch_entitlements)} /* EinkaufWatch.entitlements */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.entitlements; path = EinkaufWatch.entitlements; sourceTree = \"<group>\"; }};")
    objects.append(f"\t\t{ref_for(widget_plist)} /* Info.plist */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Info.plist; sourceTree = \"<group>\"; }};")
    objects.append(f"\t\t{ref_for(widget_entitlements)} /* EinkaufWatchWidgets.entitlements */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.entitlements; path = EinkaufWatchWidgets.entitlements; sourceTree = \"<group>\"; }};")
    objects.append(f"\t\t{ref_for(ios_widget_plist)} /* Info.plist */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Info.plist; sourceTree = \"<group>\"; }};")
    objects.append(f"\t\t{ref_for(ios_widget_entitlements)} /* EinkaufWidgets.entitlements */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.entitlements; path = EinkaufWidgets.entitlements; sourceTree = \"<group>\"; }};")
    extra_fixture = ROOT / "Fixtures/einkauf-backup-ohne-staples.json"
    objects.append(f"\t\t{ref_for(extra_fixture)} /* einkauf-backup-ohne-staples.json */ = {{isa = PBXFileReference; lastKnownFileType = text.json; path = einkauf-backup-ohne-staples.json; sourceTree = \"<group>\"; }};")
    tests_swift = ROOT / "Tests/EinkaufCoreTests/EinkaufCoreTests.swift"
    objects.append(f"\t\t{ref_for(tests_swift)} /* EinkaufCoreTests.swift */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = EinkaufCoreTests.swift; sourceTree = \"<group>\"; }};")
    objects.append("/* End PBXFileReference section */\n")

    objects.append("/* Begin PBXFrameworksBuildPhase section */")
    objects.append(
        dedent(
            f"""\
            \t\t{ios_frameworks_phase} /* Frameworks */ = {{
            \t\t\tisa = PBXFrameworksBuildPhase;
            \t\t\tbuildActionMask = 2147483647;
            \t\t\tfiles = (
            \t\t\t\t{wc_ios} /* WatchConnectivity.framework in Frameworks */,
            \t\t\t\t{widgetkit_ios} /* WidgetKit.framework in Frameworks */,
            \t\t\t);
            \t\t\trunOnlyForDeploymentPostprocessing = 0;
            \t\t}};
            \t\t{watch_frameworks_phase} /* Frameworks */ = {{
            \t\t\tisa = PBXFrameworksBuildPhase;
            \t\t\tbuildActionMask = 2147483647;
            \t\t\tfiles = (
            \t\t\t\t{wc_watch} /* WatchConnectivity.framework in Frameworks */,
            \t\t\t\t{widgetkit_watch} /* WidgetKit.framework in Frameworks */,
            \t\t\t);
            \t\t\trunOnlyForDeploymentPostprocessing = 0;
            \t\t}};
            \t\t{widget_frameworks_phase} /* Frameworks */ = {{
            \t\t\tisa = PBXFrameworksBuildPhase;
            \t\t\tbuildActionMask = 2147483647;
            \t\t\tfiles = (
            \t\t\t\t{widgetkit_widget} /* WidgetKit.framework in Frameworks */,
            \t\t\t);
            \t\t\trunOnlyForDeploymentPostprocessing = 0;
            \t\t}};
            \t\t{ios_widget_frameworks_phase} /* Frameworks */ = {{
            \t\t\tisa = PBXFrameworksBuildPhase;
            \t\t\tbuildActionMask = 2147483647;
            \t\t\tfiles = (
            \t\t\t\t{widgetkit_ios_widget} /* WidgetKit.framework in Frameworks */,
            \t\t\t);
            \t\t\trunOnlyForDeploymentPostprocessing = 0;
            \t\t}};
            """
        ).rstrip()
    )
    objects.append("/* End PBXFrameworksBuildPhase section */\n")

    def children(paths: list[Path], extra: list[str] | None = None) -> str:
        lines = []
        for p in paths:
            lines.append(f"\t\t\t\t{ref_for(p)} /* {p.name} */,")
        for e in extra or []:
            lines.append(f"\t\t\t\t{e},")
        return "\n".join(lines)

    objects.append("/* Begin PBXGroup section */")
    objects.append(
        dedent(
            f"""\
            \t\t{group_root} = {{
            \t\t\tisa = PBXGroup;
            \t\t\tchildren = (
            \t\t\t\t{group_ios} /* iOS */,
            \t\t\t\t{group_watch} /* Watch */,
            \t\t\t\t{group_widget} /* WatchWidgets */,
            \t\t\t\t{group_ios_widget} /* iOSWidgets */,
            \t\t\t\t{group_shared} /* Shared */,
            \t\t\t\t{group_fixtures} /* Fixtures */,
            \t\t\t\t{group_tests} /* Tests */,
            \t\t\t\t{group_frameworks} /* Frameworks */,
            \t\t\t\t{group_products} /* Products */,
            \t\t\t);
            \t\t\tsourceTree = "<group>";
            \t\t}};
            \t\t{group_products} /* Products */ = {{
            \t\t\tisa = PBXGroup;
            \t\t\tchildren = (
            \t\t\t\t{ios_product} /* Einkauf.app */,
            \t\t\t\t{watch_product} /* EinkaufWatch.app */,
            \t\t\t\t{widget_product} /* EinkaufWatchWidgets.appex */,
            \t\t\t\t{ios_widget_product} /* EinkaufWidgets.appex */,
            \t\t\t);
            \t\t\tname = Products;
            \t\t\tsourceTree = "<group>";
            \t\t}};
            \t\t{group_frameworks} /* Frameworks */ = {{
            \t\t\tisa = PBXGroup;
            \t\t\tchildren = (
            \t\t\t\t{wc_ref} /* WatchConnectivity.framework */,
            \t\t\t\t{widgetkit_ref} /* WidgetKit.framework */,
            \t\t\t);
            \t\t\tname = Frameworks;
            \t\t\tsourceTree = "<group>";
            \t\t}};
            \t\t{group_ios} /* iOS */ = {{
            \t\t\tisa = PBXGroup;
            \t\t\tchildren = (
            {children(ios_swifts + [ios_assets, ios_plist, ios_entitlements])}
            \t\t\t);
            \t\t\tpath = Sources/iOS;
            \t\t\tname = iOS;
            \t\t\tsourceTree = "<group>";
            \t\t}};
            \t\t{group_watch} /* Watch */ = {{
            \t\t\tisa = PBXGroup;
            \t\t\tchildren = (
            {children(watch_swifts + watch_objs + watch_headers + [watch_assets, watch_plist, watch_entitlements])}
            \t\t\t);
            \t\t\tpath = Sources/Watch;
            \t\t\tname = Watch;
            \t\t\tsourceTree = "<group>";
            \t\t}};
            \t\t{group_widget} /* WatchWidgets */ = {{
            \t\t\tisa = PBXGroup;
            \t\t\tchildren = (
            {children(widget_swifts + [widget_plist, widget_entitlements])}
            \t\t\t);
            \t\t\tpath = Sources/WatchWidgets;
            \t\t\tname = WatchWidgets;
            \t\t\tsourceTree = "<group>";
            \t\t}};
            \t\t{group_ios_widget} /* iOSWidgets */ = {{
            \t\t\tisa = PBXGroup;
            \t\t\tchildren = (
            {children(ios_widget_swifts + [ios_widget_plist, ios_widget_entitlements])}
            \t\t\t);
            \t\t\tpath = Sources/iOSWidgets;
            \t\t\tname = iOSWidgets;
            \t\t\tsourceTree = "<group>";
            \t\t}};
            \t\t{group_shared} /* Shared */ = {{
            \t\t\tisa = PBXGroup;
            \t\t\tchildren = (
            {children(shared_swifts)}
            \t\t\t);
            \t\t\tpath = Sources/Shared;
            \t\t\tname = Shared;
            \t\t\tsourceTree = "<group>";
            \t\t}};
            \t\t{group_fixtures} /* Fixtures */ = {{
            \t\t\tisa = PBXGroup;
            \t\t\tchildren = (
            {children([fixture, extra_fixture])}
            \t\t\t);
            \t\t\tpath = Fixtures;
            \t\t\tname = Fixtures;
            \t\t\tsourceTree = "<group>";
            \t\t}};
            \t\t{group_tests} /* Tests */ = {{
            \t\t\tisa = PBXGroup;
            \t\t\tchildren = (
            \t\t\t\t{ref_for(tests_swift)} /* EinkaufCoreTests.swift */,
            \t\t\t);
            \t\t\tpath = Tests/EinkaufCoreTests;
            \t\t\tname = Tests;
            \t\t\tsourceTree = "<group>";
            \t\t}};
            """
        ).rstrip()
    )
    objects.append("/* End PBXGroup section */\n")

    ios_source_entries = "\n".join(
        f"\t\t\t\t{build_for(p, 'ios')} /* {p.name} in Sources */," for p in ios_swifts + shared_swifts
    )
    watch_source_entries = "\n".join(
        f"\t\t\t\t{build_for(p, 'watch')} /* {p.name} in Sources */," for p in watch_swifts + watch_objs + shared_swifts
    )
    widget_source_entries = "\n".join(
        f"\t\t\t\t{build_for(p, 'widget')} /* {p.name} in Sources */," for p in widget_swifts + widget_shared
    )
    ios_widget_source_entries = "\n".join(
        f"\t\t\t\t{build_for(p, 'ios_widget')} /* {p.name} in Sources */," for p in ios_widget_swifts + widget_shared
    )

    objects.append("/* Begin PBXNativeTarget section */")
    objects.append(
        dedent(
            f"""\
            \t\t{ios_target} /* Einkauf */ = {{
            \t\t\tisa = PBXNativeTarget;
            \t\t\tbuildConfigurationList = {ios_cfg} /* Build configuration list for PBXNativeTarget "Einkauf" */;
            \t\t\tbuildPhases = (
            \t\t\t\t{ios_sources_phase} /* Sources */,
            \t\t\t\t{ios_frameworks_phase} /* Frameworks */,
            \t\t\t\t{ios_resources_phase} /* Resources */,
            \t\t\t\t{embed_watch_phase} /* Embed Watch Content */,
            \t\t\t\t{embed_ios_widget_phase} /* Embed Foundation Extensions */,
            \t\t\t);
            \t\t\tbuildRules = (
            \t\t\t);
            \t\t\tdependencies = (
            \t\t\t\t{target_dep} /* PBXTargetDependency */,
            \t\t\t\t{ios_widget_target_dep} /* PBXTargetDependency */,
            \t\t\t);
            \t\t\tname = Einkauf;
            \t\t\tproductName = Einkauf;
            \t\t\tproductReference = {ios_product} /* Einkauf.app */;
            \t\t\tproductType = "com.apple.product-type.application";
            \t\t}};
            \t\t{watch_target} /* EinkaufWatch */ = {{
            \t\t\tisa = PBXNativeTarget;
            \t\t\tbuildConfigurationList = {watch_cfg} /* Build configuration list for PBXNativeTarget "EinkaufWatch" */;
            \t\t\tbuildPhases = (
            \t\t\t\t{watch_sources_phase} /* Sources */,
            \t\t\t\t{watch_frameworks_phase} /* Frameworks */,
            \t\t\t\t{watch_resources_phase} /* Resources */,
            \t\t\t\t{embed_widget_phase} /* Embed Foundation Extensions */,
            \t\t\t);
            \t\t\tbuildRules = (
            \t\t\t);
            \t\t\tdependencies = (
            \t\t\t\t{widget_target_dep} /* PBXTargetDependency */,
            \t\t\t);
            \t\t\tname = EinkaufWatch;
            \t\t\tproductName = EinkaufWatch;
            \t\t\tproductReference = {watch_product} /* EinkaufWatch.app */;
            \t\t\tproductType = "com.apple.product-type.application";
            \t\t}};
            \t\t{widget_target} /* EinkaufWatchWidgets */ = {{
            \t\t\tisa = PBXNativeTarget;
            \t\t\tbuildConfigurationList = {widget_cfg} /* Build configuration list for PBXNativeTarget "EinkaufWatchWidgets" */;
            \t\t\tbuildPhases = (
            \t\t\t\t{widget_sources_phase} /* Sources */,
            \t\t\t\t{widget_frameworks_phase} /* Frameworks */,
            \t\t\t\t{widget_resources_phase} /* Resources */,
            \t\t\t);
            \t\t\tbuildRules = (
            \t\t\t);
            \t\t\tdependencies = (
            \t\t\t);
            \t\t\tname = EinkaufWatchWidgets;
            \t\t\tproductName = EinkaufWatchWidgets;
            \t\t\tproductReference = {widget_product} /* EinkaufWatchWidgets.appex */;
            \t\t\tproductType = "com.apple.product-type.app-extension";
            \t\t}};
            \t\t{ios_widget_target} /* EinkaufWidgets */ = {{
            \t\t\tisa = PBXNativeTarget;
            \t\t\tbuildConfigurationList = {ios_widget_cfg} /* Build configuration list for PBXNativeTarget "EinkaufWidgets" */;
            \t\t\tbuildPhases = (
            \t\t\t\t{ios_widget_sources_phase} /* Sources */,
            \t\t\t\t{ios_widget_frameworks_phase} /* Frameworks */,
            \t\t\t\t{ios_widget_resources_phase} /* Resources */,
            \t\t\t);
            \t\t\tbuildRules = (
            \t\t\t);
            \t\t\tdependencies = (
            \t\t\t);
            \t\t\tname = EinkaufWidgets;
            \t\t\tproductName = EinkaufWidgets;
            \t\t\tproductReference = {ios_widget_product} /* EinkaufWidgets.appex */;
            \t\t\tproductType = "com.apple.product-type.app-extension";
            \t\t}};
            """
        ).rstrip()
    )
    objects.append("/* End PBXNativeTarget section */\n")

    objects.append("/* Begin PBXProject section */")
    objects.append(
        dedent(
            f"""\
            \t\t{project} /* Project object */ = {{
            \t\t\tisa = PBXProject;
            \t\t\tattributes = {{
            \t\t\t\tBuildIndependentTargetsInParallel = 1;
            \t\t\t\tLastSwiftUpdateCheck = 1500;
            \t\t\t\tLastUpgradeCheck = 1500;
            \t\t\t\tTargetAttributes = {{
            \t\t\t\t\t{ios_target} = {{
            \t\t\t\t\t\tCreatedOnToolsVersion = 15.0;
            \t\t\t\t\t\tProvisioningStyle = Automatic;
            \t\t\t\t\t}};
            \t\t\t\t\t{watch_target} = {{
            \t\t\t\t\t\tCreatedOnToolsVersion = 15.0;
            \t\t\t\t\t\tProvisioningStyle = Automatic;
            \t\t\t\t\t}};
            \t\t\t\t\t{widget_target} = {{
            \t\t\t\t\t\tCreatedOnToolsVersion = 15.0;
            \t\t\t\t\t\tProvisioningStyle = Automatic;
            \t\t\t\t\t}};
            \t\t\t\t\t{ios_widget_target} = {{
            \t\t\t\t\t\tCreatedOnToolsVersion = 15.0;
            \t\t\t\t\t\tProvisioningStyle = Automatic;
            \t\t\t\t\t}};
            \t\t\t\t}};
            \t\t\t}};
            \t\t\tbuildConfigurationList = {project_cfg} /* Build configuration list for PBXProject "Einkauf" */;
            \t\t\tcompatibilityVersion = "Xcode 14.0";
            \t\t\tdevelopmentRegion = de;
            \t\t\thasScannedForEncodings = 0;
            \t\t\tknownRegions = (
            \t\t\t\tde,
            \t\t\t\ten,
            \t\t\t\tBase,
            \t\t\t);
            \t\t\tmainGroup = {group_root};
            \t\t\tproductRefGroup = {group_products} /* Products */;
            \t\t\tprojectDirPath = "";
            \t\t\tprojectRoot = "";
            \t\t\ttargets = (
            \t\t\t\t{ios_target} /* Einkauf */,
            \t\t\t\t{watch_target} /* EinkaufWatch */,
            \t\t\t\t{widget_target} /* EinkaufWatchWidgets */,
            \t\t\t\t{ios_widget_target} /* EinkaufWidgets */,
            \t\t\t);
            \t\t}};
            """
        ).rstrip()
    )
    objects.append("/* End PBXProject section */\n")

    objects.append("/* Begin PBXResourcesBuildPhase section */")
    objects.append(
        dedent(
            f"""\
            \t\t{ios_resources_phase} /* Resources */ = {{
            \t\t\tisa = PBXResourcesBuildPhase;
            \t\t\tbuildActionMask = 2147483647;
            \t\t\tfiles = (
            \t\t\t\t{build_for(ios_assets, 'ios')} /* Assets.xcassets in Resources */,
            \t\t\t\t{build_for(fixture, 'ios')} /* einkauf-backup.json in Resources */,
            \t\t\t);
            \t\t\trunOnlyForDeploymentPostprocessing = 0;
            \t\t}};
            \t\t{watch_resources_phase} /* Resources */ = {{
            \t\t\tisa = PBXResourcesBuildPhase;
            \t\t\tbuildActionMask = 2147483647;
            \t\t\tfiles = (
            \t\t\t\t{build_for(watch_assets, 'watch')} /* Assets.xcassets in Resources */,
            \t\t\t);
            \t\t\trunOnlyForDeploymentPostprocessing = 0;
            \t\t}};
            \t\t{widget_resources_phase} /* Resources */ = {{
            \t\t\tisa = PBXResourcesBuildPhase;
            \t\t\tbuildActionMask = 2147483647;
            \t\t\tfiles = (
            \t\t\t);
            \t\t\trunOnlyForDeploymentPostprocessing = 0;
            \t\t}};
            \t\t{ios_widget_resources_phase} /* Resources */ = {{
            \t\t\tisa = PBXResourcesBuildPhase;
            \t\t\tbuildActionMask = 2147483647;
            \t\t\tfiles = (
            \t\t\t);
            \t\t\trunOnlyForDeploymentPostprocessing = 0;
            \t\t}};
            """
        ).rstrip()
    )
    objects.append("/* End PBXResourcesBuildPhase section */\n")

    objects.append("/* Begin PBXSourcesBuildPhase section */")
    objects.append(
        f"""\t\t{ios_sources_phase} /* Sources */ = {{
\t\t\tisa = PBXSourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
{ios_source_entries}
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
\t\t{watch_sources_phase} /* Sources */ = {{
\t\t\tisa = PBXSourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
{watch_source_entries}
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
\t\t{widget_sources_phase} /* Sources */ = {{
\t\t\tisa = PBXSourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
{widget_source_entries}
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
\t\t{ios_widget_sources_phase} /* Sources */ = {{
\t\t\tisa = PBXSourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
{ios_widget_source_entries}
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};"""
    )
    objects.append("/* End PBXSourcesBuildPhase section */\n")

    objects.append("/* Begin PBXTargetDependency section */")
    objects.append(
        dedent(
            f"""\
            \t\t{target_dep} /* PBXTargetDependency */ = {{
            \t\t\tisa = PBXTargetDependency;
            \t\t\ttarget = {watch_target} /* EinkaufWatch */;
            \t\t\ttargetProxy = {container_proxy} /* PBXContainerItemProxy */;
            \t\t}};
            \t\t{widget_target_dep} /* PBXTargetDependency */ = {{
            \t\t\tisa = PBXTargetDependency;
            \t\t\ttarget = {widget_target} /* EinkaufWatchWidgets */;
            \t\t\ttargetProxy = {widget_container_proxy} /* PBXContainerItemProxy */;
            \t\t}};
            \t\t{ios_widget_target_dep} /* PBXTargetDependency */ = {{
            \t\t\tisa = PBXTargetDependency;
            \t\t\ttarget = {ios_widget_target} /* EinkaufWidgets */;
            \t\t\ttargetProxy = {ios_widget_container_proxy} /* PBXContainerItemProxy */;
            \t\t}};
            """
        ).rstrip()
    )
    objects.append("/* End PBXTargetDependency section */\n")

    common_debug = """
				ALWAYS_SEARCH_USER_PATHS = NO;
				CLANG_ANALYZER_NONNULL = YES;
				CLANG_ANALYZER_NUMBER_OBJECT_CONVERSION = YES_AGGRESSIVE;
				CLANG_CXX_LANGUAGE_STANDARD = "gnu++20";
				CLANG_ENABLE_MODULES = YES;
				CLANG_ENABLE_OBJC_ARC = YES;
				CLANG_WARN_BLOCK_CAPTURE_AUTORELEASING = YES;
				CLANG_WARN_BOOL_CONVERSION = YES;
				CLANG_WARN_COMMA = YES;
				CLANG_WARN_CONSTANT_CONVERSION = YES;
				CLANG_WARN_DEPRECATED_OBJC_IMPLEMENTATIONS = YES;
				CLANG_WARN_DIRECT_OBJC_ISA_USAGE = YES_ERROR;
				CLANG_WARN_DOCUMENTATION_COMMENTS = YES;
				CLANG_WARN_EMPTY_BODY = YES;
				CLANG_WARN_ENUM_CONVERSION = YES;
				CLANG_WARN_INFINITE_RECURSION = YES;
				CLANG_WARN_INT_CONVERSION = YES;
				CLANG_WARN_NON_LITERAL_NULL_CONVERSION = YES;
				CLANG_WARN_OBJC_IMPLICIT_RETAIN_SELF = YES;
				CLANG_WARN_OBJC_LITERAL_CONVERSION = YES;
				CLANG_WARN_OBJC_ROOT_CLASS = YES_ERROR;
				CLANG_WARN_QUOTED_INCLUDE_IN_FRAMEWORK_HEADER = YES;
				CLANG_WARN_RANGE_LOOP_ANALYSIS = YES;
				CLANG_WARN_STRICT_PROTOTYPES = YES;
				CLANG_WARN_SUSPICIOUS_MOVE = YES;
				CLANG_WARN_UNGUARDED_AVAILABILITY = YES_AGGRESSIVE;
				CLANG_WARN_UNREACHABLE_CODE = YES;
				CLANG_WARN__DUPLICATE_METHOD_MATCH = YES;
				COPY_PHASE_STRIP = NO;
				DEBUG_INFORMATION_FORMAT = dwarf;
				ENABLE_STRICT_OBJC_MSGSEND = YES;
				ENABLE_TESTABILITY = YES;
				GCC_C_LANGUAGE_STANDARD = gnu17;
				GCC_DYNAMIC_NO_PIC = NO;
				GCC_NO_COMMON_BLOCKS = YES;
				GCC_OPTIMIZATION_LEVEL = 0;
				GCC_PREPROCESSOR_DEFINITIONS = (
					"DEBUG=1",
					"$(inherited)",
				);
				GCC_WARN_64_TO_32_BIT_CONVERSION = YES;
				GCC_WARN_ABOUT_RETURN_TYPE = YES_ERROR;
				GCC_WARN_UNDECLARED_SELECTOR = YES;
				GCC_WARN_UNINITIALIZED_AUTOS = YES_AGGRESSIVE;
				GCC_WARN_UNUSED_FUNCTION = YES;
				GCC_WARN_UNUSED_VARIABLE = YES;
				IPHONEOS_DEPLOYMENT_TARGET = 17.0;
				LOCALIZATION_PREFERS_STRING_CATALOGS = YES;
				MTL_ENABLE_DEBUG_INFO = INCLUDE_SOURCE;
				ONLY_ACTIVE_ARCH = YES;
				SWIFT_ACTIVE_COMPILATION_CONDITIONS = "DEBUG $(inherited)";
				SWIFT_OPTIMIZATION_LEVEL = "-Onone";
				SWIFT_VERSION = 5.0;
				WATCHOS_DEPLOYMENT_TARGET = 10.0;
"""
    common_release = common_debug.replace("DEBUG_INFORMATION_FORMAT = dwarf;", "DEBUG_INFORMATION_FORMAT = \"dwarf-with-dsym\";")
    common_release = common_release.replace("ENABLE_TESTABILITY = YES;", "ENABLE_NS_ASSERTIONS = NO;")
    common_release = common_release.replace("GCC_DYNAMIC_NO_PIC = NO;\n", "")
    common_release = common_release.replace("GCC_OPTIMIZATION_LEVEL = 0;\n", "")
    common_release = common_release.replace(
        """				GCC_PREPROCESSOR_DEFINITIONS = (
					"DEBUG=1",
					"$(inherited)",
				);
""",
        "",
    )
    common_release = common_release.replace("MTL_ENABLE_DEBUG_INFO = INCLUDE_SOURCE;", "MTL_ENABLE_DEBUG_INFO = NO;")
    common_release = common_release.replace("ONLY_ACTIVE_ARCH = YES;\n", "")
    common_release = common_release.replace(
        'SWIFT_ACTIVE_COMPILATION_CONDITIONS = "DEBUG $(inherited)";\n\t\t\t\tSWIFT_OPTIMIZATION_LEVEL = "-Onone";',
        'SWIFT_COMPILATION_MODE = wholemodule;\n\t\t\t\tSWIFT_OPTIMIZATION_LEVEL = "-O";',
    )

    objects.append("/* Begin XCBuildConfiguration section */")
    objects.append(
        f"""\t\t{proj_debug} /* Debug */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{{common_debug}\t\t\t}};
\t\t\tname = Debug;
\t\t}};
\t\t{proj_release} /* Release */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{{common_release}\t\t\t}};
\t\t\tname = Release;
\t\t}};
\t\t{ios_debug} /* Debug */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
\t\t\t\tASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
\t\t\t\tASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;
\t\t\t\tCODE_SIGN_ENTITLEMENTS = Sources/iOS/Einkauf.entitlements;
\t\t\t\tCODE_SIGN_STYLE = Automatic;
\t\t\t\tCURRENT_PROJECT_VERSION = 24;
\t\t\t\tDEVELOPMENT_TEAM = WV26CSTDDR;
\t\t\t\tENABLE_PREVIEWS = YES;
\t\t\t\tGENERATE_INFOPLIST_FILE = YES;
\t\t\t\tINFOPLIST_FILE = Sources/iOS/Info.plist;
\t\t\t\tINFOPLIST_KEY_CFBundleDisplayName = Einkauf;
\t\t\t\tINFOPLIST_KEY_LSApplicationCategoryType = "public.app-category.shopping";
\t\t\t\tINFOPLIST_KEY_UIApplicationSceneManifest_Generation = YES;
\t\t\t\tINFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents = YES;
\t\t\t\tINFOPLIST_KEY_UILaunchScreen_Generation = YES;
\t\t\t\tINFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone = UIInterfaceOrientationPortrait;
\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 17.0;
\t\t\t\tLD_RUNPATH_SEARCH_PATHS = (
\t\t\t\t\t"$(inherited)",
\t\t\t\t\t"@executable_path/Frameworks",
\t\t\t\t);
\t\t\t\tMARKETING_VERSION = 1.0;
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = net.tschelle.einkauf;
\t\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";
\t\t\t\tSDKROOT = iphoneos;
\t\t\t\tSUPPORTED_PLATFORMS = "iphoneos iphonesimulator";
\t\t\t\tSUPPORTS_MACCATALYST = NO;
\t\t\t\tSWIFT_EMIT_LOC_STRINGS = YES;
\t\t\t\tSWIFT_VERSION = 5.0;
\t\t\t\tTARGETED_DEVICE_FAMILY = 1;
\t\t\t}};
\t\t\tname = Debug;
\t\t}};
\t\t{ios_release} /* Release */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
\t\t\t\tASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
\t\t\t\tASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;
\t\t\t\tCODE_SIGN_ENTITLEMENTS = Sources/iOS/Einkauf.entitlements;
\t\t\t\tCODE_SIGN_STYLE = Automatic;
\t\t\t\tCURRENT_PROJECT_VERSION = 24;
\t\t\t\tDEVELOPMENT_TEAM = WV26CSTDDR;
\t\t\t\tENABLE_PREVIEWS = YES;
\t\t\t\tGENERATE_INFOPLIST_FILE = YES;
\t\t\t\tINFOPLIST_FILE = Sources/iOS/Info.plist;
\t\t\t\tINFOPLIST_KEY_CFBundleDisplayName = Einkauf;
\t\t\t\tINFOPLIST_KEY_LSApplicationCategoryType = "public.app-category.shopping";
\t\t\t\tINFOPLIST_KEY_UIApplicationSceneManifest_Generation = YES;
\t\t\t\tINFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents = YES;
\t\t\t\tINFOPLIST_KEY_UILaunchScreen_Generation = YES;
\t\t\t\tINFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone = UIInterfaceOrientationPortrait;
\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 17.0;
\t\t\t\tLD_RUNPATH_SEARCH_PATHS = (
\t\t\t\t\t"$(inherited)",
\t\t\t\t\t"@executable_path/Frameworks",
\t\t\t\t);
\t\t\t\tMARKETING_VERSION = 1.0;
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = net.tschelle.einkauf;
\t\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";
\t\t\t\tSDKROOT = iphoneos;
\t\t\t\tSUPPORTED_PLATFORMS = "iphoneos iphonesimulator";
\t\t\t\tSUPPORTS_MACCATALYST = NO;
\t\t\t\tSWIFT_EMIT_LOC_STRINGS = YES;
\t\t\t\tSWIFT_VERSION = 5.0;
\t\t\t\tTARGETED_DEVICE_FAMILY = 1;
\t\t\t\tVALIDATE_PRODUCT = YES;
\t\t\t}};
\t\t\tname = Release;
\t\t}};
\t\t{watch_debug} /* Debug */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
\t\t\t\tASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
\t\t\t\tCODE_SIGN_ENTITLEMENTS = Sources/Watch/EinkaufWatch.entitlements;
\t\t\t\tCODE_SIGN_STYLE = Automatic;
\t\t\t\tCURRENT_PROJECT_VERSION = 24;
\t\t\t\tDEVELOPMENT_TEAM = WV26CSTDDR;
\t\t\t\tENABLE_PREVIEWS = YES;
\t\t\t\tGENERATE_INFOPLIST_FILE = YES;
\t\t\t\tINFOPLIST_FILE = Sources/Watch/Info.plist;
\t\t\t\tINFOPLIST_KEY_CFBundleDisplayName = Einkauf;
\t\t\t\tINFOPLIST_KEY_WKCompanionAppBundleIdentifier = net.tschelle.einkauf;
\t\t\t\tINFOPLIST_KEY_WKApplication = YES;
\t\t\t\tINFOPLIST_KEY_WKRunsIndependentlyOfCompanionApp = YES;
\t\t\t\tLD_RUNPATH_SEARCH_PATHS = (
\t\t\t\t\t"$(inherited)",
\t\t\t\t\t"@executable_path/Frameworks",
\t\t\t\t);
\t\t\t\tMARKETING_VERSION = 1.0;
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = net.tschelle.einkauf.watchkitapp;
\t\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";
\t\t\t\tSDKROOT = watchos;
\t\t\t\tSKIP_INSTALL = YES;
\t\t\t\tSUPPORTED_PLATFORMS = "watchos watchsimulator";
\t\t\t\tSWIFT_EMIT_LOC_STRINGS = YES;
\t\t\t\tSWIFT_VERSION = 5.0;
\t\t\t\tTARGETED_DEVICE_FAMILY = 4;
\t\t\t\tWATCHOS_DEPLOYMENT_TARGET = 10.0;
\t\t\t}};
\t\t\tname = Debug;
\t\t}};
\t\t{watch_release} /* Release */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
\t\t\t\tASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
\t\t\t\tCODE_SIGN_ENTITLEMENTS = Sources/Watch/EinkaufWatch.entitlements;
\t\t\t\tCODE_SIGN_STYLE = Automatic;
\t\t\t\tCURRENT_PROJECT_VERSION = 24;
\t\t\t\tDEVELOPMENT_TEAM = WV26CSTDDR;
\t\t\t\tENABLE_PREVIEWS = YES;
\t\t\t\tGENERATE_INFOPLIST_FILE = YES;
\t\t\t\tINFOPLIST_FILE = Sources/Watch/Info.plist;
\t\t\t\tINFOPLIST_KEY_CFBundleDisplayName = Einkauf;
\t\t\t\tINFOPLIST_KEY_WKCompanionAppBundleIdentifier = net.tschelle.einkauf;
\t\t\t\tINFOPLIST_KEY_WKApplication = YES;
\t\t\t\tINFOPLIST_KEY_WKRunsIndependentlyOfCompanionApp = YES;
\t\t\t\tLD_RUNPATH_SEARCH_PATHS = (
\t\t\t\t\t"$(inherited)",
\t\t\t\t\t"@executable_path/Frameworks",
\t\t\t\t);
\t\t\t\tMARKETING_VERSION = 1.0;
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = net.tschelle.einkauf.watchkitapp;
\t\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";
\t\t\t\tSDKROOT = watchos;
\t\t\t\tSKIP_INSTALL = YES;
\t\t\t\tSUPPORTED_PLATFORMS = "watchos watchsimulator";
\t\t\t\tSWIFT_EMIT_LOC_STRINGS = YES;
\t\t\t\tSWIFT_VERSION = 5.0;
\t\t\t\tTARGETED_DEVICE_FAMILY = 4;
\t\t\t\tVALIDATE_PRODUCT = YES;
\t\t\t\tWATCHOS_DEPLOYMENT_TARGET = 10.0;
\t\t\t}};
\t\t\tname = Release;
\t\t}};
\t\t{widget_debug} /* Debug */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
\t\t\t\tAPPLICATION_EXTENSION_API_ONLY = YES;
\t\t\t\tCODE_SIGN_ENTITLEMENTS = Sources/WatchWidgets/EinkaufWatchWidgets.entitlements;
\t\t\t\tCODE_SIGN_STYLE = Automatic;
\t\t\t\tCURRENT_PROJECT_VERSION = 24;
\t\t\t\tDEVELOPMENT_TEAM = WV26CSTDDR;
\t\t\t\tGENERATE_INFOPLIST_FILE = YES;
\t\t\t\tINFOPLIST_FILE = Sources/WatchWidgets/Info.plist;
\t\t\t\tINFOPLIST_KEY_CFBundleDisplayName = Einkauf;
\t\t\t\tINFOPLIST_KEY_NSExtension_NSExtensionPointIdentifier = "com.apple.widgetkit-extension";
\t\t\t\tLD_RUNPATH_SEARCH_PATHS = (
\t\t\t\t\t"$(inherited)",
\t\t\t\t\t"@executable_path/Frameworks",
\t\t\t\t\t"@executable_path/../../Frameworks",
\t\t\t\t);
\t\t\t\tMARKETING_VERSION = 1.0;
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = net.tschelle.einkauf.watchkitapp.widgets;
\t\t\t\tPRODUCT_NAME = EinkaufWatchWidgets;
\t\t\t\tSDKROOT = watchos;
\t\t\t\tSKIP_INSTALL = YES;
\t\t\t\tSUPPORTED_PLATFORMS = "watchos watchsimulator";
\t\t\t\tSWIFT_EMIT_LOC_STRINGS = YES;
\t\t\t\tSWIFT_VERSION = 5.0;
\t\t\t\tTARGETED_DEVICE_FAMILY = 4;
\t\t\t\tWATCHOS_DEPLOYMENT_TARGET = 10.0;
\t\t\t}};
\t\t\tname = Debug;
\t\t}};
\t\t{widget_release} /* Release */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
\t\t\t\tAPPLICATION_EXTENSION_API_ONLY = YES;
\t\t\t\tCODE_SIGN_ENTITLEMENTS = Sources/WatchWidgets/EinkaufWatchWidgets.entitlements;
\t\t\t\tCODE_SIGN_STYLE = Automatic;
\t\t\t\tCURRENT_PROJECT_VERSION = 24;
\t\t\t\tDEVELOPMENT_TEAM = WV26CSTDDR;
\t\t\t\tGENERATE_INFOPLIST_FILE = YES;
\t\t\t\tINFOPLIST_FILE = Sources/WatchWidgets/Info.plist;
\t\t\t\tINFOPLIST_KEY_CFBundleDisplayName = Einkauf;
\t\t\t\tINFOPLIST_KEY_NSExtension_NSExtensionPointIdentifier = "com.apple.widgetkit-extension";
\t\t\t\tLD_RUNPATH_SEARCH_PATHS = (
\t\t\t\t\t"$(inherited)",
\t\t\t\t\t"@executable_path/Frameworks",
\t\t\t\t\t"@executable_path/../../Frameworks",
\t\t\t\t);
\t\t\t\tMARKETING_VERSION = 1.0;
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = net.tschelle.einkauf.watchkitapp.widgets;
\t\t\t\tPRODUCT_NAME = EinkaufWatchWidgets;
\t\t\t\tSDKROOT = watchos;
\t\t\t\tSKIP_INSTALL = YES;
\t\t\t\tSUPPORTED_PLATFORMS = "watchos watchsimulator";
\t\t\t\tSWIFT_EMIT_LOC_STRINGS = YES;
\t\t\t\tSWIFT_VERSION = 5.0;
\t\t\t\tTARGETED_DEVICE_FAMILY = 4;
\t\t\t\tVALIDATE_PRODUCT = YES;
\t\t\t\tWATCHOS_DEPLOYMENT_TARGET = 10.0;
\t\t\t}};
\t\t\tname = Release;
\t\t}};
\t\t{ios_widget_debug} /* Debug */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
\t\t\t\tAPPLICATION_EXTENSION_API_ONLY = YES;
\t\t\t\tCODE_SIGN_ENTITLEMENTS = Sources/iOSWidgets/EinkaufWidgets.entitlements;
\t\t\t\tCODE_SIGN_STYLE = Automatic;
\t\t\t\tCURRENT_PROJECT_VERSION = 24;
\t\t\t\tDEVELOPMENT_TEAM = WV26CSTDDR;
\t\t\t\tGENERATE_INFOPLIST_FILE = YES;
\t\t\t\tINFOPLIST_FILE = Sources/iOSWidgets/Info.plist;
\t\t\t\tINFOPLIST_KEY_CFBundleDisplayName = Einkauf;
\t\t\t\tINFOPLIST_KEY_NSExtension_NSExtensionPointIdentifier = "com.apple.widgetkit-extension";
\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 17.0;
\t\t\t\tLD_RUNPATH_SEARCH_PATHS = (
\t\t\t\t\t"$(inherited)",
\t\t\t\t\t"@executable_path/Frameworks",
\t\t\t\t\t"@executable_path/../../Frameworks",
\t\t\t\t);
\t\t\t\tMARKETING_VERSION = 1.0;
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = net.tschelle.einkauf.widgets;
\t\t\t\tPRODUCT_NAME = EinkaufWidgets;
\t\t\t\tSDKROOT = iphoneos;
\t\t\t\tSKIP_INSTALL = YES;
\t\t\t\tSUPPORTED_PLATFORMS = "iphoneos iphonesimulator";
\t\t\t\tSUPPORTS_MACCATALYST = NO;
\t\t\t\tSWIFT_EMIT_LOC_STRINGS = YES;
\t\t\t\tSWIFT_VERSION = 5.0;
\t\t\t\tTARGETED_DEVICE_FAMILY = 1;
\t\t\t}};
\t\t\tname = Debug;
\t\t}};
\t\t{ios_widget_release} /* Release */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
\t\t\t\tAPPLICATION_EXTENSION_API_ONLY = YES;
\t\t\t\tCODE_SIGN_ENTITLEMENTS = Sources/iOSWidgets/EinkaufWidgets.entitlements;
\t\t\t\tCODE_SIGN_STYLE = Automatic;
\t\t\t\tCURRENT_PROJECT_VERSION = 24;
\t\t\t\tDEVELOPMENT_TEAM = WV26CSTDDR;
\t\t\t\tGENERATE_INFOPLIST_FILE = YES;
\t\t\t\tINFOPLIST_FILE = Sources/iOSWidgets/Info.plist;
\t\t\t\tINFOPLIST_KEY_CFBundleDisplayName = Einkauf;
\t\t\t\tINFOPLIST_KEY_NSExtension_NSExtensionPointIdentifier = "com.apple.widgetkit-extension";
\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 17.0;
\t\t\t\tLD_RUNPATH_SEARCH_PATHS = (
\t\t\t\t\t"$(inherited)",
\t\t\t\t\t"@executable_path/Frameworks",
\t\t\t\t\t"@executable_path/../../Frameworks",
\t\t\t\t);
\t\t\t\tMARKETING_VERSION = 1.0;
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = net.tschelle.einkauf.widgets;
\t\t\t\tPRODUCT_NAME = EinkaufWidgets;
\t\t\t\tSDKROOT = iphoneos;
\t\t\t\tSKIP_INSTALL = YES;
\t\t\t\tSUPPORTED_PLATFORMS = "iphoneos iphonesimulator";
\t\t\t\tSUPPORTS_MACCATALYST = NO;
\t\t\t\tSWIFT_EMIT_LOC_STRINGS = YES;
\t\t\t\tSWIFT_VERSION = 5.0;
\t\t\t\tTARGETED_DEVICE_FAMILY = 1;
\t\t\t\tVALIDATE_PRODUCT = YES;
\t\t\t}};
\t\t\tname = Release;
\t\t}};
"""
    )
    objects.append("/* End XCBuildConfiguration section */\n")

    objects.append("/* Begin XCConfigurationList section */")
    objects.append(
        dedent(
            f"""\
            \t\t{project_cfg} /* Build configuration list for PBXProject "Einkauf" */ = {{
            \t\t\tisa = XCConfigurationList;
            \t\t\tbuildConfigurations = (
            \t\t\t\t{proj_debug} /* Debug */,
            \t\t\t\t{proj_release} /* Release */,
            \t\t\t);
            \t\t\tdefaultConfigurationIsVisible = 0;
            \t\t\tdefaultConfigurationName = Release;
            \t\t}};
            \t\t{ios_cfg} /* Build configuration list for PBXNativeTarget "Einkauf" */ = {{
            \t\t\tisa = XCConfigurationList;
            \t\t\tbuildConfigurations = (
            \t\t\t\t{ios_debug} /* Debug */,
            \t\t\t\t{ios_release} /* Release */,
            \t\t\t);
            \t\t\tdefaultConfigurationIsVisible = 0;
            \t\t\tdefaultConfigurationName = Release;
            \t\t}};
            \t\t{watch_cfg} /* Build configuration list for PBXNativeTarget "EinkaufWatch" */ = {{
            \t\t\tisa = XCConfigurationList;
            \t\t\tbuildConfigurations = (
            \t\t\t\t{watch_debug} /* Debug */,
            \t\t\t\t{watch_release} /* Release */,
            \t\t\t);
            \t\t\tdefaultConfigurationIsVisible = 0;
            \t\t\tdefaultConfigurationName = Release;
            \t\t}};
            \t\t{widget_cfg} /* Build configuration list for PBXNativeTarget "EinkaufWatchWidgets" */ = {{
            \t\t\tisa = XCConfigurationList;
            \t\t\tbuildConfigurations = (
            \t\t\t\t{widget_debug} /* Debug */,
            \t\t\t\t{widget_release} /* Release */,
            \t\t\t);
            \t\t\tdefaultConfigurationIsVisible = 0;
            \t\t\tdefaultConfigurationName = Release;
            \t\t}};
            \t\t{ios_widget_cfg} /* Build configuration list for PBXNativeTarget "EinkaufWidgets" */ = {{
            \t\t\tisa = XCConfigurationList;
            \t\t\tbuildConfigurations = (
            \t\t\t\t{ios_widget_debug} /* Debug */,
            \t\t\t\t{ios_widget_release} /* Release */,
            \t\t\t);
            \t\t\tdefaultConfigurationIsVisible = 0;
            \t\t\tdefaultConfigurationName = Release;
            \t\t}};
            """
        ).rstrip()
    )
    objects.append("/* End XCConfigurationList section */")

    pbx = "\n".join(
        [
            "// !$*UTF8*$!",
            "{",
            "\tarchiveVersion = 1;",
            "\tclasses = {",
            "\t};",
            "\tobjectVersion = 56;",
            "\tobjects = {",
            "",
            *objects,
            "\t};",
            f"\trootObject = {project} /* Project object */;",
            "}",
            "",
        ]
    )

    proj_dir = ROOT / "Einkauf.xcodeproj"
    (proj_dir / "project.xcworkspace").mkdir(parents=True, exist_ok=True)
    (proj_dir / "xcshareddata/xcschemes").mkdir(parents=True, exist_ok=True)
    (proj_dir / "project.pbxproj").write_text(pbx)
    (proj_dir / "project.xcworkspace/contents.xcworkspacedata").write_text(
        """<?xml version="1.0" encoding="UTF-8"?>
<Workspace
   version = "1.0">
   <FileRef
      location = "self:">
   </FileRef>
</Workspace>
"""
    )
    scheme = f"""<?xml version="1.0" encoding="UTF-8"?>
<Scheme
   LastUpgradeVersion = "1500"
   version = "1.7">
   <BuildAction
      parallelizeBuildables = "YES"
      buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry
            buildForTesting = "YES"
            buildForRunning = "YES"
            buildForProfiling = "YES"
            buildForArchiving = "YES"
            buildForAnalyzing = "YES">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "{watch_target}"
               BuildableName = "EinkaufWatch.app"
               BlueprintName = "EinkaufWatch"
               ReferencedContainer = "container:Einkauf.xcodeproj">
            </BuildableReference>
         </BuildActionEntry>
         <BuildActionEntry
            buildForTesting = "YES"
            buildForRunning = "YES"
            buildForProfiling = "YES"
            buildForArchiving = "YES"
            buildForAnalyzing = "YES">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "{ios_target}"
               BuildableName = "Einkauf.app"
               BlueprintName = "Einkauf"
               ReferencedContainer = "container:Einkauf.xcodeproj">
            </BuildableReference>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      shouldUseLaunchSchemeArgsEnv = "YES"
      shouldAutocreateTestPlan = "YES">
   </TestAction>
   <LaunchAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      launchStyle = "0"
      useCustomWorkingDirectory = "NO"
      ignoresPersistentStateOnLaunch = "NO"
      debugDocumentVersioning = "YES"
      debugServiceExtension = "internal"
      allowLocationSimulation = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "{ios_target}"
            BuildableName = "Einkauf.app"
            BlueprintName = "Einkauf"
            ReferencedContainer = "container:Einkauf.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction
      buildConfiguration = "Release"
      shouldUseLaunchSchemeArgsEnv = "YES"
      savedToolIdentifier = ""
      useCustomWorkingDirectory = "NO"
      debugDocumentVersioning = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "{ios_target}"
            BuildableName = "Einkauf.app"
            BlueprintName = "Einkauf"
            ReferencedContainer = "container:Einkauf.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction
      buildConfiguration = "Debug">
   </AnalyzeAction>
   <ArchiveAction
      buildConfiguration = "Release"
      revealArchiveInOrganizer = "YES">
   </ArchiveAction>
</Scheme>
"""
    (proj_dir / "xcshareddata/xcschemes/Einkauf.xcscheme").write_text(scheme)
    watch_scheme = scheme.replace(
        f'BlueprintIdentifier = "{ios_target}"',
        f'BlueprintIdentifier = "{watch_target}"',
    ).replace("BuildableName = \"Einkauf.app\"", "BuildableName = \"EinkaufWatch.app\"").replace(
        "BlueprintName = \"Einkauf\"", "BlueprintName = \"EinkaufWatch\""
    )
    # Keep both build entries; only change launch/profile runnable. The naive replace hits build entries too.
    # Write a dedicated watch scheme instead.
    watch_scheme = f"""<?xml version="1.0" encoding="UTF-8"?>
<Scheme
   LastUpgradeVersion = "1500"
   version = "1.7">
   <BuildAction
      parallelizeBuildables = "YES"
      buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry
            buildForTesting = "YES"
            buildForRunning = "YES"
            buildForProfiling = "YES"
            buildForArchiving = "YES"
            buildForAnalyzing = "YES">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "{watch_target}"
               BuildableName = "EinkaufWatch.app"
               BlueprintName = "EinkaufWatch"
               ReferencedContainer = "container:Einkauf.xcodeproj">
            </BuildableReference>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      shouldUseLaunchSchemeArgsEnv = "YES"
      shouldAutocreateTestPlan = "YES">
   </TestAction>
   <LaunchAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      launchStyle = "0"
      useCustomWorkingDirectory = "NO"
      ignoresPersistentStateOnLaunch = "NO"
      debugDocumentVersioning = "YES"
      debugServiceExtension = "internal"
      allowLocationSimulation = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "{watch_target}"
            BuildableName = "EinkaufWatch.app"
            BlueprintName = "EinkaufWatch"
            ReferencedContainer = "container:Einkauf.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction
      buildConfiguration = "Release"
      shouldUseLaunchSchemeArgsEnv = "YES"
      savedToolIdentifier = ""
      useCustomWorkingDirectory = "NO"
      debugDocumentVersioning = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "{watch_target}"
            BuildableName = "EinkaufWatch.app"
            BlueprintName = "EinkaufWatch"
            ReferencedContainer = "container:Einkauf.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction
      buildConfiguration = "Debug">
   </AnalyzeAction>
   <ArchiveAction
      buildConfiguration = "Release"
      revealArchiveInOrganizer = "YES">
   </ArchiveAction>
</Scheme>
"""
    (proj_dir / "xcshareddata/xcschemes/EinkaufWatch.xcscheme").write_text(watch_scheme)
    print(f"Wrote {proj_dir / 'project.pbxproj'}")
    print(f"iOS target {ios_target} Watch target {watch_target} Widget target {widget_target} iOS widget {ios_widget_target}")


if __name__ == "__main__":
    main()
