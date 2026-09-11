import XCTest
@testable import EinkaufCore

final class ItemArchiveCodecTests: XCTestCase {
    func testMissingFileIsEmptyArchive() {
        withIsolatedArchiveFiles {
            try? FileManager.default.removeItem(at: CompletedItemArchive.einkaufFileURL)
            try? FileManager.default.removeItem(at: CompletedItemArchive.todoFileURL)
            let einkauf = CompletedItemArchive.loadEinkauf()
            let todo = CompletedItemArchive.loadTodo()
            XCTAssertEqual(einkauf.v, 1)
            XCTAssertTrue(einkauf.entries.isEmpty)
            XCTAssertEqual(todo.v, 1)
            XCTAssertTrue(todo.entries.isEmpty)
        }
    }

    func testEmptyFileIsEmptyArchive() throws {
        withIsolatedArchiveFiles {
            try Data().write(to: CompletedItemArchive.einkaufFileURL, options: .atomic)
            let file = CompletedItemArchive.loadEinkauf()
            XCTAssertEqual(file.v, 1)
            XCTAssertTrue(file.entries.isEmpty)
        }
    }

    func testAppendWritesISO8601ArchivedAtAndLocalItemSnapshot() throws {
        withIsolatedArchiveFiles {
            let date = Date(timeIntervalSince1970: 1_788_768_000) // 2026-09-07T12:00:00Z
            let item = Item(
                id: "i1",
                name: "Milch",
                dept: "kuehlung",
                done: true,
                added: 10,
                ord: 1,
                doneChangedAt: 20,
                imported: true,
                urgency: .later
            )
            CompletedItemArchive.appendEinkauf([item], at: date)
            let file = CompletedItemArchive.loadEinkauf()
            XCTAssertEqual(file.v, 1)
            XCTAssertEqual(file.entries.count, 1)
            XCTAssertEqual(file.entries[0].archivedAt, CompletedItemArchive.iso8601(date))
            XCTAssertTrue(file.entries[0].archivedAt.contains("T"))
            XCTAssertEqual(file.entries[0].item.id, "i1")
            XCTAssertEqual(file.entries[0].item.name, "Milch")
            XCTAssertTrue(file.entries[0].item.done)
            XCTAssertEqual(file.entries[0].item.doneChangedAt, 20)
            XCTAssertTrue(file.entries[0].item.imported)
            XCTAssertEqual(file.entries[0].item.urgency, .later)

            let raw = try Data(contentsOf: CompletedItemArchive.einkaufFileURL)
            let obj = try JSONSerialization.jsonObject(with: raw) as! [String: Any]
            XCTAssertEqual(obj["v"] as? Int, 1)
            XCTAssertNil(obj["kind"])
            let entries = obj["entries"] as! [[String: Any]]
            XCTAssertEqual(entries.count, 1)
            XCTAssertEqual(entries[0]["archivedAt"] as? String, CompletedItemArchive.iso8601(date))
            let snapshot = entries[0]["item"] as! [String: Any]
            XCTAssertEqual(snapshot["id"] as? String, "i1")
            XCTAssertEqual(snapshot["done"] as? Bool, true)
            XCTAssertEqual((snapshot["doneChangedAt"] as? NSNumber)?.doubleValue, 20)
            XCTAssertEqual(snapshot["imported"] as? Bool, true)
            XCTAssertEqual(snapshot["urgency"] as? String, "later")
        }
    }

    func testAppendNeverOverwritesHistory() throws {
        withIsolatedArchiveFiles {
            let first = Date(timeIntervalSince1970: 1_788_768_000)
            let second = Date(timeIntervalSince1970: 1_788_768_060)
            CompletedItemArchive.appendEinkauf(
                [Item(id: "a", name: "A", dept: "obst", done: true, added: 1, ord: 1)],
                at: first
            )
            CompletedItemArchive.appendEinkauf(
                [Item(id: "b", name: "B", dept: "brot", done: true, added: 2, ord: 2)],
                at: second
            )
            let file = CompletedItemArchive.loadEinkauf()
            XCTAssertEqual(file.entries.map(\.item.id), ["a", "b"])
            XCTAssertEqual(file.entries.map(\.archivedAt), [
                CompletedItemArchive.iso8601(first),
                CompletedItemArchive.iso8601(second)
            ])
            XCTAssertNotEqual(file.entries[0].archivedAt, file.entries[1].archivedAt)
        }
    }

