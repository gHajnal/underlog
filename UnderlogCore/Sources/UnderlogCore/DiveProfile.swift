import Foundation

/// One point of a dive profile.
public struct DiveSample: Codable, Hashable, Sendable {
    /// Seconds since the start of the dive.
    public var time: Double
    /// Depth in metres.
    public var depth: Double
    /// Water temperature in degrees Celsius.
    public var temperature: Double?
    /// Cylinder pressure in bar.
    public var tankPressure: Double?
    /// Heart rate in beats per minute.
    public var heartRate: Double?
    /// Remaining no-decompression time in seconds, when the dive computer recorded it.
    public var noDecoTime: Double?
    /// Depth of the next required stop in metres (0 or nil means none).
    public var stopDepth: Double?

    public init(
        time: Double,
        depth: Double,
        temperature: Double? = nil,
        tankPressure: Double? = nil,
        heartRate: Double? = nil,
        noDecoTime: Double? = nil,
        stopDepth: Double? = nil
    ) {
        self.time = time
        self.depth = depth
        self.temperature = temperature
        self.tankPressure = tankPressure
        self.heartRate = heartRate
        self.noDecoTime = noDecoTime
        self.stopDepth = stopDepth
    }
}

/// A time-ordered dive profile with derived statistics.
public struct DiveProfile: Codable, Hashable, Sendable {
    public private(set) var samples: [DiveSample]

    /// Creates a profile, sorting samples by time and dropping duplicates and invalid points.
    public init(samples: [DiveSample]) {
        var seen = Set<Double>()
        self.samples = samples
            .filter { $0.time.isFinite && $0.depth.isFinite && $0.time >= 0 }
            .sorted { $0.time < $1.time }
            .filter { seen.insert($0.time).inserted }
            .map { sample in
                var s = sample
                s.depth = max(s.depth, 0)
                return s
            }
    }

    public var isEmpty: Bool { samples.isEmpty }

    /// Total time from the first to the last sample, in seconds.
    public var duration: Double {
        guard let first = samples.first, let last = samples.last else { return 0 }
        return last.time - first.time
    }

    public var maxDepth: Double { samples.map(\.depth).max() ?? 0 }

    /// Time-weighted average depth in metres (trapezoidal integration).
    public var averageDepth: Double {
        guard samples.count > 1, duration > 0 else { return samples.first?.depth ?? 0 }
        var area = 0.0
        for (a, b) in zip(samples, samples.dropFirst()) {
            area += (a.depth + b.depth) / 2 * (b.time - a.time)
        }
        return area / duration
    }

    public var minTemperature: Double? { samples.compactMap(\.temperature).min() }
    public var maxTemperature: Double? { samples.compactMap(\.temperature).max() }

    /// The first and last recorded tank pressures, in bar.
    public var tankPressureRange: (start: Double, end: Double)? {
        let pressures = samples.compactMap(\.tankPressure)
        guard let start = pressures.first, let end = pressures.last else { return nil }
        return (start, end)
    }

    /// The fastest ascent rate in metres per minute, measured over windows of at least `window` seconds
    /// so that sensor noise between single samples does not inflate the value.
    public func maxAscentRate(window: Double = 30) -> Double {
        guard samples.count > 1 else { return 0 }
        var best = 0.0
        var startIndex = 0
        for endIndex in samples.indices.dropFirst() {
            while startIndex < endIndex - 1, samples[endIndex].time - samples[startIndex + 1].time >= window {
                startIndex += 1
            }
            let dt = samples[endIndex].time - samples[startIndex].time
            guard dt >= window else { continue }
            let rise = samples[startIndex].depth - samples[endIndex].depth
            best = max(best, rise / dt * 60)
        }
        return best
    }

    /// True when the dive computer reported a required stop at any point.
    public var hadDecompressionStop: Bool {
        samples.contains { ($0.stopDepth ?? 0) > 0 }
    }

    /// A reduced set of samples for drawing, keeping the overall shape and the deepest point.
    public func downsampled(maxPoints: Int) -> [DiveSample] {
        guard maxPoints > 2, samples.count > maxPoints else { return samples }
        let bucketSize = Double(samples.count - 2) / Double(maxPoints - 2)
        var result: [DiveSample] = [samples[0]]
        for bucket in 0..<(maxPoints - 2) {
            let lower = 1 + Int(Double(bucket) * bucketSize)
            let upper = min(1 + Int(Double(bucket + 1) * bucketSize), samples.count - 1)
            guard lower < upper else { continue }
            // Keep the deepest point of each bucket so peaks are never lost.
            if let deepest = samples[lower..<upper].max(by: { $0.depth < $1.depth }) {
                result.append(deepest)
            }
        }
        result.append(samples[samples.count - 1])
        return result
    }
}
