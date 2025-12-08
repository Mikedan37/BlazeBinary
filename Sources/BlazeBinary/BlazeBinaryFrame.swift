//
// BlazeBinaryFrame.swift
// BlazeBinary
//
// Copyright (c) 2025 Michael Danylchuk
// MIT License
//

import Foundation

/// Frame encoder for IPC/socket communication.
public enum BlazeFrameEncoder {
    /// Maximum allowed frame size (5 MB)
    public static let maxFrameSize = 5 * 1024 * 1024
    
    /// Encodes a payload into a frame with explicit frame type and compression mode.
    /// 
    /// Frame format (v2.0):
    /// - Byte 0: frameType (UInt8) - 0x00 = plaintext, 0x01 = encrypted, 0x02 = handshake
    /// - Byte 1: compressionMode (UInt8) - 0x00 = none, 0x01 = LZ4, 0x02 = LZFSE
    /// - Bytes 2-5: payloadLength (UInt32 big-endian) - length of payload after compression
    /// - Bytes 6+: payload (compressed or raw depending on compressionMode)
    /// 
    /// - Parameters:
    ///   - payload: The binary payload to encode
    ///   - frameType: Frame type byte (default: 0x00 for plaintext)
    ///   - compressionMode: Compression mode (default: .none)
    /// - Returns: The encoded frame data
    /// - Throws: `BlazeBinaryError.oversizedFrame` if payload exceeds maxFrameSize
    public static func encodeFrame(
        _ payload: Data,
        frameType: UInt8 = 0x00,
        compressionMode: CompressionMode = .none
    ) throws -> Data {
        guard payload.count <= maxFrameSize else {
            throw BlazeBinaryError.oversizedFrame
        }
        
        // Compress payload if compression is enabled
        let processedPayload: Data
        if compressionMode != .none {
            processedPayload = try BlazeCompression.compress(payload, mode: compressionMode)
            guard processedPayload.count <= maxFrameSize else {
                throw BlazeBinaryError.oversizedFrame
            }
        } else {
            processedPayload = payload
        }
        
        var frame = Data()
        
        // Frame format (v2.0):
        // - Byte 0: frameType
        // - Byte 1: compressionMode
        // - Bytes 2-5: payloadLength (big-endian UInt32)
        // - Bytes 6+: payload
        
        frame.append(frameType)
        frame.append(compressionMode.rawValue)
        
        let payloadLength = UInt32(processedPayload.count).bigEndian
        frame.append(contentsOf: withUnsafeBytes(of: payloadLength) { Data($0) })
        frame.append(processedPayload)
        
        return frame
    }
    
    // MARK: - Secure Session Extensions
    
    /// Encodes an encrypted frame payload using a secure session.
    ///
    /// The payload is encrypted with ChaCha20-Poly1305 before being wrapped in a frame.
    /// Uses v2.0 frame format with explicit frameType=0x01 and compressionMode=0x00.
    ///
    /// Note: The secure session's `makeEncryptedFrame` includes the frameType byte in the payload
    /// for AAD (Additional Authenticated Data). In v2.0 format, we keep this frameType byte in
    /// the payload (as required by the secure session API) and also include it in the frame header.
    ///
    /// - Parameters:
    ///   - plaintext: Plaintext data to encrypt and encode
    ///   - session: Secure session for encryption
    ///   - compressionMode: Optional compression mode for plaintext before encryption (default: .none)
    /// - Returns: Encoded frame with encrypted payload
    /// - Throws: `BlazeBinaryError.oversizedFrame` or `BlazeBinaryError.encryptionFailed`
    public static func encodeEncryptedFrame(
        _ plaintext: Data,
        session: inout BlazeSecureSession,
        compressionMode: CompressionMode = .none
    ) throws -> Data {
        // Compress plaintext if requested (before encryption)
        let processedPlaintext: Data
        if compressionMode != .none {
            processedPlaintext = try BlazeCompression.compress(plaintext, mode: compressionMode)
        } else {
            processedPlaintext = plaintext
        }
        
        // Encrypt the payload (secure session includes frameType=0x01 as first byte for AAD)
        let encryptedPayload = try session.makeEncryptedFrame(from: processedPlaintext)
        
        // Verify frameType byte is present (required by secure session API)
        guard encryptedPayload.count > 0 && encryptedPayload[0] == SecureFrameType.encrypted.rawValue else {
            throw BlazeBinaryError.encryptionFailed("Invalid encrypted frame format")
        }
        
        // Check size limit
        guard encryptedPayload.count <= maxFrameSize else {
            throw BlazeBinaryError.oversizedFrame
        }
        
        // Use v2.0 frame format: frameType=0x01, compressionMode (as specified), payloadLength, payload
        // Note: encryptedPayload already includes frameType byte as first byte (required for AAD)
        return try encodeFrame(encryptedPayload, frameType: SecureFrameType.encrypted.rawValue, compressionMode: compressionMode)
    }
    
