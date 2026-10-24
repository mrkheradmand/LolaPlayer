import AppKit
import SwiftUI
import PlayerCore

@main struct LolaApplication {
    static func main() {
        migrateLegacyPreferences()
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.regular)
        withExtendedLifetime(delegate) { application.run() }
    }

    private static func migrateLegacyPreferences() {
        guard Bundle.main.bundleIdentifier == "local.lolaplayer.app",
              !CommandLine.arguments.contains("--smoke-test") else { return }
        let defaults = UserDefaults.standard
        let domain = "local.lolaplayer.app"
        var preferences = defaults.persistentDomain(forName: domain) ?? [:]
        guard preferences["didMigrateLumenPreferences"] as? Bool != true else { return }
        let legacy = defaults.persistentDomain(forName: "local.lumenplayer.app") ?? [:]
        preferences = legacy.merging(preferences) { _, current in current }
        preferences["didMigrateLumenPreferences"] = true
        defaults.setPersistentDomain(preferences, forName: domain)
    }
}

final class MenuAction: NSObject, NSMenuItemValidation {
    let callback: () -> Void
    var available: () -> Bool = { true }
    init(_ callback: @escaping () -> Void) { self.callback = callback }
    @objc func invoke(_ sender: Any?) { if available() { callback() } }
    @objc func validateMenuItem(_ menuItem: NSMenuItem) -> Bool { available() }
}

/// App menu shortcuts must never handle another application’s keyboard input.
nonisolated final class PlayerMenu: NSMenu {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let appIsFrontmost = MainActor.assumeIsolated { (NSApp.delegate as? AppDelegate)?.isPlayerAppFrontmost == true }
        guard appIsFrontmost else { return false }
        let plainKey = event.charactersIgnoringModifiers?.lowercased()
        let shortcutModifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
        if plainKey == "b" && shortcutModifiers == .option {
            return MainActor.assumeIsolated {
                guard let delegate = NSApp.delegate as? AppDelegate, delegate.model.libraryReady,
                      delegate.canUseFocusedPlaybackShortcuts else { return false }
                guard delegate.model.loaded else { return false }
                delegate.model.addBookmark(named: true)
                return true
            }
        }
        let characters = event.characters
        let modifiers = event.modifierFlags.rawValue
        let windowNumber = event.windowNumber
        if ["1", "2", " "].contains(characters ?? ""),
           event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty {
            return MainActor.assumeIsolated {
                (NSApp.delegate as? AppDelegate)?.handleViewShortcut(characters: characters,
                    modifiers: NSEvent.ModifierFlags(rawValue: modifiers), windowNumber: windowNumber) ?? false
            }
        }
        return super.performKeyEquivalent(with: event)
    }
}

