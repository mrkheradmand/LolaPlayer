import Foundation
import Testing
@testable import PlayerCore

struct PlaybackOrderTests {
    @Test func repeatButtonCyclesThroughAllFourModes() {
        var mode = RepeatMode.off
        var visited: [RepeatMode] = []
        for _ in 0..<4 { visited.append(mode); mode = mode.next }
        #expect(visited == [.off, .track, .folder, .library])
        #expect(mode == .off)
    }

    @Test(arguments: [RepeatMode.off, .track, .folder, .library])
    func sequenceBoundariesRespectRepeatScope(mode: RepeatMode) {
        let a = UUID(), b = UUID(), c = UUID()
        let ids = [a, b, c]
        #expect(PlaybackOrder.destination(in: ids, current: a, offset: 1, wrap: mode.wraps) == b)
        #expect(PlaybackOrder.destination(in: ids, current: c, offset: 1, wrap: mode.wraps) == (mode.wraps ? a : nil))
        #expect(PlaybackOrder.destination(in: ids, current: a, offset: -1, wrap: mode.wraps) == (mode.wraps ? c : nil))
    }

    @Test func emptySingleAndMissingCurrentSelectionsAreHandled() {
        let a = UUID(), b = UUID()
        #expect(PlaybackOrder.destination(in: [], current: a, offset: 1, wrap: true) == nil)
        #expect(PlaybackOrder.destination(in: [a], current: a, offset: 1, wrap: true) == a)
        #expect(PlaybackOrder.destination(in: [a], current: a, offset: 1, wrap: false) == nil)
        #expect(PlaybackOrder.destination(in: [a, b], current: nil, offset: 1, wrap: false) == a)
        #expect(PlaybackOrder.destination(in: [a, b], current: UUID(), offset: -1, wrap: false) == b)
    }

    @Test func wholeLibraryOrderIsNaturalAndIndependentOfHistoryRecency() {
        var ten = MediaRecord(location: URL(fileURLWithPath: "/tmp/episode10.mp4"))
        var two = MediaRecord(location: URL(fileURLWithPath: "/tmp/episode2.mp4"))
        ten.lastOpened = Date.distantPast; two.lastOpened = Date.distantFuture
        ten.isInHistory = false
        #expect(PlaybackOrder.library([ten, two]) == [two.id, ten.id])
        ten.lastOpened = Date.distantFuture; two.lastOpened = Date.distantPast
        #expect(PlaybackOrder.library([two, ten]) == [two.id, ten.id])
    }

    @Test func folderDiscoveryFindsUnopenedMediaWithoutChangingHistory() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let two = root.appendingPathComponent("episode2.mp4"), ten = root.appendingPathComponent("episode10.mkv")
        for url in [two, ten, root.appendingPathComponent("cover.jpg"), root.appendingPathComponent(".hidden.mp4")] { try Data("fixture".utf8).write(to: url) }
        try FileManager.default.createDirectory(at: root.appendingPathComponent("subfolder.mp4"), withIntermediateDirectories: true)
        let library = try MediaLibrary(fileURL: root.appendingPathComponent("library.json"))
        let current = try library.visit(two)
        try library.addBookmark(current, seconds: 4, title: "Saved")
        let urls = try MediaFormats.files(in: root)
        #expect(urls.map(\.lastPathComponent) == ["episode2.mp4", "episode10.mkv"])
        let ids = try library.register(urls)
        #expect(ids.first == current)
        #expect(library.history.map(\.id) == [current])
        #expect(library.record(current)?.bookmarks.count == 1)
        #expect(try library.register(urls) == ids)
        let reopened = try MediaLibrary(fileURL: library.fileURL)
        #expect(reopened.records.count == 2)
        #expect(reopened.history.count == 1)
    }
}
