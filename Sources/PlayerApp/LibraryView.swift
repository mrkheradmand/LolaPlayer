import AppKit
import SwiftUI
import UniformTypeIdentifiers
import PlayerCore

struct LibraryView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Bindable var model: PlayerModel
    @FocusState private var searchFocused: Bool
    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Library").font(.system(size: 24, weight: .semibold))
                        Text("Your files. Your favorite moments.").font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        searchFocused = false
                        withAnimation(reduceMotion ? nil : .timingCurve(0.23, 1, 0.32, 1, duration: 0.18)) {
                            model.librarySearchVisible.toggle()
                            if !model.librarySearchVisible { model.search = "" }
                        }
                    } label: {
                        Image(systemName: "magnifyingglass").font(.system(size: 14, weight: .medium))
                            .frame(width: 30, height: 30).contentShape(Circle())
                    }.buttonStyle(LibraryButtonStyle(search: true))
                        .help(model.librarySearchVisible ? "Hide search" : "Show search")
                        .accessibilityLabel("Search Library")
                        .accessibilityValue(model.librarySearchVisible ? "Expanded" : "Collapsed")
                    Button { model.openPanel() } label: {
                        Image(systemName: "plus").font(.system(size: 13, weight: .semibold))
                            .frame(width: 30, height: 30).background(.quaternary, in: Circle())
                    }.buttonStyle(LibraryButtonStyle(darken: true)).help("Open files").accessibilityLabel("Open files")
                }
                HStack(spacing: 4) {
                    ForEach(LibraryTab.allCases, id: \.self) { tab in
                        Button { model.tab = tab; searchFocused = false } label: {
                            Label(tab.rawValue, systemImage: symbol(tab))
                                .font(.system(size: 12, weight: model.tab == tab ? .semibold : .regular))
                                .frame(maxWidth: .infinity).padding(.vertical, 9)
                                .contentShape(Rectangle())
                                .background(model.tab == tab ? Color.accentColor.opacity(0.18) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                                .foregroundStyle(model.tab == tab ? Color.accentColor : .secondary)
                        }.buttonStyle(LibraryButtonStyle()).accessibilityAddTraits(model.tab == tab ? .isSelected : [])
                    }
                }.padding(4).background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
                if model.librarySearchVisible {
                    VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField(model.tab == .bookmarks ? "Search files and bookmarks" : "Search files", text: $model.search)
                        .textFieldStyle(.plain).focused($searchFocused)
                        .background {
                            GeometryReader { geometry in
                                LibraryPointerRegion(kind: .text, layoutRect: geometry.frame(in: .named("libraryContent")))
                                    .frame(width: geometry.size.width, height: geometry.size.height)
                            }
                        }
                        .background(SearchFocusDismissal(isFocused: searchFocused) { searchFocused = false })
                    if !model.search.isEmpty {
                        icon("xmark.circle.fill", "Clear search") { model.search = "" }
                    }
                    Rectangle().fill(.primary.opacity(0.1)).frame(width: 1, height: 18)
                    Button {
                        searchFocused = false
                        withAnimation(reduceMotion ? nil : .timingCurve(0.23, 1, 0.32, 1, duration: 0.18)) {
                            model.sortOptionsVisible.toggle()
                        }
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(model.sortOptionsVisible ? Color.accentColor : .secondary)
                            .frame(width: 28, height: 26)
                            .background(model.sortOptionsVisible ? Color.accentColor.opacity(0.14) : .clear,
                                        in: RoundedRectangle(cornerRadius: 6))
                            .contentShape(Rectangle())
                            .overlay(alignment: .topTrailing) {
                                if model.tab == .playlist && model.onlyCurrentFolder {
                                    Circle().fill(Color.accentColor).frame(width: 5, height: 5).allowsHitTesting(false)
                                }
                            }
                    }.buttonStyle(LibraryButtonStyle())
                        .help(model.sortOptionsVisible ? "Hide sorting options" : "Show sorting options")
                        .accessibilityLabel("Sorting options")
                        .accessibilityValue(model.sortOptionsVisible ? "Expanded" : "Collapsed")

                }.padding(.horizontal, 12).padding(.vertical, 10)
                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 9))
                    .overlay(RoundedRectangle(cornerRadius: 9).stroke(searchFocused ? Color.accentColor : .primary.opacity(0.08), lineWidth: searchFocused ? 2 : 1))
                if model.sortOptionsVisible {
                    sortingPanel.transition(.opacity)
                }
                    }.transition(.opacity)
                }
            }.padding(20)
            Divider()
            ScrollViewReader { scroll in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if displayedRecords.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: model.tab == .bookmarks ? "bookmark" : "list.bullet").font(.title2)
                            Text(model.search.isEmpty ? (model.tab == .bookmarks ? "No saved bookmarks" : "No files here yet") : "No results").font(.headline)
                            Text(model.tab == .bookmarks ? "Press ⌘B to save a moment. Bookmarks stay with every file in your history." : (model.tab == .playlist ? "Drop media files or folders here, including subfolders." : "Open media to start your library.")).font(.caption).multilineTextAlignment(.center)
                        }.foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(30)
                    }
                    ForEach(displayedRecords) { record in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(spacing: 0) {
                              Button { model.play(record.id) } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: record.id == model.currentID ? (model.paused ? "pause.fill" : "waveform") : "play.rectangle")
                                        .font(.system(size: 17)).foregroundStyle(record.id == model.currentID ? Color.accentColor : .secondary)
                                        .frame(width: 36, height: 40).background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(record.name).font(.system(size: 13, weight: .medium)).lineLimit(2).multilineTextAlignment(.leading)
                                        (Text(timestamp(record.position))
                                            .foregroundColor(model.tab == .playlist && record.hasBeenPlayed && record.hasFinishedPlayback != true ? .green : nil)
                                            + Text(" / \(timestamp(record.duration)) · \(record.bookmarks.count) bookmarks")
                                            + Text(model.tab == .playlist ? record.watchStatus.map { " · " + $0 } ?? "" : "").foregroundColor(.green))
                                            .font(.system(size: 11)).foregroundStyle(.secondary)
                                    }
                                    Spacer(minLength: 0)
                                }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                              }.buttonStyle(LibraryRowButtonStyle()).help(record.location.path)
                              Button(role: .destructive) {
                                  switch model.tab {
                                  case .playlist: model.removeFromPlaylist(record)
                                  case .history: model.removeFromHistory(record)
                                  case .bookmarks: model.removeAllBookmarks(record)
                                  }
                              } label: { Image(systemName: "trash").frame(width: 28, height: 32) }
                                  .buttonStyle(LibraryButtonStyle()).foregroundStyle(.secondary).padding(.trailing, 8)
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
                                Divider().padding(.horizontal, 12)
                                ForEach(record.bookmarks.filter { model.search.isEmpty || record.name.localizedCaseInsensitiveContains(model.search) || $0.title.localizedCaseInsensitiveContains(model.search) }) { bookmark in
                                    HStack {
                                        Button { model.playBookmark(record.id, bookmark: bookmark) } label: {
                                            HStack {
                                                Text(timestamp(bookmark.seconds)).monospacedDigit().foregroundStyle(Color.accentColor).padding(.horizontal, 8).padding(.vertical, 5).background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
                                                Text(bookmark.title).lineLimit(1)
                                                Spacer()
                                            }.font(.system(size: 12))
                                        }.buttonStyle(LibraryButtonStyle()).help("Open \(record.name) at \(timestamp(bookmark.seconds))")
                                        Menu {
                                            Button("Edit…") { model.editBookmark(record, bookmark) }
                                            Button("Delete Bookmark", role: .destructive) { model.removeBookmark(record, bookmark) }
                                        } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).fixedSize().modifier(LibraryHoverFeedback())
                                        Button(role: .destructive) { model.removeBookmark(record, bookmark) } label: {
                                            Image(systemName: "trash").frame(width: 22, height: 24)
                                        }.buttonStyle(LibraryButtonStyle()).foregroundStyle(.secondary)
                                            .help("Delete bookmark at \(timestamp(bookmark.seconds))")
                                            .accessibilityLabel("Delete bookmark at \(timestamp(bookmark.seconds)) from \(record.name)")
                                    }.padding(.horizontal, 12).padding(.vertical, 5)
                                    .contextMenu {
                                        Button("Edit…") { model.editBookmark(record, bookmark) }
                                        Button("Delete Bookmark", role: .destructive) { model.removeBookmark(record, bookmark) }
                                    }
                                }
                            }
                        }.padding(.bottom, model.tab == .bookmarks ? 8 : 0)
                            .modifier(LibraryCardAppearance(model: model, id: record.id))
                            .modifier(PlaylistReorderRow(model: model, id: record.id))
                            .id(record.id)
                    }
                    if model.tab == .playlist && !model.queue.isEmpty {
                        Color.clear.frame(height: 36).contentShape(Rectangle())
                            .overlay { PlaylistNativeDragSurface(model: model, source: nil, before: nil, after: nil) }
                            .overlay(alignment: .top) {
                                if model.playlistReorderTargeted && model.playlistDropBefore == nil {
                                    Rectangle().fill(Color.accentColor).frame(height: 3).allowsHitTesting(false)
                                }
                            }
                    }
                }.padding(.horizontal, 16).padding(.bottom, 16)
            }
            .contentMargins(.top, 10, for: .scrollContent)
            .onAppear { revealPlaying(scroll) }
            .onChange(of: model.tab) { _, _ in revealPlaying(scroll) }
            .onChange(of: model.libraryScrollRequest) { _, _ in revealPlaying(scroll) }
            .onChange(of: model.sidebar) { _, visible in if visible { revealPlaying(scroll) } }
            .onChange(of: model.currentID) { _, _ in revealPlaying(scroll) }
            .onChange(of: model.librarySearchVisible) { _, _ in revealPlaying(scroll) }
            .onChange(of: model.sortOptionsVisible) { _, _ in revealPlaying(scroll) }
            .onChange(of: model.librarySort) { _, _ in revealPlaying(scroll) }
            .onChange(of: model.onlyCurrentFolder) { _, _ in revealPlaying(scroll) }
            }
            Divider()
            HStack {
                Text("\(displayedRecords.count) files" + (model.tab == .bookmarks ? " · \(displayedRecords.reduce(0) { $0 + $1.bookmarks.count }) bookmarks" : "")).font(.caption).foregroundStyle(.secondary)
                Spacer()
                if model.tab == .bookmarks { Button("Export…") { model.exportBookmarks() }.buttonStyle(LibraryFooterButtonStyle()).fixedSize() }
                if model.tab == .playlist { Button("Empty Playlist", role: .destructive) { model.queue = [] }.buttonStyle(LibraryFooterButtonStyle()).fixedSize().disabled(model.queue.isEmpty) }
                if model.tab == .history { Button("Empty History", role: .destructive) { model.emptyHistory() }.buttonStyle(LibraryFooterButtonStyle()).fixedSize().disabled(model.historyRecords.isEmpty) }
            }.controlSize(.small).padding(16)
        }.coordinateSpace(name: "libraryContent").buttonStyle(LibraryButtonStyle()).background(Color(nsColor: .windowBackgroundColor))
        .onDrop(of: [.fileURL], isTargeted: $model.playlistDropTarget) { providers in
            guard model.tab == .playlist else { return false }
            return model.dropOnPlaylist(providers)
        }
        .overlay {
            if model.playlistDropTarget && model.tab == .playlist {
                RoundedRectangle(cornerRadius: 10).stroke(Color.accentColor, lineWidth: 3)
                    .padding(4).allowsHitTesting(false)
            }
        }
    }
    private var sortingPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Sort by").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                Spacer()
                Text(model.tab.rawValue).font(.system(size: 10, weight: .medium)).foregroundStyle(.tertiary)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6),
                                    count: sortOptions.count == 1 ? 1 : 2), spacing: 6) {
                ForEach(sortOptions, id: \.self) { option in
                    Button { model.selectLibrarySort(option) } label: {
                        HStack(spacing: 8) {
                            Image(systemName: sortSymbol(option)).font(.system(size: 12))
                                .frame(width: 16).foregroundStyle(model.librarySort == option ? Color.accentColor : .secondary)
                            Text(option.rawValue).font(.system(size: 11, weight: .medium)).lineLimit(1)
                            Spacer(minLength: 0)
                            Image(systemName: model.librarySort == option && model.librarySortAscending ? "arrow.up" : "arrow.down")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(model.librarySort == option ? Color.accentColor : .secondary)
                        }.padding(.horizontal, 10).padding(.vertical, 9).frame(maxWidth: .infinity)
                            .background(model.librarySort == option ? Color.accentColor.opacity(0.12) : .white.opacity(0.035),
                                        in: RoundedRectangle(cornerRadius: 7))
                            .overlay(RoundedRectangle(cornerRadius: 7)
                                .stroke(model.librarySort == option ? Color.accentColor.opacity(0.35) : .white.opacity(0.06), lineWidth: 1))
                            .contentShape(Rectangle())
                    }.buttonStyle(LibraryButtonStyle())
                        .help(model.librarySort == option ? "Reverse sort direction" : "Sort by " + option.rawValue)
                        .accessibilityValue(model.librarySort == option ? (model.librarySortAscending ? "Ascending" : "Descending") : "Not selected")
                        .accessibilityAddTraits(model.librarySort == option ? .isSelected : [])
                }
            }
            if model.tab == .playlist {
                Divider().overlay(.white.opacity(0.03))
                HStack(spacing: 10) {
                    Image(systemName: "folder").font(.system(size: 13)).foregroundStyle(.secondary)
                    Text("Only current folder").font(.system(size: 11, weight: .medium))
                    Spacer(minLength: 12)
                    Toggle("Only current folder", isOn: $model.onlyCurrentFolder)
                        .labelsHidden().toggleStyle(.switch).controlSize(.small).fixedSize().modifier(LibraryHoverFeedback())
                }.help("Show only media in the playing file’s immediate folder")
            }
        }.padding(12)
            .background(.black.opacity(0.14), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.07), lineWidth: 1))
            .accessibilityIdentifier("library-sorting-panel")
    }
    private func sortSymbol(_ option: LibrarySort) -> String {
        switch option {
        case .playlistOrder: "list.bullet"
        case .dateAdded: "calendar.badge.plus"
        case .lastPlayed, .datePlayed: "clock"
        case .watchedTill: "play.circle"
        }
    }
    private var sortOptions: [LibrarySort] {
        switch model.tab {
        case .playlist: [.dateAdded, .lastPlayed, .watchedTill]
        case .history: [.datePlayed]
        case .bookmarks: [.dateAdded, .lastPlayed, .watchedTill]
        }
    }
    private func revealPlaying(_ scroll: ScrollViewProxy) {
        guard let id = model.currentID, displayedRecords.contains(where: { $0.id == id }) else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            guard model.currentID == id, displayedRecords.contains(where: { $0.id == id }) else { return }
            scroll.scrollTo(id, anchor: .top)
        }
    }
    private func symbol(_ tab: LibraryTab) -> String {
        switch tab { case .playlist: "list.bullet"; case .history: "clock"; case .bookmarks: "bookmark" }
    }
    var displayedRecords: [MediaRecord] {
        let records: [MediaRecord]
        switch model.tab {
        case .playlist: records = model.playlistRecords
        case .history: records = model.historyRecords
        case .bookmarks: records = model.records
        }
        let folderRecords = model.tab == .playlist && model.onlyCurrentFolder
            ? LibrarySorting.inCurrentFolder(records, current: model.current) : records
        let filtered = folderRecords.filter { record in
            (model.tab != .bookmarks || !record.bookmarks.isEmpty) &&
            (model.search.isEmpty || record.name.localizedCaseInsensitiveContains(model.search) || record.bookmarks.contains { $0.title.localizedCaseInsensitiveContains(model.search) })
        }
        return LibrarySorting.sorted(filtered, by: model.librarySort, ascending: model.librarySortAscending,
                                     bookmarkDates: model.tab == .bookmarks)
    }
    private func fileRemovalLabel(_ record: MediaRecord) -> String {
        switch model.tab {
        case .playlist: "Remove \(record.name) from Playlist"
        case .history: "Remove \(record.name) from History"
        case .bookmarks: "Remove all bookmarks for \(record.name)"
        }
    }
    private func icon(_ name: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: name).frame(width: 26, height: 26) }
            .buttonStyle(LibraryButtonStyle()).help(label).accessibilityLabel(label)
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
                          event.window !== window || !self.bounds.contains(self.convert(event.locationInWindow, from: nil)) else { return }
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

