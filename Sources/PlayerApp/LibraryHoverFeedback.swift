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
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @LibraryHoverState private var hovered = false

    func body(content: Content) -> some View {
        content
            .foregroundColor(green && hovered && enabled ? .green : nil)
            .background {
                RoundedRectangle(cornerRadius: darken || green ? 15 : 7)
                    .fill(darken ? Color.black : Color.white)
                    .opacity(enabled && (hovered || pressed) ? (darken ? 0.25 : pressed ? 0.12 : 0.07) : 0)
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: hovered)
            .onHover { inside in
                let active = inside && enabled
                guard active != hovered else { return }
                hovered = active
                if active { NSCursor.pointingHand.push() } else { NSCursor.pop() }
            }
            .onDisappear {
                if hovered { NSCursor.pop(); hovered = false }
            }
    }
}


struct ControlButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.modifier(LibraryHoverFeedback(green: true, pressed: configuration.isPressed))
    }
}