    /// Encodes a handshake frame payload.
    ///
    /// Uses v2.0 frame format with explicit frameType=0x02 and compressionMode=0x00.
    ///
    /// - Parameter handshakePayload: Handshake message data
    /// - Returns: Encoded frame with handshake payload
    /// - Throws: `BlazeBinaryError.oversizedFrame` if payload exceeds maxFrameSize
    public static func encodeHandshakeFrame(_ handshakePayload: Data) throws -> Data {
        // Use v2.0 frame format: frameType=0x02, compressionMode=0x00, payloadLength, payload
        return try encodeFrame(handshakePayload, frameType: SecureFrameType.handshake.rawValue, compressionMode: .none)
    }
}

/// Backpressure threshold configuration for frame parser.
public struct BackpressureConfig {
    /// High water mark: when buffer exceeds this, backpressure is signaled
    public let highWaterMark: Int
    
    /// Low water mark: when buffer drops below this, backpressure is cleared
    public let lowWaterMark: Int
    
    /// Creates a backpressure configuration.
    /// - Parameters:
    ///   - highWaterMark: Buffer size threshold for signaling backpressure (default: 8 MB)
    ///   - lowWaterMark: Buffer size threshold for clearing backpressure (default: 2 MB)
    public init(highWaterMark: Int = 8 * 1024 * 1024, lowWaterMark: Int = 2 * 1024 * 1024) {
        self.highWaterMark = highWaterMark
        self.lowWaterMark = lowWaterMark
    }
}

/// Streaming frame parser for incremental frame decoding with backpressure support.
public class BlazeFrameParser {
    /// Maximum allowed buffer size (10 MB)
    public static let maxBufferSize = 10 * 1024 * 1024
    
    @usableFromInline internal var buffer: Data
    @usableFromInline internal let maxFrameSize: Int
    
    /// Optional secure session for decrypting encrypted frames.
    /// If nil, encrypted frames will be returned as-is (caller must handle decryption).
    public var secureSession: BlazeSecureSession?
    
    /// Backpressure configuration
    public let backpressureConfig: BackpressureConfig
    
    /// Current backpressure state
    @usableFromInline internal var isBackpressured: Bool
    
    /// Creates a new frame parser.
    /// - Parameters:
    ///   - maxFrameSize: Maximum allowed frame size (default: 5 MB)
    ///   - secureSession: Optional secure session for decrypting encrypted frames
    ///   - backpressureConfig: Backpressure configuration (default: 8MB high, 2MB low)
    public init(
        maxFrameSize: Int = BlazeFrameEncoder.maxFrameSize,
        secureSession: BlazeSecureSession? = nil,
        backpressureConfig: BackpressureConfig = BackpressureConfig()
    ) {
        self.buffer = Data()
        self.maxFrameSize = maxFrameSize
        self.secureSession = secureSession
        self.backpressureConfig = backpressureConfig
        self.isBackpressured = false
    }
    
    /// Appends data to the internal buffer and checks for buffer overflow.
    /// 
    /// This method is used for incremental frame parsing. Data can be appended
    /// in chunks as it arrives, and `nextFrame()` can be called to extract
    /// complete frames when available.
    /// 
    /// - Parameter data: The data to append to the internal buffer
    /// - Returns: `true` if backpressure is active (buffer exceeds high water mark), `false` otherwise
    /// - Throws: `BlazeBinaryError.oversizedFrame` if appending would cause buffer to exceed maxBufferSize (10 MB)
    /// - Note: The buffer size is checked after appending. If the buffer exceeds the limit,
    ///   the error is thrown and the buffer state remains unchanged (the append is not applied).
    @discardableResult
    public func append(_ data: Data) throws -> Bool {
        let newSize = buffer.count + data.count
        guard newSize <= Self.maxBufferSize else {
            throw BlazeBinaryError.oversizedFrame
        }
        buffer.append(data)
        
        // Update backpressure state
        updateBackpressureState()
        
        return isBackpressured
    }
    