/// Native dragging avoids the competing SwiftUI Button/ScrollView gestures on cards.
struct PlaylistReorderDrop {
    nonisolated static let typeIdentifier = "local.lolaplayer.playlist-item"
}

private struct PlaylistNativeDragSurface: NSViewRepresentable {
    let model: PlayerModel
    let source: UUID?
    let before: UUID?
    let after: UUID?
    func makeNSView(context: Context) -> PlaylistDragSurfaceView {
        let view = PlaylistDragSurfaceView()
        view.registerForDraggedTypes([NSPasteboard.PasteboardType(PlaylistReorderDrop.typeIdentifier)])
        return view
    }
    func updateNSView(_ view: PlaylistDragSurfaceView, context: Context) {
        view.model = model; view.source = source; view.before = before; view.after = after
    }
}

final class PlaylistDragSurfaceView: NSView, NSDraggingSource {
    weak var model: PlayerModel?
    var source: UUID?
    var before: UUID?
    var after: UUID?
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([NSPasteboard.PasteboardType(PlaylistReorderDrop.typeIdentifier)])
    }
    required init?(coder: NSCoder) { super.init(coder: coder); registerForDraggedTypes([NSPasteboard.PasteboardType(PlaylistReorderDrop.typeIdentifier)]) }
    private var hoverTracking: NSTrackingArea?
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTracking { removeTrackingArea(hoverTracking) }
        let area = NSTrackingArea(rect: .zero,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(area); hoverTracking = area
    }
    override func mouseEntered(with event: NSEvent) { updateHover() }
    override func mouseMoved(with event: NSEvent) { updateHover() }
    override func mouseExited(with event: NSEvent) {
        if let source, model?.hoveredLibraryRecordID == source { model?.hoveredLibraryRecordID = nil }
    }
    private func updateHover() {
        guard let source else { return }
        model?.hoveredLibraryRecordID = source
        NSCursor.pointingHand.set()
    }
    override func resetCursorRects() {
        super.resetCursorRects()
        if source != nil { addCursorRect(bounds, cursor: .pointingHand) }
    }
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        guard let source, let model, let window else { return }
        let start = event.locationInWindow
        while let next = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            if next.type == .leftMouseUp { model.play(source); return }
            guard hypot(next.locationInWindow.x - start.x, next.locationInWindow.y - start.y) >= 5 else { continue }
            let item = NSPasteboardItem()
            item.setString(source.uuidString, forType: NSPasteboard.PasteboardType(PlaylistReorderDrop.typeIdentifier))
            let dragging = NSDraggingItem(pasteboardWriter: item)
            let title = model.library.record(source)?.name ?? "Playlist item"
            let image = NSImage(size: NSSize(width: 260, height: 40), flipped: false) { rect in
                NSColor.controlBackgroundColor.setFill(); NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8).fill()
                (title as NSString).draw(in: rect.insetBy(dx: 10, dy: 10), withAttributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.labelColor])
                return true
            }
            dragging.setDraggingFrame(NSRect(origin: convert(next.locationInWindow, from: nil), size: image.size), contents: image)
            beginDraggingSession(with: [dragging], event: next, source: self)
            return
        }
    }
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .move }
    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        model?.playlistReorderTargeted = false
    }
    private func destination(_ sender: NSDraggingInfo) -> UUID? {
        guard source != nil else { return before }
        return convert(sender.draggingLocation, from: nil).y < bounds.midY ? before : after
    }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { draggingUpdated(sender) }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard let model, model.tab == .playlist,
              let value = sender.draggingPasteboard.string(forType: NSPasteboard.PasteboardType(PlaylistReorderDrop.typeIdentifier)),
              let id = UUID(uuidString: value), model.queue.contains(id) else { return [] }
        showInsertion(before: destination(sender))
        return .move
    }
    func showInsertion(before destination: UUID?) {
        model?.playlistDropBefore = destination; model?.playlistReorderTargeted = true
    }
    override func draggingExited(_ sender: NSDraggingInfo?) { model?.playlistReorderTargeted = false }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { true }
    @discardableResult func acceptDrop(_ pasteboard: NSPasteboard, before destination: UUID?) -> Bool {
        guard let model, model.tab == .playlist,
              let value = pasteboard.string(forType: NSPasteboard.PasteboardType(PlaylistReorderDrop.typeIdentifier)),
              let id = UUID(uuidString: value), model.queue.contains(id) else { return false }
        model.movePlaylistItem(id, before: destination)
        model.playlistReorderTargeted = false
        return true
    }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        acceptDrop(sender.draggingPasteboard, before: destination(sender))
    }
}

private struct PlaylistReorderRow: ViewModifier {
    let model: PlayerModel
    let id: UUID
    @ViewBuilder func body(content: Content) -> some View {
        if model.tab == .playlist {
            content
                .overlay {
                    HStack(spacing: 0) {
                        PlaylistNativeDragSurface(model: model, source: id, before: id,
                            after: model.queue.firstIndex(of: id).flatMap { model.queue.indices.contains($0 + 1) ? model.queue[$0 + 1] : nil })
                        Color.clear.frame(width: 36).allowsHitTesting(false)
                    }
                }
                .overlay(alignment: .top) {
                    if model.playlistReorderTargeted && model.playlistDropBefore == id {
                        Rectangle().fill(Color.accentColor).frame(height: 3).allowsHitTesting(false)
                    }
                }
        } else { content }
    }
}
