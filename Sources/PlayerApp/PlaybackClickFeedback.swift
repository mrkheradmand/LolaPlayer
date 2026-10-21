import AppKit
import Observation
import SwiftUI

/// Short-lived confirmation of a video click, independent of other playback commands.
@Observable final class PlaybackClickFeedback {
    private(set) var symbol: String?
    private(set) var opacity = 0.0
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var generation = UUID()

    func show(paused: Bool) {
        clear()
        let generation = generation
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            symbol = paused ? "pause.fill" : "play.fill"
            opacity = 1
        }
        let duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 120 : 1000
        task = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(100))
                guard let self, self.generation == generation, !Task.isCancelled else { return }
                withAnimation(.timingCurve(0.23, 1, 0.32, 1, duration: Double(duration) / 1000)) {
                    self.opacity = 0
                }
                try await Task.sleep(for: .milliseconds(duration))
                guard self.generation == generation, !Task.isCancelled else { return }
                self.symbol = nil; self.task = nil
            } catch { return }
        }
    }
    func clear() {
        generation = UUID(); task?.cancel(); task = nil
        symbol = nil; opacity = 0
    }
}

struct PlaybackClickFeedbackView: View {
    let feedback: PlaybackClickFeedback
    var body: some View {
        if let symbol = feedback.symbol {
            Image(systemName: symbol).font(.system(size: 32, weight: .semibold))
                .foregroundStyle(.white).frame(width: 80, height: 80)
                .background(.black.opacity(0.55), in: Circle())
                .opacity(feedback.opacity)
                .allowsHitTesting(false).accessibilityHidden(true)
        }
    }
}
