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

        store.update(uid, text: "Milch holen", person: "TS", prioA: "C", prioB: "3", dueDate: "2026-09-20")
        XCTAssertEqual(store.state.tasks[0].text, "Milch holen")
        XCTAssertEqual(store.state.tasks[0].person, "TS")
        XCTAssertEqual(store.state.tasks[0].prioA, "C")
        XCTAssertEqual(store.state.tasks[0].prioB, "3")
        XCTAssertEqual(store.state.tasks[0].dueDate, "2026-09-20")

        let loaded = try XCTUnwrap(TodoPersistence.load())
        XCTAssertEqual(loaded.tasks.map(\.text), ["Milch holen"])
        XCTAssertEqual(loaded.tasks.map(\.completed), [true])

        store.delete(uid)
        XCTAssertTrue(store.state.tasks.isEmpty)
    }

    func testClearCompletedRemovesOnlyDone() throws {
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
        XCTAssertNotNil(store.add("Offen"))
        let done = try XCTUnwrap(store.add("Fertig"))
        store.toggle(done)
        XCTAssertEqual(store.state.tasks.map(\.completed), [false, true])

        store.clearCompleted()
        XCTAssertEqual(store.state.tasks.map(\.text), ["Offen"])
        XCTAssertFalse(store.state.tasks[0].completed)

        store.clearCompleted()
        XCTAssertEqual(store.state.tasks.map(\.text), ["Offen"])
    }
}

final class TodoOrderingTests: XCTestCase {
    func testPrioSortKeyMissingAGoesLast() {
        let missing = TodoTask(uid: 1, text: "x")
        let aDefaultB = TodoTask(uid: 2, text: "x", prioA: "A")
        let a1 = TodoTask(uid: 3, text: "x", prioA: "A", prioB: "1")
        let z = TodoTask(uid: 4, text: "x", prioA: "Z", prioB: "9")
        XCTAssertEqual(TodoOrdering.prioSortKey(a1), "A1")
        XCTAssertEqual(TodoOrdering.prioSortKey(aDefaultB), "A9")
        XCTAssertEqual(TodoOrdering.prioSortKey(z), "Z9")
        XCTAssertEqual(TodoOrdering.prioSortKey(missing), "\u{FFFF}")
        XCTAssertTrue(TodoOrdering.prioSortKey(a1) < TodoOrdering.prioSortKey(aDefaultB))
        XCTAssertTrue(TodoOrdering.prioSortKey(z) < TodoOrdering.prioSortKey(missing))
    }

    func testIsOverdueIgnoresTodayFutureEmptyAnd9999() {
        XCTAssertTrue(TodoOrdering.isOverdue("2026-09-03", today: "2026-09-04"))
        XCTAssertFalse(TodoOrdering.isOverdue("2026-09-04", today: "2026-09-04"))
        XCTAssertFalse(TodoOrdering.isOverdue("2026-09-05", today: "2026-09-04"))
        XCTAssertFalse(TodoOrdering.isOverdue("", today: "2026-09-04"))
        XCTAssertFalse(TodoOrdering.isOverdue("10.09.2026", today: "2026-09-04"))
        XCTAssertFalse(TodoOrdering.isOverdue("9999-12-31", today: "2026-09-04"))
        XCTAssertFalse(TodoOrdering.isOverdue("9999-01-01", today: "2026-09-04"))
        XCTAssertFalse(TodoOrdering.isOverdue(TodoTask(uid: 1, text: "x", dueDate: "9999-06-01"), today: "2026-09-04"))
        XCTAssertTrue(TodoOrdering.isOverdue(TodoTask(uid: 1, text: "x", dueDate: "2020-01-01"), today: "2026-09-04"))
    }

