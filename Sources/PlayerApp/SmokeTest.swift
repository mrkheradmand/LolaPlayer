import AppKit
import Foundation
import PlayerCore
import SwiftUI

private final class DragProbeView: PlayerMouseView {
    var dragCount = 0
    override func dragWindow(with event: NSEvent) { dragCount += 1 }
}

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
            let originalUpdateAvailability = model.updateAvailability
            let originalUpdates = UserDefaults.standard.object(forKey: "automaticUpdateChecks")
            let originalDismissedUpdate = UserDefaults.standard.object(forKey: "dismissedUpdateVersion")
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
                    try await Task.sleep(for: .milliseconds(300))
                    NSApp.activate(ignoringOtherApps: true)
                    window.makeKeyAndOrderFront(nil)
                    for _ in 0..<10 {
                        if window.isKeyWindow { break }
                        try await Task.sleep(for: .milliseconds(100))
                    }
                    let canDispatchKeys = window.isKeyWindow
                    if !canDispatchKeys { skipped.append("Foreground keyboard dispatch unavailable: macOS kept the test app inactive; window-mode actions are tested directly") }
                    let originalSidebar = model.sidebar
                    let contentTop = window.convertToScreen(window.contentLayoutRect).maxY
                    @MainActor func key(_ value: String, modifiers: NSEvent.ModifierFlags = []) -> NSEvent {
                        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers,
                            timestamp: 0, windowNumber: window.windowNumber, context: nil,
                            characters: value, charactersIgnoringModifiers: value, isARepeat: false,
                            keyCode: value == "1" ? 18 : 19)!
                    }
                    @MainActor func selectView(_ value: String) -> Bool {
                        if canDispatchKeys { return delegate.handleViewShortcut(key(value)) }
                        model.setMediaOnly(value == "2")
                        return true
                    }
                    window.makeFirstResponder(nil)
                    model.sidebar = true
                    try check(selectView("2") && model.mediaOnly,
                        "Media-only action (2) enables compact mode")
                    try check(window.titleVisibility == .hidden && window.styleMask.contains(.fullSizeContentView)
                        && window.standardWindowButton(.closeButton)?.isHidden == true && abs(window.frame.maxY - contentTop) < 1,
                        "Media-only mode hides title chrome without a video aspect to fit")
                    try check(selectView("1") && !model.mediaOnly && model.sidebar
                        && window.titleVisibility == .visible && !window.styleMask.contains(.fullSizeContentView)
                        && window.standardWindowButton(.closeButton)?.isHidden == false,
                        "1 restores title chrome and preserves the library preference")
                    if canDispatchKeys {
                    try check(!delegate.handleViewShortcut(key("2", modifiers: .command)) && !model.mediaOnly,
                        "Modified number shortcuts do not change the view")
                    let field = NSTextField(frame: NSRect(x: 10, y: 10, width: 100, height: 24))
                    window.contentView?.addSubview(field)
                    window.makeFirstResponder(field)
                    try check(!delegate.handleViewShortcut(key("2")) && !model.mediaOnly,
                        "Typing numbers in a text field does not change the view")
                    window.makeFirstResponder(nil)
                    field.removeFromSuperview()
                    }
                    let surface = DragProbeView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
                    var clicks = 0, doubleClicks = 0
                    surface.click = { clicks += 1 }; surface.doubleClick = { doubleClicks += 1 }
                    window.contentView?.addSubview(surface)
                    @MainActor func mouse(_ type: NSEvent.EventType, x: CGFloat, count: Int = 1) -> NSEvent {
                        NSEvent.mouseEvent(with: type, location: NSPoint(x: x, y: 20), modifierFlags: [],
                            timestamp: 0, windowNumber: window.windowNumber, context: nil,
                            eventNumber: 1, clickCount: count, pressure: 1)!
                    }
                    surface.mouseDown(with: mouse(.leftMouseDown, x: 20))
                    surface.mouseDragged(with: mouse(.leftMouseDragged, x: 22))
                    try check(surface.dragCount == 0, "Small pointer movement does not start a window drag")
                    surface.mouseDragged(with: mouse(.leftMouseDragged, x: 30))
                    surface.mouseUp(with: mouse(.leftMouseUp, x: 30))
                    try await Task.sleep(for: .seconds(NSEvent.doubleClickInterval + 0.1))
                    try check(surface.dragCount == 1 && clicks == 0, "Dragging the player starts a window drag without a playback click")
                    surface.mouseDown(with: mouse(.leftMouseDown, x: 20))
                    surface.mouseUp(with: mouse(.leftMouseUp, x: 20))
                    try await Task.sleep(for: .seconds(NSEvent.doubleClickInterval + 0.1))
                    try check(clicks == 1, "A short player click still invokes play/pause")
                    surface.mouseDown(with: mouse(.leftMouseDown, x: 20))
                    surface.mouseUp(with: mouse(.leftMouseUp, x: 20))
                    surface.mouseDown(with: mouse(.leftMouseDown, x: 20, count: 2))
                    surface.mouseUp(with: mouse(.leftMouseUp, x: 20, count: 2))
                    try await Task.sleep(for: .seconds(NSEvent.doubleClickInterval + 0.1))
                    try check(clicks == 1 && doubleClicks == 1, "Double-click invokes full screen without a playback click")
                    surface.cancelClick(); window.makeFirstResponder(nil); surface.removeFromSuperview()
                    model.sidebar = originalSidebar
                }
                model.automaticUpdateChecks = true
                try check(model.automaticUpdateTask == nil, "Smoke mode suppresses automatic update networking")
                let releaseData = Data(#"{"tag_name":"v999.0.0","draft":false,"prerelease":false}"#.utf8)
                model.availableUpdate = try UpdateChecker.update(from: releaseData, statusCode: 200, currentVersion: "1.0.0")
                if let release = model.availableUpdate {
                    let about = AboutView(model: model)
                    model.updateAvailability = .current
                    try check(about.versionLine == "\(about.versionText) Latest Version",
                        "About shows Latest Version beside the version after a successful current check")
                    model.updateAvailability = .available(release)
                    model.dismissUpdate()
                    try check(about.versionLine == "\(about.versionText) New version available!"
                        && model.updateAvailability == .available(release),
                        "About retains the newer-release status after its banner is dismissed")
                    model.updateAvailability = .failed
                    try check(!about.versionLine.contains("Latest Version") && about.versionLine.contains("Couldn’t check"),
                        "An update failure is not labeled Latest Version in About")
                    model.updateAvailability = .checking
                    try check(about.versionLine.contains("Checking for updates"),
                        "About reflects a pending update check")
                    let controller = AboutWindowController(model: model)
                    controller.showWindow(nil)
                    try check((!NSApp.isActive || controller.window?.isVisible == true)
                        && controller.window?.contentView is NSHostingView<AboutView>,
                        "The About window hosts the live status view")
                    controller.close()
                    for page in SettingsPage.allCases {
                        let host = NSHostingView(rootView: SettingsView(model: model, initialPage: page))
                        host.frame = NSRect(x: 0, y: 0, width: 720, height: 530)
                        host.layoutSubtreeIfNeeded()
                        try check(host.fittingSize.width >= 700 && host.fittingSize.height > 0, "Settings \(page.rawValue) page lays out at its intended size")
                    }
                    try check(NSApp.mainMenu?.items.first?.submenu?.items.contains(where: { $0.title == "Check for Updates…" }) == false,
                        "Manual update checking is accessed through About rather than Settings or a duplicate menu item"); model.window?.makeKeyAndOrderFront(nil)
                    model.updateAvailability = .notChecked
                }
                model.dismissUpdate()
                try check(model.availableUpdate == nil && UserDefaults.standard.string(forKey: "dismissedUpdateVersion") == "999.0.0",
                    "Dismissing an update remembers its version")
                model.availableUpdate = try UpdateChecker.update(from: releaseData, statusCode: 200, currentVersion: "1.0.0")
                model.automaticUpdateChecks = false
                try check(UserDefaults.standard.bool(forKey: "automaticUpdateChecks") == false
                    && model.availableUpdate == nil && model.automaticUpdateTask == nil,
                    "Turning off update checks saves the preference and clears the notification")
                model.autoplay = true; model.floatEnabled = true; model.promptForBookmark = false
                model.open([root.appendingPathComponent("first.mp4")])
                try await waitFor { model.loaded && model.position > 0.2 && !model.paused }
                let a = model.currentID!
                try check(model.window?.level == .floating, "Playing MP4 floats the actual window")
                @MainActor func mediaMouseView(in view: NSView) -> PlayerMouseView? {
                    if let surface = view as? PlayerMouseView { return surface }
                    for child in view.subviews { if let surface = mediaMouseView(in: child) { return surface } }
                    return nil
                }
                if let content = model.window?.contentView, let surface = mediaMouseView(in: content) {
                    let point = surface.convert(NSPoint(x: surface.bounds.midX, y: surface.bounds.midY), to: content)
                    try check(content.hitTest(point) === surface, "The visible media area routes mouse events to the player drag/click handler")
                } else { throw Failure(message: "Missing native player mouse surface") }

                model.setPaused(true)
                try await Task.sleep(for: .milliseconds(300))
                try check(model.paused && model.window?.level == .normal && model.floatEnabled, "Pause suspends floating and preserves preference")
                if let library = model.runtimeLibraryPath {
                    let decoder = ThumbnailDecoder()
                    let pausedPosition = model.position
                    let first = await decoder.frame(url: root.appendingPathComponent("first.mp4"), seconds: 2, library: library)
                    try check(first != nil && first!.width <= 320 && first!.height <= 180
                        && abs(first!.time - 2) < 0.3 && first!.pixels.count == first!.stride * first!.height,
                        "MP4 thumbnail contains bounded in-memory pixels at the requested time")
                    let second = await decoder.frame(url: root.appendingPathComponent("first.mp4"), seconds: 6, library: library)
                    try check(second != nil && abs(second!.time - 6) < 0.3,
                        "A second thumbnail decodes the new hovered time")
                    let mkv = await decoder.frame(url: root.appendingPathComponent("second.mkv"), seconds: 4, library: library)
                    try check(mkv != nil && abs(mkv!.time - 4) < 0.3, "MKV thumbnails use the bundled decoder")
                    try check(model.currentID == a && model.paused && abs(model.position - pausedPosition) < 0.2,
                        "Thumbnail decoding does not change the main file, pause state, or playback position")
                }
                model.timelinePreview.hoverX = 100
                try await waitFor { model.timelinePreview.image != nil }
                try check(model.timelinePreview.represented != nil && model.paused,
                    "The normal progress bar loads its hover thumbnail without changing playback")
                @MainActor func videoTop() -> CGFloat {
                    guard let window = model.window, let view = model.engine else { return .nan }
                    return window.convertToScreen(view.convert(view.bounds, to: nil)).maxY
                }
                let originalVideoTop = videoTop()
                let normalSize = model.window!.frame.size
                let originalFrame = model.window!.frame
                let originalTop = model.window!.convertToScreen(model.window!.contentLayoutRect).maxY
                let originalMinimum = model.window!.minSize
                model.setMediaOnly(true)
                try check(model.mediaAspectRatio > 0 && abs(model.window!.frame.height
                    - (model.window!.frame.width / model.mediaAspectRatio + MediaWindowLayout.progressHeight)) < 1
                    && abs(model.window!.frame.maxY - originalTop) < 1,
                    "2 fits window height to the video plus progress strip without moving the media top")
                let fittedSize = model.window!.frame.size
                model.setMediaOnly(true)
                try check(model.window!.frame.size == fittedSize, "Repeated 2 does not overwrite the saved interface size")
                try await Task.sleep(for: .milliseconds(200))
                try check(abs(videoTop() - originalVideoTop) < 1, "Hiding the title bar leaves the actual video surface at the same screen height")
                model.timelinePreview.hoverX = 100
                try await waitFor { model.timelinePreview.image != nil }
                try check(model.timelinePreview.represented != nil && model.paused,
                    "The media-only progress bar also loads hover thumbnails")
                model.setMediaOnly(false); model.timelinePreview.hoverX = nil
                try check(model.window!.frame.size == normalSize && model.window!.minSize == originalMinimum,
                    "1 restores the previous window dimensions and minimum size")
                try check(model.window!.frame == originalFrame, "Restoring title chrome returns to the original screen position")
                for _ in 0..<12 {
                    model.setMediaOnly(true)
                    try await Task.sleep(for: .milliseconds(30))
                    guard abs(model.window!.frame.maxY - originalTop) < 1 else { throw Failure(message: "Compact mode moved the media top") }
                    model.setMediaOnly(false)
                    try await Task.sleep(for: .milliseconds(30))
                }
                try check(model.window!.frame == originalFrame, "Repeated 1/2 toggles do not make the window drift upward")
                try check(abs(videoTop() - originalVideoTop) < 1, "Restoring the title bar leaves the actual video surface at its original height")
                model.scrubPosition = 4; model.scrubbing = true
                model.timelinePreview.request(model.thumbnailRequest(time: 4))
                try await waitFor { !model.timelinePreview.loading && model.timelinePreview.image != nil }
                model.timelinePreview.request(nil)
                model.timelinePreview.request(model.thumbnailRequest(time: 4))
                try check(model.timelinePreview.image != nil && !model.timelinePreview.loading,
                    "A cached thumbnail displays synchronously without a hover delay")
                model.timelinePreview.hoverX = nil; model.scrubPosition = 6; model.scrubbing = true
                try await waitFor { model.timelinePreview.represented?.seconds == 6 && model.timelinePreview.image != nil && !model.timelinePreview.loading }
                try check(model.paused, "Dragging the playhead shows its thumbnail even when there is no hover event")
                model.scrubbing = false; model.timelinePreview.request(nil)
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
                model.floatEnabled = true; model.queue = [a, b]; model.repeatMode = .off
                for shuffled in [false, true] {
                    model.shuffle = shuffled
                    model.play(a, at: 0)
                    try await waitFor { model.loaded && model.currentID == a && model.duration > 10 }
                    model.seek(model.duration - 0.3)
                    try await waitFor { model.ended || model.currentID != a }
                    try await Task.sleep(for: .milliseconds(400))
                    try check(model.currentID == a && model.ended && model.paused
                        && model.library.record(a)?.position == 0,
                        "Repeat Off stops at EOF with another file queued (shuffle=\(shuffled))")
                }
                try check(model.window?.level == .normal && model.floatEnabled, "End of file suspends floating")
                model.shuffle = false
                model.adjacent(1)
                try await waitFor { model.loaded && model.currentID == b && !model.paused }
                try check(true, "Manual Next still plays the next queued file with Repeat Off")
                model.repeatMode = .track
                model.seek(model.duration - 0.3)
                try await waitFor { model.currentID == b && model.position < 2 && !model.ended && !model.paused }
                try check(true, "One File restarts the current media at EOF")
                for mode in [RepeatMode.folder, .library] {
                    model.repeatMode = mode
                    model.seek(model.duration - 0.3)
                    try await waitFor { model.loaded && model.currentID == a && !model.paused }
                    try check(true, "\(mode.rawValue) wraps from the last media file to the first at EOF")
                    model.play(b, at: 0)
                    try await waitFor { model.loaded && model.currentID == b && model.duration > 10 }
                }
                model.repeatMode = .off
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
            model.automaticUpdateChecks = originalUpdates as? Bool ?? true
            model.updateAvailability = originalUpdateAvailability
            UserDefaults.standard.set(originalUpdates, forKey: "automaticUpdateChecks")
            UserDefaults.standard.set(originalDismissedUpdate, forKey: "dismissedUpdateVersion")
            let report: [String: Any] = ["passed": failure == nil, "checks": checks, "skipped": skipped, "failure": failure ?? NSNull()]
            if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
                try? data.write(to: root.appendingPathComponent("smoke-result.json"), options: .atomic)
            }
            model.shutdown(); NSApp.terminate(nil)
        }
    }
}
