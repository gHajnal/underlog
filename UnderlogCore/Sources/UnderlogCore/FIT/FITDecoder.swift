import Foundation

/// One decoded FIT data message: its global message number and its numeric and text fields.
public struct FITMessage: Sendable {
    public var globalNumber: UInt16
    /// Numeric fields by field number, already with invalid values removed. Arrays keep their first element.
    public var values: [UInt8: Double]
    public var strings: [UInt8: String]

    public func value(_ field: UInt8) -> Double? { values[field] }
}

/// Decodes the binary FIT container (headers, definitions, data records) into messages.
///
/// Follows the public FIT protocol: a 12- or 14-byte file header, then records that are either
/// definition messages (describing the field layout for a local message type) or data messages,
/// plus the compressed-timestamp header form. Developer fields are skipped.
public enum FITDecoder {
    public enum DecodingError: Error, Equatable {
        case notAFITFile
        case truncated
        case undefinedLocalMessage(UInt8)
    }

    /// The FIT timestamp epoch: 1989-12-31 00:00:00 UTC.
    public static let epoch = Date(timeIntervalSince1970: 631_065_600)

    private struct FieldDefinition {
        let number: UInt8
        let size: Int
        let baseType: UInt8
    }

    private struct Definition {
        let globalNumber: UInt16
        let littleEndian: Bool
        let fields: [FieldDefinition]
        let developerBytes: Int
    }

    public static func decode(_ data: Data) throws -> [FITMessage] {
        let bytes = [UInt8](data)
        var messages: [FITMessage] = []
        var fileStart = 0
        // A file may contain several FIT files chained back to back.
        repeat {
            let (fileMessages, nextStart) = try decodeFile(bytes, from: fileStart)
            messages += fileMessages
            fileStart = nextStart
        } while fileStart + 12 <= bytes.count && isHeader(bytes, at: fileStart)
        return messages
    }

    static func isHeader(_ bytes: [UInt8], at start: Int) -> Bool {
        guard start + 12 <= bytes.count else { return false }
        let size = Int(bytes[start])
        return (size == 12 || size == 14) && bytes[start + 8] == 0x2E && bytes[start + 9] == 0x46
            && bytes[start + 10] == 0x49 && bytes[start + 11] == 0x54 // ".FIT"
    }

    private static func decodeFile(_ bytes: [UInt8], from start: Int) throws -> ([FITMessage], Int) {
        guard isHeader(bytes, at: start) else { throw DecodingError.notAFITFile }
        let headerSize = Int(bytes[start])
        let dataSize = Int(readUInt(bytes, at: start + 4, size: 4, littleEndian: true))
        let dataStart = start + headerSize
        let declaredEnd = dataStart + dataSize
        // A file shorter than its header says was cut off, even if the cut falls between records.
        guard declaredEnd <= bytes.count else { throw DecodingError.truncated }
        let end = declaredEnd

        var definitions: [UInt8: Definition] = [:]
        var messages: [FITMessage] = []
        var lastTimestamp: UInt32 = 0
        var p = dataStart

        while p < end {
            let header = bytes[p]
            p += 1

            if header & 0x80 != 0 {
                // Compressed timestamp header: local type in bits 5-6, time offset in bits 0-4.
                let local = (header >> 5) & 0x03
                let offset = UInt32(header & 0x1F)
                // Wrapping arithmetic: a malformed file must not be able to crash the importer.
                var timestamp = (lastTimestamp & ~UInt32(0x1F)) &+ offset
                if offset < (lastTimestamp & 0x1F) { timestamp &+= 0x20 }
                lastTimestamp = timestamp
                guard let definition = definitions[local] else { throw DecodingError.undefinedLocalMessage(local) }
                var message = try readData(bytes, at: &p, end: end, definition: definition)
                message.values[253] = Double(timestamp)
                messages.append(message)
                continue
            }

            let local = header & 0x0F
            if header & 0x40 != 0 {
                let hasDeveloperFields = header & 0x20 != 0
                definitions[local] = try readDefinition(bytes, at: &p, end: end, hasDeveloperFields: hasDeveloperFields)
            } else {
                guard let definition = definitions[local] else { throw DecodingError.undefinedLocalMessage(local) }
                let message = try readData(bytes, at: &p, end: end, definition: definition)
                if let ts = message.values[253], let exact = UInt32(exactly: ts) { lastTimestamp = exact }
                messages.append(message)
            }
        }
        // Skip the 2-byte file CRC.
        return (messages, declaredEnd + 2)
    }

