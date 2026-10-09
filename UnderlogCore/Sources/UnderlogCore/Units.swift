import Foundation

/// Display units. Values are always stored in metric (metres, bar, Celsius, litres) and converted for display only.
public enum UnitSystem: String, Codable, CaseIterable, Sendable {
    case metric
    case imperial

    public var displayName: String {
        switch self {
        case .metric: "Metric"
        case .imperial: "Imperial"
        }
    }

    public var depthUnit: String { self == .metric ? "m" : "ft" }
    public var pressureUnit: String { self == .metric ? "bar" : "psi" }
    public var temperatureUnit: String { self == .metric ? "°C" : "°F" }
    public var volumeUnit: String { self == .metric ? "L" : "cu ft" }

    // MARK: Conversions from stored metric values

    public func depth(fromMeters meters: Double) -> Double {
        self == .metric ? meters : meters / 0.3048
    }

    public func pressure(fromBar bar: Double) -> Double {
        self == .metric ? bar : bar * 14.503_773_8
    }

    public func temperature(fromCelsius celsius: Double) -> Double {
        self == .metric ? celsius : celsius * 9 / 5 + 32
    }

    /// Litres per minute, or cubic feet per minute in imperial.
    public func volume(fromLiters liters: Double) -> Double {
        self == .metric ? liters : liters / 28.316_846_6
    }

    // MARK: Conversions back to stored metric values

    public func meters(fromDepth value: Double) -> Double {
        self == .metric ? value : value * 0.3048
    }

    public func bar(fromPressure value: Double) -> Double {
        self == .metric ? value : value / 14.503_773_8
    }

    public func celsius(fromTemperature value: Double) -> Double {
        self == .metric ? value : (value - 32) * 5 / 9
    }

    public func liters(fromVolume value: Double) -> Double {
        self == .metric ? value : value * 28.316_846_6
    }

    // MARK: Formatting

    public func formatDepth(_ meters: Double) -> String {
        "\(Self.format(depth(fromMeters: meters), decimals: self == .metric ? 1 : 0)) \(depthUnit)"
    }

    public func formatPressure(_ bar: Double) -> String {
        "\(Self.format(pressure(fromBar: bar), decimals: 0)) \(pressureUnit)"
    }

    public func formatTemperature(_ celsius: Double) -> String {
        "\(Self.format(temperature(fromCelsius: celsius), decimals: self == .metric ? 1 : 0)) \(temperatureUnit)"
    }

    public static func formatDuration(_ seconds: Double) -> String {
        guard seconds.isFinite, abs(seconds) < 1e12 else { return "–" }
        let total = Int(max(seconds, 0).rounded())
        if total >= 3600 {
            let roundedMinutes = Int((Double(total) / 60).rounded())
            return "\(roundedMinutes / 60) h \(roundedMinutes % 60) min"
        }
        // Under ten minutes, seconds still matter (freedives, short checkout dives).
        if total < 600, total % 60 != 0 {
            return "\(total / 60) min \(total % 60) s"
        }
        return "\(Int((Double(total) / 60).rounded())) min"
    }

    /// A spoken form of a duration, for VoiceOver. Follows the same seconds rule as `formatDuration`.
    public static func spokenDuration(_ seconds: Double) -> String {
        guard seconds.isFinite, abs(seconds) < 1e12 else { return "unknown duration" }
        let total = Int(max(seconds, 0).rounded())
        func plural(_ count: Int, _ unit: String) -> String { "\(count) \(unit)\(count == 1 ? "" : "s")" }

        if total < 600, total % 60 != 0 {
            let m = total / 60, s = total % 60
            return m == 0 ? plural(s, "second") : "\(plural(m, "minute")) \(plural(s, "second"))"
        }
        let minutes = Int((Double(total) / 60).rounded())
        if minutes >= 60 {
            let h = minutes / 60, m = minutes % 60
            return m == 0 ? plural(h, "hour") : "\(plural(h, "hour")) \(plural(m, "minute"))"
        }
        return plural(minutes, "minute")
    }

    /// A number rounded to a fixed count of decimals, without a unit.
    public static func format(_ value: Double, decimals: Int) -> String {
        // Non-finite or absurdly large values (only possible from damaged data) are shown as a dash, not converted to Int.
        guard value.isFinite, abs(value) < 1e15 else { return "–" }
        let factor = pow(10, Double(decimals))
        let rounded = (value * factor).rounded() / factor
        if decimals == 0 { return String(Int(rounded)) }
        return String(format: "%.\(decimals)f", rounded)
    }
}
