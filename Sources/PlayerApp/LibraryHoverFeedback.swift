import AppKit
import SwiftUI

private typealias LibraryHoverState<Value> = SwiftUI.State<Value>

struct LibraryButtonStyle: ButtonStyle {
    var darken = false
    var search = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label.modifier(LibraryHoverFeedback(
            darken: darken, green: search, pressed: configuration.isPressed))
    }
}

struct LibraryHoverFeedback: ViewModifier {
    var darken = false
    var green = false
    var pressed = false
    var showsBackground = true
    var yellow = false
    var pointerKind: LibraryPointerKind = .button
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @LibraryHoverState private var hovered = false

    func body(content: Content) -> some View {
        content
            .foregroundColor(hovered && enabled ? (yellow ? .yellow : green ? .green : nil) : nil)
            .background {
                RoundedRectangle(cornerRadius: darken || green ? 15 : 7)
                    .fill(darken ? Color.black : Color.white)
                    .opacity(showsBackground && enabled && (hovered || pressed) ? (darken ? 0.25 : pressed ? 0.12 : 0.07) : 0)
            }
            .background {
                GeometryReader { geometry in
                    LibraryPointerRegion(kind: pointerKind, layoutRect: geometry.frame(in: .named("libraryContent")))
                        .frame(width: geometry.size.width, height: geometry.size.height)
                }
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: hovered)
            .onContinuousHover { phase in
                switch phase {
                case .active:
                    hovered = enabled
                    if enabled { NSCursor.pointingHand.set() }
                case .ended:
                    if hovered { NSCursor.arrow.set() }
                    hovered = false
                }
            }
            .onDisappear {
                if hovered { NSCursor.arrow.set(); hovered = false }
            }
    }
}


struct ControlButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.modifier(ControlHoverFeedback())
    }
}

private struct ControlHoverFeedback: ViewModifier {
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @LibraryHoverState private var hovered = false

    func body(content: Content) -> some View {
        content
            .foregroundColor(hovered && enabled ? .green : nil)
            .contentShape(Rectangle())
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: hovered)
            .onContinuousHover { phase in
                switch phase {
                case .active:
                    hovered = enabled
                    // AppKit can reset the cursor after onHover; reassert it on movement.
                    if enabled { NSCursor.pointingHand.set() }
                case .ended:
                    if hovered { NSCursor.arrow.set() }
                    hovered = false
                }
            }
            .onDisappear {
                if hovered { NSCursor.arrow.set(); hovered = false }
            }
    }
}


struct LibraryRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.modifier(LibraryHoverFeedback(showsBackground: false))
    }
}

struct LibraryCardAppearance: ViewModifier {
    let model: PlayerModel
    let id: UUID
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var hovered: Bool { model.hoveredLibraryRecordID == id }
    private var current: Bool { model.currentID == id }

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: 12)
                    .fill(current ? Color.accentColor.opacity(hovered ? 0.17 : 0.1)
                          : Color(nsColor: .controlBackgroundColor))
                if hovered && !current {
                    RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.035))
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(current ? Color.accentColor.opacity(hovered ? 0.55 : 0.3)
                            : hovered ? Color.accentColor.opacity(0.3) : .primary.opacity(0.06), lineWidth: 1)
                    .allowsHitTesting(false)
            }
            .contentShape(RoundedRectangle(cornerRadius: 12))
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: hovered)
            .onContinuousHover { phase in
                switch phase {
                case .active:
                    model.hoveredLibraryRecordID = id
                    NSCursor.pointingHand.set()
                case .ended:
                    if model.hoveredLibraryRecordID == id { model.hoveredLibraryRecordID = nil }
                }
            }
            .onDisappear {
                if model.hoveredLibraryRecordID == id { model.hoveredLibraryRecordID = nil }
            }
    }
}


struct LibraryFooterButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .fixedSize()
            .modifier(LibraryHoverFeedback(showsBackground: false, yellow: true, pointerKind: .footer))
    }
}