    func testBulkAppendWritesOneEntryPerItemWithSharedArchivedAt() {
        withIsolatedArchiveFiles {
            let date = Date(timeIntervalSince1970: 1_788_768_000)
            let items = [
                Item(id: "a", name: "A", dept: "obst", done: true, added: 1, ord: 1),
                Item(id: "b", name: "B", dept: "brot", done: true, added: 2, ord: 2),
                Item(id: "c", name: "C", dept: "kuehlung", done: false, added: 3, ord: 3)
            ]
            CompletedItemArchive.appendEinkauf(items, at: date)
            let file = CompletedItemArchive.loadEinkauf()
            XCTAssertEqual(file.entries.map(\.item.id), ["a", "b"])
            XCTAssertEqual(Set(file.entries.map(\.archivedAt)).count, 1)
            XCTAssertEqual(file.entries[0].archivedAt, CompletedItemArchive.iso8601(date))
        }
    }

    func testOpenItemsAreNotArchived() {
        withIsolatedArchiveFiles {
            CompletedItemArchive.appendEinkauf([
                Item(id: "open", name: "Offen", dept: "obst", done: false, added: 1, ord: 1)
            ])
            XCTAssertTrue(CompletedItemArchive.loadEinkauf().entries.isEmpty)

            CompletedItemArchive.appendTodo([
                TodoTask(uid: 1, text: "Offen", completed: false)
            ])
            XCTAssertTrue(CompletedItemArchive.loadTodo().entries.isEmpty)
        }
    }

    func testCorruptFileIsNotOverwritten() throws {
        withIsolatedArchiveFiles {
            let garbage = Data("{not-json".utf8)
            try garbage.write(to: CompletedItemArchive.einkaufFileURL, options: .atomic)
            CompletedItemArchive.appendEinkauf([
                Item(id: "a", name: "A", dept: "obst", done: true, added: 1, ord: 1)
            ])
            XCTAssertEqual(try Data(contentsOf: CompletedItemArchive.einkaufFileURL), garbage)
        }
    }

    func testTodoAppendKeepsTaskSnapshotAndISO8601() throws {
        withIsolatedArchiveFiles {
            let date = Date(timeIntervalSince1970: 1_788_768_000)
            let task = TodoTask(
                uid: 9,
                text: "Anrufen",
                completed: true,
                prioA: "A",
                prioB: "1",
                dueDate: "2026-09-08",
                completedDate: "2026-09-07",
                person: "NA",
                createdAt: "2026-09-01T10:00:00.000Z",
                updatedAt: "2026-09-07T11:00:00.000Z",
                changedBy: "TS/NA",
                listId: "list-1"
            )
            CompletedItemArchive.appendTodo([task], at: date)
            let file = CompletedItemArchive.loadTodo()
            XCTAssertEqual(file.v, 1)
            XCTAssertEqual(file.entries.count, 1)
            XCTAssertEqual(file.entries[0].archivedAt, CompletedItemArchive.iso8601(date))
            XCTAssertEqual(file.entries[0].item.uid, 9)
            XCTAssertEqual(file.entries[0].item.text, "Anrufen")
            XCTAssertTrue(file.entries[0].item.completed)
            XCTAssertEqual(file.entries[0].item.listId, "list-1")

            let raw = try Data(contentsOf: CompletedItemArchive.todoFileURL)
            let obj = try JSONSerialization.jsonObject(with: raw) as! [String: Any]
            XCTAssertEqual(obj["v"] as? Int, 1)
            XCTAssertNil(obj["kind"])
            let entries = obj["entries"] as! [[String: Any]]
            let snapshot = entries[0]["item"] as! [String: Any]
            XCTAssertEqual((snapshot["uid"] as? NSNumber)?.int64Value, 9)
            XCTAssertEqual(snapshot["completed"] as? Bool, true)
            XCTAssertEqual(snapshot["listId"] as? String, "list-1")
        }
    }

