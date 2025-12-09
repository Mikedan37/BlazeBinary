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
/// - Parameters:
///   - payload: The data to encrypt
///   - key: The symmetric key for encryption
/// - Returns: Encrypted data (ciphertext + tag)
public func encryptPayload(_ payload: Data, using key: SymmetricKey) throws -> Data {
    // Use ChaCha20-Poly1305 like BlazeSecureSession
    let nonce = try ChaChaPoly.Nonce(data: Data(repeating: 0, count: 12)) // Simple nonce for hook
    let sealedBox = try ChaChaPoly.seal(payload, using: key, nonce: nonce)
    return sealedBox.ciphertext + sealedBox.tag
}

/// Decrypts a payload using AEAD (ChaCha20-Poly1305)
/// - Parameters:
///   - encrypted: The encrypted data (ciphertext + tag)
///   - key: The symmetric key for decryption
/// - Returns: Decrypted payload
public func decryptPayload(_ encrypted: Data, using key: SymmetricKey) throws -> Data {
    guard encrypted.count >= 16 else {
        throw BlazeBinaryError.decodeFailed("Encrypted data too short")
    }
    
    let ciphertext = encrypted.prefix(encrypted.count - 16)
    let tag = encrypted.suffix(16)
    let nonce = try ChaChaPoly.Nonce(data: Data(repeating: 0, count: 12)) // Simple nonce for hook
    
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

