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

    func testReopenKeepsOriginalCompletedAndCopiesOpen() throws {
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
        let openUid = try XCTUnwrap(store.add("Offen bleiben"))
        XCTAssertNil(store.reopen(openUid))
        XCTAssertEqual(store.state.tasks.count, 1)

        let uid = try XCTUnwrap(
            store.add("Steuer", person: "TS", prioA: "A", prioB: "1", dueDate: "2026-09-20")
        )
        store.toggle(uid)
        let originalCompletedDate = store.state.tasks[1].completedDate
        XCTAssertTrue(store.state.tasks[1].completed)
        XCTAssertFalse(originalCompletedDate.isEmpty)
        XCTAssertEqual(store.state.nextUid, uid + 1)

        let copyUid = try XCTUnwrap(store.reopen(uid))
        XCTAssertEqual(copyUid, uid + 1)
        XCTAssertEqual(store.state.nextUid, copyUid + 1)
        XCTAssertEqual(store.state.tasks.count, 3)

        let original = try XCTUnwrap(store.state.tasks.first { $0.uid == uid })
        XCTAssertTrue(original.completed)
        XCTAssertEqual(original.completedDate, originalCompletedDate)
        XCTAssertEqual(original.reopenedToUid, copyUid)
        XCTAssertEqual(original.reopenedAt, TodoTime.todayIso())
        XCTAssertEqual(original.text, "Steuer")
        XCTAssertEqual(original.person, "TS")
        XCTAssertEqual(original.prioA, "A")
        XCTAssertEqual(original.prioB, "1")
        XCTAssertEqual(original.dueDate, "2026-09-20")
        XCTAssertNil(original.reopenedFromUid)

        let copy = try XCTUnwrap(store.state.tasks.first { $0.uid == copyUid })
        XCTAssertFalse(copy.completed)
        XCTAssertEqual(copy.completedDate, "")
        XCTAssertEqual(copy.reopenedFromUid, uid)
        XCTAssertNil(copy.reopenedToUid)
        XCTAssertEqual(copy.reopenedAt, original.reopenedAt)
        XCTAssertEqual(copy.text, "Steuer")
        XCTAssertEqual(copy.person, "TS")
        XCTAssertEqual(copy.prioA, "A")
        XCTAssertEqual(copy.prioB, "1")
        XCTAssertEqual(copy.dueDate, "2026-09-20")
        XCTAssertEqual(copy.changedBy, "TS/NA")

        XCTAssertNil(store.reopen(uid))
        XCTAssertEqual(store.state.tasks.count, 3)

        let loaded = try XCTUnwrap(TodoPersistence.load())
        XCTAssertEqual(loaded.tasks.count, 3)
        XCTAssertEqual(loaded.nextUid, copyUid + 1)
        let loadedOriginal = try XCTUnwrap(loaded.tasks.first { $0.uid == uid })
        let loadedCopy = try XCTUnwrap(loaded.tasks.first { $0.uid == copyUid })
        XCTAssertTrue(loadedOriginal.completed)
        XCTAssertEqual(loadedOriginal.reopenedToUid, copyUid)
        XCTAssertFalse(loadedCopy.completed)
        XCTAssertEqual(loadedCopy.reopenedFromUid, uid)
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
        XCTAssertEqual(TodoOrdering.sorted(tasks, by: .person).map(\.uid), [5, 4, 3, 2, 6, 1] as [Int64])
    }

    func testSortKeysPrioTextDueCompletedAndCompletedDate() {
        let tasks = [
            TodoTask(uid: 1, text: "zeta", completed: true, prioA: "B", dueDate: "2026-09-10", completedDate: "2026-09-02", person: "TS"),
            TodoTask(uid: 2, text: "alpha", prioA: "A", prioB: "2", dueDate: "2026-09-20", person: "NA"),
            TodoTask(uid: 3, text: "beta", prioA: "A", prioB: "1", dueDate: "2026-09-05", person: "ZZ"),
            TodoTask(uid: 4, text: "gamma", completed: true, completedDate: "2026-09-01"),
            TodoTask(uid: 5, text: "delta", prioA: "C", dueDate: ""),
        ]
        XCTAssertEqual(TodoOrdering.sorted(tasks, by: .prioA).map(\.uid), [3, 2, 1, 5, 4] as [Int64])
        XCTAssertEqual(TodoOrdering.sorted(tasks, by: .text).map(\.uid), [2, 3, 5, 4, 1] as [Int64])
        XCTAssertEqual(TodoOrdering.sorted(tasks, by: .dueDate).map(\.uid), [3, 1, 2, 5, 4] as [Int64])
        XCTAssertEqual(TodoOrdering.sorted(tasks, by: .completed).map(\.uid), [3, 2, 5, 1, 4] as [Int64])
        XCTAssertEqual(TodoOrdering.sorted(tasks, by: .completedDate).map(\.uid), [4, 1, 3, 2, 5] as [Int64])
        XCTAssertEqual(TodoSortKey.allCases.map(\.rawValue), ["person", "prioA", "text", "dueDate", "completed", "completedDate"])
        XCTAssertEqual(TodoSortKey.iphoneDefaultsKey, "todo.iphone.sortKey")
    }

    func testMatchesFilterPersonOrTextCaseInsensitive() {
        let task = TodoTask(uid: 1, text: "Milch holen", person: "TS")
        XCTAssertTrue(TodoOrdering.matches(task, query: "milch"))
        XCTAssertTrue(TodoOrdering.matches(task, query: "TS"))
        XCTAssertTrue(TodoOrdering.matches(task, query: "  holen  "))
        XCTAssertTrue(TodoOrdering.matches(task, query: ""))
        XCTAssertTrue(TodoOrdering.matches(task, query: "   "))
        XCTAssertFalse(TodoOrdering.matches(task, query: "NA"))
        XCTAssertFalse(TodoOrdering.matches(task, query: "Steuer"))
        XCTAssertTrue(TodoOrdering.canReopen(TodoTask(uid: 2, text: "x", completed: true)))
        XCTAssertFalse(TodoOrdering.canReopen(TodoTask(uid: 3, text: "x")))
        XCTAssertFalse(TodoOrdering.canReopen(TodoTask(uid: 4, text: "x", completed: true, reopenedToUid: 9)))
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

final class WatchSyncEnvelopeTests: XCTestCase {
    func testMergingTodoIntoLegacyEinkaufContextKeepsEinkaufBlob() {
        let einkaufBlob = Data("einkauf-blob".utf8)
        let todoBlob = Data("todo-blob".utf8)
        let legacy: [String: Any] = [
            "kind": "einkauf-sync",
            "v": 1,
            "blob": einkaufBlob
        ]
        let todoPayload: [String: Any] = [
            "kind": "todo-sync",
            "v": 1,
            "blob": todoBlob
        ]
        let merged = WatchSyncEnvelope.merging(legacy, domain: WatchSyncEnvelope.todoKey, payload: todoPayload)
        XCTAssertNil(merged["kind"] as? String)
        let einkauf = WatchSyncEnvelope.dictionary(merged[WatchSyncEnvelope.einkaufKey])
        XCTAssertEqual(einkauf?["kind"] as? String, "einkauf-sync")
        XCTAssertEqual(einkauf?["blob"] as? Data, einkaufBlob)
        let todo = WatchSyncEnvelope.dictionary(merged[WatchSyncEnvelope.todoKey])
        XCTAssertEqual(todo?["kind"] as? String, "todo-sync")
        XCTAssertEqual(todo?["blob"] as? Data, todoBlob)
    }

    func testMergingEinkaufDoesNotWipeTodo() {
        let current: [String: Any] = [
            WatchSyncEnvelope.todoKey: [
                "kind": "todo-sync",
                "v": 1,
                "blob": Data("todo".utf8)
            ]
        ]
        let einkaufPayload: [String: Any] = [
            "kind": "einkauf-sync",
            "v": 1,
            "blob": Data("einkauf".utf8)
        ]
        let merged = WatchSyncEnvelope.merging(current, domain: WatchSyncEnvelope.einkaufKey, payload: einkaufPayload)
        XCTAssertEqual(WatchSyncEnvelope.dictionary(merged[WatchSyncEnvelope.todoKey])?["kind"] as? String, "todo-sync")
        XCTAssertEqual(WatchSyncEnvelope.dictionary(merged[WatchSyncEnvelope.einkaufKey])?["kind"] as? String, "einkauf-sync")
    }

    func testSplitIncomingLegacyEinkaufAndNestedBoth() {
        let legacy: [String: Any] = ["kind": "einkauf-sync", "v": 1, "blob": Data("e".utf8)]
        let splitLegacy = WatchSyncEnvelope.splitIncoming(legacy)
        XCTAssertEqual(splitLegacy.einkauf?["kind"] as? String, "einkauf-sync")
        XCTAssertNil(splitLegacy.todo)

        let nested: [String: Any] = [
            "einkauf": ["kind": "einkauf-sync", "blob": Data("e".utf8)],
            "todo": ["kind": "todo-sync", "blob": Data("t".utf8)]
        ]
        let splitNested = WatchSyncEnvelope.splitIncoming(nested)
        XCTAssertEqual(splitNested.einkauf?["kind"] as? String, "einkauf-sync")
        XCTAssertEqual(splitNested.todo?["kind"] as? String, "todo-sync")

        let todoMsg: [String: Any] = ["kind": "todo-toggle", "uid": 7, "completed": true]
        let splitToggle = WatchSyncEnvelope.splitIncoming(todoMsg)
        XCTAssertNil(splitToggle.einkauf)
        XCTAssertEqual(splitToggle.todo?["kind"] as? String, "todo-toggle")
    }

    func testExtractTodoBlobAndUidFromNSNumber() throws {
        let state = TodoCodec.normalized(
            TodoState(tasks: [TodoTask(uid: 4, text: "Anruf")], nextUid: 5, revision: 1)
        )
        let blob = try TodoCodec.encodeLocal(state)
        let payload: [String: Any] = ["kind": "todo-sync", "v": 1, "blob": blob]
        let extracted = try XCTUnwrap(WatchSyncEnvelope.extractBlob(payload))
        let decoded = try TodoCodec.decodeLocal(extracted)
        XCTAssertEqual(decoded.tasks.map(\.text), ["Anruf"])
        XCTAssertEqual(decoded.tasks.map(\.uid), [4] as [Int64])

        XCTAssertEqual(WatchSyncEnvelope.uid(from: ["uid": NSNumber(value: Int64(9))]), 9)
        XCTAssertEqual(WatchSyncEnvelope.uid(from: ["uid": Int64(3)]), 3)
        XCTAssertNil(WatchSyncEnvelope.uid(from: ["uid": 0]))
        XCTAssertNil(WatchSyncEnvelope.extractBlob(["kind": "todo-sync"]))
    }

    func testLegacyTopLevelEinkaufSyncIsEinkaufOnly() {
        XCTAssertTrue(WatchSyncEnvelope.isEinkaufKind("einkauf-sync"))
        XCTAssertTrue(WatchSyncEnvelope.isEinkaufKind("einkauf-toggle"))
        XCTAssertTrue(WatchSyncEnvelope.isEinkaufKind("einkauf-pull"))
        XCTAssertFalse(WatchSyncEnvelope.isEinkaufKind("todo-sync"))
        XCTAssertTrue(WatchSyncEnvelope.isTodoKind("todo-sync"))
        XCTAssertTrue(WatchSyncEnvelope.isTodoKind("todo-toggle"))
        XCTAssertTrue(WatchSyncEnvelope.isTodoKind("todo-pull"))
        XCTAssertFalse(WatchSyncEnvelope.isTodoKind("einkauf-sync"))
    }
}

final class TodoMergeTests: XCTestCase {
    func testHigherRevisionWinsStructureCompletedFollowsUpdatedAt() {
        let older = TodoTask(
            uid: 1,
            text: " milch",
            completed: false,
            updatedAt: "2026-09-01T10:00:00.000Z"
        )
        let newerDone = TodoTask(
            uid: 1,
            text: "milch",
            completed: true,
            completedDate: "2026-09-04",
            updatedAt: "2026-09-04T12:00:00.000Z"
        )
        let local = TodoState(tasks: [older, TodoTask(uid: 2, text: "nur lokal")], nextUid: 3, revision: 5)
        let remote = TodoState(tasks: [newerDone], nextUid: 2, revision: 4)
        let merged = TodoMerge.merge(local: local, remote: remote)
        XCTAssertEqual(merged.revision, 5)
        XCTAssertEqual(merged.tasks.map(\.text), [" milch", "nur lokal"])
        XCTAssertEqual(merged.tasks[0].completed, true)
        XCTAssertEqual(merged.tasks[0].updatedAt, "2026-09-04T12:00:00.000Z")
        XCTAssertEqual(merged.nextUid, 3)
    }

    func testWithoutTimestampCompletedWins() {
        let a = TodoTask(uid: 1, text: "x", completed: false, updatedAt: "")
        let b = TodoTask(uid: 1, text: "x", completed: true, updatedAt: "")
        let picked = TodoMerge.pickCompleted(base: a, other: b)
        XCTAssertTrue(picked.completed)
    }
}

final class TodoComplicationSnapshotTests: XCTestCase {
    func testOpenCountAndErledigtNeverReadsEinkauf() {
        XCTAssertEqual(TodoComplicationSnapshot.widgetKind, "TodoProgress")
        XCTAssertEqual(TodoComplicationSnapshot.labelText, "To Do")
        XCTAssertEqual(TodoComplicationSnapshot.openURL.absoluteString, "einkauf://todo")
        XCTAssertNotEqual(TodoComplicationSnapshot.widgetKind, ComplicationSnapshot.widgetKind)

        let empty = TodoComplicationSnapshot.make(from: .empty)
        XCTAssertEqual(empty.compactCountText, "erledigt")
        XCTAssertEqual(empty.openCount, 0)
        XCTAssertEqual(empty.progress, 0, accuracy: 0.0001)
        XCTAssertEqual(empty.inlineText, "To Do  erledigt")
        XCTAssertEqual(empty.accessibilityLabel, "To Do, Liste erledigt")

        var state = TodoState(
            tasks: [
                TodoTask(uid: 1, text: "A", completed: false),
                TodoTask(uid: 2, text: "B", completed: true),
                TodoTask(uid: 3, text: "C", completed: false)
            ],
            nextUid: 4,
            revision: 1
        )
        var snap = TodoComplicationSnapshot.make(from: state)
        XCTAssertEqual(snap.compactCountText, "2")
        XCTAssertEqual(snap.openCount, 2)
        XCTAssertEqual(snap.doneCount, 1)
        XCTAssertEqual(snap.progress, 1.0 / 3.0, accuracy: 0.0001)
        XCTAssertEqual(snap.inlineText, "To Do  2")
        XCTAssertEqual(snap.accessibilityLabel, "To Do, 2 offen")

        state.tasks[0].completed = true
        state.tasks[2].completed = true
        snap = TodoComplicationSnapshot.make(from: state)
        XCTAssertEqual(snap.compactCountText, "erledigt")
        XCTAssertEqual(snap.openCount, 0)
        XCTAssertEqual(snap.progress, 1, accuracy: 0.0001)
    }
}

@MainActor
final class TodoStoreSyncAndSiriTests: XCTestCase {
    func testApplyRemoteToggleAndSnapshot() throws {
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
        let uid = try XCTUnwrap(store.add("Anruf"))
        let beforeRevision = store.state.revision
        store.toggle(uid)
        XCTAssertTrue(store.state.tasks[0].completed)
        XCTAssertEqual(store.state.revision, beforeRevision)

        store.applyRemoteToggle(uid: uid, completed: false, at: "2026-12-01T18:00:00.000Z")
        XCTAssertFalse(store.state.tasks[0].completed)

        let remote = TodoState(
            tasks: [
                TodoTask(uid: uid, text: "Anruf", completed: true, updatedAt: "2026-12-01T19:00:00.000Z"),
                TodoTask(uid: 99, text: "Neu remote", updatedAt: "2026-12-01T19:00:00.000Z")
            ],
            nextUid: 100,
            revision: store.state.revision + 1
        )
        store.applyRemoteSnapshot(remote)
        XCTAssertEqual(store.state.tasks.map(\.text), ["Anruf", "Neu remote"])
        XCTAssertEqual(store.state.tasks[0].completed, true)
    }

    func testAddItemsFromSpeechAndPendingQueue() throws {
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
        XCTAssertEqual(store.addItems(fromSpeech: "To Do: Steuer und Anruf"), 2)
        XCTAssertEqual(store.state.tasks.map(\.text), ["Steuer", "Anruf"])
        XCTAssertEqual(store.addItems(fromSpeech: "Rechnung bezahlen"), 1)
        XCTAssertEqual(store.state.tasks.map(\.text), ["Steuer", "Anruf", "Rechnung bezahlen"])
        XCTAssertEqual(store.addItems(fromSpeech: "Katze füttern und Müll rausbringen"), 2)
        XCTAssertEqual(
            store.state.tasks.map(\.text),
            ["Steuer", "Anruf", "Rechnung bezahlen", "Katze füttern", "Müll rausbringen"]
        )

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("todo-siri-pending-test.json")
        try? FileManager.default.removeItem(at: url)
        defer { try? FileManager.default.removeItem(at: url) }
        TodoSiriPendingAdds.enqueue("To Do: Milch, Butter", at: url)
        TodoSiriPendingAdds.enqueue("  ", at: url)
        TodoSiriPendingAdds.enqueue("todo", at: url)
        XCTAssertEqual(TodoSiriPendingAdds.drain(at: url), ["Milch, Butter"])
        XCTAssertEqual(TodoSiriPendingAdds.drain(at: url), [])
        XCTAssertEqual(TodoSiriPendingAdds.defaultsKey, "todo.siriPendingAdds")
        XCTAssertEqual(TodoSiriPendingAdds.fileName, "todo-siri-pending.json")
        XCTAssertNotEqual(TodoSiriPendingAdds.defaultsKey, SiriPendingAdds.defaultsKey)
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
