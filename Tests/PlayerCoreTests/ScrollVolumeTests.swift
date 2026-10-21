import Testing
@testable import PlayerCore

struct ScrollVolumeTests {
    @Test func wheelStepsAndNaturalScrollHaveConsistentPhysicalDirection() {
        #expect(ScrollVolume.adjustment(x: 0, y: 3, precise: false, inverted: false, momentum: false) == 5)
        #expect(ScrollVolume.adjustment(x: 0, y: -3, precise: false, inverted: false, momentum: false) == -5)
        #expect(ScrollVolume.adjustment(x: 0, y: -3, precise: false, inverted: true, momentum: false) == 5)
    }
    @Test func trackpadIsFineGrainedAndLargeEventsAreBounded() {
        #expect(ScrollVolume.adjustment(x: 0, y: 2, precise: true, inverted: false, momentum: false) == 0.4)
        #expect(ScrollVolume.adjustment(x: 0, y: 1000, precise: true, inverted: false, momentum: false) == 5)
        #expect(ScrollVolume.adjustment(x: 0, y: -1000, precise: true, inverted: false, momentum: false) == -5)
    }
    @Test func horizontalMomentumAndInvalidInputCannotChangeVolume() {
        #expect(ScrollVolume.adjustment(x: 10, y: 1, precise: true, inverted: false, momentum: false) == 0)
        #expect(ScrollVolume.adjustment(x: 0, y: 4, precise: true, inverted: false, momentum: true) == 0)
        #expect(ScrollVolume.adjustment(x: 0, y: .nan, precise: false, inverted: false, momentum: false) == 0)
    }
}
