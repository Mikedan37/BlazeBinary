//
// BlazeBinaryHooks.swift
// BlazeBinary
//
// API hooks for BlazeTransport integration
// These provide simple, transport-agnostic encoding/decoding helpers
//

import Foundation
import Crypto

/// Serializes a Codable value to bytes
/// - Parameter value: The Codable value to encode
/// - Returns: Array of bytes representing the encoded value
public func serializeMessage<T: BlazeBinaryCodable>(_ value: T) throws -> [UInt8] {
    let encoder = BlazeBinaryEncoder()
    try encoder.encode(value)
    return Array(encoder.encodedData())
}

/// Deserializes bytes to a typed Codable value
/// - Parameters:
///   - bytes: The encoded bytes
///   - type: The type to decode as
/// - Returns: The decoded value
public func deserializeMessage<T: BlazeBinaryCodable>(_ bytes: [UInt8], as type: T.Type) throws -> T {
    let data = Data(bytes)
    let decoder = BlazeBinaryDecoder(data: data)
    return try decoder.decode(type)
}

/// Encrypts a payload using AEAD (ChaCha20-Poly1305)
///
/// Output format: [12-byte nonce][ciphertext][16-byte tag]
///
/// A fresh random nonce is generated for every call. The nonce is prepended
/// to the output so `decryptPayload` can recover it.
///
/// - Parameters:
///   - payload: The data to encrypt
///   - key: The symmetric key for encryption
/// - Returns: Encrypted data (nonce + ciphertext + tag)
public func encryptPayload(_ payload: Data, using key: SymmetricKey) throws -> Data {
    let nonce = ChaChaPoly.Nonce()  // Random 12-byte nonce
    let sealedBox = try ChaChaPoly.seal(payload, using: key, nonce: nonce)
    // Prepend nonce so decryptPayload can recover it
    return Data(nonce) + sealedBox.ciphertext + sealedBox.tag
}

/// Decrypts a payload using AEAD (ChaCha20-Poly1305)
///
/// Expected input format: [12-byte nonce][ciphertext][16-byte tag]
/// (as produced by `encryptPayload`)
///
/// - Parameters:
///   - encrypted: The encrypted data (nonce + ciphertext + tag)
///   - key: The symmetric key for decryption
/// - Returns: Decrypted payload
public func decryptPayload(_ encrypted: Data, using key: SymmetricKey) throws -> Data {
    // Minimum size: 12 (nonce) + 0 (ciphertext) + 16 (tag) = 28 bytes
    guard encrypted.count >= 28 else {
        throw BlazeBinaryError.decodeFailed("Encrypted data too short: need at least 28 bytes (12 nonce + 16 tag), got \(encrypted.count)")
    }

    let nonceData = encrypted.prefix(12)
    let ciphertextAndTag = encrypted.dropFirst(12)
    let ciphertext = ciphertextAndTag.prefix(ciphertextAndTag.count - 16)
    let tag = ciphertextAndTag.suffix(16)

    let nonce = try ChaChaPoly.Nonce(data: nonceData)
    let sealedBox = try ChaChaPoly.SealedBox(nonce: nonce, ciphertext: ciphertext, tag: tag)
    return try ChaChaPoly.open(sealedBox, using: key)
}

/// Encodes a BlazeBinary frame
/// Format: [1 byte frameType][varint length][payload bytes]
/// - Parameters:
///   - type: Frame type (UInt8)
///   - payload: Frame payload data
/// - Returns: Encoded frame
public func encodeFrame(type: UInt8, payload: Data) throws -> Data {
    return try BlazeFrameEncoder.encodeFrame(payload, frameType: type, compressionMode: .none)
}

/// Decodes a BlazeBinary frame
/// - Parameter data: The frame data to decode
/// - Returns: Tuple of (frameType, payload)
public func decodeFrame(_ data: Data) throws -> (frameType: UInt8, payload: Data) {
    var parser = BlazeFrameParser()
    try parser.append(data)
    
    guard let frameData = try parser.nextFrame() else {
        throw BlazeBinaryError.truncated
    }
    
    // Extract frame type from the frame header
    // Frame format: [frameType(1)][compressionMode(1)][payloadLength(4)][payload]
    guard data.count >= 1 else {
        throw BlazeBinaryError.truncated
    }
    
    let frameType = data[0]
    return (frameType: frameType, payload: frameData)
}

