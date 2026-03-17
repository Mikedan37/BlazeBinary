//
// BlazeSecureSession.swift
// BlazeBinary
//
// Copyright (c) 2025 Michael Danylchuk
// MIT License
//

import Foundation
import Crypto

/// Frame type byte values for secure session extensions.
internal enum SecureFrameType: UInt8 {
    /// Plaintext frame (backwards compatible)
    case plaintext = 0x00
    
    /// Encrypted data frame
    case encrypted = 0x01
    
    /// Handshake frame (plaintext, but marked as handshake)
    case handshake = 0x02
}

/// Secure session for encrypting and decrypting BlazeBinary frames.
///
/// Provides ChaCha20-Poly1305 AEAD encryption for frame payloads with:
/// - 12-byte nonces constructed from 4-byte prefix + 8-byte counter
/// - Separate send/recv counters for bidirectional communication
/// - AAD includes frame type and static context string
///
/// - Important: **Not thread-safe.** The send and receive counters are mutated on
///   every encrypt/decrypt call. If you need bidirectional communication from
///   different threads, use one session per direction or serialize access.
///
/// See ENCRYPTION.md for detailed specification.
public struct BlazeSecureSession {
    /// Derived session key material
    private let keyMaterial: BlazeSessionKeyMaterial
    
    /// Send counter (incremented for each outbound encrypted frame)
    private var sendCounter: UInt64

    /// Sliding window base for replay protection.
    /// Counters below this value are unconditionally rejected.
    private var recvCounterBase: UInt64

    /// Bitmap for counters in the range [recvCounterBase, recvCounterBase + windowSize - 1].
    /// Bit i is set if counter (recvCounterBase + i) has been received.
    private var recvBitmap: UInt64

    /// Size of the sliding replay protection window.
    private let windowSize: UInt64 = 64
    
    /// Enable strict replay protection (reject nonces with counter <= recvCounter)
    /// Default: true (production-ready)
    public var strictReplayProtection: Bool = true
    
    /// Crypto configuration
    private let config: BlazeCryptoConfig
    
    /// Creates a new secure session from derived key material.
    ///
    /// Counters start at 0, which is standard practice (TLS 1.3, WireGuard, Noise
    /// Protocol all do the same). Nonce uniqueness is guaranteed by the combination
    /// of the random 4-byte `noncePrefix` (unique per session) and the monotonic
    /// counter (unique per frame within a session). Even if two sessions encrypt
    /// the same plaintext, they'll produce different nonces because their prefixes
    /// differ.
    ///
    /// - Parameter keyMaterial: Session key material from handshake
    public init(keyMaterial: BlazeSessionKeyMaterial) {
        self.keyMaterial = keyMaterial
        self.sendCounter = 0
        self.recvCounterBase = 0
        self.recvBitmap = 0
        self.config = BlazeCryptoConfig()
    }
    
    /// Creates an encrypted frame payload from plaintext data.
    ///
    /// Encrypted frame format:
    /// - 1 byte: frameType = 0x01
    /// - 12 bytes: nonce (4-byte prefix + 8-byte big-endian counter)
    /// - N bytes: ciphertext
    /// - 16 bytes: authentication tag
    ///
    /// - Parameter plaintext: Plaintext data to encrypt
    /// - Returns: Encrypted frame payload (with frameType byte)
    /// - Throws: `BlazeBinaryError.encryptionFailed` if encryption fails
    public mutating func makeEncryptedFrame(from plaintext: Data) throws -> Data {
        // Bug 3 fix: Check exhaustion BEFORE using the counter
        guard sendCounter < UInt64.max else {
            throw BlazeBinaryError.encryptionFailed("Send counter exhausted — session must be rekeyed to prevent nonce reuse")
        }

        // Construct nonce: 4-byte prefix + 8-byte big-endian counter
        var nonce = Data()
        nonce.append(keyMaterial.sendNoncePrefix)

        // Append counter as big-endian UInt64
        let counterBytes = withUnsafeBytes(of: sendCounter.bigEndian) { Data($0) }
        nonce.append(counterBytes)

        guard nonce.count == 12 else {
            throw BlazeBinaryError.encryptionFailed("Invalid nonce length: \(nonce.count) (expected 12)")
        }

        // Construct AAD (Additional Authenticated Data)
        // Includes: frameType (0x01) + nonce prefix (bind prefix into authenticated data) + static context string
        var aad = Data()
        aad.append(SecureFrameType.encrypted.rawValue)
        aad.append(keyMaterial.sendNoncePrefix)
        aad.append(Data("BlazeBinaryFrame".utf8))

        // Encrypt with ChaCha20-Poly1305
        let sealedBox: ChaChaPoly.SealedBox
        do {
            let nonceObj = try ChaChaPoly.Nonce(data: nonce)
            sealedBox = try ChaChaPoly.seal(plaintext, using: keyMaterial.sendKey, nonce: nonceObj, authenticating: aad)
        } catch {
            throw BlazeBinaryError.encryptionFailed("AEAD encryption failed")
        }

        // Increment send counter after successful encryption
        sendCounter += 1

        // Construct encrypted frame payload
        var payload = Data()
        payload.append(SecureFrameType.encrypted.rawValue) // frameType = 0x01
        payload.append(nonce) // 12 bytes
        payload.append(sealedBox.ciphertext) // ciphertext
        payload.append(sealedBox.tag) // 16-byte tag

        return payload
    }
    