/// Handle player shortcuts before SwiftUI or the video responder consumes plain key presses.
final class PlayerWindow: NSWindow {
    var viewShortcut: ((NSEvent) -> Bool)?
    var pointerActivity: (() -> Void)?
    override func sendEvent(_ event: NSEvent) {
        if [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged, .leftMouseDown, .rightMouseDown, .scrollWheel].contains(event.type) {
            pointerActivity?()
        }
        if event.type == .keyDown, viewShortcut?(event) == true { return }
        super.sendEvent(event)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuDelegate {
    let model = PlayerModel()
    var window: NSWindow!
    var playbackMenu: NSMenu!
    var bookmarkMenu: NSMenu!
    var recentMenu: NSMenu!
    var audioMenu: NSMenu!
    var subtitleMenu: NSMenu!
    var chapterMenu: NSMenu!
    var floatItem: NSMenuItem!
    var rememberWindowItem: NSMenuItem!
    private(set) var libraryController: LibraryWindowController?
    private func ensureLibraryController() {
        if libraryController == nil { libraryController = LibraryWindowController(model: model) }
    }
    var isFullScreenTransitioning: Bool { fullScreenTransition }
    var isPlayerAppFrontmost: Bool {
        NSApp.isActive && NSWorkspace.shared.frontmostApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier
    }
    var canUseFocusedPlaybackShortcuts: Bool {
        guard isPlayerAppFrontmost, let window, window.isKeyWindow,
              window.attachedSheet == nil, NSApp.modalWindow == nil, !model.settingsOpen else { return false }
        return !(window.firstResponder is NSTextView) && !(window.firstResponder is NSTextField)
    }
    var playItem: NSMenuItem!
    private var fullScreenTransition = false
    private var aboutController: AboutWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenus()
        if let iconURL = Bundle.main.url(forResource: "LolaPlayerIcon", withExtension: "icns"),
           let icon = NSImage(contentsOf: iconURL) {
            NSApp.applicationIconImage = icon
        }
        window = PlayerWindow(contentRect: NSRect(x: 0, y: 0, width: 1080, height: 680), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Lola Player"; window.minSize = NSSize(width: 800, height: 420)
        window.appearance = NSAppearance(named: .darkAqua); window.backgroundColor = .black
        window.titlebarAppearsTransparent = true; window.isReleasedWhenClosed = false
        window.collectionBehavior = [.fullScreenPrimary]; window.delegate = self
        window.acceptsMouseMovedEvents = true
        (window as? PlayerWindow)?.pointerActivity = { [weak self] in
            guard let self, self.model.isFullScreen else { return }
            self.model.revealFullScreenControls()
        }
        window.center()
        if model.rememberWindowGeometry, !CommandLine.arguments.contains("--smoke-test"),
           let saved = UserDefaults.standard.string(forKey: "playerWindowFrame"),
           let frame = WindowPlacement.restored(NSRectFromString(saved), screens: NSScreen.screens.map(\.visibleFrame), minimum: window.minSize) {
            window.setFrame(frame, display: true)
        }
        model.window = window
        model.restoreInterfaceMode()
        model.libraryWindowChanged = { [weak self] in
            guard let self, !self.fullScreenTransition else { return }; if self.model.sidebar { self.ensureLibraryController() }; self.libraryController?.sync()
        }
        model.revealLibrary = { [weak self] in
            guard let self, !self.fullScreenTransition else { return }; self.ensureLibraryController(); self.libraryController?.present()
        }
        (window as? PlayerWindow)?.viewShortcut = { [weak self] event in
            self?.handleViewShortcut(event) ?? false
        }
        window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        Task {
        await model.loadLibrary()
        guard model.libraryReady else { return }
        window.contentView = NSHostingView(rootView: PlayerView(model: model))
        model.systemMediaControls = SystemMediaControls(model: model)
        if model.sidebar { ensureLibraryController(); libraryController?.sync() }
        if !CommandLine.arguments.contains("--smoke-test") { model.importElmedia(automatic: true) }
        if let index = CommandLine.arguments.firstIndex(of: "--smoke-test"), CommandLine.arguments.count > index + 1 {
            SmokeTest.run(model: model, root: URL(fileURLWithPath: CommandLine.arguments[index + 1])); return
        }
        model.startAutomaticUpdateChecks()
        let arguments = CommandLine.arguments.dropFirst().filter { !$0.hasPrefix("-") }.map { value in
            if let url = URL(string: value), url.scheme != nil { return url }
            return URL(fileURLWithPath: value)
        }
        if !arguments.isEmpty { model.open(arguments) }
        }
    }
    func application(_ sender: NSApplication, open urls: [URL]) { model.open(urls); window?.makeKeyAndOrderFront(nil) }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { !model.keepRunningWhenWindowCloses }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        model.persistPosition()
        do { try model.library.flush(); return .terminateNow }
        catch {
            let alert = NSAlert(); alert.messageText = "Could not save your library"
            alert.informativeText = error.localizedDescription; alert.runModal()
            return .terminateCancel
        }
    }
    func applicationWillTerminate(_ notification: Notification) {
        model.shutdown()
    }

    func handleViewShortcut(_ event: NSEvent) -> Bool {
        handleViewShortcut(characters: event.characters, modifiers: event.modifierFlags, windowNumber: event.windowNumber)
    }
    func handleViewShortcut(characters: String?, modifiers: NSEvent.ModifierFlags, windowNumber: Int) -> Bool {
        let targetsPlayer = windowNumber == window.windowNumber || (windowNumber == 0 && NSApp.keyWindow === window)
        guard isPlayerAppFrontmost, targetsPlayer, window.isKeyWindow, window.attachedSheet == nil,
              NSApp.modalWindow == nil, !model.settingsOpen,
              !(window.firstResponder is NSTextView), !(window.firstResponder is NSTextField),
              modifiers.intersection([.command, .control, .option, .shift]).isEmpty else { return false }
        switch characters {
        case "1": model.setMediaOnly(false)
        case "2": model.setMediaOnly(true)
        case " ":
            guard model.loaded else { return false }
            model.togglePlayback()
        default: return false
        }
        return true
    }
    func windowWillClose(_ notification: Notification) {
        model.saveWindowGeometry(); model.pauseForWindowClose()
        model.sidebar = false; aboutController?.close()
        // Keep the retained window and engine reusable; termination performs full shutdown.
    }
    func windowDidMove(_ notification: Notification) { model.saveWindowGeometry() }
    func windowDidResize(_ notification: Notification) { model.saveWindowGeometry() }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { window.makeKeyAndOrderFront(nil); return true }

    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        model.mediaOnly && !fullScreenTransition && !sender.styleMask.contains(.fullScreen) ? model.mediaOnlySize(for: frameSize) : frameSize
    }
    func windowDidResignKey(_ notification: Notification) { model.restoreFullScreenPointer() }
    func windowDidBecomeKey(_ notification: Notification) {
        if model.isFullScreen { model.revealFullScreenControls() }
    }
    func windowWillEnterFullScreen(_ notification: Notification) { model.saveWindowGeometry(); fullScreenTransition = true; libraryController?.hideForFullScreenTransition() }
    func windowDidEnterFullScreen(_ notification: Notification) { fullScreenTransition = false; model.setFullScreenControls(true); libraryController?.sync(reposition: true) }
    func windowWillExitFullScreen(_ notification: Notification) { fullScreenTransition = true; model.setFullScreenControls(false); libraryController?.hideForFullScreenTransition() }
    func windowDidExitFullScreen(_ notification: Notification) { fullScreenTransition = false; model.didExitFullScreen(); libraryController?.sync(reposition: true); model.saveWindowGeometry() }

