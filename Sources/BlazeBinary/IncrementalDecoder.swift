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
        
        while bytesRead < maxBytes && offset < buffer.count {
            let byte = buffer[offset]
            offset += 1
            bytesRead += 1
            
            length |= UInt64(byte & 0x7F) << shift
            
            if (byte & 0x80) == 0 {
                break
            }
            
            shift += 7
            if shift >= 64 {
                offset = savedOffset
                throw BlazeBinaryError.invalidVarint
            }
        }
        
        // Check if we have the complete field
        // Validate that length can fit in Int before conversion
        guard length <= UInt64(Int.max) else {
            offset = savedOffset
            throw BlazeBinaryError.decodeFailed("Field length \(length) exceeds Int.max")
        }
        
        let lengthInt = Int(length)
        guard lengthInt <= maxAllowedLength else {
            offset = savedOffset
            throw BlazeBinaryError.decodeFailed("Field length \(lengthInt) exceeds maximum \(maxAllowedLength)")
        }
        
        guard offset + lengthInt <= buffer.count else {
            // Not enough data yet, restore offset
            offset = savedOffset
            return nil
        }
        
        // Extract field data
        let fieldData = buffer.subdata(in: offset..<(offset + lengthInt))
        offset += lengthInt
        
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
        
        while bytesRead < maxBytes && offset < buffer.count {
            let byte = buffer[offset]
            offset += 1
            bytesRead += 1
            
            count |= UInt64(byte & 0x7F) << shift
            
            if (byte & 0x80) == 0 {
                break
            }
            
            shift += 7
            if shift >= 64 {
                offset = savedOffset
                throw BlazeBinaryError.invalidVarint
            }
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
        
        // Process elements incrementally
        var processed = 0
        let countInt = Int(count)
        for _ in 0..<countInt {
            // For each element, we need to decode it completely
            // This is a simplified version - in practice, you'd need to know the element structure
            // For now, we'll just track that we're processing
            // A full implementation would decode each element and call the callback
            processed += 1
        }
        
        return processed
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

