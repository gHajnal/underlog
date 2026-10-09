import Foundation

/// A breathing gas, described by its oxygen and helium fractions (0...1). The rest is nitrogen.
public struct GasMix: Codable, Hashable, Sendable {
    public var oxygen: Double
    public var helium: Double

    public init(oxygen: Double, helium: Double = 0) {
        self.oxygen = oxygen
        self.helium = helium
    }

    public static let air = GasMix(oxygen: 0.21)
    public static let pureOxygen = GasMix(oxygen: 1.0)

    public var nitrogen: Double { max(1 - oxygen - helium, 0) }

    /// True when the fractions are physically possible.
    public var isValid: Bool {
        oxygen > 0 && oxygen <= 1 && helium >= 0 && oxygen + helium <= 1.000_001
    }

    public var oxygenPercent: Int { Int((oxygen * 100).rounded()) }
    public var heliumPercent: Int { Int((helium * 100).rounded()) }

    /// A short conventional name: "Air", "EAN32", "Oxygen", "Tx 18/45".
    public var name: String {
        let o2 = oxygenPercent
        let he = heliumPercent
        if he > 0 { return "Tx \(o2)/\(he)" }
        if o2 == 21 { return "Air" }
        if o2 == 100 { return "Oxygen" }
        if o2 > 21 { return "EAN\(o2)" }
        return "Hypoxic \(o2)"
    }
}

/// Standard gas calculations for planning and logging.
public enum GasCalculator {
    /// Partial pressure of oxygen at a depth, in bar.
    public static func ppO2(_ mix: GasMix, atDepth depth: Double, water: WaterType = .salt) -> Double {
        mix.oxygen * Physics.absolutePressure(atDepth: depth, water: water)
    }

    /// Maximum operating depth in metres for a maximum ppO2 (commonly 1.4 bar working, 1.6 bar deco).
    public static func maximumOperatingDepth(_ mix: GasMix, maxPPO2: Double = 1.4, water: WaterType = .salt) -> Double {
        guard mix.oxygen > 0 else { return 0 }
        return Physics.depth(forAbsolutePressure: maxPPO2 / mix.oxygen, water: water)
    }

    /// Equivalent narcotic depth in metres.
    /// - Parameter oxygenIsNarcotic: When true (the common modern convention), oxygen counts as narcotic like nitrogen.
    public static func equivalentNarcoticDepth(
        _ mix: GasMix,
        atDepth depth: Double,
        oxygenIsNarcotic: Bool = true,
        water: WaterType = .salt
    ) -> Double {
        let ambient = Physics.absolutePressure(atDepth: depth, water: water)
        let narcoticFraction = oxygenIsNarcotic ? mix.oxygen + mix.nitrogen : mix.nitrogen
        let airNarcoticFraction = oxygenIsNarcotic ? 1.0 : GasMix.air.nitrogen
        return Physics.depth(forAbsolutePressure: ambient * narcoticFraction / airNarcoticFraction, water: water)
    }

    /// Equivalent air depth in metres for a nitrox mix.
    public static func equivalentAirDepth(_ mix: GasMix, atDepth depth: Double, water: WaterType = .salt) -> Double {
        let ambient = Physics.absolutePressure(atDepth: depth, water: water)
        return Physics.depth(forAbsolutePressure: ambient * mix.nitrogen / GasMix.air.nitrogen, water: water)
    }

    /// The richest nitrox (oxygen fraction) whose ppO2 stays within the limit at a depth, capped at 100%.
    public static func bestMixOxygen(forDepth depth: Double, maxPPO2: Double = 1.4, water: WaterType = .salt) -> Double {
        min(maxPPO2 / Physics.absolutePressure(atDepth: depth, water: water), 1.0)
    }

    /// Surface air consumption in litres per minute.
    ///
    /// Uses the ideal gas approximation: gas used = (start - end pressure) x cylinder volume,
    /// spread over the dive time and divided by the average ambient pressure.
    /// Returns nil when the inputs do not allow a meaningful result.
    public static func surfaceAirConsumption(
        cylinderVolumeLiters: Double,
        startPressureBar: Double,
        endPressureBar: Double,
        durationSeconds: Double,
        averageDepth: Double,
        water: WaterType = .salt
    ) -> Double? {
        guard cylinderVolumeLiters > 0, durationSeconds > 0, startPressureBar > endPressureBar else { return nil }
        let litersUsed = (startPressureBar - endPressureBar) * cylinderVolumeLiters
        let minutes = durationSeconds / 60
        let ambient = Physics.absolutePressure(atDepth: averageDepth, water: water)
        return litersUsed / minutes / ambient
    }
}
