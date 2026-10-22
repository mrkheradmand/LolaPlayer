import Foundation
import Testing
@testable import PlayerCore

struct MediaInputTests {
    @Test func hlsSegmentsAndMasterVariantsStayOneMediaInput() {
        #expect(MediaInput.isHLS("\u{FEFF}#EXTM3U\n#EXT-X-TARGETDURATION:6\n#EXTINF:6,\npart.ts\n#EXT-X-ENDLIST"))
        #expect(MediaInput.isHLS("#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=64000\nlow/index.m3u8"))
        #expect(!MediaInput.isHLS("#EXTM3U\n#EXTINF:90,Song\nsong.flac"))
    }

    @Test func playlistsHandleWhitespaceAbsolutePathsAndRemoteURLs() {
        let base = URL(fileURLWithPath: "/music/lists/favorites.m3u8")
        let inputs = MediaInput.playlistItems("\u{FEFF}#EXTM3U\r\n  ../Song 1.flac \r\n/Volumes/Audio/song.wav\nhttps://example.org/a.mp3?x=1\nfile:///music/a%20b.mp3\n#comment\n\njavascript:bad", relativeTo: base)
        #expect(inputs.count == 4)
        #expect(inputs[0].path == "/music/Song 1.flac")
        #expect(inputs[1].path == "/Volumes/Audio/song.wav")
        #expect(inputs[2].absoluteString == "https://example.org/a.mp3?x=1")
        #expect(inputs[3].path == "/music/a b.mp3")
    }

    @Test func discRecordsKeepBookmarksAndTypeAcrossRelaunch() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let disc = root.appendingPathComponent("Movie")
        let video = disc.appendingPathComponent("VIDEO_TS")
        try FileManager.default.createDirectory(at: video, withIntermediateDirectories: true)
        try Data().write(to: video.appendingPathComponent("VIDEO_TS.IFO"))
        #expect(MediaInput.discFolder(disc)?.1 == .dvd)
        #expect(MediaInput.discFolder(video)?.0.path == disc.path)
        let library = try MediaLibrary(fileURL: root.appendingPathComponent("library.json"))
        let id = try library.visitDisc(disc, kind: .dvd)
        try library.setDiscTitle(id, title: 2)
        try library.addBookmark(id, seconds: 12, title: "Scene")
        try library.setDiscTitle(id, title: 3)
        let reopened = try MediaLibrary(fileURL: library.fileURL)
        #expect(reopened.record(id)?.discKind == .dvd)
        #expect(reopened.record(id)?.bookmarks.first?.seconds == 12)
        #expect(reopened.record(id)?.bookmarks.first?.discTitle == 2)
        #expect(reopened.record(id)?.discTitle == 3)
        #expect(reopened.resolve(id)?.resolvingSymlinksInPath().path == disc.resolvingSymlinksInPath().path)
    }

    @Test func expandedFolderImportUsesCaseInsensitiveExtensionsAndExcludesSubtitles() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        for name in ["camera.MTS", "music.APE", "score.MID", "film.MXF", "notes.srt", "cover.jpg"] {
            try Data().write(to: root.appendingPathComponent(name))
        }
        #expect(try MediaFormats.files(in: root).map(\.lastPathComponent) == ["camera.MTS", "film.MXF", "music.APE", "score.MID"])
    }
}

struct PlaylistDropTests {
    @Test func recursivelyFindsMediaAndDeduplicatesOverlappingDrops() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let nested = root.appendingPathComponent("Season/Subfolder")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        for name in ["first.MP4", "notes.txt", ".hidden.mp3"] { try Data().write(to: root.appendingPathComponent(name)) }
        for name in ["episode2.mkv", "episode10.mkv", "song.FLAC", "subtitles.srt"] { try Data().write(to: nested.appendingPathComponent(name)) }
        let files = try MediaInput.playlistDropFiles([root, nested, root.appendingPathComponent("first.MP4")])
        #expect(files.map(\.lastPathComponent) == ["first.MP4", "episode2.mkv", "episode10.mkv", "song.FLAC"])
        #expect(try MediaInput.playlistDropFiles([root.appendingPathComponent("notes.txt")]).isEmpty)
        #expect(try MediaInput.playlistDropFiles([URL(string: "https://example.com/movie.mp4")!]).isEmpty)
    }
    @Test func rejectsMissingInputsAndDoesNotFollowDirectorySymlinks() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data().write(to: root.appendingPathComponent("clip.mp4"))
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("loop"), withDestinationURL: root)
        #expect(try MediaInput.playlistDropFiles([root]).count == 1)
        #expect(throws: (any Error).self) { try MediaInput.playlistDropFiles([root.appendingPathComponent("missing.mp4")]) }
    }
}
