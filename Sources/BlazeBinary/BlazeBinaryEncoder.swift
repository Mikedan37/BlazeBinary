//
// BlazeBinaryEncoder.swift
// BlazeBinary
//
// Copyright (c) 2025 Michael Danylchuk
// MIT License
//

import Foundation

/// Encoder for converting Swift values to deterministic binary format.
public class BlazeBinaryEncoder {
    @usableFromInline internal var data: Data
    
    /// Creates a new encoder.
    public init() {
        self.data = Data()
    }
    
    /// Returns the encoded data.
    public func encodedData() -> Data {
        return data
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
    
    // MARK: - Fixed-Width Little-Endian Encoding
    
    /// Encodes a UInt32 in little-endian format.
    /// - Parameter value: The UInt32 to encode
    @inlinable
    public func encode(_ value: UInt32) {
        withUnsafeBytes(of: value.littleEndian) { bytes in
            data.append(contentsOf: bytes)
        }
    }
    
    /// Encodes a UInt64 in little-endian format.
    /// - Parameter value: The UInt64 to encode
    @inlinable
    public func encode(_ value: UInt64) {
        withUnsafeBytes(of: value.littleEndian) { bytes in
            data.append(contentsOf: bytes)
        }
    }
    
    /// Encodes a Bool as a single byte (0x00 for false, 0x01 for true).
    /// - Parameter value: The Bool to encode
    @inlinable
    public func encode(_ value: Bool) {
        data.append(value ? 1 : 0)
    }
    
    /// Encodes a Double in little-endian format (8 bytes).
    /// - Parameter value: The Double to encode
    @inlinable
    public func encode(_ value: Double) {
        let bitPattern = value.bitPattern
        withUnsafeBytes(of: bitPattern.littleEndian) { bytes in
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
        // String.data(using: .utf8) always returns non-nil for valid Swift Strings
        // as Swift Strings are guaranteed to be valid UTF-8 or UTF-16 that can be converted
        let utf8Data = value.data(using: .utf8) ?? Data()
        encodeVarint(UInt64(utf8Data.count))
        data.append(utf8Data)
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
    
    /// Encodes a collection of BlazeBinaryEncodable values.
    /// Format: <varint count> <item1> <item2> ...
    /// - Parameter items: The collection to encode
    /// - Throws: Any error thrown by an item's blazeEncode method
    public func encodeCollection<T: BlazeBinaryEncodable>(_ items: [T]) throws {
        encodeVarint(UInt64(items.count))
        for item in items {
            try item.blazeEncode(to: self)
        }
    }
}

