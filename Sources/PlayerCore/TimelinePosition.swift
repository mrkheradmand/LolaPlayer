import Foundation

public enum TimelinePosition {
    /// The mini slider thumb has a small inset at each end of the track.
    public static func seconds(x: Double, width: Double, duration: Double) -> Double {
        guard x.isFinite, width.isFinite, duration.isFinite, width > 12, duration > 0 else { return 0 }
        return min(max((x - 6) / (width - 12), 0), 1) * duration
    }
}
