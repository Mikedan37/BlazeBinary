//
//  StreamingCompression.swift
//  BlazeBinary
//
//  Copyright (c) 2025 Michael Danylchuk
//  MIT License
//

import Foundation
#if canImport(Compression)
import Compression
#endif

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
        #if !canImport(Compression)
        throw BlazeBinaryError.decodeFailed("Compression not supported on this platform")
        #else
        self.mode = mode
        self.accumulatedData = Data()
        self.chunkSize = chunkSize
        #endif
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

/// Buffered decompression context.
///
/// Each call to `decompress(_:)` should pass a complete independently-compressed
/// chunk (as produced by `BlazeStreamingCompressor`). The chunk is decompressed
/// immediately and the result returned. If a chunk cannot be decompressed on its
/// own (e.g. the compressed data was not chunked), accumulate all data and call
/// `decompressFinal()` instead.
///
/// > Note: This does not use `compression_stream` internally. Each chunk must be
/// > a self-contained compressed block.
public class BlazeStreamingDecompressor {
    private let mode: CompressionMode
    private var accumulatedData: Data
    private let estimatedOutputSize: Int?
    private var isFinalized: Bool = false

    /// Creates a new decompressor.
    /// - Parameters:
    ///   - mode: Compression mode (LZ4 or LZFSE)
    ///   - estimatedOutputSize: Estimated decompressed size (optional, improves performance)
    public init(mode: CompressionMode, estimatedOutputSize: Int? = nil) throws {
        guard mode != .none else {
            throw BlazeBinaryError.decodeFailed("Streaming decompression requires LZ4 or LZFSE")
        }
        #if !canImport(Compression)
        throw BlazeBinaryError.decodeFailed("Compression not supported on this platform")
        #else
        self.mode = mode
        self.accumulatedData = Data()
        self.estimatedOutputSize = estimatedOutputSize
        #endif
    }

    /// Decompresses a single independently-compressed chunk.
    ///
    /// If the chunk is a complete compressed block (e.g. one output chunk from
    /// `BlazeStreamingCompressor`), it is decompressed and returned immediately.
    /// If decompression fails — typically because the data is a fragment of a
    /// larger compressed stream — the data is buffered for `decompressFinal()`.
    ///
    /// - Parameter data: A compressed data chunk
    /// - Returns: Decompressed data, or empty `Data` if the chunk was buffered
    /// - Throws: Only rethrows errors unrelated to incomplete input
    public func decompress(_ data: Data) throws -> Data {
        guard !isFinalized else {
            throw BlazeBinaryError.decodeFailed("Cannot decompress after finalization")
        }
        // Try to decompress this chunk as a standalone block.
        // BlazeStreamingCompressor produces independent chunks, so this
        // should succeed when paired with that compressor.
        do {
            return try BlazeCompression.decompress(data, mode: mode, originalSize: estimatedOutputSize)
        } catch let error as BlazeBinaryError {
            // Decompression-specific failure — this chunk is not a standalone block.
            // Buffer it for decompressFinal().
            if case .decodeFailed = error {
                accumulatedData.append(data)
                return Data()
            }
            throw error
        }
    }

    /// Decompresses any buffered data that could not be decompressed per-chunk.
    ///
    /// Call this after all chunks have been passed to `decompress(_:)`. If every
    /// chunk was already decompressed individually, this returns empty data.
    ///
    /// - Returns: Final decompressed data
    /// - Throws: `BlazeBinaryError.decodeFailed` if decompression fails
    public func decompressFinal() throws -> Data {
        isFinalized = true
        guard !accumulatedData.isEmpty else {
            return Data()
        }

        let compressed = accumulatedData
        accumulatedData.removeAll()
        return try BlazeCompression.decompress(compressed, mode: mode, originalSize: estimatedOutputSize)
    }
}