    func testFilesSitBesideLocalJSON() {
        XCTAssertEqual(CompletedItemArchive.einkaufFileURL.lastPathComponent, "einkauf-archiv.json")
        XCTAssertEqual(CompletedItemArchive.todoFileURL.lastPathComponent, "todo-archiv.json")
        XCTAssertEqual(
            CompletedItemArchive.einkaufFileURL.deletingLastPathComponent().path,
            Persistence.fileURL.deletingLastPathComponent().path
        )
        XCTAssertEqual(
            CompletedItemArchive.todoFileURL.deletingLastPathComponent().path,
            TodoPersistence.fileURL.deletingLastPathComponent().path
        )
        XCTAssertNotEqual(CompletedItemArchive.einkaufFileURL.path, Persistence.fileURL.path)
        XCTAssertNotEqual(CompletedItemArchive.todoFileURL.path, TodoPersistence.fileURL.path)
    }

    func testExportEmptyArchiveIsValidJSON() throws {
        withIsolatedArchiveFiles {
            try? FileManager.default.removeItem(at: CompletedItemArchive.einkaufFileURL)
            let data = try CompletedItemArchive.encodeEinkauf()
            let obj = try JSONSerialization.jsonObject(with: data) as! [String: Any]
            XCTAssertEqual(obj["v"] as? Int, 1)
            XCTAssertEqual((obj["entries"] as? [Any])?.count, 0)
        }
    }

    func testDeleteSingleEntryPersistsAndLeavesOthers() throws {
        withIsolatedArchiveFiles {
            let first = Date(timeIntervalSince1970: 1_788_768_000)
            let second = Date(timeIntervalSince1970: 1_788_768_060)
            let third = Date(timeIntervalSince1970: 1_788_768_120)
            CompletedItemArchive.appendEinkauf(
                [Item(id: "a", name: "A", dept: "obst", done: true, added: 1, ord: 1)],
                at: first
            )
            CompletedItemArchive.appendEinkauf(
                [Item(id: "b", name: "B", dept: "brot", done: true, added: 2, ord: 2)],
                at: second
            )
            CompletedItemArchive.appendEinkauf(
                [Item(id: "c", name: "C", dept: "kuehlung", done: true, added: 3, ord: 3)],
                at: third
            )
            XCTAssertTrue(CompletedItemArchive.deleteEinkauf(at: 1))
            let file = CompletedItemArchive.loadEinkauf()
            XCTAssertEqual(file.entries.map(\.item.id), ["a", "c"])
            XCTAssertEqual(file.entries.map(\.item.name), ["A", "C"])
            XCTAssertEqual(file.v, 1)

            let raw = try Data(contentsOf: CompletedItemArchive.einkaufFileURL)
            let obj = try JSONSerialization.jsonObject(with: raw) as! [String: Any]
            let entries = obj["entries"] as! [[String: Any]]
            XCTAssertEqual(entries.count, 2)
            let names = entries.compactMap { ($0["item"] as? [String: Any])?["name"] as? String }
            XCTAssertEqual(names, ["A", "C"])
        }
    }

    func testDeletedEntryDoesNotReturnOnLaterAppend() {
        withIsolatedArchiveFiles {
            CompletedItemArchive.appendEinkauf(
                [Item(id: "a", name: "A", dept: "obst", done: true, added: 1, ord: 1)]
            )
            CompletedItemArchive.appendEinkauf(
                [Item(id: "b", name: "B", dept: "brot", done: true, added: 2, ord: 2)]
            )
            XCTAssertTrue(CompletedItemArchive.deleteEinkauf(at: 0))
            CompletedItemArchive.appendEinkauf(
                [Item(id: "c", name: "C", dept: "kuehlung", done: true, added: 3, ord: 3)]
            )
            XCTAssertEqual(CompletedItemArchive.loadEinkauf().entries.map(\.item.id), ["b", "c"])
        }
    }

