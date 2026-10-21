import AppKit
import SwiftUI
import PlayerCore

final class AboutWindowController: NSWindowController {
    init(model: PlayerModel) {
        let window = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 560, height: 440),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isFloatingPanel = true
        window.level = .floating
        window.hidesOnDeactivate = true
        window.title = "About Lola Player"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.contentView = NSHostingView(rootView: AboutView(model: model))
        window.center()
    }
    required init?(coder: NSCoder) { nil }
}

struct AboutView: View {
    @Bindable var model: PlayerModel
    private let repository = URL(string: "https://github.com/mrkheradmand/LolaPlayer")!

    var versionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "Version \(version) (\(build))"
    }
    var copyrightText: String {
        Bundle.main.object(forInfoDictionaryKey: "NSHumanReadableCopyright") as? String
            ?? "Copyright © 2026 J Kheradmand"
    }
    var versionLine: String { "\(versionText) \(model.updateAvailability.aboutLabel)" }

    var body: some View {
        VStack(spacing: 18) {
            Image(nsImage: NSApp.applicationIconImage).resizable().scaledToFit().frame(width: 96, height: 96)
            Text("Lola Player").font(.system(size: 26, weight: .bold))
            HStack(spacing: 10) {
                Text(versionText)
                if case .available(let release) = model.updateAvailability {
                    Link(model.updateAvailability.aboutLabel, destination: release.releaseURL)
                } else {
                    Text(model.updateAvailability.aboutLabel)
                        .foregroundStyle(model.updateAvailability == .current ? Color.green : Color.secondary)
                }
            }
            .font(.system(size: 14)).lineLimit(1)
            .accessibilityElement(children: .contain).accessibilityLabel(versionLine)
            VStack(spacing: 5) {
                Text("Made for Mac OS with Love").font(.system(size: 17))
                Link(repository.absoluteString, destination: repository).font(.system(size: 14))
            }
            Text("An independent native media player.\nBuilt with Swift, AppKit, and libmpv.")
                .font(.system(size: 14)).multilineTextAlignment(.center)
            HStack(spacing: 10) {
                Text(copyrightText).foregroundStyle(.secondary)
                Link("MIT License", destination: repository.appendingPathComponent("blob/master/LICENSE"))
            }.font(.system(size: 12))
            Button("Check for Updates…") { model.checkForUpdates() }
                .disabled(model.updateAvailability == .checking)
                .help(model.updateCheckStatus)
        }
        .padding(28).frame(width: 560, height: 440)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
