import AppKit
import Foundation
import PlayerCore

/// Invoked only by --smoke-test; exercises the real bundled decoder and NSWindow.
@MainActor enum SmokeTest {
    struct Failure: Error { let message: String }
    static func run(model: PlayerModel, root: URL) {
        Task { @MainActor in
            var checks: [String] = []
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
            } catch let error as Failure { failure = error.message }
            catch { failure = error.localizedDescription }
            model.floatEnabled = originalFloat; model.autoplay = originalAutoplay
            model.promptForBookmark = originalPrompt
            let report: [String: Any] = ["passed": failure == nil, "checks": checks, "failure": failure ?? NSNull()]
            if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
                try? data.write(to: root.appendingPathComponent("smoke-result.json"), options: .atomic)
            }
            model.shutdown(); NSApp.terminate(nil)
        }
    }
}
