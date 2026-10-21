import Foundation
import Testing
@testable import PlayerCore

struct LibraryTests {
    func fixture() throws -> (URL, MediaLibrary) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        return (root, try MediaLibrary(fileURL: root.appendingPathComponent("library.json")))
    }
    @Test func bookmarksSurviveFileSwitchingAndRelaunch() throws {
        let (root, library) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let a = try library.visit(URL(fileURLWithPath: "/tmp/first.mp4"))
        try library.addBookmark(a, seconds: 33.125, title: "A moment")
        let b = try library.visit(URL(fileURLWithPath: "/tmp/second.mkv"))
        try library.addBookmark(b, seconds: 202.5, title: "Another moment")
        try library.updatePosition(a, seconds: 90, duration: 300)
        let reopened = try MediaLibrary(fileURL: library.fileURL)
        #expect(reopened.records.count == 2)
        #expect(reopened.record(a)?.bookmarks.first?.seconds == 33.125)
        #expect(reopened.record(b)?.bookmarks.first?.seconds == 202.5)
        #expect(reopened.record(a)?.position == 90)
        #expect(try reopened.visit(URL(fileURLWithPath: "/tmp/first.mp4")) == a)
        #expect(reopened.records.count == 2)
    }
    @Test func fileRenameAndSymlinkRetainBookmarks() throws {
        let (root, library) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let original = root.appendingPathComponent("old.mp4")
        try Data("fixture".utf8).write(to: original)
        let id = try library.visit(original)
        try library.addBookmark(id, seconds: 21, title: "keep")
        let link = root.appendingPathComponent("link.mp4")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: original)
        #expect(try library.visit(link) == id)
        let renamed = root.appendingPathComponent("new.mp4")
        try FileManager.default.moveItem(at: original, to: renamed)
        #expect(try library.visit(renamed) == id)
        #expect(library.record(id)?.bookmarks.count == 1)
    }
    @Test func historyCleanupPreservesBookmarkedFiles() throws {
        let (root, library) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let a = try library.visit(URL(fileURLWithPath: "/tmp/kept.mp4"))
        try library.addBookmark(a, seconds: 1, title: "Keep")
        _ = try library.visit(URL(fileURLWithPath: "/tmp/removed.mp4"))
        try library.clearUnbookmarkedHistory()
        #expect(library.records.count == 1)
        #expect(library.record(a)?.bookmarks.count == 1)
    }
    @Test func corruptLibraryIsNotOverwritten() throws {
        let (root, library) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let invalid = Data("broken".utf8); try invalid.write(to: library.fileURL)
        #expect(throws: (any Error).self) { _ = try MediaLibrary(fileURL: library.fileURL) }
        #expect(try Data(contentsOf: library.fileURL) == invalid)
    }
    @Test func bookmarkEditingAndDeletionArePerFile() throws {
        let (root, library) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let a = try library.visit(URL(fileURLWithPath: "/tmp/a.mp4"))
        let b = try library.visit(URL(fileURLWithPath: "/tmp/b.mp4"))
        try library.addBookmark(a, seconds: 100, title: "a")
        try library.addBookmark(b, seconds: 100, title: "b")
        let mark = try #require(library.record(a)?.bookmarks.first)
        try library.editBookmark(a, bookmark: mark.id, title: "edited", seconds: 42)
        #expect(library.record(a)?.bookmarks.first?.title == "edited")
        try library.removeBookmark(a, bookmark: mark.id)
        #expect(library.record(a)?.bookmarks.isEmpty == true)
        #expect(library.record(b)?.bookmarks.count == 1)
    }
    @Test func explicitRelocationPreservesIdentityAndBookmarkTimes() throws {
        let (root, library) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let id = try library.visit(URL(fileURLWithPath: "/tmp/unavailable-original.mp4"))
        try library.addBookmark(id, seconds: 33.5, title: "Saved moment")
        let replacement = root.appendingPathComponent("replacement.mp4")
        try Data("fixture".utf8).write(to: replacement)
        try library.relocate(id, to: replacement)
        #expect(library.record(id)?.bookmarks.first?.seconds == 33.5)
        #expect(library.resolve(id)?.resolvingSymlinksInPath() == replacement.resolvingSymlinksInPath())
        #expect(try library.visit(replacement) == id)
    }
    @Test func removingHistoryPreservesBookmarksAndDoesNotReturnOnPositionSave() throws {
        let (root, library) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let a = try library.visit(URL(fileURLWithPath: "/tmp/history-a.mp4"))
        let b = try library.visit(URL(fileURLWithPath: "/tmp/history-b.mp4"))
        try library.addBookmark(a, seconds: 42, title: "Keep this")
        try library.removeFromHistory(a)
        try library.updatePosition(a, seconds: 90, duration: 300)
        let reopened = try MediaLibrary(fileURL: library.fileURL)
        #expect(reopened.history.map(\.id) == [b])
        #expect(reopened.record(a)?.bookmarks.first?.seconds == 42)
        #expect(reopened.record(a)?.position == 90)
        #expect(try reopened.visit(URL(fileURLWithPath: "/tmp/history-a.mp4")) == a)
        #expect(reopened.history.count == 2)
    }
    @Test func emptyHistoryLeavesRecordsAvailableForQueueAndBookmarks() throws {
        let (root, library) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let a = try library.visit(URL(fileURLWithPath: "/tmp/empty-a.mp4"))
        let b = try library.visit(URL(fileURLWithPath: "/tmp/empty-b.mp4"))
        try library.addBookmark(a, seconds: 12, title: "Saved")
        try library.emptyHistory()
        let reopened = try MediaLibrary(fileURL: library.fileURL)
        #expect(reopened.history.isEmpty)
        #expect(reopened.record(a)?.bookmarks.count == 1)
        #expect(reopened.record(b) != nil)
    }
    @Test func removeAllBookmarksAffectsOnlySelectedFileAndSurvivesRelaunch() throws {
        let (root, library) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let a = try library.visit(URL(fileURLWithPath: "/tmp/marks-a.mp4"))
        let b = try library.visit(URL(fileURLWithPath: "/tmp/marks-b.mp4"))
        try library.addBookmark(a, seconds: 12, title: "A1")
        try library.addBookmark(a, seconds: 34, title: "A2")
        try library.addBookmark(b, seconds: 56, title: "B1")
        try library.updatePosition(a, seconds: 80, duration: 120)
        try library.removeAllBookmarks(a)
        let reopened = try MediaLibrary(fileURL: library.fileURL)
        #expect(reopened.record(a)?.bookmarks.isEmpty == true)
        #expect(reopened.record(a)?.position == 80)
        #expect(reopened.record(b)?.bookmarks.count == 1)
        #expect(reopened.history.count == 2)
    }
    @Test func oldLibrariesWithoutHistoryFlagRemainVisible() throws {
        let (root, library) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        _ = try library.visit(URL(fileURLWithPath: "/tmp/legacy.mp4"))
        var json = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: library.fileURL)) as? [[String: Any]])
        json[0].removeValue(forKey: "isInHistory")
        try JSONSerialization.data(withJSONObject: json).write(to: library.fileURL)
        let reopened = try MediaLibrary(fileURL: library.fileURL)
        #expect(reopened.history.count == 1)
    }
    @Test(arguments: [false, true], [false, true])
    func floatPreferenceAndPause(enabled: Bool, paused: Bool) {
        #expect(PlaybackPolicy.shouldFloat(enabled: enabled, loaded: true, paused: paused, buffering: false, ended: false, failed: false) == (enabled && !paused))
    }
    @Test(arguments: 0..<4)
    func inactivePlaybackNeverFloats(reason: Int) {
        #expect(!PlaybackPolicy.shouldFloat(enabled: true, loaded: reason != 0, paused: false, buffering: reason == 1, ended: reason == 2, failed: reason == 3))
    }
}

