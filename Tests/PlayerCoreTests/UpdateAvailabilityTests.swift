import Foundation
import Testing
@testable import PlayerCore

struct UpdateAvailabilityTests {
    @Test func onlySuccessfulCheckCanClaimLatestVersion() {
        #expect(UpdateAvailability.current.aboutLabel == "Latest Version")
        for state in [UpdateAvailability.notChecked, .checking, .failed] {
            #expect(state.aboutLabel != "Latest Version")
        }
        #expect(UpdateAvailability.checking.aboutLabel == "Checking for updates…")
        #expect(UpdateAvailability.failed.aboutLabel == "Couldn’t check for updates")
    }
    @Test func newerReleaseRemainsAvailableWithItsLink() throws {
        let data = Data(#"{"tag_name":"v99.0.0","draft":false,"prerelease":false}"#.utf8)
        let release = try #require(try UpdateChecker.update(from: data, statusCode: 200, currentVersion: "1.5.0"))
        let state = UpdateAvailability.available(release)
        #expect(state.aboutLabel == "New version available!")
        #expect(state != .current)
        if case .available(let knownRelease) = state {
            #expect(knownRelease.releaseURL.absoluteString.hasSuffix("/releases/tag/v99.0.0"))
        } else { Issue.record("Lost the available release") }
    }
}
