//
// BlazeBinaryDecoder.swift
// BlazeBinary
//
// Copyright (c) 2025 Michael Danylchuk
// MIT License
//

import Foundation

/// Decoder for converting binary format to Swift values with strict bounds checking.
///
/// - Important: **Not thread-safe.** Each `BlazeBinaryDecoder` instance must be
///   used from a single thread (or serial queue) at a time. The internal read
///   offset is mutated on every decode call.
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
        
        // Detect schema version: if first byte is 0xFE, try to read schema version.
        //
        // Schema version marker: 0xFE followed by a single-byte varint (version 2...127).
        //
        // KNOWN LIMITATION (in-band signaling collision):
        // 0xFE (254) is also the zigzag encoding of Int(127). If the very first field
        // of a v1 record is a signed Int with value 127, the encoder writes 0xFE as a
        // single-byte varint. The decoder then sees [0xFE, <next-byte>] and may parse
        // a false-positive schema version. Mitigations:
        //   1. Only single-byte varints (no continuation bit) in 2...127 are accepted.
        //      This rejects multi-byte varints which are almost certainly payload data.
        //   2. At least 1 byte of payload must remain after the marker + version byte
        //      (data.count > 2), so [0xFE, 0x02] alone is not misinterpreted.
        //   3. If your first field can be Int(127), use schemaVersion >= 2 (which
        //      writes an explicit marker), or encode the first field as UInt32/UInt64.
        if !data.isEmpty && data[0] == 0xFE && data.count > 2 {
            let versionByte = data[1]

            // Accept only single-byte varints (continuation bit clear) in range 2...127.
            // Multi-byte varints (continuation bit set) are almost certainly payload data,
            // not a schema version — reject them as false positives.
            if (versionByte & 0x80) == 0 && versionByte >= 2 {
                self.schemaVersion = UInt32(versionByte)
                self.offset = 2 // Skip marker byte + version byte
            } else {
                self.schemaVersion = 1
                self.offset = 0
            }
        } else {
            // No schema version marker, assume v1 (backwards compatible)
            self.schemaVersion = 1
            self.offset = 0
        }
    }
    
    /// Internal initializer that skips schema version detection.
    /// Used for decoding individual elements from buffer slices where
    /// the first byte should never be interpreted as a schema version marker.
    internal init(data: Data, maxAllowedLength: Int = 10 * 1024 * 1024, rawMode: Bool) {
        self.data = data
        self.offset = 0
        self.maxAllowedLength = maxAllowedLength
        self.schemaVersion = 1
    }

    /// Returns the detected schema version (defaults to 1 if not present).
    public var version: UInt32 {
        return schemaVersion
    }
    
    /// Returns the remaining unread data.
    public var remainingData: Data {
        guard offset >= 0, offset <= data.count else { return Data() }
        guard offset < data.count else { return Data() }
        return data.subdata(in: offset..<data.count)
    }
    
    // MARK: - Bounds Checking
    
    /// Ensures there are at least `count` bytes remaining.
    /// - Parameter count: The number of bytes required
    /// - Throws: `BlazeBinaryError.truncated` if insufficient data or count is negative
    @usableFromInline internal func ensureBytes(_ count: Int) throws {
        guard count >= 0 else {
            throw BlazeBinaryError.decodeFailed("Negative byte count")
        }
        let end = offset + count
        guard end >= offset, end <= data.count else {
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
    
    // MARK: - Fixed-Width Big-Endian (Network Byte Order) Decoding
    
    /// Decodes a UInt16 in big-endian (network byte order) format.
    ///
    /// **Endianness**: Big-endian (network byte order) for cross-language compatibility.
    /// - Wire format: 2 bytes, big-endian
    /// - Format: `[MSB, LSB]`
    /// - Example: `[0x12, 0x34]` → `0x1234`
    ///
    /// **Framing**: Expects exactly 2 bytes. No length prefix.
    /// **Allocation**: Zero-copy operation using manual byte assembly.
    ///
    /// - Returns: The decoded UInt16
    /// - Throws: `BlazeBinaryError.truncated` if insufficient bytes
    @inlinable
    public func decodeUInt16() throws -> UInt16 {
        try ensureBytes(2)
        // Read bytes manually in big-endian order to avoid alignment issues
        var value: UInt16 = 0
        value |= UInt16(data[offset]) << 8
        value |= UInt16(data[offset + 1])
        offset += 2
        return value
    }
    
    /// Decodes a UInt32 in big-endian (network byte order) format.
    ///
    /// **Endianness**: Big-endian (network byte order) for cross-language compatibility.
    /// - Wire format: 4 bytes, big-endian
    /// - Format: `[MSB, byte2, byte3, LSB]`
    /// - Example: `[0x12, 0x34, 0x56, 0x78]` → `0x12345678`
    ///
    /// **Framing**: Expects exactly 4 bytes. No length prefix.
    /// **Allocation**: Zero-copy operation using manual byte assembly.
    ///
    /// - Returns: The decoded UInt32
    /// - Throws: `BlazeBinaryError.truncated` if insufficient bytes
    @inlinable
    public func decodeUInt32() throws -> UInt32 {
        try ensureBytes(4)
        // Read bytes manually in big-endian order to avoid alignment issues
        var value: UInt32 = 0
        value |= UInt32(data[offset]) << 24
        value |= UInt32(data[offset + 1]) << 16
        value |= UInt32(data[offset + 2]) << 8
        value |= UInt32(data[offset + 3])
        offset += 4
        return value
    }
    
    /// Decodes a UInt64 in big-endian (network byte order) format.
    ///
    /// **Endianness**: Big-endian (network byte order) for cross-language compatibility.
    /// - Wire format: 8 bytes, big-endian
    /// - Format: `[MSB, ..., LSB]`
    /// - Example: `[0x01, 0x23, 0x45, 0x67, 0x89, 0xAB, 0xCD, 0xEF]` → `0x0123456789ABCDEF`
    ///
    /// **Framing**: Expects exactly 8 bytes. No length prefix.
    /// **Allocation**: Zero-copy operation using manual byte assembly.
    ///
    /// - Returns: The decoded UInt64
    /// - Throws: `BlazeBinaryError.truncated` if insufficient bytes
    @inlinable
    public func decodeUInt64() throws -> UInt64 {
        try ensureBytes(8)
        // Read bytes manually in big-endian order to avoid alignment issues
        var value: UInt64 = 0
        value |= UInt64(data[offset]) << 56
        value |= UInt64(data[offset + 1]) << 48
        value |= UInt64(data[offset + 2]) << 40
        value |= UInt64(data[offset + 3]) << 32
        value |= UInt64(data[offset + 4]) << 24
        value |= UInt64(data[offset + 5]) << 16
        value |= UInt64(data[offset + 6]) << 8
        value |= UInt64(data[offset + 7])
        offset += 8
        return value
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
    
    /// Decodes a Float (Float32) in big-endian (network byte order) format (4 bytes).
    ///
    /// **Endianness**: Big-endian (network byte order) for cross-language compatibility.
    /// - Wire format: 4 bytes, big-endian IEEE 754 single precision
    /// - Format: IEEE 754 single precision, bit pattern decoded from big-endian bytes
    /// - Example: `[0x3F, 0x80, 0x00, 0x00]` → `1.0`
    ///
    /// **Framing**: Expects exactly 4 bytes. No length prefix.
    /// **Allocation**: Zero-copy operation using manual byte assembly.
    ///
    /// - Returns: The decoded Float
    /// - Throws: `BlazeBinaryError.truncated` if insufficient bytes
    @inlinable
    public func decodeFloat() throws -> Float {
        try ensureBytes(4)
        // Read bytes manually in big-endian order to avoid alignment issues
        var bitPattern: UInt32 = 0
        bitPattern |= UInt32(data[offset]) << 24
        bitPattern |= UInt32(data[offset + 1]) << 16
        bitPattern |= UInt32(data[offset + 2]) << 8
        bitPattern |= UInt32(data[offset + 3])
        offset += 4
        return Float(bitPattern: bitPattern)
    }
    
    /// Decodes a Double in big-endian (network byte order) format (8 bytes).
    ///
    /// **Endianness**: Big-endian (network byte order) for cross-language compatibility.
    /// - Wire format: 8 bytes, big-endian IEEE 754 double precision
    /// - Format: IEEE 754 double precision, bit pattern decoded from big-endian bytes
    /// - Example: `[0x3F, 0xF0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]` → `1.0`
    ///
    /// **Framing**: Expects exactly 8 bytes. No length prefix.
    /// **Allocation**: Zero-copy operation using manual byte assembly.
    ///
    /// - Returns: The decoded Double
    /// - Throws: `BlazeBinaryError.truncated` if insufficient bytes
    @inlinable
    public func decodeDouble() throws -> Double {
        try ensureBytes(8)
        // Read bytes manually in big-endian order to avoid alignment issues
        var bitPattern: UInt64 = 0
        bitPattern |= UInt64(data[offset]) << 56
        bitPattern |= UInt64(data[offset + 1]) << 48
        bitPattern |= UInt64(data[offset + 2]) << 40
        bitPattern |= UInt64(data[offset + 3]) << 32
        bitPattern |= UInt64(data[offset + 4]) << 24
        bitPattern |= UInt64(data[offset + 5]) << 16
        bitPattern |= UInt64(data[offset + 6]) << 8
        bitPattern |= UInt64(data[offset + 7])
        offset += 8
        return Double(bitPattern: bitPattern)
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
        // Prevent Int overflow: length > Int.max becomes negative and causes Range crash in subdata
        guard length <= UInt64(Int.max) else {
            throw BlazeBinaryError.decodeFailed("Data length \(length) exceeds Int.max")
        }
        let lengthInt = Int(length)
        guard lengthInt >= 0 else {
            throw BlazeBinaryError.decodeFailed("Data length negative or overflowed")
        }
        try ensureBytes(lengthInt)
        
        // Bounds check to avoid Range crash (lowerBound <= upperBound)
        let end = offset + lengthInt
        guard end >= offset, end <= data.count else {
            throw BlazeBinaryError.truncated
        }
        // Zero-copy: subdata creates a slice that references the same underlying buffer
        let result = data.subdata(in: offset..<end)
        offset = end
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
        // Prevent Int overflow: count > Int.max makes 0..<count and reserveCapacity(Int(count)) unsafe
        guard count <= UInt64(Int.max) else {
            throw BlazeBinaryError.decodeFailed("Array count \(count) exceeds Int.max")
        }
        let countInt = Int(count)
        guard countInt >= 0 else {
            throw BlazeBinaryError.decodeFailed("Array count negative or overflowed")
        }
        
        var result: [T] = []
        result.reserveCapacity(countInt)
        
        for _ in 0..<countInt {
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
    
    /// Skips an unknown field of a given wire type.
    ///
    /// Without type metadata, raw bytes cannot be reliably classified (e.g. `0x00`
    /// could be `Bool(false)`, the first byte of `UInt32(0)`, or a varint).
    /// Callers must specify the expected wire type.
    ///
    /// - Parameter type: The wire type of the field to skip.
    /// - Throws: `BlazeBinaryError.truncated` if insufficient bytes remain.
    public func skipField(_ type: WireType) throws {
        switch type {
        case .bool:
            try ensureBytes(1)
            offset += 1
        case .fixedWidth32:
            try ensureBytes(4)
            offset += 4
        case .fixedWidth64:
            try ensureBytes(8)
            offset += 8
        case .varint:
            _ = try decodeVarint()
        case .lengthPrefixed:
            _ = try decodeData()
        }
    }

    /// Wire types for ``skipField(_:)``.
    public enum WireType {
        case bool
        case fixedWidth32
        case fixedWidth64
        case varint
        case lengthPrefixed
    }

    /// Skips an unknown field using byte-level heuristics.
    ///
    /// - Important: This is a best-effort heuristic. It **cannot** reliably distinguish
    ///   a `Bool(false)` (`0x00`) from the first byte of a big-endian `UInt32`.
    ///   Prefer ``skipField(_:)`` when the wire type is known.
    @available(*, deprecated, message: "Use skipField(_:) with an explicit WireType instead")
    public func skipUnknownField() throws {
        guard offset < data.count else {
            throw BlazeBinaryError.truncated
        }

        let firstByte = data[offset]

        // Continuation bit set → definitely a multi-byte varint
        if (firstByte & 0x80) != 0 {
            _ = try decodeVarint()
            return
        }

        // Small value (< 128) with no continuation bit.
        // Default to skipping 4 bytes (UInt32) when enough data remains,
        // since single-byte bools are indistinguishable from leading zeros
        // of a big-endian fixed-width integer.
        if offset + 4 <= data.count {
            offset += 4
            return
        }

        // Not enough bytes for fixed-width; treat as single-byte varint or bool
        try ensureBytes(1)
        offset += 1
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
        guard length <= UInt64(Int.max) else {
            throw BlazeBinaryError.decodeFailed("Data length \(length) exceeds Int.max")
        }
        let lengthInt = Int(length)
        guard lengthInt >= 0 else {
            throw BlazeBinaryError.decodeFailed("Data length negative or overflowed")
        }
        try ensureBytes(lengthInt)
        
        let end = offset + lengthInt
        guard end >= offset, end <= data.count else {
            throw BlazeBinaryError.truncated
        }
        // Return a slice (zero-copy) - Data.subdata creates a slice that references the same buffer
        let result = data.subdata(in: offset..<end)
        offset = end
        return result
    }
    
    /// Decodes a `BlazeBinaryCodable` value, falling back from zero-copy to field-wise decoding.
    ///
    /// BlazeBinary uses big-endian wire format, so raw pointer casts only produce
    /// correct results on big-endian hosts. On little-endian platforms (all Apple
    /// Silicon), this method decodes through the standard `BlazeBinaryCodable`
    /// path, which handles endian conversion per-field.
    ///
    /// - Parameter type: The `BlazeBinaryCodable` type to decode.
    /// - Returns: The decoded value.
    /// - Throws: `BlazeBinaryError` if decoding fails.
    public func decodeZeroCopy<T: BlazeBinaryCodable>(_ type: T.Type) throws -> T {
        return try T(from: self)
    }
}

