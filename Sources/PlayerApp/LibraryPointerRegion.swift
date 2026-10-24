import AppKit
import SwiftUI

/// Apply cursors after SwiftUI/AppKit dispatch, including over button labels.
final class LibraryPanel: NSPanel {
    let pointerRegions = NSHashTable<LibraryPointerRegionView>.weakObjects()

    override func sendEvent(_ event: NSEvent) {
        super.sendEvent(event)
        guard [.mouseMoved, .cursorUpdate, .leftMouseUp].contains(event.type) else { return }
        let regions = pointerRegions.allObjects.filter { $0.containsPointer(event.locationInWindow) }
        if regions.contains(where: { $0.kind == .text }) {
            NSCursor.iBeam.set()
        } else if !regions.isEmpty {
            NSCursor.pointingHand.set()
        } else {
            NSCursor.arrow.set()
        }
    }
}

enum LibraryPointerKind { case button, text, footer }

struct LibraryPointerRegion: NSViewRepresentable {
    var kind: LibraryPointerKind = .button
    var layoutRect: CGRect
    @Environment(\.isEnabled) private var enabled
    func makeNSView(context: Context) -> LibraryPointerRegionView { LibraryPointerRegionView() }
    func updateNSView(_ view: LibraryPointerRegionView, context: Context) {
        view.layoutRect = layoutRect
        view.kind = kind
        view.pointerEnabled = enabled
        view.window?.invalidateCursorRects(for: view)
    }
}

final class LibraryPointerRegionView: NSView {
    var layoutRect: CGRect = .zero
    var pointerEnabled = true
    var kind: LibraryPointerKind = .button
    private var pointer: NSCursor { kind == .text ? .iBeam : .pointingHand }
    private var tracking: NSTrackingArea?
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        (window as? LibraryPanel)?.pointerRegions.remove(self)
        super.viewWillMove(toWindow: newWindow)
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        (window as? LibraryPanel)?.pointerRegions.add(self)
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero,
            options: [.cursorUpdate, .mouseMoved, .activeInActiveApp, .inVisibleRect], owner: self)
        addTrackingArea(area); tracking = area
    }
    override func resetCursorRects() {
        super.resetCursorRects()
        if pointerEnabled, let content = window?.contentView {
            var rect = layoutRect
            if !content.isFlipped { rect.origin.y = content.bounds.height - rect.maxY }
            let cursorRect = convert(rect, from: content).intersection(visibleRect)
            if !cursorRect.isNull && !cursorRect.isEmpty { addCursorRect(cursorRect, cursor: pointer) }
        }
    }
    override func cursorUpdate(with event: NSEvent) {
        if containsPointer(event.locationInWindow) { pointer.set() }
    }
    override func mouseMoved(with event: NSEvent) {
        if containsPointer(event.locationInWindow) { pointer.set() }
    }
    func containsPointer(_ point: NSPoint) -> Bool {
        guard pointerEnabled, let content = window?.contentView, !isHiddenOrHasHiddenAncestor else { return false }
        var location = content.convert(point, from: nil)
        if !content.isFlipped { location.y = content.bounds.height - location.y }
        return layoutRect.contains(location) && visibleRect.contains(convert(point, from: nil))
    }
}