    private static func readDefinition(_ bytes: [UInt8], at p: inout Int, end: Int, hasDeveloperFields: Bool) throws -> Definition {
        guard p + 5 <= end else { throw DecodingError.truncated }
        let littleEndian = bytes[p + 1] == 0
        let global = UInt16(readUInt(bytes, at: p + 2, size: 2, littleEndian: littleEndian))
        let count = Int(bytes[p + 4])
        p += 5
        guard p + count * 3 <= end else { throw DecodingError.truncated }
        var fields: [FieldDefinition] = []
        for _ in 0..<count {
            fields.append(FieldDefinition(number: bytes[p], size: Int(bytes[p + 1]), baseType: bytes[p + 2]))
            p += 3
        }
        var developerBytes = 0
        if hasDeveloperFields {
            guard p + 1 <= end else { throw DecodingError.truncated }
            let devCount = Int(bytes[p])
            p += 1
            guard p + devCount * 3 <= end else { throw DecodingError.truncated }
            for _ in 0..<devCount {
                developerBytes += Int(bytes[p + 1])
                p += 3
            }
        }
        return Definition(globalNumber: global, littleEndian: littleEndian, fields: fields, developerBytes: developerBytes)
    }

    private static func readData(_ bytes: [UInt8], at p: inout Int, end: Int, definition: Definition) throws -> FITMessage {
        var message = FITMessage(globalNumber: definition.globalNumber, values: [:], strings: [:])
        for field in definition.fields {
            guard p + field.size <= end else { throw DecodingError.truncated }
            let typeIndex = field.baseType & 0x1F
            if typeIndex == 7 {
                let raw = bytes[p..<(p + field.size)].prefix { $0 != 0 }
                if let text = String(bytes: raw, encoding: .utf8), !text.isEmpty {
                    message.strings[field.number] = text
                }
            } else if let value = decodeNumber(bytes, at: p, size: field.size, typeIndex: typeIndex, littleEndian: definition.littleEndian) {
                message.values[field.number] = value
            }
            p += field.size
        }
        guard p + definition.developerBytes <= end else { throw DecodingError.truncated }
        p += definition.developerBytes
        return message
    }

    /// Base type sizes indexed by the low five bits of the base type byte.
    private static let baseSizes: [Int] = [1, 1, 1, 2, 2, 4, 4, 1, 4, 8, 1, 2, 4, 1, 8, 8, 8]

    private static func decodeNumber(_ bytes: [UInt8], at p: Int, size: Int, typeIndex: UInt8, littleEndian: Bool) -> Double? {
        guard Int(typeIndex) < baseSizes.count else { return nil }
        let elementSize = baseSizes[Int(typeIndex)]
        guard size >= elementSize, size % elementSize == 0 else { return nil }
        let raw = readUInt(bytes, at: p, size: elementSize, littleEndian: littleEndian)

        switch typeIndex {
        case 0, 2, 13: return raw == 0xFF ? nil : Double(raw) // enum, uint8, byte
        case 1: return raw == 0x7F ? nil : Double(Int8(bitPattern: UInt8(raw)))
        case 3: return raw == 0x7FFF ? nil : Double(Int16(bitPattern: UInt16(raw)))
        case 4: return raw == 0xFFFF ? nil : Double(raw)
        case 5: return raw == 0x7FFF_FFFF ? nil : Double(Int32(bitPattern: UInt32(raw)))
        case 6: return raw == 0xFFFF_FFFF ? nil : Double(raw)
        case 8:
            guard raw != 0xFFFF_FFFF else { return nil }
            let value = Double(Float(bitPattern: UInt32(raw)))
            return value.isFinite ? value : nil
        case 9:
            guard raw != UInt64.max else { return nil }
            let value = Double(bitPattern: raw)
            return value.isFinite ? value : nil
        case 10, 11, 12, 16: return raw == 0 ? nil : Double(raw) // "z" types use 0 as invalid
        case 14: return raw == 0x7FFF_FFFF_FFFF_FFFF ? nil : Double(Int64(bitPattern: raw))
        case 15: return raw == UInt64.max ? nil : Double(raw)
        default: return nil
        }
    }

    static func readUInt(_ bytes: [UInt8], at p: Int, size: Int, littleEndian: Bool) -> UInt64 {
        var value: UInt64 = 0
        for i in 0..<size {
            let byte = UInt64(bytes[littleEndian ? p + i : p + size - 1 - i])
            value |= byte << (8 * UInt64(i))
        }
        return value
    }
}

/// The CRC-16 used by FIT files.
public enum FITCRC {
    private static let table: [UInt16] = [
        0x0000, 0xCC01, 0xD801, 0x1400, 0xF001, 0x3C00, 0x2800, 0xE401,
        0xA001, 0x6C00, 0x7800, 0xB401, 0x5000, 0x9C01, 0x8801, 0x4400,
    ]

    public static func checksum<S: Sequence>(_ bytes: S, start: UInt16 = 0) -> UInt16 where S.Element == UInt8 {
        var crc = start
        for byte in bytes {
            var tmp = table[Int(crc & 0xF)]
            crc = (crc >> 4) & 0x0FFF
            crc = crc ^ tmp ^ table[Int(byte & 0xF)]
            tmp = table[Int(crc & 0xF)]
            crc = (crc >> 4) & 0x0FFF
            crc = crc ^ tmp ^ table[Int((byte >> 4) & 0xF)]
        }
        return crc
    }
}
