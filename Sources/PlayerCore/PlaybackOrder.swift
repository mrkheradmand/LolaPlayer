import Foundation

public enum RepeatMode: String, CaseIterable, Sendable {
    case off = "Repeat Off"
    case track = "One File"
    case folder = "Current Folder"
    case library = "Whole Library"

    public var wraps: Bool { self == .folder || self == .library }
    public var next: Self {
        switch self {
        case .off: .track
        case .track: .folder
        case .folder: .library
        case .library: .off
        }
    }
}

public enum MediaFormats {
    public static let fileExtensions: Set<String> = [
        "mp4", "mkv", "mov", "avi", "webm", "mp3", "flac", "m4a", "wav", "ogg",
        "m4v", "ts", "wmv", "flv", "mpeg", "mpg", "opus", "aac",
        "3gp", "3g2", "f4v", "asf", "divx", "m2ts", "mts", "m2t", "vob", "evo",
        "mxf", "dv", "y4m", "ivf", "rm", "rmvb", "ra", "mka", "oga", "ogv", "ogm", "weba",
        "aif", "aiff", "aifc", "caf", "au", "snd", "ape", "wv", "mpc", "tta", "tak", "shn",
        "amr", "spx", "wma", "ac3", "eac3", "dts", "dtshd", "thd", "mlp", "dsf", "dff",
        "wtv", "dav", "bik", "smk", "vvc", "h266",
        "mid", "midi"
    ]
    public static func files(in folder: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])
            .filter { fileExtensions.contains($0.pathExtension.lowercased()) && (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }
}

public enum PlaybackOrder {
    public static func library(_ records: [MediaRecord]) -> [UUID] {
        records.sorted {
            let names = $0.name.localizedStandardCompare($1.name)
            return names == .orderedSame ? $0.location.absoluteString < $1.location.absoluteString : names == .orderedAscending
        }.map(\.id)
    }
    public static func destination(in ids: [UUID], current: UUID?, offset: Int, wrap: Bool) -> UUID? {
        guard !ids.isEmpty else { return nil }
        guard let current, let index = ids.firstIndex(of: current) else { return offset < 0 ? ids.last : ids.first }
        let next = index + offset
        if ids.indices.contains(next) { return ids[next] }
        guard wrap else { return nil }
        return ids[((next % ids.count) + ids.count) % ids.count]
    }
}