    func testSortPersonThenOpenFirstThenPrio() {
        let tasks = [
            TodoTask(uid: 1, text: "done TS", completed: true, prioA: "A", person: "TS"),
            TodoTask(uid: 2, text: "open B", prioA: "B", person: "NA"),
            TodoTask(uid: 3, text: "open A2", prioA: "A", prioB: "2", person: "NA"),
            TodoTask(uid: 4, text: "open A1", prioA: "A", prioB: "1", person: "NA"),
            TodoTask(uid: 5, text: "no person", prioA: "A"),
            TodoTask(uid: 6, text: "open TS", person: "TS"),
        ]
        XCTAssertEqual(TodoOrdering.sorted(tasks).map(\.uid), [5, 4, 3, 2, 6, 1] as [Int64])
    }
}

final class TodoListGroupingTests: XCTestCase {
    func testPDFGroupsByPersonOpenFirstAndPrio() {
        let tasks = [
            TodoTask(uid: 1, text: "done TS", completed: true, prioA: "A", person: "TS"),
            TodoTask(uid: 2, text: "open B", prioA: "B", person: "NA"),
            TodoTask(uid: 3, text: "open A2", prioA: "A", prioB: "2", person: "NA"),
            TodoTask(uid: 4, text: "open A1", prioA: "A", prioB: "1", person: "NA"),
            TodoTask(uid: 5, text: "no person", prioA: "A"),
            TodoTask(uid: 6, text: "open TS", person: "TS"),
        ]
        let groups = TodoListGrouping.groups(tasks, showCompleted: true)
        XCTAssertEqual(groups.map(\.title), ["Keine Person", "NA", "TS"])
        XCTAssertEqual(groups[0].tasks.map(\.uid), [5] as [Int64])
        XCTAssertEqual(groups[1].tasks.map(\.uid), [4, 3, 2] as [Int64])
        XCTAssertEqual(groups[2].tasks.map(\.uid), [6, 1] as [Int64])
        XCTAssertEqual(TodoListGrouping.progressLabel(groups: groups), "5/1/6")
    }

    func testPDFHidesCompletedWhenEyeClosed() {
        let tasks = [
            TodoTask(uid: 1, text: "open", person: "NA"),
            TodoTask(uid: 2, text: "done", completed: true, person: "NA"),
            TodoTask(uid: 3, text: "done other", completed: true, person: "TS"),
        ]
        let hidden = TodoListGrouping.groups(tasks, showCompleted: false)
        XCTAssertEqual(hidden.map(\.title), ["NA"])
        XCTAssertEqual(hidden[0].tasks.map(\.uid), [1] as [Int64])
        XCTAssertEqual(TodoListGrouping.progressLabel(groups: hidden), "1/0/1")

        let shown = TodoListGrouping.groups(tasks, showCompleted: true)
        XCTAssertEqual(shown.map(\.title), ["NA", "TS"])
        XCTAssertEqual(TodoListGrouping.progressLabel(groups: shown), "1/2/3")
    }

    func testPDFEmptyWhenOnlyCompletedHidden() {
        let tasks = [TodoTask(uid: 1, text: "done", completed: true, person: "TS")]
        XCTAssertTrue(TodoListGrouping.groups(tasks, showCompleted: false).isEmpty)
        XCTAssertEqual(
            TodoListGrouping.progressLabel(groups: TodoListGrouping.groups(tasks, showCompleted: false)),
            "0/0/0"
        )
    }

    func testBlankPersonGroupsAsKeinePerson() {
        let tasks = [
            TodoTask(uid: 1, text: "a", person: "  "),
            TodoTask(uid: 2, text: "b", person: ""),
        ]
        let groups = TodoListGrouping.groups(tasks, showCompleted: true)
        XCTAssertEqual(groups.map(\.title), ["Keine Person"])
        XCTAssertEqual(groups[0].tasks.map(\.uid), [1, 2] as [Int64])
    }

