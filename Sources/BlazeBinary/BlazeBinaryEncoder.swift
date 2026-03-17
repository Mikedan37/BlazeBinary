//
// BlazeBinaryEncoder.swift
// BlazeBinary
//
// Copyright (c) 2025 Michael Danylchuk
// MIT License
//

import Foundation

/// Encoder for converting Swift values to deterministic binary format.
///
/// - Important: **Not thread-safe.** Each `BlazeBinaryEncoder` instance must be
///   used from a single thread (or serial queue) at a time. Create a separate
///   encoder per task if you need concurrent encoding.
public class BlazeBinaryEncoder {
    @usableFromInline internal var data: Data
    @usableFromInline internal let schemaVersion: UInt32
    
    /// Creates a new encoder.
    /// - Parameter schemaVersion: Optional schema version (default: 1). If > 1, will be encoded in the record.
    public init(schemaVersion: UInt32 = 1) {
        self.data = Data()
        self.schemaVersion = schemaVersion
    }
    
    /// Returns the schema version for this encoder.
    public var version: UInt32 {
        return schemaVersion
    }
    
    /// Returns the encoded data.
    /// If schemaVersion > 1, the schema version is prepended to the data.
    ///
    /// Schema version is encoded as: `0xFE` (marker) + single-byte varint (2...127).
    /// Versions outside 2...127 are not supported (the decoder only accepts single-byte
    /// varints to avoid in-band collision with payload data starting with 0xFE).
    public func encodedData() -> Data {
        // If schema version is 1 (default), don't encode it (backwards compatible)
        if schemaVersion == 1 {
            return data
        }

        // Schema version must fit in a single-byte varint (2...127) to avoid
        // ambiguity with the decoder's 0xFE detection heuristic.
        precondition(schemaVersion >= 2 && schemaVersion <= 127,
                     "Schema version must be in range 2...127 (got \(schemaVersion))")

        // Prepend: 0xFE (marker) + single byte (schemaVersion)
        var result = Data()
        result.append(0xFE) // Schema version marker byte
        result.append(UInt8(schemaVersion))
        result.append(data)
        return result
    }
    
    // MARK: - Varint Encoding (LEB128)
    
    /// Encodes a signed integer using varint (LEB128) with zigzag encoding.
    /// - Parameter value: The integer to encode
    @inlinable
    public func encode(_ value: Int) {
        // Zigzag encoding: maps signed integers to unsigned integers
        // -1 -> 1, 1 -> 2, -2 -> 3, 2 -> 4, etc.
        // Formula: (value << 1) ^ (value >> 63)
        // Cast to Int64 to handle full range, but need to avoid overflow on Int64.min
        let value64 = Int64(truncatingIfNeeded: value)
        
        // Handle Int64.min specially (left shift would overflow)
        let zigzag: UInt64
        if value64 == Int64.min {
            // Int64.min zigzag encodes to UInt64.max
            zigzag = UInt64.max
        } else {
            // Standard zigzag: (value << 1) ^ (value >> 63)
            // Do arithmetic in signed space first to get correct result
            let shifted = value64 << 1
            let sign = value64 >> 63
            let result = shifted ^ sign
            zigzag = UInt64(bitPattern: result)
        }
        encodeVarint(zigzag)
    }
    
    /// Encodes an unsigned integer using varint (LEB128) encoding.
    /// - Parameter value: The unsigned integer to encode
    @inlinable
    internal func encodeVarint(_ value: UInt64) {
        var v = value
        repeat {
            var byte = UInt8(v & 0x7F)
            v >>= 7
            if v != 0 {
                byte |= 0x80
            }
            data.append(byte)
        } while v != 0
    }
    
    // MARK: - Fixed-Width Big-Endian (Network Byte Order) Encoding
    
    /// Encodes a UInt16 in big-endian (network byte order) format.
    ///
    /// **Endianness**: Big-endian (network byte order) for cross-language compatibility.
    /// - Wire format: 2 bytes, big-endian
    /// - Format: `[MSB, LSB]`
    /// - Example: `0x1234` → `[0x12, 0x34]`
    ///
    /// **Framing**: This is a fixed-width 2-byte field. No length prefix.
    /// **Allocation**: Single allocation-safe operation using `withUnsafeBytes`.
    ///
    /// - Parameter value: The UInt16 to encode
    @inlinable
    public func encode(_ value: UInt16) {
        withUnsafeBytes(of: value.bigEndian) { bytes in
            data.append(contentsOf: bytes)
        }
    }
    
    /// Encodes a UInt32 in big-endian (network byte order) format.
    ///
    /// **Endianness**: Big-endian (network byte order) for cross-language compatibility.
    /// - Wire format: 4 bytes, big-endian
    /// - Format: `[MSB, byte2, byte3, LSB]`
    /// - Example: `0x12345678` → `[0x12, 0x34, 0x56, 0x78]`
    ///
    /// **Framing**: This is a fixed-width 4-byte field. No length prefix.
    /// **Allocation**: Single allocation-safe operation using `withUnsafeBytes`.
    ///
    /// - Parameter value: The UInt32 to encode
    @inlinable
    public func encode(_ value: UInt32) {
        withUnsafeBytes(of: value.bigEndian) { bytes in
            data.append(contentsOf: bytes)
        }
    }
    
