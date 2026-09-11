import XCTest
@testable import EinkaufCore

final class DepartmentCatalogTests: XCTestCase {
    func testResolvedKeepsCustomIdsAndMapsUnknownToSonstiges() {
        let customs = [CustomDepartment(id: "d-bio", title: "Bio")]
        XCTAssertEqual(DepartmentCatalog.resolved("d-bio", customs: customs), "d-bio")
        XCTAssertEqual(DepartmentCatalog.resolved("obst", customs: customs), "obst")
        XCTAssertEqual(DepartmentCatalog.resolved("nope", customs: customs), "sonstiges")
        XCTAssertEqual(DepartmentCatalog.resolved("", customs: customs), "sonstiges")
        XCTAssertEqual(Department.resolved("d-bio"), "sonstiges")
        XCTAssertEqual(Department.resolved("obst"), "obst")
    }

    func testTitleUsesCustomThenBuiltin() {
        let customs = [CustomDepartment(id: "d-bio", title: "Bio-Ecke")]
        XCTAssertEqual(DepartmentCatalog.title(for: "d-bio", customs: customs), "Bio-Ecke")
        XCTAssertEqual(DepartmentCatalog.title(for: "obst", customs: customs), "Obst & Gemüse")
        XCTAssertEqual(DepartmentCatalog.title(for: "d-bio"), "d-bio")
    }

    func testCreateRejectsEmptyAndAvoidsBuiltinIds() {
        XCTAssertNil(DepartmentCatalog.create(title: "   ", existing: []))
        let created = DepartmentCatalog.create(title: "  Bio  ", existing: [], id: "obst")
        XCTAssertEqual(created?.title, "Bio")
        XCTAssertNotEqual(created?.id, "obst")
        XCTAssertFalse(Department.isKnown(created?.id ?? "obst"))
        XCTAssertTrue(created?.id.hasPrefix("d") == true)
    }

    func testRenameChangesOnlyTitle() {
        let customs = [CustomDepartment(id: "d-bio", title: "Bio")]
        let next = DepartmentCatalog.rename(id: "d-bio", title: "  Bio-Ecke  ", in: customs)
        XCTAssertEqual(next, [CustomDepartment(id: "d-bio", title: "Bio-Ecke")])
        XCTAssertNil(DepartmentCatalog.rename(id: "d-bio", title: "  ", in: customs))
        XCTAssertNil(DepartmentCatalog.rename(id: "missing", title: "X", in: customs))
    }

    func testDeleteRemapsItemsStaplesSavedListsMappingsAndLayouts() {
        let customs = [CustomDepartment(id: "d-bio", title: "Bio")]
        let items = [
            Item(id: "i1", name: "Tofu", dept: "d-bio", done: false, added: 1, ord: 1),
            Item(id: "i2", name: "Milch", dept: "kuehlung", done: false, added: 2, ord: 2)
        ]
        let staples = [Staple(name: "Tofu", dept: "d-bio"), Staple(name: "Butter", dept: "kuehlung")]
        let saved = [SavedList(id: "l1", name: "Asia", items: [Staple(name: "Tofu", dept: "d-bio")])]
        let mappings = ["tofu": "d-bio", "milch": "kuehlung"]
        let stores = [
            Store(id: "edeka", name: "Edeka", layout: ["vor", "obst", "d-bio", "sonstiges", "nach"], builtin: true)
        ]
        let remapped = DepartmentCatalog.remappingDeletion(
            "d-bio",
            items: items,
            staples: staples,
            savedLists: saved,
            mappings: mappings,
            stores: stores,
            remainingCustoms: []
        )
        XCTAssertEqual(remapped.items.map(\.dept), ["sonstiges", "kuehlung"])
        XCTAssertEqual(remapped.staples.map(\.dept), ["sonstiges", "kuehlung"])
        XCTAssertEqual(remapped.savedLists[0].items.map(\.dept), ["sonstiges"])
        XCTAssertEqual(remapped.mappings["tofu"], "sonstiges")
        XCTAssertEqual(remapped.mappings["milch"], "kuehlung")
        XCTAssertFalse(remapped.stores[0].layout.contains("d-bio"))
        XCTAssertEqual(remapped.stores[0].layout.first, "vor")
        XCTAssertEqual(remapped.stores[0].layout.last, "nach")
    }
}

final class CustomDepartmentGroupingTests: XCTestCase {
    func testCustomDeptInLayoutKeepsPositionAndTitle() {
        let customs = [CustomDepartment(id: "d-bio", title: "Bio-Ecke")]
        let store = Store(id: "markt", name: "Markt", layout: ["vor", "obst", "d-bio", "sonstiges", "nach"], builtin: false)
        let items = [
            Item(id: "a", name: "Äpfel", dept: "obst", done: false, added: 1, ord: 1),
            Item(id: "t", name: "Tofu", dept: "d-bio", done: false, added: 2, ord: 2)
        ]
        let groups = ListGrouping.groups(items: items, store: store, customs: customs)
        XCTAssertEqual(groups.map(\.dept), ["obst", "d-bio"])
        XCTAssertEqual(groups.first { $0.dept == "d-bio" }?.title, "Bio-Ecke")
        XCTAssertEqual(items.first { $0.id == "t" }?.dept, "d-bio")
    }