    @discardableResult func item(_ menu: NSMenu, _ title: String, key: String = "", modifiers: NSEvent.ModifierFlags = .command, action: @escaping () -> Void) -> NSMenuItem {
        let target = MenuAction(action)
        if !["Quit Lola Player", "Hide Lola Player", "Close Window"].contains(title) {
            target.available = { [weak self] in
                guard self?.model.libraryReady == true else { return false }
                if title == "About Lola Player" {
                    let responder = NSApp.keyWindow?.firstResponder
                    return !(responder is NSTextView) && !(responder is NSTextField) && NSApp.modalWindow == nil
                }
                return true
            }
        }
        let entry = NSMenuItem(title: title, action: #selector(MenuAction.invoke(_:)), keyEquivalent: key)
        entry.keyEquivalentModifierMask = modifiers; entry.target = target; entry.representedObject = target; menu.addItem(entry); return entry
    }
    func submenu(_ parent: NSMenu, _ title: String) -> NSMenu {
        let entry = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let menu = NSMenu(title: title); entry.submenu = menu; parent.addItem(entry); return menu
    }
    func showAbout() {
        if aboutController == nil { aboutController = AboutWindowController(model: model) }
        aboutController?.showWindow(nil)
        aboutController?.window?.makeKeyAndOrderFront(nil)
        if model.automaticUpdateChecks && !CommandLine.arguments.contains("--smoke-test") {
            model.checkForUpdates(manual: false)
        }
    }

    func buildMenus() {
        let bar = PlayerMenu(); NSApp.mainMenu = bar
        let app = submenu(bar, "Lola Player")
        item(app, "About Lola Player", key: "a") { self.showAbout() }
        item(app, "Settings…", key: ",") { self.model.settingsOpen = true }
        app.addItem(.separator()); item(app, "Hide Lola Player", key: "h") { NSApp.hide(nil) }
        item(app, "Quit Lola Player", key: "q") { NSApp.terminate(nil) }
        let file = submenu(bar, "File")
        item(file, "Open…", key: "o") { self.model.openPanel() }
        item(file, "Open URL…", key: "o", modifiers: [.command, .shift]) { self.model.openURL() }
        item(file, "Import Elmedia Library…") { self.model.importElmedia() }
        recentMenu = submenu(file, "Open Recent"); recentMenu.delegate = self
        file.addItem(.separator()); item(file, "Save Playlist…", key: "s") { self.model.savePlaylist() }
        item(file, "Clear Playlist") { self.model.queue = [] }
        item(file, "Show in Finder") { if let url = self.model.current?.location, url.isFileURL { NSWorkspace.shared.activateFileViewerSelecting([url]) } }
        file.addItem(.separator()); item(file, "Close Window", key: "w") { NSApp.keyWindow?.performClose(nil) }
        let edit = submenu(bar, "Edit")
        for (title, key, selector) in [("Cut", "x", "cut:"), ("Copy", "c", "copy:"), ("Paste", "v", "paste:"), ("Select All", "a", "selectAll:")] {
            edit.addItem(NSMenuItem(title: title, action: NSSelectorFromString(selector), keyEquivalent: key))
        }
        let view = submenu(bar, "View"); view.delegate = self
        item(view, "Show Full Interface", key: "1", modifiers: []) { self.model.setMediaOnly(false) }
        item(view, "Media Only", key: "2", modifiers: []) { self.model.setMediaOnly(true) }
        view.addItem(.separator())
        rememberWindowItem = item(view, "Remember Window Position and Size") { self.model.rememberWindowGeometry.toggle() }
        floatItem = item(view, "Float on Top", key: "t", modifiers: [.command, .option]) { self.model.floatEnabled.toggle() }
        item(view, "Show Playlist", key: "l") { self.model.show(.playlist) }
        item(view, "Show History", key: "h", modifiers: [.command, .shift]) { self.model.show(.history) }
        item(view, "Show All Bookmarks", key: "b", modifiers: [.command, .shift]) { self.model.show(.bookmarks) }
        view.addItem(.separator())
        item(view, "Enter Full Screen", key: "f", modifiers: [.command, .control]) { self.window.toggleFullScreen(nil) }
        for (title, scale) in [("Half Size", 0.5), ("Normal Size", 1.0), ("Double Size", 2.0)] {
            item(view, title) { self.window.setContentSize(NSSize(width: 960 * scale, height: 540 * scale + 100)) }
        }
        let aspect = submenu(view, "Aspect Ratio")
        for ratio in ["Original", "16:9", "4:3", "1:1", "2.35:1"] { item(aspect, ratio) { self.model.engine?.setProperty("video-aspect-override", value: ratio == "Original" ? "-1" : ratio) } }
        playbackMenu = submenu(bar, "Playback"); playbackMenu.delegate = self
        playItem = item(playbackMenu, "Play", key: " ", modifiers: []) { self.model.togglePlayback() }
        item(playbackMenu, "Stop", key: ".") { self.model.stop() }
        item(playbackMenu, "Jump to Beginning") { self.model.seek(0) }
        item(playbackMenu, "Jump to Time…", key: "j") {
            guard let text = self.model.textPrompt("Jump to time (seconds or HH:MM:SS)", initial: timestamp(self.model.position)) else { return }
            let parts = text.split(separator: ":").compactMap { Double($0) }
            guard !parts.isEmpty else { return }; self.model.seek(parts.reduce(0) { $0 * 60 + $1 })
        }
        item(playbackMenu, "Back 10 Seconds", key: "\u{f702}", modifiers: []) { self.model.skip(-10) }
        item(playbackMenu, "Forward 10 Seconds", key: "\u{f703}", modifiers: []) { self.model.skip(10) }
        item(playbackMenu, "Previous", key: "\u{f702}") { self.model.adjacent(-1) }
        item(playbackMenu, "Next", key: "\u{f703}") { self.model.adjacent(1) }
        item(playbackMenu, "Next Video Frame", key: "e", modifiers: []) { self.model.stepFrame() }
        item(playbackMenu, "Previous Video Frame", key: "e", modifiers: .shift) { self.model.stepFrame(true) }
        playbackMenu.addItem(.separator())
        item(playbackMenu, "Bookmark Current Position", key: "b") { self.model.addBookmark() }
        let namedBookmark = item(playbackMenu, "Add Named Bookmark…", key: "b", modifiers: .option) { self.model.addBookmark(named: true) }
        (namedBookmark.target as? MenuAction)?.available = { [weak self] in
            self?.model.libraryReady == true && self?.model.loaded == true && self?.canUseFocusedPlaybackShortcuts == true
        }
        bookmarkMenu = submenu(playbackMenu, "Bookmarks from All Files"); bookmarkMenu.delegate = self
        item(playbackMenu, "Import Bookmarks…") { self.model.importBookmarks() }
        item(playbackMenu, "Export Bookmarks…") { self.model.exportBookmarks() }
        chapterMenu = submenu(playbackMenu, "Chapters"); chapterMenu.delegate = self
        item(playbackMenu, "Choose Disc Title…") { self.model.chooseDiscTitle() }
        item(playbackMenu, "Use Longest Disc Title") { self.model.chooseDiscTitle(automatic: true) }
        let loop = submenu(playbackMenu, "A–B Loop")
        item(loop, "Set Starting Point", key: "a", modifiers: [.command, .option]) { self.model.setLoopA() }
        item(loop, "Set Return Point", key: "b", modifiers: [.command, .option]) { self.model.setLoopB() }
        item(loop, "Cancel") { self.model.clearLoop() }
        let repeatMenu = submenu(playbackMenu, "Repeat")
        for mode in RepeatMode.allCases { item(repeatMenu, mode.rawValue) { self.model.repeatMode = mode } }
        item(playbackMenu, "Shuffle") { self.model.shuffle.toggle() }
        playbackMenu.addItem(.separator())
        item(playbackMenu, "Increase Speed", key: "]") { self.model.changeSpeed(self.model.speed + 0.1) }
        item(playbackMenu, "Decrease Speed", key: "[") { self.model.changeSpeed(self.model.speed - 0.1) }
        item(playbackMenu, "Reset to Normal Speed", key: "\\") { self.model.changeSpeed(1) }
        item(playbackMenu, "Playback Settings…") { self.model.settingsOpen = true }
        let audio = submenu(bar, "Audio")
        item(audio, "Mute", key: "m") { self.model.toggleMute() }
        item(audio, "Volume Up", key: "\u{f700}", modifiers: []) { self.model.changeVolume(self.model.volume + 5) }
        item(audio, "Volume Down", key: "\u{f701}", modifiers: []) { self.model.changeVolume(self.model.volume - 5) }
        audioMenu = submenu(audio, "Audio Track"); audioMenu.delegate = self
        item(audio, "Use External Audio…") { self.model.openPanel(audio: true) }
        let subs = submenu(bar, "Subtitles")
        item(subs, "Add Subtitles from File…") { self.model.openPanel(subtitles: true) }
        item(subs, "Show / Hide Subtitles", key: "v", modifiers: []) {
            self.model.subtitlesVisible.toggle(); self.model.engine?.setProperty("sub-visibility", value: self.model.subtitlesVisible ? "yes" : "no")
        }
        subtitleMenu = submenu(subs, "Subtitle Track"); subtitleMenu.delegate = self
        item(subs, "Increase Size") { self.model.subtitleScale += 0.1; self.model.engine?.setProperty("sub-scale", value: String(self.model.subtitleScale)) }
        item(subs, "Decrease Size") { self.model.subtitleScale = max(0.2, self.model.subtitleScale - 0.1); self.model.engine?.setProperty("sub-scale", value: String(self.model.subtitleScale)) }
        let windows = submenu(bar, "Window"); NSApp.windowsMenu = windows
        item(windows, "Minimize", key: "m", modifiers: [.command, .option]) { self.window.miniaturize(nil) }
        item(windows, "Zoom") { self.window.zoom(nil) }
        let help = submenu(bar, "Help")
        item(help, "Playback Support…") {
            let runtime = self.model.runtimeCapabilities
            let alert = NSAlert()
            alert.messageText = "Playback Support"
            alert.informativeText = "\(runtime["mpv"] as? String ?? "Runtime version unavailable")\nFFmpeg \(runtime["ffmpeg"] as? String ?? "version unavailable")\n\nVVC: \(runtime["vvc"] as? Bool == true ? "Available" : "Not included")\nProRes RAW: \(runtime["prores_raw"] as? Bool == true ? "Available" : "Not included")\nMIDI: uses macOS General MIDI instruments when available.\n\nSupported codecs do not guarantee every file variant. This player provides playback only."
            alert.runModal()
        }
        item(help, "Keyboard Shortcuts") {
            let alert = NSAlert(); alert.messageText = "Keyboard Shortcuts"
            alert.informativeText = "⌘A — About Lola Player (outside text fields)\n1 — Show full interface\n2 — Media only with progress bar\nSpace — Play / Pause\n← / → — Seek 10 seconds\n↑ / ↓ — Volume\n⌘B — Save bookmark\n⌥B — Save named bookmark\n⇧⌘B — All bookmarks\n⇧⌘H — History\n⌥⌘T — Float on Top while playing\n⌘L — Playlist\n⌘O — Open file\n⌃⌘F — Full screen\n⌘[ / ⌘] — Playback speed\n⌘\\ — Reset speed to 1×\nE / ⇧E — Next / previous frame"
            alert.runModal()
        }
    }
    func menuNeedsUpdate(_ menu: NSMenu) {
        floatItem?.state = model.floatEnabled ? .on : .off; rememberWindowItem?.state = model.rememberWindowGeometry ? .on : .off; playItem?.title = model.paused ? "Play" : "Pause"
        if menu === recentMenu {
            menu.removeAllItems()
            for record in model.historyRecords.prefix(30) { item(menu, record.name) { self.model.play(record.id) } }
            menu.addItem(.separator()); item(menu, "Show Full History") { self.model.show(.history) }
        } else if menu === bookmarkMenu {
            menu.removeAllItems(); item(menu, "Manage All Bookmarks…") { self.model.show(.bookmarks) }
            menu.addItem(.separator())
            for record in model.records where !record.bookmarks.isEmpty {
                let group = submenu(menu, record.name)
                for bookmark in record.bookmarks { item(group, "\(timestamp(bookmark.seconds)) — \(bookmark.title)") { self.model.playBookmark(record.id, bookmark: bookmark) } }
            }
        } else if menu === audioMenu || menu === subtitleMenu {
            menu.removeAllItems(); let audio = menu === audioMenu
            item(menu, "Disabled") { self.model.engine?.setProperty(audio ? "aid" : "sid", value: "no") }
            for track in model.tracks where track["type"] as? String == (audio ? "audio" : "sub") {
                guard let id = track["id"] as? Int else { continue }
                let title = ["Track \(id)", track["title"] as? String, track["lang"] as? String, track["codec"] as? String].compactMap { $0 }.joined(separator: " · ")
                let entry = item(menu, title) { self.model.engine?.setProperty(audio ? "aid" : "sid", value: String(id)) }
                entry.state = track["selected"] as? Bool == true ? .on : .off
            }
        } else if menu === chapterMenu {
            menu.removeAllItems()
            for (i, chapter) in model.chapters.enumerated() {
                let title = chapter["title"] as? String ?? "Chapter \(i + 1)"
                let seconds = chapter["time"] as? Double ?? 0
                item(menu, "\(timestamp(seconds)) · \(title)") { self.model.seek(seconds) }
            }
        }
    }
}
