import Foundation
import SwiftData
import UnderlogCore

/// Logbook operations that touch several models at once.
@MainActor
enum Logbook {
    static func nextDiveNumber(in context: ModelContext) -> Int {
        var descriptor = FetchDescriptor<Dive>(sortBy: [SortDescriptor(\.number, order: .reverse)])
        descriptor.fetchLimit = 1
        return ((try? context.fetch(descriptor).first?.number) ?? 0) + 1
    }

    /// Finds a site by name (ignoring case and surrounding spaces) or creates it. Returns nil for an empty name.
    static func site(named rawName: String, in context: ModelContext) -> DiveSite? {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        let sites = (try? context.fetch(FetchDescriptor<DiveSite>())) ?? []
        if let existing = sites.first(where: { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }) {
            return existing
        }
        let site = DiveSite(name: name)
        context.insert(site)
        return site
    }

    /// Finds a trip by name or creates it. Returns nil for an empty name.
    static func trip(named rawName: String, in context: ModelContext) -> Trip? {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        let trips = (try? context.fetch(FetchDescriptor<Trip>())) ?? []
        if let existing = trips.first(where: { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }) {
            return existing
        }
        let trip = Trip(name: name)
        context.insert(trip)
        return trip
    }

    /// Adds imported dives to the log, numbering any that came without a number.
    @discardableResult
    static func insert(_ imported: [ImportedDive], water: WaterType, in context: ModelContext) -> [Dive] {
        var next = nextDiveNumber(in: context)
        var created: [Dive] = []
        for source in imported.sorted(by: { $0.startDate < $1.startDate }) {
            let dive = Dive(number: source.diveNumber ?? next, startDate: source.startDate)
            if source.diveNumber == nil { next += 1 } else { next = max(next, (source.diveNumber ?? 0) + 1) }
            dive.duration = source.duration
            dive.maxDepth = source.maxDepth
            dive.averageDepth = source.averageDepth
            dive.minTemperature = source.minTemperature
            dive.mode = source.mode
            dive.waterType = water
            dive.notes = source.notes ?? ""
            dive.rating = source.rating ?? 0
            dive.buddies = source.buddies
            dive.deviceName = source.deviceName
            dive.samples = source.samples
            context.insert(dive)

            if let importedSite = source.site {
                if importedSite.name.isEmpty {
                    // A position without a name: keep it as an unnamed site the diver can rename later.
                    let site = DiveSite(name: "", latitude: importedSite.latitude, longitude: importedSite.longitude)
                    context.insert(site)
                    dive.site = site
                } else if let matchedSite = Logbook.site(named: importedSite.name, in: context) {
                    if matchedSite.latitude == nil { matchedSite.latitude = importedSite.latitude }
                    if matchedSite.longitude == nil { matchedSite.longitude = importedSite.longitude }
                    dive.site = matchedSite
                }
            }

            for (index, cylinderSource) in source.cylinders.enumerated() {
                let cylinder = Cylinder(order: index, gas: cylinderSource.gas)
                cylinder.volumeLiters = cylinderSource.volumeLiters
                cylinder.workingPressureBar = cylinderSource.workingPressureBar
                cylinder.startPressureBar = cylinderSource.startPressureBar
                cylinder.endPressureBar = cylinderSource.endPressureBar
                context.insert(cylinder)
                cylinder.dive = dive
            }
            created.append(dive)
        }
        return created
    }

    /// Renumbers every dive from 1 in date order.
    static func renumber(in context: ModelContext) {
        let dives = (try? context.fetch(FetchDescriptor<Dive>(sortBy: [SortDescriptor(\.startDate)]))) ?? []
        for (index, dive) in dives.enumerated() {
            dive.number = index + 1
        }
    }

    /// The format-independent form of a stored dive, used for export.
    static func exportable(_ dive: Dive) -> ImportedDive {
        ImportedDive(
            startDate: dive.startDate,
            duration: dive.duration,
            maxDepth: dive.maxDepth,
            averageDepth: dive.averageDepth,
            minTemperature: dive.minTemperature,
            diveNumber: dive.number,
            mode: dive.mode,
            cylinders: dive.orderedCylinders.map {
                ImportedCylinder(
                    volumeLiters: $0.volumeLiters,
                    workingPressureBar: $0.workingPressureBar,
                    startPressureBar: $0.startPressureBar,
                    endPressureBar: $0.endPressureBar,
                    gas: $0.gas
                )
            },
            samples: dive.samples,
            site: dive.site.map { ImportedSite(name: $0.name, latitude: $0.latitude, longitude: $0.longitude) },
            buddies: dive.buddies,
            notes: dive.notes.isEmpty ? nil : dive.notes,
            rating: dive.rating == 0 ? nil : dive.rating,
            deviceName: dive.deviceName
        )
    }
}
