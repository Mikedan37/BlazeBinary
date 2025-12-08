//
//  Compression.swift
//  BlazeBinary
//
//  Copyright (c) 2025 Michael Danylchuk
//  MIT License
//

import Foundation
import Compression

/// Compression mode for BlazeBinary frames.
public enum CompressionMode: UInt8 {
    /// No compression (default)
    case none = 0x00
    
    /// LZ4 compression (fast, good compression ratio)
    case lz4 = 0x01
    
    /// LZFSE compression (Apple's compression, good balance)
    case lzfse = 0x02
}

/// Compression utilities for BlazeBinary.
public enum BlazeCompression {
    /// Compresses data using the specified compression mode.
    /// - Parameters:
    ///   - data: The data to compress
    ///   - mode: The compression mode to use
    /// - Returns: The compressed data
    /// - Throws: `BlazeBinaryError.decodeFailed` if compression fails
    public static func compress(_ data: Data, mode: CompressionMode) throws -> Data {
        guard mode != .none else {
            return data
        }
        
        guard !data.isEmpty else {
            return data
        }
        
        let algorithm: compression_algorithm
        switch mode {
        case .none:
            return data
        case .lz4:
            algorithm = COMPRESSION_LZ4
        case .lzfse:
            algorithm = COMPRESSION_LZFSE
        }
        
        let bufferSize = data.count + (data.count / 8) + 32 // Conservative estimate
        var compressedData = Data(count: bufferSize)
        
        let compressedSize = data.withUnsafeBytes { sourceBuffer in
            compressedData.withUnsafeMutableBytes { destBuffer in
                compression_encode_buffer(
                    destBuffer.bindMemory(to: UInt8.self).baseAddress!,
                    bufferSize,
                    sourceBuffer.bindMemory(to: UInt8.self).baseAddress!,
                    data.count,
                    nil,
                    algorithm
                )
            }
        }
        
        guard compressedSize > 0 else {
            throw BlazeBinaryError.decodeFailed("Compression failed")
        }
        
        compressedData.count = compressedSize
        return compressedData
    }
    
    /// Decompresses data using the specified compression mode.
    /// - Parameters:
    ///   - data: The compressed data
    ///   - mode: The compression mode used
    ///   - originalSize: The expected decompressed size (if known, improves performance)
    /// - Returns: The decompressed data
    /// - Throws: `BlazeBinaryError.decodeFailed` if decompression fails
    public static func decompress(_ data: Data, mode: CompressionMode, originalSize: Int? = nil) throws -> Data {
        guard mode != .none else {
            return data
        }
        
        guard !data.isEmpty else {
            return data
        }
        
        let algorithm: compression_algorithm
        switch mode {
        case .none:
            return data
        case .lz4:
            algorithm = COMPRESSION_LZ4
        case .lzfse:
            algorithm = COMPRESSION_LZFSE
        }
        
        // Estimate decompressed size if not provided
        // For LZFSE, we need a more conservative estimate as it can compress very well
        // Try progressively larger buffers if needed
        var estimatedSize = originalSize ?? max(data.count * 10, 1024) // More conservative estimate
        var decompressedData = Data(count: estimatedSize)
        var result: Int = 0
        
        // Try decompression with estimated size
        result = data.withUnsafeBytes { sourceBuffer in
            decompressedData.withUnsafeMutableBytes { destBuffer in
                compression_decode_buffer(
                    destBuffer.bindMemory(to: UInt8.self).baseAddress!,
                    estimatedSize,
                    sourceBuffer.bindMemory(to: UInt8.self).baseAddress!,
                    data.count,
                    nil,
                    algorithm
                )
            }
        }
        
        // If buffer was too small, try with progressively larger sizes
        if result == 0 && estimatedSize < 100 * 1024 * 1024 { // Max 100MB
            // Try 20x, then 50x, then 100x
            for multiplier in [20, 50, 100] {
                estimatedSize = data.count * multiplier
                decompressedData = Data(count: estimatedSize)
                result = data.withUnsafeBytes { sourceBuffer in
                    decompressedData.withUnsafeMutableBytes { destBuffer in
                        compression_decode_buffer(
                            destBuffer.bindMemory(to: UInt8.self).baseAddress!,
                            estimatedSize,
                            sourceBuffer.bindMemory(to: UInt8.self).baseAddress!,
                            data.count,
                            nil,
                            algorithm
                        )
                    }
                }
                if result > 0 {
                    break
                }
            }
        }
        
        guard result > 0 else {
            throw BlazeBinaryError.decodeFailed("Decompression failed: buffer too small or invalid data")
        }
        
        decompressedData.count = result
        return decompressedData
    }
}

