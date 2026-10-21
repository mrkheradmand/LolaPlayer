import Foundation

public struct ReleaseUpdate: Equatable, Sendable {
    public let version: String
    public let releaseURL: URL
}

public enum UpdateCheckError: Error, LocalizedError {
    case invalidVersion, invalidResponse, requestFailed(Int)

    public var errorDescription: String? {
        switch self {
        case .invalidVersion: "The release version could not be compared with this app."
        case .invalidResponse: "GitHub returned an unreadable release response."
        case .requestFailed(let status): "GitHub update check failed (HTTP \(status)). Try again later."
        }
    }
}

public enum UpdateChecker {
    public static let endpoint = URL(string: "https://api.github.com/repos/mrkheradmand/LolaPlayer/releases/latest")!

    public static func check(currentVersion: String, session: URLSession) async throws -> ReleaseUpdate? {
        var request = URLRequest(url: endpoint, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("LolaPlayer/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw UpdateCheckError.invalidResponse }
        return try update(from: data, statusCode: response.statusCode, currentVersion: currentVersion)
    }

    /// Kept separate from transport so release and error handling can be checked offline.
    public static func update(from data: Data, statusCode: Int, currentVersion: String) throws -> ReleaseUpdate? {
        guard let current = Version(currentVersion) else { throw UpdateCheckError.invalidVersion }
        if statusCode == 404 { return nil } // No published release yet.
        guard statusCode == 200 else { throw UpdateCheckError.requestFailed(statusCode) }
        guard let release = try? JSONDecoder().decode(GitHubRelease.self, from: data) else {
            throw UpdateCheckError.invalidResponse
        }
        guard !release.draft, !release.prerelease else { return nil }
        let tag = release.tag_name
        guard let latest = Version(tag) else { throw UpdateCheckError.invalidVersion }
        guard current < latest else { return nil }
        // Construct our own repository URL rather than trusting a URL in remote JSON.
        return ReleaseUpdate(version: latest.description,
            releaseURL: URL(string: "https://github.com/mrkheradmand/LolaPlayer/releases/tag/\(tag)")!)
    }

    private struct GitHubRelease: Decodable {
        let tag_name: String
        let draft: Bool
        let prerelease: Bool
    }

    private struct Version: Comparable {
        let parts: [Int]
        var description: String { parts.map(String.init).joined(separator: ".") }

        init?(_ value: String) {
            let text = value.hasPrefix("v") ? String(value.dropFirst()) : value
            let fields = text.split(separator: ".", omittingEmptySubsequences: false)
            guard fields.count == 3 else { return nil }
            var parsed: [Int] = []
            for field in fields {
                guard !field.isEmpty, field.utf8.allSatisfy({ (48...57).contains($0) }),
                      field.count == 1 || field.first != "0", let number = Int(field) else { return nil }
                parsed.append(number)
            }
            parts = parsed
        }

        static func < (lhs: Self, rhs: Self) -> Bool { lhs.parts.lexicographicallyPrecedes(rhs.parts) }
    }
}
