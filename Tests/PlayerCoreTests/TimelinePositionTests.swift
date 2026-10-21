import Testing
@testable import PlayerCore

struct TimelinePositionTests {
    @Test func hoverTimeMatchesSliderEndpointsAndMidpoint() {
        #expect(TimelinePosition.seconds(x: 6, width: 212, duration: 120) == 0)
        #expect(TimelinePosition.seconds(x: 106, width: 212, duration: 120) == 60)
        #expect(TimelinePosition.seconds(x: 206, width: 212, duration: 120) == 120)
        #expect(TimelinePosition.seconds(x: -100, width: 212, duration: 120) == 0)
        #expect(TimelinePosition.seconds(x: 500, width: 212, duration: 120) == 120)
    }
    @Test func unknownDurationAndInvalidGeometryDoNotProduceInvalidTimes() {
        #expect(TimelinePosition.seconds(x: .nan, width: 212, duration: 120) == 0)
        #expect(TimelinePosition.seconds(x: 20, width: 0, duration: 120) == 0)
        #expect(TimelinePosition.seconds(x: 20, width: 12, duration: 120) == 0)
        #expect(TimelinePosition.seconds(x: 20, width: 212, duration: .infinity) == 0)
        #expect(TimelinePosition.seconds(x: 20, width: 212, duration: 0) == 0)
    }
}