    /// Decrypts an encrypted frame payload.
    ///
    /// Expected format:
    /// - 1 byte: frameType = 0x01
    /// - 12 bytes: nonce
    /// - N bytes: ciphertext
    /// - 16 bytes: tag
    ///
    /// - Parameter payload: Encrypted frame payload (including frameType byte)
    /// - Returns: Decrypted plaintext
    /// - Throws: `BlazeBinaryError.encryptionFailed` if decryption fails or authentication fails
    public mutating func decryptFramePayload(_ payload: Data) throws -> Data {
        // Minimum length: 1 (frameType) + 12 (nonce) + 16 (tag) = 29 bytes
        guard !payload.isEmpty else {
            throw BlazeBinaryError.encryptionFailed("Encrypted frame payload is empty")
        }
        
        guard payload.count >= 29 else {
            throw BlazeBinaryError.encryptionFailed("Encrypted frame too short: \(payload.count) bytes (minimum 29)")
        }
        
        // Check frame type (safe to access - we've verified payload is not empty and has at least 29 bytes)
        // Use withUnsafeBytes for safer access across platforms
        let frameTypeByte = payload.withUnsafeBytes { bytes in
            guard bytes.count > 0 else {
                return UInt8(0xFF) // Invalid value
            }
            return bytes[0]
        }
        guard frameTypeByte == SecureFrameType.encrypted.rawValue else {
            throw BlazeBinaryError.encryptionFailed("Invalid frame type for decryption: \(frameTypeByte) (expected 0x01)")
        }
        
        // Extract nonce (bytes 1-12) - validate range before extraction
        guard payload.count >= 13 else {
            throw BlazeBinaryError.encryptionFailed("Payload too short for nonce extraction: \(payload.count) bytes (need 13)")
        }
        let nonceData = payload.subdata(in: 1..<13)
        
        // Note: The nonce prefix in keyMaterial is only used during encryption to construct nonces.
        // During decryption, we use the nonce from the frame directly. This allows different
        // sessions (with different nonce prefixes) to decrypt frames encrypted by other sessions
        // as long as they share the same encryption key (e.g., client/server after handshake).
        
        // Extract tag (last 16 bytes) - validate we have at least 16 bytes
        guard payload.count >= 16 else {
            throw BlazeBinaryError.encryptionFailed("Payload too short for tag extraction: \(payload.count) bytes (need 16)")
        }
        let tag = payload.suffix(16)
        
        // Extract ciphertext (bytes 13 to tag start) - validate range
        guard payload.count >= 29 else {
            throw BlazeBinaryError.encryptionFailed("Payload too short for ciphertext extraction: \(payload.count) bytes (need 29)")
        }
        let ciphertextStart = 13
        let ciphertextEnd = payload.count - 16
        // Allow empty ciphertext (ciphertextStart == ciphertextEnd) for empty plaintext
        guard ciphertextStart <= ciphertextEnd else {
            throw BlazeBinaryError.encryptionFailed("Invalid ciphertext range: start=\(ciphertextStart), end=\(ciphertextEnd)")
        }
        // Use withUnsafeBytes for safe extraction
        let ciphertext = payload.withUnsafeBytes { bytes -> Data in
            guard bytes.count >= payload.count else {
                return Data()  // Return empty on error
            }
            if ciphertextStart == ciphertextEnd {
                // Empty ciphertext (empty plaintext case)
                return Data()
            }
            return Data(bytes[ciphertextStart..<ciphertextEnd])
        }
        guard ciphertext.count == (ciphertextEnd - ciphertextStart) else {
            throw BlazeBinaryError.encryptionFailed("Ciphertext extraction failed: expected \(ciphertextEnd - ciphertextStart) bytes, got \(ciphertext.count)")
        }
        
        // Construct AAD (same as encryption — includes receive nonce prefix for prefix binding)
        var aad = Data()
        aad.append(SecureFrameType.encrypted.rawValue)
        aad.append(keyMaterial.receiveNoncePrefix)
        aad.append(Data("BlazeBinaryFrame".utf8))

        // Reconstruct sealed box
        let sealedBox = try ChaChaPoly.SealedBox(
            nonce: try ChaChaPoly.Nonce(data: nonceData),
            ciphertext: ciphertext,
            tag: tag
        )

        // Decrypt and authenticate
        let plaintext: Data
        do {
            plaintext = try ChaChaPoly.open(sealedBox, using: keyMaterial.receiveKey, authenticating: aad)
        } catch {
            // Map ChaChaPoly errors to BlazeBinaryError
            // Authentication failures are critical - drop connection
            // Maps to BlazeBinary.CryptoError.authenticationFailed via error conversion
            throw BlazeBinaryError.encryptionFailed("AEAD authentication failed")
        }
        
        // Extract and validate counter (strict replay protection)
        // Nonce format: 4-byte prefix + 8-byte big-endian counter
        let counterBytes = nonceData.suffix(8)
        let counter = counterBytes.withUnsafeBytes { bytes in
            var value: UInt64 = 0
            value |= UInt64(bytes[0]) << 56
            value |= UInt64(bytes[1]) << 48
            value |= UInt64(bytes[2]) << 40
            value |= UInt64(bytes[3]) << 32
            value |= UInt64(bytes[4]) << 24
            value |= UInt64(bytes[5]) << 16
            value |= UInt64(bytes[6]) << 8
            value |= UInt64(bytes[7])
            return value
        }
        
        // Sliding window replay protection:
        // - Counters below recvCounterBase are unconditionally rejected (too old).
        // - Counters within [recvCounterBase, recvCounterBase + windowSize - 1] are
        //   checked against recvBitmap — duplicates are rejected.
        // - Counters beyond the window advance the window and are accepted.
        if strictReplayProtection {
            if counter < recvCounterBase {
                throw BlazeBinaryError.encryptionFailed("Replay detected: frame counter is behind the replay window")
            }

            let offset = counter - recvCounterBase

            if offset < windowSize {
                // Within the window — check bitmap for duplicate
                let bit: UInt64 = 1 << offset
                if recvBitmap & bit != 0 {
                    throw BlazeBinaryError.encryptionFailed("Replay detected: duplicate frame counter within window")
                }
                recvBitmap |= bit
            } else {
                // Beyond the window — advance the window
                let shift = offset - windowSize + 1
                if shift >= windowSize {
                    // Jumped past the entire window — reset bitmap
                    recvBitmap = 0
                    recvCounterBase = counter
                } else {
                    recvBitmap >>= shift
                    recvCounterBase += shift
                }
                // Mark the new counter in the bitmap
                let newOffset = counter - recvCounterBase
                recvBitmap |= (1 << newOffset)
            }
        }
        
        return plaintext
    }
    
