import Foundation

public struct MediaBookmark: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public var seconds: Double
    public var title: String
    public init(seconds: Double, title: String) {
        id = UUID(); self.seconds = max(0, seconds); self.title = title
    }
}

public struct MediaRecord: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var location: URL
    public var fileIdentity: String?
    public var accessBookmark: Data?
    public var lastOpened: Date
    public var position: Double
    public var duration: Double
    public var bookmarks: [MediaBookmark]
    /// Nil in older libraries means visible. History membership is independent of bookmarks/queue.
    public var isInHistory: Bool?
    public var name: String { location.isFileURL ? location.lastPathComponent : location.absoluteString }
    public init(location: URL, fileIdentity: String? = nil) {
        id = UUID(); self.location = location; self.fileIdentity = fileIdentity
        lastOpened = Date(); position = 0; duration = 0; bookmarks = []
    }
}

public struct PlaybackPolicy {
    public static func shouldFloat(enabled: Bool, loaded: Bool, paused: Bool, buffering: Bool, ended: Bool, failed: Bool) -> Bool {
        enabled && loaded && !paused && !buffering && !ended && !failed
    }
}

/// History and bookmarks share one durable identity; removing a playlist entry never removes either.
public final class MediaLibrary {
    public private(set) var records: [MediaRecord] = []
    public let fileURL: URL
    public init(fileURL: URL) throws {
        self.fileURL = fileURL
        if FileManager.default.fileExists(atPath: fileURL.path) {
            records = try JSONDecoder().decode([MediaRecord].self, from: Data(contentsOf: fileURL))
        }
    }
    public var recent: [MediaRecord] { records.sorted { $0.lastOpened > $1.lastOpened } }
    public var history: [MediaRecord] { recent.filter { $0.isInHistory != false } }
    public func record(_ id: UUID) -> MediaRecord? { records.first { $0.id == id } }

    /// Discover folder siblings without marking unopened files as recently played.
    public func register(_ inputs: [URL]) throws -> [UUID] {
        var ids: [UUID] = []
        for input in inputs {
            let url = input.standardizedFileURL.resolvingSymlinksInPath()
            let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
            let identity: String? = if let device = attributes?[.systemNumber], let inode = attributes?[.systemFileNumber] { "\(device):\(inode)" } else { nil }
            let i: Int
            if let found = records.firstIndex(where: { $0.location == url || (identity != nil && $0.fileIdentity == identity) }) {
                i = found
                records[i].location = url; records[i].fileIdentity = identity
            } else {
                var item = MediaRecord(location: url, fileIdentity: identity)
                item.isInHistory = false
                records.append(item); i = records.count - 1
            }
            ids.append(records[i].id)
        }
        try save(); return ids
    }

    @discardableResult public func visit(_ input: URL) throws -> UUID {
        let url = input.isFileURL ? input.standardizedFileURL.resolvingSymlinksInPath() : input
        let attributes = url.isFileURL ? try? FileManager.default.attributesOfItem(atPath: url.path) : nil
        let identity: String? = if let device = attributes?[.systemNumber], let inode = attributes?[.systemFileNumber] { "\(device):\(inode)" } else { nil }
        let index = records.firstIndex { $0.location == url || (identity != nil && $0.fileIdentity == identity) }
        let i: Int
        if let index { i = index } else { records.append(MediaRecord(location: url, fileIdentity: identity)); i = records.count - 1 }
        records[i].location = url; records[i].fileIdentity = identity; records[i].lastOpened = Date()
        records[i].isInHistory = true
        if url.isFileURL { records[i].accessBookmark = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) }
        try save(); return records[i].id
    }

    public func resolve(_ id: UUID) -> URL? {
        guard let item = record(id) else { return nil }
        if let data = item.accessBookmark {
            var stale = false
            if let resolved = try? URL(resolvingBookmarkData: data, options: [.withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale),
               FileManager.default.fileExists(atPath: resolved.path) { return resolved }
        }
        return item.location
    }
    public func updatePosition(_ id: UUID, seconds: Double, duration: Double) throws {
        guard let i = records.firstIndex(where: { $0.id == id }) else { return }
        if seconds.isFinite { records[i].position = max(0, seconds) }
        if duration.isFinite { records[i].duration = max(0, duration) }
        try save()
    }
    public func relocate(_ id: UUID, to input: URL) throws {
        guard let i = records.firstIndex(where: { $0.id == id }) else { return }
        let url = input.standardizedFileURL.resolvingSymlinksInPath()
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        records[i].location = url
        if let device = attributes[.systemNumber], let inode = attributes[.systemFileNumber] { records[i].fileIdentity = "\(device):\(inode)" }
        records[i].accessBookmark = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        try save()
    }
    public func addBookmark(_ id: UUID, seconds: Double, title: String) throws {
        guard seconds.isFinite, let i = records.firstIndex(where: { $0.id == id }) else { return }
        records[i].bookmarks.append(MediaBookmark(seconds: seconds, title: title))
        records[i].bookmarks.sort { $0.seconds < $1.seconds }; try save()
    }
    public func editBookmark(_ id: UUID, bookmark: UUID, title: String, seconds: Double) throws {
        guard seconds.isFinite, let i = records.firstIndex(where: { $0.id == id }), let b = records[i].bookmarks.firstIndex(where: { $0.id == bookmark }) else { return }
        records[i].bookmarks[b].title = title; records[i].bookmarks[b].seconds = max(0, seconds)
        records[i].bookmarks.sort { $0.seconds < $1.seconds }; try save()
    }
    public func removeBookmark(_ id: UUID, bookmark: UUID) throws {
        guard let i = records.firstIndex(where: { $0.id == id }) else { return }
        records[i].bookmarks.removeAll { $0.id == bookmark }; try save()
    }
    public func removeAllBookmarks(_ id: UUID) throws {
        guard let i = records.firstIndex(where: { $0.id == id }) else { return }
        records[i].bookmarks = []; try save()
    }
    public func removeFromHistory(_ id: UUID) throws {
        guard let i = records.firstIndex(where: { $0.id == id }) else { return }
        records[i].isInHistory = false; try save()
    }
    public func emptyHistory() throws {
        for i in records.indices { records[i].isInHistory = false }
        try save()
    }
    public func clearUnbookmarkedHistory() throws {
        records.removeAll { $0.bookmarks.isEmpty }; try save()
    }
    public func save() throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(records).write(to: fileURL, options: .atomic)
    }
}

public func timestamp(_ seconds: Double) -> String {
    guard seconds.isFinite else { return "00:00" }
    let s = Int(max(0, seconds))
    return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, (s / 60) % 60, s % 60) : String(format: "%02d:%02d", s / 60, s % 60)
}
