import Foundation
import Testing
@testable import UnderlogCore

/// Builds small FIT files in memory for tests, following the public FIT file layout.
struct FITWriter {
    struct Field {
        let number: UInt8
        let size: UInt8
        let baseType: UInt8
    }

    enum BaseType {
        static let enumType: UInt8 = 0x00
        static let sint8: UInt8 = 0x01
        static let uint8: UInt8 = 0x02
        static let uint16: UInt8 = 0x84
        static let sint32: UInt8 = 0x85
        static let uint32: UInt8 = 0x86
        static let string: UInt8 = 0x07
    }

    private var body: [UInt8] = []
    private var layouts: [UInt8: (fields: [Field], bigEndian: Bool, developerBytes: Int)] = [:]

    mutating func define(local: UInt8, global: UInt16, fields: [Field], bigEndian: Bool = false, developerFieldSizes: [UInt8] = []) {
        let hasDeveloper = !developerFieldSizes.isEmpty
        body.append(0x40 | (hasDeveloper ? 0x20 : 0) | local)
        body.append(0) // reserved
        body.append(bigEndian ? 1 : 0)
        body += bytes(UInt64(global), size: 2, bigEndian: bigEndian)
        body.append(UInt8(fields.count))
        for field in fields { body += [field.number, field.size, field.baseType] }
        if hasDeveloper {
            body.append(UInt8(developerFieldSizes.count))
            for (i, size) in developerFieldSizes.enumerated() { body += [UInt8(i), size, 0] }
        }
        layouts[local] = (fields, bigEndian, developerFieldSizes.reduce(0) { $0 + Int($1) })
    }

    /// Values are raw bit patterns; strings are passed with `text`.
    mutating func data(local: UInt8, _ values: [UInt64], text: [UInt8: String] = [:]) {
        body.append(local)
        writeValues(local: local, values, text: text)
    }

    mutating func compressedData(local: UInt8, timestamp: UInt32, _ values: [UInt64]) {
        body.append(0x80 | (local << 5) | UInt8(timestamp & 0x1F))
        writeValues(local: local, values, text: [:])
    }

    private mutating func writeValues(local: UInt8, _ values: [UInt64], text: [UInt8: String]) {
        let layout = layouts[local]!
        var valueIterator = values.makeIterator()
        for field in layout.fields {
            if field.baseType == BaseType.string {
                var encoded = Array((text[field.number] ?? "").utf8.prefix(Int(field.size) - 1))
                encoded += Array(repeating: 0, count: Int(field.size) - encoded.count)
                body += encoded
            } else {
                body += bytes(valueIterator.next()!, size: Int(field.size), bigEndian: layout.bigEndian)
            }
        }
        body += Array(repeating: 0xAB, count: layout.developerBytes)
    }

    func file() -> Data {
        var header: [UInt8] = [14, 0x20]
        header += bytes(2195, size: 2, bigEndian: false) // profile version
        header += bytes(UInt64(body.count), size: 4, bigEndian: false)
        header += Array(".FIT".utf8)
        header += bytes(UInt64(FITCRC.checksum(header)), size: 2, bigEndian: false)
        var file = header + body
        file += bytes(UInt64(FITCRC.checksum(file)), size: 2, bigEndian: false)
        return Data(file)
    }

    private func bytes(_ value: UInt64, size: Int, bigEndian: Bool) -> [UInt8] {
        let little = (0..<size).map { UInt8((value >> (8 * UInt64($0))) & 0xFF) }
        return bigEndian ? little.reversed() : little
    }
}

@Suite("Garmin FIT import")
struct FITTests {
    typealias F = FITWriter.Field
    typealias T = FITWriter.BaseType

    /// Chosen so that the low five bits are 25: compressed offsets then wrap past 31, which the decoder must handle.
    let t0: UInt32 = 1_000_000_025

