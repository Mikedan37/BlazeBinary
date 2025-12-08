//
// BlazeCrypto.swift
// BlazeBinary
//
// Copyright (c) 2025 Michael Danylchuk
// MIT License
//

import Foundation
import Crypto

/// Configuration for BlazeBinary secure session encryption.
public struct BlazeCryptoConfig {
    /// Supported cipher suites for secure sessions.
    public enum CipherSuite {
        /// X25519 key agreement + ChaCha20-Poly1305 AEAD + HKDF-SHA256 key derivation
        case x25519ChaChaPolyHKDF_SHA256
    }
    
    /// The cipher suite to use for this session.
    public let cipherSuite: CipherSuite
    
    /// HKDF info parameter (application-specific context).
    /// Default: "BlazeBinarySession" as UTF-8 bytes.
    public let hkdfInfo: Data
    
    /// Optional HKDF salt. If nil, a zero-length salt is used.
    public let hkdfSalt: Data?
    
    /// Creates a new crypto configuration.
    /// - Parameters:
    ///   - cipherSuite: The cipher suite to use (default: .x25519ChaChaPolyHKDF_SHA256)
    ///   - hkdfInfo: HKDF info parameter (default: "BlazeBinarySession")
    ///   - hkdfSalt: Optional HKDF salt (default: nil, uses zero-length salt)
    public init(
        cipherSuite: CipherSuite = .x25519ChaChaPolyHKDF_SHA256,
        hkdfInfo: Data = Data("BlazeBinarySession".utf8),
        hkdfSalt: Data? = nil
    ) {
        self.cipherSuite = cipherSuite
        self.hkdfInfo = hkdfInfo
        self.hkdfSalt = hkdfSalt
    }
}

/// Session key material derived from a Diffie-Hellman key agreement.
public struct BlazeSessionKeyMaterial {
    /// Symmetric key for ChaCha20-Poly1305 encryption/decryption (32 bytes).
    public let encryptionKey: SymmetricKey
    
    /// Symmetric key reserved for future authentication use (32 bytes).
    public let authenticationKey: SymmetricKey
    
    /// Random 4-byte prefix used for nonce construction.
    /// Combined with a counter to form 12-byte nonces for ChaChaPoly.
    public let noncePrefix: Data
    
    /// Creates session key material from derived keys and nonce prefix.
    /// - Parameters:
    ///   - encryptionKey: 32-byte encryption key
    ///   - authenticationKey: 32-byte authentication key
    ///   - noncePrefix: 4-byte nonce prefix
    internal init(encryptionKey: SymmetricKey, authenticationKey: SymmetricKey, noncePrefix: Data) {
        self.encryptionKey = encryptionKey
        self.authenticationKey = authenticationKey
        self.noncePrefix = noncePrefix
    }
}

// MARK: - HKDF Key Derivation

/// Derives session key material from a shared secret using HKDF-SHA256.
///
/// Key derivation process:
/// 1. PRK = HKDF-Extract(salt, sharedSecretBytes)
/// 2. OKM = HKDF-Expand(PRK, info, L = 64)
/// 3. encryptionKey = OKM[0..<32]
/// 4. authenticationKey = OKM[32..<64]
/// 5. noncePrefix = 4 random bytes
///
/// - Parameters:
///   - sharedSecret: The shared secret from X25519 key agreement
///   - config: Crypto configuration with HKDF parameters
/// - Returns: Derived session key material
/// - Throws: `BlazeBinaryError.encryptionFailed` if derivation fails
internal func deriveSessionKeys(
    from sharedSecret: SharedSecret,
    config: BlazeCryptoConfig
) throws -> BlazeSessionKeyMaterial {
    // Extract salt (use zero-length if nil)
    let salt = config.hkdfSalt ?? Data()
    
    // HKDF-SHA256 key derivation using Swift Crypto
    // Extract shared secret bytes
    let sharedSecretBytes = sharedSecret.withUnsafeBytes { Data($0) }
    let inputKeyMaterial = SymmetricKey(data: sharedSecretBytes)
    
    // HKDF-Expand: Derive 64 bytes total (32 for encryption, 32 for authentication)
    let okm = HKDF<SHA256>.deriveKey(
        inputKeyMaterial: inputKeyMaterial,
        salt: salt,
        info: config.hkdfInfo,
        outputByteCount: 64
    )
    
    // Extract bytes from SymmetricKey
    let okmData = okm.withUnsafeBytes { Data($0) }
    
    // Split OKM into encryption and authentication keys
    guard okmData.count == 64 else {
        throw BlazeBinaryError.encryptionFailed("HKDF output length mismatch: expected 64, got \(okmData.count)")
    }
    
    let encryptionKeyBytes = okmData.prefix(32)
    let authenticationKeyBytes = okmData.suffix(32)
    
    let encryptionKey = SymmetricKey(data: encryptionKeyBytes)
    let authenticationKey = SymmetricKey(data: authenticationKeyBytes)
    
    // Generate random 4-byte nonce prefix
    var noncePrefix = Data(count: 4)
    let result = noncePrefix.withUnsafeMutableBytes { bytes in
        SecRandomCopyBytes(kSecRandomDefault, 4, bytes.baseAddress!)
    }
    guard result == errSecSuccess else {
        throw BlazeBinaryError.encryptionFailed("Failed to generate nonce prefix: \(result)")
    }
    
    return BlazeSessionKeyMaterial(
        encryptionKey: encryptionKey,
        authenticationKey: authenticationKey,
        noncePrefix: noncePrefix
    )
}

