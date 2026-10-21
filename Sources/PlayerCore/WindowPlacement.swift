import Foundation
import CoreGraphics

public enum WindowPlacement {
    public static func restored(_ saved: CGRect, screens: [CGRect], minimum: CGSize) -> CGRect? {
        guard saved.minX.isFinite, saved.minY.isFinite, saved.width.isFinite, saved.height.isFinite,
              saved.width > 0, saved.height > 0, let first = screens.first else { return nil }
        let screen = screens.filter { area($0.intersection(saved)) > 0 }.max { area($0.intersection(saved)) < area($1.intersection(saved)) } ?? first
        return clamped(saved, to: screen, minimum: minimum)
    }

    public static func library(beside player: CGRect, screens: [CGRect], size: CGSize, fullScreen: Bool) -> CGRect {
        let screen = screens.first ?? player
        let fitted = CGSize(width: min(size.width, screen.width - (fullScreen ? 48 : 0)), height: min(size.height, screen.height - 32))
        if fullScreen {
            return CGRect(x: screen.maxX - fitted.width - 24, y: screen.midY - fitted.height / 2,
                          width: fitted.width, height: fitted.height)
        }
        for available in screens {
            let candidates = [
                CGPoint(x: player.maxX + 12, y: player.maxY - fitted.height),
                CGPoint(x: player.minX - fitted.width - 12, y: player.maxY - fitted.height),
                CGPoint(x: player.minX, y: player.minY - fitted.height - 12),
                CGPoint(x: player.minX, y: player.maxY + 12)
            ]
            for origin in candidates {
                let frame = clamped(CGRect(origin: origin, size: fitted), to: available, minimum: .zero)
                if !frame.intersects(player.insetBy(dx: -8, dy: -8)) { return frame }
            }
        }
        return clamped(CGRect(x: screen.maxX - fitted.width - 16, y: screen.maxY - fitted.height - 16,
                              width: fitted.width, height: fitted.height), to: screen, minimum: .zero)
    }

    private static func area(_ rect: CGRect) -> CGFloat { rect.isNull ? 0 : rect.width * rect.height }
    private static func clamped(_ rect: CGRect, to screen: CGRect, minimum: CGSize) -> CGRect {
        let width = min(max(rect.width, minimum.width), screen.width)
        let height = min(max(rect.height, minimum.height), screen.height)
        return CGRect(x: min(max(rect.minX, screen.minX), screen.maxX - width),
                      y: min(max(rect.minY, screen.minY), screen.maxY - height), width: width, height: height)
    }
}
