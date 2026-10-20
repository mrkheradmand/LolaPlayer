import Foundation

public enum DiscKind: String, Codable, Sendable {
    case dvd, bluray
    public var playbackURL: String { self == .dvd ? "dvd://" : "bd://longest" }
    public var deviceOption: String { self == .dvd ? "dvd-device" : "bluray-device" }
    public func playbackURL(title: Int?) -> String {
        guard let title else { return playbackURL }
        return self == .dvd ? "dvd://\(title)" : "bd://\(title)"
    }
}

public enum MediaInput {
    /// HLS must reach the demuxer as one manifest, never a queue of segments.
    public static func isHLS(_ text: String) -> Bool {
        text.components(separatedBy: .newlines).contains {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("#EXT-X-")
        }
    }

    public static func playlistItems(_ text: String, relativeTo playlist: URL) -> [URL] {
        text.replacingOccurrences(of: "\u{FEFF}", with: "").components(separatedBy: .newlines).compactMap { raw in
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, !line.hasPrefix("#") else { return nil }
            if let url = URL(string: line), let scheme = url.scheme {
                guard ["file", "http", "https", "rtsp", "rtmp"].contains(scheme.lowercased()) else { return nil }
                return url
            }
            return URL(fileURLWithPath: line, relativeTo: playlist.deletingLastPathComponent()).standardizedFileURL
        }
    }

    public static func discFolder(_ input: URL) -> (URL, DiscKind)? {
        guard input.isFileURL else { return nil }
        let manager = FileManager.default
        let root = ["VIDEO_TS", "BDMV"].contains(input.lastPathComponent.uppercased()) ? input.deletingLastPathComponent() : input
        if manager.fileExists(atPath: root.appendingPathComponent("VIDEO_TS/VIDEO_TS.IFO").path) { return (root, .dvd) }
        if manager.fileExists(atPath: root.appendingPathComponent("BDMV/index.bdmv").path) { return (root, .bluray) }
        return nil
    }
}