    /// Builds a handshake frame payload.
    /// - Parameter handshakePayload: Handshake message data
    /// - Returns: Frame payload with frameType = 0x02 prefix
    public func buildHandshakeFrame(_ handshakePayload: Data) -> Data {
        var payload = Data()
        payload.append(SecureFrameType.handshake.rawValue) // frameType = 0x02
        payload.append(handshakePayload)
        return payload
    }
    
    /// Parses a handshake frame payload and returns the handshake message.
    /// - Parameter framePayload: Frame payload (with frameType byte)
    /// - Returns: Handshake message data (without frameType byte)
    /// - Throws: `BlazeBinaryError.invalidHandshake` if frame type is incorrect
    public func parseHandshakeFrame(_ framePayload: Data) throws -> Data {
        guard framePayload.count >= 1 else {
            throw BlazeBinaryError.invalidHandshake("Handshake frame too short")
        }
        
        guard framePayload[0] == SecureFrameType.handshake.rawValue else {
            throw BlazeBinaryError.invalidHandshake("Invalid frame type for handshake: \(framePayload[0]) (expected 0x02)")
        }
        
        return framePayload.subdata(in: 1..<framePayload.count)
    }
    
    /// Convenience method: Encrypts a frame (alias for makeEncryptedFrame).
    public mutating func encryptFrame(_ plaintext: Data) throws -> Data {
        return try makeEncryptedFrame(from: plaintext)
    }
    
    /// Convenience method: Decrypts a frame (alias for decryptFramePayload).
    public mutating func decryptFrame(_ payload: Data) throws -> Data {
        return try decryptFramePayload(payload)
    }
}

