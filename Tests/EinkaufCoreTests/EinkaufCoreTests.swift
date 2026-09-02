import XCTest
@testable import EinkaufCore

final class BackupCodecTests: XCTestCase {
    func testFixtureIsBackupAndKeepsItems() throws {
        let data = try loadFixture("einkauf-backup.json")
        let state = try BackupCodec.decode(data)
        XCTAssertEqual(state.currentStoreId, "edeka")
        XCTAssertEqual(state.items.count, 14)
        XCTAssertEqual(state.staples.count, 3)
        XCTAssertTrue(state.stores.contains(where: { $0.id == "rewe" }))
        XCTAssertEqual(state.items.first(where: { $0.id == "i014unk" })?.dept, "sonstiges")
    }

    func testMissingStaplesIsFine() throws {
        let data = try loadFixture("einkauf-backup-ohne-staples.json")
        let state = try BackupCodec.decode(data)
        XCTAssertTrue(state.staples.isEmpty)
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
        let obj = try JSONSerialization.jsonObject(with: exported) as! [String: Any]
        XCTAssertEqual(obj["kind"] as? String, "einkauf-backup")
        XCTAssertEqual(obj["walkMode"] as? Bool, true)
        XCTAssertNil(obj["listRevision"])
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
        let ids = state.grouped().map(\.id)
        XCTAssertEqual(ids.first, "vor")
        XCTAssertEqual(ids.last, "nach")
        XCTAssertEqual(ids, ["vor", "obst", "bedienung", "brot", "kuehlung", "tiefkuehl", "trocken", "suess", "getraenke", "drogerie", "sonstiges", "nach"])
    }

    func testSortByOrdInsideDept() {
        let items = [
            Item(id: "b", name: "B", dept: "obst", done: false, added: 2, ord: 20),
            Item(id: "a", name: "A", dept: "obst", done: false, added: 1, ord: 10)
        ]
        let store = Store.seeds.first { $0.id == "edeka" }!
        let groups = ListGrouping.groups(items: items, store: store)
        XCTAssertEqual(groups.first { $0.id == "obst" }?.items.map(\.id), ["a", "b"])
    }

    func testAldiPutsBedienungAfterLayout() {
        let items = [
            Item(id: "1", name: "Gouda", dept: "bedienung", done: false, added: 1, ord: 1),
            Item(id: "2", name: "Äpfel", dept: "obst", done: false, added: 1, ord: 1),
            Item(id: "3", name: "Nachher", dept: "nach", done: false, added: 1, ord: 1)
        ]
        let store = Store.seeds.first { $0.id == "aldi" }!
        let ids = ListGrouping.groups(items: items, store: store).map(\.id)
        XCTAssertEqual(ids.first, "obst")
        XCTAssertEqual(ids.last, "nach")
        XCTAssertEqual(ids, ["obst", "bedienung", "nach"])
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
        XCTAssertEqual(AppState.seed.doneCount, 0)
        XCTAssertEqual(AppState.seed.items.count, 0)
        XCTAssertEqual(AppState.seed.progressLabel, "0/0")
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
        XCTAssertEqual(state.progressLabel, "2/3")
        XCTAssertEqual(state.openCount, 1)
    }

    func testAllDone() {
        var state = AppState.seed
        state.items = [
            Item(id: "a", name: "A", dept: "obst", done: true, added: 1, ord: 1),
            Item(id: "b", name: "B", dept: "brot", done: true, added: 2, ord: 1)
        ]
        XCTAssertEqual(state.progressLabel, "2/2")
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
        local.items = [Item(id: "old", name: "Alt", dept: "obst", done: false, added: 1, ord: 1)]
        var remote = AppState.seed
        remote.listRevision = 5
        remote.items = [Item(id: "new", name: "Neu", dept: "obst", done: false, added: 2, ord: 1)]
        let merged = StateMerge.merge(local: local, remote: remote)
        XCTAssertEqual(merged.items.map(\.id), ["new"])
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
        XCTAssertNil(StoreCatalog.delete(id: "edeka", stores: Store.seeds, currentId: "edeka"))
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
        XCTAssertEqual(state.grouped().map(\.id), ["obst", "brot", "kuehlung"])

        state.currentStoreId = marktB.id
        XCTAssertEqual(state.grouped().map(\.id), ["kuehlung", "brot", "obst"])
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
        XCTAssertEqual(state.grouped().map(\.id), ["obst", "drogerie"])
        state.currentStoreId = dmKopie.id
        XCTAssertEqual(state.grouped().map(\.id), ["drogerie", "obst"])
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
        XCTAssertEqual(rows.map(\.id), ["h:vor", "v", "h:obst", "a", "b", "h:brot", "br", "h:nach", "n"])
    }

    func testDropSlotBeforeItemIsThatDept() {
        let remaining: [ItemEditing.Row] = [
            .header("obst"),
            .item(Item(id: "a", name: "A", dept: "obst", done: false, added: 1, ord: 1)),
            .header("brot"),
            .item(Item(id: "br", name: "Brot", dept: "brot", done: false, added: 2, ord: 1))
        ]
        let slot = ItemEditing.dropSlot(remaining: remaining, destination: 3)
        XCTAssertEqual(slot?.dept, "brot")
        XCTAssertEqual(slot?.beforeId, "br")
    }

    func testDropSlotBeforeHeaderAppendsToPrevious() {
        let remaining: [ItemEditing.Row] = [
            .header("obst"),
            .item(Item(id: "a", name: "A", dept: "obst", done: false, added: 1, ord: 1)),
            .header("brot"),
            .item(Item(id: "br", name: "Brot", dept: "brot", done: false, added: 2, ord: 1))
        ]
        let slot = ItemEditing.dropSlot(remaining: remaining, destination: 2)
        XCTAssertEqual(slot?.dept, "obst")
        XCTAssertNil(slot?.beforeId)
    }

    func testDropSlotAtEndIsLastDept() {
        let remaining: [ItemEditing.Row] = [
            .header("vor"),
            .item(Item(id: "v", name: "Tasche", dept: "vor", done: false, added: 1, ord: 1)),
            .header("nach"),
            .item(Item(id: "n", name: "Pfand", dept: "nach", done: false, added: 2, ord: 1))
        ]
        let slot = ItemEditing.dropSlot(remaining: remaining, destination: 4)
        XCTAssertEqual(slot?.dept, "nach")
        XCTAssertNil(slot?.beforeId)
    }

    func testMoveRowsAcrossDeptUpdatesDeptMappingAndOrder() {
        let items = sampleItems
        let rows = ItemEditing.rows(items: items, store: edeka)
        // Birne (idx 4) vor Brot (idx 6) → nach Entfernen destination 5
        XCTAssertEqual(rows[4].id, "b")
        XCTAssertEqual(rows[6].id, "br")
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
        XCTAssertEqual(rows[1].id, "v")
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
