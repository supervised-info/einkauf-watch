import XCTest
@testable import EinkaufCore

final class BackupCodecTests: XCTestCase {
    func testFixtureIsBackupAndKeepsItems() throws {
        let data = try loadFixture("einkauf-backup.json")
        let state = try BackupCodec.decode(data)
        XCTAssertEqual(state.currentStoreId, "edeka")
        XCTAssertEqual(state.items.count, 14)
        XCTAssertEqual(state.staples.count, 3)
        XCTAssertTrue(state.savedLists.isEmpty)
        XCTAssertTrue(state.stores.contains(where: { $0.id == "rewe" }))
        XCTAssertEqual(state.items.first(where: { $0.id == "i014unk" })?.dept, "sonstiges")
    }

    func testMissingStaplesIsFine() throws {
        let data = try loadFixture("einkauf-backup-ohne-staples.json")
        let state = try BackupCodec.decode(data)
        XCTAssertTrue(state.staples.isEmpty)
        XCTAssertTrue(state.savedLists.isEmpty)
        XCTAssertEqual(state.currentStoreId, "aldi")
        XCTAssertEqual(state.items.count, 3)
        XCTAssertEqual(state.walkMode, false)
    }

    func testUnknownFieldsIgnored() throws {
        let json = """
        {"kind":"einkauf-backup","v":1,"currentStoreId":"edeka","future":{"x":1},"stores":[],"items":[{"id":"a","name":"Milch","dept":"kuehlung","done":false,"added":1,"ord":1,"nope":true}]}
        """
        let state = try BackupCodec.decode(Data(json.utf8))
        XCTAssertEqual(state.items.count, 1)
        XCTAssertEqual(state.items[0].name, "Milch")
    }

    func testExportRoundTrip() throws {
        let original = try BackupCodec.decode(try loadFixture("einkauf-backup.json"))
        let exported = try BackupCodec.encodeExport(original)
        let again = try BackupCodec.decode(exported)
        XCTAssertEqual(again.currentStoreId, original.currentStoreId)
        XCTAssertEqual(again.items.map(\.id), original.items.map(\.id))
        XCTAssertEqual(again.items.map(\.done), original.items.map(\.done))
        XCTAssertEqual(again.walkMode, true)
        XCTAssertEqual(again.savedLists, original.savedLists)
        let obj = try JSONSerialization.jsonObject(with: exported) as! [String: Any]
        XCTAssertEqual(obj["kind"] as? String, "einkauf-backup")
        XCTAssertEqual(obj["walkMode"] as? Bool, true)
        XCTAssertNil(obj["listRevision"])
        XCTAssertNotNil(obj["savedLists"])
        XCTAssertNotNil(obj["mappings"])
        XCTAssertNil(obj["learnedMappings"])
        XCTAssertNil(obj["userMappings"])
        XCTAssertNil(obj["meineZuordnungen"])
    }

    func testFixtureKeepsMappingsAndExportUsesSameField() throws {
        let data = try loadFixture("einkauf-backup.json")
        let state = try BackupCodec.decode(data)
        XCTAssertEqual(state.mappings["milch"], "kuehlung")
        XCTAssertEqual(state.mappings["klopapier"], "drogerie")
        let exported = try BackupCodec.encodeExport(state)
        let obj = try JSONSerialization.jsonObject(with: exported) as! [String: Any]
        let maps = obj["mappings"] as? [String: String]
        XCTAssertEqual(maps?["milch"], "kuehlung")
        XCTAssertEqual(maps?["klopapier"], "drogerie")
        XCTAssertEqual(Set(obj.keys.filter { $0.lowercased().contains("map") }), ["mappings"])
        XCTAssertNil(obj["learnedMappings"])
        XCTAssertNil(obj["userMappings"])
        XCTAssertNil(obj["meineZuordnungen"])
        let again = try BackupCodec.decode(exported)
        XCTAssertEqual(again.mappings, state.mappings)
    }

    func testNotABackupRejected() {
        let json = Data("{\"kind\":\"einkauf-laeden\",\"stores\":[]}".utf8)
        XCTAssertThrowsError(try BackupCodec.decode(json))
    }

    private func loadFixture(_ name: String) throws -> Data {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
            .appendingPathComponent(name)
        return try Data(contentsOf: url)
    }
}

final class GroupingTests: XCTestCase {
    func testVorFirstNachLast() throws {
        let state = try BackupCodec.decode(try loadFixture("einkauf-backup.json"))
        let groups = state.grouped()
        XCTAssertEqual(groups.map(\.dept).first, "vor")
        XCTAssertEqual(groups.map(\.dept).last, "nach")
        XCTAssertEqual(groups.map(\.dept), ["vor", "obst", "bedienung", "brot", "kuehlung", "tiefkuehl", "trocken", "suess", "getraenke", "drogerie", "sonstiges", "nach"])
        XCTAssertEqual(groups.map(\.id), groups.map { "edeka|\($0.dept)" })
    }

    func testSortByOrdInsideDept() {
        let items = [
            Item(id: "b", name: "B", dept: "obst", done: false, added: 2, ord: 20),
            Item(id: "a", name: "A", dept: "obst", done: false, added: 1, ord: 10)
        ]
        let store = Store.seeds.first { $0.id == "edeka" }!
        let groups = ListGrouping.groups(items: items, store: store)
        XCTAssertEqual(groups.first { $0.dept == "obst" }?.items.map(\.id), ["a", "b"])
        XCTAssertEqual(groups.first { $0.dept == "obst" }?.id, "edeka|obst")
    }

    func testAldiPutsBedienungAfterLayout() {
        let items = [
            Item(id: "1", name: "Gouda", dept: "bedienung", done: false, added: 1, ord: 1),
            Item(id: "2", name: "Äpfel", dept: "obst", done: false, added: 1, ord: 1),
            Item(id: "3", name: "Nachher", dept: "nach", done: false, added: 1, ord: 1)
        ]
        let store = Store.seeds.first { $0.id == "aldi" }!
        let ids = ListGrouping.groups(items: items, store: store).map(\.dept)
        XCTAssertEqual(ids.first, "obst")
        XCTAssertEqual(ids.last, "nach")
        XCTAssertEqual(ids, ["obst", "bedienung", "nach"])
        XCTAssertEqual(items.first { $0.id == "1" }?.dept, "bedienung")
    }

    func testSonstigesFollowsStoreLayoutPosition() {
        let items = [
            Item(id: "s", name: "AXE", dept: "sonstiges", done: false, added: 1, ord: 1),
            Item(id: "o", name: "Äpfel", dept: "obst", done: false, added: 2, ord: 1)
        ]
        let storeA = Store(id: "markt-a", name: "Markt A", layout: ["vor", "sonstiges", "obst", "nach"], builtin: false)
        let storeB = Store(id: "markt-b", name: "Markt B", layout: ["vor", "obst", "sonstiges", "nach"], builtin: false)

        let groupsA = ListGrouping.groups(items: items, store: storeA)
        XCTAssertEqual(groupsA.map(\.dept), ["sonstiges", "obst"])
        XCTAssertEqual(groupsA.first { $0.dept == "sonstiges" }?.items.map(\.id), ["s"])
        XCTAssertEqual(groupsA.first { $0.dept == "sonstiges" }?.items.map(\.dept), ["sonstiges"])
        XCTAssertEqual(groupsA.first { $0.dept == "obst" }?.items.map(\.id), ["o"])

        let groupsB = ListGrouping.groups(items: items, store: storeB)
        XCTAssertEqual(groupsB.map(\.dept), ["obst", "sonstiges"])
        XCTAssertEqual(groupsB.first { $0.dept == "sonstiges" }?.items.map(\.id), ["s"])
        XCTAssertEqual(groupsB.first { $0.dept == "sonstiges" }?.items.map(\.name), ["AXE"])
        XCTAssertEqual(groupsA.first { $0.dept == "sonstiges" }?.items, groupsB.first { $0.dept == "sonstiges" }?.items)
        XCTAssertEqual(items.first { $0.id == "s" }?.dept, "sonstiges")
        XCTAssertEqual(items.first { $0.id == "o" }?.dept, "obst")
    }

    func testDmSeedKeepsSonstigesBeforeNach() {
        let dm = Store.seeds.first { $0.id == "dm" }!
        XCTAssertEqual(dm.layout.dropLast().last, "sonstiges")
        XCTAssertEqual(StoreLayout.sanitized(dm.layout).dropLast().last, "sonstiges")
        let items = [
            Item(id: "t", name: "Toilettenpapier", dept: "drogerie", done: false, added: 1, ord: 1),
            Item(id: "a", name: "AXE", dept: "sonstiges", done: false, added: 2, ord: 1)
        ]
        XCTAssertEqual(ListGrouping.groups(items: items, store: dm).map(\.dept), ["drogerie", "sonstiges"])
    }

    func testWalkLinesEdekaSuessThenDrogerieDmReversed() {
        let items = [
            Item(id: "k", name: "Kinderschokolade", dept: "suess", done: false, added: 1, ord: 1),
            Item(id: "t", name: "Toilettenpapier", dept: "drogerie", done: false, added: 2, ord: 1),
            Item(id: "a", name: "AXE", dept: "sonstiges", done: false, added: 3, ord: 1)
        ]
        let edeka = Store.seeds.first { $0.id == "edeka" }!
        let dm = Store.seeds.first { $0.id == "dm" }!

        let edekaGroups = ListGrouping.groups(items: items, store: edeka)
        XCTAssertEqual(edekaGroups.map(\.dept), ["suess", "drogerie", "sonstiges"])
        let edekaLines = ListGrouping.walkLines(groups: edekaGroups, storeId: "edeka")
        XCTAssertEqual(edekaLines.compactMap(\.headerDept), ["suess", "drogerie", "sonstiges"])
        XCTAssertEqual(edekaLines.map(\.id), [
            "edeka|h:suess", "edeka|i:k",
            "edeka|h:drogerie", "edeka|i:t",
            "edeka|h:sonstiges", "edeka|i:a"
        ])

        let dmGroups = ListGrouping.groups(items: items, store: dm)
        XCTAssertEqual(dmGroups.map(\.dept), ["drogerie", "sonstiges", "suess"])
        XCTAssertEqual(dmGroups.first { $0.dept == "sonstiges" }?.items.map(\.id), ["a"])
        XCTAssertEqual(dmGroups.first { $0.dept == "suess" }?.items.map(\.id), ["k"])
        XCTAssertEqual(dmGroups.flatMap(\.items).first { $0.id == "k" }?.dept, "suess")
        let dmLines = ListGrouping.walkLines(groups: dmGroups, storeId: "dm")
        XCTAssertEqual(dmLines.compactMap(\.headerDept), ["drogerie", "sonstiges", "suess"])
        XCTAssertEqual(dmLines.map(\.id), [
            "dm|h:drogerie", "dm|i:t",
            "dm|h:sonstiges", "dm|i:a",
            "dm|h:suess", "dm|i:k"
        ])

        let dmRows = ListGrouping.walkListRows(groups: dmGroups, storeId: "dm")
        XCTAssertEqual(dmRows.map(\.id), [
            "dm|0|dm|h:drogerie", "dm|1|dm|i:t",
            "dm|2|dm|h:sonstiges", "dm|3|dm|i:a",
            "dm|4|dm|h:suess", "dm|5|dm|i:k"
        ])
        XCTAssertNotEqual(edekaLines.compactMap(\.headerDept).prefix(2), dmLines.compactMap(\.headerDept).prefix(2))
        XCTAssertEqual(items.first { $0.id == "k" }?.dept, "suess")
    }

    func testWalkListRowsHidingCompletedDropsDoneItemsAndEmptyHeaders() {
        let items = [
            Item(id: "k", name: "Kinderschokolade", dept: "suess", done: true, added: 1, ord: 1),
            Item(id: "t", name: "Toilettenpapier", dept: "drogerie", done: false, added: 2, ord: 1),
            Item(id: "a", name: "AXE", dept: "sonstiges", done: true, added: 3, ord: 1)
        ]
        let edeka = Store.seeds.first { $0.id == "edeka" }!
        let groups = ListGrouping.groups(items: items, store: edeka)
        XCTAssertEqual(groups.map(\.dept), ["suess", "drogerie", "sonstiges"])

        let allRows = ListGrouping.walkListRows(groups: groups, storeId: "edeka")
        XCTAssertEqual(allRows.compactMap(\.line.headerDept), ["suess", "drogerie", "sonstiges"])
        XCTAssertEqual(allRows.filter(\.line.isItem).count, 3)

        let hidden = ListGrouping.walkListRows(groups: groups, storeId: "edeka", hidingCompleted: true)
        XCTAssertEqual(hidden.compactMap(\.line.headerDept), ["drogerie"])
        XCTAssertEqual(hidden.compactMap(\.line.itemId), ["t"])
        XCTAssertEqual(groups.flatMap(\.items).filter(\.done).map(\.id), ["k", "a"])
        XCTAssertEqual(items.filter(\.done).map(\.id), ["k", "a"])
    }