    /// Encodes a UInt64 in big-endian (network byte order) format.
    ///
    /// **Endianness**: Big-endian (network byte order) for cross-language compatibility.
    /// - Wire format: 8 bytes, big-endian
    /// - Format: `[MSB, ..., LSB]`
    /// - Example: `0x0123456789ABCDEF` → `[0x01, 0x23, 0x45, 0x67, 0x89, 0xAB, 0xCD, 0xEF]`
    ///
    /// **Framing**: This is a fixed-width 8-byte field. No length prefix.
    /// **Allocation**: Single allocation-safe operation using `withUnsafeBytes`.
    ///
    /// - Parameter value: The UInt64 to encode
    @inlinable
    public func encode(_ value: UInt64) {
        withUnsafeBytes(of: value.bigEndian) { bytes in
            data.append(contentsOf: bytes)
        }
    }
    
    /// Encodes a Bool as a single byte (0x00 for false, 0x01 for true).
    ///
    /// **Framing**: Single-byte field, no endianness concerns.
    /// **Cross-language**: Compatible with any language's boolean encoding.
    ///
    /// - Parameter value: The Bool to encode
    @inlinable
    public func encode(_ value: Bool) {
        data.append(value ? 1 : 0)
    }
    
    /// Encodes a Float (Float32) in big-endian (network byte order) format (4 bytes).
    ///
    /// **Endianness**: Big-endian (network byte order) for cross-language compatibility.
    /// - Wire format: 4 bytes, big-endian IEEE 754 single precision
    /// - Format: IEEE 754 single precision, bit pattern encoded as big-endian UInt32
    /// - Example: `1.0` → IEEE 754 bit pattern `0x3F800000` → `[0x3F, 0x80, 0x00, 0x00]`
    ///
    /// **Framing**: This is a fixed-width 4-byte field. No length prefix.
    /// **Allocation**: Single allocation-safe operation using `withUnsafeBytes`.
    ///
    /// - Parameter value: The Float to encode
    @inlinable
    public func encode(_ value: Float) {
        let bitPattern = value.bitPattern
        withUnsafeBytes(of: bitPattern.bigEndian) { bytes in
            data.append(contentsOf: bytes)
        }
    }
    
    /// Encodes a Double in big-endian (network byte order) format (8 bytes).
    ///
    /// **Endianness**: Big-endian (network byte order) for cross-language compatibility.
    /// - Wire format: 8 bytes, big-endian IEEE 754 double precision
    /// - Format: IEEE 754 double precision, bit pattern encoded as big-endian UInt64
    /// - Example: `1.0` → IEEE 754 bit pattern `0x3FF0000000000000` → `[0x3F, 0xF0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]`
    ///
    /// **Framing**: This is a fixed-width 8-byte field. No length prefix.
    /// **Allocation**: Single allocation-safe operation using `withUnsafeBytes`.
    ///
    /// - Parameter value: The Double to encode
    @inlinable
    public func encode(_ value: Double) {
        let bitPattern = value.bitPattern
        withUnsafeBytes(of: bitPattern.bigEndian) { bytes in
            data.append(contentsOf: bytes)
        }
    }
    
    // MARK: - Length-Prefixed Encoding
    
    /// Encodes a Data value with a varint length prefix.
    /// 
    /// Format: `<varint length> <bytes>`
    /// 
    /// The length is encoded as a LEB128 varint, followed by the raw bytes.
    /// 
    /// - Parameter value: The Data to encode
    /// - Note: Empty Data values are encoded as a single byte (varint 0).
    public func encode(_ value: Data) {
        encodeVarint(UInt64(value.count))
        data.append(value)
    }
    
    /// Encodes a String as UTF-8 bytes with a varint length prefix.
    /// 
    /// Format: `<varint byteCount> <utf8 bytes>`
    /// 
    /// The string is converted to UTF-8 bytes, the byte count is encoded as a LEB128 varint,
    /// followed by the UTF-8 bytes.
    /// 
    /// - Parameter value: The String to encode
    /// - Note: All valid Swift Strings can be encoded as UTF-8. Swift's String type guarantees
    ///   that `data(using: .utf8)` returns non-nil for all valid strings. Empty strings are
    ///   encoded as a single byte (varint 0).
    public func encode(_ value: String) {
        // Use String.utf8 (a UTF8View) which is always valid — no optional, no fallback.
        // This avoids the previous `data(using: .utf8) ?? Data()` pattern which could
        // silently encode 0 bytes if the NSString bridge ever returned nil.
        let utf8Bytes = Array(value.utf8)
        encodeVarint(UInt64(utf8Bytes.count))
        data.append(contentsOf: utf8Bytes)
    }
    
    // MARK: - Composite Types
    
    /// Encodes a value conforming to BlazeBinaryEncodable.
    /// - Parameter value: The value to encode
    /// - Throws: Any error thrown by the value's blazeEncode method
    public func encode<T: BlazeBinaryEncodable>(_ value: T) throws {
        try value.blazeEncode(to: self)
    }
    
    /// Encodes an array of BlazeBinaryEncodable values.
    /// Format: <varint count> <item1> <item2> ...
    /// - Parameter array: The array to encode
    /// - Throws: Any error thrown by an item's blazeEncode method
    public func encode<T: BlazeBinaryEncodable>(_ array: [T]) throws {
        encodeVarint(UInt64(array.count))
        for item in array {
            try item.blazeEncode(to: self)
        }
    }
    
    // MARK: - Convenience APIs
    
    /// Encodes an optional value as a Bool flag followed by the value if present.
    /// Format: <bool present> <value if present>
    /// - Parameter value: The optional value to encode
    /// - Throws: Any error thrown by the value's blazeEncode method
    public func encode<T: BlazeBinaryEncodable>(_ value: T?) throws {
        if let value = value {
            encode(true)
            try value.blazeEncode(to: self)
        } else {
            encode(false)
        }
    }
    
}

