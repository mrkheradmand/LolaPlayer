import Foundation

/// Last check result is independent of whether its notification was dismissed.
public enum UpdateAvailability: Equatable, Sendable {
    case notChecked
    case checking
    case current
    case available(ReleaseUpdate)
    case failed

    public var aboutLabel: String {
        switch self {
        case .notChecked: "Not checked"
        case .checking: "Checking for updates…"
        case .current: "Latest Version"
        case .available: "New version available!"
        case .failed: "Couldn’t check for updates"
        }
    }
}
