import Foundation
import Testing
@testable import PlayerCore

struct MediaWindowLayoutTests {
    @Test func landscapeFitsVideoAndOnlyTheProgressStrip() throws {
        let size = try #require(MediaWindowLayout.fittedSize(width: 1280, aspect: 16.0 / 9, available: CGSize(width: 2000, height: 1400)))
        #expect(size.width == 1280 && size.height == 744)
    }
    @Test func portraitFitsTheScreenWithoutLetterboxing() throws {
        let size = try #require(MediaWindowLayout.fittedSize(width: 1280, aspect: 9.0 / 16, available: CGSize(width: 1600, height: 900)))
        #expect(size.height == 900)
        #expect(abs(size.width / (size.height - 24) - 9.0 / 16) < 0.0001)
    }
    @Test func unavailableGeometryDoesNotResizeTheWindow() {
        #expect(MediaWindowLayout.fittedSize(width: 1000, aspect: 0, available: CGSize(width: 1600, height: 900)) == nil)
        #expect(MediaWindowLayout.fittedSize(width: .nan, aspect: 2, available: CGSize(width: 1600, height: 900)) == nil)
        #expect(MediaWindowLayout.fittedSize(width: 1000, aspect: 2, available: CGSize(width: 1600, height: 24)) == nil)
    }
}
