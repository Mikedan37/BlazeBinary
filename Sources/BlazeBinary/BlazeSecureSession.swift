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
/// See ENCRYPTION.md for detailed specification.
public struct BlazeSecureSession {
    /// Derived session key material
    private let keyMaterial: BlazeSessionKeyMaterial
    
    /// Send counter (incremented for each outbound encrypted frame)
    private var sendCounter: UInt64
    
    /// Receive counter (used for strict replay protection)
    /// Frames with counter <= recvCounter are rejected
    private var recvCounter: UInt64
    
    /// Enable strict replay protection (reject nonces with counter <= recvCounter)
    /// Default: true (production-ready)
    public var strictReplayProtection: Bool = true
    
    /// Crypto configuration
    private let config: BlazeCryptoConfig
    
    /// Creates a new secure session from derived key material.
    /// - Parameter keyMaterial: Session key material from handshake
    public init(keyMaterial: BlazeSessionKeyMaterial) {
        self.keyMaterial = keyMaterial
        self.sendCounter = 0
        self.recvCounter = 0
        self.config = BlazeCryptoConfig() // Use default config
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
        // Construct nonce: 4-byte prefix + 8-byte big-endian counter
        var nonce = Data()
        nonce.append(keyMaterial.noncePrefix)
        
        // Append counter as big-endian UInt64
        let counterBytes = withUnsafeBytes(of: sendCounter.bigEndian) { Data($0) }
        nonce.append(counterBytes)
        
        guard nonce.count == 12 else {
            throw BlazeBinaryError.encryptionFailed("Invalid nonce length: \(nonce.count) (expected 12)")
        }
        
        // Construct AAD (Additional Authenticated Data)
        // Includes: frameType (0x01) + static context string
        var aad = Data()
        aad.append(SecureFrameType.encrypted.rawValue)
        aad.append(Data("BlazeBinaryFrame".utf8))
        
        // Encrypt with ChaCha20-Poly1305
        let sealedBox: ChaChaPoly.SealedBox
        do {
            let nonceObj = try ChaChaPoly.Nonce(data: nonce)
            sealedBox = try ChaChaPoly.seal(plaintext, using: keyMaterial.encryptionKey, nonce: nonceObj, authenticating: aad)
        } catch {
            throw BlazeBinaryError.encryptionFailed("ChaChaPoly encryption failed: \(error)")
        }
        
        // Increment send counter
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
        guard payload.count >= 29 else {
            throw BlazeBinaryError.encryptionFailed("Encrypted frame too short: \(payload.count) bytes (minimum 29)")
        }
        
        // Check frame type
        guard payload[0] == SecureFrameType.encrypted.rawValue else {
            throw BlazeBinaryError.encryptionFailed("Invalid frame type for decryption: \(payload[0]) (expected 0x01)")
        }
        
        // Extract nonce (bytes 1-12)
        let nonceData = payload.subdata(in: 1..<13)
        
        // Note: The nonce prefix in keyMaterial is only used during encryption to construct nonces.
        // During decryption, we use the nonce from the frame directly. This allows different
        // sessions (with different nonce prefixes) to decrypt frames encrypted by other sessions
        // as long as they share the same encryption key (e.g., client/server after handshake).
        
        // Extract tag (last 16 bytes)
        let tag = payload.suffix(16)
        
        // Extract ciphertext (bytes 13 to tag start)
        let ciphertext = payload.subdata(in: 13..<(payload.count - 16))
        
        // Construct AAD (same as encryption)
        var aad = Data()
        aad.append(SecureFrameType.encrypted.rawValue)
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
            plaintext = try ChaChaPoly.open(sealedBox, using: keyMaterial.encryptionKey, authenticating: aad)
        } catch {
            // Map ChaChaPoly errors to BlazeBinaryError
            // Authentication failures are critical - drop connection
            // Maps to CryptoError.authenticationFailed via error conversion
            throw BlazeBinaryError.encryptionFailed("Authentication failed: \(error)")
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
        
        // Strict replay protection: reject nonces with counter <= recvCounter
        // Exception: Allow counter == recvCounter == 0 for the very first frame only
        // After that, counters must be strictly increasing (counter > recvCounter)
        if strictReplayProtection {
            if counter < recvCounter {
                // Counter is less than highest seen - definitely a replay
                throw CryptoError.nonceReuse
            } else if counter == recvCounter {
                // Counter equals highest seen
                if recvCounter == 0 {
                    // First frame: counter 0 == recvCounter 0, allow it
                    // Will be updated to 1 below
                } else {
                    // Not first frame: counter == recvCounter means replay
                    throw CryptoError.nonceReuse
                }
            }
            // Allow: counter > recvCounter (normal case)
        }
        
        // Update receive counter (strictly monotonic)
        // Set to counter + 1 to ensure next frame must have counter > current
        recvCounter = counter + 1
        
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

