import Observation
import AppKit
import Foundation
import CoreGraphics
import PlayerCore
import SwiftUI

private final class DragProbeView: PlayerMouseView {
    var dragCount = 0
    override func dragWindow(with event: NSEvent) { dragCount += 1 }
}

/// Invoked only by --smoke-test; exercises the real bundled decoder and NSWindow.
@MainActor enum SmokeTest {
    struct Failure: Error { let message: String }
    private static func runPlaylistReorderOnly(model: PlayerModel, root: URL) {
        Task { @MainActor in
            var checks: [String] = []
            var failure: String?
            func check(_ valid: Bool, _ name: String) throws {
                guard valid else { throw Failure(message: name) }; checks.append(name)
            }
            do {
                let ids = (0..<4).map { _ in UUID() }
                model.queue = ids
                let current = model.currentID
                let speed = model.speed
                let pasteboard = NSPasteboard.withUniqueName()
                defer { pasteboard.releaseGlobally() }
                pasteboard.setString(ids[3].uuidString, forType: NSPasteboard.PasteboardType(PlaylistReorderDrop.typeIdentifier))
                let surface = PlaylistDragSurfaceView()
                surface.model = model
                try check(surface.registeredDraggedTypes.contains(NSPasteboard.PasteboardType(PlaylistReorderDrop.typeIdentifier)),
                    "Native card registers the actual pasteboard drag type")
                surface.showInsertion(before: ids[1])
                try check(model.playlistReorderTargeted && model.playlistDropBefore == ids[1],
                    "Native drag hover activates the insertion indicator")
                try check(surface.acceptDrop(pasteboard, before: ids[1]), "Native Playlist drop target accepts the dragged row pasteboard")
                try check(model.queue == [ids[0], ids[3], ids[1], ids[2]], "Dropping a row inserts it before the destination")
                try check(!model.playlistReorderTargeted, "Dropping clears the insertion indicator")
                model.movePlaylistItem(ids[0], before: nil)
                try check(model.queue == [ids[3], ids[1], ids[2], ids[0]], "Bottom drop target moves an item to the end")
                model.movePlaylistItem(ids[2], before: ids[3])
                try check(model.queue == [ids[2], ids[3], ids[1], ids[0]], "Reordering upward preserves all other item positions")
                let ordered = model.queue
                model.movePlaylistItem(ids[1], before: ids[1])
                model.movePlaylistItem(UUID(), before: ids[0])
                try check(model.queue == ordered && Set(model.queue).count == 4, "Self and stale drops do not duplicate or remove entries")
                try check(model.currentID == current && model.speed == speed, "Reordering does not change the playing item or speed")
            } catch let error as Failure { failure = error.message }
            catch { failure = error.localizedDescription }
            let report: [String: Any] = ["passed": failure == nil, "checks": checks, "skipped": [], "failure": failure ?? NSNull()]
            if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
                try? data.write(to: root.appendingPathComponent("smoke-result.json"), options: .atomic)
            }
            model.queue = []; model.shutdown(); NSApp.terminate(nil)
        }
    }

    private static func runFolderOpenOnly(model: PlayerModel, root: URL) {
        Task { @MainActor in
            var checks: [String] = []
            var failure: String?
            let folder = root.appendingPathComponent("folder-open-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: folder) }
            func check(_ valid: Bool, _ name: String) throws {
                guard valid else { throw Failure(message: name) }; checks.append(name)
            }
            do {
                for _ in 0..<200 {
                    if model.engine?.engineReady == true { break }
                    try await Task.sleep(for: .milliseconds(50))
                }
                guard model.engine?.engineReady == true else { throw Failure(message: "Playback engine did not initialize") }
                let nested = folder.appendingPathComponent("Season/Subfolder")
                try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
                try FileManager.default.copyItem(at: root.appendingPathComponent("first.mp4"), to: folder.appendingPathComponent("first.mp4"))
                try FileManager.default.copyItem(at: root.appendingPathComponent("second.mkv"), to: nested.appendingPathComponent("second.MKV"))
                try FileManager.default.copyItem(at: root.appendingPathComponent("first.mp4"), to: nested.appendingPathComponent("third.mp4"))
                try Data().write(to: nested.appendingPathComponent("notes.txt"))
                model.open([folder])
                let names = model.queue.compactMap { model.library.record($0)?.name }
                try check(names == ["first.mp4", "second.MKV", "third.mp4"], "Folder opening includes supported media from all nested subfolders in stable order")
                try check(model.current?.name == "first.mp4", "Folder opening selects the first media file as before")
                for _ in 0..<200 {
                    if model.loaded || model.error != nil { break }
                    try await Task.sleep(for: .milliseconds(50))
                }
                try check(model.loaded && model.error == nil && model.duration > 10, "Recursively opened folder still loads its first playable media file")
                model.open([folder])
                try check(model.queue.count == 3 && Set(model.queue).count == 3, "Reopening a recursive folder does not duplicate playlist entries")
            } catch let error as Failure { failure = error.message }
            catch { failure = error.localizedDescription }
            let report: [String: Any] = ["passed": failure == nil, "checks": checks, "skipped": [], "failure": failure ?? NSNull()]
            if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
                try? data.write(to: root.appendingPathComponent("smoke-result.json"), options: .atomic)
            }
            model.shutdown(); NSApp.terminate(nil)
        }
    }

    private static func runCloseToDockOnly(model: PlayerModel, root: URL) {
        Task { @MainActor in
            var checks: [String] = []
            var failure: String?
            let originalKeepRunning = model.keepRunningWhenWindowCloses
            func check(_ valid: Bool, _ name: String) throws {
                guard valid else { throw Failure(message: name) }; checks.append(name)
            }
            @MainActor func waitFor(_ condition: @MainActor () -> Bool) async throws {
                for _ in 0..<200 {
                    if condition() { return }
                    if let error = model.error { throw Failure(message: error) }
                    try await Task.sleep(for: .milliseconds(50))
                }
                throw Failure(message: "Timed out checking close-to-Dock behavior")
            }
            do {
                guard let delegate = NSApp.delegate as? AppDelegate, let window = model.window else {
                    throw Failure(message: "Missing player window")
                }
                model.keepRunningWhenWindowCloses = false
                try check(delegate.applicationShouldTerminateAfterLastWindowClosed(NSApp), "Switch off retains close-to-quit behavior")
                model.keepRunningWhenWindowCloses = true
                try check(!delegate.applicationShouldTerminateAfterLastWindowClosed(NSApp), "Switch on keeps the app running without a player window")
                try await waitFor { model.engine?.engineReady == true }
                model.open([root.appendingPathComponent("first.mp4")])
                try await waitFor { model.loaded && model.duration > 10 }
                model.setPaused(false)
                try await waitFor { !model.paused && model.position > 0.2 }
                let engine = model.engine
                let current = model.currentID
                let queue = model.queue
                model.show(.playlist)
                window.performClose(nil)
                try await waitFor { model.paused && model.engine?.flagProperty("pause") == true }
                try check(!window.isVisible && model.paused && !model.sidebar
                    && delegate.libraryController?.window?.isVisible != true, "Closing pauses actual playback and hides the player and Library")
                try check(model.engine === engine && model.engine?.engineReady == true
                    && model.currentID == current && model.queue == queue, "Closing retains the loaded engine, current file, and playlist")
                _ = delegate.applicationShouldHandleReopen(NSApp, hasVisibleWindows: false)
                try await waitFor { window.isVisible }
                try check(window.isVisible && model.paused && model.currentID == current, "Dock reopen restores the same player and leaves playback paused")
                let position = model.position
                model.setPaused(false)
                try await waitFor { !model.paused && model.position > position + 0.15 }
                try check(model.engine === engine, "Playback resumes after reopening without rebuilding the engine")
                model.closePlayerWindow()
                try await waitFor { model.paused && model.engine?.flagProperty("pause") == true }
                try check(!window.isVisible && model.paused, "Context-menu Close also pauses and keeps the player reusable")
                _ = delegate.applicationShouldHandleReopen(NSApp, hasVisibleWindows: false)
                try check(delegate.applicationShouldTerminate(NSApp) == .terminateNow,
                    "Explicit Quit remains allowed while keep-running is enabled")
            } catch let error as Failure { failure = error.message }
            catch { failure = error.localizedDescription }
            model.keepRunningWhenWindowCloses = originalKeepRunning
            let report: [String: Any] = ["passed": failure == nil, "checks": checks, "skipped": [], "failure": failure ?? NSNull()]
            if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
                try? data.write(to: root.appendingPathComponent("smoke-result.json"), options: .atomic)
            }
            NSApp.terminate(nil)
        }
    }

    private static func runLibraryRefreshOnly(model: PlayerModel, root: URL) {
        Task { @MainActor in
            var checks: [String] = []
            var failure: String?
            do {
                let id = try model.library.visit(root.appendingPathComponent("refresh.mp4"))
                model.queue = [id]; model.currentID = id; model.tab = .playlist
                let view = LibraryView(model: model)
                // Exercise the same read that supplies the SwiftUI rows, not a separate revision read.
                func verifyRefresh(_ name: String, change: () -> Void, valid: () -> Bool) throws {
                    let notification = RefreshNotification()
                    withObservationTracking {
                        _ = view.displayedRecords
                    } onChange: {
                        notification.received = true
                    }
                    change()
                    guard notification.received && valid() else { throw Failure(message: name) }
                    checks.append(name)
                }
                try verifyRefresh("Playlist observes bookmark additions", change: {
                    model.perform { try model.library.addBookmark(id, seconds: 10, title: "Refresh") }
                }, valid: { view.displayedRecords.first?.bookmarks.count == 1 })
                try verifyRefresh("Playlist observes saved watch position", change: {
                    model.perform { try model.library.updatePosition(id, seconds: 5, duration: 100) }
                }, valid: { view.displayedRecords.first?.hasBeenPlayed == true && view.displayedRecords.first?.watchStatus == nil })
                try verifyRefresh("Playlist observes watched status", change: {
                    model.perform { try model.library.recordPlayback(id, seconds: 0, finished: true) }
                }, valid: { view.displayedRecords.first?.watchStatus == "Watched" })
                try verifyRefresh("Playlist observes bookmark removals", change: {
                    model.perform { try model.library.removeAllBookmarks(id) }
                }, valid: { view.displayedRecords.first?.bookmarks.isEmpty == true })
            } catch let error as Failure { failure = error.message }
            catch { failure = error.localizedDescription }
            let report: [String: Any] = ["passed": failure == nil, "checks": checks, "skipped": [], "failure": failure ?? NSNull()]
            if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
                try? data.write(to: root.appendingPathComponent("smoke-result.json"), options: .atomic)
            }
            model.shutdown(); NSApp.terminate(nil)
        }
    }

    // Observation invokes onChange synchronously on the mutating thread in these checks.
    private final class RefreshNotification: @unchecked Sendable {
        nonisolated(unsafe) var received = false
    }

    private static func runControlsTimeoutOnly(model: PlayerModel, root: URL) {
        Task { @MainActor in
            var checks: [String] = []
            var failure: String?
            func check(_ valid: Bool, _ message: String) throws {
                guard valid else { throw Failure(message: message) }
                checks.append(message)
            }
            do {
                let player = model.window as? PlayerWindow
                let pointerActivity = player?.pointerActivity
                player?.pointerActivity = nil
                defer { player?.pointerActivity = pointerActivity }
                model.setFullScreenControls(true)
                try check(!model.fullScreenControlsHidden, "Controls visible on entering full screen")
                try await Task.sleep(for: .seconds(3))
                model.revealFullScreenControls()
                try await Task.sleep(for: .seconds(3))
                try check(!model.fullScreenControlsHidden, "Pointer activity resets the five-second deadline")
                try await Task.sleep(for: .seconds(2.3))
                try check(model.fullScreenControlsHidden, "Controls hide five seconds after the latest activity")
                player?.pointerActivity = pointerActivity
                if let window = player,
                   let event = NSEvent.mouseEvent(with: .mouseMoved, location: .zero, modifierFlags: [],
                        timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                        context: nil, eventNumber: 0, clickCount: 0, pressure: 0) {
                    window.sendEvent(event)
                    try check(!model.fullScreenControlsHidden, "Native mouse movement reveals hidden controls")
                } else { throw Failure(message: "Could not send mouse movement to player") }
                model.setFullScreenControls(false)
                try await Task.sleep(for: .seconds(5.3))
                try check(!model.fullScreenControlsHidden && !model.isFullScreen, "Windowed controls remain visible after timeout")
            } catch let error as Failure { failure = error.message }
            catch { failure = error.localizedDescription }
            let report: [String: Any] = ["passed": failure == nil, "checks": checks, "skipped": [], "failure": failure ?? NSNull()]
            if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
                try? data.write(to: root.appendingPathComponent("smoke-result.json"), options: .atomic)
            }
            model.shutdown(); NSApp.terminate(nil)
        }
    }

    private static func runBookmarkNamingOnly(model: PlayerModel, root: URL) {
        Task { @MainActor in
            var checks: [String] = []
            var failure: String?
            let preference = model.promptForBookmark
            defer { model.promptForBookmark = preference }
            func check(_ valid: Bool, _ message: String) throws {
                guard valid else { throw Failure(message: message) }
                checks.append(message)
            }
            do {
                model.promptForBookmark = false
                let id = try model.library.visit(root.appendingPathComponent("name.mp4"))
                model.currentID = id; model.loaded = true; model.position = 12
                model.addBookmark()
                guard let target = model.bookmarkConfirmation else { throw Failure(message: "Missing bookmark confirmation") }
                try check(model.library.record(id)?.bookmarks.count == 1 && model.messageUntil.timeIntervalSinceNow > 2.8,
                          "Bookmark saved immediately with three-second clickable confirmation")
                model.nameConfirmedBookmark()
                try check(model.bookmarkNameTarget?.bookmarkID == target.bookmarkID, "Confirmation opens naming for exact saved bookmark")
                let prompt = NSHostingView(rootView: BookmarkNamePrompt(model: model))
                prompt.frame = NSRect(x: 0, y: 0, width: 960, height: 540)
                prompt.layoutSubtreeIfNeeded()
                model.currentID = try model.library.visit(root.appendingPathComponent("other.mp4"))
                model.finishBookmarkNaming("  Favorite scene  ")
                try check(model.library.record(id)?.bookmarks.first?.title == "Favorite scene"
                    && model.library.record(id)?.bookmarks.count == 1 && model.bookmarkNameTarget == nil,
                    "Enter renames the original bookmark without duplicates after file change")
                model.bookmarkNameTarget = target; model.finishBookmarkNaming("   ")
                try check(model.library.record(id)?.bookmarks.first?.title == "Favorite scene" && model.bookmarkNameTarget == nil,
                          "Empty Enter dismisses and preserves bookmark")
                model.bookmarkNameTarget = target; model.finishBookmarkNaming(nil)
                try check(model.library.record(id)?.bookmarks.count == 1 && model.bookmarkNameTarget == nil,
                          "Cancel or Escape preserves saved bookmark")
                model.bookmarkConfirmation = target; model.messageUntil = .distantPast
                model.nameConfirmedBookmark()
                try check(model.bookmarkNameTarget == nil, "Expired confirmation cannot open naming")
            } catch let error as Failure { failure = error.message }
            catch { failure = error.localizedDescription }
            model.loaded = false
            let report: [String: Any] = ["passed": failure == nil, "checks": checks, "skipped": [], "failure": failure ?? NSNull()]
            if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
                try? data.write(to: root.appendingPathComponent("smoke-result.json"), options: .atomic)
            }
            model.shutdown(); NSApp.terminate(nil)
        }
    }

    private static func runLibrarySortingOnly(model: PlayerModel, root: URL) {
        Task { @MainActor in
            var checks: [String] = []
            var failure: String?
            func check(_ valid: Bool, _ message: String) throws {
                guard valid else { throw Failure(message: message) }
                checks.append(message)
            }
            func scrollView(in view: NSView?) -> NSScrollView? {
                guard let view else { return nil }
                if let scroll = view as? NSScrollView { return scroll }
                return view.subviews.compactMap { scrollView(in: $0) }.first
            }
            do {
                var ids: [UUID] = []
                for index in 0..<60 {
                    let id = try model.library.visit(root.appendingPathComponent("folder/Item-\(index).mp4"))
                    try model.library.addBookmark(id, seconds: 1, title: "Moment")
                    ids.append(id)
                }
                let other = try model.library.visit(root.appendingPathComponent("other/Other.mp4"))
                model.queue = ids + [other]; model.currentID = ids.last; model.revision += 1
                model.show(.playlist)
                try await Task.sleep(for: .seconds(1))
                let panel = (NSApp.delegate as? AppDelegate)?.libraryController?.window
                try check((scrollView(in: panel?.contentView)?.contentView.bounds.origin.y ?? 0) > 100,
                          "Opening Playlist scrolls to the current media near the bottom")
                model.onlyCurrentFolder = true
                let view = LibraryView(model: model)
                try check(view.displayedRecords.count == 60 && !view.displayedRecords.contains(where: { $0.id == other }),
                          "Playlist current-folder filter excludes other folders")
                model.playlistSort = .dateAdded
                try check(view.displayedRecords.first?.id == ids.last, "Playlist Date added sorts newest first")
                model.historyAscending = true; model.tab = .history
                try await Task.sleep(for: .seconds(0.8))
                try check((scrollView(in: panel?.contentView)?.contentView.bounds.origin.y ?? 0) > 100,
                          "Switching to History reveals current media")
                model.bookmarksAscending = true; model.tab = .bookmarks
                try await Task.sleep(for: .seconds(0.8))
                try check((scrollView(in: panel?.contentView)?.contentView.bounds.origin.y ?? 0) > 100,
                          "Switching to Bookmarks reveals current file group")
                model.sidebar = false; model.show(.playlist)
                try await Task.sleep(for: .seconds(0.8))
                try check(panel?.isVisible == true, "Library reopens and requests current-media reveal")
                let count = model.library.record(ids[0])?.bookmarks.count
                model.play(ids[0])
                try check(model.error?.contains("unavailable") == true && model.library.record(ids[0])?.bookmarks.count == count,
                          "Missing media reports unavailable and preserves bookmarks")
            } catch let error as Failure { failure = error.message }
            catch { failure = error.localizedDescription }
            let report: [String: Any] = ["passed": failure == nil, "checks": checks, "skipped": [], "failure": failure ?? NSNull()]
            if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
                try? data.write(to: root.appendingPathComponent("smoke-result.json"), options: .atomic)
            }
            model.shutdown(); NSApp.terminate(nil)
        }
    }

    static func run(model: PlayerModel, root: URL) {
        if ProcessInfo.processInfo.environment["LOLA_SMOKE_LIBRARY_SORTING_ONLY"] == "1" {
            runLibrarySortingOnly(model: model, root: root); return
        }
        if ProcessInfo.processInfo.environment["LOLA_SMOKE_BOOKMARK_NAMING_ONLY"] == "1" {
            runBookmarkNamingOnly(model: model, root: root); return
        }
        if ProcessInfo.processInfo.environment["LOLA_SMOKE_CONTROLS_TIMEOUT_ONLY"] == "1" {
            runControlsTimeoutOnly(model: model, root: root); return
        }
        if ProcessInfo.processInfo.environment["LOLA_SMOKE_LIBRARY_REFRESH_ONLY"] == "1" {
            runLibraryRefreshOnly(model: model, root: root); return
        }
        if CommandLine.arguments.contains("--close-to-dock-only") {
            runCloseToDockOnly(model: model, root: root); return
        }
        if CommandLine.arguments.contains("--folder-open-only") {
            runFolderOpenOnly(model: model, root: root); return
        }
        if CommandLine.arguments.contains("--playlist-reorder-only") {
            runPlaylistReorderOnly(model: model, root: root); return
        }
        Task { @MainActor in
            var checks: [String] = []
            var skipped: [String] = []
            let originalFloat = model.floatEnabled
            let originalAutoplay = model.autoplay
            let originalPrompt = model.promptForBookmark
            let originalRememberWindow = model.rememberWindowGeometry
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
                try check(NSApp.mainMenu != nil && model.libraryReady, "Menu and library are ready before playback tests")
                try check((NSApp.delegate as? AppDelegate)?.libraryController == nil, "Hidden Library panel is not created during startup")
                try await waitFor { model.engine?.engineReady == true }
                let dropRoot = root.appendingPathComponent("playlist-drop-\(UUID().uuidString)")
                defer { try? FileManager.default.removeItem(at: dropRoot) }
                let nestedDrop = dropRoot.appendingPathComponent("Folder/Subfolder")
                try FileManager.default.createDirectory(at: nestedDrop, withIntermediateDirectories: true)
                try Data().write(to: dropRoot.appendingPathComponent("first.mp4"))
                try Data().write(to: nestedDrop.appendingPathComponent("second.mkv"))
                try Data().write(to: nestedDrop.appendingPathComponent("ignore.txt"))
                let droppedModel = PlayerModel()
                await droppedModel.loadLibrary()
                try check(droppedModel.dropOnPlaylist([NSItemProvider(object: dropRoot as NSURL)]),
                    "Playlist accepts a Finder-style folder URL provider")
                try await waitFor { droppedModel.queue.count == 2 || droppedModel.error != nil }
                try check(droppedModel.queue.count == 2 && droppedModel.error == nil
                    && droppedModel.historyRecords.isEmpty && droppedModel.currentID == nil,
                    "Folder drops add nested media to Playlist without playing it or marking it as History")
                let originalQueue = droppedModel.queue
                await droppedModel.appendPlaylistFiles([dropRoot, dropRoot.appendingPathComponent("first.mp4")])
                try check(droppedModel.queue == originalQueue, "Repeated file and overlapping folder drops do not duplicate Playlist entries")
                try droppedModel.library.flush()
                let modeSuite = "local.lolaplayer.mode-test.\(UUID().uuidString)"
                let modeDefaults = UserDefaults(suiteName: modeSuite)!
                defer { modeDefaults.removePersistentDomain(forName: modeSuite) }
                func freshModeWindow() -> NSWindow {
                    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 500),
                        styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
                    window.isReleasedWhenClosed = false
                    return window
                }
                let firstWindow = freshModeWindow()
                let firstLaunch = PlayerModel(); firstLaunch.window = firstWindow
                firstLaunch.rememberWindowGeometry = false
                firstLaunch.setMediaOnly(true, defaults: modeDefaults)
                let modeWindow = freshModeWindow()
                let nextLaunch = PlayerModel(); nextLaunch.window = modeWindow
                nextLaunch.rememberWindowGeometry = false
                nextLaunch.restoreInterfaceMode(from: modeDefaults)
                try check(nextLaunch.mediaOnly && modeWindow.titleVisibility == .hidden
                    && modeWindow.styleMask.contains(.fullSizeContentView)
                    && modeWindow.minSize == NSSize(width: 100, height: 64),
                    "Media-only preference restores hidden controls and window chrome without remembering geometry")
                nextLaunch.setMediaOnly(false, defaults: modeDefaults)
                let fullWindow = freshModeWindow()
                let fullLaunch = PlayerModel(); fullLaunch.window = fullWindow
                fullLaunch.restoreInterfaceMode(from: modeDefaults)
                try check(!fullLaunch.mediaOnly && !modeDefaults.bool(forKey: "mediaOnly")
                    && fullWindow.titleVisibility == .visible,
                    "Returning to full interface persists for the next launch")
                fullWindow.orderFront(nil)
                fullLaunch.closePlayerWindow()
                try check(!fullWindow.isVisible, "Player Close action closes its window")

                if let delegate = NSApp.delegate as? AppDelegate, let window = model.window {
                    try await Task.sleep(for: .milliseconds(300))
                    NSApp.activate(ignoringOtherApps: true)
                    window.makeKeyAndOrderFront(nil)
                    for _ in 0..<10 {
                        if window.isKeyWindow && delegate.isPlayerAppFrontmost { break }
                        try await Task.sleep(for: .milliseconds(100))
                    }
                    let canDispatchKeys = window.isKeyWindow && delegate.isPlayerAppFrontmost
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
                    try check(NSApp.mainMenu?.performKeyEquivalent(with: key("2")) == false && !model.mediaOnly,
                        "Real menu key equivalents also preserve number entry in text fields")
                    window.makeFirstResponder(nil)
                    field.removeFromSuperview()
                    }
                    if canDispatchKeys {
                        window.sendEvent(key("2"))
                        try check(model.mediaOnly, "Direct player-window key dispatch handles 2 before the video responder")
                        window.sendEvent(key("1"))
                        try check(!model.mediaOnly, "Direct player-window key dispatch handles 1 before the video responder")
                        let noSource = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                            windowNumber: 0, context: nil, characters: "2", charactersIgnoringModifiers: "2", isARepeat: false, keyCode: 19)!
                        try check(NSApp.mainMenu?.performKeyEquivalent(with: noSource) == true && model.mediaOnly,
                            "Number key events with no source window target the current key player")
                        NSApp.sendEvent(key("1"))
                        try check(!model.mediaOnly, "Application-level key dispatch restores the full interface")
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
                    let playerFrame = window.frame
                    model.show(.playlist)
                    guard let libraryWindow = delegate.libraryController?.window else { throw Failure(message: "Missing detached library window") }
                    try check(libraryWindow !== window && libraryWindow.isVisible && window.frame == playerFrame,
                        "Library opens in a separate window without resizing the player")
                    try check(libraryWindow.collectionBehavior.contains(.fullScreenAuxiliary), "Library supports the player full-screen Space")
                    for tab in LibraryTab.allCases {
                        model.show(tab)
                        libraryWindow.contentView?.layoutSubtreeIfNeeded()
                        try check(model.tab == tab && libraryWindow.frame.width >= 380 && window.frame == playerFrame,
                            "Detached \(tab.rawValue) layout keeps the player unchanged")
                    }
                    libraryWindow.performClose(nil)
                    try check(!model.sidebar && !libraryWindow.isVisible, "Closing Library clears visibility without closing the player")
                    let viewMenu = NSApp.mainMenu?.items.first(where: { $0.title == "View" })?.submenu
                    try check(viewMenu?.items[0].title == "Show Full Interface" && viewMenu?.items[0].keyEquivalent == "1"
                        && viewMenu?.items[0].keyEquivalentModifierMask.isEmpty == true
                        && viewMenu?.items[1].title == "Media Only" && viewMenu?.items[1].keyEquivalent == "2"
                        && viewMenu?.items[1].keyEquivalentModifierMask.isEmpty == true,
                        "View shows unmodified 1/2 shortcuts in the shortcut column")
                    try check(delegate.rememberWindowItem.title == "Remember Window Position and Size", "View includes the window-geometry preference")
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
                    controller.window?.makeKeyAndOrderFront(nil)
                    let aboutWasKey = controller.window?.isKeyWindow == true
                    model.window?.makeKeyAndOrderFront(nil)
                    if aboutWasKey {
                        try await Task.sleep(for: .milliseconds(100))
                        try check(controller.window?.isVisible == false, "Returning to the player dismisses About")
                    } else {
                        controller.windowDidResignKey(Notification(name: NSWindow.didResignKeyNotification, object: controller.window))
                        try check(controller.window?.isVisible == false, "About dismisses when its key focus is lost")
                    }
                    controller.showWindow(nil)
                    controller.applicationDidResignActive(Notification(name: NSApplication.didResignActiveNotification, object: NSApp))
                    try check(controller.window?.isVisible == false && controller.window?.hidesOnDeactivate == false,
                        "App deactivation closes About rather than leaving a hidden auto-restoring panel")
                    controller.showWindow(nil)
                    try check(controller.window?.isVisible == true, "About can still be explicitly reopened after dismissal")
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
                if let delegate = NSApp.delegate as? AppDelegate, let window = model.window {
                    @MainActor func space(_ number: Int = 0) -> NSEvent {
                        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                            windowNumber: number, context: nil, characters: " ", charactersIgnoringModifiers: " ",
                            isARepeat: false, keyCode: 49)!
                    }
                    @MainActor func playbackKey(_ key: String, modifiers: NSEvent.ModifierFlags) -> NSEvent {
                        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0,
                            windowNumber: window.windowNumber, context: nil,
                            characters: modifiers == .option && key == "b" ? "∫" : key,
                            charactersIgnoringModifiers: key, isARepeat: false, keyCode: key == "\\" ? 42 : 11)!
                    }
                    let resetKey = playbackKey("\\", modifiers: .command)
                    let namedKey = playbackKey("b", modifiers: .option)
                    if let finder = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first {
                        finder.activate(options: [.activateIgnoringOtherApps])
                        try await waitFor { NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.finder" }
                        model.changeSpeed(1.5)
                        let beforeBackground = model.current?.bookmarks.count
                        try check(NSApp.mainMenu?.performKeyEquivalent(with: resetKey) == false && model.speed == 1.5
                            && NSApp.mainMenu?.performKeyEquivalent(with: namedKey) == false
                            && model.current?.bookmarks.count == beforeBackground,
                            "Command-Backslash and Option-B cannot change speed or add bookmarks while Finder is active")
                        let position = model.position
                        try check(NSApp.mainMenu?.performKeyEquivalent(with: space()) == false && !model.paused,
                            "With Finder frontmost, Lola menu refuses Space and leaves playback running")
                        try check(!delegate.handleViewShortcut(space(window.windowNumber)) && !model.paused,
                            "Even a Space event naming the player cannot control background Lola")
                        try await Task.sleep(for: .milliseconds(300))
                        try check(!model.paused && model.position >= position, "Finder focus does not pause or stop playback")
                    }
                    NSApp.activate(ignoringOtherApps: true); window.makeKeyAndOrderFront(nil)
                    try await waitFor { delegate.isPlayerAppFrontmost && window.isKeyWindow }
                    window.makeFirstResponder(nil)
                    model.changeSpeed(1.75)
                    let unusedPrintKey = playbackKey("p", modifiers: .command)
                    try check(NSApp.mainMenu?.performKeyEquivalent(with: unusedPrintKey) == false && model.speed == 1.75,
                        "Command-P is unassigned and does not reset playback speed")
                    try check(NSApp.mainMenu?.performKeyEquivalent(with: resetKey) == true && model.speed == 1,
                        "Focused Command-Backslash resets playback speed to 1x")
                    model.settingsOpen = true
                    model.changeSpeed(1.5)
                    try check(NSApp.mainMenu?.performKeyEquivalent(with: namedKey) == false,
                        "Settings prevents Option-B playback shortcuts")
                    model.settingsOpen = false
                    let typingField = NSTextField(string: "Typing")
                    window.contentView?.addSubview(typingField); window.makeFirstResponder(typingField)
                    try check(NSApp.mainMenu?.performKeyEquivalent(with: namedKey) == false,
                        "Text editing protects Option-B")
                    window.makeFirstResponder(nil); typingField.removeFromSuperview()
                    model.changeSpeed(1)
                    window.makeKeyAndOrderFront(nil)
                    try await waitFor { delegate.canUseFocusedPlaybackShortcuts }
                    model.setPaused(true)
                    if ProcessInfo.processInfo.environment["LOLA_SKIP_NAMED_BOOKMARK_SMOKE"] != "1" {
                    let bookmarkCount = model.current?.bookmarks.count ?? 0
                    let namingTimer = Timer(timeInterval: 0.15, repeats: false) { _ in
                        MainActor.assumeIsolated {
                            (NSApp.modalWindow?.initialFirstResponder as? NSTextField)?.stringValue = "Shortcut named bookmark"
                            NSApp.stopModal(withCode: .alertFirstButtonReturn)
                        }
                    }
                    RunLoop.main.add(namingTimer, forMode: .modalPanel)
                    let namedHandled = NSApp.mainMenu?.performKeyEquivalent(with: namedKey)
                    namingTimer.invalidate()
                    let shortcutBookmark = model.current?.bookmarks.last
                    try check(namedHandled == true && model.current?.bookmarks.count == bookmarkCount + 1
                        && shortcutBookmark?.title == "Shortcut named bookmark" && !model.promptForBookmark,
                        "Option-B saves the entered name even when automatic bookmark naming is disabled (handled: \(String(describing: namedHandled)), count: \(model.current?.bookmarks.count ?? -1), title: \(shortcutBookmark?.title ?? "none"), loaded: \(model.loaded), key: \(namedKey.charactersIgnoringModifiers ?? "none"), focused: \(delegate.canUseFocusedPlaybackShortcuts))")
                    if let id = model.currentID, let shortcutBookmark { try model.library.removeBookmark(id, bookmark: shortcutBookmark.id) }
                    window.makeKeyAndOrderFront(nil); window.makeFirstResponder(nil)
                    try await waitFor { delegate.canUseFocusedPlaybackShortcuts }
                    let cancelTimer = Timer(timeInterval: 0.15, repeats: false) { _ in
                        MainActor.assumeIsolated { NSApp.stopModal(withCode: .alertSecondButtonReturn) }
                    }
                    RunLoop.main.add(cancelTimer, forMode: .modalPanel)
                    _ = NSApp.mainMenu?.performKeyEquivalent(with: namedKey)
                    cancelTimer.invalidate()
                    try check(model.current?.bookmarks.count == bookmarkCount, "Canceling Option-B does not add a bookmark")
                    } else { skipped.append("Named-bookmark dialog checks omitted by request") }
                    window.makeKeyAndOrderFront(nil); window.makeFirstResponder(nil)
                    try await waitFor { delegate.canUseFocusedPlaybackShortcuts }
                    model.seek(0.5); model.setPaused(false)
                    try await waitFor { !model.paused && model.position < 3 }
                    window.sendEvent(space(window.windowNumber))
                    try check(model.paused, "Space still pauses when the player is active")
                    window.sendEvent(space(window.windowNumber))
                    try check(!model.paused, "Space still resumes when the player is active")
                    let field = NSTextField(frame: NSRect(x: 10, y: 10, width: 100, height: 24))
                    window.contentView?.addSubview(field); window.makeFirstResponder(field)
                    try check(NSApp.mainMenu?.performKeyEquivalent(with: space(window.windowNumber)) == false && !model.paused,
                        "Space is reserved for text entry while a field is being edited")
                    window.makeFirstResponder(nil); field.removeFromSuperview()
                }
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
                    if let delegate = NSApp.delegate as? AppDelegate, let window = model.window {
                        model.show(.playlist)
                        if window.isKeyWindow == false && NSApp.isActive {
                            let source = delegate.libraryController!.window!
                            let typing = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                windowNumber: source.windowNumber, context: nil, characters: "2", charactersIgnoringModifiers: "2", isARepeat: false, keyCode: 19)!
                            try check(NSApp.mainMenu?.performKeyEquivalent(with: typing) == false && !model.mediaOnly,
                                "Typing 2 in the detached Library does not change the player layout")
                        }
                        model.sidebar = false
                    }
                    (NSApp.delegate as? AppDelegate)?.showAbout()
                    let location = surface.convert(NSPoint(x: surface.bounds.midX, y: surface.bounds.midY), to: nil)
                    for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                        let event = NSEvent.mouseEvent(with: type, location: location, modifierFlags: [], timestamp: 0,
                            windowNumber: model.window!.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
                        if type == .leftMouseDown { surface.mouseDown(with: event) } else { surface.mouseUp(with: event) }
                    }
                    try await waitFor { model.paused }
                    try check(model.playbackClickFeedback.symbol == "pause.fill", "Video click shows a centered pause confirmation state")
                    try await waitFor { model.playbackClickFeedback.symbol == nil }
                    try check(model.playbackClickFeedback.opacity == 0, "Video-click confirmation clears after its short fade")
                    model.togglePlaybackFromVideo()
                    try check(!model.paused && model.playbackClickFeedback.symbol == "play.fill", "Resuming by video click shows the play confirmation state")
                    model.togglePlaybackFromVideo()
                    try check(model.paused && model.playbackClickFeedback.symbol == "pause.fill", "A newer click replaces the previous confirmation")
                    try await waitFor { model.playbackClickFeedback.symbol == nil }
                    model.togglePlayback(); model.togglePlayback()
                    try check(model.playbackClickFeedback.symbol == nil && model.paused, "Other playback commands do not trigger click animation")
                    NSApp.activate(ignoringOtherApps: true)
                    model.window?.makeKeyAndOrderFront(nil)
                    try await waitFor { (NSApp.delegate as? AppDelegate)?.isPlayerAppFrontmost == true && model.window?.isKeyWindow == true }
                    if model.window?.isKeyWindow == true {
                        let window = model.window!
                        @MainActor func number(_ value: String) -> NSEvent {
                            NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                windowNumber: window.windowNumber, context: nil, characters: value,
                                charactersIgnoringModifiers: value, isARepeat: false, keyCode: value == "1" ? 18 : 19)!
                        }
                        window.sendEvent(number("2"))
                        try check(model.mediaOnly, "After clicking the playing video, 2 hides its controls")
                        window.sendEvent(number("1"))
                        try check(!model.mediaOnly, "After clicking the playing video, 1 restores its controls")
                        @MainActor func wheel(_ y: Int32, x: Int32 = 0) -> NSEvent {
                            NSEvent(cgEvent: CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 2,
                                wheel1: y, wheel2: x, wheel3: 0)!)!
                        }
                        NSApp.activate(ignoringOtherApps: true)
                        window.makeKeyAndOrderFront(nil)
                        try await waitFor { NSApp.isActive && window.isKeyWindow }
                        let oldVolume = model.volume
                        model.changeVolume(50)
                        surface.scrollWheel(with: wheel(1))
                        try check(model.volume == 55 && model.paused, "Scrolling up over active video raises volume without changing playback")
                        surface.scrollWheel(with: wheel(-1))
                        try check(model.volume == 50, "Scrolling down over active video lowers volume")
                        surface.scrollWheel(with: wheel(1, x: 10))
                        try check(model.volume == 50, "Horizontal video scrolling leaves volume unchanged")
                        model.changeVolume(99); surface.scrollWheel(with: wheel(1))
                        try check(model.volume == 100, "Scroll volume cannot exceed 100 percent")
                        model.changeVolume(1); surface.scrollWheel(with: wheel(-1))
                        try check(model.volume == 0, "Scroll volume cannot go below zero")
                        model.settingsOpen = true
                        surface.scrollWheel(with: wheel(1))
                        try check(model.volume == 0, "Open Settings prevents player scroll volume changes")
                        model.settingsOpen = false
                        model.setMediaOnly(true)
                        surface.scrollWheel(with: wheel(1))
                        try check(model.volume == 5 && model.messageInMediaOnly && model.message?.contains("5%") == true,
                            "Media-only scrolling changes volume and shows temporary percentage feedback")
                        model.setMediaOnly(false)
                        model.show(.playlist)
                        surface.scrollWheel(with: wheel(1))
                        try check(model.volume == 5, "Library focus prevents video scroll volume changes")
                        model.sidebar = false; window.makeKeyAndOrderFront(nil)
                        let wasMuted = model.muted
                        if !wasMuted { model.toggleMute() }
                        surface.scrollWheel(with: wheel(1))
                        try check(model.volume == 10 && model.muted, "Scroll volume preserves an explicit mute selection")
                        if !wasMuted { model.toggleMute() }
                        model.changeVolume(oldVolume)

                    }
                    try check(!NSApp.windows.contains(where: { $0.title == "About Lola Player" && $0.isVisible }),
                        "Clicking the actual player pauses playback and does not reveal the cached About window")
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
                let geometryDomain = "local.lolaplayer.geometry-test.\(UUID().uuidString)"
                let geometryDefaults = UserDefaults(suiteName: geometryDomain)!
                defer { geometryDefaults.removePersistentDomain(forName: geometryDomain) }
                model.rememberWindowGeometry = true
                model.saveWindowGeometry(to: geometryDefaults)
                try check(geometryDefaults.string(forKey: "playerWindowFrame").map(NSRectFromString) == originalFrame,
                    "Remember Window writes the current position and dimensions")
                model.rememberWindowGeometry = false
                geometryDefaults.removeObject(forKey: "playerWindowFrame")
                model.saveWindowGeometry(to: geometryDefaults)
                try check(geometryDefaults.object(forKey: "playerWindowFrame") == nil, "Turning off Remember Window stops geometry storage")
                model.rememberWindowGeometry = true
                model.setMediaOnly(true)
                try check(model.mediaAspectRatio > 0 && abs(model.window!.frame.height
                    - (model.window!.frame.width / model.mediaAspectRatio + MediaWindowLayout.progressHeight)) < 1
                    && abs(model.window!.frame.maxY - originalTop) < 1,
                    "2 fits window height to the video plus progress strip without moving the media top")
                let fittedSize = model.window!.frame.size
                model.saveWindowGeometry(to: geometryDefaults)
                try check(geometryDefaults.string(forKey: "playerWindowFrame").map(NSRectFromString) == originalFrame,
                    "Media-only mode saves the full-interface size and stable position for the next launch")
                let libraryWasOpen = model.sidebar
                model.show(.bookmarks)
                try check(model.mediaOnly && model.window!.frame.size == fittedSize,
                    "Opening detached bookmarks preserves media-only mode and player size")
                model.sidebar = libraryWasOpen
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
                if let delegate = NSApp.delegate as? AppDelegate, let window = model.window, NSApp.isActive {
                    let wasOpen = model.sidebar
                    model.sidebar = true
                    window.makeKeyAndOrderFront(nil)
                    window.toggleFullScreen(nil)
                    try await waitFor { window.styleMask.contains(.fullScreen) && !delegate.isFullScreenTransitioning }
                    try await waitFor { delegate.libraryController?.window?.isVisible == true }
                    let panel = delegate.libraryController!.window!
                    let screen = window.screen!.frame
                    try check(panel.parent === window && abs(panel.frame.maxX - (screen.maxX - 24)) < 2
                        && abs(panel.frame.midY - screen.midY) < 2,
                        "Full-screen Library floats at the actual player screen right-center")
                    window.toggleFullScreen(nil)
                    try await waitFor { !window.styleMask.contains(.fullScreen) && !delegate.isFullScreenTransitioning }
                    try check(panel.parent == nil && panel.isVisible, "Leaving full screen restores the independent Library panel")
                    model.sidebar = wasOpen
                } else { skipped.append("Native full-screen transition checks require an active app; placement math is covered by unit tests") }
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
                try model.library.flush()
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
            model.rememberWindowGeometry = originalRememberWindow
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
