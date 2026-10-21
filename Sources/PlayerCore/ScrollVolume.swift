import Foundation

public enum ScrollVolume {
    /// Normalize natural scrolling so physically rolling the wheel up always raises volume.
    public static func adjustment(x: Double, y: Double, precise: Bool, inverted: Bool, momentum: Bool) -> Double {
        guard x.isFinite, y.isFinite, !momentum, abs(y) > 0.01, abs(y) >= abs(x) else { return 0 }
        let direction = inverted ? -y : y
        if precise { return min(max(direction * 0.2, -5), 5) }
        return direction > 0 ? 5 : -5
    }
}
