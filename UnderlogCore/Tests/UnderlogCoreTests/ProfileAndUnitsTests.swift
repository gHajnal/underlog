import Foundation
import Testing
@testable import UnderlogCore

@Suite("Profiles, storage, units and statistics")
struct ProfileAndUnitsTests {
    /// A simple square dive: down to 20 m in 1 min, 10 min at 20 m, up in 2 min.
    let square = DiveProfile(samples: [
        DiveSample(time: 0, depth: 0, temperature: 22),
        DiveSample(time: 60, depth: 20, temperature: 18),
        DiveSample(time: 660, depth: 20, temperature: 17),
        DiveSample(time: 780, depth: 0, temperature: 21),
    ])

    @Test func basicStatistics() {
        #expect(square.duration == 780)
        #expect(square.maxDepth == 20)
        #expect(square.minTemperature == 17)
        // Area = 600 (descent) + 12000 (bottom) + 1200 (ascent) = 13800 over 780 s.
        #expect(abs(square.averageDepth - 13800.0 / 780.0) < 1e-9)
    }

    @Test func ascentRateUsesAWindow() {
        // 20 m over 120 s = 10 m/min.
        #expect(abs(square.maxAscentRate(window: 30) - 10) < 1e-9)
    }

    @Test func ascentRateIgnoresSingleSampleNoise() {
        // A 2 m jump between two samples one second apart would read as 120 m/min without the window.
        var samples = (0...120).map { DiveSample(time: Double($0), depth: 20) }
        samples[61].depth = 18
        samples[62].depth = 20
        let rate = DiveProfile(samples: samples).maxAscentRate(window: 30)
        #expect(rate < 5)
    }

    @Test func ascentRateIsZeroForAProfileShorterThanTheWindow() {
        let short = DiveProfile(samples: [DiveSample(time: 0, depth: 10), DiveSample(time: 20, depth: 0)])
        #expect(short.maxAscentRate(window: 30) == 0)
    }

    @Test func profileCleansInput() {
        let messy = DiveProfile(samples: [
            DiveSample(time: 20, depth: 5),
            DiveSample(time: 10, depth: -1),
            DiveSample(time: 20, depth: 6),
            DiveSample(time: .nan, depth: 3),
        ])
        #expect(messy.samples.map(\.time) == [10, 20])
        #expect(messy.samples[0].depth == 0)
    }

    @Test func downsamplingKeepsTheDeepestPoint() {
        var samples = (0..<1000).map { DiveSample(time: Double($0), depth: 10) }
        samples[537].depth = 31.7
        let reduced = DiveProfile(samples: samples).downsampled(maxPoints: 100)
        #expect(reduced.count <= 100)
        #expect(reduced.contains { $0.depth == 31.7 })
        #expect(reduced.first?.time == 0)
        #expect(reduced.last?.time == 999)
    }

    @Test func codecRoundTrip() throws {
        let samples = [
            DiveSample(time: 0, depth: 0, temperature: 21.5, tankPressure: 210),
            DiveSample(time: 10, depth: 4.25, temperature: nil, tankPressure: 208, heartRate: 88),
            DiveSample(time: 20, depth: 9.5, stopDepth: 3),
        ]
        let decoded = try ProfileCodec.decode(ProfileCodec.encode(samples))
        #expect(decoded == samples)
    }

