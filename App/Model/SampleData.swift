import Foundation
import SwiftData
import UnderlogCore

/// Example dives for previews and UI tests.
@MainActor
enum SampleData {
    static func makeContainer(seeded: Bool) -> ModelContainer {
        let schema = Schema(ModelSchema.models)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        // An in-memory store cannot fail for a valid schema; crashing here only affects previews and tests.
        let container = try! ModelContainer(for: schema, configurations: configuration)
        if seeded { seed(container.mainContext) }
        return container
    }

    static func seed(_ context: ModelContext) {
        let calendar = Calendar.current
        let base = calendar.date(from: DateComponents(year: 2026, month: 8, day: 14, hour: 10))!

        let dives: [ImportedDive] = [
            ImportedDive(
                startDate: base,
                duration: 52 * 60, maxDepth: 18.4,
                cylinders: [ImportedCylinder(volumeLiters: 12, workingPressureBar: 232, startPressureBar: 210, endPressureBar: 70, gas: GasMix(oxygen: 0.32))],
                samples: profile(maxDepth: 18.4, minutes: 52, startTemp: 24, bottomTemp: 21),
                site: ImportedSite(name: "Blue Hole Reef", latitude: 28.572, longitude: 34.537),
                buddies: ["Anna"], notes: "Easy reef dive, good visibility.", rating: 4
            ),
            ImportedDive(
                startDate: calendar.date(byAdding: .hour, value: 4, to: base)!,
                duration: 41 * 60, maxDepth: 24.1,
                cylinders: [ImportedCylinder(volumeLiters: 12, startPressureBar: 200, endPressureBar: 60, gas: GasMix(oxygen: 0.32))],
                samples: profile(maxDepth: 24.1, minutes: 41, startTemp: 24, bottomTemp: 20),
                site: ImportedSite(name: "Canyon Wall"), buddies: ["Anna", "Péter"], rating: 5
            ),
            ImportedDive(
                startDate: calendar.date(byAdding: .day, value: 30, to: base)!,
                duration: 63 * 60, maxDepth: 9.8,
                cylinders: [ImportedCylinder(volumeLiters: 10, startPressureBar: 200, endPressureBar: 90)],
                samples: profile(maxDepth: 9.8, minutes: 63, startTemp: 28, bottomTemp: 27),
                site: ImportedSite(name: "Thermal Cave Training Line"), notes: "Guideline practice."
            ),
        ]
        let created = Logbook.insert(dives, water: .salt, in: context)
        if let trip = Logbook.trip(named: "Red Sea 2026", in: context) {
            created.prefix(2).forEach { $0.trip = trip }
        }
    }

    /// A plausible multilevel profile with a safety stop.
    static func profile(maxDepth: Double, minutes: Double, startTemp: Double, bottomTemp: Double) -> [DiveSample] {
        let total = minutes * 60
        let step = 10.0
        return stride(from: 0, through: total, by: step).map { t in
            let progress = t / total
            let depth: Double
            switch progress {
            case ..<0.08: depth = maxDepth * progress / 0.08
            case ..<0.45: depth = maxDepth * (1 - 0.1 * sin(progress * 20))
            case ..<0.80: depth = maxDepth * (0.75 - (progress - 0.45) * 1.2)
            case ..<0.86: depth = 5
            default: depth = max(5 * (1 - (progress - 0.86) / 0.14), 0)
            }
            let temperature = startTemp - (startTemp - bottomTemp) * min(depth / maxDepth, 1)
            return DiveSample(time: t, depth: max(depth, 0), temperature: temperature.rounded(toPlaces: 1))
        }
    }
}