struct LibraryPersistenceTests {
    @Test func backgroundWritesFlushLatestSnapshotAndPreserveBookmarks() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = MediaLibrary(fileURL: root.appendingPathComponent("library.json"), records: [])
        library.enableBackgroundSaving()
        let id = try library.visit(root.appendingPathComponent("movie.mp4"))
        try library.addBookmark(id, seconds: 12, title: "Keep")
        for second in 1...50 { try library.updatePosition(id, seconds: Double(second), duration: 100) }
        try library.flush()
        let reopened = try MediaLibrary(fileURL: library.fileURL)
        #expect(reopened.record(id)?.position == 50)
        #expect(reopened.record(id)?.bookmarks.first?.title == "Keep")
    }
    @Test func backgroundWriteFailureCanBeRetriedWithoutLosingSnapshot() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data().write(to: root) // Parent is a file, so the first write must fail.
        let library = MediaLibrary(fileURL: root.appendingPathComponent("library.json"), records: [])
        library.enableBackgroundSaving()
        let id = try library.visit(URL(string: "https://example.com/movie.mp4")!)
        #expect(throws: (any Error).self) { try library.flush() }
        #expect(library.takeSaveError() != nil)
        try FileManager.default.removeItem(at: root)
        try library.flush()
        #expect(try MediaLibrary(fileURL: library.fileURL).record(id) != nil)
    }
    @Test func importMergePreservesEditsAndDoesNotDuplicateBookmarks() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = MediaLibrary(fileURL: root.appendingPathComponent("library.json"), records: [])
        let url = URL(string: "https://example.com/movie.mp4")!
        let id = try library.visit(url)
        try library.addBookmark(id, seconds: 12, title: "Edited locally")
        try library.updatePosition(id, seconds: 42, duration: 100)
        var incoming = MediaRecord(location: url)
        incoming.bookmarks = [MediaBookmark(seconds: 12, title: "Old title"), MediaBookmark(seconds: 20, title: "Imported")]
        try library.mergeImported([incoming]); try library.mergeImported([incoming])
        #expect(library.records.count == 1)
        #expect(library.record(id)?.position == 42)
        #expect(library.record(id)?.bookmarks.map(\.title) == ["Edited locally", "Imported"])
    }
}
