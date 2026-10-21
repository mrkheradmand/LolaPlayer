import AppKit
import Foundation
import PlayerCore

/// Invoked only by --smoke-test; exercises the real bundled decoder and NSWindow.
@MainActor enum SmokeTest {
    struct Failure: Error { let message: String }
    static func run(model: PlayerModel, root: URL) {
        Task { @MainActor in
            var checks: [String] = []
            var skipped: [String] = []
            let originalFloat = model.floatEnabled
            let originalAutoplay = model.autoplay
            let originalPrompt = model.promptForBookmark
            func check(_ condition: Bool, _ name: String) throws {
                guard condition else { throw Failure(message: name) }; checks.append(name)
            }
            @MainActor func waitFor(_ condition: @MainActor () -> Bool) async throws {
                for _ in 0..<100 {
                    if condition() { return }
                    if let error = model.error { throw Failure(message: error) }
                    try await Task.sleep(for: .milliseconds(100))
                }
                throw Failure(message: "Timed out waiting for playback state")
            }
            var failure: String?
            do {
                if let delegate = NSApp.delegate as? AppDelegate, let window = model.window {
                    try await waitFor { window.isKeyWindow }
                    let originalSidebar = model.sidebar
                    let frame = window.frame
                    @MainActor func key(_ value: String, modifiers: NSEvent.ModifierFlags = []) -> NSEvent {
                        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers,
                            timestamp: 0, windowNumber: window.windowNumber, context: nil,
                            characters: value, charactersIgnoringModifiers: value, isARepeat: false,
                            keyCode: value == "1" ? 18 : 19)!
                    }
                    window.makeFirstResponder(nil)
                    model.sidebar = true
                    try check(delegate.handleViewShortcut(key("2")) && model.mediaOnly,
                        "2 enables media-only mode")
                    try check(window.titleVisibility == .hidden && window.styleMask.contains(.fullSizeContentView)
                        && window.standardWindowButton(.closeButton)?.isHidden == true && window.frame == frame,
                        "Media-only mode removes title chrome without resizing the window")
                    try check(delegate.handleViewShortcut(key("1")) && !model.mediaOnly && model.sidebar
                        && window.titleVisibility == .visible && !window.styleMask.contains(.fullSizeContentView)
                        && window.standardWindowButton(.closeButton)?.isHidden == false,
                        "1 restores title chrome and preserves the library preference")
                    try check(!delegate.handleViewShortcut(key("2", modifiers: .command)) && !model.mediaOnly,
                        "Modified number shortcuts do not change the view")
                    let field = NSTextField(frame: NSRect(x: 10, y: 10, width: 100, height: 24))
                    window.contentView?.addSubview(field)
                    window.makeFirstResponder(field)
                    try check(!delegate.handleViewShortcut(key("2")) && !model.mediaOnly,
                        "Typing numbers in a text field does not change the view")
                    window.makeFirstResponder(nil)
                    field.removeFromSuperview()
                    model.sidebar = originalSidebar
                }
                model.autoplay = true; model.floatEnabled = true; model.promptForBookmark = false
                model.open([root.appendingPathComponent("first.mp4")])
                try await waitFor { model.loaded && model.position > 0.2 && !model.paused }
                let a = model.currentID!
                try check(model.window?.level == .floating, "Playing MP4 floats the actual window")
                model.setPaused(true)
                try await Task.sleep(for: .milliseconds(300))
                try check(model.paused && model.window?.level == .normal && model.floatEnabled, "Pause suspends floating and preserves preference")
                model.setPaused(false)
                try await waitFor { !model.paused && model.window?.level == .floating }
                try check(model.floating, "Resume restores floating")
                model.seek(3)
                try await waitFor { model.position >= 3 && model.position < 4 }
                model.addBookmark()
                let bookmarkA = model.library.record(a)!.bookmarks.last!
                model.open([root.appendingPathComponent("second.mkv")])
                try await waitFor { model.loaded && model.currentID != a && model.position > 0.2 }
                let b = model.currentID!
                try check(model.duration > 10, "MKV with Opus audio decodes through bundled libmpv")
                model.seek(5)
                try await waitFor { model.position >= 5 && model.position < 6 }
                model.addBookmark()
                try check(model.library.record(a)?.bookmarks.count == 1 && model.library.record(b)?.bookmarks.count == 1, "Both files retain their independent bookmarks")
                model.play(a, at: bookmarkA.seconds)
                try await waitFor { model.loaded && model.currentID == a && model.position >= 3 && model.position < 4.5 }
                try check(true, "Selecting another file's bookmark loads it and seeks to the saved second")
                model.persistPosition()
                let reopened = try MediaLibrary(fileURL: model.library.fileURL)
                try check(reopened.record(a)?.bookmarks.count == 1 && reopened.record(b)?.bookmarks.count == 1, "Bookmarks persist after reconstructing library from disk")
                model.floatEnabled = false
                try check(model.window?.level == .normal, "Disabling preference restores normal level during playback")
                model.floatEnabled = true; model.queue = []; model.seek(model.duration - 0.3)
                try await waitFor { model.ended }
                try check(model.window?.level == .normal && model.floatEnabled, "End of file suspends floating")
                model.stop()
                try check(model.window?.level == .normal, "Stop keeps normal window level")
                let manifest = root.appendingPathComponent("hls/index.m3u8")
                if FileManager.default.fileExists(atPath: manifest.path) {
                    model.open([manifest])
                    try await waitFor { model.loaded && model.current?.location.path == manifest.path && model.duration > 2 }
                    try check(model.queue.compactMap { model.library.record($0)?.location.pathExtension }.allSatisfy { $0 != "ts" }, "HLS opens as one manifest without queueing segments")
                    model.stop()
                }
                let cycle = root.appendingPathComponent("cycle.m3u")
                try "#EXTM3U\ncycle.m3u\n".write(to: cycle, atomically: true, encoding: .utf8)
                model.open([cycle])
                try check(model.error?.contains("cycle") == true, "Recursive playlists report an error without overflowing the stack")
                model.error = nil
                let score = root.appendingPathComponent("score.mid")
                if FileManager.default.fileExists(atPath: score.path) {
                    model.changeVolume(0)
                    model.open([score])
                    if model.failed, model.error?.contains("synthesizer is unavailable") == true {
                        skipped.append("MIDI audio component unavailable in this environment")
                        model.error = nil
                    } else {
                        try await waitFor { model.loaded && model.position > 0.2 }
                        model.setPaused(true)
                        let position = model.position
                        try await Task.sleep(for: .milliseconds(300))
                        try check(abs(model.position - position) < 0.1 && model.window?.level == .normal, "MIDI pause preserves position and suspends floating")
                        model.seek(0.5); model.addBookmark()
                        try check(model.current?.bookmarks.last?.seconds == 0.5, "MIDI bookmarks use the same persistent library")
                        model.setPaused(false)
                        try await waitFor { model.position > 0.7 }
                        try check(true, "MIDI resumes and seeks through the native synthesizer")
                        model.stop()
                    }
                }
            } catch let error as Failure { failure = error.message }
            catch { failure = error.localizedDescription }
            model.floatEnabled = originalFloat; model.autoplay = originalAutoplay
            model.promptForBookmark = originalPrompt
            let report: [String: Any] = ["passed": failure == nil, "checks": checks, "skipped": skipped, "failure": failure ?? NSNull()]
            if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
                try? data.write(to: root.appendingPathComponent("smoke-result.json"), options: .atomic)
            }
            model.shutdown(); NSApp.terminate(nil)
        }
    }
}
