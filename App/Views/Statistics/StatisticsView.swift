import SwiftUI
import SwiftData
import Charts
import UnderlogCore

struct StatisticsView: View {
    @Query(sort: \Dive.startDate) private var dives: [Dive]
    @AppStorage(SettingsKey.unitSystem) private var units: UnitSystem = .metric

    var body: some View {
        NavigationStack {
            Group {
                if dives.isEmpty {
                    ContentUnavailableView("No statistics yet", systemImage: "chart.bar.xaxis",
                                           description: Text("Statistics appear once you've logged some dives."))
                } else {
                    content(LogStatistics(dives: dives.map(\.facts), bucketSize: units == .metric ? 5 : 15 * 0.3048))
                }
            }
            .navigationTitle("Statistics")
        }
    }

    private func content(_ stats: LogStatistics) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                    StatTile(title: "Dives", value: "\(stats.totalDives)", symbol: "number")
                    StatTile(title: "Time underwater", value: UnitSystem.formatDuration(stats.totalTime), symbol: "clock",
                             spokenValue: UnitSystem.spokenDuration(stats.totalTime))
                    if let deepest = stats.deepest {
                        StatTile(title: "Deepest", value: units.formatDepth(deepest.maxDepth), symbol: "arrow.down.to.line")
                    }
                    if let longest = stats.longest {
                        StatTile(title: "Longest", value: UnitSystem.formatDuration(longest.duration), symbol: "hourglass",
                                 spokenValue: UnitSystem.spokenDuration(longest.duration))
                    }
                    StatTile(title: "Average max depth", value: units.formatDepth(stats.averageMaxDepth), symbol: "water.waves")
                    if let coldest = stats.coldestTemperature {
                        StatTile(title: "Coldest water", value: units.formatTemperature(coldest), symbol: "snowflake")
                    }
                }

                if stats.divesPerYear.count > 1 {
                    VStack(alignment: .leading, spacing: 8) {
                        SectionTitle("Dives per year")
                        Chart(stats.divesPerYear, id: \.year) { entry in
                            BarMark(x: .value("Year", String(entry.year)), y: .value("Dives", entry.dives))
                                .foregroundStyle(Theme.deepWater.gradient)
                                .annotation(position: .top) {
                                    Text("\(entry.dives)").font(.caption2).foregroundStyle(.secondary)
                                }
                        }
                        .frame(height: 200)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    SectionTitle("Maximum depth")
                    Chart(stats.depthDistribution, id: \.lower) { bucket in
                        BarMark(
                            x: .value("Depth", depthLabel(bucket)),
                            y: .value("Dives", bucket.dives)
                        )
                        .foregroundStyle(Theme.surfaceWater.gradient)
                    }
                    .frame(height: 200)
                    .chartXAxisLabel(units.depthUnit)
                }
            }
            .padding()
        }
    }

    private func depthLabel(_ bucket: LogStatistics.DepthBucket) -> String {
        let lower = Int(units.depth(fromMeters: bucket.lower).rounded())
        let upper = Int(units.depth(fromMeters: bucket.upper).rounded())
        return "\(lower)–\(upper)"
    }
}