    func testDeleteDisplayedNewestMapsToLastFileIndex() throws {
        withIsolatedArchiveFiles {
            CompletedItemArchive.appendEinkauf(
                [Item(id: "a", name: "A", dept: "obst", done: true, added: 1, ord: 1)]
            )
            CompletedItemArchive.appendEinkauf(
                [Item(id: "b", name: "B", dept: "brot", done: true, added: 2, ord: 2)]
            )
            CompletedItemArchive.appendEinkauf(
                [Item(id: "c", name: "C", dept: "kuehlung", done: true, added: 3, ord: 3)]
            )
            let file = CompletedItemArchive.loadEinkauf()
            let rows = CompletedItemArchive.displayRows(file.entries, title: { $0.name })
            XCTAssertEqual(rows.map(\.title), ["C", "B", "A"])
            XCTAssertEqual(rows.map(\.fileIndex), [2, 1, 0])
            let newest = CompletedItemArchive.fileIndices(
                fromDisplayed: IndexSet(integer: 0),
                entryCount: rows.count
            )
            XCTAssertEqual(newest, IndexSet(integer: 2))
            XCTAssertTrue(CompletedItemArchive.deleteEinkauf(at: newest))
            XCTAssertEqual(CompletedItemArchive.loadEinkauf().entries.map(\.item.id), ["a", "b"])
        }
    }

    func testDeleteTodoEntryPersists() throws {
        withIsolatedArchiveFiles {
            CompletedItemArchive.appendTodo([
                TodoTask(uid: 1, text: "Eins", completed: true),
                TodoTask(uid: 2, text: "Zwei", completed: true)
            ])
            XCTAssertTrue(CompletedItemArchive.deleteTodo(at: 0))
            let file = CompletedItemArchive.loadTodo()
            XCTAssertEqual(file.entries.map(\.item.text), ["Zwei"])
            XCTAssertEqual(file.entries.map(\.item.uid), [2])

            let raw = try Data(contentsOf: CompletedItemArchive.todoFileURL)
            let obj = try JSONSerialization.jsonObject(with: raw) as! [String: Any]
            let entries = obj["entries"] as! [[String: Any]]
            XCTAssertEqual(entries.count, 1)
            let snapshot = entries[0]["item"] as! [String: Any]
            XCTAssertEqual(snapshot["text"] as? String, "Zwei")
        }
    }

    func testDeleteOutOfRangeDoesNotCreateOrClearFile() {
        withIsolatedArchiveFiles {
            try? FileManager.default.removeItem(at: CompletedItemArchive.einkaufFileURL)
            XCTAssertFalse(CompletedItemArchive.deleteEinkauf(at: 0))
            XCTAssertFalse(FileManager.default.fileExists(atPath: CompletedItemArchive.einkaufFileURL.path))

            CompletedItemArchive.appendEinkauf(
                [Item(id: "a", name: "A", dept: "obst", done: true, added: 1, ord: 1)]
            )
            XCTAssertFalse(CompletedItemArchive.deleteEinkauf(at: 9))
            XCTAssertEqual(CompletedItemArchive.loadEinkauf().entries.map(\.item.id), ["a"])
        }
    }

    func testDeleteDoesNotOverwriteCorruptFile() throws {
        withIsolatedArchiveFiles {
            let garbage = Data("{not-json".utf8)
            try garbage.write(to: CompletedItemArchive.einkaufFileURL, options: .atomic)
            XCTAssertFalse(CompletedItemArchive.deleteEinkauf(at: 0))
            XCTAssertEqual(try Data(contentsOf: CompletedItemArchive.einkaufFileURL), garbage)
        }
    }