    func testWalkListRowsHidingCompletedEmptyWhenAllDone() {
        let items = [
            Item(id: "k", name: "Kinderschokolade", dept: "suess", done: true, added: 1, ord: 1),
            Item(id: "t", name: "Toilettenpapier", dept: "drogerie", done: true, added: 2, ord: 1)
        ]
        let edeka = Store.seeds.first { $0.id == "edeka" }!
        let groups = ListGrouping.groups(items: items, store: edeka)
        XCTAssertFalse(groups.isEmpty)
        let hidden = ListGrouping.walkListRows(groups: groups, storeId: "edeka", hidingCompleted: true)
        XCTAssertTrue(hidden.isEmpty)
        XCTAssertEqual(ListGrouping.walkListRows(groups: groups, storeId: "edeka").filter(\.line.isItem).count, 2)
    }

    func testVisibleGroupsHidingCompletedDropsDoneItemsAndEmptyDepartments() {
        let items = [
            Item(id: "k", name: "Kinderschokolade", dept: "suess", done: true, added: 1, ord: 1),
            Item(id: "t", name: "Toilettenpapier", dept: "drogerie", done: false, added: 2, ord: 1),
            Item(id: "m", name: "Milch", dept: "kuehlung", done: false, added: 3, ord: 1),
            Item(id: "a", name: "AXE", dept: "sonstiges", done: true, added: 4, ord: 1)
        ]
        let edeka = Store.seeds.first { $0.id == "edeka" }!
        let groups = ListGrouping.groups(items: items, store: edeka)
        XCTAssertEqual(groups.map(\.dept), ["kuehlung", "suess", "drogerie", "sonstiges"])
        XCTAssertEqual(ListGrouping.visibleGroups(groups, hidingCompleted: false), groups)
        XCTAssertEqual(ListGrouping.progressLabel(groups: groups), "2/2/4")

        let hidden = ListGrouping.visibleGroups(groups, hidingCompleted: true)
        XCTAssertEqual(hidden.map(\.dept), ["kuehlung", "drogerie"])
        XCTAssertEqual(hidden.flatMap(\.items).map(\.id), ["m", "t"])
        XCTAssertTrue(hidden.flatMap(\.items).allSatisfy { !$0.done })
        XCTAssertEqual(ListGrouping.progressLabel(groups: hidden), "2/0/2")
    }

    func testVisibleGroupsHidingCompletedEmptyWhenAllDone() {
        let items = [
            Item(id: "k", name: "Kinderschokolade", dept: "suess", done: true, added: 1, ord: 1),
            Item(id: "t", name: "Toilettenpapier", dept: "drogerie", done: true, added: 2, ord: 1)
        ]
        let edeka = Store.seeds.first { $0.id == "edeka" }!
        let groups = ListGrouping.groups(items: items, store: edeka)
        XCTAssertFalse(groups.isEmpty)
        let hidden = ListGrouping.visibleGroups(groups, hidingCompleted: true)
        XCTAssertTrue(hidden.isEmpty)
        XCTAssertEqual(ListGrouping.progressLabel(groups: hidden), "0/0/0")
        XCTAssertEqual(ListGrouping.progressLabel(groups: groups), "0/2/2")
    }

    private func loadFixture(_ name: String) throws -> Data {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
            .appendingPathComponent(name)
        return try Data(contentsOf: url)
    }
}

final class ListProgressTests: XCTestCase {
    func testEmptyIsZeroOverZero() {
        XCTAssertEqual(AppState.seed.openCount, 0)
        XCTAssertEqual(AppState.seed.doneCount, 0)
        XCTAssertEqual(AppState.seed.items.count, 0)
        XCTAssertEqual(AppState.seed.progressLabel, "0/0/0")
    }

    func testCountsDoneAcrossAllDepartmentsIncludingVorNach() {
        var state = AppState.seed
        state.items = [
            Item(id: "v", name: "Tasche", dept: "vor", done: true, added: 1, ord: 1),
            Item(id: "m", name: "Milch", dept: "kuehlung", done: false, added: 2, ord: 1),
            Item(id: "n", name: "Pfand", dept: "nach", done: true, added: 3, ord: 1)
        ]
        XCTAssertEqual(state.doneCount, 2)
        XCTAssertEqual(state.items.count, 3)
        XCTAssertEqual(state.progressLabel, "1/2/3")
        XCTAssertEqual(state.openCount, 1)
    }

    func testAllDone() {
        var state = AppState.seed
        state.items = [
            Item(id: "a", name: "A", dept: "obst", done: true, added: 1, ord: 1),
            Item(id: "b", name: "B", dept: "brot", done: true, added: 2, ord: 1)
        ]
        XCTAssertEqual(state.openCount, 0)
        XCTAssertEqual(state.doneCount, 2)
        XCTAssertEqual(state.progressLabel, "0/2/2")
    }
}

final class WatchTitleTests: XCTestCase {
    func testSeedShowsStoreAndProgress() {
        XCTAssertEqual(AppState.seed.watchTitle, "Edeka  Einkauf 0/0/0")
    }

    func testUpdatesWhenCurrentStoreChanges() {
        var state = AppState.seed
        state.currentStoreId = "rewe"
        XCTAssertEqual(state.watchTitle, "Rewe  Einkauf 0/0/0")
        state.currentStoreId = "aldi"
        XCTAssertEqual(state.watchTitle, "Aldi  Einkauf 0/0/0")
    }

    func testKeepsProgressLabelOnTheSameLine() {
        var state = AppState.seed
        state.items = [
            Item(id: "a", name: "A", dept: "obst", done: false, added: 1, ord: 1),
            Item(id: "b", name: "B", dept: "obst", done: false, added: 2, ord: 1),
            Item(id: "c", name: "C", dept: "obst", done: false, added: 3, ord: 1)
        ]
        XCTAssertEqual(state.watchTitle, "Edeka  Einkauf 3/0/3")
        state.items[0].done = true
        XCTAssertEqual(state.watchTitle, "Edeka  Einkauf 2/1/3")
    }

    func testTruncatesLongStoreNameSoProgressFits() {
        var state = AppState.seed
        state.stores.append(Store(id: "lang", name: "Wochenmarkt Neustadt", layout: ["vor", "sonstiges", "nach"], builtin: false))
        state.currentStoreId = "lang"
        state.items = [
            Item(id: "a", name: "A", dept: "obst", done: false, added: 1, ord: 1),
            Item(id: "b", name: "B", dept: "obst", done: false, added: 2, ord: 1),
            Item(id: "c", name: "C", dept: "obst", done: false, added: 3, ord: 1)
        ]
        XCTAssertEqual(state.watchTitle, "Woche…  Einkauf 3/0/3")
        XCTAssertTrue(state.watchTitle.hasSuffix("Einkauf \(state.progressLabel)"))
        XCTAssertLessThanOrEqual(AppState.clippedWatchStoreName(state.currentStore.name).count, AppState.watchStoreNameLimit)
    }

    func testBuiltinEigenesLayoutIsTruncated() {
        var state = AppState.seed
        state.currentStoreId = "eigenes"
        XCTAssertEqual(state.currentStore.name, "Eigenes Layout")
        XCTAssertEqual(state.watchTitle, "Eigen…  Einkauf 0/0/0")
    }

    func testRemoteSetStoreUpdatesTitleViaMerge() {
        var local = AppState.seed
        local.listRevision = 1
        local.currentStoreId = "edeka"
        var remote = AppState.seed
        remote.listRevision = 4
        remote.currentStoreId = "aldi"
        let merged = StateMerge.merge(local: local, remote: remote)
        XCTAssertEqual(merged.currentStoreId, "aldi")
        XCTAssertEqual(merged.watchTitle, "Aldi  Einkauf 0/0/0")
    }
}

final class ComplicationSnapshotTests: XCTestCase {
    func testEmptyListIsZeroOverZeroNotHidden() {
        let snap = ComplicationSnapshot.make(from: .seed)
        XCTAssertEqual(snap.progressLabel, "0/0/0")
        XCTAssertEqual(snap.storeName, "Edeka")
        XCTAssertTrue(snap.isEmpty)
        XCTAssertEqual(snap.openCount, 0)
        XCTAssertEqual(snap.compactCountText, "erledigt")
        XCTAssertEqual(snap.inlineText, "Edeka  erledigt")
        XCTAssertEqual(snap.accessibilityLabel, "Edeka, Liste erledigt")
        XCTAssertEqual(snap.progress, 0, accuracy: 0.0001)
        XCTAssertEqual(snap.openText, "0")
        XCTAssertEqual(snap.doneText, "0")
        XCTAssertEqual(snap.totalText, "0")
    }

    func testGaugeProgressIsZeroWhenEmptyAndFractionOtherwise() {
        XCTAssertEqual(ComplicationSnapshot.make(from: .seed).progress, 0, accuracy: 0.0001)
        var state = AppState.seed
        state.items = [
            Item(id: "v", name: "Tasche", dept: "vor", done: true, added: 1, ord: 1),
            Item(id: "m", name: "Milch", dept: "kuehlung", done: false, added: 2, ord: 1),
            Item(id: "n", name: "Pfand", dept: "nach", done: true, added: 3, ord: 1)
        ]
        XCTAssertEqual(state.complicationSnapshot.progress, 2.0 / 3.0, accuracy: 0.0001)
        XCTAssertEqual(state.complicationSnapshot.openText, "1")
        XCTAssertEqual(state.complicationSnapshot.compactCountText, "1")
        XCTAssertEqual(state.complicationSnapshot.doneText, "2")
        XCTAssertEqual(state.complicationSnapshot.totalText, "3")
        state.items = [
            Item(id: "a", name: "A", dept: "obst", done: true, added: 1, ord: 1),
            Item(id: "b", name: "B", dept: "brot", done: true, added: 2, ord: 1)
        ]
        XCTAssertEqual(state.complicationSnapshot.progress, 1, accuracy: 0.0001)
        XCTAssertEqual(state.complicationSnapshot.progressLabel, "0/2/2")
        XCTAssertEqual(state.complicationSnapshot.openText, "0")
        XCTAssertEqual(state.complicationSnapshot.compactCountText, "erledigt")
        XCTAssertEqual(state.complicationSnapshot.accessibilityLabel, "Edeka, Liste erledigt")
        XCTAssertEqual(state.complicationSnapshot.doneText, "2")
        XCTAssertEqual(state.complicationSnapshot.totalText, "2")
    }

    func testProgressMatchesWatchTitleAndIncludesVorNach() {
        var state = AppState.seed
        state.items = [
            Item(id: "v", name: "Tasche", dept: "vor", done: true, added: 1, ord: 1),
            Item(id: "m", name: "Milch", dept: "kuehlung", done: false, added: 2, ord: 1),
            Item(id: "n", name: "Pfand", dept: "nach", done: true, added: 3, ord: 1)
        ]
        let snap = state.complicationSnapshot
        XCTAssertEqual(snap.progressLabel, state.progressLabel)
        XCTAssertEqual(snap.progressLabel, "1/2/3")
        XCTAssertEqual(snap.storeName, AppState.clippedWatchStoreName(state.currentStore.name))
        XCTAssertFalse(snap.isEmpty)
        XCTAssertEqual(snap.openCount, 1)
        XCTAssertEqual(snap.compactCountText, "1")
        XCTAssertEqual(snap.inlineText, "Edeka  1")
        XCTAssertEqual(snap.accessibilityLabel, "Edeka, 1 offen")
        XCTAssertTrue(state.watchTitle.contains(snap.progressLabel))
        XCTAssertFalse(snap.inlineText.contains(snap.progressLabel))
    }

    func testStoreChangeAndClippedName() {
        var state = AppState.seed
        state.currentStoreId = "rewe"
        XCTAssertEqual(ComplicationSnapshot.make(from: state).storeName, "Rewe")
        state.currentStoreId = "eigenes"
        XCTAssertEqual(ComplicationSnapshot.make(from: state).storeName, "Eigen…")
        state.stores.append(Store(id: "lang", name: "Wochenmarkt Neustadt", layout: ["vor", "sonstiges", "nach"], builtin: false))
        state.currentStoreId = "lang"
        XCTAssertEqual(ComplicationSnapshot.make(from: state).storeName, "Woche…")
    }

