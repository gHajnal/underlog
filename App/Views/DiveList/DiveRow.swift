import SwiftUI
import UnderlogCore

struct DiveRow: View {
    let dive: Dive
    let units: UnitSystem

    var body: some View {
        HStack(spacing: 14) {
            DepthBadge(depth: dive.maxDepth)

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(dive.title)
                        .font(.headline)
                        .lineLimit(2)
                    Spacer(minLength: 8)
                    Text("#\(dive.number)")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Text(dive.startDate.formatted(date: .abbreviated, time: .shortened))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) { metrics }
                    VStack(alignment: .leading, spacing: 2) { metrics }
                }
                .font(.subheadline)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    @ViewBuilder
    private var metrics: some View {
        Label(units.formatDepth(dive.maxDepth), systemImage: "arrow.down.to.line")
        Label(UnitSystem.formatDuration(dive.duration), systemImage: "clock")
        if let gas = dive.primaryGasName {
            Label(gas, systemImage: "aqi.medium")
        }
    }

    private var accessibilityText: String {
        var parts = [
            "Dive \(dive.number)",
            dive.title,
            dive.startDate.formatted(date: .long, time: .shortened),
            "maximum depth \(units.formatDepth(dive.maxDepth))",
            UnitSystem.spokenDuration(dive.duration),
        ]
        if let gas = dive.primaryGasName { parts.append(gas) }
        if dive.rating > 0 { parts.append("rated \(dive.rating) of 5") }
        return parts.joined(separator: ", ")
    }
}

/// A small tile whose colour deepens with the dive's maximum depth.
struct DepthBadge: View {
    let depth: Double
    @ScaledMetric(relativeTo: .headline) private var size = 44

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(color.gradient)
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: "water.waves")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
            }
            .accessibilityHidden(true)
    }

    private var color: Color {
        let fraction = min(depth / 40, 1)
        return Color(
            red: 0.36 + (0.05 - 0.36) * fraction,
            green: 0.72 + (0.27 - 0.72) * fraction,
            blue: 0.85 + (0.52 - 0.85) * fraction
        )
    }
}