    func testDisplayArchivedAtIsReadableGerman() {
        let iso = CompletedItemArchive.iso8601(Date(timeIntervalSince1970: 1_788_768_000))
        let label = CompletedItemArchive.displayArchivedAt(iso, timeZone: TimeZone(secondsFromGMT: 0)!)
        XCTAssertEqual(label, "07.09.2026, 12:00")
        XCTAssertEqual(CompletedItemArchive.displayTitle("  Milch  "), "Milch")
        XCTAssertEqual(CompletedItemArchive.displayTitle("   "), "Ohne Titel")
    }

    func testDeleteLastEntryWritesEmptyArchiveNotClearAllAPI() throws {
        withIsolatedArchiveFiles {
            CompletedItemArchive.appendEinkauf(
                [Item(id: "a", name: "A", dept: "obst", done: true, added: 1, ord: 1)]
            )
            XCTAssertTrue(CompletedItemArchive.deleteEinkauf(at: 0))
            let file = CompletedItemArchive.loadEinkauf()
            XCTAssertTrue(file.entries.isEmpty)
            XCTAssertEqual(file.v, 1)
            let data = try CompletedItemArchive.encodeEinkauf()
            let obj = try JSONSerialization.jsonObject(with: data) as! [String: Any]
            XCTAssertEqual((obj["entries"] as? [Any])?.count, 0)
        }
    }
}

@MainActor
final class ItemArchiveStoreTests: XCTestCase {
    func testClearDoneArchivesOnlyCompletedAndLeavesOpen() throws {
        withIsolatedArchiveFiles {
            isolateLocalFiles {
                let store = ShoppingStore(state: .seed, enableSync: false)
                store.addItem("Offen")
                store.addItem("Fertig")
                let doneId = store.state.items[1].id
                store.toggle(doneId)
                XCTAssertTrue(CompletedItemArchive.loadEinkauf().entries.isEmpty)

                store.clearDone()
                XCTAssertEqual(store.state.items.map(\.name), ["Offen"])
                let archived = CompletedItemArchive.loadEinkauf()
                XCTAssertEqual(archived.entries.map(\.item.name), ["Fertig"])
                XCTAssertTrue(archived.entries[0].item.done)
                XCTAssertFalse(archived.entries[0].archivedAt.isEmpty)
            }
        }
    }

    func testDeleteOpenEditRowDoesNotArchive() throws {
        withIsolatedArchiveFiles {
            isolateLocalFiles {
                let store = ShoppingStore(state: .seed, enableSync: false)
                store.addItem("Milch")
                store.addItem("Butter")
                store.toggle(store.state.items[1].id)
                let rows = store.editRows
                guard let openIdx = rows.firstIndex(where: {
                    if case .item(_, let item) = $0 { return item.name == "Milch" }
                    return false
                }) else {
                    return XCTFail("open row missing")
                }
                store.deleteEditRows(at: IndexSet(integer: openIdx))
                XCTAssertTrue(CompletedItemArchive.loadEinkauf().entries.isEmpty)
                XCTAssertEqual(store.state.items.map(\.name), ["Butter"])
            }
        }
    }

    func testDeleteCompletedEditRowArchivesSnapshot() throws {
        withIsolatedArchiveFiles {
            isolateLocalFiles {
                let store = ShoppingStore(state: .seed, enableSync: false)
                store.addItem("Milch")
                store.toggle(store.state.items[0].id)
                let rows = store.editRows
                guard let doneIdx = rows.firstIndex(where: {
                    if case .item(_, let item) = $0 { return item.done }
                    return false
                }) else {
                    return XCTFail("done row missing")
                }
                store.deleteEditRows(at: IndexSet(integer: doneIdx))
                XCTAssertTrue(store.state.items.isEmpty)
                let archived = CompletedItemArchive.loadEinkauf()
                XCTAssertEqual(archived.entries.map(\.item.name), ["Milch"])
                XCTAssertTrue(archived.entries[0].item.done)
            }
        }
    }

