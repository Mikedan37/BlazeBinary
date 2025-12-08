//
//  HexDump.swift
//  BlazeBinary
//
//  Copyright (c) 2025 Michael Danylchuk
//  MIT License
//

import Foundation

/// Hex dump utility for debugging and inspection of binary data.
public enum HexDump {
    /// Dumps binary data in hexadecimal format with ASCII representation.
    /// - Parameters:
    ///   - data: The data to dump
    ///   - bytesPerLine: Number of bytes per line (default: 16)
    ///   - showOffset: Whether to show byte offsets (default: true)
    /// - Returns: Formatted hex dump string
    public static func dump(_ data: Data, bytesPerLine: Int = 16, showOffset: Bool = true) -> String {
        guard !data.isEmpty else {
            return showOffset ? "00000000\n" : "\n"
        }
        
        var result = ""
        var offset = 0
        
        while offset < data.count {
            if showOffset {
                result += String(format: "%08X  ", offset)
            }
            
            // Hex bytes
            let lineEnd = min(offset + bytesPerLine, data.count)
            for i in offset..<lineEnd {
                result += String(format: "%02X ", data[i])
            }
            
            // Padding for incomplete lines
            if lineEnd < offset + bytesPerLine {
                let padding = (offset + bytesPerLine - lineEnd) * 3
                result += String(repeating: " ", count: padding)
            }
            
            result += " |"
            
            // ASCII representation
            for i in offset..<lineEnd {
                let byte = data[i]
                if byte >= 32 && byte < 127, let scalar = UnicodeScalar(UInt32(byte)) {
                    result += String(Character(scalar))
                } else {
                    result += "."
                }
            }
            
            result += "|\n"
            offset = lineEnd
        }
        
        return result
    }
    
    /// Dumps binary data in compact hexadecimal format (no ASCII, no offsets).
    /// - Parameter data: The data to dump
    /// - Returns: Compact hex string (e.g., "01 02 03 FF")
    public static func dumpCompact(_ data: Data) -> String {
        return data.map { String(format: "%02X", $0) }.joined(separator: " ")
    }
    
    /// Dumps binary data with custom formatting.
    /// - Parameters:
    ///   - data: The data to dump
    ///   - prefix: Prefix for each line (e.g., "  " for indentation)
    ///   - bytesPerLine: Number of bytes per line
    /// - Returns: Formatted hex dump string
    public static func dump(_ data: Data, prefix: String, bytesPerLine: Int = 16) -> String {
        guard !data.isEmpty else {
            return "\(prefix)\n"
        }
        
        var result = ""
        var offset = 0
        
        while offset < data.count {
            result += prefix
            result += String(format: "%08X  ", offset)
            
            let lineEnd = min(offset + bytesPerLine, data.count)
            for i in offset..<lineEnd {
                result += String(format: "%02X ", data[i])
            }
            
            if lineEnd < offset + bytesPerLine {
                let padding = (offset + bytesPerLine - lineEnd) * 3
                result += String(repeating: " ", count: padding)
            }
            
            result += " |"
            for i in offset..<lineEnd {
                let byte = data[i]
                if byte >= 32 && byte < 127, let scalar = UnicodeScalar(UInt32(byte)) {
                    result += String(Character(scalar))
                } else {
                    result += "."
                }
            }
            result += "|\n"
            
            offset = lineEnd
        }
        
        return result
    }
}

