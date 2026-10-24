import AppKit
import SwiftUI
import PlayerCore

final class LibraryWindowController: NSWindowController, NSWindowDelegate {
    private let model: PlayerModel
    private var fullScreenParent: NSWindow?

    init(model: PlayerModel) {
        self.model = model
        let panel = LibraryPanel(contentRect: NSRect(x: 0, y: 0, width: 440, height: 620),
                            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        panel.acceptsMouseMovedEvents = true
        panel.title = "Library"
        panel.titlebarAppearsTransparent = true
        panel.isReleasedWhenClosed = false
        panel.minSize = NSSize(width: 380, height: 360)
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.fullScreenAuxiliary]
        panel.appearance = NSAppearance(named: .darkAqua)
        super.init(window: panel)
        panel.delegate = self
        panel.contentView = NSHostingView(rootView: LibraryView(model: model).preferredColorScheme(.dark))
    }
    required init?(coder: NSCoder) { nil }

    func sync(reposition: Bool = false) {
        guard let panel = window as? NSPanel, let player = model.window else { return }
        guard model.sidebar else {
            fullScreenParent?.removeChildWindow(panel); fullScreenParent = nil
            if panel.isVisible { panel.orderOut(nil) }
            return
        }
        let fullScreen = player.styleMask.contains(.fullScreen)
        if fullScreen && !NSApp.isActive {
            if panel.isVisible { panel.orderOut(nil) }
            return
        }
        if fullScreen && fullScreenParent == nil {
            player.addChildWindow(panel, ordered: .above); fullScreenParent = player
        } else if !fullScreen, let parent = fullScreenParent {
            parent.removeChildWindow(panel); fullScreenParent = nil
        }
        panel.hidesOnDeactivate = fullScreen
        let level: NSWindow.Level = fullScreen ? .floating : player.level
        if panel.level != level { panel.level = level }
        if !panel.isVisible || reposition {
            let primary = player.screen ?? NSScreen.main
            let screens = ([primary].compactMap { $0 } + NSScreen.screens.filter { $0 !== primary })
                .map { fullScreen ? $0.frame : $0.visibleFrame }
            panel.setFrame(WindowPlacement.library(beside: player.frame, screens: screens,
                size: panel.frame.size, fullScreen: fullScreen), display: true)
        }
        if !panel.isVisible { panel.orderFront(nil) }
    }

    func present() {
        model.libraryScrollRequest += 1
        guard model.window?.styleMask.contains(.fullScreen) != true || NSApp.isActive else { return }
        sync()
        window?.makeKeyAndOrderFront(nil)
    }
    func windowWillClose(_ notification: Notification) { model.sidebar = false }
    func hideForFullScreenTransition() { window?.orderOut(nil) }
}