    func testToggleDoesNotArchive() throws {
        withIsolatedArchiveFiles {
            isolateLocalFiles {
                let store = ShoppingStore(state: .seed, enableSync: false)
                store.addItem("Milch")
                store.toggle(store.state.items[0].id)
                store.toggle(store.state.items[0].id)
                XCTAssertTrue(CompletedItemArchive.loadEinkauf().entries.isEmpty)
                XCTAssertEqual(store.state.items.count, 1)
            }
        }
    }

    func testTodoDeleteAndClearCompletedArchiveOnlyDone() throws {
        withIsolatedArchiveFiles {
            isolateTodoLocal {
                let store = TodoStore(state: .empty, enableSync: false)
                let open = try XCTUnwrap(store.add("Offen"))
                let done = try XCTUnwrap(store.add("Fertig"))
                store.toggle(done)
                XCTAssertTrue(CompletedItemArchive.loadTodo().entries.isEmpty)

                store.delete(open)
                XCTAssertTrue(CompletedItemArchive.loadTodo().entries.isEmpty)
                XCTAssertEqual(store.state.tasks.map(\.text), ["Fertig"])

                store.clearCompleted()
                XCTAssertTrue(store.state.tasks.isEmpty)
                let archived = CompletedItemArchive.loadTodo()
                XCTAssertEqual(archived.entries.map(\.item.text), ["Fertig"])
                XCTAssertTrue(archived.entries[0].item.completed)
                XCTAssertFalse(archived.entries[0].archivedAt.isEmpty)
            }
        }
    }

    func testTodoBulkClearSharesArchivedAt() throws {
        withIsolatedArchiveFiles {
            isolateTodoLocal {
                let store = TodoStore(state: .empty, enableSync: false)
                let a = try XCTUnwrap(store.add("A"))
                let b = try XCTUnwrap(store.add("B"))
                store.toggle(a)
                store.toggle(b)
                store.clearCompleted()
                let stamps = CompletedItemArchive.loadTodo().entries.map(\.archivedAt)
                XCTAssertEqual(stamps.count, 2)
                XCTAssertEqual(stamps[0], stamps[1])
            }
        }
    }

    func testRestoreEinkaufCopiesOpenItemKeepsArchive() throws {
        withIsolatedArchiveFiles {
            isolateLocalFiles {
                let store = ShoppingStore(state: .seed, enableSync: false)
                store.addItem("Milch")
                store.cycleItemUrgency(store.state.items[0].id)
                store.toggle(store.state.items[0].id)
                store.clearDone()
                XCTAssertTrue(store.state.items.isEmpty)
                let archived = CompletedItemArchive.loadEinkauf()
                XCTAssertEqual(archived.entries.map(\.item.name), ["Milch"])
                let oldId = archived.entries[0].item.id
                let snapshotDept = archived.entries[0].item.dept
                let snapshotUrgency = archived.entries[0].item.urgency
                let newId = store.restoreFromArchive(archived.entries[0].item)
                XCTAssertEqual(newId, store.state.items.last?.id)
                XCTAssertNotEqual(newId, oldId)
                XCTAssertEqual(store.state.items.count, 1)
                XCTAssertEqual(store.state.items[0].name, "Milch")
                XCTAssertFalse(store.state.items[0].done)
                XCTAssertEqual(store.state.items[0].dept, snapshotDept)
                XCTAssertEqual(store.state.items[0].urgency, snapshotUrgency)
                XCTAssertFalse(store.state.items[0].imported)
                XCTAssertEqual(CompletedItemArchive.loadEinkauf().entries.map(\.item.id), [oldId])
                XCTAssertTrue(CompletedItemArchive.loadEinkauf().entries[0].item.done)
            }
        }
    }

    func testRestoreEinkaufTwiceCreatesTwoOpenCopiesArchiveUnchanged() throws {
        withIsolatedArchiveFiles {
            isolateLocalFiles {
                let store = ShoppingStore(state: .seed, enableSync: false)
                store.addItem("Butter")
                store.toggle(store.state.items[0].id)
                store.clearDone()
                let snapshot = CompletedItemArchive.loadEinkauf().entries[0].item
                let first = try XCTUnwrap(store.restoreFromArchive(snapshot))
                let second = try XCTUnwrap(store.restoreFromArchive(snapshot))
                XCTAssertNotEqual(first, second)
                XCTAssertEqual(store.state.items.map(\.name), ["Butter", "Butter"])
                XCTAssertTrue(store.state.items.allSatisfy { !$0.done })
                XCTAssertEqual(CompletedItemArchive.loadEinkauf().entries.count, 1)
            }
        }
    }