    func testPlaceholderSplitsThreeParts() {
        XCTAssertEqual(ComplicationSnapshot.placeholder.progressLabel, "5/2/7")
        XCTAssertEqual(ComplicationSnapshot.placeholder.openText, "5")
        XCTAssertEqual(ComplicationSnapshot.placeholder.compactCountText, "5")
        XCTAssertEqual(ComplicationSnapshot.placeholder.doneText, "2")
        XCTAssertEqual(ComplicationSnapshot.placeholder.totalText, "7")
        XCTAssertEqual(HomeWidgetSnapshot.placeholder.progressLabel, "5/2/7")
    }

    func testCompactCountIsOpenOnlyAndErledigtWhenZero() {
        var state = AppState.seed
        state.items = [
            Item(id: "a", name: "A", dept: "obst", done: false, added: 1, ord: 1),
            Item(id: "b", name: "B", dept: "obst", done: false, added: 2, ord: 1)
        ]
        var snap = state.complicationSnapshot
        XCTAssertEqual(snap.progressLabel, "2/0/2")
        XCTAssertEqual(snap.compactCountText, "2")
        XCTAssertEqual(snap.accessibilityLabel, "Edeka, 2 offen")
        state.items[0].done = true
        snap = state.complicationSnapshot
        XCTAssertEqual(snap.progressLabel, "1/1/2")
        XCTAssertEqual(snap.compactCountText, "1")
        XCTAssertEqual(snap.inlineText, "Edeka  1")
        state.items[1].done = true
        snap = state.complicationSnapshot
        XCTAssertEqual(snap.progressLabel, "0/2/2")
        XCTAssertEqual(snap.compactCountText, "erledigt")
        XCTAssertEqual(snap.inlineText, "Edeka  erledigt")
        XCTAssertEqual(snap.accessibilityLabel, "Edeka, Liste erledigt")
    }

    func testWidgetKindIsStable() {
        XCTAssertEqual(ComplicationSnapshot.widgetKind, "EinkaufProgress")
        XCTAssertEqual(ComplicationSnapshot.openURL.scheme, "einkauf")
    }
}

final class HomeWidgetSnapshotTests: XCTestCase {
    func testEmptyListIsZeroOverZeroNotHidden() {
        let snap = HomeWidgetSnapshot.make(from: .seed)
        XCTAssertEqual(snap.progressLabel, "0/0/0")
        XCTAssertEqual(snap.storeName, "Edeka")
        XCTAssertTrue(snap.isEmpty)
        XCTAssertTrue(snap.openItemNames.isEmpty)
        XCTAssertTrue(snap.accessibilityLabel.contains("leer"))
    }

    func testProgressMatchesWatchTitleAndIncludesVorNach() {
        var state = AppState.seed
        state.items = [
            Item(id: "v", name: "Tasche", dept: "vor", done: true, added: 1, ord: 1),
            Item(id: "m", name: "Milch", dept: "kuehlung", done: false, added: 2, ord: 1),
            Item(id: "n", name: "Pfand", dept: "nach", done: true, added: 3, ord: 1)
        ]
        let snap = HomeWidgetSnapshot.make(from: state)
        XCTAssertEqual(snap.progressLabel, state.progressLabel)
        XCTAssertEqual(snap.progressLabel, "1/2/3")
        XCTAssertEqual(snap.storeName, state.currentStore.name)
        XCTAssertFalse(snap.isEmpty)
        XCTAssertEqual(snap.openItemNames, ["Milch"])
        XCTAssertTrue(state.watchTitle.contains(snap.progressLabel))
        XCTAssertEqual(state.complicationSnapshot.progressLabel, snap.progressLabel)
    }

    func testOpenItemsFollowWalkOrderAndSkipDone() {
        var state = AppState.seed
        state.items = [
            Item(id: "d", name: "Seife", dept: "drogerie", done: false, added: 1, ord: 1),
            Item(id: "k", name: "Milch", dept: "kuehlung", done: false, added: 2, ord: 1),
            Item(id: "o", name: "Äpfel", dept: "obst", done: true, added: 3, ord: 1),
            Item(id: "v", name: "Tasche", dept: "vor", done: false, added: 4, ord: 1)
        ]
        let edeka = HomeWidgetSnapshot.make(from: state)
        XCTAssertEqual(edeka.openItemNames, ["Tasche", "Milch", "Seife"])
        state.currentStoreId = "dm"
        let dm = HomeWidgetSnapshot.make(from: state)
        XCTAssertEqual(dm.openItemNames, ["Tasche", "Seife", "Milch"])
    }

    func testOpenItemLimitAndFullStoreName() {
        var state = AppState.seed
        state.currentStoreId = "eigenes"
        state.items = (0..<8).map { i in
            Item(id: "i\(i)", name: "Artikel \(i)", dept: "sonstiges", done: false, added: Double(i), ord: Double(i))
        }
        let snap = HomeWidgetSnapshot.make(from: state)
        XCTAssertEqual(snap.storeName, "Eigenes Layout")
        XCTAssertNotEqual(snap.storeName, AppState.clippedWatchStoreName(state.currentStore.name))
        XCTAssertEqual(snap.openItemNames.count, HomeWidgetSnapshot.openItemLimit)
        XCTAssertEqual(snap.openItemNames, (0..<5).map { "Artikel \($0)" })
    }

    func testWidgetKindIsStable() {
        XCTAssertEqual(HomeWidgetSnapshot.widgetKind, "EinkaufHome")
        XCTAssertEqual(HomeWidgetSnapshot.openURL.scheme, "einkauf")
        XCTAssertEqual(HomeWidgetSnapshot.openURL, ComplicationSnapshot.openURL)
    }
}

final class MergeTests: XCTestCase {
    func testNewerDoneWinsWithoutClobberingList() {
        var local = AppState.seed
        local.listRevision = 2
        local.items = [Item(id: "i1", name: "Milch", dept: "kuehlung", done: false, added: 1, ord: 1, doneChangedAt: 10)]
        var remote = AppState.seed
        remote.listRevision = 1
        remote.items = [Item(id: "i1", name: "Milch", dept: "kuehlung", done: true, added: 1, ord: 1, doneChangedAt: 50)]
        let merged = StateMerge.merge(local: local, remote: remote)
        XCTAssertEqual(merged.listRevision, 2)
        XCTAssertEqual(merged.items[0].done, true)
        XCTAssertEqual(merged.items[0].doneChangedAt, 50)
    }

    func testHigherListRevisionKeepsNewItems() {
        var local = AppState.seed
        local.listRevision = 1
        local.currentStoreId = "edeka"
        local.items = [Item(id: "old", name: "Alt", dept: "obst", done: false, added: 1, ord: 1)]
        var remote = AppState.seed
        remote.listRevision = 5
        remote.currentStoreId = "dm"
        remote.items = [Item(id: "new", name: "Neu", dept: "obst", done: false, added: 2, ord: 1)]
        let merged = StateMerge.merge(local: local, remote: remote)
        XCTAssertEqual(merged.items.map(\.id), ["new"])
        XCTAssertEqual(merged.currentStoreId, "dm")
        XCTAssertEqual(merged.listRevision, 5)
    }
}

final class StapleApplyTests: XCTestCase {
    func testAddsMissingStapleWithDepartment() {
        let staple = Staple(name: "Milch", dept: "kuehlung")
        let result = StapleApply.apply(staple, items: [], mappings: [:], nextOrd: 1, now: 10)
        XCTAssertEqual(result.added, 1)
        XCTAssertEqual(result.items[0].name, "Milch")
        XCTAssertEqual(result.items[0].dept, "kuehlung")
        XCTAssertEqual(result.mappings["milch"], "kuehlung")
    }

    func testReopensDoneStaple() {
        let items = [Item(id: "i1", name: "Milch", dept: "kuehlung", done: true, added: 1, ord: 1, doneChangedAt: 1)]
        let staple = Staple(name: "Milch", dept: "kuehlung")
        let result = StapleApply.apply(staple, items: items, mappings: [:], nextOrd: 2, now: 50)
        XCTAssertEqual(result.reopened, 1)
        XCTAssertEqual(result.added, 0)
        XCTAssertFalse(result.items[0].done)
        XCTAssertEqual(result.items[0].doneChangedAt, 50)
    }

    func testSkipsOpenDuplicate() {
        let items = [Item(id: "i1", name: "Milch", dept: "kuehlung", done: false, added: 1, ord: 1)]
        let result = StapleApply.apply(Staple(name: "Milch", dept: "kuehlung"), items: items, mappings: [:], nextOrd: 2)
        XCTAssertEqual(result.already, 1)
        XCTAssertEqual(result.items.count, 1)
    }

    func testApplyAllAddsAndReopens() {
        let items = [Item(id: "i1", name: "Butter", dept: "kuehlung", done: true, added: 1, ord: 1)]
        let staples = [
            Staple(name: "Butter", dept: "kuehlung"),
            Staple(name: "Klopapier", dept: "drogerie")
        ]
        let result = StapleApply.applyAll(staples, items: items, mappings: [:], nextOrd: 2, now: 9)
        XCTAssertEqual(result.reopened, 1)
        XCTAssertEqual(result.added, 1)
        XCTAssertEqual(result.items.count, 2)
        XCTAssertFalse(result.items[0].done)
        XCTAssertEqual(result.items[1].name, "Klopapier")
        XCTAssertEqual(result.items[1].dept, "drogerie")
    }
}

@MainActor
final class SavedListTests: XCTestCase {
    private func threeItemsOneDone() -> [Item] {
        [
            Item(id: "a", name: "Milch", dept: "kuehlung", done: false, added: 1, ord: 1),
            Item(id: "b", name: "Butter", dept: "kuehlung", done: true, added: 2, ord: 2, doneChangedAt: 2),
            Item(id: "c", name: "Grillkohle", dept: "sonstiges", done: false, added: 3, ord: 3)
        ]
    }

    func testSaveSnapshotOmitsDone() throws {
        var seed = AppState.seed
        seed.items = threeItemsOneDone()
        let store = ShoppingStore(state: seed, enableSync: false)
        XCTAssertEqual(store.saveCurrentList(name: "Grillen"), .saved)
        XCTAssertEqual(store.savedLists.count, 1)
        let list = store.savedLists[0]
        XCTAssertEqual(list.name, "Grillen")
        XCTAssertEqual(list.items.map(\.name), ["Milch", "Butter", "Grillkohle"])
        XCTAssertEqual(list.items.map(\.dept), ["kuehlung", "kuehlung", "sonstiges"])
        XCTAssertEqual(list.items.count, 3)

        let exported = try BackupCodec.encodeExport(store.state)
        let obj = try JSONSerialization.jsonObject(with: exported) as! [String: Any]
        let saved = obj["savedLists"] as! [[String: Any]]
        XCTAssertEqual(saved.count, 1)
        let items = saved[0]["items"] as! [[String: Any]]
        XCTAssertEqual(items.count, 3)
        XCTAssertTrue(items.allSatisfy { $0["done"] == nil })
        XCTAssertTrue(items.allSatisfy { $0["id"] == nil })
        XCTAssertEqual(items.map { $0["name"] as? String }, ["Milch", "Butter", "Grillkohle"])
    }

    func testApplyOnEmptyAddsAllOpen() {
        let list = SavedList(
            id: "l-grillen",
            name: "Grillen",
            items: SavedList.snapshot(from: threeItemsOneDone())
        )
        XCTAssertEqual(list.items.count, 3)
        let store = ShoppingStore(state: .seed, enableSync: false)
        XCTAssertTrue(store.state.items.isEmpty)
        let result = store.applySavedList(list)
        XCTAssertEqual(result.added, 3)
        XCTAssertEqual(result.reopened, 0)
        XCTAssertEqual(store.state.items.count, 3)
        XCTAssertTrue(store.state.items.allSatisfy { !$0.done })
        XCTAssertEqual(store.state.items.map(\.name), ["Milch", "Butter", "Grillkohle"])
    }

