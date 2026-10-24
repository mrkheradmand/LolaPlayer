import Foundation
import Testing
@testable import PlayerCore

struct LibrarySortingTests {
    @Test func sortsDatesPositionsAndKeepsStableTies() {
        var a = MediaRecord(location: URL(fileURLWithPath: "/tmp/a.mp4"))
        var b = MediaRecord(location: URL(fileURLWithPath: "/tmp/b.mp4"))
        a.addedAt = Date(timeIntervalSince1970: 10); b.addedAt = Date(timeIntervalSince1970: 20)
        a.lastPlayedAt = Date(timeIntervalSince1970: 30); b.lastPlayedAt = Date(timeIntervalSince1970: 25)
        a.position = 10; b.position = 20
        let records = [a, b]
        #expect(LibrarySorting.sorted(records, by: .dateAdded, ascending: false).map(\.id) == [b.id, a.id])
        #expect(LibrarySorting.sorted(records, by: .lastPlayed, ascending: false).map(\.id) == [a.id, b.id])
        #expect(LibrarySorting.sorted(records, by: .datePlayed, ascending: true).map(\.id) == [b.id, a.id])
        #expect(LibrarySorting.sorted(records, by: .watchedTill, ascending: false).map(\.id) == [b.id, a.id])
        a.hasFinishedPlayback = true; a.duration = 100
        #expect(LibrarySorting.sorted([a, b], by: .watchedTill, ascending: false).first?.id == a.id)
        a.position = 20; a.hasFinishedPlayback = false
        #expect(LibrarySorting.sorted([a, b], by: .watchedTill, ascending: true).map(\.id) == [a.id, b.id])
        #expect(LibrarySorting.sorted(records, by: .playlistOrder, ascending: false).map(\.id) == [a.id, b.id])
    }
    @Test func bookmarkDateSortingAndLegacyFallback() {
        var a = MediaRecord(location: URL(fileURLWithPath: "/tmp/a.mp4"))
        var b = MediaRecord(location: URL(fileURLWithPath: "/tmp/b.mp4"))
        a.addedAt = Date(timeIntervalSince1970: 10); b.addedAt = Date(timeIntervalSince1970: 20)
        var mark = MediaBookmark(seconds: 2, title: "New")
        mark.addedAt = Date(timeIntervalSince1970: 30); a.bookmarks = [mark]
        #expect(LibrarySorting.sorted([a, b], by: .dateAdded, ascending: false, bookmarkDates: true).first?.id == a.id)
        a.addedAt = nil; a.lastOpened = Date(timeIntervalSince1970: 5)
        a.bookmarks[0].addedAt = nil
        #expect(LibrarySorting.sorted([a, b], by: .dateAdded, ascending: true, bookmarkDates: true).first?.id == a.id)
    }
    @Test func folderFilterExcludesSubfoldersAndRemoteMedia() {
        let a = MediaRecord(location: URL(fileURLWithPath: "/tmp/series/a.mp4"))
        let b = MediaRecord(location: URL(fileURLWithPath: "/tmp/series/b.mp4"))
        let nested = MediaRecord(location: URL(fileURLWithPath: "/tmp/series/sub/c.mp4"))
        let remote = MediaRecord(location: URL(string: "https://example.com/a.mp4")!)
        #expect(LibrarySorting.inCurrentFolder([a, b, nested, remote], current: a).map(\.id) == [a.id, b.id])
        #expect(LibrarySorting.inCurrentFolder([a], current: remote).isEmpty)
        #expect(LibrarySorting.inCurrentFolder([a], current: nil).isEmpty)
    }
    @Test func addedDatesAndLastPlayedSurviveReopening() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = MediaLibrary(fileURL: root.appendingPathComponent("library.json"), records: [])
        let url = root.appendingPathComponent("a.mp4")
        let id = try library.visit(url)
        let added = library.record(id)?.addedAt
        try library.markPlayed(id)
        _ = try library.visit(url)
        try library.addBookmark(id, seconds: 1, title: "One")
        let reopened = try MediaLibrary(fileURL: library.fileURL)
        #expect(reopened.record(id)?.addedAt == added)
        #expect(reopened.record(id)?.lastPlayedAt != nil)
        #expect(reopened.record(id)?.bookmarks.first?.addedAt != nil)
    }
}
