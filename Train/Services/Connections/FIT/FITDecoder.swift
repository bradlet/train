//
//  FITDecoder.swift
//  Train
//
//  A small, pure decoder for Garmin's FIT binary format (#22): enough to read
//  an activity file's messages and their single-value numeric fields. It
//  handles normal and compressed-timestamp record headers, both
//  architectures, developer fields (skipped), invalid-value sentinels, and
//  chained files. Strings and arrays are skipped; nothing here needs them.
//
//  Format reference: the FIT Protocol in Garmin's FIT SDK.
//

import Foundation

/// One decoded FIT data message.
struct FITMessage: Equatable, Sendable {
    /// The profile's global message number (e.g. 18 = session).
    let globalNumber: UInt16
    /// Field number → value, for single-value numeric fields that weren't
    /// the type's "invalid" sentinel.
    let fields: [UInt8: Double]

    /// A field's value.
    subscript(_ field: UInt8) -> Double? { fields[field] }
}

/// Why a FIT file couldn't be read.
enum FITDecodeError: Error, Equatable, LocalizedError {
    /// Too short, or no ".FIT" signature.
    case notFIT
    /// The data ran out mid-record.
    case truncated
    /// A data message used a local type with no definition.
    case undefinedLocalType(UInt8)

    var errorDescription: String? {
        switch self {
        case .notFIT: return "This isn't a FIT file."
        case .truncated: return "The FIT file is incomplete."
        case .undefinedLocalType: return "The FIT file is malformed."
        }
    }
}

/// Decodes FIT bytes into messages.
enum FITDecoder {

    /// Seconds between the Unix epoch and FIT's (1989-12-31 00:00:00 UTC).
    static let epochOffset: TimeInterval = 631_065_600

    /// A FIT `date_time` value as a `Date`.
    static func date(fromFIT seconds: Double) -> Date {
        Date(timeIntervalSince1970: seconds + epochOffset)
    }

    /// Decodes every data message in the file, in order. Chained files
    /// (several FIT files back to back) are read one after another.
    /// - Parameter data: The file's bytes.
    static func messages(from data: Data) throws -> [FITMessage] {
        let bytes = [UInt8](data)
        var offset = 0
        var messages: [FITMessage] = []
        repeat {
            let (fileMessages, next) = try decodeFile(bytes, at: offset)
            messages += fileMessages
            offset = next
        } while offset + 12 <= bytes.count && hasSignature(bytes, fileAt: offset)
        return messages
    }

    // MARK: - Internals

    /// A field in a definition message.
    private struct FieldDefinition {
        let number: UInt8
        let size: Int
        let baseType: UInt8
    }

    /// A definition message: how to read a local message type's data.
    private struct Definition {
        let globalNumber: UInt16
        let bigEndian: Bool
        let fields: [FieldDefinition]
        let developerBytes: Int
    }

    /// Whether a FIT header with the ".FIT" signature starts at `offset`.
    private static func hasSignature(_ bytes: [UInt8], fileAt offset: Int) -> Bool {
        guard offset + 12 <= bytes.count else { return false }
        return bytes[offset + 8] == 0x2E && bytes[offset + 9] == 0x46 && bytes[offset + 10] == 0x49 && bytes[offset + 11] == 0x54
    }

    /// Decodes one file starting at `start`.
    /// - Returns: Its messages and the offset just past its CRC.
    private static func decodeFile(_ bytes: [UInt8], at start: Int) throws -> ([FITMessage], Int) {
        guard hasSignature(bytes, fileAt: start) else { throw FITDecodeError.notFIT }
        let headerSize = Int(bytes[start])
        guard headerSize >= 12 else { throw FITDecodeError.notFIT }
        let dataSize = Int(readUInt(bytes, at: start + 4, size: 4, bigEndian: false))
        var offset = start + headerSize
        let end = offset + dataSize
        guard end <= bytes.count else { throw FITDecodeError.truncated }

        var definitions: [UInt8: Definition] = [:]
        var messages: [FITMessage] = []
        while offset < end {
            let header = bytes[offset]
            offset += 1
            if header & 0x80 != 0 {
                // Compressed timestamp header: a data message for local
                // types 0–3. The time offset itself isn't needed here.
                let local = (header >> 5) & 0x03
                messages.append(try readData(bytes, &offset, end: end, definition: definitions[local], local: local))
            } else if header & 0x40 != 0 {
                let local = header & 0x0F
                definitions[local] = try readDefinition(bytes, &offset, end: end, hasDeveloperFields: header & 0x20 != 0)
            } else {
                let local = header & 0x0F
                messages.append(try readData(bytes, &offset, end: end, definition: definitions[local], local: local))
            }
        }
        // Skip the file's 2-byte CRC.
        return (messages, end + 2)
    }

