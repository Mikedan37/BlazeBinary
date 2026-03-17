//
//  Compression.swift
//  BlazeBinary
//
//  Copyright (c) 2025 Michael Danylchuk
//  MIT License
//

import Foundation
#if canImport(Compression)
import Compression
#endif

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
        
        #if canImport(Compression)
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

        // If compressedSize == bufferSize, output may have been truncated.
        // Retry with progressively larger buffers until compressedSize < currentBufferSize.
        if compressedSize == bufferSize {
            var currentBufferSize = bufferSize
            var currentCompressedData = compressedData
            var currentCompressedSize = compressedSize
            for multiplier in [2, 4, 8] {
                currentBufferSize = bufferSize * multiplier
                currentCompressedData = Data(count: currentBufferSize)
                currentCompressedSize = data.withUnsafeBytes { sourceBuffer in
                    currentCompressedData.withUnsafeMutableBytes { destBuffer in
                        compression_encode_buffer(
                            destBuffer.bindMemory(to: UInt8.self).baseAddress!,
                            currentBufferSize,
                            sourceBuffer.bindMemory(to: UInt8.self).baseAddress!,
                            data.count,
                            nil,
                            algorithm
                        )
                    }
                }
                guard currentCompressedSize > 0 else {
                    throw BlazeBinaryError.decodeFailed("Compression failed")
                }
                if currentCompressedSize < currentBufferSize { break }
            }
            guard currentCompressedSize < currentBufferSize else {
                throw BlazeBinaryError.decodeFailed("Compression failed: output buffer exhausted")
            }
            currentCompressedData.count = currentCompressedSize
            return currentCompressedData
        }

        compressedData.count = compressedSize
        return compressedData
        #else
        // Compression not available on this platform
        throw BlazeBinaryError.decodeFailed("Compression not supported on this platform")
        #endif
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
        
        #if canImport(Compression)
        let algorithm: compression_algorithm
        switch mode {
        case .none:
            return data
        case .lz4:
            algorithm = COMPRESSION_LZ4
        case .lzfse:
            algorithm = COMPRESSION_LZFSE
        }
        
        let maxAbsoluteSize = 16 * 1024 * 1024 // 16MB absolute ceiling
        let maxRatio = 100                      // 100x expansion ratio ceiling
        
        // Estimate decompressed size if not provided
        var estimatedSize = originalSize ?? max(data.count * 10, 1024)
        
        // Enforce both absolute and ratio limits on estimated size
        let ratioLimit = data.count <= Int.max / maxRatio ? data.count * maxRatio : maxAbsoluteSize
        let effectiveLimit = min(maxAbsoluteSize, ratioLimit)
        estimatedSize = min(estimatedSize, effectiveLimit)
        
        var decompressedData = Data(count: estimatedSize)
        var result: Int = 0
        
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
        
        // If buffer was too small or result == estimatedSize (ambiguous truncation), retry with larger sizes
        if result == 0 || result == estimatedSize {
            for multiplier in [20, 50, 100] {
                let (candidateSize, overflow) = data.count.multipliedReportingOverflow(by: multiplier)
                if overflow { break }
                estimatedSize = min(candidateSize, effectiveLimit)
                if estimatedSize == decompressedData.count { continue }

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
                if result > 0 && result < estimatedSize { break }
                if estimatedSize >= effectiveLimit { break }
            }
        }
        
        guard result > 0 else {
            throw BlazeBinaryError.decodeFailed("Decompression failed: buffer too small or invalid data")
        }
        
        guard result <= maxAbsoluteSize else {
            throw BlazeBinaryError.decodeFailed("Decompressed size (\(result) bytes) exceeds absolute limit (\(maxAbsoluteSize) bytes)")
        }
        
        decompressedData.count = result
        return decompressedData
        #else
        // Compression not available on this platform
        throw BlazeBinaryError.decodeFailed("Compression not supported on this platform")
        #endif
    }
}

