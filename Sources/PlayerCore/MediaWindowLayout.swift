import Foundation

public enum MediaWindowLayout {
    public static let progressHeight = 24.0

    public static func fittedSize(width: Double, aspect: Double, available: CGSize) -> CGSize? {
        guard width.isFinite, width > 0, aspect.isFinite, aspect > 0,
              available.width.isFinite, available.height.isFinite, available.width > 0, available.height > progressHeight else { return nil }
        var fittedWidth = min(width, available.width)
        var height = fittedWidth / aspect + progressHeight
        if height > available.height {
            height = available.height
            fittedWidth = (height - progressHeight) * aspect
        }
        return CGSize(width: fittedWidth, height: height)
    }
}
