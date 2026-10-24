import SwiftUI
import AppKit
import UniformTypeIdentifiers
import PlayerCore
import CMpv

struct VideoSurface: NSViewRepresentable {
    let model: PlayerModel
    func makeNSView(context: Context) -> LPMpvView {
        let view = LPMpvView(frame: NSRect(x: 0, y: 0, width: 960, height: 540))
        // Let AppKit present the initial window before loading the playback runtime.
        DispatchQueue.main.async { model.attach(view) }
        return view
    }
    func updateNSView(_ view: LPMpvView, context: Context) {}
}

struct PlayerView: View {
    @Bindable var model: PlayerModel
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
                    PlayerMouseSurface(click: model.togglePlaybackFromVideo,
                        doubleClick: { model.window?.toggleFullScreen(nil) }, scrollVolume: model.adjustVolumeByScroll)
                    if model.currentID == nil && !model.mediaOnly {
                        welcomeBackground
                        VStack(spacing: 16) {
                            Image(systemName: "play.rectangle").font(.system(size: 55, weight: .ultraLight)).foregroundStyle(.white.opacity(0.7))
                            Text("Lola Player").font(.system(size: 25, weight: .medium))
                            Text("Drop a video, an audio file, or a folder").foregroundStyle(.white.opacity(0.8))
                            Button("Open File…") { model.openPanel() }.keyboardShortcut("o").controlSize(.large)
                            if let recent = model.historyRecords.first {
                                Button { model.play(recent.id) } label: {
                                    Label(model.showLastPlayedMediaName ? "Resume \(recent.name)" : "Resume Last Media", systemImage: "clock.arrow.circlepath").lineLimit(1)
                                }.buttonStyle(.plain).foregroundStyle(.white.opacity(0.8)).padding(.top, 6)
                            }
                        }.padding(40).shadow(color: .black.opacity(0.5), radius: 12, y: 2)
                    }
                    if model.buffering {
                        ProgressView("Opening media…").padding(20).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                    }
                    VStack {
                        HStack {
                            if !model.mediaOnly && model.floatEnabled && model.floatStatusVisible {
                                Label(model.floating ? "Floating" : "Float on Top · paused", systemImage: model.floating ? "pin.fill" : "pin.slash")
                                    .font(.system(size: 11)).padding(.horizontal, 9).padding(.vertical, 6)
                                    .background(.black.opacity(0.65), in: Capsule()).padding(14)
                            }
                            Spacer()
                        }
                        Spacer()
                        if let message = model.message, !model.mediaOnly || model.messageInMediaOnly {
                            Text(message).font(.system(size: 13, weight: .medium)).padding(10).background(.ultraThinMaterial, in: Capsule()).padding(.bottom, 22)
                        }
                    }.allowsHitTesting(false)
                }
                .overlay { PlaybackClickFeedbackView(feedback: model.playbackClickFeedback) }
                .contentShape(Rectangle())
                .contextMenu {
                    Button(model.paused ? "Play" : "Pause") { model.togglePlayback() }
                    Button("Bookmark Current Position") { model.addBookmark() }
                    Toggle("Float on Top", isOn: $model.floatEnabled)
                    Divider()
                    Button("Open File…") { model.openPanel() }
                    Button("Show All Bookmarks") { model.show(.bookmarks) }
                    Button(model.mediaOnly ? "Show Full Interface (1)" : "Media Only (2)") { model.setMediaOnly(!model.mediaOnly) }
                    Button("Enter Full Screen") { model.window?.toggleFullScreen(nil) }
                    Divider()
                    Button("Close") { model.closePlayerWindow() }
                }
                if model.mediaOnly {
                    timeline.padding(.horizontal, 12).padding(.vertical, 4)
                } else {
                    controls
                }
            }
        }
        .background(Color(nsColor: NSColor(white: 0.12, alpha: 1)))
        .ignoresSafeArea(.container, edges: model.mediaOnly ? .top : [])
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
        .overlay(alignment: .top) {
            if model.availableUpdate != nil && !model.settingsOpen {
                updateNotice.padding(12)
            }
        }
        .alert("Lola Player", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("OK") { model.error = nil }
        } message: { Text(model.error ?? "") }
        .sheet(isPresented: $model.settingsOpen) { SettingsView(model: model) }
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

    private var timeline: some View {
        HStack(spacing: 10) {
            if !model.mediaOnly { Text(timestamp(model.scrubbing ? model.scrubPosition : model.position)).monospacedDigit().frame(minWidth: 46, alignment: .leading) }
            PreviewSeekBar(model: model)
            if !model.mediaOnly { Text(timestamp(model.duration)).monospacedDigit().frame(minWidth: 46, alignment: .trailing) }
        }.font(.system(size: 11)).foregroundStyle(.secondary)
    }

    private var controls: some View {
        VStack(spacing: 8) {
            timeline
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
        }.padding(.horizontal, 18).padding(.vertical, 12)
    }

    private func icon(_ system: String, _ label: String, size: CGFloat = 15, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: system).font(.system(size: size, weight: .medium)).frame(width: max(20, size), height: 26) }
            .buttonStyle(.plain).help(label).accessibilityLabel(label)
    }

    private var updateNotice: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.down.circle.fill").foregroundStyle(.blue)
            Text("Lola Player \(model.availableUpdate?.version ?? "") is available.")
                .font(.callout).frame(maxWidth: .infinity, alignment: .leading)
            Button("View Release") { model.openUpdateRelease() }
            Button { model.dismissUpdate() } label: { Image(systemName: "xmark") }
                .buttonStyle(.plain).help("Dismiss this update").accessibilityLabel("Dismiss update notification")
        }.padding(12).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
    }


}
