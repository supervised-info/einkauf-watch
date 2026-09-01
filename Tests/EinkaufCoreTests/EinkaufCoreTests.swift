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
        let obj = try JSONSerialization.jsonObject(with: exported) as! [String: Any]
        XCTAssertEqual(obj["kind"] as? String, "einkauf-backup")
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

    func testUnused() {
        let unused = StoreLayout.unused(in: ["vor", "sonstiges", "nach"])
        XCTAssertTrue(unused.contains("obst"))
        XCTAssertFalse(unused.contains("vor"))
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
