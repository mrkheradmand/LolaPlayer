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
    @Test func scrubPositionAnchorsThePreviewToTheThumb() {
        #expect(TimelinePosition.x(seconds: 60, width: 212, duration: 120) == 106)
        #expect(TimelinePosition.seconds(x: TimelinePosition.x(seconds: 90, width: 212, duration: 120), width: 212, duration: 120) == 90)
    }
    @Test func warmingCoversTheTimelineProgressivelyWithinItsBudget() {
        let times = TimelinePosition.warmupTimes(duration: 3600)
        #expect(times.count == 64)
        #expect(times[0] == 0 && times[1] == 3599.9 && times[2] == 1800)
        #expect(Set(times).count == times.count)
        #expect(times.allSatisfy { $0 >= 0 && $0 < 3600 })
        #expect(TimelinePosition.warmupTimes(duration: .infinity).isEmpty)
    }

}
