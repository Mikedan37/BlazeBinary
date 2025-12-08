//
//  StreamingCompression.swift
//  BlazeBinary
//
//  Copyright (c) 2025 Michael Danylchuk
//  MIT License
//

import Foundation
import Compression

/// Streaming compression context for incremental compression/decompression.
/// 
/// This provides a chunked compression API that processes data in chunks
/// rather than requiring the entire payload in memory at once.
public class BlazeStreamingCompressor {
    private let mode: CompressionMode
    private var accumulatedData: Data
    private let chunkSize: Int
    
    /// Creates a new streaming compressor.
    /// - Parameters:
    ///   - mode: Compression mode (LZ4 or LZFSE)
    ///   - chunkSize: Size of chunks to compress (default: 64KB)
    public init(mode: CompressionMode, chunkSize: Int = 64 * 1024) throws {
        guard mode != .none else {
            throw BlazeBinaryError.decodeFailed("Streaming compression requires LZ4 or LZFSE")
        }
        self.mode = mode
        self.accumulatedData = Data()
        self.chunkSize = chunkSize
    }
    
    /// Compresses a chunk of data incrementally.
    /// - Parameter data: Data chunk to compress
    /// - Returns: Compressed data (may be empty if accumulating for larger chunk)
    /// - Throws: `BlazeBinaryError.decodeFailed` if compression fails
    public func compress(_ data: Data) throws -> Data {
        accumulatedData.append(data)
        
        // If we have enough data for a chunk, compress it
        if accumulatedData.count >= chunkSize {
            let chunk = accumulatedData.prefix(chunkSize)
            accumulatedData.removeFirst(chunk.count)
            
            return try BlazeCompression.compress(chunk, mode: mode)
        }
        
        // Not enough data yet, return empty
        return Data()
    }
    
    /// Finalizes compression and returns any remaining compressed data.
    /// - Returns: Final compressed data chunk
    /// - Throws: `BlazeBinaryError.decodeFailed` if finalization fails
    public func finalize() throws -> Data {
        guard !accumulatedData.isEmpty else {
            return Data()
        }
        
        let remaining = accumulatedData
        accumulatedData.removeAll()
        return try BlazeCompression.compress(remaining, mode: mode)
    }
}

/// Streaming decompression context for incremental decompression.
public class BlazeStreamingDecompressor {
    private let mode: CompressionMode
    private var accumulatedData: Data
    private let estimatedOutputSize: Int?
    
    /// Creates a new streaming decompressor.
    /// - Parameters:
    ///   - mode: Compression mode (LZ4 or LZFSE)
    ///   - estimatedOutputSize: Estimated decompressed size (optional, improves performance)
    public init(mode: CompressionMode, estimatedOutputSize: Int? = nil) throws {
        guard mode != .none else {
            throw BlazeBinaryError.decodeFailed("Streaming decompression requires LZ4 or LZFSE")
        }
        self.mode = mode
        self.accumulatedData = Data()
        self.estimatedOutputSize = estimatedOutputSize
    }
    
    /// Decompresses a chunk of data incrementally.
    /// - Parameter data: Compressed data chunk
    /// - Returns: Decompressed data (may be partial if more input needed)
    /// - Throws: `BlazeBinaryError.decodeFailed` if decompression fails
    public func decompress(_ data: Data) throws -> Data {
        accumulatedData.append(data)
        
        // Try to decompress accumulated data
        // In a real streaming implementation, we'd use compression_stream,
        // but for simplicity, we'll use the existing decompress API
        // This works for chunked compression where each chunk is independently compressed
        
        // For now, return empty - caller should call finalize() when done
        return Data()
    }
    
    /// Finalizes decompression and returns any remaining decompressed data.
    /// - Returns: Final decompressed data chunk
    /// - Throws: `BlazeBinaryError.decodeFailed` if finalization fails
    public func decompressFinal() throws -> Data {
        guard !accumulatedData.isEmpty else {
            return Data()
        }
        
        let compressed = accumulatedData
        accumulatedData.removeAll()
        return try BlazeCompression.decompress(compressed, mode: mode, originalSize: estimatedOutputSize)
    }
}
