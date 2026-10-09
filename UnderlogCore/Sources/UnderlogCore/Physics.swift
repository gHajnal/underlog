import Foundation

/// The kind of water a dive took place in. It decides how much pressure each metre of depth adds.
public enum WaterType: String, Codable, CaseIterable, Sendable {
    case salt
    case fresh
    /// The EN 13319 standard density many dive computers use by default.
    case en13319

    /// Water density in kilograms per cubic metre.
    public var density: Double {
        switch self {
        case .salt: 1025
        case .fresh: 1000
        case .en13319: 1020
        }
    }

    /// Pressure added by one metre of this water, in bar.
    public var barPerMeter: Double {
        density * Physics.gravity / 100_000
    }
}

public enum Physics {
    /// Standard gravity in metres per second squared.
    public static let gravity = 9.80665
    /// Standard atmospheric pressure at sea level, in bar.
    public static let standardSurfacePressure = 1.01325

    /// Absolute (ambient) pressure at a depth, in bar.
    public static func absolutePressure(
        atDepth depth: Double,
        water: WaterType = .salt,
        surfacePressure: Double = standardSurfacePressure
    ) -> Double {
        surfacePressure + max(depth, 0) * water.barPerMeter
    }

    /// The depth, in metres, at which the ambient pressure equals the given absolute pressure.
    public static func depth(
        forAbsolutePressure pressure: Double,
        water: WaterType = .salt,
        surfacePressure: Double = standardSurfacePressure
    ) -> Double {
        max((pressure - surfacePressure) / water.barPerMeter, 0)
    }
}
