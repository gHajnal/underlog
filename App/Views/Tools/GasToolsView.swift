import SwiftUI
import UnderlogCore

/// Quick gas calculations: maximum operating depth, ppO2, narcotic depth, best mix and SAC.
struct GasToolsView: View {
    @AppStorage(SettingsKey.unitSystem) private var units: UnitSystem = .metric
    @AppStorage(SettingsKey.defaultWaterType) private var water: WaterType = .salt
    @AppStorage(SettingsKey.maxPPO2) private var maxPPO2 = 1.4

    @State private var oxygenPercent = 32.0
    @State private var heliumPercent = 0.0
    @State private var depthMeters: Double? = 30

    @State private var cylinderLiters: Double? = 12
    @State private var startBar: Double? = 200
    @State private var endBar: Double? = 70
    @State private var minutes: Double? = 45
    @State private var averageDepthMeters: Double? = 15

    private var gas: GasMix { GasMix(oxygen: oxygenPercent / 100, helium: heliumPercent / 100) }

    var body: some View {
        NavigationStack {
            Form {
                Section("Gas") {
                    PercentStepper(title: "Oxygen", value: $oxygenPercent, range: 1...100)
                        .onChange(of: oxygenPercent) { _, oxygen in heliumPercent = min(heliumPercent, 100 - oxygen) }
                    PercentStepper(title: "Helium", value: $heliumPercent, range: 0...(100 - oxygenPercent))
                    Picker("Max ppO₂", selection: $maxPPO2) {
                        ForEach([1.2, 1.3, 1.4, 1.5, 1.6], id: \.self) { Text("\(UnitSystem.format($0, decimals: 1)) bar").tag($0) }
                    }
                    Picker("Water", selection: $water) {
                        ForEach(WaterType.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                }

                Section("Results for \(gas.name)") {
                    ResultRow(label: "Maximum operating depth",
                              value: units.formatDepth(GasCalculator.maximumOperatingDepth(gas, maxPPO2: maxPPO2, water: water)))
                        .accessibilityIdentifier(A11yID.toolsMOD)
                    NumberField("At depth", value: depth($depthMeters), unit: units.depthUnit, identifier: A11yID.toolsDepth)
                    if let depth = depthMeters {
                        let ppO2 = GasCalculator.ppO2(gas, atDepth: depth, water: water)
                        ResultRow(label: "ppO₂", value: "\(UnitSystem.format(ppO2, decimals: 2)) bar",
                                  warning: ppO2 > maxPPO2 ? "Above your limit of \(UnitSystem.format(maxPPO2, decimals: 1)) bar" : nil)
                        ResultRow(label: "Equivalent narcotic depth",
                                  value: units.formatDepth(GasCalculator.equivalentNarcoticDepth(gas, atDepth: depth, water: water)))
                        if gas.helium == 0 {
                            ResultRow(label: "Equivalent air depth",
                                      value: units.formatDepth(GasCalculator.equivalentAirDepth(gas, atDepth: depth, water: water)))
                        }
                        ResultRow(label: "Best nitrox for this depth",
                                  value: GasMix(oxygen: (GasCalculator.bestMixOxygen(forDepth: depth, maxPPO2: maxPPO2, water: water) * 100).rounded(.down) / 100).name)
                    }
                }

                Section {
                    NumberField("Cylinder volume", value: $cylinderLiters, unit: "L")
                    NumberField("Start pressure", value: pressure($startBar), unit: units.pressureUnit)
                    NumberField("End pressure", value: pressure($endBar), unit: units.pressureUnit)
                    NumberField("Dive time", value: $minutes, unit: "min")
                    NumberField("Average depth", value: depth($averageDepthMeters), unit: units.depthUnit)
                    if let sac = surfaceConsumption {
                        ResultRow(label: "Surface air consumption",
                                  value: "\(UnitSystem.format(units.volume(fromLiters: sac), decimals: 1)) \(units.volumeUnit)/min")
                    } else {
                        Text("Fill in all values, with a start pressure higher than the end pressure.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Gas consumption")
                }
            }
            .safeAreaInset(edge: .bottom) {
                Text("For reference only. Plan dives with your training, your dive computer and your agency's tables.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .background(.bar)
            }
            .navigationTitle("Gas tools")
        }
    }

    private var surfaceConsumption: Double? {
        guard let cylinderLiters, let startBar, let endBar, let minutes, let averageDepthMeters else { return nil }
        return GasCalculator.surfaceAirConsumption(
            cylinderVolumeLiters: cylinderLiters, startPressureBar: startBar, endPressureBar: endBar,
            durationSeconds: minutes * 60, averageDepth: averageDepthMeters, water: water
        )
    }

    private func depth(_ binding: Binding<Double?>) -> Binding<Double?> {
        Binding(get: { binding.wrappedValue.map(units.depth(fromMeters:)) },
                set: { binding.wrappedValue = $0.map(units.meters(fromDepth:)) })
    }

    private func pressure(_ binding: Binding<Double?>) -> Binding<Double?> {
        Binding(get: { binding.wrappedValue.map(units.pressure(fromBar:)) },
                set: { binding.wrappedValue = $0.map(units.bar(fromPressure:)) })
    }
}

private struct ResultRow: View {
    let label: String
    let value: String
    var warning: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            LabeledContent(label) {
                Text(value).monospacedDigit().fontWeight(.semibold)
            }
            if let warning {
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
