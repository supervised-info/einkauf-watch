import XCTest
@testable import EinkaufCore

final class TodoCodecTests: XCTestCase {
    func testLocalRoundTripPreservesTasksAndNextUid() throws {
        let original = TodoCodec.normalized(
            TodoState(
                tasks: [
                    TodoTask(
                        uid: 3,
                        text: "Steuer",
                        completed: true,
                        prioA: "A",
                        prioB: "1",
                        dueDate: "2026-09-10",
                        completedDate: "2026-09-01",
                        person: "TS",
                        createdAt: "2026-08-01T10:00:00.000Z",
                        updatedAt: "2026-09-01T12:00:00.000Z",
                        changedBy: "TS/NA"
                    )
                ],
                nextUid: 4,
                revision: 2
            )
        )
        let data = try TodoCodec.encodeLocal(original)
        let obj = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(obj["kind"] as? String, "todo-local")
        XCTAssertEqual(obj["v"] as? Int, 1)
        XCTAssertNil(obj["format"])
        XCTAssertNil(obj["stores"])

        let again = try TodoCodec.decodeLocal(data)
        XCTAssertEqual(again.tasks.map(\.uid), [3])
        XCTAssertEqual(again.tasks.map(\.text), ["Steuer"])
        XCTAssertEqual(again.tasks.map(\.completed), [true])
        XCTAssertEqual(again.tasks.map(\.prioA), ["A"])
        XCTAssertEqual(again.tasks.map(\.prioB), ["1"])
        XCTAssertEqual(again.tasks.map(\.dueDate), ["2026-09-10"])
        XCTAssertEqual(again.tasks.map(\.person), ["TS"])
        XCTAssertEqual(again.nextUid, 4)
        XCTAssertEqual(again.revision, 2)
    }

    func testRejectsEinkaufLocalAndBackup() throws {
        let local = try BackupCodec.encodeLocal(.seed)
        XCTAssertThrowsError(try TodoCodec.decodeLocal(local)) { error in
            XCTAssertEqual(error as? TodoCodecError, .notTodoLocal)
        }
        let backup = try BackupCodec.encodeExport(.seed)
        XCTAssertThrowsError(try TodoCodec.decodeLocal(backup)) { error in
            XCTAssertEqual(error as? TodoCodecError, .notTodoLocal)
        }
    }

    func testRejectsInvalidJSON() {
        XCTAssertThrowsError(try TodoCodec.decodeLocal(Data("nope".utf8))) { error in
            XCTAssertEqual(error as? TodoCodecError, .invalidJSON)
        }
    }

    func testNormalizeAssignsMissingUidsFromNextUid() {
        let raw = TodoState(
            tasks: [
                TodoTask(uid: 0, text: "Eins"),
                TodoTask(uid: 7, text: "Sieben"),
                TodoTask(uid: 0, text: "Zwei"),
                TodoTask(uid: 7, text: "Duplikat")
            ],
            nextUid: 3
        )
        let normalized = TodoCodec.normalized(raw)
        XCTAssertEqual(normalized.tasks.map(\.text), ["Eins", "Sieben", "Zwei", "Duplikat"])
        // 7 bleibt, nextUid = max(3, 8) = 8; Lücken und Duplikate bekommen 8, 9, 10.
        XCTAssertEqual(normalized.tasks.map(\.uid), [8, 7, 9, 10] as [Int64])
        XCTAssertEqual(normalized.nextUid, 11)
    }

    func testNormalizeMissingUidJSON() throws {
        let json = """
        {"kind":"todo-local","v":1,"state":{"tasks":[{"text":"Milch","completed":false},{"text":"Butter","uid":2}],"nextUid":1}}
        """
        let state = try TodoCodec.decodeLocal(Data(json.utf8))
        XCTAssertEqual(state.tasks.map(\.text), ["Milch", "Butter"])
        XCTAssertEqual(state.tasks[1].uid, 2)
        XCTAssertEqual(state.tasks[0].uid, 3)
        XCTAssertEqual(state.nextUid, 4)
    }

    func testSanitizePrioAndDates() {
        let raw = TodoState(
            tasks: [
                TodoTask(uid: 1, text: "X", prioA: "ab", prioB: "0", dueDate: "10.09.2026", completedDate: "2026-13-99")
            ],
            nextUid: 2
        )
        let n = TodoCodec.normalized(raw)
        XCTAssertEqual(n.tasks[0].prioA, "")
        XCTAssertEqual(n.tasks[0].prioB, "")
        XCTAssertEqual(n.tasks[0].dueDate, "")
        XCTAssertEqual(n.tasks[0].completedDate, "")
    }
}

