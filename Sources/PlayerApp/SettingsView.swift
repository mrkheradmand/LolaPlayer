import AppKit
import SwiftUI
import PlayerCore

enum SettingsPage: String, CaseIterable, Identifiable {
    case general = "General", playback = "Playback", bookmarks = "Bookmarks"
    var id: Self { self }
    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .playback: "play.circle"
        case .bookmarks: "bookmark"
        }
    }
    var subtitle: String {
        switch self {
        case .general: "Make Lola feel at home."
        case .playback: "Fine-tune how your media plays."
        case .bookmarks: "Keep your favorite moments close."
        }
    }
}

// Disambiguate the property wrapper from the macOS 27 SDK macro of the same name.
private typealias SettingsState<Value> = SwiftUI.State<Value>

struct SettingsView: View {
    @Bindable var model: PlayerModel
    @SettingsState private var selection: SettingsPage? = .general
    private var page: SettingsPage { selection ?? .general }

    init(model: PlayerModel, initialPage: SettingsPage = .general) {
        self.model = model
        _selection = SettingsState(initialValue: initialPage)
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 20) {
                Label("Settings", systemImage: "slider.horizontal.3")
                    .font(.headline).padding(.horizontal, 18).padding(.top, 26)
                List(SettingsPage.allCases, selection: $selection) { item in
                    Label(item.rawValue, systemImage: item.symbol)
                        .padding(.vertical, 5).tag(item)
                }.listStyle(.sidebar).scrollDisabled(true)
                Text("Lola Player").font(.caption).foregroundStyle(.secondary)
                    .padding(.horizontal, 20).padding(.bottom, 20)
            }
            .frame(width: 172).background(.regularMaterial)
            Divider()
            VStack(spacing: 0) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(page.rawValue).font(.system(size: 23, weight: .semibold))
                        Text(page.subtitle).font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { model.settingsOpen = false } label: {
                        Image(systemName: "xmark").font(.system(size: 11, weight: .semibold))
                            .frame(width: 24, height: 24).background(.quaternary, in: Circle())
                    }.buttonStyle(.plain).keyboardShortcut(.cancelAction)
                        .help("Close Settings").accessibilityLabel("Close Settings")
                }.padding(24)
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        switch page {
                        case .general: general
                        case .playback: playback
                        case .bookmarks: bookmarks
                        }
                    }.padding(.horizontal, 24).padding(.bottom, 24)
                }
                Divider()
                HStack {
                    Text("Changes apply immediately").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Done") { model.settingsOpen = false }.keyboardShortcut(.defaultAction)
                }.padding(.horizontal, 24).padding(.vertical, 14)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(width: 720, height: min(530, (model.window?.screen?.visibleFrame.height ?? 800) - 80))
    }

    private var general: some View {
        Group {
            card("Window") {
                preference("Float on Top", detail: "Keep the player above other windows during playback. It returns to normal when paused or stopped.", value: $model.floatEnabled)
                Divider()
                preference("Keep running when the player window closes", detail: "Pause playback and stay in the Dock. Click the Dock icon to reopen the player; press ⌘Q to quit.", value: $model.keepRunningWhenWindowCloses)
            }
            card("Opening media") {
                preference("Play automatically", detail: "Start playback when you open a file.", value: $model.autoplay)
                Divider()
                preference("Remember playback position", detail: "Continue from where you left off in each file.", value: $model.rememberPosition)
            }
            HStack(spacing: 8) {
                Image(systemName: "keyboard").foregroundStyle(.secondary)
                Text("Press 2 for media only, or 1 for the full interface.")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(.horizontal, 4)
        }
    }

    private var playback: some View {
        Group {
            card("Playback") {
                setting("Speed") {
                    Picker("Playback speed", selection: Binding(get: { model.speed }, set: model.changeSpeed)) {
                        ForEach([0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 3.0, 4.0], id: \.self) {
                            Text(String(format: "%.2g×", $0)).tag($0)
                        }
                    }.labelsHidden().frame(width: 125)
                }
                Divider()
                setting("Repeat") {
                    Picker("Repeat", selection: $model.repeatMode) {
                        ForEach(RepeatMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }.labelsHidden().frame(width: 160)
                }
                Divider()
                preference("Shuffle", detail: "Randomize file selection when moving to another file.", value: $model.shuffle)
            }
            card("Synchronization") {
                setting("Audio delay") { delay($model.audioDelay, property: "audio-delay", label: "Audio delay") }
                Divider()
                setting("Subtitle delay") { delay($model.subtitleDelay, property: "sub-delay", label: "Subtitle delay") }
            }
            card("A–B loop") {
                Text("Repeat a section of the current file.").font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button(model.loopA.map { "A: \(timestamp($0))" } ?? "Set start (A)") { model.setLoopA() }
                    Button(model.loopB.map { "B: \(timestamp($0))" } ?? "Set end (B)") { model.setLoopB() }
                    Spacer()
                    Button("Clear") { model.clearLoop() }.disabled(model.loopA == nil && model.loopB == nil)
                }.controlSize(.small)
            }
        }
    }

    private var bookmarks: some View {
        Group {
            card("Saving moments") {
                preference("Ask for a bookmark name", detail: "Add a meaningful name when saving a moment.", value: $model.promptForBookmark)
            }
            card("Your library") {
                Text("Find saved moments across all your files, or bring bookmarks in from another library.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("All Bookmarks") { model.show(.bookmarks); model.settingsOpen = false }
                    Button("Import Bookmarks…") { model.importBookmarks() }
                }.padding(.top, 4)
            }
        }
    }

    private func card<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary).padding(.leading, 4)
            VStack(alignment: .leading, spacing: 13, content: content)
                .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(.primary.opacity(0.07), lineWidth: 1))
        }
    }
    private func preference(_ title: String, detail: String, value: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 13, weight: .medium))
                Text(detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Toggle(title, isOn: value)
                .labelsHidden().toggleStyle(.switch).controlSize(.small)
                .accessibilityHint(detail)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func setting<Control: View>(_ title: String, @ViewBuilder control: () -> Control) -> some View {
        HStack {
            Text(title).font(.system(size: 13, weight: .medium))
            Spacer(minLength: 12)
            control()
        }
    }
    private func delay(_ value: Binding<Double>, property: String, label: String) -> some View {
        HStack(spacing: 6) {
            TextField(label, value: value, format: .number.precision(.fractionLength(1)))
                .frame(width: 58).textFieldStyle(.roundedBorder).multilineTextAlignment(.trailing)
                .onChange(of: value.wrappedValue) { _, value in model.engine?.setProperty(property, value: String(value)) }
            Text("s").font(.caption).foregroundStyle(.secondary)
            Stepper(label, value: value, in: -60...60, step: 0.1).labelsHidden()
        }
    }
}
