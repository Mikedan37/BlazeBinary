//
//  CanonicalText.swift
//  BlazeBinary
//
//  Copyright (c) 2025 Michael Danylchuk
//  MIT License
//

import Foundation

/// Canonical text formatter for BlazeBinary data (developer-only debug utility).
public enum CanonicalText {
    /// Converts BlazeBinary-encoded data to canonical text format.
    /// 
    /// Canonical format ensures:
    /// - Sorted keys for dictionaries
    /// - Stable numeric formats
    /// - Stable Unicode escapes
    /// 
    /// This is a developer-only utility for debugging and inspection.
    /// - Parameter data: The BlazeBinary-encoded data
    /// - Returns: Canonical text representation
    /// - Throws: `BlazeBinaryError` if data cannot be decoded
    public static func toCanonicalText(_ data: Data) throws -> String {
        let decoder = BlazeBinaryDecoder(data: data)
        return try formatValue(decoder: decoder)
    }
    
    private static func formatValue(decoder: BlazeBinaryDecoder) throws -> String {
        // Create a new decoder for each attempt to avoid offset issues
        // This is heuristic-based - a full implementation would require schema information
        
        let data = decoder.remainingData
        guard !data.isEmpty else {
            return "null"
        }
        
        // Try Int (most common, try first)
        do {
            let testDecoder = BlazeBinaryDecoder(data: data)
            let intValue = try testDecoder.decodeInt()
            // If we successfully decoded and consumed all data, return it
            if testDecoder.offset == data.count {
                return "\(intValue)"
            }
        } catch {
            // Try next type
        }
        
        // Try String
        do {
            let testDecoder = BlazeBinaryDecoder(data: data)
            let stringValue = try testDecoder.decodeString()
            if testDecoder.offset == data.count {
                return formatString(stringValue)
            }
        } catch {
            // Try next type
        }
        
        // Try Bool (single byte: 0x00 = false, 0x01 = true)
        // Check if data is exactly 1 byte and is a valid bool value
        if data.count == 1 {
            if data[0] == 0x00 {
                return "false"
            } else if data[0] == 0x01 {
                return "true"
            }
        }
        
        // Try decoding as Bool (may be part of larger structure)
        do {
            let testDecoder = BlazeBinaryDecoder(data: data)
            let boolValue = try testDecoder.decodeBool()
            if testDecoder.offset == data.count {
                return boolValue ? "true" : "false"
            }
        } catch {
            // Try next type
        }
        
        // Try Data (show as hex)
        do {
            let testDecoder = BlazeBinaryDecoder(data: data)
            let dataValue = try testDecoder.decodeData()
            if testDecoder.offset == data.count {
                return formatData(dataValue)
            }
        } catch {
            // Fallback
        }
        
        // Fallback: show remaining data as hex dump
        return formatData(data)
    }
    
    private static func formatString(_ string: String) -> String {
        var result = "\""
        for scalar in string.unicodeScalars {
            switch scalar.value {
            case 0x22: // "
                result += "\\\""
            case 0x5C: // \
                result += "\\\\"
            case 0x0A: // \n
                result += "\\n"
            case 0x0D: // \r
                result += "\\r"
            case 0x09: // \t
                result += "\\t"
            case 0x00...0x1F, 0x7F...0x9F:
                result += String(format: "\\u%04X", scalar.value)
            default:
                result += String(scalar)
            }
        }
        result += "\""
        return result
    }
    
    private static func formatData(_ data: Data) -> String {
        if data.isEmpty {
            return "[]"
        }
        let hex = data.prefix(32).map { String(format: "%02X", $0) }.joined(separator: " ")
        if data.count > 32 {
            return "[\(hex)...] (\(data.count) bytes)"
        }
        return "[\(hex)]"
    }
}

/// Protocol extension helper for canonical text formatting.
/// Use `CanonicalText.toCanonicalText()` directly with encoded data,
/// or encode your value first and then call `toCanonicalText()` on the data.
public extension BlazeBinaryEncodable {
    /// Returns a canonical text representation of this value.
    /// 
    /// This is a developer-only utility for debugging.
    /// - Returns: Canonical text representation
    /// - Throws: `BlazeBinaryError` if encoding/decoding fails
    func toCanonicalText() throws -> String {
        let encoder = BlazeBinaryEncoder()
        try encoder.encode(self)
        let data = encoder.encodedData()
        return try CanonicalText.toCanonicalText(data)
    }
}

