import Foundation

public enum DiveMode: String, Codable, CaseIterable, Sendable {
    case openCircuit
    case closedCircuitRebreather
    case gauge
    case freedive

    public var displayName: String {
        switch self {
        case .openCircuit: "Open circuit"
        case .closedCircuitRebreather: "Rebreather (CCR)"
        case .gauge: "Gauge"
        case .freedive: "Freedive"
        }
    }
}

/// A cylinder as read from a file. All values are optional because formats and devices vary.
public struct ImportedCylinder: Codable, Hashable, Sendable {
    /// Water capacity in litres.
    public var volumeLiters: Double?
    /// Rated working pressure in bar.
    public var workingPressureBar: Double?
    public var startPressureBar: Double?
    public var endPressureBar: Double?
    public var gas: GasMix

    public init(
        volumeLiters: Double? = nil,
        workingPressureBar: Double? = nil,
        startPressureBar: Double? = nil,
        endPressureBar: Double? = nil,
        gas: GasMix = .air
    ) {
        self.volumeLiters = volumeLiters
        self.workingPressureBar = workingPressureBar
        self.startPressureBar = startPressureBar
        self.endPressureBar = endPressureBar
        self.gas = gas
    }
}

public struct ImportedSite: Codable, Hashable, Sendable {
    public var name: String
    public var latitude: Double?
    public var longitude: Double?

    public init(name: String, latitude: Double? = nil, longitude: Double? = nil) {
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
    }
}

/// A dive read from a file, in a format-independent shape. The app turns these into stored dives.
public struct ImportedDive: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var startDate: Date
    /// Dive duration in seconds.
    public var duration: Double
    public var maxDepth: Double
    public var averageDepth: Double?
    public var minTemperature: Double?
    public var diveNumber: Int?
    public var mode: DiveMode
    public var cylinders: [ImportedCylinder]
    public var samples: [DiveSample]
    public var site: ImportedSite?
    public var buddies: [String]
    public var notes: String?
    /// Rating from 1 to 5.
    public var rating: Int?
    public var deviceName: String?

    public init(
        id: UUID = UUID(),
        startDate: Date,
        duration: Double,
        maxDepth: Double,
        averageDepth: Double? = nil,
        minTemperature: Double? = nil,
        diveNumber: Int? = nil,
        mode: DiveMode = .openCircuit,
        cylinders: [ImportedCylinder] = [],
        samples: [DiveSample] = [],
        site: ImportedSite? = nil,
        buddies: [String] = [],
        notes: String? = nil,
        rating: Int? = nil,
        deviceName: String? = nil
    ) {
        self.id = id
        self.startDate = startDate
        self.duration = duration
        self.maxDepth = maxDepth
        self.averageDepth = averageDepth
        self.minTemperature = minTemperature
        self.diveNumber = diveNumber
        self.mode = mode
        self.cylinders = cylinders
        self.samples = samples
        self.site = site
        self.buddies = buddies
        self.notes = notes
        self.rating = rating
        self.deviceName = deviceName
    }

    /// Fills in duration, depths and temperature from the profile when the file did not state them.
    public mutating func deriveMissingValuesFromProfile() {
        let profile = DiveProfile(samples: samples)
        guard !profile.isEmpty else { return }
        samples = profile.samples
        if duration <= 0 { duration = profile.duration }
        if maxDepth <= 0 { maxDepth = profile.maxDepth }
        if averageDepth == nil { averageDepth = profile.averageDepth }
        if minTemperature == nil { minTemperature = profile.minTemperature }
        if let range = profile.tankPressureRange, !cylinders.isEmpty {
            if cylinders[0].startPressureBar == nil { cylinders[0].startPressureBar = range.start }
            if cylinders[0].endPressureBar == nil { cylinders[0].endPressureBar = range.end }
        }
    }
}

public enum DuplicateDetector {
    /// Two dives are treated as the same dive when they start within `tolerance` seconds of each other.
    public static func isLikelyDuplicate(_ a: Date, _ b: Date, tolerance: TimeInterval = 120) -> Bool {
        abs(a.timeIntervalSince(b)) <= tolerance
    }
}
