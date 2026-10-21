import Foundation
import Testing
@testable import PlayerCore

@Suite struct UpdateCheckerTests {
    private func release(_ tag: String, draft: Bool = false, prerelease: Bool = false) -> Data {
        Data("{\"tag_name\":\"\(tag)\",\"draft\":\(draft),\"prerelease\":\(prerelease)}".utf8)
    }

    @Test func numericVersionsAndTrustedReleaseLink() throws {
        let update = try #require(try UpdateChecker.update(from: release("v1.10.0"), statusCode: 200, currentVersion: "1.9.9"))
        #expect(update.version == "1.10.0")
        #expect(update.releaseURL.absoluteString == "https://github.com/mrkheradmand/LolaPlayer/releases/tag/v1.10.0")
        #expect(try UpdateChecker.update(from: release("2.0.0"), statusCode: 200, currentVersion: "1.10.0")?.version == "2.0.0")
    }

    @Test(arguments: ["v1.4.0", "v1.3.9", "v0.99.99"])
    func equalOrOlderReleaseDoesNotNotify(tag: String) throws {
        #expect(try UpdateChecker.update(from: release(tag), statusCode: 200, currentVersion: "1.4.0") == nil)
    }

    @Test func draftsPrereleasesAndNoReleasesDoNotNotify() throws {
        #expect(try UpdateChecker.update(from: release("v9.0.0", draft: true), statusCode: 200, currentVersion: "1.4.0") == nil)
        #expect(try UpdateChecker.update(from: release("v9.0.0-beta", prerelease: true), statusCode: 200, currentVersion: "1.4.0") == nil)
        #expect(try UpdateChecker.update(from: Data(), statusCode: 404, currentVersion: "1.4.0") == nil)
    }

    @Test(arguments: [403, 429, 500])
    func httpErrorsAreReported(status: Int) {
        #expect(throws: UpdateCheckError.self) {
            try UpdateChecker.update(from: Data(), statusCode: status, currentVersion: "1.4.0")
        }
    }

    @Test(arguments: ["v1.5", "v1.5.0-beta", "v01.5.0", "v1.5.0/../../bad", "v1.5.0?url=bad", "v1.5.99999999999999999999999"])
    func invalidTagsAreRejected(tag: String) {
        #expect(throws: UpdateCheckError.self) {
            try UpdateChecker.update(from: release(tag), statusCode: 200, currentVersion: "1.4.0")
        }
    }

    @Test func malformedResponsesAndUnknownAppVersionAreReported() {
        for data in [Data(), Data("{}".utf8), Data("<html>Error</html>".utf8)] {
            #expect(throws: UpdateCheckError.self) {
                try UpdateChecker.update(from: data, statusCode: 200, currentVersion: "1.4.0")
            }
        }
        #expect(throws: UpdateCheckError.self) {
            try UpdateChecker.update(from: release("v2.0.0"), statusCode: 200, currentVersion: "Development")
        }
    }

    @Test func githubRequestAndResponseWorkWithoutNetwork() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ReleaseProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let result = try await UpdateChecker.check(currentVersion: "1.4.0", session: session)
        #expect(result?.version == "2.0.0")
    }
}

private final class ReleaseProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        #expect(request.url == UpdateChecker.endpoint)
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/vnd.github+json")
        #expect(request.value(forHTTPHeaderField: "User-Agent") == "LolaPlayer/1.4.0")
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(request.timeoutInterval == 20)
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(#"{"tag_name":"v2.0.0","draft":false,"prerelease":false}"#.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
