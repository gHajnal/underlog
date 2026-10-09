import SwiftUI
import MapKit
import UnderlogCore

struct DiveDetailView: View {
    let dive: Dive
    @AppStorage(SettingsKey.unitSystem) private var units: UnitSystem = .metric
    @State private var isEditing = false
    @State private var profile: DiveProfile?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                statsGrid
                profileSection
                if dive.mode != .freedive, !dive.orderedCylinders.isEmpty { gasSection }
                if !dive.buddies.isEmpty { buddiesSection }
                if !dive.notes.isEmpty { notesSection }
                if let site = dive.site, site.hasCoordinates { mapSection(site) }
                detailsSection
            }
            .padding()
        }
        .navigationTitle("Dive \(dive.number)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit") { isEditing = true }
                    .accessibilityIdentifier(A11yID.detailEdit)
            }
        }
        .sheet(isPresented: $isEditing, onDismiss: loadProfile) {
            DiveEditorView(dive: dive)
        }
        .task(id: dive.profileData) { loadProfile() }
    }

    private func loadProfile() {
        let samples = dive.samples
        profile = samples.isEmpty ? nil : DiveProfile(samples: samples)
    }

    // MARK: Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(dive.title)
                .font(.largeTitle.bold())
                .accessibilityAddTraits(.isHeader)
            Text(dive.startDate.formatted(date: .complete, time: .shortened))
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                if let trip = dive.trip {
                    Label(trip.name, systemImage: "suitcase")
                }
                if dive.rating > 0 {
                    RatingView(rating: dive.rating)
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
    }

    private var statsGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 12)], spacing: 12) {
            StatTile(title: "Max depth", value: units.formatDepth(dive.maxDepth), symbol: "arrow.down.to.line")
                .accessibilityIdentifier(A11yID.detailMaxDepth)
            StatTile(title: "Duration", value: UnitSystem.formatDuration(dive.duration), symbol: "clock",
                     spokenValue: UnitSystem.spokenDuration(dive.duration))
            if let average = dive.averageDepth {
                StatTile(title: "Average depth", value: units.formatDepth(average), symbol: "water.waves")
            }
            if let temperature = dive.minTemperature {
                StatTile(title: "Water temp.", value: units.formatTemperature(temperature), symbol: "thermometer.medium")
            }
            if let sac = dive.surfaceAirConsumption {
                StatTile(title: "SAC", value: "\(UnitSystem.format(units.volume(fromLiters: sac), decimals: 1)) \(units.volumeUnit)/min",
                         symbol: "lungs", spokenValue: "\(UnitSystem.format(units.volume(fromLiters: sac), decimals: 1)) \(units == .metric ? "litres" : "cubic feet") per minute")
            }
            StatTile(title: "Mode", value: dive.mode.displayName, symbol: "figure.open.water.swim")
        }
    }

    @ViewBuilder
    private var profileSection: some View {
        if let profile {
            VStack(alignment: .leading, spacing: 8) {
                SectionTitle("Profile")
                ProfileChartView(profile: profile, units: units)
                    .frame(height: 240)
                    .accessibilityIdentifier(A11yID.profileChart)
                if profile.hadDecompressionStop {
                    Label("Decompression stop required during this dive", systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    private var gasSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle("Gas")
            ForEach(dive.orderedCylinders) { cylinder in
                CylinderSummary(cylinder: cylinder, units: units, water: dive.waterType)
            }
        }
    }

    private var buddiesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle("Buddies")
            Text(dive.buddies.formatted(.list(type: .and)))
        }
    }

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle("Notes")
            Text(dive.notes)
                .textSelection(.enabled)
        }
    }

    private func mapSection(_ site: DiveSite) -> some View {
        let coordinate = CLLocationCoordinate2D(latitude: site.latitude ?? 0, longitude: site.longitude ?? 0)
        return VStack(alignment: .leading, spacing: 8) {
            SectionTitle("Location")
            Map(initialPosition: .region(MKCoordinateRegion(center: coordinate, latitudinalMeters: 4000, longitudinalMeters: 4000))) {
                Marker(site.name.isEmpty ? "Dive site" : site.name, systemImage: "water.waves", coordinate: coordinate)
            }
            .frame(height: 200)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .accessibilityLabel("Map showing \(site.name.isEmpty ? "the dive site" : site.name)")
        }
    }

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle("Details")
            DetailRow(label: "Water", value: dive.waterType.displayName)
            if let visibility = dive.visibility {
                DetailRow(label: "Visibility", value: units.formatDepth(visibility))
            }
            if !dive.suit.isEmpty { DetailRow(label: "Suit", value: dive.suit) }
            if let weight = dive.weight {
                DetailRow(label: "Weight", value: units == .metric ? "\(UnitSystem.format(weight, decimals: 1)) kg" : "\(UnitSystem.format(weight * 2.204_62, decimals: 0)) lb")
            }
            if let device = dive.deviceName { DetailRow(label: "Dive computer", value: device) }
        }
    }
}

// MARK: - Building blocks

struct SectionTitle: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.title3.bold())
            .accessibilityAddTraits(.isHeader)
    }
}

struct StatTile: View {
    let title: String
    let value: String
    let symbol: String
    var spokenValue: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: symbol)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.semibold).monospacedDigit())
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(spokenValue ?? value)
    }
}

struct DetailRow: View {
    let label: String
    let value: String

    var body: some View {
        LabeledContent(label, value: value)
            .padding(.vertical, 2)
    }
}

struct RatingView: View {
    let rating: Int

    var body: some View {
        HStack(spacing: 2) {
            ForEach(1...5, id: \.self) { star in
                Image(systemName: star <= rating ? "star.fill" : "star")
            }
        }
        .foregroundStyle(.yellow)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Rated \(rating) of 5")
    }
}

struct CylinderSummary: View {
    let cylinder: Cylinder
    let units: UnitSystem
    let water: WaterType

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(cylinder.gas.name).font(.headline)
                if let volume = cylinder.volumeLiters {
                    Text(units == .metric ? "\(UnitSystem.format(volume, decimals: 1)) L" : "\(UnitSystem.format(units.volume(fromLiters: volume * (cylinder.workingPressureBar ?? 200)), decimals: 0)) cu ft")
                        .foregroundStyle(.secondary)
                }
                if !cylinder.name.isEmpty {
                    Text(cylinder.name).foregroundStyle(.secondary)
                }
            }
            if let start = cylinder.startPressureBar, let end = cylinder.endPressureBar {
                Text("\(units.formatPressure(start)) → \(units.formatPressure(end))")
                    .monospacedDigit()
                    .accessibilityLabel("Pressure from \(units.formatPressure(start)) to \(units.formatPressure(end))")
            }
            Text("MOD \(units.formatDepth(GasCalculator.maximumOperatingDepth(cylinder.gas, maxPPO2: 1.4, water: water))) at 1.4 bar ppO₂")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

extension WaterType {
    var displayName: String {
        switch self {
        case .salt: "Salt water"
        case .fresh: "Fresh water"
        case .en13319: "EN 13319"
        }
    }
}