    /// Reads a definition message's body.
    private static func readDefinition(_ bytes: [UInt8], _ offset: inout Int, end: Int, hasDeveloperFields: Bool) throws -> Definition {
        guard offset + 5 <= end else { throw FITDecodeError.truncated }
        let bigEndian = bytes[offset + 1] == 1
        let global = UInt16(readUInt(bytes, at: offset + 2, size: 2, bigEndian: bigEndian))
        let count = Int(bytes[offset + 4])
        offset += 5
        guard offset + count * 3 <= end else { throw FITDecodeError.truncated }
        var fields: [FieldDefinition] = []
        for index in 0..<count {
            let base = offset + index * 3
            fields.append(FieldDefinition(number: bytes[base], size: Int(bytes[base + 1]), baseType: bytes[base + 2]))
        }
        offset += count * 3
        var developerBytes = 0
        if hasDeveloperFields {
            guard offset < end else { throw FITDecodeError.truncated }
            let devCount = Int(bytes[offset])
            offset += 1
            guard offset + devCount * 3 <= end else { throw FITDecodeError.truncated }
            for index in 0..<devCount {
                developerBytes += Int(bytes[offset + index * 3 + 1])
            }
            offset += devCount * 3
        }
        return Definition(globalNumber: global, bigEndian: bigEndian, fields: fields, developerBytes: developerBytes)
    }

    /// Reads a data message for a defined local type.
    private static func readData(_ bytes: [UInt8], _ offset: inout Int, end: Int, definition: Definition?, local: UInt8) throws -> FITMessage {
        guard let definition else { throw FITDecodeError.undefinedLocalType(local) }
        var values: [UInt8: Double] = [:]
        for field in definition.fields {
            guard offset + field.size <= end else { throw FITDecodeError.truncated }
            if let value = decodeValue(bytes, at: offset, size: field.size, baseType: field.baseType, bigEndian: definition.bigEndian) {
                values[field.number] = value
            }
            offset += field.size
        }
        guard offset + definition.developerBytes <= end else { throw FITDecodeError.truncated }
        offset += definition.developerBytes
        return FITMessage(globalNumber: definition.globalNumber, fields: values)
    }

    /// One numeric value, or `nil` for strings, arrays, and invalid sentinels.
    private static func decodeValue(_ bytes: [UInt8], at offset: Int, size: Int, baseType: UInt8, bigEndian: Bool) -> Double? {
        let type = baseType & 0x1F
        // (size, signed, invalid sentinel, "z" type where 0 is invalid)
        let spec: (size: Int, signed: Bool, zeroInvalid: Bool)
        switch type {
        case 0x00, 0x02, 0x0D: spec = (1, false, false)   // enum, uint8, byte
        case 0x01: spec = (1, true, false)                // sint8
        case 0x03: spec = (2, true, false)                // sint16
        case 0x04: spec = (2, false, false)               // uint16
        case 0x05: spec = (4, true, false)                // sint32
        case 0x06: spec = (4, false, false)               // uint32
        case 0x0A: spec = (1, false, true)                // uint8z
        case 0x0B: spec = (2, false, true)                // uint16z
        case 0x0C: spec = (4, false, true)                // uint32z
        case 0x0E: spec = (8, true, false)                // sint64
        case 0x0F: spec = (8, false, false)               // uint64
        case 0x10: spec = (8, false, true)                // uint64z
        case 0x08:                                        // float32
            guard size == 4 else { return nil }
            let bits = UInt32(readUInt(bytes, at: offset, size: 4, bigEndian: bigEndian))
            guard bits != 0xFFFF_FFFF else { return nil }
            return Double(Float(bitPattern: bits))
        case 0x09:                                        // float64
            guard size == 8 else { return nil }
            let bits = readUInt(bytes, at: offset, size: 8, bigEndian: bigEndian)
            guard bits != UInt64.max else { return nil }
            return Double(bitPattern: bits)
        default: return nil                               // string and unknown
        }
        guard size == spec.size else { return nil }       // arrays aren't needed
        let raw = readUInt(bytes, at: offset, size: size, bigEndian: bigEndian)
        let bitCount = UInt64(size * 8)
        let allOnes: UInt64 = size == 8 ? .max : (1 << bitCount) - 1
        if spec.zeroInvalid {
            return raw == 0 ? nil : Double(raw)
        }
        if spec.signed {
            let invalid = allOnes >> 1                    // 0x7F…
            guard raw != invalid else { return nil }
            let signBit: UInt64 = 1 << (bitCount - 1)
            if raw & signBit != 0 {
                return size == 8 ? Double(Int64(bitPattern: raw)) : Double(Int64(raw) - Int64(1 << bitCount))
            }
            return Double(raw)
        }
        return raw == allOnes ? nil : Double(raw)
    }

    /// An unsigned integer of 1–8 bytes.
    private static func readUInt(_ bytes: [UInt8], at offset: Int, size: Int, bigEndian: Bool) -> UInt64 {
        var value: UInt64 = 0
        for index in 0..<size {
            let byte = UInt64(bytes[offset + (bigEndian ? index : size - 1 - index)])
            value = (value << 8) | byte
        }
        return value
    }
}
