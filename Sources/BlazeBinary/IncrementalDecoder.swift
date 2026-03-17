//
//  IncrementalDecoder.swift
//  BlazeBinary
//
//  Copyright (c) 2025 Michael Danylchuk
//  MIT License
//

import Foundation

/// Incremental decoder for processing huge payloads in chunks.
///
/// This decoder allows processing large BlazeBinary records incrementally,
/// without loading the entire payload into memory at once.
public class BlazeIncrementalDecoder {
    @usableFromInline internal var buffer: Data
    @usableFromInline internal var offset: Int
    @usableFromInline internal let maxAllowedLength: Int
    @usableFromInline internal let schemaVersion: UInt32
    
    /// Callback for processing decoded chunks incrementally.
    public typealias ChunkCallback = (Data) throws -> Void
    
    /// Creates a new incremental decoder.
    /// - Parameters:
    ///   - maxAllowedLength: Maximum allowed length for variable-length fields (default: 10 MB)
    public init(maxAllowedLength: Int = 10 * 1024 * 1024) {
        self.buffer = Data()
        self.offset = 0
        self.maxAllowedLength = maxAllowedLength
        self.schemaVersion = 1 // Default, will be detected when data arrives
    }
    
    /// Appends data to the internal buffer for incremental processing.
    /// - Parameter data: Data chunk to append
    public func append(_ data: Data) {
        buffer.append(data)
    }
    
    /// Attempts to decode a complete field incrementally.
    /// - Returns: Decoded field data if complete, nil if more data needed
    /// - Throws: `BlazeBinaryError` if decoding fails
    public func decodeNextField() throws -> Data? {
        guard offset < buffer.count else {
            return nil
        }
        
        // Try to decode a varint length-prefixed field
        // First, check if we have enough data for the length prefix
        let savedOffset = offset
        
        // Try to decode varint length
        var length: UInt64 = 0
        var shift: UInt64 = 0
        var bytesRead = 0
        let maxBytes = 10
        
        var varintComplete = false
        while bytesRead < maxBytes && offset < buffer.count {
            let byte = buffer[offset]
            offset += 1
            bytesRead += 1

            length |= UInt64(byte & 0x7F) << shift

            if (byte & 0x80) == 0 {
                varintComplete = true
                break
            }

            shift += 7
            if shift >= 64 {
                offset = savedOffset
                throw BlazeBinaryError.invalidVarint
            }
        }

        // If the buffer was exhausted mid-varint (last byte had continuation bit set),
        // the varint is incomplete — restore offset and signal need for more data.
        if !varintComplete {
            offset = savedOffset
            return nil
        }

        // Check if we have the complete field
        // Validate that length can fit in Int before conversion
        guard length <= UInt64(Int.max) else {
            offset = savedOffset
            throw BlazeBinaryError.decodeFailed("Field length \(length) exceeds Int.max")
        }
        
        let lengthInt = Int(length)
        guard lengthInt >= 0 else {
            offset = savedOffset
            throw BlazeBinaryError.decodeFailed("Field length negative or overflowed")
        }
        guard lengthInt <= maxAllowedLength else {
            offset = savedOffset
            throw BlazeBinaryError.decodeFailed("Field length \(lengthInt) exceeds maximum \(maxAllowedLength)")
        }
        let end = offset + lengthInt
        guard end >= offset else {
            offset = savedOffset
            throw BlazeBinaryError.decodeFailed("Field length overflow")
        }
        guard end <= buffer.count else {
            // Not enough data yet, restore offset
            offset = savedOffset
            return nil
        }
        
        // Extract field data (end already validated)
        let fieldData = buffer.subdata(in: offset..<end)
        offset = end

        compactIfNeeded()
        return fieldData
    }
    
    /// Decodes a complete Data field incrementally.
    /// - Returns: Decoded Data if complete, nil if more data needed
    /// - Throws: `BlazeBinaryError` if decoding fails
    public func decodeDataIncremental() throws -> Data? {
        return try decodeNextField()
    }
    
