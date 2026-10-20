import Foundation
import Testing
import CSQLite
@testable import PlayerCore

struct ImportTests {
    @Test func elmediaImportIsReadOnlyAndIdempotent() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("TimeBookmarks.db")
        let marks: NSArray = [["time": 33.742, "title": "Opening"], ["time": 202.076]]
        let archive = try NSKeyedArchiver.archivedData(withRootObject: marks, requiringSecureCoding: false)
        var db: OpaquePointer?
        #expect(sqlite3_open(url.path, &db) == SQLITE_OK)
        sqlite3_exec(db, "CREATE TABLE time_bookmarks (id INTEGER PRIMARY KEY, path TEXT, bookmarks BLOB)", nil, nil, nil)
        var statement: OpaquePointer?
        sqlite3_prepare_v2(db, "INSERT INTO time_bookmarks VALUES (1, '/tmp/imported.mp4', ?)", -1, &statement, nil)
        _ = archive.withUnsafeBytes { bytes in
            sqlite3_bind_blob(statement, 1, bytes.baseAddress, Int32(bytes.count), unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        }
        #expect(sqlite3_step(statement) == SQLITE_DONE)
        sqlite3_finalize(statement); sqlite3_close(db)
        let before = try Data(contentsOf: url)
        let library = try MediaLibrary(fileURL: root.appendingPathComponent("library.json"))
        let result = try library.importElmedia(from: root)
        #expect(result.files == 1); #expect(result.bookmarks == 2)
        #expect(library.records.first?.bookmarks.first?.title == "Opening")
        #expect(library.records.first?.bookmarks.last?.seconds == 202.076)
        let again = try library.importElmedia(from: root)
        #expect(again.files == 0); #expect(again.bookmarks == 0)
        #expect(try Data(contentsOf: url) == before)
    }
}