    func testMetaLinePrioAndDue() {
        XCTAssertEqual(TodoListGrouping.metaLine(TodoTask(uid: 1, text: "x")), "")
        XCTAssertEqual(
            TodoListGrouping.metaLine(TodoTask(uid: 1, text: "x", prioA: "B", prioB: "2")),
            "B2"
        )
        XCTAssertEqual(
            TodoListGrouping.metaLine(TodoTask(uid: 1, text: "x", dueDate: "2026-09-04")),
            "04.09.2026"
        )
        XCTAssertEqual(
            TodoListGrouping.metaLine(TodoTask(uid: 1, text: "x", prioA: "A", dueDate: "2026-09-10")),
            "A · 10.09.2026"
        )
    }
}

final class TodoBackupCodecTests: XCTestCase {
    func testV3JsonFixtureRoundTripAndIgnoresExtraFields() throws {
        let data = try loadTodoFixture("todo-v3-json.json")
        let state = try TodoCodec.decodeBackup(data)
        XCTAssertEqual(state.tasks.map(\.uid), [1, 2] as [Int64])
        XCTAssertEqual(state.tasks.map(\.text), ["Steuererklärung", "Milch holen"])
        XCTAssertEqual(state.tasks.map(\.completed), [false, true])
        XCTAssertEqual(state.tasks[0].prioA, "A")
        XCTAssertEqual(state.tasks[0].person, "TS")
        XCTAssertEqual(state.tasks[1].completedDate, "2026-09-01")
        XCTAssertEqual(state.nextUid, 3)

        let exported = try TodoCodec.encodeBackup(state)
        let obj = try JSONSerialization.jsonObject(with: exported) as! [String: Any]
        XCTAssertEqual(obj["format"] as? String, "todo-v3-json")
        XCTAssertNotNil(obj["exportedAt"] as? String)
        XCTAssertEqual(obj["nextUid"] as? Int, 3)
        XCTAssertNil(obj["kind"])
        XCTAssertNil(obj["stores"])
        XCTAssertNil(obj["revision"])
        XCTAssertFalse((obj["kind"] as? String) == "einkauf-backup")

        let again = try TodoCodec.decodeBackup(exported)
        XCTAssertEqual(again.tasks.map(\.uid), state.tasks.map(\.uid))
        XCTAssertEqual(again.tasks.map(\.text), state.tasks.map(\.text))
        XCTAssertEqual(again.tasks.map(\.completed), state.tasks.map(\.completed))
        XCTAssertEqual(again.nextUid, state.nextUid)
    }

    func testBareTasksArrayAndLooseObject() throws {
        let arrayJSON = """
        [{"uid":4,"text":"Anrufen","completed":false,"person":"NA"}]
        """
        let fromArray = try TodoCodec.decodeBackup(Data(arrayJSON.utf8))
        XCTAssertEqual(fromArray.tasks.map(\.text), ["Anrufen"])
        XCTAssertEqual(fromArray.tasks[0].uid, 4)

        let loose = """
        {"nextUid":9,"tasks":[{"text":"Ohne Format","uid":8}],"future":{"x":1}}
        """
        let fromLoose = try TodoCodec.decodeBackup(Data(loose.utf8))
        XCTAssertEqual(fromLoose.tasks.map(\.text), ["Ohne Format"])
        XCTAssertEqual(fromLoose.tasks[0].uid, 8)
        XCTAssertEqual(fromLoose.nextUid, 9)
    }

    func testRejectsEinkaufBackupAndLocal() throws {
        let backup = try BackupCodec.encodeExport(.seed)
        XCTAssertThrowsError(try TodoCodec.decodeBackup(backup)) { error in
            XCTAssertEqual(error as? TodoCodecError, .einkaufFile)
        }
        let local = try BackupCodec.encodeLocal(.seed)
        XCTAssertThrowsError(try TodoCodec.decodeBackup(local)) { error in
            XCTAssertEqual(error as? TodoCodecError, .einkaufFile)
        }
    }