    func testApplyReopensDoneMatchingItem() {
        var seed = AppState.seed
        seed.items = [
            Item(id: "keep", name: "Äpfel", dept: "obst", done: false, added: 1, ord: 1),
            Item(id: "m", name: "Milch", dept: "kuehlung", done: true, added: 2, ord: 2, doneChangedAt: 2)
        ]
        let store = ShoppingStore(state: seed, enableSync: false)
        let list = SavedList(
            id: "l-grillen",
            name: "Grillen",
            items: [
                Staple(name: "Milch", dept: "kuehlung"),
                Staple(name: "Grillkohle", dept: "sonstiges")
            ]
        )
        let result = store.applySavedList(list)
        XCTAssertEqual(result.reopened, 1)
        XCTAssertEqual(result.added, 1)
        XCTAssertEqual(store.state.items.count, 3)
        XCTAssertEqual(store.state.items.first { $0.id == "keep" }?.name, "Äpfel")
        XCTAssertFalse(store.state.items.first { $0.id == "keep" }?.done ?? true)
        XCTAssertFalse(store.state.items.first { $0.id == "m" }?.done ?? true)
        XCTAssertEqual(store.state.items.first { $0.name == "Grillkohle" }?.dept, "sonstiges")
        XCTAssertFalse(store.state.items.first { $0.name == "Grillkohle" }?.done ?? true)
    }

    func testSaveThenApplyReopensDoneWithoutReplacing() {
        var seed = AppState.seed
        seed.items = threeItemsOneDone()
        let store = ShoppingStore(state: seed, enableSync: false)
        XCTAssertEqual(store.saveCurrentList(name: "Grillen"), .saved)
        let result = store.applySavedList(store.savedLists[0])
        XCTAssertEqual(result.reopened, 1)
        XCTAssertEqual(result.added, 0)
        XCTAssertEqual(result.already, 2)
        XCTAssertEqual(store.state.items.count, 3)
        XCTAssertFalse(store.state.items.first { $0.name == "Butter" }?.done ?? true)
        XCTAssertEqual(store.state.items.map(\.id), ["a", "b", "c"])
    }

    func testEmptyListDoesNotSave() {
        let store = ShoppingStore(state: .seed, enableSync: false)
        XCTAssertEqual(store.saveCurrentList(name: "Grillen"), .emptyList)
        XCTAssertTrue(store.savedLists.isEmpty)
        XCTAssertEqual(store.state.listRevision, 0)
        XCTAssertEqual(store.saveCurrentList(name: "   "), .invalidName)
    }

    func testDuplicateNamesAllowed() {
        var seed = AppState.seed
        seed.items = [Item(id: "a", name: "Milch", dept: "kuehlung", done: false, added: 1, ord: 1)]
        let store = ShoppingStore(state: seed, enableSync: false)
        XCTAssertEqual(store.saveCurrentList(name: "Grillen"), .saved)
        XCTAssertEqual(store.saveCurrentList(name: "Grillen"), .saved)
        XCTAssertEqual(store.savedLists.map(\.name), ["Grillen", "Grillen"])
        XCTAssertNotEqual(store.savedLists[0].id, store.savedLists[1].id)
    }

    func testBackupRoundTripSavedLists() throws {
        var state = AppState.seed
        state.items = threeItemsOneDone()
        state.savedLists = [
            SavedList(
                id: "l1",
                name: "Grillen",
                items: SavedList.snapshot(from: state.items)
            )
        ]
        state.staples = [Staple(name: "Milch", dept: "kuehlung")]
        let exported = try BackupCodec.encodeExport(state)
        let again = try BackupCodec.decode(exported)
        XCTAssertEqual(again.savedLists.count, 1)
        XCTAssertEqual(again.savedLists[0].id, "l1")
        XCTAssertEqual(again.savedLists[0].name, "Grillen")
        XCTAssertEqual(again.savedLists[0].items.map(\.name), ["Milch", "Butter", "Grillkohle"])
        XCTAssertEqual(again.savedLists[0].items.map(\.dept), ["kuehlung", "kuehlung", "sonstiges"])
        XCTAssertEqual(again.staples.map(\.name), ["Milch"])
        let obj = try JSONSerialization.jsonObject(with: exported) as! [String: Any]
        XCTAssertNotNil(obj["savedLists"])
        XCTAssertEqual(obj["kind"] as? String, "einkauf-backup")
    }

    func testLocalEncodeRoundTripSavedLists() throws {
        var state = AppState.seed
        state.savedLists = [
            SavedList(id: "l1", name: "Grillen", items: [Staple(name: "Milch", dept: "kuehlung")])
        ]
        state.listRevision = 4
        let data = try BackupCodec.encodeLocal(state)
        let again = try BackupCodec.decodeLocal(data)
        XCTAssertEqual(again.savedLists, state.savedLists)
        XCTAssertEqual(again.listRevision, 4)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(json["kind"] as? String, "einkauf-local")
        let encodedState = json["state"] as! [String: Any]
        XCTAssertNotNil(encodedState["savedLists"])
    }

    func testOldBackupHasEmptySavedLists() throws {
        let data = try loadFixture("einkauf-backup-ohne-staples.json")
        let state = try BackupCodec.decode(data)
        XCTAssertTrue(state.savedLists.isEmpty)
        XCTAssertTrue(state.staples.isEmpty)
        XCTAssertEqual(state.items.count, 3)
    }

    func testBuiltinStoresUntouchedAfterSavedListsRoundTrip() throws {
        var state = AppState.seed
        state.savedLists = [
            SavedList(id: "l1", name: "Drogerie", items: [Staple(name: "Klopapier", dept: "drogerie")])
        ]
        let exported = try BackupCodec.encodeExport(state)
        let again = try BackupCodec.decode(exported)
        XCTAssertEqual(Set(again.stores.map(\.id)), Set(Store.seeds.map(\.id)))
        XCTAssertTrue(again.stores.allSatisfy(\.builtin))
        XCTAssertEqual(again.stores.map(\.id), Store.seeds.map(\.id))
        XCTAssertEqual(again.savedLists.first?.name, "Drogerie")
        XCTAssertEqual(again.staples, [])
        XCTAssertEqual(again.currentStoreId, "edeka")
    }

    func testBackupIgnoresDoneOnSavedListItemsAndKeepsSeeds() throws {
        let json = """
        {"kind":"einkauf-backup","v":1,"currentStoreId":"edeka","stores":[],"items":[],"savedLists":[{"id":"l1","name":"Grillen","items":[{"name":"Milch","dept":"kuehlung","done":true}]}]}
        """
        let state = try BackupCodec.decode(Data(json.utf8))
        XCTAssertEqual(state.savedLists.count, 1)
        XCTAssertEqual(state.savedLists[0].name, "Grillen")
        XCTAssertEqual(state.savedLists[0].items.map(\.name), ["Milch"])
        XCTAssertEqual(state.savedLists[0].items.map(\.dept), ["kuehlung"])
        XCTAssertEqual(Set(state.stores.map(\.id)), Set(Store.seeds.map(\.id)))
        XCTAssertTrue(state.stores.allSatisfy(\.builtin))
        XCTAssertTrue(state.staples.isEmpty)
    }

    func testRemoveSavedList() {
        var seed = AppState.seed
        seed.items = [Item(id: "a", name: "Milch", dept: "kuehlung", done: false, added: 1, ord: 1)]
        let store = ShoppingStore(state: seed, enableSync: false)
        store.saveCurrentList(name: "Grillen")
        let id = store.savedLists[0].id
        store.removeSavedList(id: id)
        XCTAssertTrue(store.savedLists.isEmpty)
    }

    private func loadFixture(_ name: String) throws -> Data {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
            .appendingPathComponent(name)
        return try Data(contentsOf: url)
    }
}

final class StoreLayoutTests: XCTestCase {
    func testVorFirstNachLastAfterSanitize() {
        let layout = StoreLayout.sanitized(["nach", "obst", "vor", "brot"])
        XCTAssertEqual(layout.first, "vor")
        XCTAssertEqual(layout.last, "nach")
        XCTAssertEqual(layout, ["vor", "obst", "brot", "nach"])
    }

    func testCannotMoveVorOrNach() {
        let start = ["vor", "obst", "brot", "nach"]
        XCTAssertEqual(StoreLayout.move(start, id: "vor", by: 1), start)
        XCTAssertEqual(StoreLayout.move(start, id: "nach", by: -1), start)
    }

    func testMoveMiddleDept() {
        let next = StoreLayout.move(["vor", "obst", "brot", "nach"], id: "brot", by: -1)
        XCTAssertEqual(next, ["vor", "brot", "obst", "nach"])
    }

    func testSonstigesIsNotLockedAndCanMove() {
        XCTAssertFalse(StoreLayout.isLocked("sonstiges"))
        let next = StoreLayout.move(["vor", "obst", "sonstiges", "nach"], id: "sonstiges", by: -1)
        XCTAssertEqual(next, ["vor", "sonstiges", "obst", "nach"])
    }

    func testAddInsertsBeforeNach() {
        let next = StoreLayout.adding("drogerie", to: ["vor", "obst", "nach"])
        XCTAssertEqual(next.last, "nach")
        XCTAssertEqual(next, ["vor", "obst", "drogerie", "nach"])
    }

    func testCannotRemoveVor() {
        let start = ["vor", "obst", "nach"]
        XCTAssertEqual(StoreLayout.removing("vor", from: start), StoreLayout.sanitized(start))
    }

    func testResetBuiltin() {
        XCTAssertEqual(
            StoreLayout.reset(storeId: "dm", current: ["vor", "obst", "nach"]),
            Store.seeds.first { $0.id == "dm" }!.layout
        )
    }

    func testResetCustomUsesEigenesDefault() {
        XCTAssertEqual(
            StoreLayout.reset(storeId: "s-custom", current: ["vor", "obst", "brot", "nach"]),
            ["vor", "sonstiges", "nach"]
        )
    }

    func testUnused() {
        let unused = StoreLayout.unused(in: ["vor", "sonstiges", "nach"])
        XCTAssertTrue(unused.contains("obst"))
        XCTAssertFalse(unused.contains("vor"))
    }

    func testMovingReordersMiddleAndKeepsVorNach() {
        let start = ["vor", "obst", "brot", "kuehlung", "nach"]
        let next = StoreLayout.moving(start, from: IndexSet(integer: 1), to: 3)
        XCTAssertEqual(next.first, "vor")
        XCTAssertEqual(next.last, "nach")
        XCTAssertEqual(next, ["vor", "brot", "obst", "kuehlung", "nach"])
    }

    func testMovingLockedIsNoOp() {
        let start = ["vor", "obst", "brot", "nach"]
        XCTAssertEqual(StoreLayout.moving(start, from: IndexSet(integer: 0), to: 2), StoreLayout.sanitized(start))
        XCTAssertEqual(StoreLayout.moving(start, from: IndexSet(integer: 3), to: 1), StoreLayout.sanitized(start))
    }

    func testMovingPastNachStillEndsWithNach() {
        let start = ["vor", "obst", "brot", "nach"]
        let next = StoreLayout.moving(start, from: IndexSet(integer: 1), to: 4)
        XCTAssertEqual(next.first, "vor")
        XCTAssertEqual(next.last, "nach")
        XCTAssertEqual(next, ["vor", "brot", "obst", "nach"])
    }
}

final class StoreCatalogTests: XCTestCase {
    func testCreateCopiesLayoutAndIsNotBuiltin() {
        let source = Store.seeds.first { $0.id == "dm" }!
        let created = StoreCatalog.create(name: "  Mein Markt  ", copying: source, id: "s-test")
        XCTAssertEqual(created?.id, "s-test")
        XCTAssertEqual(created?.name, "Mein Markt")
        XCTAssertEqual(created?.layout, source.layout)
        XCTAssertEqual(created?.builtin, false)
    }

    func testCreateRejectsEmptyAndTruncatesName() {
        let source = Store.seeds[0]
        XCTAssertNil(StoreCatalog.create(name: "   ", copying: source, id: "s1"))
        let long = String(repeating: "a", count: 80)
        XCTAssertEqual(StoreCatalog.create(name: long, copying: source, id: "s2")?.name.count, 60)
    }

    func testDeleteCustomFallsBackToEdeka() {
        let custom = Store(id: "s-x", name: "X", layout: ["vor", "nach"], builtin: false)
        let stores = Store.seeds + [custom]
        let result = StoreCatalog.delete(id: "s-x", stores: stores, currentId: "s-x")
        XCTAssertEqual(result?.currentId, "edeka")
        XCTAssertFalse(result?.stores.contains(where: { $0.id == "s-x" }) ?? true)
        XCTAssertTrue(Store.seeds.allSatisfy { seed in result?.stores.contains(where: { $0.id == seed.id }) ?? false })
    }

