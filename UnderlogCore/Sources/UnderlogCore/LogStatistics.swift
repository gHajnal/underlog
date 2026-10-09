import Foundation

/// The facts about one dive that statistics need.
public struct DiveFacts: Hashable, Sendable {
    public var startDate: Date
    public var duration: Double
    public var maxDepth: Double
    public var minTemperature: Double?

    public init(startDate: Date, duration: Double, maxDepth: Double, minTemperature: Double? = nil) {
        self.startDate = startDate
        self.duration = duration
        self.maxDepth = maxDepth
        self.minTemperature = minTemperature
    }
}

public struct LogStatistics: Sendable {
    public struct YearCount: Hashable, Sendable {
        public var year: Int
        public var dives: Int
    }

    public struct DepthBucket: Hashable, Sendable {
        /// Lower bound of the bucket in metres (inclusive).
        public var lower: Double
        /// Upper bound of the bucket in metres (exclusive).
        public var upper: Double
        public var dives: Int
    }

    public var totalDives: Int
    /// Total time underwater in seconds.
    public var totalTime: Double
    public var deepest: DiveFacts?
    public var longest: DiveFacts?
    public var coldestTemperature: Double?
    public var averageMaxDepth: Double
    public var averageDuration: Double
    public var divesPerYear: [YearCount]
    public var depthDistribution: [DepthBucket]

    public init(dives: [DiveFacts], bucketSize: Double = 5, calendar: Calendar = .current) {
        totalDives = dives.count
        totalTime = dives.reduce(0) { $0 + $1.duration }
        deepest = dives.max { $0.maxDepth < $1.maxDepth }
        longest = dives.max { $0.duration < $1.duration }
        coldestTemperature = dives.compactMap(\.minTemperature).min()
        averageMaxDepth = dives.isEmpty ? 0 : dives.reduce(0) { $0 + $1.maxDepth } / Double(dives.count)
        averageDuration = dives.isEmpty ? 0 : totalTime / Double(dives.count)

        let byYear = Dictionary(grouping: dives) { calendar.component(.year, from: $0.startDate) }
        divesPerYear = byYear.map { YearCount(year: $0.key, dives: $0.value.count) }.sorted { $0.year < $1.year }

        let size = max(bucketSize, 1)
        let byBucket = Dictionary(grouping: dives) { Int(($0.maxDepth / size).rounded(.down)) }
        if let top = byBucket.keys.max() {
            depthDistribution = (0...top).map { index in
                DepthBucket(lower: Double(index) * size, upper: Double(index + 1) * size, dives: byBucket[index]?.count ?? 0)
            }
        } else {
            depthDistribution = []
        }
    }
}
