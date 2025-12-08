//
// BlazeSecureHandshake.swift
// BlazeBinary
//
// Copyright (c) 2025 Michael Danylchuk
// MIT License
//

import Foundation
import Crypto

/// Role in the secure handshake protocol.
public enum BlazeHandshakeRole {
    /// Client role: initiates handshake with clientHello
    case client
    
    /// Server role: responds to clientHello with serverHello
    case server
}

/// Internal handshake message type.
private enum HandshakeType: UInt8 {
    case clientHello = 0x01
    case serverHello = 0x02
}

/// Secure handshake protocol for establishing encrypted sessions.
///
/// Implements X25519 Diffie-Hellman key agreement with the following flow:
/// 1. Client generates keypair, sends clientHello with public key
/// 2. Server generates keypair, sends serverHello with public key
/// 3. Both parties derive shared secret and session keys via HKDF
///
/// See HANDSHAKE.md for detailed protocol specification.
public struct BlazeSecureHandshake {
    /// Handshake role (client or server)
    public let role: BlazeHandshakeRole
    
    /// Local private key for key agreement
    private let localPrivateKey: Curve25519.KeyAgreement.PrivateKey
    
    /// Local public key (derived from private key)
    public var localPublicKey: Curve25519.KeyAgreement.PublicKey {
        return localPrivateKey.publicKey
    }
    
    /// Remote public key (set after receiving handshake message)
    private var remotePublicKey: Curve25519.KeyAgreement.PublicKey?
    
    /// Crypto configuration
    private let config: BlazeCryptoConfig
    
    /// Creates a new handshake instance.
    /// - Parameters:
    ///   - role: Handshake role (client or server)
    ///   - config: Crypto configuration (default: standard config)
    public init(role: BlazeHandshakeRole, config: BlazeCryptoConfig = .init()) {
        self.role = role
        self.localPrivateKey = Curve25519.KeyAgreement.PrivateKey()
        self.remotePublicKey = nil
        self.config = config
    }
    
    /// Returns the local public key as raw 32-byte data.
    /// - Returns: 32-byte X25519 public key
    public func localPublicKeyData() -> Data {
        return localPublicKey.rawRepresentation
    }
    
