import SwiftUI
import UnderlogCore

struct CylinderEditorView: View {
    @Binding var cylinder: CylinderDraft
    let water: WaterType
    @AppStorage(SettingsKey.unitSystem) private var units: UnitSystem = .metric
    @AppStorage(SettingsKey.maxPPO2) private var maxPPO2 = 1.4

    var body: some View {
        Form {
            if let error = cylinder.validationError {
                Section {
                    Label(error, systemImage: "exclamationmark.circle").foregroundStyle(.red)
                }
            }

            Section {
                PercentStepper(title: "Oxygen", value: $cylinder.oxygenPercent, range: 1...100)
                PercentStepper(title: "Helium", value: $cylinder.heliumPercent, range: 0...99)
                HStack {
                    ForEach(presets, id: \.name) { preset in
                        Button(preset.name) {
                            cylinder.oxygenPercent = Double(preset.oxygenPercent)
                            cylinder.heliumPercent = Double(preset.heliumPercent)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            } header: {
                Text("Gas mix")
            } footer: {
                if cylinder.validationError == nil {
                    Text("\(cylinder.gas.name): maximum operating depth \(units.formatDepth(GasCalculator.maximumOperatingDepth(cylinder.gas, maxPPO2: maxPPO2, water: water))) at \(UnitSystem.format(maxPPO2, decimals: 1)) bar ppO₂.")
                }
            }

            Section("Cylinder") {
                TextField("Name (for example 12 L steel)", text: $cylinder.name)
                NumberField("Volume", value: $cylinder.volumeLiters, unit: "L")
                NumberField("Working pressure", value: pressure($cylinder.workingPressureBar), unit: units.pressureUnit)
            }

            Section("Pressure") {
                NumberField("Start", value: pressure($cylinder.startPressureBar), unit: units.pressureUnit)
                NumberField("End", value: pressure($cylinder.endPressureBar), unit: units.pressureUnit)
            }
        }
        .navigationTitle(cylinder.gas.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var presets: [GasMix] {
        [.air, GasMix(oxygen: 0.32), GasMix(oxygen: 0.36), GasMix(oxygen: 0.5), .pureOxygen]
    }

    private func pressure(_ binding: Binding<Double?>) -> Binding<Double?> {
        Binding(
            get: { binding.wrappedValue.map(units.pressure(fromBar:)) },
            set: { binding.wrappedValue = $0.map(units.bar(fromPressure:)) }
        )
    }
}

struct PercentStepper: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>

    var body: some View {
        Stepper(value: $value, in: range, step: 1) {
            LabeledContent(title, value: "\(Int(value.rounded())) %")
        }
        .accessibilityValue("\(Int(value.rounded())) percent")
    }
}
