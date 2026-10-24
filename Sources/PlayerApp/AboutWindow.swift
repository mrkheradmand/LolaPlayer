import AppKit
import SwiftUI
import PlayerCore

final class AboutWindowController: NSWindowController, NSWindowDelegate {
    init(model: PlayerModel) {
        let window = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 560, height: 520),
            styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .aqua)
        window.backgroundColor = .white
        window.isFloatingPanel = true
        window.level = .floating
        // Close on focus/app changes instead of leaving an automatically restored hidden panel.
        window.hidesOnDeactivate = false
        window.title = "About Lola Player"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        NotificationCenter.default.addObserver(self, selector: #selector(applicationDidResignActive(_:)),
            name: NSApplication.didResignActiveNotification, object: NSApp)
        window.contentView = NSHostingView(rootView: AboutView(model: model))
        // Full-size content includes the title bar; size the complete surface.
        window.setFrame(NSRect(origin: window.frame.origin, size: NSSize(width: 560, height: 520)), display: false)
        window.center()
    }
    required init?(coder: NSCoder) { nil }
    func windowDidResignKey(_ notification: Notification) { close() }
    @objc func applicationDidResignActive(_ notification: Notification) { close() }
    deinit { NotificationCenter.default.removeObserver(self) }
}

struct AboutView: View {
    @Bindable var model: PlayerModel
    private let repository = URL(string: "https://github.com/mrkheradmand/LolaPlayer")!

    var versionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "Version \(version) (Build \(build))"
    }
    var copyrightText: String {
        Bundle.main.object(forInfoDictionaryKey: "NSHumanReadableCopyright") as? String
            ?? "Copyright © 2026 J Kheradmand"
    }
    var versionLine: String { "\(versionText) \(model.updateAvailability.aboutLabel)" }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                Image(nsImage: NSApp.applicationIconImage).resizable().scaledToFit()
                    .frame(width: 88, height: 88)
                    .shadow(color: .black.opacity(0.16), radius: 10, y: 4)
                    .padding(.bottom, 12)
                Text("Lola Player").font(.system(size: 28, weight: .bold))
                Text("Your media. Your favorite moments.")
                    .font(.system(size: 15, weight: .medium)).foregroundStyle(.secondary)
                Text(versionText).font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity).padding(.top, 42).padding(.bottom, 22)
            .accessibilityElement(children: .contain).accessibilityLabel(versionLine)

            Divider()
            VStack(alignment: .leading, spacing: 13) {
                HStack(spacing: 12) {
                    Text("Keep Lola Player up to date.")
                        .font(.system(size: 13)).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    Button("Check for Updates") { model.checkForUpdates() }
                        .controlSize(.regular)
                        .disabled(model.updateAvailability == .checking)
                        .help(model.updateCheckStatus)
                }
                Toggle("Automatically check for updates", isOn: $model.automaticUpdateChecks)
                    .toggleStyle(.checkbox).font(.system(size: 13))
                HStack(spacing: 6) {
                    if model.updateAvailability == .checking {
                        ProgressView().controlSize(.mini)
                    }
                    if case .available(let release) = model.updateAvailability {
                        Link(model.updateAvailability.aboutLabel, destination: release.releaseURL)
                    } else {
                        Text(model.updateAvailability.aboutLabel)
                            .foregroundStyle(model.updateAvailability == .current ? Color.green : Color.secondary)
                    }
                }.font(.system(size: 11))
                    .accessibilityLabel(model.updateCheckStatus)
            }.padding(.horizontal, 4).padding(.top, 20)

            Spacer(minLength: 24)

            VStack(spacing: 9) {
                HStack(spacing: 14) {
                    Link("GitHub Repository", destination: repository)
                    Text("·").foregroundStyle(.tertiary)
                    Link("Releases", destination: repository.appendingPathComponent("releases"))
                    Text("·").foregroundStyle(.tertiary)
                    Link("MIT License", destination: repository.appendingPathComponent("blob/master/LICENSE"))
                }.font(.system(size: 12))
                Text(copyrightText).font(.system(size: 11)).foregroundStyle(.secondary)
                Text("Built natively with Swift, SwiftUI, AppKit, and libmpv for macOS.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity).padding(.bottom, 20)
        }
        .padding(.horizontal, 24).frame(width: 560, height: 520)
        .background(.white).preferredColorScheme(.light)
    }
}
