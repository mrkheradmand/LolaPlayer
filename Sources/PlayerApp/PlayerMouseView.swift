import AppKit
import SwiftUI

struct PlayerMouseSurface: NSViewRepresentable {
    let click: () -> Void
    let doubleClick: () -> Void

    func makeNSView(context: Context) -> PlayerMouseView { PlayerMouseView() }
    func updateNSView(_ view: PlayerMouseView, context: Context) {
        view.click = click
        view.doubleClick = doubleClick
    }
    static func dismantleNSView(_ view: PlayerMouseView, coordinator: ()) { view.cancelClick() }
}

class PlayerMouseView: NSView {
    var click: (() -> Void)?
    var doubleClick: (() -> Void)?
    private var down: NSEvent?
    private var dragged = false
    private var pendingClick: DispatchWorkItem?

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        if event.clickCount > 1 { cancelClick() }
        down = event
        dragged = false
    }
    override func mouseDragged(with event: NSEvent) {
        guard let down, !dragged else { return }
        let delta = CGPoint(x: event.locationInWindow.x - down.locationInWindow.x,
                            y: event.locationInWindow.y - down.locationInWindow.y)
        guard hypot(delta.x, delta.y) >= 4 else { return }
        dragged = true
        cancelClick()
        if window?.styleMask.contains(.fullScreen) == false { dragWindow(with: down) }
    }
    func dragWindow(with event: NSEvent) { window?.performDrag(with: event) }
    override func mouseUp(with event: NSEvent) {
        defer { down = nil }
        guard down != nil, !dragged else { return }
        if event.clickCount == 2 {
            cancelClick()
            doubleClick?()
        } else if event.clickCount == 1 {
            cancelClick()
            let work = DispatchWorkItem { [weak self] in
                guard let self, self.window != nil else { return }
                self.click?()
            }
            pendingClick = work
            DispatchQueue.main.asyncAfter(deadline: .now() + NSEvent.doubleClickInterval, execute: work)
        }
    }
    override func rightMouseDown(with event: NSEvent) {
        cancelClick()
        super.rightMouseDown(with: event)
    }
    func cancelClick() { pendingClick?.cancel(); pendingClick = nil }
}