    func sampleDiveFile() -> Data {
        var w = FITWriter()

        // file_id with product name
        w.define(local: 0, global: 0, fields: [F(number: 8, size: 16, baseType: T.string)])
        w.data(local: 0, [], text: [8: "Descent G1"])

        // dive_gas: one enabled EAN32, one disabled 50%
        w.define(local: 2, global: 259, fields: [
            F(number: 254, size: 2, baseType: T.uint16),
            F(number: 1, size: 1, baseType: T.uint8),
            F(number: 0, size: 1, baseType: T.uint8),
            F(number: 2, size: 1, baseType: T.enumType),
        ])
        w.data(local: 2, [0, 32, 0, 1])
        w.data(local: 2, [1, 50, 0, 0])

        // Full record: timestamp, depth (mm), temperature (C)
        w.define(local: 3, global: 20, fields: [
            F(number: 253, size: 4, baseType: T.uint32),
            F(number: 92, size: 4, baseType: T.uint32),
            F(number: 13, size: 1, baseType: T.sint8),
        ])
        w.data(local: 3, [UInt64(t0), 0, 21])

        // A record type carrying a developer field the decoder must skip.
        w.define(local: 4, global: 20, fields: [
            F(number: 253, size: 4, baseType: T.uint32),
            F(number: 92, size: 4, baseType: T.uint32),
        ], developerFieldSizes: [2])
        w.data(local: 4, [UInt64(t0 + 5), 2_000])

        // Compressed-timestamp records (local type 1): depth and temperature only.
        w.define(local: 1, global: 20, fields: [
            F(number: 92, size: 4, baseType: T.uint32),
            F(number: 13, size: 1, baseType: T.sint8),
        ])
        w.compressedData(local: 1, timestamp: t0 + 10, [5_000, 19])
        w.compressedData(local: 1, timestamp: t0 + 20, [18_000, UInt64(UInt8(bitPattern: -2))])
        w.compressedData(local: 1, timestamp: t0 + 30, [10_000, 0x7F]) // 0x7F = invalid temperature

        w.data(local: 3, [UInt64(t0 + 40), 0, 20])

        // session, written big-endian: start time, elapsed time (ms), sub sport, position
        w.define(local: 5, global: 18, fields: [
            F(number: 2, size: 4, baseType: T.uint32),
            F(number: 7, size: 4, baseType: T.uint32),
            F(number: 6, size: 1, baseType: T.enumType),
            F(number: 3, size: 4, baseType: T.sint32),
            F(number: 4, size: 4, baseType: T.sint32),
        ], bigEndian: true)
        let lat = Int32((47.5 / 180 * 2_147_483_648).rounded())
        let lon = Int32((19.04 / 180 * 2_147_483_648).rounded())
        w.data(local: 5, [UInt64(t0), 40_000, 54, UInt64(UInt32(bitPattern: lat)), UInt64(UInt32(bitPattern: lon))])

        // dive_summary: max depth (mm), dive number
        w.define(local: 6, global: 268, fields: [
            F(number: 0, size: 2, baseType: T.uint16),
            F(number: 3, size: 4, baseType: T.uint32),
            F(number: 10, size: 4, baseType: T.uint32),
        ])
        w.data(local: 6, [18, 18_000, 42])

        return w.file()
    }

    @Test func importsADive() throws {
        let dives = try FITImporter.importDives(from: sampleDiveFile())
        let dive = try #require(dives.first)
        #expect(dives.count == 1)
        #expect(dive.startDate == FITDecoder.epoch.addingTimeInterval(TimeInterval(t0)))
        #expect(dive.samples.map(\.time) == [0, 5, 10, 20, 30, 40])
        #expect(dive.samples.map(\.depth) == [0, 2, 5, 18, 10, 0])
        #expect(dive.samples[3].temperature == -2)
        #expect(dive.samples[4].temperature == nil)
        #expect(dive.maxDepth == 18)
        #expect(dive.duration == 40)
        #expect(dive.diveNumber == 42)
        #expect(dive.mode == .openCircuit)
        #expect(dive.cylinders.map(\.gas) == [GasMix(oxygen: 0.32)])
        #expect(dive.deviceName == "Descent G1")
        #expect(dive.minTemperature == -2)
        let site = try #require(dive.site)
        #expect(abs((site.latitude ?? 0) - 47.5) < 1e-6)
        #expect(abs((site.longitude ?? 0) - 19.04) < 1e-6)
    }

    @Test func rejectsANonDiveActivity() {
        var w = FITWriter()
        w.define(local: 0, global: 20, fields: [
            F(number: 253, size: 4, baseType: T.uint32),
            F(number: 3, size: 1, baseType: T.uint8), // heart rate only, like a run
        ])
        w.data(local: 0, [UInt64(t0), 120])
        #expect(throws: FITImporter.ImportError.noDiveData) {
            try FITImporter.importDives(from: w.file())
        }
    }

    @Test func rejectsNonFITData() {
        #expect(throws: FITDecoder.DecodingError.notAFITFile) {
            try FITImporter.importDives(from: Data("hello, this is not a fit file".utf8))
        }
    }

    @Test func detectsTruncatedFiles() {
        let data = sampleDiveFile()
        #expect(throws: FITDecoder.DecodingError.self) {
            try FITDecoder.decode(data.prefix(data.count - 30))
        }
    }

    @Test func freediveModeFromSubSport() {
        #expect(FITImporter.diveMode(subSport: 56) == .freedive)
        #expect(FITImporter.diveMode(subSport: 63) == .closedCircuitRebreather)
        #expect(FITImporter.diveMode(subSport: 55) == .gauge)
        #expect(FITImporter.diveMode(subSport: nil) == .openCircuit)
    }

    @Test func crcMatchesTheStandardCheckValue() {
        // FIT uses the CRC-16 variant whose standard check value for "123456789" is 0xBB3D.
        #expect(FITCRC.checksum(Array("123456789".utf8)) == 0xBB3D)
    }
}
