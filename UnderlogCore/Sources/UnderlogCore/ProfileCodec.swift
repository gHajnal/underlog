import Foundation

/// Compact binary storage for dive profiles.
///
/// Layout (little-endian): version (UInt8), field flags (UInt8), sample count (UInt32),
/// then one Float32 column per field: time, depth, and each optional field that is present.
/// Missing values inside an optional column are stored as NaN.
public enum ProfileCodec {
    public static let currentVersion: UInt8 = 1

    public enum DecodingError: Error, Equatable {
        case empty
        case unsupportedVersion(UInt8)
        case truncated
    }

    private struct Field: Sendable {
        let flag: UInt8
        let get: @Sendable (DiveSample) -> Double?
        let set: @Sendable (inout DiveSample, Double?) -> Void
    }

    private static let optionalFields: [Field] = [
        Field(flag: 1 << 0, get: { $0.temperature }, set: { $0.temperature = $1 }),
        Field(flag: 1 << 1, get: { $0.tankPressure }, set: { $0.tankPressure = $1 }),
        Field(flag: 1 << 2, get: { $0.heartRate }, set: { $0.heartRate = $1 }),
        Field(flag: 1 << 3, get: { $0.noDecoTime }, set: { $0.noDecoTime = $1 }),
        Field(flag: 1 << 4, get: { $0.stopDepth }, set: { $0.stopDepth = $1 }),
    ]

    public static func encode(_ samples: [DiveSample]) -> Data {
        var flags: UInt8 = 0
        for field in optionalFields where samples.contains(where: { field.get($0) != nil }) {
            flags |= field.flag
        }
        var data = Data()
        data.append(currentVersion)
        data.append(flags)
        append(UInt32(samples.count), to: &data)
        appendColumn(samples.map { $0.time }, to: &data)
        appendColumn(samples.map { $0.depth }, to: &data)
        for field in optionalFields where flags & field.flag != 0 {
            appendColumn(samples.map { field.get($0) ?? .nan }, to: &data)
        }
        return data
    }

    public static func decode(_ data: Data) throws -> [DiveSample] {
        let bytes = [UInt8](data)
        guard bytes.count >= 6 else { throw bytes.isEmpty ? DecodingError.empty : DecodingError.truncated }
        guard bytes[0] == currentVersion else { throw DecodingError.unsupportedVersion(bytes[0]) }
        let flags = bytes[1]
        let count = Int(UInt32(bytes[2]) | UInt32(bytes[3]) << 8 | UInt32(bytes[4]) << 16 | UInt32(bytes[5]) << 24)
        let present = optionalFields.filter { flags & $0.flag != 0 }
        let columnBytes = count * 4
        guard bytes.count >= 6 + columnBytes * (2 + present.count) else { throw DecodingError.truncated }

        var offset = 6
        func readColumn() -> [Double] {
            var values = [Double]()
            values.reserveCapacity(count)
            for i in 0..<count {
                let p = offset + i * 4
                let bits = UInt32(bytes[p]) | UInt32(bytes[p + 1]) << 8 | UInt32(bytes[p + 2]) << 16 | UInt32(bytes[p + 3]) << 24
                values.append(Double(Float(bitPattern: bits)))
            }
            offset += columnBytes
            return values
        }

        let times = readColumn()
        let depths = readColumn()
        var samples = (0..<count).map { DiveSample(time: times[$0], depth: depths[$0]) }
        for field in present {
            let column = readColumn()
            for i in 0..<count where !column[i].isNaN {
                field.set(&samples[i], column[i])
            }
        }
        return samples
    }

    private static func append(_ value: UInt32, to data: inout Data) {
        data.append(UInt8(value & 0xFF))
        data.append(UInt8((value >> 8) & 0xFF))
        data.append(UInt8((value >> 16) & 0xFF))
        data.append(UInt8((value >> 24) & 0xFF))
    }

    private static func appendColumn(_ values: [Double], to data: inout Data) {
        data.reserveCapacity(data.count + values.count * 4)
        for value in values {
            append(Float(value).bitPattern, to: &data)
        }
    }
}
