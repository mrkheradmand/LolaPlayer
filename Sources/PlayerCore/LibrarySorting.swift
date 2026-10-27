import Foundation

public enum LibrarySort: String, CaseIterable, Sendable {
    case name = "Name"
    case playlistOrder = "Playlist order"
    case dateAdded = "Date added"
    case lastPlayed = "Last played"
    case watchedTill = "Watched till"
    case datePlayed = "Date played"
}

public enum LibrarySorting {
    public static func sorted(_ records: [MediaRecord], by sort: LibrarySort, ascending: Bool,
                              bookmarkDates: Bool = false) -> [MediaRecord] {
        guard sort != .playlistOrder else { return records }
        func value(_ record: MediaRecord) -> Double {
            switch sort {
            case .name, .playlistOrder: return 0
            case .dateAdded:
                let date = bookmarkDates ? record.bookmarks.compactMap(\.addedAt).max() : record.addedAt
                return (date ?? record.addedAt ?? record.lastOpened).timeIntervalSinceReferenceDate
            case .lastPlayed, .datePlayed:
                return (record.lastPlayedAt ?? (record.isInHistory == false ? .distantPast : record.lastOpened)).timeIntervalSinceReferenceDate
            case .watchedTill:
                let seconds = record.hasFinishedPlayback == true ? record.duration : record.position
                return seconds.isFinite ? max(0, seconds) : 0
            }
        }
        return records.enumerated().sorted {
            if sort == .name {
                let order = $0.element.name.localizedStandardCompare($1.element.name)
                if order == .orderedSame { return $0.offset < $1.offset }
                return ascending ? order == .orderedAscending : order == .orderedDescending
            }
            let a = value($0.element), b = value($1.element)
            if a == b { return $0.offset < $1.offset }
            return ascending ? a < b : a > b
        }.map(\.element)
    }

    public static func inCurrentFolder(_ records: [MediaRecord], current: MediaRecord?) -> [MediaRecord] {
        guard let current, current.location.isFileURL else { return [] }
        let folder = current.location.standardizedFileURL.deletingLastPathComponent()
        return records.filter {
            $0.location.isFileURL && $0.location.standardizedFileURL.deletingLastPathComponent() == folder
        }
    }
}