    func testCannotDeleteBuiltin() {
        for seed in Store.seeds {
            XCTAssertNil(StoreCatalog.delete(id: seed.id, stores: Store.seeds, currentId: seed.id), seed.id)
        }
    }

    func testEmptyStoresMergeSeeds() throws {
        let json = """
        {"kind":"einkauf-backup","v":1,"currentStoreId":"edeka","stores":[],"items":[]}
        """
        let state = try BackupCodec.decode(Data(json.utf8))
        XCTAssertEqual(Set(state.stores.map(\.id)), Set(Store.seeds.map(\.id)))
        XCTAssertTrue(state.stores.allSatisfy(\.builtin))
    }

    func testBackupRoundTripKeepsCustomStore() throws {
        var state = AppState.seed
        let custom = StoreCatalog.create(name: "Testmarkt", copying: state.currentStore, id: "s-round")!
        state.stores.append(custom)
        state.currentStoreId = custom.id
        let exported = try BackupCodec.encodeExport(state)
        let again = try BackupCodec.decode(exported)
        XCTAssertEqual(again.currentStoreId, "s-round")
        XCTAssertEqual(again.stores.first(where: { $0.id == "s-round" })?.name, "Testmarkt")
        XCTAssertTrue(Store.seeds.allSatisfy { seed in again.stores.contains(where: { $0.id == seed.id }) })
    }

    func testTwoCustomStoresIndependentLayoutsChangeGroupOrder() {
        var state = AppState.seed
        state.items = [
            Item(id: "o", name: "Äpfel", dept: "obst", done: false, added: 1, ord: 1),
            Item(id: "b", name: "Brot", dept: "brot", done: false, added: 2, ord: 1),
            Item(id: "k", name: "Milch", dept: "kuehlung", done: false, added: 3, ord: 1)
        ]
        let marktA = StoreCatalog.create(
            name: "Markt A",
            copying: Store(id: "src-a", name: "A", layout: ["vor", "obst", "brot", "kuehlung", "nach"], builtin: false),
            id: "s-a"
        )!
        let marktB = StoreCatalog.create(
            name: "Markt B",
            copying: Store(id: "src-b", name: "B", layout: ["vor", "kuehlung", "brot", "obst", "nach"], builtin: false),
            id: "s-b"
        )!
        XCTAssertEqual(marktA.layout, ["vor", "obst", "brot", "kuehlung", "nach"])
        XCTAssertEqual(marktB.layout, ["vor", "kuehlung", "brot", "obst", "nach"])
        XCTAssertNotEqual(marktA.layout, marktB.layout)

        state.stores.append(contentsOf: [marktA, marktB])
        state.currentStoreId = marktA.id
        XCTAssertEqual(state.grouped().map(\.dept), ["obst", "brot", "kuehlung"])
        XCTAssertEqual(state.grouped().map(\.id), ["s-a|obst", "s-a|brot", "s-a|kuehlung"])

        state.currentStoreId = marktB.id
        XCTAssertEqual(state.grouped().map(\.dept), ["kuehlung", "brot", "obst"])
        XCTAssertEqual(state.grouped().map(\.id), ["s-b|kuehlung", "s-b|brot", "s-b|obst"])
    }

    func testCreateCopiesSelectedStoreThenSwitchingKeepsBothLayouts() {
        var state = AppState.seed
        let rewe = Store.seeds.first { $0.id == "rewe" }!
        let dm = Store.seeds.first { $0.id == "dm" }!
        state.currentStoreId = "rewe"
        let reweKopie = StoreCatalog.create(name: "Rewe Kopie", copying: state.currentStore, id: "s-rewe-copy")!
        XCTAssertEqual(reweKopie.layout, rewe.layout)
        state.stores.append(reweKopie)

        state.currentStoreId = "dm"
        let dmKopie = StoreCatalog.create(name: "dm Kopie", copying: state.currentStore, id: "s-dm-copy")!
        XCTAssertEqual(dmKopie.layout, dm.layout)
        XCTAssertNotEqual(reweKopie.layout, dmKopie.layout)
        state.stores.append(dmKopie)

        state.items = [
            Item(id: "d", name: "Shampoo", dept: "drogerie", done: false, added: 1, ord: 1),
            Item(id: "o", name: "Äpfel", dept: "obst", done: false, added: 2, ord: 1)
        ]
        state.currentStoreId = reweKopie.id
        XCTAssertEqual(state.grouped().map(\.dept), ["obst", "drogerie"])
        state.currentStoreId = dmKopie.id
        XCTAssertEqual(state.grouped().map(\.dept), ["drogerie", "obst"])
    }
}

@MainActor
final class ShoppingStoreSetStoreTests: XCTestCase {
    /// `groups` ist @Published und folgt dem Layout nach `setStore` (enableSync: false).
    func testSetStoreRebuildsPublishedGroupsInLayoutOrder() {
        var seed = AppState.seed
        seed.items = [
            Item(id: "o", name: "Äpfel", dept: "obst", done: false, added: 1, ord: 1),
            Item(id: "k", name: "Milch", dept: "kuehlung", done: false, added: 2, ord: 1),
            Item(id: "d", name: "Seife", dept: "drogerie", done: false, added: 3, ord: 1)
        ]
        let store = ShoppingStore(state: seed, enableSync: false)
        XCTAssertEqual(store.state.currentStoreId, "edeka")
        XCTAssertEqual(store.groups.map(\.dept), ["obst", "kuehlung", "drogerie"])
        XCTAssertEqual(store.groups.map(\.id), ["edeka|obst", "edeka|kuehlung", "edeka|drogerie"])

        store.setStore("dm")
        XCTAssertEqual(store.state.currentStoreId, "dm")
        XCTAssertEqual(store.groups.map(\.dept), ["drogerie", "obst", "kuehlung"])
        XCTAssertNotEqual(store.groups.map(\.dept), ["obst", "kuehlung", "drogerie"])
        XCTAssertEqual(store.groups.map(\.id), ["dm|drogerie", "dm|obst", "dm|kuehlung"])
        XCTAssertEqual(store.walkLines.compactMap(\.headerDept), ["drogerie", "obst", "kuehlung"])
        XCTAssertEqual(store.editRows.filter(\.isHeader).map(\.id), ["dm|h:drogerie", "dm|h:obst", "dm|h:kuehlung"])
        XCTAssertGreaterThan(store.state.listRevision, seed.listRevision)

        store.setStore("edeka")
        XCTAssertEqual(store.state.currentStoreId, "edeka")
        XCTAssertEqual(store.groups.map(\.dept), ["obst", "kuehlung", "drogerie"])
        XCTAssertEqual(store.groups.map(\.id), ["edeka|obst", "edeka|kuehlung", "edeka|drogerie"])
        XCTAssertEqual(store.walkLines.compactMap(\.headerDept), ["obst", "kuehlung", "drogerie"])
        XCTAssertEqual(store.state.watchTitle, "Edeka  Einkauf 3/0/3")
        store.toggle("o")
        XCTAssertEqual(store.walkListRows.compactMap(\.line.itemId), ["o", "k", "d"])
        XCTAssertEqual(store.walkListRows(hidingCompleted: true).compactMap(\.line.itemId), ["k", "d"])
        XCTAssertEqual(store.state.watchTitle, "Edeka  Einkauf 2/1/3")
    }

    func testSetStoreWalkLinesScreenshotItemsReorder() {
        var seed = AppState.seed
        seed.items = [
            Item(id: "k", name: "Kinderschokolade", dept: "suess", done: false, added: 1, ord: 1),
            Item(id: "t", name: "Toilettenpapier", dept: "drogerie", done: false, added: 2, ord: 1),
            Item(id: "a", name: "AXE", dept: "sonstiges", done: false, added: 3, ord: 1)
        ]
        let store = ShoppingStore(state: seed, enableSync: false)
        XCTAssertEqual(store.walkLines.compactMap(\.headerDept), ["suess", "drogerie", "sonstiges"])
        store.setStore("dm")
        XCTAssertEqual(store.walkLines.compactMap(\.headerDept), ["drogerie", "sonstiges", "suess"])
        XCTAssertEqual(Array(store.walkListRows.map(\.id).prefix(2)), ["dm|0|dm|h:drogerie", "dm|1|dm|i:t"])
        XCTAssertEqual(store.groups.first { $0.dept == "sonstiges" }?.items.map(\.id), ["a"])
        XCTAssertEqual(store.state.items.first { $0.id == "k" }?.dept, "suess")
        store.setStore("edeka")
        XCTAssertEqual(store.walkLines.compactMap(\.headerDept), ["suess", "drogerie", "sonstiges"])
        XCTAssertEqual(store.groups.first { $0.dept == "suess" }?.items.map(\.id), ["k"])
        XCTAssertEqual(store.state.items.first { $0.id == "k" }?.dept, "suess")
    }

    func testSetStoreMovesSonstigesSectionWithLayoutPosition() {
        var seed = AppState.seed
        seed.stores.append(contentsOf: [
            Store(id: "markt-a", name: "Markt A", layout: ["vor", "sonstiges", "obst", "nach"], builtin: false),
            Store(id: "markt-b", name: "Markt B", layout: ["vor", "obst", "sonstiges", "nach"], builtin: false)
        ])
        seed.items = [
            Item(id: "s", name: "AXE", dept: "sonstiges", done: false, added: 1, ord: 1),
            Item(id: "o", name: "Äpfel", dept: "obst", done: false, added: 2, ord: 1)
        ]
        seed.currentStoreId = "markt-a"
        let store = ShoppingStore(state: seed, enableSync: false)
        XCTAssertEqual(store.walkLines.compactMap(\.headerDept), ["sonstiges", "obst"])
        XCTAssertEqual(store.groups.first { $0.dept == "sonstiges" }?.items.map(\.id), ["s"])
        store.setStore("markt-b")
        XCTAssertEqual(store.walkLines.compactMap(\.headerDept), ["obst", "sonstiges"])
        XCTAssertEqual(store.groups.first { $0.dept == "sonstiges" }?.items.map(\.id), ["s"])
        XCTAssertEqual(store.groups.first { $0.dept == "sonstiges" }?.items.map(\.dept), ["sonstiges"])
        XCTAssertEqual(store.state.items.first { $0.id == "s" }?.dept, "sonstiges")
        store.setStore("markt-a")
        XCTAssertEqual(store.walkLines.compactMap(\.headerDept), ["sonstiges", "obst"])
        XCTAssertEqual(store.state.items.first { $0.id == "s" }?.dept, "sonstiges")
    }
}

@MainActor
final class ShoppingStoreDeleteStoreTests: XCTestCase {
    func testDeleteCustomStoreFallsBackToEdekaAndRebuildsGroups() {
        var seed = AppState.seed
        seed.items = [
            Item(id: "o", name: "Äpfel", dept: "obst", done: false, added: 1, ord: 1),
            Item(id: "d", name: "Seife", dept: "drogerie", done: false, added: 2, ord: 1)
        ]
        let custom = Store(
            id: "s-custom",
            name: "Mein Markt",
            layout: ["vor", "drogerie", "obst", "nach"],
            builtin: false
        )
        seed.stores.append(custom)
        seed.currentStoreId = "s-custom"
        let store = ShoppingStore(state: seed, enableSync: false)
        XCTAssertEqual(store.groups.map(\.dept), ["drogerie", "obst"])
        XCTAssertEqual(
            store.state.watchTitle,
            "\(AppState.clippedWatchStoreName("Mein Markt"))  Einkauf 2/0/2"
        )

        store.deleteStore(id: "s-custom")
        XCTAssertEqual(store.state.currentStoreId, "edeka")
        XCTAssertFalse(store.stores.contains(where: { $0.id == "s-custom" }))
        XCTAssertTrue(store.stores.contains(where: { $0.id == "edeka" }))
        XCTAssertEqual(store.groups.map(\.dept), ["obst", "drogerie"])
        XCTAssertEqual(store.state.watchTitle, "Edeka  Einkauf 2/0/2")
        XCTAssertGreaterThan(store.state.listRevision, seed.listRevision)
    }

    func testDeleteNonCurrentCustomKeepsCurrentStore() {
        var seed = AppState.seed
        seed.stores.append(Store(id: "s-x", name: "X", layout: ["vor", "nach"], builtin: false))
        seed.currentStoreId = "rewe"
        let store = ShoppingStore(state: seed, enableSync: false)
        let revision = store.state.listRevision
        store.deleteStore(id: "s-x")
        XCTAssertEqual(store.state.currentStoreId, "rewe")
        XCTAssertFalse(store.stores.contains(where: { $0.id == "s-x" }))
        XCTAssertGreaterThan(store.state.listRevision, revision)
    }