    /// Decodes a complete String field incrementally.
    /// - Returns: Decoded String if complete, nil if more data needed
    /// - Throws: `BlazeBinaryError` if decoding fails
    public func decodeStringIncremental() throws -> String? {
        guard let utf8Data = try decodeNextField() else {
            return nil
        }
        
        guard let string = String(data: utf8Data, encoding: .utf8) else {
            throw BlazeBinaryError.decodeFailed("Invalid UTF-8 encoding")
        }
        
        return string
    }
    
    /// Processes a large array incrementally, calling the callback for each element.
    /// - Parameters:
    ///   - elementType: The element type to decode
    ///   - callback: Callback called for each decoded element
    /// - Returns: Number of elements processed
    /// - Throws: `BlazeBinaryError` if decoding fails
    public func decodeArrayIncremental<T: BlazeBinaryDecodable>(
        _ elementType: T.Type,
        callback: ChunkCallback
    ) throws -> Int {
        // Decode array count
        guard offset < buffer.count else {
            return 0
        }
        
        let savedOffset = offset
        var count: UInt64 = 0
        var shift: UInt64 = 0
        var bytesRead = 0
        let maxBytes = 10
        
        var varintComplete = false
        while bytesRead < maxBytes && offset < buffer.count {
            let byte = buffer[offset]
            offset += 1
            bytesRead += 1

            count |= UInt64(byte & 0x7F) << shift

            if (byte & 0x80) == 0 {
                varintComplete = true
                break
            }

            shift += 7
            if shift >= 64 {
                offset = savedOffset
                throw BlazeBinaryError.invalidVarint
            }
        }

        // If the buffer was exhausted mid-varint (last byte had continuation bit set),
        // the varint is incomplete — restore offset and signal need for more data.
        if !varintComplete {
            offset = savedOffset
            return 0
        }

        // Validate that count can fit in Int before conversion
        guard count <= UInt64(Int.max) else {
            offset = savedOffset
            throw BlazeBinaryError.decodeFailed("Array count \(count) exceeds Int.max")
        }
        
        guard count <= UInt64(maxAllowedLength) else {
            offset = savedOffset
            throw BlazeBinaryError.decodeFailed("Array count \(count) exceeds maximum \(maxAllowedLength)")
        }
        
        // Process elements incrementally — decode each element and call the callback
        // with the raw bytes consumed by that element.
        var processed = 0
        let countInt = Int(count)
        for _ in 0..<countInt {
            guard offset < buffer.count else {
                throw BlazeBinaryError.truncated
            }

            // Decode one element from the current position in the buffer.
            // BlazeBinaryDecoder works on a Data slice; its internal offset
            // tells us how many bytes the element consumed.
            let remaining = buffer.subdata(in: offset..<buffer.count)
            // Use rawMode to prevent the decoder from misinterpreting
            // element bytes that happen to start with 0xFE as a schema version marker.
            let elementDecoder = BlazeBinaryDecoder(data: remaining, rawMode: true)
            let _ = try T(from: elementDecoder)

            let bytesConsumed = elementDecoder.offset
            guard bytesConsumed > 0 else {
                throw BlazeBinaryError.decodeFailed("Element \(processed) consumed 0 bytes — possible infinite loop")
            }

            // Hand the raw bytes for this element to the callback
            let elementBytes = buffer.subdata(in: offset..<(offset + bytesConsumed))
            try callback(elementBytes)

            offset += bytesConsumed
            processed += 1
        }

        compactIfNeeded()
        return processed
    }
    
    /// Compacts the buffer by removing already-consumed bytes when more than
    /// half of the buffer has been processed, reducing memory waste.
    private func compactIfNeeded() {
        if offset > 0 && offset > buffer.count / 2 {
            buffer.removeFirst(offset)
            offset = 0
        }
    }

    /// Returns the current buffer size.
    public var bufferSize: Int {
        return buffer.count
    }
    
    /// Returns the current decode offset.
    public var currentOffset: Int {
        return offset
    }
    
    /// Clears the buffer and resets the decoder.
    public func clear() {
        buffer.removeAll()
        offset = 0
    }
    
    /// Returns remaining unprocessed data.
    public var remainingData: Data {
        guard offset < buffer.count else {
            return Data()
        }
        return buffer.subdata(in: offset..<buffer.count)
    }
}

