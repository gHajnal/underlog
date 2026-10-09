import Foundation
import SwiftData
import UnderlogCore

@Model
final class Dive {
    var number: Int = 0
    var startDate: Date = Date()
    /// Seconds.
    var duration: Double = 0
    /// Metres.
    var maxDepth: Double = 0
    var averageDepth: Double?
    /// Degrees Celsius.
    var minTemperature: Double?
    var modeRaw: String = DiveMode.openCircuit.rawValue
    var waterTypeRaw: String = WaterType.salt.rawValue
    var notes: String = ""
    /// 0 means not rated, otherwise 1...5.
    var rating: Int = 0
    var buddies: [String] = []
    /// Metres.
    var visibility: Double?
    var suit: String = ""
    /// Kilograms.
    var weight: Double?
    var deviceName: String?
    @Attribute(.externalStorage) var profileData: Data?

    var site: DiveSite?
    var trip: Trip?
    @Relationship(deleteRule: .cascade, inverse: \Cylinder.dive)
    var cylinders: [Cylinder] = []

    init(number: Int = 0, startDate: Date = .now) {
        self.number = number
        self.startDate = startDate
    }

    var mode: DiveMode {
        get { DiveMode(rawValue: modeRaw) ?? .openCircuit }
        set { modeRaw = newValue.rawValue }
    }

    var waterType: WaterType {
        get { WaterType(rawValue: waterTypeRaw) ?? .salt }
        set { waterTypeRaw = newValue.rawValue }
    }

    /// Cylinders in the order the diver entered or the file listed them.
    var orderedCylinders: [Cylinder] { cylinders.sorted { $0.order < $1.order } }

    var samples: [DiveSample] {
        get { profileData.flatMap { try? ProfileCodec.decode($0) } ?? [] }
        set { profileData = newValue.isEmpty ? nil : ProfileCodec.encode(newValue) }
    }

    var hasProfile: Bool { profileData != nil }

    var title: String {
        if let name = site?.name, !name.isEmpty { return name }
        return "Dive \(number)"
    }

    var primaryGasName: String? {
        guard mode != .freedive else { return nil }
        return orderedCylinders.first.map { $0.gas.name }
    }

    /// Surface air consumption from the first cylinder, in litres per minute.
    var surfaceAirConsumption: Double? {
        guard let cylinder = orderedCylinders.first,
              let volume = cylinder.volumeLiters,
              let start = cylinder.startPressureBar,
              let end = cylinder.endPressureBar else { return nil }
        return GasCalculator.surfaceAirConsumption(
            cylinderVolumeLiters: volume,
            startPressureBar: start,
            endPressureBar: end,
            durationSeconds: duration,
            averageDepth: averageDepth ?? maxDepth * 0.6,
            water: waterType
        )
    }

    var facts: DiveFacts {
        DiveFacts(startDate: startDate, duration: duration, maxDepth: maxDepth, minTemperature: minTemperature)
    }
}

@Model
final class Cylinder {
    var order: Int = 0
    var name: String = ""
    /// Litres of water capacity.
    var volumeLiters: Double?
    var workingPressureBar: Double?
    var startPressureBar: Double?
    var endPressureBar: Double?
    var oxygen: Double = 0.21
    var helium: Double = 0
    var dive: Dive?

    init(order: Int = 0, gas: GasMix = .air) {
        self.order = order
        self.oxygen = gas.oxygen
        self.helium = gas.helium
    }

    var gas: GasMix {
        get { GasMix(oxygen: oxygen, helium: helium) }
        set {
            oxygen = newValue.oxygen
            helium = newValue.helium
        }
    }
}

@Model
final class DiveSite {
    var name: String = ""
    var latitude: Double?
    var longitude: Double?
    var notes: String = ""
    @Relationship(deleteRule: .nullify, inverse: \Dive.site)
    var dives: [Dive] = []

    init(name: String, latitude: Double? = nil, longitude: Double? = nil) {
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
    }

    /// True only for a real position. A damaged import could hold impossible values, which would crash the map.
    var hasCoordinates: Bool {
        guard let latitude, let longitude, latitude.isFinite, longitude.isFinite else { return false }
        return abs(latitude) <= 90 && abs(longitude) <= 180
    }
}

@Model
final class Trip {
    var name: String = ""
    var notes: String = ""
    @Relationship(deleteRule: .nullify, inverse: \Dive.trip)
    var dives: [Dive] = []

    init(name: String) {
        self.name = name
    }
}

enum ModelSchema {
    static var models: [any PersistentModel.Type] { [Dive.self, Cylinder.self, DiveSite.self, Trip.self] }
}
