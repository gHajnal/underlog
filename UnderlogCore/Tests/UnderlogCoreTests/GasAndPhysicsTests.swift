import Testing
@testable import UnderlogCore

@Suite("Physics and gas calculations")
struct GasAndPhysicsTests {
    @Test func absolutePressureInSaltWater() {
        #expect(abs(Physics.absolutePressure(atDepth: 10) - 2.0185) < 0.001)
        #expect(Physics.absolutePressure(atDepth: 0) == Physics.standardSurfacePressure)
    }

    @Test func freshWaterAddsLessPressure() {
        #expect(Physics.absolutePressure(atDepth: 30, water: .fresh) < Physics.absolutePressure(atDepth: 30, water: .salt))
    }

    @Test func depthAndPressureAreInverse() {
        let pressure = Physics.absolutePressure(atDepth: 42.5, water: .en13319)
        #expect(abs(Physics.depth(forAbsolutePressure: pressure, water: .en13319) - 42.5) < 1e-9)
    }

    @Test func maximumOperatingDepth() {
        #expect(abs(GasCalculator.maximumOperatingDepth(GasMix(oxygen: 0.32)) - 33.44) < 0.05)
        #expect(abs(GasCalculator.maximumOperatingDepth(.air) - 56.24) < 0.05)
        #expect(abs(GasCalculator.maximumOperatingDepth(.pureOxygen, maxPPO2: 1.6) - 5.84) < 0.05)
    }

    @Test func ppO2AtDepth() {
        #expect(abs(GasCalculator.ppO2(GasMix(oxygen: 0.32), atDepth: 30) - 1.289) < 0.001)
    }

    @Test func equivalentNarcoticDepthForTrimix() {
        let trimix = GasMix(oxygen: 0.21, helium: 0.35)
        #expect(abs(GasCalculator.equivalentNarcoticDepth(trimix, atDepth: 60) - 35.47) < 0.05)
        // Without counting oxygen as narcotic the END is shallower.
        #expect(GasCalculator.equivalentNarcoticDepth(trimix, atDepth: 60, oxygenIsNarcotic: false) < 35.47)
    }

    @Test func equivalentAirDepthForNitrox() {
        #expect(abs(GasCalculator.equivalentAirDepth(GasMix(oxygen: 0.32), atDepth: 30) - 24.42) < 0.05)
        #expect(abs(GasCalculator.equivalentAirDepth(.air, atDepth: 30) - 30) < 1e-9)
    }

    @Test func bestMix() {
        #expect(abs(GasCalculator.bestMixOxygen(forDepth: 30) - 0.3475) < 0.001)
        #expect(GasCalculator.bestMixOxygen(forDepth: 0, maxPPO2: 1.6) == 1.0)
    }

    @Test func surfaceAirConsumption() throws {
        let sac = try #require(GasCalculator.surfaceAirConsumption(
            cylinderVolumeLiters: 12, startPressureBar: 200, endPressureBar: 50,
            durationSeconds: 50 * 60, averageDepth: 15
        ))
        #expect(abs(sac - 14.28) < 0.05)
        #expect(GasCalculator.surfaceAirConsumption(
            cylinderVolumeLiters: 12, startPressureBar: 50, endPressureBar: 200,
            durationSeconds: 600, averageDepth: 10
        ) == nil)
    }

    @Test(arguments: [
        (GasMix.air, "Air"),
        (GasMix(oxygen: 0.32), "EAN32"),
        (GasMix.pureOxygen, "Oxygen"),
        (GasMix(oxygen: 0.18, helium: 0.45), "Tx 18/45"),
        (GasMix(oxygen: 0.10), "Hypoxic 10"),
    ])
    func gasNames(mix: GasMix, name: String) {
        #expect(mix.name == name)
    }

    @Test func gasValidity() {
        #expect(GasMix(oxygen: 0.21, helium: 0.35).isValid)
        #expect(!GasMix(oxygen: 0.5, helium: 0.6).isValid)
        #expect(!GasMix(oxygen: 0).isValid)
    }
}
