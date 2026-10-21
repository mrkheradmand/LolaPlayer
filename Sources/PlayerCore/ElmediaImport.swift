import Foundation
import CSQLite

public struct ElmediaImportResult: Sendable {
    public var files = 0
    public var bookmarks = 0
}

public extension MediaLibrary {
    /// Opens only the two observed 8.24 schemas, with SQLITE_OPEN_READONLY.
    /// Keyed archives are decoded with an explicit Foundation class allowlist.
    func importElmedia(from directory: URL) throws -> ElmediaImportResult {
        try batchUpdates {
        var result = ElmediaImportResult()
        func mediaURL(_ text: String) -> URL {
            if let url = URL(string: text), url.scheme != nil { return url }
            return URL(fileURLWithPath: text)
        }
        let playlist = directory.appendingPathComponent("Playlist.db")
        if FileManager.default.fileExists(atPath: playlist.path) {
            try readDatabase(playlist, sql: "SELECT path, length, last_position FROM playlist_items ORDER BY id") { statement in
                guard let path = sqlite3_column_text(statement, 0) else { return }
                let url = mediaURL(String(cString: path))
                let wasKnown = records.contains { $0.location == url }
                let id = try visit(url)
                if !wasKnown {
                    result.files += 1
                    try updatePosition(id, seconds: sqlite3_column_double(statement, 2), duration: sqlite3_column_double(statement, 1))
                }
            }
        }
        let bookmarks = directory.appendingPathComponent("TimeBookmarks.db")
        if FileManager.default.fileExists(atPath: bookmarks.path) {
            try readDatabase(bookmarks, sql: "SELECT path, bookmarks FROM time_bookmarks ORDER BY id") { statement in
                guard let path = sqlite3_column_text(statement, 0), let pointer = sqlite3_column_blob(statement, 1) else { return }
                let url = mediaURL(String(cString: path))
                let wasKnown = records.contains { $0.location == url }
                let id = try visit(url)
                if !wasKnown { result.files += 1 }
                let data = Data(bytes: pointer, count: Int(sqlite3_column_bytes(statement, 1)))
                guard let marks = try NSKeyedUnarchiver.unarchivedObject(ofClasses: [NSArray.self, NSMutableArray.self, NSDictionary.self, NSMutableDictionary.self, NSString.self, NSNumber.self], from: data) as? [[String: Any]] else { return }
                for mark in marks {
                    guard let number = mark["time"] as? NSNumber, number.doubleValue.isFinite else { continue }
                    let time = number.doubleValue
                    let title = mark["title"] as? String ?? mark["name"] as? String ?? "Bookmark \(timestamp(time))"
                    if record(id)?.bookmarks.contains(where: { abs($0.seconds - time) < 0.001 }) == true { continue }
                    try addBookmark(id, seconds: time, title: title); result.bookmarks += 1
                }
            }
        }
        return result
        }
    }
}

private func readDatabase(_ url: URL, sql: String, row: (OpaquePointer) throws -> Void) throws {
    var database: OpaquePointer?
    guard sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let database else {
        if let database { sqlite3_close(database) }
        throw CocoaError(.fileReadNoPermission, userInfo: [NSFilePathErrorKey: url.path])
    }
    defer { sqlite3_close(database) }
    sqlite3_busy_timeout(database, 1000)
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
        throw CocoaError(.fileReadCorruptFile, userInfo: [NSLocalizedDescriptionKey: "The Elmedia database schema is not supported."])
    }
    defer { sqlite3_finalize(statement) }
    var status = sqlite3_step(statement)
    while status == SQLITE_ROW { try row(statement); status = sqlite3_step(statement) }
    guard status == SQLITE_DONE else { throw CocoaError(.fileReadUnknown) }
}
