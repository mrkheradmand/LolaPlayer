import Foundation
import Testing
@testable import PlayerCore

struct PlaylistReorderTests {
    @Test func movesUpDownAndToEndWithoutDuplicates() {
        let a = UUID(), b = UUID(), c = UUID(), d = UUID()
        let ids = [a, b, c, d]
        #expect(PlaybackOrder.moving(ids, item: d, before: b) == [a, d, b, c])
        #expect(PlaybackOrder.moving(ids, item: a, before: d) == [b, c, a, d])
        #expect(PlaybackOrder.moving(ids, item: b, before: nil) == [a, c, d, b])
    }
    @Test func ignoresSelfDropsAndStaleItems() {
        let a = UUID(), b = UUID()
        #expect(PlaybackOrder.moving([a, b], item: a, before: a) == [a, b])
        #expect(PlaybackOrder.moving([a, b], item: UUID(), before: b) == [a, b])
        #expect(PlaybackOrder.moving([a, b], item: a, before: UUID()) == [a, b])
        #expect(PlaybackOrder.moving([], item: a, before: nil).isEmpty)
    }
}