    @Test func codecRejectsBadData() {
        #expect(throws: ProfileCodec.DecodingError.empty) { try ProfileCodec.decode(Data()) }
        #expect(throws: ProfileCodec.DecodingError.unsupportedVersion(9)) {
            try ProfileCodec.decode(Data([9, 0, 0, 0, 0, 0]))
        }
        #expect(throws: ProfileCodec.DecodingError.truncated) {
            try ProfileCodec.decode(Data([1, 0, 5, 0, 0, 0, 1, 2]))
        }
    }

    @Test func unitConversions() {
        #expect(UnitSystem.imperial.formatDepth(30) == "98 ft")
        #expect(UnitSystem.metric.formatDepth(30) == "30.0 m")
        #expect(UnitSystem.imperial.formatTemperature(20) == "68 °F")
        #expect(UnitSystem.imperial.formatPressure(200) == "2901 psi")
        #expect(abs(UnitSystem.imperial.meters(fromDepth: 100) - 30.48) < 1e-9)
        #expect(abs(UnitSystem.imperial.celsius(fromTemperature: 50) - 10) < 1e-9)
    }

    @Test(arguments: [
        (2700.0, "45 min"),
        (330.0, "5 min 30 s"),
        (3900.0, "1 h 5 min"),
        (59.0, "0 min 59 s"),
    ])
    func durations(seconds: Double, text: String) {
        #expect(UnitSystem.formatDuration(seconds) == text)
    }

    @Test(arguments: [
        (2700.0, "45 minutes"),
        (3600.0, "1 hour"),
        (3660.0, "1 hour 1 minute"),
        (5400.0, "1 hour 30 minutes"),
        (7200.0, "2 hours"),
        (25.0, "25 seconds"),
        (61.0, "1 minute 1 second"),
        (330.0, "5 minutes 30 seconds"),
        (60.0, "1 minute"),
    ])
    func spokenDurations(seconds: Double, text: String) {
        #expect(UnitSystem.spokenDuration(seconds) == text)
    }

    @Test func formattingNeverTrapsOnDamagedValues() {
        #expect(UnitSystem.format(.nan, decimals: 0) == "–")
        #expect(UnitSystem.format(.infinity, decimals: 1) == "–")
        #expect(UnitSystem.format(1e30, decimals: 0) == "–")
        #expect(UnitSystem.imperial.formatDepth(.nan) == "– ft")
        #expect(UnitSystem.formatDuration(.nan) == "–")
        #expect(UnitSystem.spokenDuration(.infinity) == "unknown duration")
    }

    @Test func statisticsForAnEmptyLog() {
        let stats = LogStatistics(dives: [])
        #expect(stats.totalDives == 0)
        #expect(stats.averageMaxDepth == 0)
        #expect(stats.averageDuration == 0)
        #expect(stats.depthDistribution.isEmpty)
        #expect(stats.deepest == nil)
    }

    @Test func statisticsSurviveDamagedDepths() {
        let now = Date()
        let stats = LogStatistics(dives: [
            DiveFacts(startDate: now, duration: 60, maxDepth: .nan),
            DiveFacts(startDate: now, duration: 60, maxDepth: -4),
            DiveFacts(startDate: now, duration: 60, maxDepth: .infinity),
            DiveFacts(startDate: now, duration: 60, maxDepth: 1e9),
            DiveFacts(startDate: now, duration: 60, maxDepth: 12),
        ], bucketSize: .nan)
        // Absurd depths are capped, so the chart stays bounded.
        #expect(stats.depthDistribution.count <= Int(LogStatistics.maxChartedDepth / 5) + 1)
        #expect(stats.depthDistribution.reduce(0) { $0 + $1.dives } == 2)
        #expect(stats.deepest?.maxDepth == 1e9)
    }

    @Test func statisticsWithOnlyNegativeDepthsDoNotTrap() {
        let stats = LogStatistics(dives: [DiveFacts(startDate: Date(), duration: 60, maxDepth: -1)])
        #expect(stats.depthDistribution.isEmpty)
    }

    @Test func logStatistics() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        func date(_ y: Int) -> Date { calendar.date(from: DateComponents(year: y, month: 6, day: 1))! }
        let dives = [
            DiveFacts(startDate: date(2024), duration: 3000, maxDepth: 12, minTemperature: 18),
            DiveFacts(startDate: date(2025), duration: 2400, maxDepth: 31, minTemperature: 9),
            DiveFacts(startDate: date(2025), duration: 3600, maxDepth: 7),
        ]
        let stats = LogStatistics(dives: dives, bucketSize: 10, calendar: calendar)
        #expect(stats.totalDives == 3)
        #expect(stats.totalTime == 9000)
        #expect(stats.deepest?.maxDepth == 31)
        #expect(stats.longest?.duration == 3600)
        #expect(stats.coldestTemperature == 9)
        #expect(stats.divesPerYear == [.init(year: 2024, dives: 1), .init(year: 2025, dives: 2)])
        #expect(stats.depthDistribution.map(\.dives) == [1, 1, 0, 1])
    }

    @Test func duplicateDetection() {
        let now = Date()
        #expect(DuplicateDetector.isLikelyDuplicate(now, now.addingTimeInterval(90)))
        #expect(!DuplicateDetector.isLikelyDuplicate(now, now.addingTimeInterval(600)))
    }
}