    /// Receives and validates a remote public key from a handshake message.
    /// - Parameter data: Raw handshake message data
    /// - Throws: `BlazeBinaryError.invalidHandshake` if message is malformed
    public mutating func receiveRemotePublicKey(_ data: Data) throws {
        let (_, remoteKeyData) = try parseHandshakeMessage(data)
        
        // Validate key length (X25519 public keys are 32 bytes)
        guard remoteKeyData.count == 32 else {
            throw BlazeBinaryError.invalidHandshake("Invalid public key length: expected 32, got \(remoteKeyData.count)")
        }
        
        // Create public key object
        do {
            self.remotePublicKey = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: remoteKeyData)
        } catch {
            throw BlazeBinaryError.invalidHandshake("Invalid public key format: \(error)")
        }
    }
    
    /// Derives session keys from the shared secret.
    /// - Returns: Session key material (encryption key, authentication key, nonce prefix)
    /// - Throws: `BlazeBinaryError.handshakeFailed` if remote public key is not set or key agreement fails
    public func deriveSessionKeys() throws -> BlazeSessionKeyMaterial {
        guard let remoteKey = remotePublicKey else {
            throw BlazeBinaryError.handshakeFailed("Remote public key not received")
        }
        
        do {
            // Perform key agreement
            let sharedSecret = try localPrivateKey.sharedSecretFromKeyAgreement(with: remoteKey)
            
            // Derive session keys via HKDF
            return try BlazeBinary.deriveSessionKeys(from: sharedSecret, config: config)
        } catch let error as BlazeBinaryError {
            throw error
        } catch {
            throw BlazeBinaryError.handshakeFailed("Key agreement failed: \(error)")
        }
    }
    
    // MARK: - Handshake Message Format
    
    /// Creates a clientHello message.
    /// - Returns: Handshake message data
    public func makeClientHello() -> Data {
        return makeHandshakeMessage(type: .clientHello, publicKey: localPublicKey.rawRepresentation)
    }
    
    /// Creates a serverHello message.
    /// - Returns: Handshake message data
    public func makeServerHello() -> Data {
        return makeHandshakeMessage(type: .serverHello, publicKey: localPublicKey.rawRepresentation)
    }
    
    /// Creates an outbound handshake message based on role.
    /// - Returns: Handshake message data (clientHello for client, serverHello for server)
    public func makeOutboundMessage() -> Data {
        switch role {
        case .client:
            return makeClientHello()
        case .server:
            return makeServerHello()
        }
    }
    
    /// Processes an inbound handshake message and derives session keys.
    /// - Parameter data: Inbound handshake message data
    /// - Returns: Derived session key material
    /// - Throws: `BlazeBinaryError.invalidHandshake` or `BlazeBinaryError.handshakeFailed`
    public mutating func processInboundMessage(_ data: Data) throws -> BlazeSessionKeyMaterial {
        // Parse and store remote public key
        try receiveRemotePublicKey(data)
        
        // Derive session keys
        return try deriveSessionKeys()
    }
    
    // MARK: - Private Helpers
    
    /// Creates a handshake message with the specified type and public key.
    /// 
    /// Message format:
    /// - 1 byte: handshakeVersion (0x01)
    /// - 1 byte: handshakeType (0x01 = clientHello, 0x02 = serverHello)
    /// - 2 bytes: flags (reserved, currently 0x0000)
    /// - 32 bytes: public key (X25519)
    ///
    /// Total: 36 bytes
    private func makeHandshakeMessage(type: HandshakeType, publicKey: Data) -> Data {
        var message = Data()
        message.append(0x01) // handshakeVersion = 0x01
        message.append(type.rawValue)
        message.append(contentsOf: [0x00, 0x00]) // flags = 0x0000
        message.append(publicKey)
        return message
    }
    
    /// Parses a handshake message and returns the type and remote public key.
    /// - Parameter data: Handshake message data
    /// - Returns: Tuple of (handshakeType, remoteKeyData)
    /// - Throws: `BlazeBinaryError.invalidHandshake` if message is malformed
    private func parseHandshakeMessage(_ data: Data) throws -> (type: HandshakeType, remoteKey: Data) {
        // Exact length: 1 (version) + 1 (type) + 2 (flags) + 32 (key) = 36 bytes
        guard data.count == 36 else {
            if data.count < 36 {
                throw BlazeBinaryError.invalidHandshake("Handshake message too short: expected 36 bytes, got \(data.count)")
            } else {
                throw BlazeBinaryError.invalidHandshake("Handshake message too long: expected 36 bytes, got \(data.count)")
            }
        }
        
        // Check version - use withUnsafeBytes for safety
        let version = data.withUnsafeBytes { bytes -> UInt8 in
            guard bytes.count >= 1 else {
                return 0xFF  // Invalid sentinel
            }
            return bytes[0]
        }
        guard version == 0x01 else {
            throw BlazeBinaryError.invalidHandshake("Unsupported handshake version: \(version) (expected 0x01)")
        }
        
        // Check type - use withUnsafeBytes for safety
        let typeByte = data.withUnsafeBytes { bytes -> UInt8 in
            guard bytes.count >= 2 else {
                return 0xFF  // Invalid sentinel
            }
            return bytes[1]
        }
        guard typeByte != 0xFF else {
            throw BlazeBinaryError.invalidHandshake("Invalid handshake message format")
        }
        guard let type = HandshakeType(rawValue: typeByte) else {
            throw BlazeBinaryError.invalidHandshake("Invalid handshake type: \(typeByte) (expected 0x01 or 0x02)")
        }
        
        // Skip flags (bytes 2-3, reserved for future use)
        // Extract public key (bytes 4-35, exactly 32 bytes) - use withUnsafeBytes for safety
        let remoteKey = data.withUnsafeBytes { bytes -> Data in
            guard bytes.count >= 36 else {
                return Data()  // Return empty on error
            }
            return Data(bytes[4..<36])
        }
        guard remoteKey.count == 32 else {
            throw BlazeBinaryError.invalidHandshake("Failed to extract remote key: expected 32 bytes, got \(remoteKey.count)")
        }
        
        return (type, remoteKey)
    }
}

