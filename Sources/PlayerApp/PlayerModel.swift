import AppKit
import SwiftUI
import Observation
import PlayerCore
import CMpv

enum LibraryTab: String, CaseIterable { case playlist = "Playlist", history = "History", bookmarks = "Bookmarks" }

@Observable final class PlayerModel {
    private let playbackWake = PlaybackWake()
    private var playbackSampleTime = ProcessInfo.processInfo.systemUptime
    private var unsavedPlayedSeconds = 0.0
    var playlistReorderTargeted = false
    var playlistDropBefore: UUID?
    var playlistDropTarget = false
    var library: MediaLibrary
    var revision = 0
    var queue: [UUID] = [] {
        didSet {
            if !CommandLine.arguments.contains("--smoke-test") { UserDefaults.standard.set(queue.map(\.uuidString), forKey: "playlist") }
        }
    }
    var currentID: UUID?
    var position = 0.0
    var duration = 0.0
    var paused = true
    var loaded = false
    var buffering = false
    var ended = false
    var failed = false
    var speed = 1.0
    var volume = 100.0
    var muted = false
    private(set) var mediaOnly = false
    private(set) var mediaAspectRatio = 0.0
    @ObservationIgnored private var fullInterfaceSize: NSSize?
    @ObservationIgnored private var fullInterfaceMinimum: NSSize?
    @ObservationIgnored private var fullInterfaceTitleHeight: CGFloat = 0
    var sidebar = false { didSet { libraryWindowChanged?() } }
    @ObservationIgnored var libraryWindowChanged: (() -> Void)?
    @ObservationIgnored var revealLibrary: (() -> Void)?
    @ObservationIgnored private var changingInterface = false
    var keepRunningWhenWindowCloses = UserDefaults.standard.bool(forKey: "keepRunningWhenWindowCloses") {
        didSet {
            guard !CommandLine.arguments.contains("--smoke-test") else { return }
            UserDefaults.standard.set(keepRunningWhenWindowCloses, forKey: "keepRunningWhenWindowCloses")
        }
    }
    var rememberWindowGeometry = UserDefaults.standard.object(forKey: "rememberWindowGeometry") as? Bool ?? true {
        didSet {
            guard !CommandLine.arguments.contains("--smoke-test") else { return }
            UserDefaults.standard.set(rememberWindowGeometry, forKey: "rememberWindowGeometry")
            if rememberWindowGeometry { saveWindowGeometry() }
            else { UserDefaults.standard.removeObject(forKey: "playerWindowFrame") }
        }
    }
    var tab: LibraryTab = .playlist
    var search = ""
    var error: String?
    var message: String?
    var messageInMediaOnly = false
    var floatStatusVisible = false
    var tracks: [[String: Any]] = []
    var chapters: [[String: Any]] = []
    var repeatMode: RepeatMode = .off {
        didSet {
            if repeatMode == .folder { refreshFolder() }
            systemMediaControls?.update()
        }
    }
    var shuffle = false
    var loopA: Double?
    var loopB: Double?
    var audioDelay = 0.0
    var subtitleDelay = 0.0
    var subtitleScale = 1.0
    var subtitlesVisible = true
    var settingsOpen = false
    var scrubbing = false
    var scrubPosition = 0.0
    var dropTarget = false
    var floatEnabled = UserDefaults.standard.bool(forKey: "floatEnabled") {
        didSet {
            UserDefaults.standard.set(floatEnabled, forKey: "floatEnabled")
            lastFloatingState = nil
            applyWindowLevel()
        }
    }
    var rememberPosition = UserDefaults.standard.object(forKey: "rememberPosition") as? Bool ?? true {
        didSet { UserDefaults.standard.set(rememberPosition, forKey: "rememberPosition") }
    }
    var autoplay = UserDefaults.standard.object(forKey: "autoplay") as? Bool ?? true {
        didSet { UserDefaults.standard.set(autoplay, forKey: "autoplay") }
    }
    var promptForBookmark = UserDefaults.standard.bool(forKey: "promptForBookmark") {
        didSet { UserDefaults.standard.set(promptForBookmark, forKey: "promptForBookmark") }
    }
    var automaticUpdateChecks = UserDefaults.standard.object(forKey: "automaticUpdateChecks") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(automaticUpdateChecks, forKey: "automaticUpdateChecks")
            if !automaticUpdateChecks {
                updateCheckTask?.cancel()
                if updateAvailability == .checking { updateAvailability = .notChecked }
                availableUpdate = nil
                updateCheckStatus = "Automatic update checks are off."
            }
            startAutomaticUpdateChecks()
        }
    }
    var updateAvailability: UpdateAvailability = .notChecked
    var availableUpdate: ReleaseUpdate?
    var updateCheckStatus = ""
    @ObservationIgnored var automaticUpdateTask: Task<Void, Never>?
    @ObservationIgnored var updateCheckTask: Task<Void, Never>?
    weak var window: NSWindow?
    @ObservationIgnored let timelinePreview = TimelinePreview()
    @ObservationIgnored let playbackClickFeedback = PlaybackClickFeedback()
    @ObservationIgnored private(set) var runtimeLibraryPath: String?
    @ObservationIgnored var engine: LPMpvView?
    @ObservationIgnored var timer: Timer?
    @ObservationIgnored var ticks = 0
    @ObservationIgnored var pendingURLs: [URL] = []
    @ObservationIgnored var pendingSeek: Double?
    @ObservationIgnored var pendingLocation: String?
    @ObservationIgnored var loadingSince: Date?
    @ObservationIgnored var handledEnd = false
    @ObservationIgnored var messageUntil = Date.distantPast
    @ObservationIgnored var floatStatusTimer: Timer?
    @ObservationIgnored var lastFloatingState: Bool?
    @ObservationIgnored var folderIDs: [UUID] = []
    @ObservationIgnored var systemMediaControls: SystemMediaControls?
    @ObservationIgnored private var openingPlaylists = Set<URL>()
    @ObservationIgnored private var midi: MIDIPlayback?
    @ObservationIgnored let runtimeCapabilities: [String: Any] = {
        guard let url = Bundle.main.url(forResource: "RuntimeCapabilities", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let result = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return result
    }()

    var current: MediaRecord? { currentID.flatMap { library.record($0) } }
    var records: [MediaRecord] { _ = revision; return library.recent }
    var historyRecords: [MediaRecord] { _ = revision; return library.history }
    var floating: Bool { PlaybackPolicy.shouldFloat(enabled: floatEnabled, loaded: loaded, paused: paused, buffering: buffering, ended: ended, failed: failed) }

    private(set) var libraryReady = false
    @ObservationIgnored private var shuttingDown = false
    @ObservationIgnored private var importing = false

    init() {
        let smokeIndex = CommandLine.arguments.firstIndex(of: "--smoke-test")
        let smokeRoot = smokeIndex.flatMap { index in CommandLine.arguments.count > index + 1 ? URL(fileURLWithPath: CommandLine.arguments[index + 1]).appendingPathComponent("library-\(UUID().uuidString)") : nil }
        let root = smokeRoot ?? ProcessInfo.processInfo.environment["LUMEN_DATA_DIR"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("LumenPlayer")
        library = MediaLibrary(fileURL: root.appendingPathComponent("library.json"), records: [])
    }

    func loadLibrary() async {
        let url = library.fileURL
        let result = await Task.detached {
            Result { try MediaLibrary(fileURL: url).records }
        }.value
        guard !shuttingDown else { return }
        switch result {
        case .success(let records): library = MediaLibrary(fileURL: url, records: records)
        case .failure(let problem):
            library = MediaLibrary(fileURL: url.deletingLastPathComponent().appendingPathComponent("library-recovery-\(UUID().uuidString).json"), records: [])
            error = "Could not read your library. The original file is preserved at \(url.path). \(problem.localizedDescription)"
        }
        library.enableBackgroundSaving()
        if !CommandLine.arguments.contains("--smoke-test") {
            let known = Set(library.records.map(\.id))
            let stored = UserDefaults.standard.stringArray(forKey: "playlist")
            queue = stored.map { $0.compactMap(UUID.init(uuidString:)).filter { known.contains($0) } } ?? library.recent.reversed().map(\.id)
        }
        libraryReady = true
    }

    func importElmedia(automatic: Bool = false) {
        guard libraryReady, !importing, !shuttingDown else { return }
        if automatic && (!library.records.isEmpty || UserDefaults.standard.bool(forKey: "didAttemptElmediaImport")) { return }
        importing = true
        let source = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Elmedia Player")
        // Import into an isolated snapshot, then merge on the UI actor so user edits survive.
        Task {
            let result = await Task.detached {
                Result { () throws -> [MediaRecord] in
                    let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("lola-import-\(UUID().uuidString).json")
                    defer { try? FileManager.default.removeItem(at: temporary) }
                    let imported = MediaLibrary(fileURL: temporary, records: [])
                    if FileManager.default.fileExists(atPath: source.path) { _ = try imported.importElmedia(from: source) }
                    return imported.records
                }
            }.value
            importing = false
            guard !shuttingDown else { return }
            switch result {
            case .success(let records):
                perform { try library.mergeImported(records) }
                if automatic { UserDefaults.standard.set(true, forKey: "didAttemptElmediaImport") }
                if !records.isEmpty { notify("Imported Elmedia library"); show(.bookmarks) }
            case .failure(let problem): error = problem.localizedDescription
            }
        }
    }

    func attach(_ view: LPMpvView) {
        guard engine == nil, !shuttingDown else { return }
        engine = view
        let bundled = Bundle.main.bundleURL.appendingPathComponent("Contents/Frameworks/libmpv.2.dylib").path
        let candidates = [ProcessInfo.processInfo.environment["LUMEN_MPV_LIBRARY"], bundled,
                          "/opt/homebrew/lib/libmpv.2.dylib", "/usr/local/lib/libmpv.2.dylib", "/Applications/IINA.app/Contents/Frameworks/libmpv.2.dylib"].compactMap { $0 }
        guard let path = candidates.first(where: { FileManager.default.fileExists(atPath: $0) }), view.startEngine(path) else {
            error = view.engineError ?? "libmpv is missing. Run scripts/build-app.sh to bundle the playback runtime."; failed = true; return
        }
        runtimeLibraryPath = path
        timer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        let pending = pendingURLs; pendingURLs = []
        if !pending.isEmpty { open(pending) }
    }

    func perform(_ operation: () throws -> Void) {
        do { try operation(); revision += 1 } catch { self.error = error.localizedDescription }
    }
    func notify(_ text: String, inMediaOnly: Bool = false) { message = text; messageInMediaOnly = inMediaOnly; messageUntil = Date().addingTimeInterval(2.5) }
    func persistPosition() {
        guard let id = currentID, loaded else { return }
        perform {
            try library.batchUpdates {
                try library.recordPlayback(id, seconds: unsavedPlayedSeconds, finished: ended)
                try library.updatePosition(id, seconds: ended ? 0 : position, duration: duration)
            }
            unsavedPlayedSeconds = 0
        }
    }
    func movePlaylistItem(_ id: UUID, before destination: UUID?) {
        let reordered = PlaybackOrder.moving(queue, item: id, before: destination)
        if reordered != queue { queue = reordered }
    }

    @discardableResult func dropOnPlaylist(_ providers: [NSItemProvider]) -> Bool {
        guard libraryReady else { return false }
        let providers = providers.filter { $0.canLoadObject(ofClass: URL.self) }
        guard !providers.isEmpty else { return false }
        Task {
            var urls: [URL] = []
            for provider in providers {
                let url: URL? = await withCheckedContinuation { continuation in
                    _ = provider.loadObject(ofClass: URL.self) { url, _ in continuation.resume(returning: url) }
                }
                if let url { urls.append(url) }
            }
            await appendPlaylistFiles(urls)
        }
        return true
    }

    func appendPlaylistFiles(_ urls: [URL]) async {
        guard libraryReady, !shuttingDown else { return }
        let result = await Task.detached { Result { try MediaInput.playlistDropFiles(urls) } }.value
        guard !shuttingDown else { return }
        switch result {
        case .success(let files):
            perform {
                let ids = try library.register(files)
                var known = Set(queue)
                queue += ids.filter { known.insert($0).inserted }
            }
        case .failure(let problem): error = "Could not add dropped files: \(problem.localizedDescription)"
        }
    }

    func open(_ urls: [URL]) {
        guard libraryReady, engine?.engineReady == true else { pendingURLs += urls; return }
        var ids: [UUID] = []
        for url in urls {
            if url.pathExtension.lowercased() == "m3u" || url.pathExtension.lowercased() == "m3u8", url.isFileURL {
                do {
                    let identity = url.standardizedFileURL.resolvingSymlinksInPath()
                    guard openingPlaylists.count < 16, !openingPlaylists.contains(identity) else {
                        throw CocoaError(.fileReadCorruptFile, userInfo: [NSLocalizedDescriptionKey: "The playlist contains a cycle or exceeds 16 nested playlists."])
                    }
                    openingPlaylists.insert(identity)
                    defer { openingPlaylists.remove(identity) }
                    let text = try String(contentsOf: url, encoding: .utf8)
                    if MediaInput.isHLS(text) {
                        ids.append(try library.visit(url))
                    } else {
                        open(MediaInput.playlistItems(text, relativeTo: url))
                    }
                } catch { self.error = error.localizedDescription }
                continue
            }
            if url.isFileURL && ["srt", "ass", "ssa", "vtt", "sub"].contains(url.pathExtension.lowercased()) {
                engine?.command(["sub-add", url.path, "select"]); continue
            }
            var directory: ObjCBool = false
            if url.isFileURL, FileManager.default.fileExists(atPath: url.path, isDirectory: &directory), directory.boolValue {
                if let (root, kind) = MediaInput.discFolder(url) {
                    perform { ids.append(try library.visitDisc(root, kind: kind)) }
                    continue
                }
                do { open(try MediaInput.playlistDropFiles([url])) }
                catch { self.error = error.localizedDescription }; continue
            }
            if url.isFileURL && url.pathExtension.lowercased() == "iso" {
                let alert = NSAlert()
                alert.messageText = "Open Disc Image"
                alert.informativeText = "Choose the disc type for \(url.lastPathComponent). The image must contain accessible, unencrypted media. Disc menus are not supported."
                alert.addButton(withTitle: "DVD"); alert.addButton(withTitle: "Blu-ray"); alert.addButton(withTitle: "Cancel")
                let response = alert.runModal()
                if response == .alertFirstButtonReturn || response == .alertSecondButtonReturn {
                    perform { ids.append(try library.visitDisc(url, kind: response == .alertFirstButtonReturn ? .dvd : .bluray)) }
                }
                continue
            }
            perform { ids.append(try library.visit(url)) }
        }
        for id in ids where !queue.contains(id) { queue.append(id) }
        if let first = ids.first { play(first) }
    }

    func play(_ id: UUID, at bookmark: Double? = nil) {
        guard let url = library.resolve(id) else { return }
        if ["vvc", "h266"].contains(url.pathExtension.lowercased()), runtimeCapabilities["vvc"] as? Bool == false {
            error = "This build does not contain a VVC decoder. A newer compatible playback runtime is required."
            return
        }
        if let kind = library.record(id)?.discKind, runtimeCapabilities[kind.rawValue] as? Bool == false {
            error = "This build does not include \(kind == .dvd ? "DVD" : "Blu-ray") disc reading. Individual video files can still be opened."
            return
        }
        if url.isFileURL && !FileManager.default.fileExists(atPath: url.path) {
            error = "The file \(url.lastPathComponent) is unavailable. Use Relocate File in History to find it."; return
        }
        persistPosition()
        if currentID == id, loaded, pendingLocation == nil, let bookmark {
            seek(bookmark); setPaused(false); return
        }
        midi?.shutdown(); midi = nil
        guard engine?.engineReady == true else { pendingURLs.append(url); return }
        if !queue.contains(id) { queue.append(id) }
        perform { _ = try library.visit(url) }
        playbackClickFeedback.clear(); timelinePreview.clear(); mediaAspectRatio = 0
        unsavedPlayedSeconds = 0; playbackSampleTime = ProcessInfo.processInfo.systemUptime
        currentID = id; position = 0; duration = 0; loaded = false; ended = false; failed = false
        if repeatMode == .folder { refreshFolder() }
        paused = !autoplay; buffering = true; handledEnd = false; loopA = nil; loopB = nil
        pendingSeek = bookmark ?? (rememberPosition ? library.record(id)?.position : 0)
        if bookmark != nil { paused = false }
        window?.title = library.record(id)?.name ?? "Lola Player"
        if url.isFileURL && ["mid", "midi"].contains(url.pathExtension.lowercased()) {
            engine?.command(["stop"])
            pendingLocation = nil; loadingSince = nil; tracks = []; chapters = []
            do {
                let playback = try MIDIPlayback(url: url)
                midi = playback; duration = playback.duration
                playback.rate = speed; playback.volume = muted ? 0 : volume / 100
                playback.seek(min(pendingSeek ?? 0, max(0, duration - 0.1)))
                position = playback.position; pendingSeek = nil
                if !paused { try playback.play() }
                loaded = true; buffering = false
            } catch {
                midi?.shutdown(); midi = nil; failed = true; buffering = false
                self.error = "MIDI playback: \(error.localizedDescription)"
            }
            applyWindowLevel(); systemMediaControls?.update(force: true)
            return
        }
        if let kind = library.record(id)?.discKind {
            engine?.setProperty("options/\(kind.deviceOption)", value: url.path)
            pendingLocation = kind.playbackURL(title: library.record(id)?.discTitle)
        } else {
            pendingLocation = url.isFileURL ? url.path : url.absoluteString
        }
        loadingSince = Date()
        engine?.setProperty("pause", value: "yes")
        engine?.command(["loadfile", pendingLocation!, "replace"])
        engine?.setProperty("ab-loop-a", value: "no"); engine?.setProperty("ab-loop-b", value: "no")
        window?.title = library.record(id)?.name ?? "Lola Player"
        applyWindowLevel()
        systemMediaControls?.update()
    }

    func tick() {
        samplePlaybackTime()
        guard let engine, engine.engineReady else { return }
        if let problem = library.takeSaveError() { error = "Could not save library: \(problem)" }
        ticks += 1
        if let midi {
            position = midi.position
            if let loopA, let loopB, position >= loopB { midi.seek(loopA); position = loopA }
            if !paused && position >= duration {
                midi.pause(); ended = true; paused = true
                if !handledEnd { handledEnd = true; persistPosition(); handleEnd() }
            }
            if ticks % 34 == 0 { persistPosition() }
            if message != nil && Date() > messageUntil { message = nil }
            applyWindowLevel(); systemMediaControls?.update()
            return
        }
        let errors = engine.drainErrors()
        if let problem = errors.first {
            error = "Playback: \(problem)"
            if engine.playbackFailed || pendingLocation != nil {
                failed = true; loadingSince = nil; pendingLocation = nil; buffering = false
            }
        }
        if let location = pendingLocation {
            if engine.fileLoaded, engine.stringProperty("path") == location, !engine.flagProperty("idle-active") {
                loaded = true; buffering = false; pendingLocation = nil; loadingSince = nil
                duration = engine.numberProperty("duration")
                let target = min(pendingSeek ?? 0, max(0, duration - 0.1)); pendingSeek = nil
                if duration > 0 { engine.command(["seek", String(target), "absolute+exact"]) }
                engine.setProperty("speed", value: String(speed))
                engine.setProperty("pause", value: paused ? "yes" : "no")
                tracks = engine.tracks(); chapters = engine.chapters()
                updateMediaGeometry()
                prepareTimelinePreviews()
            } else if let since = loadingSince, Date().timeIntervalSince(since) > 20 {
                pendingLocation = nil; loadingSince = nil; failed = true; buffering = false
                error = "The media could not be opened within 20 seconds. Check the file or network address."
            }
        } else if loaded && !failed {
            position = engine.numberProperty("time-pos"); duration = engine.numberProperty("duration")
            paused = engine.flagProperty("pause"); ended = engine.flagProperty("eof-reached")
            buffering = engine.flagProperty("paused-for-cache")
            if ended && !handledEnd { handledEnd = true; persistPosition(); handleEnd() }
        }
        if ticks % 34 == 0 { persistPosition() }
        if ticks % 10 == 0 && loaded { tracks = engine.tracks(); chapters = engine.chapters(); updateMediaGeometry(); prepareTimelinePreviews() }
        if message != nil && Date() > messageUntil { message = nil }
        applyWindowLevel()
        systemMediaControls?.update()
    }
    private func samplePlaybackTime() {
        let now = ProcessInfo.processInfo.systemUptime
        let elapsed = now - playbackSampleTime
        playbackSampleTime = now
        if loaded && !paused && !buffering && !ended && !failed && elapsed >= 0 && elapsed < 1 {
            unsavedPlayedSeconds += elapsed
        }
    }
    func applyWindowLevel() {
        playbackWake.update(active: !shuttingDown && loaded && !paused && !ended && !failed)
        let active = floating
        let level: NSWindow.Level = active ? .floating : .normal
        if window?.level != level { window?.level = level }
        if !floatEnabled {
            floatStatusTimer?.invalidate(); floatStatusVisible = false
        } else if lastFloatingState != active {
            floatStatusTimer?.invalidate(); floatStatusVisible = true
            floatStatusTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.floatStatusVisible = false }
            }
        }
        lastFloatingState = active
        libraryWindowChanged?()
    }
    func setPaused(_ value: Bool) {
        samplePlaybackTime()
        guard loaded else { return }
        if !value && ended { seek(0) }
        if let midi {
            do { if value { midi.pause() } else { try midi.play() } }
            catch { self.error = "MIDI playback: \(error.localizedDescription)"; return }
        }
        paused = value; engine?.setProperty("pause", value: value ? "yes" : "no"); applyWindowLevel()
        systemMediaControls?.update(force: true)
        if value { persistPosition() }
    }
    func togglePlayback() { setPaused(!paused) }
    func togglePlaybackFromVideo() {
        let previous = paused
        togglePlayback()
        if paused != previous { playbackClickFeedback.show(paused: paused) }
    }
    func chooseDiscTitle(automatic: Bool = false) {
        guard let record = current, let kind = record.discKind else {
            notify("Open a DVD or Blu-ray folder/image first")
            return
        }
        var title: Int?
        if !automatic {
            let minimum = kind == .dvd ? 1 : 0
            guard let text = textPrompt("Disc title number (starting at \(minimum))", initial: String(record.discTitle ?? minimum)),
                  let value = Int(text), value >= minimum else { return }
            title = value
        }
        persistPosition(); loaded = false
        perform { try library.setDiscTitle(record.id, title: title) }
        play(record.id, at: 0)
    }
    func playBookmark(_ record: UUID, bookmark: MediaBookmark) {
        if currentID == record, library.record(record)?.discTitle != bookmark.discTitle {
            persistPosition(); loaded = false
        }
        perform { try library.setDiscTitle(record, title: bookmark.discTitle) }
        play(record, at: bookmark.seconds)
    }
    func seek(_ seconds: Double) {
        guard loaded, seconds.isFinite else { return }
        let target = min(max(0, seconds), max(0, duration))
        if let midi { midi.seek(target) }
        else { engine?.command(["seek", String(target), "absolute+exact"]) }
        position = target; ended = false; handledEnd = false
        systemMediaControls?.update(force: true)
    }
    func skip(_ seconds: Double) { seek(position + seconds) }
    func stop() { setPaused(true); seek(0); ended = false; persistPosition(); applyWindowLevel() }
    func changeSpeed(_ value: Double) { speed = min(max(value, 0.25), 4); midi?.rate = speed; engine?.setProperty("speed", value: String(speed)); notify(String(format: "Speed %.2g×", speed)) }
    func changeVolume(_ value: Double) { volume = min(max(value, 0), 100); midi?.volume = muted ? 0 : volume / 100; engine?.setProperty("volume", value: String(volume)) }
    func adjustVolumeByScroll(_ delta: Double) {
        guard delta.isFinite, NSApp.isActive, window?.isKeyWindow == true, !settingsOpen,
              window?.attachedSheet == nil, NSApp.modalWindow == nil else { return }
        let previous = volume
        changeVolume(volume + delta)
        if volume != previous { notify("Volume \(Int(volume.rounded()))%" + (muted ? " · Muted" : ""), inMediaOnly: true) }
    }
    func toggleMute() { muted.toggle(); midi?.volume = muted ? 0 : volume / 100; engine?.setProperty("mute", value: muted ? "yes" : "no") }
    func stepFrame(_ backwards: Bool = false) { guard midi == nil else { return }; setPaused(true); engine?.command([backwards ? "frame-back-step" : "frame-step"]) }
    func adjacent(_ offset: Int) {
        guard let id = adjacentID(offset) else { return }
        play(id, at: 0)
    }
    var playbackSequence: [UUID] {
        let ids: [UUID]
        switch repeatMode {
        case .off, .track: ids = queue
        case .folder: ids = folderIDs
        case .library: ids = PlaybackOrder.library(library.records)
        }
        return ids.filter { id in
            guard let url = library.resolve(id) else { return false }
            return !url.isFileURL || FileManager.default.fileExists(atPath: url.path)
        }
    }
    func adjacentID(_ offset: Int) -> UUID? {
        let ids = playbackSequence
        if shuffle, let id = ids.filter({ $0 != currentID }).randomElement() { return id }
        return PlaybackOrder.destination(in: ids, current: currentID, offset: offset, wrap: repeatMode.wraps)
    }
    func refreshFolder() {
        folderIDs = []
        guard let url = currentID.flatMap({ library.resolve($0) }), url.isFileURL else { return }
        perform { folderIDs = try library.register(MediaFormats.files(in: url.deletingLastPathComponent())) }
    }
    func cycleRepeatMode() {
        repeatMode = repeatMode.next
        notify(repeatMode.rawValue)
    }
    func handleEnd() {
        persistPosition()
        switch repeatMode {
        case .off:
            setPaused(true)
        case .track:
            seek(0); setPaused(false)
        case .folder, .library:
            if let id = adjacentID(1) { play(id, at: 0) }
            else { setPaused(true) }
        }
    }
    func setLoopA() { loopA = position; loopB = nil; engine?.setProperty("ab-loop-a", value: String(position)); engine?.setProperty("ab-loop-b", value: "no"); notify("A: \(timestamp(position))") }
    func setLoopB() {
        guard let loopA, position > loopA else { notify("Set A before B"); return }
        loopB = position; engine?.setProperty("ab-loop-b", value: String(position)); notify("A–B loop active")
    }
    func clearLoop() { loopA = nil; loopB = nil; engine?.setProperty("ab-loop-a", value: "no"); engine?.setProperty("ab-loop-b", value: "no") }
    func addBookmark() { addBookmark(named: false) }
    func addBookmark(named: Bool) {
        guard let id = currentID, loaded else { return }
        let seconds = position
        let title: String
        if named || promptForBookmark {
            guard let value = textPrompt("Bookmark at \(timestamp(seconds))", initial: "Bookmark \(timestamp(seconds))") else { return }; title = value
        } else { title = "Bookmark \(timestamp(seconds))" }
        perform { try library.addBookmark(id, seconds: seconds, title: title) }; notify("Saved bookmark at \(timestamp(seconds))")
    }
    func editBookmark(_ record: MediaRecord, _ bookmark: MediaBookmark) {
        let alert = NSAlert(); alert.messageText = "Edit Bookmark"; alert.addButton(withTitle: "Save"); alert.addButton(withTitle: "Cancel")
        let name = NSTextField(string: bookmark.title)
        let time = NSTextField(string: String(format: "%.3f", bookmark.seconds))
        let stack = NSStackView(views: [NSTextField(labelWithString: "Name"), name, NSTextField(labelWithString: "Time in seconds"), time])
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 6; stack.frame = NSRect(x: 0, y: 0, width: 360, height: 104)
        name.widthAnchor.constraint(equalToConstant: 360).isActive = true; time.widthAnchor.constraint(equalToConstant: 360).isActive = true
        alert.accessoryView = stack; alert.window.initialFirstResponder = name
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        guard let seconds = Double(time.stringValue), seconds.isFinite, seconds >= 0 else { error = "Enter a valid time in seconds."; return }
        perform { try library.editBookmark(record.id, bookmark: bookmark.id, title: name.stringValue, seconds: seconds) }
    }
    func removeBookmark(_ record: MediaRecord, _ bookmark: MediaBookmark) { perform { try library.removeBookmark(record.id, bookmark: bookmark.id) } }
    func removeAllBookmarks(_ record: MediaRecord) { perform { try library.removeAllBookmarks(record.id) } }
    func removeFromHistory(_ record: MediaRecord) { perform { try library.removeFromHistory(record.id) } }
    func emptyHistory() { perform { try library.emptyHistory() } }
    func removeFromPlaylist(_ record: MediaRecord) { queue.removeAll { $0 == record.id } }
    func updateMediaGeometry() {
        guard loaded, tracks.contains(where: { $0["type"] as? String == "video" && $0["albumart"] as? Bool != true }), let engine else { return }
        let override = engine.numberProperty("video-aspect-override")
        let width = engine.numberProperty("dwidth"), height = engine.numberProperty("dheight")
        let aspect = override > 0 ? override : (height > 0 ? width / height : 0)
        guard aspect.isFinite, aspect > 0, abs(aspect - mediaAspectRatio) > 0.0001 else { return }
        mediaAspectRatio = aspect
        if mediaOnly { fitMediaOnlyWindow() }
    }

    func mediaOnlySize(for proposed: NSSize) -> NSSize {
        let available = window?.screen?.visibleFrame.size ?? NSSize(width: 1600, height: 1000)
        return MediaWindowLayout.fittedSize(width: proposed.width, aspect: mediaAspectRatio, available: available) ?? proposed
    }

    func fitMediaOnlyWindow() {
        guard mediaOnly, let window, !window.styleMask.contains(.fullScreen), mediaAspectRatio > 0 else { return }
        var frame = window.frame
        let size = mediaOnlySize(for: frame.size)
        frame.origin.y += frame.height - size.height
        frame.size = size
        if let visible = window.screen?.visibleFrame {
            frame.origin.x = min(max(frame.minX, visible.minX), max(visible.minX, visible.maxX - frame.width))
            frame.origin.y = min(max(frame.minY, visible.minY), max(visible.minY, visible.maxY - frame.height))
        }
        window.setFrame(frame, display: true)
    }

    func restoreInterfaceSize(top: CGFloat? = nil) {
        guard let window, !window.styleMask.contains(.fullScreen) else { return }
        if let minimum = fullInterfaceMinimum { window.minSize = minimum }
        if let size = fullInterfaceSize {
            var frame = window.frame
            frame.origin.y = (top ?? frame.maxY) - size.height
            frame.size = size
            window.setFrame(frame, display: true)
        }
        fullInterfaceSize = nil; fullInterfaceMinimum = nil; fullInterfaceTitleHeight = 0
    }

    func didExitFullScreen() {
        if mediaOnly {
            if fullInterfaceSize == nil { fullInterfaceSize = window?.frame.size }
            fitMediaOnlyWindow()
        } else { restoreInterfaceSize() }
    }

    func restoreInterfaceMode(from defaults: UserDefaults = .standard) {
        guard !CommandLine.arguments.contains("--smoke-test") || defaults !== UserDefaults.standard else { return }
        setMediaOnly(defaults.bool(forKey: "mediaOnly"), defaults: defaults)
    }

    func pauseForWindowClose() {
        if loaded { setPaused(true) }
        else { paused = true; engine?.setProperty("pause", value: "yes") }
        playbackClickFeedback.clear()
    }

    func closePlayerWindow() { window?.performClose(nil) }

    func setMediaOnly(_ enabled: Bool, defaults: UserDefaults = .standard) {
        if !CommandLine.arguments.contains("--smoke-test") || defaults !== UserDefaults.standard {
            defaults.set(enabled, forKey: "mediaOnly")
        }
        guard enabled != mediaOnly else { return }
        guard let window else { mediaOnly = enabled; return }
        let fullScreen = window.styleMask.contains(.fullScreen)
        let originalFrame = window.frame
        changingInterface = true
        defer { changingInterface = false; saveWindowGeometry() }
        if enabled {
            if !fullScreen {
                fullInterfaceSize = originalFrame.size
                fullInterfaceTitleHeight = originalFrame.maxY - window.convertToScreen(window.contentLayoutRect).maxY
            }
            fullInterfaceMinimum = window.minSize
            window.minSize = NSSize(width: 100, height: 64)
        }
        mediaOnly = enabled
        window.titleVisibility = enabled ? .hidden : .visible
        if enabled { window.styleMask.insert(.fullSizeContentView) }
        else { window.styleMask.remove(.fullSizeContentView) }
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            window.standardWindowButton(button)?.isHidden = enabled
        }
        if enabled {
            if !fullScreen {
                // Keep the media's screen position: remove title space above it, rather than moving it into that space.
                var compactFrame = originalFrame
                compactFrame.size.height -= fullInterfaceTitleHeight
                window.setFrame(compactFrame, display: true)
            }
            fitMediaOnlyWindow()
        }
        else if !fullScreen { restoreInterfaceSize(top: originalFrame.maxY + fullInterfaceTitleHeight) }
    }

    func show(_ page: LibraryTab) { tab = page; sidebar = true; revealLibrary?() }

    func saveWindowGeometry(to defaults: UserDefaults = .standard) {
        guard rememberWindowGeometry, !changingInterface, let window,
              !window.styleMask.contains(.fullScreen),
              (NSApp.delegate as? AppDelegate)?.isFullScreenTransitioning != true,
              (!CommandLine.arguments.contains("--smoke-test") || defaults !== UserDefaults.standard) else { return }
        var frame = window.frame
        if mediaOnly, let size = fullInterfaceSize {
            frame.origin.y = frame.maxY + fullInterfaceTitleHeight - size.height
            frame.size = size
        }
        defaults.set(NSStringFromRect(frame), forKey: "playerWindowFrame")
    }
    func relocate(_ record: MediaRecord) {
        let panel = NSOpenPanel(); panel.message = "Locate \(record.name)"; panel.allowsMultipleSelection = false
        panel.canChooseDirectories = record.discKind != nil
        guard panel.runModal() == .OK, let url = panel.url else { return }
        perform {
            try library.relocate(record.id, to: record.discKind != nil ? (MediaInput.discFolder(url)?.0 ?? url) : url)
            play(record.id)
        }
    }
    func openPanel(subtitles: Bool = false, audio: Bool = false) {
        let panel = NSOpenPanel(); panel.allowsMultipleSelection = !subtitles && !audio; panel.canChooseDirectories = !subtitles && !audio
        panel.message = subtitles ? "Choose a subtitle file" : audio ? "Choose an external audio track" : "Open media files, folders, or playlists"
        guard panel.runModal() == .OK else { return }
        if subtitles, let url = panel.url { engine?.command(["sub-add", url.path, "select"]) }
        else if audio, let url = panel.url { engine?.command(["audio-add", url.path, "select"]) }
        else { open(panel.urls) }
    }
    func openURL() {
        guard let text = textPrompt("Open Media URL", initial: "https://"), let url = URL(string: text), ["http", "https", "rtsp", "rtmp"].contains(url.scheme?.lowercased() ?? "") else { return }
        open([url])
    }
    func savePlaylist() {
        let panel = NSSavePanel(); panel.nameFieldStringValue = "Playlist.m3u"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let lines = queue.compactMap { library.resolve($0) }.map { $0.isFileURL ? $0.path : $0.absoluteString }
        perform { try ("#EXTM3U\n" + lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8) }
    }
    func exportBookmarks() {
        let panel = NSSavePanel(); panel.nameFieldStringValue = "Bookmarks.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        perform { let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; try encoder.encode(records.filter { !$0.bookmarks.isEmpty }).write(to: url, options: .atomic) }
    }
    func importBookmarks() {
        let panel = NSOpenPanel(); panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        perform {
            let imported = try JSONDecoder().decode([MediaRecord].self, from: Data(contentsOf: url))
            for record in imported {
                let id = try library.visit(record.location)
                for bookmark in record.bookmarks where !(library.record(id)?.bookmarks.contains(where: { $0.seconds == bookmark.seconds && $0.title == bookmark.title }) ?? false) {
                    try library.addBookmark(id, seconds: bookmark.seconds, title: bookmark.title)
                }
            }
        }
    }
    func textPrompt(_ title: String, initial: String) -> String? {
        let alert = NSAlert(); alert.messageText = title; alert.addButton(withTitle: "Save"); alert.addButton(withTitle: "Cancel")
        let input = NSTextField(string: initial); input.frame = NSRect(x: 0, y: 0, width: 360, height: 24); alert.accessoryView = input
        alert.window.initialFirstResponder = input
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }; return input.stringValue
    }
    func shutdown() { shuttingDown = true; playbackWake.update(active: false); samplePlaybackTime(); playbackClickFeedback.clear(); saveWindowGeometry(); timelinePreview.clear(); automaticUpdateTask?.cancel(); updateCheckTask?.cancel(); timer?.invalidate(); floatStatusTimer?.invalidate(); systemMediaControls?.stop(); persistPosition(); do { try library.flush() } catch { NSLog("Library save failed: %@", error.localizedDescription) }; midi?.shutdown(); engine?.shutdown(); window?.level = .normal }
}