    func testCustomDeptNotInLayoutIsExtraBeforeNach() {
        let customs = [CustomDepartment(id: "d-bio", title: "Bio")]
        let store = Store.seeds.first { $0.id == "edeka" }!
        let items = [
            Item(id: "t", name: "Tofu", dept: "d-bio", done: false, added: 1, ord: 1),
            Item(id: "n", name: "Pfand", dept: "nach", done: false, added: 2, ord: 2)
        ]
        let groups = ListGrouping.groups(items: items, store: store, customs: customs)
        XCTAssertEqual(groups.map(\.dept), ["d-bio", "nach"])
        XCTAssertEqual(groups.first?.title, "Bio")
    }

    func testUnknownDeptWithoutCustomCollapsesToSonstiges() {
        let store = Store.seeds.first { $0.id == "edeka" }!
        let items = [Item(id: "x", name: "X", dept: "ghost", done: false, added: 1, ord: 1)]
        let groups = ListGrouping.groups(items: items, store: store)
        XCTAssertEqual(groups.map(\.dept), ["sonstiges"])
        XCTAssertEqual(items[0].dept, "ghost")
    }

    func testStoreLayoutKeepsCustomIds() {
        let customs = [CustomDepartment(id: "d-bio", title: "Bio")]
        let layout = StoreLayout.sanitized(["vor", "d-bio", "sonstiges", "nach"], customs: customs)
        XCTAssertEqual(layout, ["vor", "d-bio", "sonstiges", "nach"])
        XCTAssertTrue(StoreLayout.unused(in: ["vor", "sonstiges", "nach"], customs: customs).contains("d-bio"))
        let added = StoreLayout.adding("d-bio", to: ["vor", "sonstiges", "nach"], customs: customs)
        XCTAssertEqual(added, ["vor", "sonstiges", "d-bio", "nach"])
        XCTAssertEqual(StoreLayout.sanitized(["vor", "d-bio", "nach"]), ["vor", "nach"])
    }
}

final class CustomDepartmentBackupTests: XCTestCase {
    func testExportRoundTripKeepsCustomsAndOldBackupIsEmpty() throws {
        var original = AppState.seed
        original.customDepartments = [CustomDepartment(id: "d-bio", title: "Bio-Ecke")]
        original.items = [
            Item(id: "i1", name: "Tofu", dept: "d-bio", done: false, added: 1, ord: 1)
        ]
        original.stores[0].layout = ["vor", "obst", "d-bio", "sonstiges", "nach"]
        original.staples = [Staple(name: "Tofu", dept: "d-bio")]
        original.mappings = ["tofu": "d-bio"]

        let exported = try BackupCodec.encodeExport(original)
        let obj = try JSONSerialization.jsonObject(with: exported) as! [String: Any]
        let raw = obj["customDepartments"] as! [[String: Any]]
        XCTAssertEqual(raw[0]["id"] as? String, "d-bio")
        XCTAssertEqual(raw[0]["title"] as? String, "Bio-Ecke")

        let again = try BackupCodec.decode(exported)
        XCTAssertEqual(again.customDepartments, original.customDepartments)
        XCTAssertEqual(again.items[0].dept, "d-bio")
        XCTAssertEqual(again.staples[0].dept, "d-bio")
        XCTAssertEqual(again.mappings["tofu"], "d-bio")
        XCTAssertTrue(again.stores.first { $0.id == "edeka" }?.layout.contains("d-bio") == true)
    }

    func testOldBackupWithoutCustomsFieldIsEmpty() throws {
        let json = """
        {"kind":"einkauf-backup","v":1,"currentStoreId":"edeka","stores":[],"items":[{"id":"a","name":"Milch","dept":"kuehlung","done":false,"added":1,"ord":1}]}
        """
        let state = try BackupCodec.decode(Data(json.utf8))
        XCTAssertTrue(state.customDepartments.isEmpty)
        XCTAssertEqual(state.items[0].dept, "kuehlung")
    }

    func testUnknownDeptWithoutMatchingCustomBecomesSonstiges() throws {
        let json = """
        {"kind":"einkauf-backup","v":1,"currentStoreId":"edeka","stores":[],"items":[{"id":"a","name":"X","dept":"ghost","done":false,"added":1,"ord":1}],"customDepartments":[{"id":"d-bio","title":"Bio"}]}
        """
        let state = try BackupCodec.decode(Data(json.utf8))
        XCTAssertEqual(state.customDepartments.map(\.id), ["d-bio"])
        XCTAssertEqual(state.items[0].dept, "sonstiges")
    }

    func testLocalRoundTripKeepsCustomDeptOnItems() throws {
        var state = AppState.seed
        state.customDepartments = [CustomDepartment(id: "d-bio", title: "Bio")]
        state.items = [Item(id: "i1", name: "Tofu", dept: "d-bio", done: false, added: 1, ord: 1)]
        let data = try BackupCodec.encodeLocal(state)
        let again = try BackupCodec.decodeLocal(data)
        XCTAssertEqual(again.customDepartments, state.customDepartments)
        XCTAssertEqual(again.items[0].dept, "d-bio")
    }

    func testBuiltinIdIsDroppedFromCustoms() throws {
        let json = """
        {"kind":"einkauf-backup","v":1,"currentStoreId":"edeka","stores":[],"items":[],"customDepartments":[{"id":"obst","title":"Mein Obst"},{"id":"d-ok","title":"Ok"}]}
        """
        let state = try BackupCodec.decode(Data(json.utf8))
        XCTAssertEqual(state.customDepartments.map(\.id), ["d-ok"])
    }
}