    func testDeleteBuiltinIsNoOp() {
        var seed = AppState.seed
        seed.currentStoreId = "edeka"
        let store = ShoppingStore(state: seed, enableSync: false)
        let ids = store.stores.map(\.id)
        let revision = store.state.listRevision
        store.deleteStore(id: "edeka")
        store.deleteStore(id: "aldi")
        store.deleteStore(id: "rewe")
        store.deleteStore(id: "lidl")
        store.deleteStore(id: "dm")
        store.deleteStore(id: "eigenes")
        XCTAssertEqual(store.state.currentStoreId, "edeka")
        XCTAssertEqual(store.stores.map(\.id), ids)
        XCTAssertEqual(store.state.listRevision, revision)
        XCTAssertTrue(store.stores.contains(where: { $0.id == "edeka" && $0.builtin }))
    }
}

final class GuesserTests: XCTestCase {
    func testCommonItems() {
        XCTAssertEqual(DepartmentGuesser.guess("Milch"), "kuehlung")
        XCTAssertEqual(DepartmentGuesser.guess("Äpfel"), "obst")
        XCTAssertEqual(DepartmentGuesser.guess("TK-Pizza"), "tiefkuehl")
        XCTAssertEqual(DepartmentGuesser.guess("Eistee"), "getraenke")
        XCTAssertEqual(DepartmentGuesser.guess("Chips"), "suess")
        XCTAssertEqual(DepartmentGuesser.guess("Klopapier"), "drogerie")
        XCTAssertEqual(DepartmentGuesser.guess("xyzzy-unbekannt"), "sonstiges")
    }

    func testUserMappingBeatsKeyword() {
        let key = DepartmentGuesser.mappingKey("Milch")
        XCTAssertEqual(DepartmentGuesser.guess("Milch", mappings: [key: "trocken"]), "trocken")
        XCTAssertEqual(DepartmentGuesser.guess("2x Milch", mappings: [key: "getraenke"]), "getraenke")
    }

    func testUserMappingBeatsSpecialRules() {
        XCTAssertEqual(
            DepartmentGuesser.guess("TK-Pizza", mappings: [DepartmentGuesser.mappingKey("TK-Pizza"): "trocken"]),
            "trocken"
        )
        XCTAssertEqual(
            DepartmentGuesser.guess("Eistee", mappings: [DepartmentGuesser.mappingKey("Eistee"): "kuehlung"]),
            "kuehlung"
        )
        XCTAssertEqual(
            DepartmentGuesser.guess("Chips", mappings: [DepartmentGuesser.mappingKey("Chips"): "trocken"]),
            "trocken"
        )
        XCTAssertEqual(
            DepartmentGuesser.guess("Vanilleeis", mappings: [DepartmentGuesser.mappingKey("Vanilleeis"): "suess"]),
            "suess"
        )
    }

    func testUnknownMappingFallsThroughToKeyword() {
        XCTAssertEqual(DepartmentGuesser.guess("Milch", mappings: ["milch": "nope"]), "kuehlung")
    }

    func testUserMappingDoesNotChangeKeywordDictionary() {
        let before = KeywordDictionary.source["kuehlung"]
        _ = DepartmentGuesser.guess("Milch", mappings: ["milch": "trocken"])
        XCTAssertEqual(KeywordDictionary.source["kuehlung"], before)
    }
}

final class KeywordDictionaryBrowseTests: XCTestCase {
    private let german = Locale(identifier: "de")

    func testSpeziIsUnderGetraenkeTitle() {
        let groups = KeywordDictionary.groups(from: KeywordDictionary.source)
        let drinks = groups.first { $0.title == "Getränke" }
        XCTAssertEqual(drinks?.dept, "getraenke")
        XCTAssertTrue(drinks?.words.contains("spezi") == true)
    }

    func testGroupsUseDepartmentTitlesNotRawIds() {
        let titles = KeywordDictionary.groups(from: KeywordDictionary.source).map(\.title)
        XCTAssertTrue(titles.contains("Obst & Gemüse"))
        XCTAssertTrue(titles.contains("Getränke"))
        XCTAssertFalse(titles.contains("obst"))
        XCTAssertFalse(titles.contains("getraenke"))
        XCTAssertFalse(titles.contains("Vor dem Einkauf"))
        XCTAssertFalse(titles.contains("Sonstiges"))
    }

    func testDedupSkipEmptyAndGermanSort() {
        let source = [
            "getraenke": "spezi, wasser, ,spezi,Cola,  ",
            "obst": ""
        ]
        let groups = KeywordDictionary.groups(from: source)
        XCTAssertEqual(groups.map(\.title), ["Getränke"])
        XCTAssertEqual(groups[0].words, ["Cola", "spezi", "wasser"])
    }

    func testWordsSortedAndUniquePerDepartment() {
        for group in KeywordDictionary.groups(from: KeywordDictionary.source) {
            XCTAssertFalse(group.words.isEmpty)
            XCTAssertFalse(group.words.contains { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
            let folded = group.words.map { $0.lowercased(with: german) }
            XCTAssertEqual(Set(folded).count, folded.count, group.title)
            let sorted = group.words.sorted { $0.compare($1, locale: german) == .orderedAscending }
            XCTAssertEqual(group.words, sorted, group.title)
        }
    }

    func testSearchKeepsMatchingWordsOnly() {
        let groups = KeywordDictionary.groups(from: KeywordDictionary.source, matching: "spezi")
        XCTAssertEqual(groups.map(\.title), ["Getränke"])
        XCTAssertEqual(groups[0].words, ["spezi"])
    }

    func testLearnedMappingsSearch() {
        let maps = ["milch": "kuehlung", "spezi": "getraenke", "apfel": "obst", "nope": "unknown"]
        let all = KeywordDictionary.learnedMappings(from: maps)
        XCTAssertEqual(all.map(\.key), ["apfel", "milch", "spezi"])
        XCTAssertEqual(all.map(\.dept), ["obst", "kuehlung", "getraenke"])
        let filtered = KeywordDictionary.learnedMappings(from: maps, matching: "SPEZI")
        XCTAssertEqual(filtered.map(\.key), ["spezi"])
        XCTAssertEqual(filtered.first?.dept, "getraenke")
        XCTAssertTrue(KeywordDictionary.learnedMappings(from: maps, matching: "xyz").isEmpty)
        XCTAssertTrue(KeywordDictionary.learnedMappings(from: [:]).isEmpty)
    }
}

@MainActor
final class ShoppingStoreMappingTests: XCTestCase {
    func testSetMappingWritesMappingKey() {
        let store = ShoppingStore(state: .seed, enableSync: false)
        store.setMapping("2x Milch", dept: "trocken")
        XCTAssertEqual(store.state.mappings["milch"], "trocken")
        XCTAssertNil(store.state.mappings["2x milch"])
        XCTAssertEqual(DepartmentGuesser.guess("Milch", mappings: store.state.mappings), "trocken")
        XCTAssertGreaterThan(store.state.listRevision, 0)
    }

    func testRemoveMappingDropsKey() {
        let store = ShoppingStore(state: .seed, enableSync: false)
        store.setMapping("Milch", dept: "trocken")
        XCTAssertEqual(store.state.mappings["milch"], "trocken")
        store.removeMapping("milch")
        XCTAssertNil(store.state.mappings["milch"])
        XCTAssertEqual(DepartmentGuesser.guess("Milch", mappings: store.state.mappings), "kuehlung")
    }

    func testSetMappingUnknownDeptAndEmptyAreNoOp() {
        let store = ShoppingStore(state: .seed, enableSync: false)
        store.setMapping("Milch", dept: "nope")
        store.setMapping("   ", dept: "kuehlung")
        XCTAssertTrue(store.state.mappings.isEmpty)
        XCTAssertEqual(store.state.listRevision, 0)
        store.setMapping("Milch", dept: "trocken")
        let rev = store.state.listRevision
        store.setMapping("Milch", dept: "trocken")
        XCTAssertEqual(store.state.listRevision, rev)
        store.removeMapping("missing")
        XCTAssertEqual(store.state.listRevision, rev)
        XCTAssertEqual(store.state.mappings["milch"], "trocken")
    }

    func testExportKeepsMappingsField() throws {
        let store = ShoppingStore(state: .seed, enableSync: false)
        store.setMapping("Äpfel", dept: "brot")
        let exported = try BackupCodec.encodeExport(store.state)
        let obj = try JSONSerialization.jsonObject(with: exported) as! [String: Any]
        let maps = obj["mappings"] as? [String: String]
        XCTAssertEqual(maps?[DepartmentGuesser.mappingKey("Äpfel")], "brot")
        XCTAssertNil(obj["learnedMappings"])
        XCTAssertNil(obj["userMappings"])
        XCTAssertEqual(obj["kind"] as? String, "einkauf-backup")
        let again = try BackupCodec.decode(exported)
        XCTAssertEqual(again.mappings[DepartmentGuesser.mappingKey("Äpfel")], "brot")
    }
}

final class ItemEditingTests: XCTestCase {
    func testEmptyRenameIsNoOp() {
        let item = Item(id: "i1", name: "Milch", dept: "kuehlung", done: false, added: 1, ord: 1)
        XCTAssertNil(ItemEditing.rename(item, to: "  ", mappings: [:]))
    }

    func testRenameKeepsDeptWhenSameKey() {
        let item = Item(id: "i1", name: "Milch", dept: "kuehlung", done: false, added: 1, ord: 1)
        let result = ItemEditing.rename(item, to: "Milch", mappings: [:])
        XCTAssertEqual(result?.0.dept, "kuehlung")
        XCTAssertEqual(result?.0.name, "Milch")
    }

    func testRenameGuessesDeptWhenKeyChanges() {
        let item = Item(id: "i1", name: "Milch", dept: "kuehlung", done: false, added: 1, ord: 1)
        let result = ItemEditing.rename(item, to: "Äpfel", mappings: [:])
        XCTAssertEqual(result?.0.name, "Äpfel")
        XCTAssertEqual(result?.0.dept, "obst")
        XCTAssertEqual(result?.1[DepartmentGuesser.mappingKey("Äpfel")], "obst")
    }

    func testSetDeptWritesMapping() {
        let item = Item(id: "i1", name: "Milch", dept: "kuehlung", done: false, added: 1, ord: 1)
        let result = ItemEditing.setDept(item, dept: "trocken", mappings: [:])
        XCTAssertEqual(result?.0.dept, "trocken")
        XCTAssertEqual(result?.1["milch"], "trocken")
    }

    func testMoveReordersWithinDeptOnly() {
        let items = [
            Item(id: "a", name: "A", dept: "obst", done: false, added: 1, ord: 1),
            Item(id: "b", name: "B", dept: "obst", done: false, added: 2, ord: 2),
            Item(id: "c", name: "C", dept: "brot", done: false, added: 3, ord: 1)
        ]
        let moved = ItemEditing.move(allItems: items, dept: "obst", from: IndexSet(integer: 1), to: 0)
        XCTAssertEqual(moved.filter { $0.dept == "obst" }.sorted(by: ListGrouping.sortItems).map(\.id), ["b", "a"])
        XCTAssertEqual(moved.first { $0.id == "c" }?.ord, 1)
    }

    func testFlattenedRowsHeadersThenItems() {
        let store = edeka
        let items = sampleItems
        let rows = ItemEditing.rows(items: items, store: store)
        XCTAssertEqual(rows.map(\.id), ["edeka|h:vor", "edeka|i:v", "edeka|h:obst", "edeka|i:a", "edeka|i:b", "edeka|h:brot", "edeka|i:br", "edeka|h:nach", "edeka|i:n"])
    }

    func testDropSlotBeforeItemIsThatDept() {
        let remaining: [ItemEditing.Row] = [
            .header(storeId: "edeka", dept: "obst"),
            .item(storeId: "edeka", Item(id: "a", name: "A", dept: "obst", done: false, added: 1, ord: 1)),
            .header(storeId: "edeka", dept: "brot"),
            .item(storeId: "edeka", Item(id: "br", name: "Brot", dept: "brot", done: false, added: 2, ord: 1))
        ]
        let slot = ItemEditing.dropSlot(remaining: remaining, destination: 3)
        XCTAssertEqual(slot?.dept, "brot")
        XCTAssertEqual(slot?.beforeId, "br")
    }

    func testDropSlotBeforeHeaderAppendsToPrevious() {
        let remaining: [ItemEditing.Row] = [
            .header(storeId: "edeka", dept: "obst"),
            .item(storeId: "edeka", Item(id: "a", name: "A", dept: "obst", done: false, added: 1, ord: 1)),
            .header(storeId: "edeka", dept: "brot"),
            .item(storeId: "edeka", Item(id: "br", name: "Brot", dept: "brot", done: false, added: 2, ord: 1))
        ]
        let slot = ItemEditing.dropSlot(remaining: remaining, destination: 2)
        XCTAssertEqual(slot?.dept, "obst")
        XCTAssertNil(slot?.beforeId)
    }

    func testDropSlotAtEndIsLastDept() {
        let remaining: [ItemEditing.Row] = [
            .header(storeId: "edeka", dept: "vor"),
            .item(storeId: "edeka", Item(id: "v", name: "Tasche", dept: "vor", done: false, added: 1, ord: 1)),
            .header(storeId: "edeka", dept: "nach"),
            .item(storeId: "edeka", Item(id: "n", name: "Pfand", dept: "nach", done: false, added: 2, ord: 1))
        ]
        let slot = ItemEditing.dropSlot(remaining: remaining, destination: 4)
        XCTAssertEqual(slot?.dept, "nach")
        XCTAssertNil(slot?.beforeId)
    }

    func testMoveRowsAcrossDeptUpdatesDeptMappingAndOrder() {
        let items = sampleItems
        let rows = ItemEditing.rows(items: items, store: edeka)
        // Birne (idx 4) vor Brot (idx 6) → nach Entfernen destination 5
        XCTAssertEqual(rows[4].id, "edeka|i:b")
        XCTAssertEqual(rows[6].id, "edeka|i:br")
        let result = ItemEditing.moveRows(
            allItems: items,
            store: edeka,
            from: IndexSet(integer: 4),
            to: 5,
            mappings: [:]
        )
        XCTAssertEqual(result?.items.first { $0.id == "b" }?.dept, "brot")
        XCTAssertEqual(result?.mappings[DepartmentGuesser.mappingKey("Birne")], "brot")
        let brot = result!.items.filter { $0.dept == "brot" }.sorted(by: ListGrouping.sortItems).map(\.id)
        XCTAssertEqual(brot, ["b", "br"])
        XCTAssertEqual(result?.items.first { $0.id == "a" }?.dept, "obst")
    }

    func testMoveRowsIntoVorAndNach() {
        let items = sampleItems
        // Äpfel (idx 3) ans Ende von vor: vor obst-Header (idx 2) nach Entfernen von 3 → dest 2
        let toVor = ItemEditing.moveRows(
            allItems: items,
            store: edeka,
            from: IndexSet(integer: 3),
            to: 2,
            mappings: [:]
        )
        XCTAssertEqual(toVor?.items.first { $0.id == "a" }?.dept, "vor")
        let vor = toVor!.items.filter { $0.dept == "vor" }.sorted(by: ListGrouping.sortItems).map(\.id)
        XCTAssertEqual(vor, ["v", "a"])

        // Tasche (idx 1) ans Ende von nach
        let rows = ItemEditing.rows(items: items, store: edeka)
        XCTAssertEqual(rows[1].id, "edeka|i:v")
        let afterRemoveCount = rows.count - 1
        let toNach = ItemEditing.moveRows(
            allItems: items,
            store: edeka,
            from: IndexSet(integer: 1),
            to: afterRemoveCount,
            mappings: [:]
        )
        XCTAssertEqual(toNach?.items.first { $0.id == "v" }?.dept, "nach")
        let nach = toNach!.items.filter { $0.dept == "nach" }.sorted(by: ListGrouping.sortItems).map(\.id)
        XCTAssertEqual(nach, ["n", "v"])
    }

    func testMoveRowsSamePositionIsNoOp() {
        let items = sampleItems
        // Äpfel (idx 3) bleibt vor Birne: nach Entfernen dest zeigt auf Birne (idx 3)
        let result = ItemEditing.moveRows(
            allItems: items,
            store: edeka,
            from: IndexSet(integer: 3),
            to: 3,
            mappings: ["äpfel": "obst"]
        )
        XCTAssertNil(result)
    }

    func testMoveRowsHeaderSourceIsNoOp() {
        let result = ItemEditing.moveRows(
            allItems: sampleItems,
            store: edeka,
            from: IndexSet(integer: 0),
            to: 4,
            mappings: [:]
        )
        XCTAssertNil(result)
    }

    func testMoveRowsWithinDeptViaFlattenedList() {
        let items = sampleItems
        // Birne (4) vor Äpfel: nach Entfernen dest = 3 (Äpfel)
        let result = ItemEditing.moveRows(
            allItems: items,
            store: edeka,
            from: IndexSet(integer: 4),
            to: 3,
            mappings: [:]
        )
        let obst = result!.items.filter { $0.dept == "obst" }.sorted(by: ListGrouping.sortItems).map(\.id)
        XCTAssertEqual(obst, ["b", "a"])
        XCTAssertEqual(result?.items.first { $0.id == "b" }?.dept, "obst")
    }

    func testItemIDsSkipsHeaders() {
        let rows = ItemEditing.rows(items: sampleItems, store: edeka)
        let ids = ItemEditing.itemIDs(in: rows, at: IndexSet([0, 1, 3]))
        XCTAssertEqual(ids, ["v", "a"])
    }

    private var edeka: Store { Store.seeds.first { $0.id == "edeka" }! }

    private var sampleItems: [Item] {
        [
            Item(id: "v", name: "Tasche", dept: "vor", done: false, added: 1, ord: 1),
            Item(id: "a", name: "Äpfel", dept: "obst", done: false, added: 2, ord: 1),
            Item(id: "b", name: "Birne", dept: "obst", done: false, added: 3, ord: 2),
            Item(id: "br", name: "Brot", dept: "brot", done: false, added: 4, ord: 1),
            Item(id: "n", name: "Pfand", dept: "nach", done: false, added: 5, ord: 1)
        ]
    }
}

final class BackupShareTests: XCTestCase {
    func testStampedFilenameMatchesHTML() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let date = calendar.date(from: DateComponents(year: 2026, month: 9, day: 1, hour: 19, minute: 7))!
        XCTAssertEqual(
            BackupShare.stampedFilename(date: date, timeZone: TimeZone(secondsFromGMT: 0)!),
            "20260901_1907-einkauf-backup.json"
        )
        XCTAssertEqual(
            BackupShare.stampedFilename(stem: BackupShare.todoStem, date: date, timeZone: TimeZone(secondsFromGMT: 0)!),
            "20260901_1907-todo-liste.json"
        )
    }
}

final class ListShareTests: XCTestCase {
    private var utc: TimeZone { TimeZone(secondsFromGMT: 0)! }

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        return calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    func testStampedFilenameUsesStoreSlug() {
        XCTAssertEqual(
            ListShare.stampedFilename(storeName: "Edeka", date: date(2026, 9, 2, 16, 39), timeZone: utc),
            "20260902_1639-einkauf-edeka.pdf"
        )
        XCTAssertEqual(
            ListShare.stampedFilename(storeName: "Eigenes Layout", date: date(2026, 9, 2, 16, 39), timeZone: utc),
            "20260902_1639-einkauf-eigenes-layout.pdf"
        )
    }