    func testRestoreEinkaufEmptyNameIsNoOp() {
        withIsolatedArchiveFiles {
            isolateLocalFiles {
                let store = ShoppingStore(state: .seed, enableSync: false)
                XCTAssertNil(store.restoreFromArchive(
                    Item(id: "x", name: "   ", dept: "obst", done: true, added: 1, ord: 1)
                ))
                XCTAssertTrue(store.state.items.isEmpty)
                XCTAssertTrue(CompletedItemArchive.loadEinkauf().entries.isEmpty)
            }
        }
    }

    func testRestoreTodoCopiesOpenTaskKeepsArchive() throws {
        withIsolatedArchiveFiles {
            isolateTodoLocal {
                let store = TodoStore(state: .empty, enableSync: false)
                let uid = try XCTUnwrap(store.add(
                    "Anrufen",
                    person: "NA",
                    prioA: "A",
                    prioB: "1",
                    dueDate: "2026-09-08",
                    listId: "list-1"
                ))
                store.toggle(uid)
                store.clearCompleted()
                XCTAssertTrue(store.state.tasks.isEmpty)
                let archived = CompletedItemArchive.loadTodo()
                XCTAssertEqual(archived.entries.map(\.item.text), ["Anrufen"])
                let oldUid = archived.entries[0].item.uid
                let newUid = try XCTUnwrap(store.restoreFromArchive(archived.entries[0].item))
                XCTAssertNotEqual(newUid, oldUid)
                XCTAssertEqual(store.state.tasks.count, 1)
                XCTAssertEqual(store.state.tasks[0].text, "Anrufen")
                XCTAssertFalse(store.state.tasks[0].completed)
                XCTAssertEqual(store.state.tasks[0].person, "NA")
                XCTAssertEqual(store.state.tasks[0].prioA, "A")
                XCTAssertEqual(store.state.tasks[0].prioB, "1")
                XCTAssertEqual(store.state.tasks[0].dueDate, "2026-09-08")
                XCTAssertEqual(store.state.tasks[0].listId, "list-1")
                XCTAssertTrue(store.state.tasks[0].completedDate.isEmpty)
                XCTAssertEqual(CompletedItemArchive.loadTodo().entries.map(\.item.uid), [oldUid])
                XCTAssertTrue(CompletedItemArchive.loadTodo().entries[0].item.completed)
            }
        }
    }
}

private func isolateLocalFiles(_ body: () throws -> Void) rethrows {
    let url = Persistence.fileURL
    let previous = try? Data(contentsOf: url)
    try? FileManager.default.removeItem(at: url)
    defer {
        if let previous {
            try? previous.write(to: url, options: .atomic)
        } else {
            try? FileManager.default.removeItem(at: url)
        }
    }
    try body()
}

private func isolateTodoLocal(_ body: () throws -> Void) rethrows {
    let url = TodoPersistence.fileURL
    let previous = try? Data(contentsOf: url)
    try? FileManager.default.removeItem(at: url)
    defer {
        if let previous {
            try? previous.write(to: url, options: .atomic)
        } else {
            try? FileManager.default.removeItem(at: url)
        }
    }
    try body()
}

private func withIsolatedArchiveFiles(_ body: () throws -> Void) rethrows {
    let einkauf = CompletedItemArchive.einkaufFileURL
    let todo = CompletedItemArchive.todoFileURL
    let previousEinkauf = try? Data(contentsOf: einkauf)
    let previousTodo = try? Data(contentsOf: todo)
    try? FileManager.default.removeItem(at: einkauf)
    try? FileManager.default.removeItem(at: todo)
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
    try body()
}
