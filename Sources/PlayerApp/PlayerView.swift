import SwiftUI
import AppKit
import UniformTypeIdentifiers
import PlayerCore
import CMpv

struct VideoSurface: NSViewRepresentable {
    let model: PlayerModel
    func makeNSView(context: Context) -> LPMpvView {
        let view = LPMpvView(frame: NSRect(x: 0, y: 0, width: 960, height: 540))
        model.attach(view); return view
    }
    func updateNSView(_ view: LPMpvView, context: Context) {}
}

struct PlayerView: View {
    @Bindable var model: PlayerModel
    @FocusState private var searchFocused: Bool
    private static let welcomePhoto: NSImage? = {
        let bundled = Bundle.main.url(forResource: "WelcomeNature", withExtension: "png")
        let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Resources/WelcomeNature.png")
        return NSImage(contentsOf: bundled ?? source)
    }()

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                ZStack {
                    Color.black
                    VideoSurface(model: model)
                    if model.currentID == nil {
                        welcomeBackground
                        VStack(spacing: 16) {
                            Image(systemName: "play.rectangle").font(.system(size: 55, weight: .ultraLight)).foregroundStyle(.white.opacity(0.7))
                            Text("Lola Player").font(.system(size: 25, weight: .medium))
                            Text("Drop a video, an audio file, or a folder").foregroundStyle(.white.opacity(0.8))
                            Button("Open File…") { model.openPanel() }.keyboardShortcut("o").controlSize(.large)
                            if let recent = model.historyRecords.first {
                                Button { model.play(recent.id) } label: {
                                    Label("Resume \(recent.name)", systemImage: "clock.arrow.circlepath").lineLimit(1)
                                }.buttonStyle(.plain).foregroundStyle(.white.opacity(0.8)).padding(.top, 6)
                            }
                        }.padding(40).shadow(color: .black.opacity(0.5), radius: 12, y: 2)
                    }
                    if model.buffering {
                        ProgressView("Opening media…").padding(20).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                    }
                    VStack {
                        HStack {
                            if model.floatEnabled && model.floatStatusVisible {
                                Label(model.floating ? "Floating" : "Float on Top · paused", systemImage: model.floating ? "pin.fill" : "pin.slash")
                                    .font(.system(size: 11)).padding(.horizontal, 9).padding(.vertical, 6)
                                    .background(.black.opacity(0.65), in: Capsule()).padding(14)
                            }
                            Spacer()
                        }
                        Spacer()
                        if let message = model.message {
                            Text(message).font(.system(size: 13, weight: .medium)).padding(10).background(.ultraThinMaterial, in: Capsule()).padding(.bottom, 22)
                        }
                    }.allowsHitTesting(false)
                }
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { model.window?.toggleFullScreen(nil) }
                .onTapGesture { model.togglePlayback() }
                .contextMenu {
                    Button(model.paused ? "Play" : "Pause") { model.togglePlayback() }
                    Button("Bookmark Current Position") { model.addBookmark() }
                    Toggle("Float on Top", isOn: $model.floatEnabled)
                    Divider()
                    Button("Open File…") { model.openPanel() }
                    Button("Show All Bookmarks") { model.show(.bookmarks) }
                    Button("Enter Full Screen") { model.window?.toggleFullScreen(nil) }
                }
                controls
            }
            if model.sidebar { libraryPanel.frame(width: 330) }
        }
        .background(Color(nsColor: NSColor(white: 0.12, alpha: 1)))
        .preferredColorScheme(.dark)
        .onDrop(of: [.fileURL, .url], isTargeted: $model.dropTarget) { providers in
            for provider in providers {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    Task { @MainActor in model.open([url]) }
                }
            }
            return true
        }
        .overlay { if model.dropTarget { RoundedRectangle(cornerRadius: 8).stroke(.blue, lineWidth: 3).padding(4).allowsHitTesting(false) } }
        .alert("Lola Player", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("OK") { model.error = nil }
        } message: { Text(model.error ?? "") }
        .sheet(isPresented: $model.settingsOpen) { settings }
    }

    private var welcomeBackground: some View {
        GeometryReader { geometry in
            ZStack {
                if let photo = Self.welcomePhoto {
                    Image(nsImage: photo).resizable().interpolation(.high).scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height).clipped()
                }
                LinearGradient(stops: [
                    .init(color: .black.opacity(0.12), location: 0),
                    .init(color: .black.opacity(0.48), location: 0.5),
                    .init(color: .black.opacity(0.32), location: 1)
                ], startPoint: .top, endPoint: .bottom)
            }
        }.accessibilityHidden(true).allowsHitTesting(false)
    }

    private var controls: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Text(timestamp(model.scrubbing ? model.scrubPosition : model.position)).monospacedDigit().frame(minWidth: 46, alignment: .leading)
                Slider(value: Binding(get: { model.scrubbing ? model.scrubPosition : model.position }, set: { model.scrubPosition = $0 }), in: 0...max(1, model.duration)) { editing in
                    if editing { model.scrubPosition = model.position; model.scrubbing = true }
                    else { model.scrubbing = false; model.seek(model.scrubPosition) }
                }.controlSize(.mini).disabled(!model.loaded).accessibilityLabel("Timeline")
                Text(timestamp(model.duration)).monospacedDigit().frame(minWidth: 46, alignment: .trailing)
            }.font(.system(size: 11)).foregroundStyle(.secondary)
            HStack(spacing: 14) {
                icon(model.muted || model.volume == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill", "Mute", action: model.toggleMute)
                Slider(value: Binding(get: { model.volume }, set: model.changeVolume), in: 0...100).controlSize(.mini).frame(width: 80).accessibilityLabel("Volume")
                Spacer(minLength: 5)
                icon("shuffle", model.shuffle ? "Shuffle: On" : "Shuffle: Off") { model.shuffle.toggle() }
                    .foregroundStyle(model.shuffle ? Color.blue : Color.secondary)
                    .accessibilityValue(model.shuffle ? "On" : "Off")
                icon("backward.end.fill", "Previous item") { model.adjacent(-1) }
                icon("gobackward.10", "Back 10 seconds") { model.skip(-10) }
                icon(model.paused || model.ended ? "play.fill" : "pause.fill", model.paused ? "Play" : "Pause", size: 23, action: model.togglePlayback)
                icon("goforward.10", "Forward 10 seconds") { model.skip(10) }
                icon("forward.end.fill", "Next item") { model.adjacent(1) }
                Button { model.cycleRepeatMode() } label: {
                    ZStack(alignment: .bottomTrailing) {
                        Image(systemName: model.repeatMode == .track ? "repeat.1" : "repeat").font(.system(size: 16, weight: .medium))
                        if model.repeatMode == .folder || model.repeatMode == .library {
                            Image(systemName: model.repeatMode == .folder ? "folder.fill" : "books.vertical.fill")
                                .font(.system(size: 7)).padding(2).background(Color(nsColor: .windowBackgroundColor), in: Circle()).offset(x: 6, y: 5)
                        }
                    }.frame(width: 25, height: 26)
                }.buttonStyle(.plain)
                    .foregroundStyle(model.repeatMode == .off ? Color.secondary : Color.blue)
                    .help("\(model.repeatMode.rawValue) — click to change")
                    .accessibilityLabel("Repeat: \(model.repeatMode.rawValue)")
                    .contextMenu {
                        ForEach(RepeatMode.allCases, id: \.self) { mode in
                            Button { model.repeatMode = mode } label: {
                                if model.repeatMode == mode { Label(mode.rawValue, systemImage: "checkmark") } else { Text(mode.rawValue) }
                            }
                        }
                    }
                Spacer(minLength: 5)
                Button { model.changeSpeed(model.speed == 1 ? 1.5 : 1) } label: { Text(String(format: "%.2g×", model.speed)).font(.system(size: 11, weight: .medium)).frame(width: 28) }.buttonStyle(.plain).help("Toggle playback speed")
                icon("bookmark", "Bookmark Current Position", action: model.addBookmark)
                icon(model.floatEnabled ? "pin.fill" : "pin", "Float on Top while playing") { model.floatEnabled.toggle() }.foregroundStyle(model.floatEnabled ? .blue : .primary)
                icon("slider.horizontal.3", "Playback settings") { model.settingsOpen = true }
                icon("list.bullet", "Show playlist and history") { model.sidebar.toggle() }
            }
            Text(model.current?.name ?? "No media loaded").font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
        }.padding(.horizontal, 18).padding(.vertical, 12)
    }

    private func icon(_ system: String, _ label: String, size: CGFloat = 15, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: system).font(.system(size: size, weight: .medium)).frame(width: max(20, size), height: 26) }
            .buttonStyle(.plain).help(label).accessibilityLabel(label)
    }

    private var libraryPanel: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Library").font(.headline)
                Spacer()
                icon("plus", "Open files") { model.openPanel() }
                icon("xmark", "Close library") { model.sidebar = false }
            }.padding(16)
            Picker("Library", selection: $model.tab) { ForEach(LibraryTab.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented).padding(.horizontal, 12)
            TextField("Search files and bookmarks", text: $model.search)
                .textFieldStyle(.roundedBorder)
                .focused($searchFocused)
                .background(SearchFocusDismissal(isFocused: searchFocused) { searchFocused = false })
                .padding(12)
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    if displayedRecords.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: model.tab == .bookmarks ? "bookmark" : "list.bullet").font(.title2)
                            Text(model.search.isEmpty ? (model.tab == .bookmarks ? "No saved bookmarks" : "No files here yet") : "No results").font(.headline)
                            Text(model.tab == .bookmarks ? "Press ⌘B to save a moment. Bookmarks stay with every file in your history." : "Open media to start your library.").font(.caption).multilineTextAlignment(.center)
                        }.foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(30)
                    }
                    ForEach(displayedRecords) { record in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(spacing: 0) {
                              Button { model.play(record.id) } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: record.id == model.currentID ? "waveform" : "play.rectangle").foregroundStyle(record.id == model.currentID ? .blue : .secondary)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(record.name).font(.system(size: 12, weight: .medium)).lineLimit(2).multilineTextAlignment(.leading)
                                        Text("\(timestamp(record.position)) / \(timestamp(record.duration)) · \(record.bookmarks.count) bookmarks").font(.system(size: 10)).foregroundStyle(.secondary)
                                    }
                                    Spacer(minLength: 0)
                                }.padding(10).frame(maxWidth: .infinity, alignment: .leading).background(record.id == model.currentID ? Color.blue.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
                              }.buttonStyle(.plain).help(record.location.path)
                              Button(role: .destructive) {
                                  switch model.tab {
                                  case .playlist: model.removeFromPlaylist(record)
                                  case .history: model.removeFromHistory(record)
                                  case .bookmarks: model.removeAllBookmarks(record)
                                  }
                              } label: { Image(systemName: "trash").frame(width: 28, height: 32) }
                                  .buttonStyle(.plain).foregroundStyle(.secondary).padding(.trailing, 8)
                                  .help(fileRemovalLabel(record))
                                  .accessibilityLabel(fileRemovalLabel(record))
                            }
                            .contextMenu {
                                Button("Play") { model.play(record.id) }
                                Button("Add to Playlist") { if !model.queue.contains(record.id) { model.queue.append(record.id) } }
                                if record.location.isFileURL {
                                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([model.library.resolve(record.id) ?? record.location]) }
                                    Button("Relocate File…") { model.relocate(record) }
                                }
                                Divider()
                                if model.tab == .playlist { Button("Remove from Playlist", role: .destructive) { model.removeFromPlaylist(record) } }
                                if model.tab == .history { Button("Remove from History", role: .destructive) { model.removeFromHistory(record) } }
                                if model.tab == .bookmarks { Button("Remove All Bookmarks for This File", role: .destructive) { model.removeAllBookmarks(record) } }
                            }
                            if model.tab == .bookmarks {
                                ForEach(record.bookmarks.filter { model.search.isEmpty || record.name.localizedCaseInsensitiveContains(model.search) || $0.title.localizedCaseInsensitiveContains(model.search) }) { bookmark in
                                    HStack {
                                        Button { model.playBookmark(record.id, bookmark: bookmark) } label: {
                                            HStack {
                                                Text(timestamp(bookmark.seconds)).monospacedDigit().foregroundStyle(.blue).frame(width: 52, alignment: .leading)
                                                Text(bookmark.title).lineLimit(1)
                                                Spacer()
                                            }.font(.system(size: 11))
                                        }.buttonStyle(.plain).help("Open \(record.name) at \(timestamp(bookmark.seconds))")
                                        Menu {
                                            Button("Edit…") { model.editBookmark(record, bookmark) }
                                            Button("Delete Bookmark", role: .destructive) { model.removeBookmark(record, bookmark) }
                                        } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).fixedSize()
                                        Button(role: .destructive) { model.removeBookmark(record, bookmark) } label: {
                                            Image(systemName: "trash").frame(width: 22, height: 24)
                                        }.buttonStyle(.plain).foregroundStyle(.secondary)
                                            .help("Delete bookmark at \(timestamp(bookmark.seconds))")
                                            .accessibilityLabel("Delete bookmark at \(timestamp(bookmark.seconds)) from \(record.name)")
                                    }.padding(.leading, 39).padding(.trailing, 12).padding(.vertical, 6)
                                    .contextMenu {
                                        Button("Edit…") { model.editBookmark(record, bookmark) }
                                        Button("Delete Bookmark", role: .destructive) { model.removeBookmark(record, bookmark) }
                                    }
                                }
                            }
                        }
                    }
                }.padding(6)
            }
            Divider()
            HStack {
                Text("\(displayedRecords.count) files").font(.caption).foregroundStyle(.secondary)
                Spacer()
                if model.tab == .bookmarks { Button("Export…") { model.exportBookmarks() } }
                if model.tab == .playlist { Button("Empty Playlist", role: .destructive) { model.queue = [] }.disabled(model.queue.isEmpty) }
                if model.tab == .history { Button("Empty History", role: .destructive) { model.emptyHistory() }.disabled(model.historyRecords.isEmpty) }
            }.padding(12)
        }.background(Color(nsColor: .controlBackgroundColor))
    }
    private var displayedRecords: [MediaRecord] {
        let records: [MediaRecord]
        switch model.tab {
        case .playlist: records = model.queue.compactMap { model.library.record($0) }
        case .history: records = model.historyRecords
        case .bookmarks: records = model.records
        }
        return records.filter { record in
            (model.tab != .bookmarks || !record.bookmarks.isEmpty) &&
            (model.search.isEmpty || record.name.localizedCaseInsensitiveContains(model.search) || record.bookmarks.contains { $0.title.localizedCaseInsensitiveContains(model.search) })
        }
    }
    private func fileRemovalLabel(_ record: MediaRecord) -> String {
        switch model.tab {
        case .playlist: "Remove \(record.name) from Playlist"
        case .history: "Remove \(record.name) from History"
        case .bookmarks: "Remove all bookmarks for \(record.name)"
        }
    }
    private var settings: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack { Text("Playback Settings").font(.title2.bold()); Spacer(); Button("Done") { model.settingsOpen = false }.keyboardShortcut(.defaultAction) }
            Grid(alignment: .leading, horizontalSpacing: 22, verticalSpacing: 16) {
                GridRow {
                    Text("Playback speed")
                    Picker("Speed", selection: Binding(get: { model.speed }, set: model.changeSpeed)) {
                        ForEach([0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 3.0, 4.0], id: \.self) { Text(String(format: "%.2g×", $0)).tag($0) }
                    }.labelsHidden()
                }
                GridRow { Text("Repeat"); Picker("Repeat", selection: $model.repeatMode) { ForEach(RepeatMode.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.labelsHidden() }
                GridRow { Text("Shuffle"); Toggle("Shuffle playlist", isOn: $model.shuffle) }
                GridRow { Text("Audio delay"); delayField($model.audioDelay, property: "audio-delay") }
                GridRow { Text("Subtitle delay"); delayField($model.subtitleDelay, property: "sub-delay") }
                GridRow {
                    Text("A–B loop")
                    HStack {
                        Button(model.loopA.map { "A: \(timestamp($0))" } ?? "Set A") { model.setLoopA() }
                        Button(model.loopB.map { "B: \(timestamp($0))" } ?? "Set B") { model.setLoopB() }
                        Button("Clear") { model.clearLoop() }
                    }
                }
            }
            Divider()
            Toggle("Float on Top while media is playing", isOn: $model.floatEnabled)
            Text("The player returns to normal window level while paused, stopped, or buffering. Floating resumes automatically when playback resumes.").font(.caption).foregroundStyle(.secondary)
            Toggle("Remember playback position for every file", isOn: $model.rememberPosition)
            Toggle("Play automatically when opening media", isOn: $model.autoplay)
            Toggle("Ask for a name when adding a bookmark", isOn: $model.promptForBookmark)
            HStack {
                Button("All Bookmarks") { model.show(.bookmarks); model.settingsOpen = false }
                Button("Import Bookmarks…") { model.importBookmarks() }
            }
        }.padding(24).frame(width: 490).preferredColorScheme(.dark)
    }
    private func delayField(_ binding: Binding<Double>, property: String) -> some View {
        HStack {
            TextField("Seconds", value: binding, format: .number.precision(.fractionLength(1))).frame(width: 70).textFieldStyle(.roundedBorder)
                .onChange(of: binding.wrappedValue) { _, value in model.engine?.setProperty(property, value: String(value)) }
            Stepper("seconds", value: binding, in: -60...60, step: 0.1).labelsHidden()
            Text("seconds").foregroundStyle(.secondary)
        }
    }
}

/// Observes clicks without consuming them, including clicks on native video and controls.
private struct SearchFocusDismissal: NSViewRepresentable {
    let isFocused: Bool
    let dismiss: () -> Void

    func makeNSView(context: Context) -> ClickObserver { ClickObserver() }

    func updateNSView(_ view: ClickObserver, context: Context) {
        view.isFocused = isFocused
        view.dismiss = dismiss
    }

    static func dismantleNSView(_ view: ClickObserver, coordinator: ()) {
        view.stopObserving()
    }

    final class ClickObserver: NSView {
        var isFocused = false
        var dismiss: (() -> Void)?
        private var monitor: Any?

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stopObserving()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
                MainActor.assumeIsolated {
                    guard let self, self.isFocused, let window = self.window,
                          event.window === window,
                          !self.bounds.contains(self.convert(event.locationInWindow, from: nil)) else { return }
                    window.makeFirstResponder(nil)
                    self.dismiss?()
                }
                return event
            }
        }

        func stopObserving() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }
    }
}
