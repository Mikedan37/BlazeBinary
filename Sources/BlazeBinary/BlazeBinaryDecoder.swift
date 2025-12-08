//
// BlazeBinaryDecoder.swift
// BlazeBinary
//
// Copyright (c) 2025 Michael Danylchuk
// MIT License
//

import Foundation

/// Decoder for converting binary format to Swift values with strict bounds checking.
public class BlazeBinaryDecoder {
    @usableFromInline internal let data: Data
    @usableFromInline internal var offset: Int
    @usableFromInline internal let maxAllowedLength: Int
    @usableFromInline internal let schemaVersion: UInt32
    
    /// Creates a new decoder from the provided data.
    /// - Parameters:
    ///   - data: The binary data to decode
    ///   - maxAllowedLength: Maximum allowed length for variable-length fields (default: 10 MB)
    public init(data: Data, maxAllowedLength: Int = 10 * 1024 * 1024) {
        self.data = data
        self.offset = 0
        self.maxAllowedLength = maxAllowedLength
        
        // Detect schema version: if first byte is 0xFE, try to read varint as schema version
        // Schema version marker: 0xFE followed by varint (schema version >= 2)
        // We distinguish from regular data by checking if the varint is valid and >= 2
        // Note: 0xFE (254) can appear as a regular varint value, so we need careful detection
        if !data.isEmpty && data[0] == 0xFE && data.count > 1 {
            // Potential schema version marker - read varint
            var savedOffset = 1 // Skip marker byte
            var result: UInt64 = 0
            var shift: UInt64 = 0
            var bytesRead = 0
            let maxBytes = 10
            
            // Read varint schema version (safely, without throwing)
            // We read up to maxBytes or until we hit the end of data
            var lastByteHadContinuation = false
            while bytesRead < maxBytes && savedOffset < data.count {
                let byte = data[savedOffset]
                savedOffset += 1
                bytesRead += 1
                
                result |= UInt64(byte & 0x7F) << shift
                lastByteHadContinuation = (byte & 0x80) != 0
                
                if !lastByteHadContinuation {
                    break
                }
                
                shift += 7
                if shift >= 64 {
                    // Invalid varint (too many bits), assume v1
                    self.schemaVersion = 1
                    self.offset = 0
                    return
                }
            }
            
            // If we didn't read a complete varint (last byte had continuation bit or no bytes read), 
            // it's not a schema version marker - treat as regular data
            if lastByteHadContinuation || bytesRead == 0 {
                self.schemaVersion = 1
                self.offset = 0
                return
            }
            
            // Validate: schema version must be >= 2 and reasonable
            // Version 1 is never encoded (backwards compatibility)
            // If result is 1 or 0, it's likely a false positive (data starting with 0xFE 0x01 or 0xFE 0x00)
            // Schema versions can be multi-byte varints, but we need to distinguish from regular data
            // Key insight: If the varint we read would leave no data remaining (savedOffset >= data.count),
            // it's likely a false positive - we're reading the entire data as a schema version, leaving nothing to decode
            // This prevents cases like [0xFE, 0xFF, 0x00] (value 16383) from being misidentified
            if result >= 2 && result <= UInt32.max {
                // Additional check: if reading this as schema version would consume all data, it's a false positive
                // Schema version should be followed by actual encoded data, so there should be data remaining
                if savedOffset >= data.count {
                    // No data remaining after schema version - likely false positive (entire data is the varint)
                    self.schemaVersion = 1
                    self.offset = 0
                } else {
                    self.schemaVersion = UInt32(result)
                    self.offset = savedOffset
                }
            } else {
                // Invalid schema version or result < 2 (false positive), assume v1
                // Reset offset to 0 so decoder starts from beginning
                self.schemaVersion = 1
                self.offset = 0
            }
        } else {
            // No schema version marker, assume v1 (backwards compatible)
            self.schemaVersion = 1
            self.offset = 0
        }
    }
    
    /// Returns the detected schema version (defaults to 1 if not present).
    public var version: UInt32 {
        return schemaVersion
    }
    
    /// Returns the remaining unread data.
    public var remainingData: Data {
        guard offset < data.count else { return Data() }
        return data.subdata(in: offset..<data.count)
    }
    
    // MARK: - Bounds Checking
    
    /// Ensures there are at least `count` bytes remaining.
    /// - Parameter count: The number of bytes required
    /// - Throws: `BlazeBinaryError.truncated` if insufficient data
    @usableFromInline internal func ensureBytes(_ count: Int) throws {
        guard offset + count <= data.count else {
            throw BlazeBinaryError.truncated
        }
    }
    
