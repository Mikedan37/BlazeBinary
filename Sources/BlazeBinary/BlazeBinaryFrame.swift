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

    /// Magic byte that unambiguously identifies v2 frames.
    ///
    /// v1 frames start with a big-endian UInt32 length prefix. Since the maximum
    /// frame size is 5 MB (0x004C4B40), byte 0 of a valid v1 frame is always 0x00.
    /// The magic byte 0xBF is structurally impossible in v1, making format detection
    /// deterministic with zero heuristics.
    public static let v2Magic: UInt8 = 0xBF

    /// Size of v2 frame header in bytes: 1 (magic) + 1 (frameType) + 1 (compressionMode) + 4 (payloadLength) = 7
    public static let v2HeaderSize = 7

    /// Encodes a payload into a frame with explicit frame type and compression mode.
    ///
    /// **Frame Format (v2.1)** — structurally unambiguous:
    /// - Byte 0: `0xBF` (magic byte — deterministic v2 identification)
    /// - Byte 1: `frameType` (UInt8) - 0x00 = plaintext, 0x01 = encrypted, 0x02 = handshake
    /// - Byte 2: `compressionMode` (UInt8) - 0x00 = none, 0x01 = LZ4, 0x02 = LZFSE
    /// - Bytes 3-6: `payloadLength` (UInt32, **big-endian network byte order**)
    /// - Bytes 7+: `payload` (compressed or raw depending on compressionMode)
    ///
    /// **Why magic byte**: Previous v2.0 format used a heuristic (byte0 <= 0x02 && byte1 <= 0x02)
    /// to distinguish v2 from v1 frames. This created in-band signaling ambiguity for v1 frames
    /// with payload lengths whose first two bytes happened to both be <= 0x02. The magic byte
    /// eliminates all heuristics — protocol detection is now structurally deterministic.
    ///
    /// **Endianness**: The `payloadLength` field uses big-endian (network byte order).
    ///
    /// **Framing Assumptions**:
    /// - Frames are delimited by the length prefix. The parser reads exactly `payloadLength` bytes after the header.
    /// - Frame boundaries are transport-agnostic: works with TCP, UDP, IPC, files, etc.
    /// - Maximum frame size: 5 MB (enforced by `maxFrameSize`).
    ///
    /// **Cross-Language Compatibility**:
    /// - Frame header (7 bytes) can be parsed by any language that supports big-endian UInt32.
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
        guard !payload.isEmpty else {
            throw BlazeBinaryError.invalidFrameLength
        }
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

        // Frame format (v2.1):
        // - Byte 0: 0xBF (magic)
        // - Byte 1: frameType
        // - Byte 2: compressionMode
        // - Bytes 3-6: payloadLength (big-endian UInt32)
        // - Bytes 7+: payload

        frame.append(v2Magic)
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
        guard encryptedPayload.count > 0 else {
            throw BlazeBinaryError.encryptionFailed("Encrypted payload is empty")
        }
        let frameTypeByte = encryptedPayload.withUnsafeBytes { bytes -> UInt8 in
            guard bytes.count >= 1 else {
                return 0xFF // Invalid sentinel value
            }
            return bytes[0]
        }
        guard frameTypeByte == SecureFrameType.encrypted.rawValue else {
            throw BlazeBinaryError.encryptionFailed("Invalid encrypted frame format: expected frameType \(SecureFrameType.encrypted.rawValue), got \(frameTypeByte)")
        }
        
        // Check size limit
        guard encryptedPayload.count <= maxFrameSize else {
            throw BlazeBinaryError.oversizedFrame
        }
        
        // Compression was already applied to plaintext above, so pass .none to encodeFrame
        // to avoid double-compression. Then patch byte 2 of the frame header to record the
        // original compressionMode so the parser knows to decompress after decryption.
        // v2.1 format: [0xBF][frameType][compressionMode][payloadLength][payload]
        var frame = try encodeFrame(encryptedPayload, frameType: SecureFrameType.encrypted.rawValue, compressionMode: .none)
        frame[2] = compressionMode.rawValue
        return frame
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
///
/// - Important: **Not thread-safe.** Calls to `append(_:)` and `nextFrame()` must
///   be serialized (e.g., on a single dispatch queue). The internal buffer is
///   mutated by both methods.
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
        let (newSize, overflow) = buffer.count.addingReportingOverflow(data.count)
        guard !overflow, newSize <= Self.maxBufferSize else {
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
    /// Supports both v1.0 (legacy) and v2.1 (current) frame formats:
    ///
    /// **v1.0 format (legacy, backwards compatible)**:
    /// - Bytes 0-3: `payloadLength` (UInt32, **big-endian network byte order**)
    /// - Bytes 4+: `payload`
    ///
    /// **v2.1 format (current, structurally unambiguous)**:
    /// - Byte 0: `0xBF` (magic byte)
    /// - Byte 1: `frameType` (UInt8)
    /// - Byte 2: `compressionMode` (UInt8)
    /// - Bytes 3-6: `payloadLength` (UInt32, **big-endian network byte order**)
    /// - Bytes 7+: `payload`
    ///
    /// **Detection**: Byte 0 == `0xBF` → v2.1. Anything else → v1.0.
    /// This is deterministic: v1 frames start with a big-endian length whose MSB
    /// is always 0x00 (max 5 MB = 0x004C4B40), so 0xBF cannot occur at byte 0 in v1.
    ///
    /// - Returns: The frame payload (decompressed if needed) if a complete frame is available, nil if more data is needed
    /// - Throws: `BlazeBinaryError.invalidFrameLength` if the payload length is invalid (0 or exceeds maxFrameSize)
    /// - Throws: `BlazeBinaryError.decodeFailed` if decompression fails or compression mode is invalid
    public func nextFrame() throws -> Data? {
        // Need at least 4 bytes for v1.0 format (length prefix)
        guard buffer.count >= 4 else {
            return nil // Need more data
        }

        // Deterministic format detection: check for v2 magic byte
        let byte0 = buffer.withUnsafeBytes { bytes -> UInt8 in
            guard bytes.count >= 1 else { return 0xFF }
            return bytes[0]
        }
        guard byte0 != 0xFF else { return nil }

        let isV2Format = (byte0 == BlazeFrameEncoder.v2Magic)

        if isV2Format {
            // v2.1 format: [0xBF][frameType][compressionMode][payloadLength(4 BE)][payload]
            let headerSize = BlazeFrameEncoder.v2HeaderSize // 7 bytes
            guard buffer.count >= headerSize else {
                return nil // Need more data
            }

            let (frameType, compressionModeByte) = buffer.withUnsafeBytes { bytes -> (UInt8, UInt8) in
                guard bytes.count >= 3 else { return (0xFF, 0xFF) }
                return (bytes[1], bytes[2])
            }
            guard frameType != 0xFF && compressionModeByte != 0xFF else {
                return nil
            }

            // Read payload length (bytes 3-6, big-endian UInt32)
            let payloadLength = buffer.withUnsafeBytes { bytes -> UInt32 in
                guard bytes.count >= headerSize else { return UInt32(0) }
                var value: UInt32 = 0
                value |= UInt32(bytes[3]) << 24
                value |= UInt32(bytes[4]) << 16
                value |= UInt32(bytes[5]) << 8
                value |= UInt32(bytes[6])
                return value
            }

            let payloadLengthInt = Int(payloadLength)

            // Validate payload length
            guard payloadLengthInt > 0 && payloadLengthInt <= maxFrameSize else {
                throw BlazeBinaryError.invalidFrameLength
            }

            // Check if we have the complete frame
            let totalFrameSize = headerSize + payloadLengthInt
            guard buffer.count >= totalFrameSize else {
                return nil // Need more data
            }

            // Extract payload (bytes 7+)
            let payloadStartIndex = headerSize
            let payloadEndIndex = payloadStartIndex + payloadLengthInt
            guard payloadEndIndex <= buffer.count else {
                return nil // Need more data
            }

            var payload = buffer.withUnsafeBytes { bytes -> Data in
                guard bytes.count >= payloadEndIndex else { return Data() }
                return Data(bytes[payloadStartIndex..<payloadEndIndex])
            }

            guard payload.count == payloadLengthInt else {
                throw BlazeBinaryError.decodeFailed("Payload extraction failed: expected \(payloadLengthInt) bytes, got \(payload.count)")
            }
            guard !payload.isEmpty else {
                throw BlazeBinaryError.decodeFailed("Payload extraction resulted in empty data")
            }

            // Parse compression mode
            guard let compressionMode = CompressionMode(rawValue: compressionModeByte) else {
                throw BlazeBinaryError.decodeFailed("Invalid compression mode: \(compressionModeByte)")
            }

            // Handle secure session frame types
            // Wire format for encrypted frames: encrypted(compressed(plaintext))
            // So decode order is: decrypt first, then decompress.
            if frameType == SecureFrameType.encrypted.rawValue {
                guard payload.count >= 29 else {
                    throw BlazeBinaryError.decodeFailed("Encrypted frame too small: \(payload.count) bytes (minimum 29)")
                }

                let payloadFrameType = payload.withUnsafeBytes { bytes -> UInt8 in
                    guard bytes.count >= 1 else { return 0xFF }
                    return bytes[0]
                }
                guard payloadFrameType == SecureFrameType.encrypted.rawValue else {
                    throw BlazeBinaryError.decodeFailed("Encrypted frame payload frameType mismatch: expected \(SecureFrameType.encrypted.rawValue), got \(payloadFrameType)")
                }

                if var session = secureSession {
                    var decrypted = try session.decryptFramePayload(payload)
                    secureSession = session
                    // Decompress after decryption
                    if compressionMode != .none {
                        do {
                            decrypted = try BlazeCompression.decompress(decrypted, mode: compressionMode, originalSize: nil)
                            guard !decrypted.isEmpty else {
                                throw BlazeBinaryError.decodeFailed("Decompression resulted in empty payload")
                            }
                        } catch {
                            throw BlazeBinaryError.decodeFailed("Decompression failed: \(error.localizedDescription)")
                        }
                    }
                    buffer.removeFirst(totalFrameSize)
                    updateBackpressureState()
                    return decrypted
                } else {
                    guard payload.count > 1 else {
                        throw BlazeBinaryError.decodeFailed("Encrypted payload too small for extraction")
                    }
                    let encryptedData = payload.withUnsafeBytes { bytes -> Data in
                        guard bytes.count > 1 else { return Data() }
                        return Data(bytes[1..<bytes.count])
                    }
                    guard !encryptedData.isEmpty else {
                        throw BlazeBinaryError.decodeFailed("Failed to extract encrypted data")
                    }
                    buffer.removeFirst(totalFrameSize)
                    updateBackpressureState()
                    return encryptedData
                }
            } else if frameType == SecureFrameType.handshake.rawValue {
                // Handshake frames: return as-is, no decompression
                buffer.removeFirst(totalFrameSize)
                updateBackpressureState()
                return payload
            } else {
                // Plaintext frames: decompress if needed
                if compressionMode != .none {
                    do {
                        payload = try BlazeCompression.decompress(payload, mode: compressionMode, originalSize: nil)
                        guard !payload.isEmpty else {
                            throw BlazeBinaryError.decodeFailed("Decompression resulted in empty payload")
                        }
                    } catch {
                        throw BlazeBinaryError.decodeFailed("Decompression failed: \(error.localizedDescription)")
                    }
                }
                buffer.removeFirst(totalFrameSize)
                updateBackpressureState()
                return payload
            }
        } else {
            // v1.0 format (legacy): [payloadLength(4 BE)][payload]
            let lengthBytes = buffer.prefix(4)
            let length = lengthBytes.withUnsafeBytes { bytes in
                guard bytes.count >= 4 else { return UInt32(0) }
                var value: UInt32 = 0
                value |= UInt32(bytes[0]) << 24
                value |= UInt32(bytes[1]) << 16
                value |= UInt32(bytes[2]) << 8
                value |= UInt32(bytes[3])
                return value
            }

            let lengthInt = Int(length)

            guard lengthInt > 0 && lengthInt <= maxFrameSize else {
                throw BlazeBinaryError.invalidFrameLength
            }

            let totalFrameSize = 4 + lengthInt
            guard buffer.count >= totalFrameSize else {
                return nil // Need more data
            }

            let payloadStart = 4
            let payloadEnd = 4 + lengthInt
            let payload = buffer.withUnsafeBytes { bytes -> Data in
                guard bytes.count >= payloadEnd else { return Data() }
                return Data(bytes[payloadStart..<payloadEnd])
            }

            guard payload.count == lengthInt else {
                throw BlazeBinaryError.decodeFailed("Payload extraction failed: expected \(lengthInt) bytes, got \(payload.count)")
            }

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

