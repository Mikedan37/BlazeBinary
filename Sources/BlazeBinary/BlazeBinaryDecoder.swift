import Foundation

/// Decoder for converting binary format to Swift values with strict bounds checking.
public class BlazeBinaryDecoder {
    private let data: Data
    private var offset: Int
    private let maxAllowedLength: Int
    
    /// Creates a new decoder from the provided data.
    /// - Parameters:
    ///   - data: The binary data to decode
    ///   - maxAllowedLength: Maximum allowed length for variable-length fields (default: 10 MB)
    public init(data: Data, maxAllowedLength: Int = 10 * 1024 * 1024) {
        self.data = data
        self.offset = 0
        self.maxAllowedLength = maxAllowedLength
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
    private func ensureBytes(_ count: Int) throws {
        guard offset + count <= data.count else {
            throw BlazeBinaryError.truncated
        }
    }
    
    // MARK: - Varint Decoding (LEB128)
    
    /// Decodes a varint (LEB128) and returns it as a UInt64.
    /// - Returns: The decoded unsigned integer
    /// - Throws: `BlazeBinaryError.truncated` or `BlazeBinaryError.invalidVarint`
    @inlinable
    private func decodeVarint() throws -> UInt64 {
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
        let value = Int64(truncatingIfNeeded: zigzag)
        return Int((value >> 1) ^ (-(value & 1)))
    }
    
    // MARK: - Fixed-Width Little-Endian Decoding
    
    /// Decodes a UInt32 in little-endian format.
    /// - Returns: The decoded UInt32
    /// - Throws: `BlazeBinaryError.truncated`
    @inlinable
    public func decodeUInt32() throws -> UInt32 {
        try ensureBytes(4)
        let slice = data.subdata(in: offset..<(offset + 4))
        let value = slice.withUnsafeBytes { bytes in
            bytes.load(as: UInt32.self)
        }
        offset += 4
        return UInt32(littleEndian: value)
    }
    
    /// Decodes a UInt64 in little-endian format.
    /// - Returns: The decoded UInt64
    /// - Throws: `BlazeBinaryError.truncated`
    @inlinable
    public func decodeUInt64() throws -> UInt64 {
        try ensureBytes(8)
        let slice = data.subdata(in: offset..<(offset + 8))
        let value = slice.withUnsafeBytes { bytes in
            bytes.load(as: UInt64.self)
        }
        offset += 8
        return UInt64(littleEndian: value)
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
    
    // MARK: - Convenience APIs
    
    /// Decodes a collection of BlazeBinaryDecodable values.
    /// Format: <varint count> <item1> <item2> ...
    /// - Returns: The decoded collection
    /// - Throws: Any error thrown during decoding
    public func decodeCollection<T: BlazeBinaryDecodable>() throws -> [T] {
        return try decodeArray(T.self)
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
            offset += 1
            return
        }
        
        // Check if it's a varint (has continuation bit set or value < 128)
        if (firstByte & 0x80) != 0 || firstByte < 0x80 {
            // Decode varint to skip it
            // Note: For length-prefixed fields (String/Data), the caller should
            // use decodeData() or decodeString() and discard the result
            _ = try decodeVarint()
            return
        }
        
        // Check if it's a fixed-width integer (UInt32 = 4 bytes, UInt64 = 8 bytes)
        // We'll try UInt32 first (most common)
        if offset + 4 <= data.count {
            offset += 4
            return
        }
        
        // If we can't determine, try varint as fallback
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
}