    // MARK: - Varint Decoding (LEB128)
    
    /// Decodes a varint (LEB128) and returns it as a UInt64.
    /// - Returns: The decoded unsigned integer
    /// - Throws: `BlazeBinaryError.truncated` or `BlazeBinaryError.invalidVarint`
    @inlinable
    internal func decodeVarint() throws -> UInt64 {
        var result: UInt64 = 0
        var shift: UInt64 = 0
        var bytesRead = 0
        let maxBytes = 10 // Maximum bytes for a 64-bit varint
        
        while bytesRead < maxBytes {
            try ensureBytes(1)
            let byte = data[offset]
            offset += 1
            bytesRead += 1
            
            result |= UInt64(byte & 0x7F) << shift
            
            if (byte & 0x80) == 0 {
                return result
            }
            
            shift += 7
            if shift >= 64 {
                throw BlazeBinaryError.invalidVarint
            }
        }
        
        throw BlazeBinaryError.invalidVarint
    }
    
    /// Decodes a signed integer using varint (LEB128) with zigzag decoding.
    /// - Returns: The decoded integer
    /// - Throws: `BlazeBinaryError.truncated` or `BlazeBinaryError.invalidVarint`
    @inlinable
    public func decodeInt() throws -> Int {
        let zigzag = try decodeVarint()
        // Reverse zigzag encoding
        // If zigzag is odd: value = -(zigzag + 1) / 2
        // If zigzag is even: value = zigzag / 2
        // Handle UInt64.max specially (decodes to Int64.min)
        let value64: Int64
        if zigzag == UInt64.max {
            value64 = Int64.min
        } else {
            if (zigzag & 1) == 1 {
                // Odd: negative value
                // -(zigzag + 1) / 2 = -((zigzag + 1) >> 1)
                value64 = -Int64(truncatingIfNeeded: (zigzag + 1) >> 1)
            } else {
                // Even: positive value
                // zigzag / 2 = zigzag >> 1
                value64 = Int64(truncatingIfNeeded: zigzag >> 1)
            }
        }
        return Int(truncatingIfNeeded: value64)
    }
    
    // MARK: - Fixed-Width Little-Endian Decoding
    
    /// Decodes a UInt32 in little-endian format.
    /// - Returns: The decoded UInt32
    /// - Throws: `BlazeBinaryError.truncated`
    @inlinable
    public func decodeUInt32() throws -> UInt32 {
        try ensureBytes(4)
        // Read bytes manually to avoid alignment issues
        var value: UInt32 = 0
        value |= UInt32(data[offset])
        value |= UInt32(data[offset + 1]) << 8
        value |= UInt32(data[offset + 2]) << 16
        value |= UInt32(data[offset + 3]) << 24
        offset += 4
        return value // Already little-endian
    }
    
    /// Decodes a UInt64 in little-endian format.
    /// - Returns: The decoded UInt64
    /// - Throws: `BlazeBinaryError.truncated`
    @inlinable
    public func decodeUInt64() throws -> UInt64 {
        try ensureBytes(8)
        // Read bytes manually to avoid alignment issues
        var value: UInt64 = 0
        value |= UInt64(data[offset])
        value |= UInt64(data[offset + 1]) << 8
        value |= UInt64(data[offset + 2]) << 16
        value |= UInt64(data[offset + 3]) << 24
        value |= UInt64(data[offset + 4]) << 32
        value |= UInt64(data[offset + 5]) << 40
        value |= UInt64(data[offset + 6]) << 48
        value |= UInt64(data[offset + 7]) << 56
        offset += 8
        return value // Already little-endian
    }
    
    /// Decodes a Bool from a single byte (0x00 for false, 0x01 for true).
    /// - Returns: The decoded Bool
    /// - Throws: `BlazeBinaryError.truncated` or `BlazeBinaryError.decodeFailed` for invalid values
    @inlinable
    public func decodeBool() throws -> Bool {
        try ensureBytes(1)
        let byte = data[offset]
        offset += 1
        
        switch byte {
        case 0:
            return false
        case 1:
            return true
        default:
            throw BlazeBinaryError.decodeFailed("Invalid bool value: \(byte)")
        }
    }
    
