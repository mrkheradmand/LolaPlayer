import AppKit
import SwiftUI
import PlayerCore

struct LibraryView: View {
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
                    Button { model.openPanel() } label: {
                        Image(systemName: "plus").font(.system(size: 13, weight: .semibold))
                            .frame(width: 30, height: 30).background(.quaternary, in: Circle())
                    }.buttonStyle(.plain).help("Open files").accessibilityLabel("Open files")
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
                        }.buttonStyle(.plain).accessibilityAddTraits(model.tab == tab ? .isSelected : [])
                    }
                }.padding(4).background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField(model.tab == .bookmarks ? "Search files and bookmarks" : "Search files", text: $model.search)
                        .textFieldStyle(.plain).focused($searchFocused)
                        .background(SearchFocusDismissal(isFocused: searchFocused) { searchFocused = false })
                    if !model.search.isEmpty {
                        icon("xmark.circle.fill", "Clear search") { model.search = "" }
                    }
                }.padding(.horizontal, 12).padding(.vertical, 10)
                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 9))
                    .overlay(RoundedRectangle(cornerRadius: 9).stroke(searchFocused ? Color.accentColor : .primary.opacity(0.08), lineWidth: searchFocused ? 2 : 1))
            }.padding(20)
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
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
                                    Image(systemName: record.id == model.currentID ? (model.paused ? "pause.fill" : "waveform") : "play.rectangle")
                                        .font(.system(size: 17)).foregroundStyle(record.id == model.currentID ? Color.accentColor : .secondary)
                                        .frame(width: 36, height: 40).background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(record.name).font(.system(size: 13, weight: .medium)).lineLimit(2).multilineTextAlignment(.leading)
                                        Text("\(timestamp(record.position)) / \(timestamp(record.duration)) · \(record.bookmarks.count) bookmarks").font(.system(size: 11)).foregroundStyle(.secondary)
                                    }
                                    Spacer(minLength: 0)
                                }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
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
                                Divider().padding(.horizontal, 12)
                                ForEach(record.bookmarks.filter { model.search.isEmpty || record.name.localizedCaseInsensitiveContains(model.search) || $0.title.localizedCaseInsensitiveContains(model.search) }) { bookmark in
                                    HStack {
                                        Button { model.playBookmark(record.id, bookmark: bookmark) } label: {
                                            HStack {
                                                Text(timestamp(bookmark.seconds)).monospacedDigit().foregroundStyle(Color.accentColor).padding(.horizontal, 8).padding(.vertical, 5).background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
                                                Text(bookmark.title).lineLimit(1)
                                                Spacer()
                                            }.font(.system(size: 12))
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
                                    }.padding(.horizontal, 12).padding(.vertical, 5)
                                    .contextMenu {
                                        Button("Edit…") { model.editBookmark(record, bookmark) }
                                        Button("Delete Bookmark", role: .destructive) { model.removeBookmark(record, bookmark) }
                                    }
                                }
                            }
                        }.padding(.bottom, model.tab == .bookmarks ? 8 : 0)
                            .background(record.id == model.currentID ? Color.accentColor.opacity(0.1) : Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(record.id == model.currentID ? Color.accentColor.opacity(0.3) : .primary.opacity(0.06), lineWidth: 1))
                    }
                }.padding(16)
            }
            Divider()
            HStack {
                Text("\(displayedRecords.count) files" + (model.tab == .bookmarks ? " · \(displayedRecords.reduce(0) { $0 + $1.bookmarks.count }) bookmarks" : "")).font(.caption).foregroundStyle(.secondary)
                Spacer()
                if model.tab == .bookmarks { Button("Export…") { model.exportBookmarks() } }
                if model.tab == .playlist { Button("Empty Playlist", role: .destructive) { model.queue = [] }.disabled(model.queue.isEmpty) }
                if model.tab == .history { Button("Empty History", role: .destructive) { model.emptyHistory() }.disabled(model.historyRecords.isEmpty) }
            }.controlSize(.small).padding(16)
        }.background(Color(nsColor: .windowBackgroundColor))
    }
    private func symbol(_ tab: LibraryTab) -> String {
        switch tab { case .playlist: "list.bullet"; case .history: "clock"; case .bookmarks: "bookmark" }
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
    private func icon(_ name: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: name).frame(width: 26, height: 26) }
            .buttonStyle(.plain).help(label).accessibilityLabel(label)
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