    /// Updates the backpressure state based on current buffer size.
    @usableFromInline
    internal func updateBackpressureState() {
        if !isBackpressured && buffer.count >= backpressureConfig.highWaterMark {
            isBackpressured = true
        } else if isBackpressured && buffer.count <= backpressureConfig.lowWaterMark {
            isBackpressured = false
        }
    }
    
    /// Returns whether backpressure is currently active.
    /// 
    /// Backpressure is active when the buffer size exceeds the high water mark.
    /// Callers should pause sending data when backpressure is active.
    /// 
    /// - Returns: `true` if backpressure is active, `false` otherwise
    public var hasBackpressure: Bool {
        return isBackpressured
    }
    
    /// Attempts to extract the next complete frame from the buffer.
    /// 
    /// Supports both v1.0 (legacy) and v2.0 (new) frame formats:
    /// 
    /// v1.0 format (legacy, backwards compatible):
    /// - Bytes 0-3: payloadLength (UInt32 big-endian)
    /// - Bytes 4+: payload
    /// 
    /// v2.0 format (new, explicit):
    /// - Byte 0: frameType (UInt8)
    /// - Byte 1: compressionMode (UInt8)
    /// - Bytes 2-5: payloadLength (UInt32 big-endian)
    /// - Bytes 6+: payload
    /// 
    /// Detection: If byte 0 is a valid frameType (0x00-0x02) and byte 1 is a valid compressionMode (0x00-0x02),
    /// treat as v2.0 format. Otherwise, treat as v1.0 format.
    /// 
    /// - Returns: The frame payload (decompressed if needed) if a complete frame is available, nil if more data is needed
    /// - Throws: `BlazeBinaryError.invalidFrameLength` if the payload length is invalid (0 or exceeds maxFrameSize)
    /// - Throws: `BlazeBinaryError.decodeFailed` if decompression fails or compression mode is invalid
    /// - Note: This method never throws for partial frames. It only throws for invalid frame lengths or decompression errors.
    ///   Partial frames return nil, allowing the caller to append more data and try again.
    public func nextFrame() throws -> Data? {
        // Need at least 4 bytes for v1.0 format (length prefix)
        guard buffer.count >= 4 else {
            return nil // Need more data
        }
        
        // Try to detect v2.0 format: check if bytes 0-1 look like frameType + compressionMode
        // v2.0 format: byte0 is frameType (0x00-0x02), byte1 is compressionMode (0x00-0x02)
        // v1.0 format: bytes 0-3 form a length prefix (big-endian UInt32)
        // Detection heuristic: If byte0 <= 0x02 AND byte1 <= 0x02 AND the resulting payload length is reasonable,
        // treat as v2.0. Otherwise, treat as v1.0.
        let isV2Format: Bool
        if buffer.count >= 6 {
            let byte0 = buffer[0]
            let byte1 = buffer[1]
            
            // Check if bytes 0-1 could be frameType + compressionMode
            if (byte0 <= 0x02) && (byte1 <= 0x02) {
                // Read potential payload length (bytes 2-5)
                let lengthBytes = buffer.subdata(in: 2..<6)
                let potentialLength = lengthBytes.withUnsafeBytes { bytes in
                    var value: UInt32 = 0
                    value |= UInt32(bytes[0]) << 24
                    value |= UInt32(bytes[1]) << 16
                    value |= UInt32(bytes[2]) << 8
                    value |= UInt32(bytes[3])
                    return value
                }
                
                // If the potential payload length is reasonable (not absurdly large), treat as v2.0
                // v1.0 frames with very small payloads (byte0=0x00, byte1=0x00) would have length=0, which is invalid
                // So if byte0=0x00, byte1=0x00, and potentialLength is reasonable, it's likely v2.0
                // But if byte0=0x00, byte1=0x00, and potentialLength is 0 or very large, it's likely v1.0
                if potentialLength > 0 && potentialLength <= UInt32(maxFrameSize) {
                    isV2Format = true
                } else {
                    // Potential length is invalid, treat as v1.0
                    isV2Format = false
                }
            } else {
                // Bytes 0-1 don't look like frameType + compressionMode, treat as v1.0
                isV2Format = false
            }
        } else {
            // Not enough bytes for v2.0 format, treat as v1.0
            isV2Format = false
        }
        
        if isV2Format {
            // v2.0 format: explicit frameType and compressionMode
            let frameType = buffer[0]
            let compressionModeByte = buffer[1]
            
            // Read payload length (bytes 2-5, big-endian UInt32)
            let lengthBytes = buffer.subdata(in: 2..<6)
            let payloadLength = lengthBytes.withUnsafeBytes { bytes in
                var value: UInt32 = 0
                value |= UInt32(bytes[0]) << 24
                value |= UInt32(bytes[1]) << 16
                value |= UInt32(bytes[2]) << 8
                value |= UInt32(bytes[3])
                return value
            }
            
            let payloadLengthInt = Int(payloadLength)
            
            // Validate payload length
            guard payloadLengthInt > 0 && payloadLengthInt <= maxFrameSize else {
                throw BlazeBinaryError.invalidFrameLength
            }
            
            // Check if we have the complete frame (6-byte header + payload)
            let totalFrameSize = 6 + payloadLengthInt
            guard buffer.count >= totalFrameSize else {
                return nil // Need more data
            }
            
            // Extract payload (bytes 6+)
            let payloadStartIndex = 6
            let payloadEndIndex = payloadStartIndex + payloadLengthInt
            guard buffer.count >= payloadEndIndex else {
                return nil // Need more data
            }
            var payload = buffer.subdata(in: payloadStartIndex..<payloadEndIndex)
            
            // Parse compression mode (explicit, no detection)
            guard let compressionMode = CompressionMode(rawValue: compressionModeByte) else {
                throw BlazeBinaryError.decodeFailed("Invalid compression mode: \(compressionModeByte)")
            }
            
            // Decompress if needed (explicit mode, no heuristics)
            if compressionMode != .none {
                do {
                    payload = try BlazeCompression.decompress(payload, mode: compressionMode, originalSize: nil)
                } catch {
                    throw BlazeBinaryError.decodeFailed("Decompression failed: \(error.localizedDescription)")
                }
            }
            
            // Handle secure session frame types
            if frameType == SecureFrameType.encrypted.rawValue {
                // Encrypted frame (minimum size: 1 byte frameType + 12 byte nonce + 16 byte tag = 29 bytes)
                guard payload.count >= 29 else {
                    throw BlazeBinaryError.decodeFailed("Encrypted frame too small: \(payload.count) bytes (minimum 29)")
                }
                
                guard payload[0] == SecureFrameType.encrypted.rawValue else {
                    throw BlazeBinaryError.decodeFailed("Encrypted frame payload frameType mismatch")
                }
                
                if var session = secureSession {
                    let decrypted = try session.decryptFramePayload(payload)
                    secureSession = session
                    buffer.removeFirst(totalFrameSize)
                    return decrypted
                } else {
                    let encryptedData = payload.subdata(in: 1..<payload.count)
                    buffer.removeFirst(totalFrameSize)
                    return encryptedData
                }
            } else if frameType == SecureFrameType.handshake.rawValue {
                buffer.removeFirst(totalFrameSize)
                return payload
            } else {
                buffer.removeFirst(totalFrameSize)
                return payload
            }
        } else {
            // v1.0 format (legacy): length prefix + payload
            let lengthBytes = buffer.prefix(4)
            let length = lengthBytes.withUnsafeBytes { bytes in
                var value: UInt32 = 0
                value |= UInt32(bytes[0]) << 24
                value |= UInt32(bytes[1]) << 16
                value |= UInt32(bytes[2]) << 8
                value |= UInt32(bytes[3])
                return value
            }
            
            let lengthInt = Int(length)
            
            // Validate frame length
            guard lengthInt > 0 && lengthInt <= maxFrameSize else {
                throw BlazeBinaryError.invalidFrameLength
            }
            
            // Check if we have the complete frame (4-byte header + payload)
            let totalFrameSize = 4 + lengthInt
            guard buffer.count >= totalFrameSize else {
                return nil // Need more data
            }
            
            // Extract payload (bytes 4+)
            let payload = buffer.subdata(in: 4..<(4 + lengthInt))
            
            // v1.0 format: no compression, no frameType (treat as plaintext)
            buffer.removeFirst(totalFrameSize)
            updateBackpressureState()
            return payload
        }
    }
    
    /// Returns the current buffer size in bytes.
    /// 
    /// This can be used to monitor buffer growth and ensure it stays within limits.
    /// - Returns: The number of bytes currently in the buffer
    public var bufferSize: Int {
        return buffer.count
    }
    
    /// Clears the internal buffer, resetting the parser to its initial state.
    /// 
    /// This is useful for resetting the parser after an error or when starting
    /// a new stream. After clearing, the parser is ready to accept new data via `append()`.
    public func clear() {
        buffer.removeAll()
    }
}