    func testGermanStoreSlug() {
        XCTAssertEqual(ListShare.storeSlug("Edeka"), "edeka")
        XCTAssertEqual(ListShare.storeSlug("dm"), "dm")
        XCTAssertEqual(ListShare.storeSlug("Eigenes Layout"), "eigenes-layout")
        XCTAssertEqual(ListShare.storeSlug("Müller Süd"), "mueller-sued")
        XCTAssertEqual(ListShare.storeSlug("  "), "laden")
        XCTAssertEqual(ListShare.storeSlug("Aldi!!!"), "aldi")
    }

    func testWriteTempFileUsesSlug() throws {
        let data = Data("%PDF-1.4\n".utf8)
        let url = try ListShare.writeTempFile(
            data: data,
            storeName: "Edeka",
            date: date(2026, 9, 2, 16, 41),
            timeZone: utc
        )
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertEqual(url.lastPathComponent, "20260902_1641-einkauf-edeka.pdf")
        XCTAssertEqual(try Data(contentsOf: url), data)
    }

    func testTodoFilenameIsTodoListeStem() {
        XCTAssertEqual(ListShare.todoStem, "todo-liste")
        XCTAssertEqual(
            ListShare.stampedTodoFilename(date: date(2026, 9, 4, 15, 39), timeZone: utc),
            "20260904_1539-todo-liste.pdf"
        )
    }

    func testWriteTodoTempFile() throws {
        let data = Data("%PDF-1.4-todo\n".utf8)
        let url = try ListShare.writeTodoTempFile(
            data: data,
            date: date(2026, 9, 4, 15, 40),
            timeZone: utc
        )
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertEqual(url.lastPathComponent, "20260904_1540-todo-liste.pdf")
        XCTAssertEqual(try Data(contentsOf: url), data)
    }
}

final class ThemeTokenTests: XCTestCase {
    func testVintageLight() {
        let t = ThemeRGB.tokens(palette: .vintage, dark: false)
        XCTAssertEqual(t.paper, 0xF3EEE4)
        XCTAssertEqual(t.ink, 0x1C1814)
        XCTAssertEqual(t.oxide, 0x9C3424)
        XCTAssertEqual(t.rule, 0xD2C8B8)
    }

    func testVintageDark() {
        let t = ThemeRGB.tokens(palette: .vintage, dark: true)
        XCTAssertEqual(t.paper, 0x14110E)
        XCTAssertEqual(t.ink, 0xF3EEE4)
        XCTAssertEqual(t.oxide, 0xE07060)
        XCTAssertEqual(t.rule, 0x3D362C)
    }

    func testNavyLightAndDark() {
        let light = ThemeRGB.tokens(palette: .navy, dark: false)
        XCTAssertEqual(light.paper, 0xF0F4FF)
        XCTAssertEqual(light.ink, 0x08102A)
        XCTAssertEqual(light.oxide, 0x2060DF)
        let dark = ThemeRGB.tokens(palette: .navy, dark: true)
        XCTAssertEqual(dark.paper, 0x060C1A)
        XCTAssertEqual(dark.oxide, 0x4A94FF)
        XCTAssertEqual(dark.ink, 0xEDF2FF)
    }

    func testThemePreferenceMapsColorScheme() {
        XCTAssertEqual(AppThemePreference.parse(nil), .system)
        XCTAssertEqual(AppThemePreference.parse("system"), .system)
        XCTAssertEqual(AppThemePreference.parse("light"), .light)
        XCTAssertEqual(AppThemePreference.parse("dark"), .dark)
        XCTAssertNil(AppThemePreference.system.preferredColorScheme)
        XCTAssertEqual(AppThemePreference.light.preferredColorScheme, .light)
        XCTAssertEqual(AppThemePreference.dark.preferredColorScheme, .dark)
    }
}

final class SpeechItemSplitterTests: XCTestCase {
    func testCommaUndUndKeepsQuantity() {
        XCTAssertEqual(
            SpeechItemSplitter.items(from: "Milch, Butter und zwei Eier"),
            ["Milch", "Butter", "zwei Eier"]
        )
    }

    func testSemicolonSowieAndNewlines() {
        XCTAssertEqual(
            SpeechItemSplitter.items(from: "Milch; Butter sowie Brot"),
            ["Milch", "Butter", "Brot"]
        )
        XCTAssertEqual(
            SpeechItemSplitter.items(from: "Milch\nButter\nzwei Eier"),
            ["Milch", "Butter", "zwei Eier"]
        )
    }

    func testTrimCollapseDropEmpty() {
        XCTAssertEqual(
            SpeechItemSplitter.items(from: "  Milch ,  , Butter  und   zwei   Eier  "),
            ["Milch", "Butter", "zwei Eier"]
        )
        XCTAssertEqual(SpeechItemSplitter.items(from: "  "), [])
        XCTAssertEqual(SpeechItemSplitter.items(from: ", und ;"), [])
    }

    func testDoesNotSplitHundertOrGlueUnd() {
        XCTAssertEqual(SpeechItemSplitter.items(from: "hundert"), ["hundert"])
        XCTAssertEqual(SpeechItemSplitter.items(from: "MilchundButter"), ["MilchundButter"])
    }

