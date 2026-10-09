import Foundation
import SwiftData
import UnderlogCore

/// An editable copy of a cylinder. Values are metric; the editor converts for display.
struct CylinderDraft: Identifiable, Equatable {
    let id = UUID()
    var name = ""
    var volumeLiters: Double? = 12
    var workingPressureBar: Double? = 232
    var startPressureBar: Double?
    var endPressureBar: Double?
    var oxygenPercent: Double = 21
    var heliumPercent: Double = 0

    var gas: GasMix { GasMix(oxygen: oxygenPercent / 100, helium: heliumPercent / 100) }

    var validationError: String? {
        if oxygenPercent < 1 || oxygenPercent > 100 { return "Oxygen must be between 1% and 100%." }
        if heliumPercent < 0 || oxygenPercent + heliumPercent > 100 { return "Oxygen and helium can't add up to more than 100%." }
        if let start = startPressureBar, let end = endPressureBar, end > start { return "End pressure is higher than start pressure." }
        return nil
    }
}

/// An editable copy of a dive. Nothing is written to the log until the diver saves.
struct DiveDraft {
    var startDate = Date()
    var durationMinutes: Double?
    var maxDepth: Double?
    var averageDepth: Double?
    var temperature: Double?
    var siteName = ""
    var latitude: Double?
    var longitude: Double?
    var tripName = ""
    var buddies: [String] = []
    var mode: DiveMode = .openCircuit
    var water: WaterType = .salt
    var rating = 0
    var visibility: Double?
    var suit = ""
    var weight: Double?
    var notes = ""
    var cylinders: [CylinderDraft] = [CylinderDraft()]

    init(defaultWater: WaterType = .salt) {
        water = defaultWater
    }

    init(dive: Dive) {
        startDate = dive.startDate
        durationMinutes = dive.duration > 0 ? (dive.duration / 60).rounded(toPlaces: 1) : nil
        maxDepth = dive.maxDepth > 0 ? dive.maxDepth : nil
        averageDepth = dive.averageDepth
        temperature = dive.minTemperature
        siteName = dive.site?.name ?? ""
        latitude = dive.site?.latitude
        longitude = dive.site?.longitude
        tripName = dive.trip?.name ?? ""
        buddies = dive.buddies
        mode = dive.mode
        water = dive.waterType
        rating = dive.rating
        visibility = dive.visibility
        suit = dive.suit
        weight = dive.weight
        notes = dive.notes
        cylinders = dive.orderedCylinders.map { cylinder in
            CylinderDraft(
                name: cylinder.name,
                volumeLiters: cylinder.volumeLiters,
                workingPressureBar: cylinder.workingPressureBar,
                startPressureBar: cylinder.startPressureBar,
                endPressureBar: cylinder.endPressureBar,
                oxygenPercent: (cylinder.oxygen * 100).rounded(toPlaces: 1),
                heliumPercent: (cylinder.helium * 100).rounded(toPlaces: 1)
            )
        }
    }

    var validationErrors: [String] {
        var errors: [String] = []
        if (maxDepth ?? 0) <= 0 { errors.append("Enter the maximum depth.") }
        if (durationMinutes ?? 0) <= 0 { errors.append("Enter how long the dive lasted.") }
        if let max = maxDepth, let average = averageDepth, average > max {
            errors.append("Average depth can't be deeper than the maximum depth.")
        }
        if (latitude == nil) != (longitude == nil) { errors.append("Enter both latitude and longitude, or neither.") }
        if let lat = latitude, abs(lat) > 90 { errors.append("Latitude must be between -90 and 90.") }
        if let lon = longitude, abs(lon) > 180 { errors.append("Longitude must be between -180 and 180.") }
        if mode != .freedive {
            for (index, cylinder) in cylinders.enumerated() {
                if let error = cylinder.validationError { errors.append("Cylinder \(index + 1): \(error)") }
            }
        }
        return errors
    }

    /// Writes the draft into a dive (creating sites, trips and cylinders as needed).
    @MainActor
    func apply(to dive: Dive, in context: ModelContext) {
        dive.startDate = startDate
        dive.duration = (durationMinutes ?? 0) * 60
        dive.maxDepth = maxDepth ?? 0
        dive.averageDepth = averageDepth
        dive.minTemperature = temperature
        dive.buddies = buddies
        dive.mode = mode
        dive.waterType = water
        dive.rating = rating
        dive.visibility = visibility
        dive.suit = suit.trimmingCharacters(in: .whitespacesAndNewlines)
        dive.weight = weight
        dive.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)

        if siteName.trimmingCharacters(in: .whitespaces).isEmpty, dive.site?.name.isEmpty == true {
            // An unnamed site (for example a GPS position from a dive computer): keep it and update coordinates.
            dive.site?.latitude = latitude
            dive.site?.longitude = longitude
        } else {
            dive.site = Logbook.site(named: siteName, in: context)
            if let site = dive.site {
                site.latitude = latitude
                site.longitude = longitude
            }
        }
        dive.trip = Logbook.trip(named: tripName, in: context)

        for old in dive.cylinders { context.delete(old) }
        dive.cylinders = []
        if mode != .freedive {
            for (index, draft) in cylinders.enumerated() {
                let cylinder = Cylinder(order: index, gas: draft.gas)
                cylinder.name = draft.name.trimmingCharacters(in: .whitespaces)
                cylinder.volumeLiters = draft.volumeLiters
                cylinder.workingPressureBar = draft.workingPressureBar
                cylinder.startPressureBar = draft.startPressureBar
                cylinder.endPressureBar = draft.endPressureBar
                context.insert(cylinder)
                cylinder.dive = dive
            }
        }
    }
}