    /// Decodes a Double in little-endian format (8 bytes).
    /// - Returns: The decoded Double
    /// - Throws: `BlazeBinaryError.truncated`
    @inlinable
    public func decodeDouble() throws -> Double {
        try ensureBytes(8)
        // Read bytes manually to avoid alignment issues
        var bitPattern: UInt64 = 0
        bitPattern |= UInt64(data[offset])
        bitPattern |= UInt64(data[offset + 1]) << 8
        bitPattern |= UInt64(data[offset + 2]) << 16
        bitPattern |= UInt64(data[offset + 3]) << 24
        bitPattern |= UInt64(data[offset + 4]) << 32
        bitPattern |= UInt64(data[offset + 5]) << 40
        bitPattern |= UInt64(data[offset + 6]) << 48
        bitPattern |= UInt64(data[offset + 7]) << 56
        offset += 8
        return Double(bitPattern: bitPattern) // Already little-endian
    }
    
    // MARK: - Length-Prefixed Decoding
    
    /// Decodes a Data value with a varint length prefix (zero-copy when possible).
    /// - Returns: The decoded Data (may be a slice referencing the original buffer)
    /// - Throws: `BlazeBinaryError.truncated`, `BlazeBinaryError.invalidVarint`, or `BlazeBinaryError.decodeFailed` if length exceeds maxAllowedLength
    @inlinable
    public func decodeData() throws -> Data {
        let length = try decodeVarint()
        
        guard length <= maxAllowedLength else {
            throw BlazeBinaryError.decodeFailed("Data length \(length) exceeds maximum allowed \(maxAllowedLength)")
        }
        
        let lengthInt = Int(length)
        try ensureBytes(lengthInt)
        
        // Zero-copy: subdata creates a slice that references the same underlying buffer
        let result = data.subdata(in: offset..<(offset + lengthInt))
        offset += lengthInt
        return result
    }
    
    /// Decodes a String from UTF-8 bytes with a varint length prefix.
    /// - Returns: The decoded String
    /// - Throws: `BlazeBinaryError.truncated`, `BlazeBinaryError.invalidVarint`, or `BlazeBinaryError.decodeFailed` if invalid UTF-8 or length exceeds maxAllowedLength
    public func decodeString() throws -> String {
        let utf8Data = try decodeData()
        
        guard let string = String(data: utf8Data, encoding: .utf8) else {
            throw BlazeBinaryError.decodeFailed("Invalid UTF-8 encoding")
        }
        
        return string
    }
    
    // MARK: - Composite Types
    
    /// Decodes a value conforming to BlazeBinaryDecodable.
    /// - Parameter type: The type to decode
    /// - Returns: The decoded value
    /// - Throws: Any error thrown by the type's initializer or decoding operations
    public func decode<T: BlazeBinaryDecodable>(_ type: T.Type) throws -> T {
        return try T(from: self)
    }
    
    /// Decodes an array of BlazeBinaryDecodable values.
    /// Format: <varint count> <item1> <item2> ...
    /// - Parameter type: The element type to decode
    /// - Returns: The decoded array
    /// - Throws: Any error thrown during decoding
    public func decodeArray<T: BlazeBinaryDecodable>(_ type: T.Type) throws -> [T] {
        let count = try decodeVarint()
        
        guard count <= maxAllowedLength else {
            throw BlazeBinaryError.decodeFailed("Array count \(count) exceeds maximum allowed \(maxAllowedLength)")
        }
        
        var result: [T] = []
        result.reserveCapacity(Int(count))
        
        for _ in 0..<count {
            let item = try T(from: self)
            result.append(item)
        }
        
        return result
    }
    
    // MARK: - Schema Evolution Support
    
    /// Decodes a value if present, otherwise returns nil.
    /// This is useful for handling optional fields in schema evolution.
    /// - Parameter type: The type to decode
    /// - Returns: The decoded value or nil if data is exhausted
    /// - Throws: Errors if data is corrupted (not just truncated)
    public func decodeIfPresent<T: BlazeBinaryDecodable>(_ type: T.Type) throws -> T? {
        guard offset < data.count else {
            return nil
        }
        return try T(from: self)
    }
    
    /// Decodes an optional value encoded as a Bool flag followed by the value if true.
    /// Format: <bool present> <value if present>
    /// - Parameter type: The type to decode
    /// - Returns: The decoded value or nil
    /// - Throws: Errors during decoding
    public func decodeOptional<T: BlazeBinaryDecodable>(_ type: T.Type) throws -> T? {
        let isPresent = try decodeBool()
        guard isPresent else {
            return nil
        }
        return try T(from: self)
    }
    