    func testCaseInsensitiveUnd() {
        XCTAssertEqual(
            SpeechItemSplitter.items(from: "Milch UND Butter"),
            ["Milch", "Butter"]
        )
        XCTAssertEqual(
            SpeechItemSplitter.items(from: "Milch Sowie Butter"),
            ["Milch", "Butter"]
        )
    }

    func testStripsLeadingEinkaufTrigger() {
        XCTAssertEqual(SpeechItemSplitter.strippingTriggerPrefix("Einkauf Milch, Butter"), "Milch, Butter")
        XCTAssertEqual(SpeechItemSplitter.strippingTriggerPrefix("Einkauf: Milch"), "Milch")
        XCTAssertEqual(SpeechItemSplitter.strippingTriggerPrefix("einkauf:Milch"), "Milch")
        XCTAssertEqual(SpeechItemSplitter.strippingTriggerPrefix("Einkauf"), "")
        XCTAssertEqual(SpeechItemSplitter.strippingTriggerPrefix("Einkaufen Milch"), "Einkaufen Milch")
        XCTAssertEqual(
            SpeechItemSplitter.items(from: SpeechItemSplitter.strippingTriggerPrefix("Einkauf: Milch, Butter und Eier")),
            ["Milch", "Butter", "Eier"]
        )
    }

    func testStripsLeadingBesorgenTrigger() {
        XCTAssertEqual(SpeechItemSplitter.strippingTriggerPrefix("Besorgen Milch, Butter"), "Milch, Butter")
        XCTAssertEqual(SpeechItemSplitter.strippingTriggerPrefix("Besorgen: Milch"), "Milch")
        XCTAssertEqual(SpeechItemSplitter.strippingTriggerPrefix("besorgen:Milch"), "Milch")
        XCTAssertEqual(SpeechItemSplitter.strippingTriggerPrefix("Besorgen"), "")
        XCTAssertEqual(SpeechItemSplitter.strippingTriggerPrefix("Besorgnis Milch"), "Besorgnis Milch")
        XCTAssertEqual(
            SpeechItemSplitter.items(from: SpeechItemSplitter.strippingTriggerPrefix("Besorgen: Milch, Butter und Eier")),
            ["Milch", "Butter", "Eier"]
        )
    }

    func testStripsLeadingTodoTriggerNotBesorgen() {
        XCTAssertEqual(SpeechItemSplitter.strippingTodoTriggerPrefix("To Do Steuer, Anruf"), "Steuer, Anruf")
        XCTAssertEqual(SpeechItemSplitter.strippingTodoTriggerPrefix("To Do: Milch"), "Milch")
        XCTAssertEqual(SpeechItemSplitter.strippingTodoTriggerPrefix("todo:Milch"), "Milch")
        XCTAssertEqual(SpeechItemSplitter.strippingTodoTriggerPrefix("To-Do Milch"), "Milch")
        XCTAssertEqual(SpeechItemSplitter.strippingTodoTriggerPrefix("Todo Rechnung bezahlen"), "Rechnung bezahlen")
        XCTAssertEqual(SpeechItemSplitter.strippingTodoTriggerPrefix("Aufgaben: Rechnung bezahlen"), "Rechnung bezahlen")
        XCTAssertEqual(SpeechItemSplitter.strippingTodoTriggerPrefix("Aufgaben Katze füttern"), "Katze füttern")
        XCTAssertEqual(SpeechItemSplitter.strippingTodoTriggerPrefix("To Do"), "")
        XCTAssertEqual(SpeechItemSplitter.strippingTodoTriggerPrefix("Aufgaben"), "")
        XCTAssertEqual(SpeechItemSplitter.strippingTodoTriggerPrefix("Today Milch"), "Today Milch")
        XCTAssertEqual(SpeechItemSplitter.strippingTodoTriggerPrefix("Besorgen Milch"), "Besorgen Milch")
        XCTAssertEqual(SpeechItemSplitter.strippingTodoTriggerPrefix("Aufgabenliste Milch"), "Aufgabenliste Milch")
        XCTAssertEqual(
            SpeechItemSplitter.items(from: SpeechItemSplitter.strippingTodoTriggerPrefix("To Do: Steuer und Anruf")),
            ["Steuer", "Anruf"]
        )
        XCTAssertEqual(
            SpeechItemSplitter.items(from: SpeechItemSplitter.strippingTodoTriggerPrefix("Rechnung bezahlen")),
            ["Rechnung bezahlen"]
        )
        XCTAssertEqual(
            SpeechItemSplitter.items(from: SpeechItemSplitter.strippingTodoTriggerPrefix("Katze füttern und Müll rausbringen")),
            ["Katze füttern", "Müll rausbringen"]
        )
        XCTAssertEqual(
            SpeechItemSplitter.items(from: SpeechItemSplitter.strippingTodoTriggerPrefix("Aufgaben: Rechnung bezahlen")),
            ["Rechnung bezahlen"]
        )
        XCTAssertEqual(
            SpeechItemSplitter.items(from: SpeechItemSplitter.strippingTodoTriggerPrefix("Todo Katze füttern und Müll rausbringen")),
            ["Katze füttern", "Müll rausbringen"]
        )
        XCTAssertEqual(SpeechItemSplitter.todoConfirmation(addedCount: 0), "Keine Aufgaben erkannt.")
        XCTAssertEqual(SpeechItemSplitter.todoConfirmation(addedCount: 1), "1 Aufgabe hinzugefügt.")
        XCTAssertEqual(SpeechItemSplitter.todoConfirmation(addedCount: 3), "3 Aufgaben hinzugefügt.")
    }

    func testConfirmationCopy() {
        XCTAssertEqual(SpeechItemSplitter.confirmation(addedCount: 0), "Keine Artikel erkannt.")
        XCTAssertEqual(SpeechItemSplitter.confirmation(addedCount: 1), "1 Artikel hinzugefügt.")
        XCTAssertEqual(SpeechItemSplitter.confirmation(addedCount: 3), "3 Artikel hinzugefügt.")
    }
}

@MainActor
final class SpeechAddItemsTests: XCTestCase {
    func testAddItemsFromSpeechSplitsAndGuesses() {
        let store = ShoppingStore(state: .seed, enableSync: false)
        XCTAssertEqual(store.addItems(fromSpeech: "Milch, Butter und zwei Eier"), 3)
        XCTAssertEqual(store.state.items.map(\.name), ["Milch", "Butter", "zwei Eier"])
        XCTAssertEqual(store.state.items.map(\.dept), ["kuehlung", "kuehlung", "kuehlung"])
        XCTAssertEqual(store.state.listRevision, 1)
    }

    func testAddItemsFromSpeechEmptyAddsNothing() {
        let store = ShoppingStore(state: .seed, enableSync: false)
        XCTAssertEqual(store.addItems(fromSpeech: "  "), 0)
        XCTAssertTrue(store.state.items.isEmpty)
        XCTAssertEqual(store.state.listRevision, 0)
        XCTAssertEqual(store.addItems(fromSpeech: "Einkauf"), 0)
        XCTAssertTrue(store.state.items.isEmpty)
    }

    func testAddItemsFromSpeechStripsTriggerAndPersistsOnce() {
        let store = ShoppingStore(state: .seed, enableSync: false)
        XCTAssertEqual(store.addItems(fromSpeech: "Einkauf: Milch, Butter und zwei Eier"), 3)
        XCTAssertEqual(store.state.items.map(\.name), ["Milch", "Butter", "zwei Eier"])
        XCTAssertEqual(store.state.listRevision, 1)
    }

    func testAddItemsFromSpeechStripsBesorgenTrigger() {
        let store = ShoppingStore(state: .seed, enableSync: false)
        XCTAssertEqual(store.addItems(fromSpeech: "Besorgen: Milch und Butter"), 2)
        XCTAssertEqual(store.state.items.map(\.name), ["Milch", "Butter"])
        XCTAssertEqual(store.state.listRevision, 1)
    }

}

final class SiriPendingAddsTests: XCTestCase {
    private func tempQueueURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("einkauf-siri-pending-\(UUID().uuidString).json")
    }

    func testEnqueueThenDrainPreservesOrder() {
        let url = tempQueueURL()
        defer { try? FileManager.default.removeItem(at: url) }
        SiriPendingAdds.enqueue("Milch, Butter", at: url)
        SiriPendingAdds.enqueue("Eier", at: url)
        XCTAssertEqual(SiriPendingAdds.drain(at: url), ["Milch, Butter", "Eier"])
        XCTAssertEqual(SiriPendingAdds.drain(at: url), [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testEnqueueStripsTriggerAndSkipsBlank() {
        let url = tempQueueURL()
        defer { try? FileManager.default.removeItem(at: url) }
        SiriPendingAdds.enqueue("  ", at: url)
        SiriPendingAdds.enqueue("Besorgen", at: url)
        SiriPendingAdds.enqueue("Besorgen: Milch und Butter", at: url)
        SiriPendingAdds.enqueue("Einkauf: Eier", at: url)
        XCTAssertEqual(SiriPendingAdds.drain(at: url), ["Milch und Butter", "Eier"])
    }

    func testConsumeSiriPendingAddsDrainsOntoLiveStore() {
        let url = tempQueueURL()
        defer { try? FileManager.default.removeItem(at: url) }
        SiriPendingAdds.enqueue("Besorgen: Milch, Butter und zwei Eier", at: url)
        let pending = SiriPendingAdds.drain(at: url)
        let store = ShoppingStore(state: .seed, enableSync: false)
        for speech in pending {
            store.addItems(fromSpeech: speech)
        }
        XCTAssertEqual(store.state.items.map(\.name), ["Milch", "Butter", "zwei Eier"])
        XCTAssertEqual(store.state.items.map(\.dept), ["kuehlung", "kuehlung", "kuehlung"])
        XCTAssertEqual(store.state.listRevision, 1)
        XCTAssertEqual(SiriPendingAdds.drain(at: url), [])
    }

    func testEnqueueThenDrainViaSuiteDefaults() {
        let suite = "group.net.tschelle.einkauf.test.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            XCTFail("UserDefaults(suiteName:) must accept a suite name")
            return
        }
        defer { defaults.removePersistentDomain(forName: suite) }
        SiriPendingAdds.enqueue("Milch, Butter", defaults: defaults)
        SiriPendingAdds.enqueue("Eier", defaults: defaults)
        XCTAssertEqual(SiriPendingAdds.drain(defaults: defaults), ["Milch, Butter", "Eier"])
        XCTAssertEqual(SiriPendingAdds.drain(defaults: defaults), [])
        XCTAssertNil(defaults.stringArray(forKey: SiriPendingAdds.defaultsKey))
    }

    func testSuiteDefaultsPreferredOverFileWhenBothPresent() {
        let suite = "group.net.tschelle.einkauf.test.\(UUID().uuidString)"
        let url = tempQueueURL()
        guard let defaults = UserDefaults(suiteName: suite) else {
            XCTFail("UserDefaults(suiteName:) must accept a suite name")
            return
        }
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: url)
        }
        SiriPendingAdds.enqueue("Suite-Milch", defaults: defaults)
        SiriPendingAdds.enqueue("Datei-Butter", at: url)
        XCTAssertEqual(SiriPendingAdds.drain(defaults: defaults, at: url), ["Suite-Milch"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }
}

final class MakeIDTests: XCTestCase {
    /// watchOS arm64_32: `Int` is 32-bit; epoch millis (~1.7e12) overflow Int32.max.
    func testMakeIDDoesNotTrapOnEpochMillis() {
        let millis = Date().timeIntervalSince1970 * 1000
        XCTAssertGreaterThan(millis, Double(Int32.max))
        let t = Int64(millis)
        XCTAssertGreaterThan(t, Int64(Int32.max))
        XCTAssertFalse(String(t, radix: 36).isEmpty)

        let items = (0..<8).map { _ in Item.makeID() }
        let lists = (0..<8).map { _ in SavedList.makeID() }
        let stores = (0..<8).map { _ in StoreCatalog.makeID() }
        XCTAssertTrue(items.allSatisfy { $0.hasPrefix("i") && $0.count > 1 })
        XCTAssertTrue(lists.allSatisfy { $0.hasPrefix("l") && $0.count > 1 })
        XCTAssertTrue(stores.allSatisfy { $0.hasPrefix("s") && $0.count > 1 })
        XCTAssertEqual(Set(items).count, items.count)
        XCTAssertEqual(Set(lists).count, lists.count)
        XCTAssertEqual(Set(stores).count, stores.count)
    }
}