final class TodoPersistenceTests: XCTestCase {
    func testFilesSitTogetherButStayDistinct() {
        let einkauf = Persistence.fileURL
        let todo = TodoPersistence.fileURL
        XCTAssertEqual(einkauf.lastPathComponent, "einkauf-local.json")
        XCTAssertEqual(todo.lastPathComponent, "todo-local.json")
        XCTAssertEqual(einkauf.deletingLastPathComponent().path, todo.deletingLastPathComponent().path)
        XCTAssertNotEqual(einkauf.path, todo.path)
    }

    func testSaveDoesNotWriteEinkaufLocal() throws {
        let einkauf = Persistence.fileURL
        let todo = TodoPersistence.fileURL
        let previousEinkauf = try? Data(contentsOf: einkauf)
        let previousTodo = try? Data(contentsOf: todo)
        let marker = Data(#"{"kind":"einkauf-local","probe":"todo-must-not-clobber"}"#.utf8)
        try marker.write(to: einkauf, options: .atomic)
        defer {
            if let previousEinkauf {
                try? previousEinkauf.write(to: einkauf, options: .atomic)
            } else {
                try? FileManager.default.removeItem(at: einkauf)
            }
            if let previousTodo {
                try? previousTodo.write(to: todo, options: .atomic)
            } else {
                try? FileManager.default.removeItem(at: todo)
            }
        }

        TodoPersistence.save(
            TodoState(tasks: [TodoTask(uid: 1, text: "Anruf", changedBy: "TS/NA")], nextUid: 2, revision: 1)
        )

        XCTAssertEqual(try Data(contentsOf: einkauf), marker)
        let loaded = try XCTUnwrap(TodoPersistence.load())
        XCTAssertEqual(loaded.tasks.map(\.text), ["Anruf"])
        XCTAssertEqual(loaded.nextUid, 2)
        let raw = try Data(contentsOf: todo)
        let obj = try JSONSerialization.jsonObject(with: raw) as! [String: Any]
        XCTAssertEqual(obj["kind"] as? String, "todo-local")
        XCTAssertFalse(String(data: raw, encoding: .utf8)!.contains("einkauf-backup"))
        XCTAssertFalse(String(data: raw, encoding: .utf8)!.contains("einkauf-local"))
    }

    func testMissingFileLoadsNil() {
        let todo = TodoPersistence.fileURL
        let previous = try? Data(contentsOf: todo)
        try? FileManager.default.removeItem(at: todo)
        defer {
            if let previous {
                try? previous.write(to: todo, options: .atomic)
            }
        }
        XCTAssertNil(TodoPersistence.load())
    }
}

@MainActor
final class TodoStoreTests: XCTestCase {
    func testAddToggleDeleteAndEmptyText() throws {
        let todo = TodoPersistence.fileURL
        let previous = try? Data(contentsOf: todo)
        try? FileManager.default.removeItem(at: todo)
        defer {
            if let previous {
                try? previous.write(to: todo, options: .atomic)
            } else {
                try? FileManager.default.removeItem(at: todo)
            }
        }

        let store = TodoStore(state: .empty, enableSync: false)
        XCTAssertNil(store.add("  "))
        XCTAssertTrue(store.state.tasks.isEmpty)

        let uid = try XCTUnwrap(store.add("  Milch kaufen  ", person: "NA", prioA: "B", prioB: "2"))
        XCTAssertEqual(store.state.tasks.count, 1)
        XCTAssertEqual(store.state.tasks[0].text, "Milch kaufen")
        XCTAssertEqual(store.state.tasks[0].uid, uid)
        XCTAssertEqual(store.state.tasks[0].changedBy, "TS/NA")
        XCTAssertEqual(store.state.tasks[0].prioA, "B")
        XCTAssertFalse(store.state.tasks[0].completed)
        XCTAssertEqual(store.state.nextUid, uid + 1)

        store.toggle(uid)
        XCTAssertTrue(store.state.tasks[0].completed)
        XCTAssertFalse(store.state.tasks[0].completedDate.isEmpty)

        store.update(uid, text: "Milch holen")
        XCTAssertEqual(store.state.tasks[0].text, "Milch holen")

        let loaded = try XCTUnwrap(TodoPersistence.load())
        XCTAssertEqual(loaded.tasks.map(\.text), ["Milch holen"])
        XCTAssertEqual(loaded.tasks.map(\.completed), [true])

        store.delete(uid)
        XCTAssertTrue(store.state.tasks.isEmpty)
    }
}
