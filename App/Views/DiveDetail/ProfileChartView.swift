import SwiftUI
import Charts
import Accessibility
import UnderlogCore

/// The depth profile: time across, depth downwards, with a scrub-to-read selection.
struct ProfileChartView: View {
    let profile: DiveProfile
    let units: UnitSystem
    /// Downsampled once per profile, not on every redraw while scrubbing.
    private let points: [DiveSample]

    @State private var selectedMinute: Double?

    init(profile: DiveProfile, units: UnitSystem) {
        self.profile = profile
        self.units = units
        self.points = profile.downsampled(maxPoints: 400)
    }

    var body: some View {
        Chart {
            ForEach(points, id: \.time) { sample in
                AreaMark(
                    x: .value("Time", sample.time / 60),
                    yStart: .value("Surface", 0),
                    yEnd: .value("Depth", units.depth(fromMeters: sample.depth))
                )
                .foregroundStyle(
                    LinearGradient(colors: [Theme.surfaceWater.opacity(0.35), Theme.deepWater.opacity(0.6)],
                                   startPoint: .top, endPoint: .bottom)
                )
                LineMark(
                    x: .value("Time", sample.time / 60),
                    y: .value("Depth", units.depth(fromMeters: sample.depth))
                )
                .foregroundStyle(Theme.deepWater)
                .lineStyle(StrokeStyle(lineWidth: 2))
            }

            if let selected = selectedSample {
                RuleMark(x: .value("Selected", selected.time / 60))
                    .foregroundStyle(.secondary)
                    .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        SelectionCallout(sample: selected, units: units)
                    }
            }
        }
        .chartYScale(domain: .automatic(includesZero: true, reversed: true))
        .chartXAxisLabel("Minutes")
        .chartYAxisLabel(units.depthUnit)
        .chartXSelection(value: $selectedMinute)
        .accessibilityChartDescriptor(ProfileChartDescriptor(profile: profile, units: units))
    }

    private var selectedSample: DiveSample? {
        guard let minute = selectedMinute else { return nil }
        let target = minute * 60
        return points.min { abs($0.time - target) < abs($1.time - target) }
    }
}

private struct SelectionCallout: View {
    let sample: DiveSample
    let units: UnitSystem

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(UnitSystem.formatDuration(sample.time)).font(.caption2).foregroundStyle(.secondary)
            Text(units.formatDepth(sample.depth)).font(.caption.bold())
            if let temperature = sample.temperature {
                Text(units.formatTemperature(temperature)).font(.caption2)
            }
            if let pressure = sample.tankPressure {
                Text(units.formatPressure(pressure)).font(.caption2)
            }
        }
        .padding(6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

/// Lets VoiceOver users explore the profile as an audio graph.
struct ProfileChartDescriptor: AXChartDescriptorRepresentable {
    let profile: DiveProfile
    let units: UnitSystem

    func makeChartDescriptor() -> AXChartDescriptor {
        let samples = profile.downsampled(maxPoints: 120)
        let durationMinutes = max(profile.duration / 60, 1)
        let maxDepth = max(units.depth(fromMeters: profile.maxDepth), 1)
        let unit = units

        let xAxis = AXNumericDataAxisDescriptor(
            title: "Time in minutes",
            range: 0...durationMinutes,
            gridlinePositions: []
        ) { value in "\(Int(value.rounded())) minutes" }

        let yAxis = AXNumericDataAxisDescriptor(
            title: "Depth in \(unit == .metric ? "metres" : "feet")",
            range: 0...maxDepth,
            gridlinePositions: []
        ) { value in "\(UnitSystem.format(value, decimals: unit == .metric ? 1 : 0)) \(unit == .metric ? "metres" : "feet")" }

        let series = AXDataSeriesDescriptor(
            name: "Depth",
            isContinuous: true,
            dataPoints: samples.map { AXDataPoint(x: $0.time / 60, y: units.depth(fromMeters: $0.depth)) }
        )

        return AXChartDescriptor(
            title: "Dive profile",
            summary: "Maximum depth \(units.formatDepth(profile.maxDepth)) over \(UnitSystem.spokenDuration(profile.duration)).",
            xAxis: xAxis,
            yAxis: yAxis,
            additionalAxes: [],
            series: [series]
        )
    }
}