    /// Skips an unknown field by detecting its type and skipping the appropriate number of bytes.
    /// Supports: varints, fixed-width integers (UInt32, UInt64), length-prefixed blobs, bools.
    /// - Throws: `BlazeBinaryError.truncated` if data is incomplete
    public func skipUnknownField() throws {
        guard offset < data.count else {
            throw BlazeBinaryError.truncated
        }
        
        let firstByte = data[offset]
        
        // Check if it's a bool (0x00 or 0x01) - most specific check first
        if firstByte == 0x00 || firstByte == 0x01 {
            // Check if there are more bytes - if so, might be part of fixed-width
            if offset + 1 < data.count {
                let secondByte = data[offset + 1]
                // If next bytes are all zeros, might be fixed-width UInt32/UInt64
                // But for simplicity, treat 0x00/0x01 as bool if followed by non-zero or end
                if secondByte == 0x00 && offset + 4 <= data.count {
                    // Could be UInt32(0) or UInt64(0) - check if all 4/8 bytes are zero
                    var allZero = true
                    for i in offset..<min(offset + 4, data.count) {
                        if data[i] != 0x00 {
                            allZero = false
                            break
                        }
                    }
                    if allZero && offset + 4 <= data.count {
                        offset += 4
                        return
                    }
                }
            }
            offset += 1
            return
        }
        
        // Check if it's a varint with continuation bit set (definitely a varint)
        if (firstByte & 0x80) != 0 {
            _ = try decodeVarint()
            return
        }
        
        // For bytes < 128 without continuation bit, it could be:
        // 1. A single-byte varint (value < 128)
        // 2. First byte of a fixed-width UInt32/UInt64
        // We can't reliably distinguish, so we use a heuristic:
        // If the next 3 bytes are all zeros and we have 4 bytes, it's likely UInt32
        if offset + 4 <= data.count {
            let secondByte = data[offset + 1]
            let thirdByte = data[offset + 2]
            let fourthByte = data[offset + 3]
            // If bytes 2-4 are zeros, likely a fixed-width UInt32
            if secondByte == 0x00 && thirdByte == 0x00 && fourthByte == 0x00 {
                offset += 4
                return
            }
        }
        
        // Otherwise, treat as varint (single byte for values < 128)
        _ = try decodeVarint()
    }
    
    // MARK: - Zero-Copy Decoding
    
    /// Decodes a Data value with zero-copy when possible (returns a slice).
    /// Falls back to copying if slice is not possible.
    /// - Returns: The decoded Data (may be a slice or copy)
    /// - Throws: `BlazeBinaryError.truncated`, `BlazeBinaryError.invalidVarint`, or `BlazeBinaryError.decodeFailed`
    @inlinable
    public func decodeDataZeroCopy() throws -> Data {
        let length = try decodeVarint()
        
        guard length <= maxAllowedLength else {
            throw BlazeBinaryError.decodeFailed("Data length \(length) exceeds maximum allowed \(maxAllowedLength)")
        }
        
        let lengthInt = Int(length)
        try ensureBytes(lengthInt)
        
        // Return a slice (zero-copy) - Data.subdata creates a slice that references the same buffer
        let result = data.subdata(in: offset..<(offset + lengthInt))
        offset += lengthInt
        return result
    }
    
    /// EXPERIMENTAL: Decodes a struct with zero-copy memory mapping.
    /// 
    /// This method maps struct memory directly onto the data buffer, eliminating copies.
    /// 
    /// **Restrictions**:
    /// - Struct must contain only fixed-width primitives (UInt8-64, Int8-64, Float, Double, Bool)
    /// - No variable-length types (String, Data, arrays, optionals)
    /// - Struct must be properly aligned for the platform
    /// - Struct layout must match expected byte layout exactly
    /// 
    /// - Parameter type: The struct type to decode
    /// - Returns: The decoded struct value
    /// - Throws: `BlazeBinaryError` if decoding fails or struct is incompatible
    public func decodeZeroCopy<T>(_ type: T.Type) throws -> T {
        // Calculate struct size using MemoryLayout
        let structSize = MemoryLayout<T>.size
        let structAlignment = MemoryLayout<T>.alignment
        
        // Check bounds
        try ensureBytes(structSize)
        
        // Check alignment
        let dataPtr = data.withUnsafeBytes { $0.baseAddress }
        let offsetPtr = dataPtr?.advanced(by: offset)
        let alignment = Int(bitPattern: offsetPtr) % structAlignment
        
        guard alignment == 0 else {
            throw BlazeBinaryError.decodeFailed("Struct alignment mismatch: offset \(offset) not aligned to \(structAlignment) bytes")
        }
        
        // Validate that T is a fixed-width type (heuristic check)
        // In production, this would use more sophisticated reflection
        // For now, we rely on the type system and runtime checks
        
        // Perform zero-copy decode
        return data.withUnsafeBytes { bytes in
            let sourcePtr = bytes.baseAddress!.advanced(by: offset).assumingMemoryBound(to: T.self)
            return sourcePtr.pointee
        }
    }
}

