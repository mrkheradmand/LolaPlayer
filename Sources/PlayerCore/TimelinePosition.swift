import Foundation

public enum TimelinePosition {
    /// The mini slider thumb has a small inset at each end of the track.
    public static func seconds(x: Double, width: Double, duration: Double) -> Double {
        guard x.isFinite, width.isFinite, duration.isFinite, width > 12, duration > 0 else { return 0 }
        return min(max((x - 6) / (width - 12), 0), 1) * duration
    }
    public static func x(seconds: Double, width: Double, duration: Double) -> Double {
        guard seconds.isFinite, width.isFinite, duration.isFinite, width > 12, duration > 0 else { return 6 }
        return 6 + min(max(seconds / duration, 0), 1) * (width - 12)
    }

    /// Progressive coverage: endpoints, midpoint, quarters, then finer intervals.
    public static func warmupTimes(duration: Double) -> [Double] {
        guard duration.isFinite, duration > 0 else { return [] }
        let end = max(0, duration - 0.1)
        var result = [0.0, end]
        for divisions in [2, 4, 8, 16, 32, 64] {
            for index in stride(from: 1, to: divisions, by: 2) {
                let time = min((duration * Double(index) / Double(divisions) * 2).rounded() / 2, end)
                if !result.contains(time) { result.append(time) }
                if result.count >= 64 { return result }
            }
        }
        return result
    }

}