    func testEinkaufLooksLikeBackupRejectsTodoJSON() throws {
        let data = try loadTodoFixture("todo-v3-json.json")
        let obj = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertFalse(BackupCodec.looksLikeBackup(obj))
        XCTAssertThrowsError(try BackupCodec.decode(data)) { error in
            XCTAssertEqual(error as? BackupError, .notABackup)
        }
    }

    func testIncomingJSONRoutesTodoAndEinkaufApart() throws {
        let todo = try loadTodoFixture("todo-v3-json.json")
        XCTAssertEqual(IncomingJSON.classify(todo), .todoBackup)
        XCTAssertTrue(IncomingJSON.looksLikeTodo(try JSONSerialization.jsonObject(with: todo)))

        let einkauf = try loadTodoFixture("einkauf-backup.json")
        XCTAssertEqual(IncomingJSON.classify(einkauf), .einkaufBackup)
        XCTAssertFalse(IncomingJSON.looksLikeTodo(try JSONSerialization.jsonObject(with: einkauf)))

        XCTAssertEqual(IncomingJSON.classify(Data("[{".utf8)), .invalidJSON)
        XCTAssertEqual(IncomingJSON.classify(Data(#"{"foo":1}"#.utf8)), .unknown)
        XCTAssertEqual(IncomingJSON.classify(Data(#"[{"text":"X"}]"#.utf8)), .todoBackup)
    }

    func testImportChoiceMessage() {
        XCTAssertEqual(
            TodoImportPrompt.message(currentCount: 2, incomingCount: 3),
            "Aktuelle Liste (2 Aufgaben) und 3 importierte Aufgaben – ersetzen oder anhängen?"
        )
        XCTAssertEqual(
            TodoImportPrompt.message(currentCount: 1, incomingCount: 1),
            "Aktuelle Liste (1 Aufgabe) und 1 importierte Aufgabe – ersetzen oder anhängen?"
        )
    }
}

@MainActor
final class TodoStoreBackupTests: XCTestCase {
    func testExportImportReplaceAndAppendRenumbersCollidingUids() throws {
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
        XCTAssertNotNil(store.add("Lokal", person: "TS"))
        XCTAssertEqual(store.state.tasks[0].uid, 1)

        let incoming = try loadTodoFixture("todo-v3-json.json")
        try store.importBackup(incoming, append: true)
        XCTAssertEqual(store.state.tasks.map(\.text), ["Lokal", "Steuererklärung", "Milch holen"])
        XCTAssertEqual(store.state.tasks.map(\.uid), [1, 3, 2] as [Int64])
        XCTAssertEqual(store.state.nextUid, 4)

        try store.importBackup(incoming, append: false)
        XCTAssertEqual(store.state.tasks.map(\.text), ["Steuererklärung", "Milch holen"])
        XCTAssertEqual(store.state.tasks.map(\.uid), [1, 2] as [Int64])
        XCTAssertEqual(store.state.nextUid, 3)

        let exported = try store.exportBackup()
        let obj = try JSONSerialization.jsonObject(with: exported) as! [String: Any]
        XCTAssertEqual(obj["format"] as? String, "todo-v3-json")
        XCTAssertNil(obj["kind"])

        let empty = TodoStore(state: .empty, enableSync: false)
        try empty.importBackup(exported, append: false)
        XCTAssertEqual(empty.state.tasks.map(\.text), ["Steuererklärung", "Milch holen"])

        XCTAssertThrowsError(try store.importBackup(try BackupCodec.encodeExport(.seed), append: false)) { error in
            XCTAssertEqual(error as? TodoCodecError, .einkaufFile)
        }
        XCTAssertEqual(store.state.tasks.map(\.text), ["Steuererklärung", "Milch holen"])
    }
}

private func loadTodoFixture(_ name: String) throws -> Data {
    let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures")
        .appendingPathComponent(name)
    return try Data(contentsOf: url)
}
