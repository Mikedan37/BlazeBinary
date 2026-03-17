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
///
/// Uses algorithms specified in IETF RFCs (Requests for Comments — the published
/// standards that define how internet protocols work):
///
/// - **RFC 7748**: X25519 key agreement (Curve25519 Diffie-Hellman)
/// - **RFC 5869**: HKDF (HMAC-based Key Derivation Function) — takes a shared
///   secret and stretches it into multiple independent keys using a two-step
///   extract-then-expand process.
/// - **RFC 8439**: ChaCha20-Poly1305 AEAD (Authenticated Encryption with
///   Associated Data) — encrypts and authenticates in a single pass.
///
/// **What is HKDF?**
/// When two parties do a Diffie-Hellman key exchange, they end up with a shared
/// secret — a blob of bytes that only they know. But you can't just use that blob
/// directly as an encryption key. HKDF is a standard recipe for turning that
/// shared secret into one or more strong, independent keys:
///   1. **Extract** — compress the shared secret into a fixed-size pseudorandom
///      key (PRK), mixed with an optional salt for domain separation.
///   2. **Expand** — stretch the PRK into as many output bytes as you need,
///      mixed with an "info" string that labels what each key is for.
///
/// This is defined in RFC 5869 (an "RFC" is a published internet standard — think
/// of it as the spec sheet that every implementation agrees to follow).
public struct BlazeCryptoConfig {
    /// Supported cipher suites for secure sessions.
    public enum CipherSuite {
        /// X25519 key agreement + ChaCha20-Poly1305 AEAD + HKDF-SHA256 key derivation
        case x25519ChaChaPolyHKDF_SHA256
    }

    /// The cipher suite to use for this session.
    public let cipherSuite: CipherSuite

    /// HKDF "info" parameter — application-specific context label.
    ///
    /// This string is mixed into the Expand step so that keys derived for
    /// different purposes (even from the same shared secret) are independent.
    /// Default: `"BlazeBinarySession"`.
    public let hkdfInfo: Data

    /// HKDF salt for domain separation.
    ///
    /// Per RFC 5869 §3.1, a non-secret salt "adds to the strength of HKDF,
    /// ensuring independence from the source key material." The default is a
    /// fixed application-specific string rather than an empty/zero salt, which
    /// gives better domain separation between BlazeBinary and any other protocol
    /// that might use the same shared secret.
    ///
    /// Pass `nil` to use the default. Pass `Data()` for the legacy zero-salt
    /// behavior (not recommended).
    public let hkdfSalt: Data?

    /// Default salt used when `hkdfSalt` is nil.
    /// A fixed, non-secret, application-specific string — better than zero-length
    /// per RFC 5869 §3.1 ("even a non-secret random value... is a significant
    /// improvement over an all-zero salt").
    internal static let defaultSalt = Data("BlazeBinary-HKDF-v1".utf8)

    /// Creates a new crypto configuration.
    /// - Parameters:
    ///   - cipherSuite: The cipher suite to use (default: .x25519ChaChaPolyHKDF_SHA256)
    ///   - hkdfInfo: HKDF info parameter (default: "BlazeBinarySession")
    ///   - hkdfSalt: HKDF salt (default: nil → uses "BlazeBinary-HKDF-v1")
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
///
/// Contains separate keys and nonce prefixes for each communication direction
/// (send vs receive), preventing key reuse across directions.
public struct BlazeSessionKeyMaterial {
    /// Symmetric key for encrypting outbound frames (32 bytes).
    public let sendKey: SymmetricKey

    /// Symmetric key for decrypting inbound frames (32 bytes).
    public let receiveKey: SymmetricKey

    /// Symmetric key for ChaCha20-Poly1305 encryption/decryption (32 bytes).
    /// - Note: Deprecated in favor of `sendKey`/`receiveKey`. Kept for backward compatibility.
    public var encryptionKey: SymmetricKey { sendKey }

    /// Symmetric key reserved for future use (32 bytes).
    ///
    /// **Not currently used.** Derived from HKDF alongside encryption keys to keep
    /// the key schedule stable if a future version adds key-confirmation or
    /// channel-binding. ChaCha20-Poly1305 already provides authentication via its
    /// AEAD tag, so no separate MAC key is needed for the current protocol.
    public let authenticationKey: SymmetricKey

    /// 4-byte prefix for constructing outbound nonces.
    /// Combined with a counter to form 12-byte nonces for ChaChaPoly.
    public let sendNoncePrefix: Data

    /// 4-byte prefix for validating inbound nonces.
    /// Used in AAD construction during decryption for prefix binding.
    public let receiveNoncePrefix: Data

    /// Nonce prefix for outbound frames.
    /// - Note: Returns `sendNoncePrefix` for backward compatibility.
    public var noncePrefix: Data { sendNoncePrefix }

    /// Creates session key material with separate send/receive keys and nonce prefixes.
    /// - Parameters:
    ///   - sendKey: 32-byte key for encrypting outbound frames
    ///   - receiveKey: 32-byte key for decrypting inbound frames
    ///   - authenticationKey: 32-byte authentication key (reserved)
    ///   - sendNoncePrefix: 4-byte nonce prefix for outbound frames
    ///   - receiveNoncePrefix: 4-byte nonce prefix for inbound frames
    internal init(sendKey: SymmetricKey, receiveKey: SymmetricKey, authenticationKey: SymmetricKey, sendNoncePrefix: Data, receiveNoncePrefix: Data) {
        self.sendKey = sendKey
        self.receiveKey = receiveKey
        self.authenticationKey = authenticationKey
        self.sendNoncePrefix = sendNoncePrefix
        self.receiveNoncePrefix = receiveNoncePrefix
    }

    /// Creates session key material from a single encryption key and nonce prefix.
    /// Both send and receive use the same key and prefix (legacy behavior).
    /// - Parameters:
    ///   - encryptionKey: 32-byte encryption key (used for both send and receive)
    ///   - authenticationKey: 32-byte authentication key
    ///   - noncePrefix: 4-byte nonce prefix (used for both send and receive)
    internal init(encryptionKey: SymmetricKey, authenticationKey: SymmetricKey, noncePrefix: Data) {
        self.sendKey = encryptionKey
        self.receiveKey = encryptionKey
        self.authenticationKey = authenticationKey
        self.sendNoncePrefix = noncePrefix
        self.receiveNoncePrefix = noncePrefix
    }
}

// MARK: - HKDF Key Derivation

/// Derives session key material from a shared secret using HKDF-SHA256.
///
/// Key derivation process (per direction):
/// 1. clientOKM = HKDF(sharedSecret, salt, info="BlazeBinarySession-client", L=36)
/// 2. serverOKM = HKDF(sharedSecret, salt, info="BlazeBinarySession-server", L=36)
/// 3. Each OKM: encryptionKey = OKM[0..<32], noncePrefix = OKM[32..<36]
/// 4. authOKM = HKDF(sharedSecret, salt, info=config.hkdfInfo, L=32)
///
/// The `role` parameter determines which derived key is used for send vs receive:
/// - Client: sendKey = clientKey, receiveKey = serverKey
/// - Server: sendKey = serverKey, receiveKey = clientKey
///
/// - Parameters:
///   - sharedSecret: The shared secret from X25519 key agreement
///   - config: Crypto configuration with HKDF parameters
///   - role: The local role (client or server) to assign send/receive keys
/// - Returns: Derived session key material
/// - Throws: `BlazeBinaryError.encryptionFailed` if derivation fails
internal func deriveSessionKeys(
    from sharedSecret: SharedSecret,
    config: BlazeCryptoConfig,
    role: BlazeHandshakeRole
) throws -> BlazeSessionKeyMaterial {
    // Use configured salt, or the application-specific default (not zero-length).
    // Per RFC 5869 §3.1, even a non-secret fixed salt is better than no salt.
    let salt = config.hkdfSalt ?? BlazeCryptoConfig.defaultSalt

    // HKDF-SHA256 key derivation using Swift Crypto.
    //
    // SECURITY NOTE on key material lifetime:
    // Swift does not guarantee that Data/Array contents are zeroed on deallocation.
    // The intermediate buffers below (sharedSecretBytes, okmData) may persist in
    // memory after this function returns. Apple's SymmetricKey is opaque and may
    // or may not zero its backing storage. This is a known limitation of Swift's
    // memory model — there is no reliable way to force zeroing without unsafe
    // tricks that the compiler can optimize away. For defense-in-depth, we
    // explicitly overwrite intermediate Data buffers before they go out of scope.

    // Extract shared secret bytes
    var sharedSecretBytes = sharedSecret.withUnsafeBytes { Data($0) }
    let inputKeyMaterial = SymmetricKey(data: sharedSecretBytes)
    // Best-effort zeroing of intermediate shared secret copy
    sharedSecretBytes.resetBytes(in: 0..<sharedSecretBytes.count)

    // Derive client-direction key material (32-byte key + 4-byte nonce prefix = 36 bytes)
    let clientInfo = Data("BlazeBinarySession-client".utf8)
    let clientOKM = HKDF<SHA256>.deriveKey(
        inputKeyMaterial: inputKeyMaterial,
        salt: salt,
        info: clientInfo,
        outputByteCount: 36
    )
    var clientOKMData = clientOKM.withUnsafeBytes { Data($0) }
    guard clientOKMData.count == 36 else {
        clientOKMData.resetBytes(in: 0..<clientOKMData.count)
        throw BlazeBinaryError.encryptionFailed("HKDF client output length mismatch: expected 36, got \(clientOKMData.count)")
    }
    let clientKey = SymmetricKey(data: clientOKMData.prefix(32))
    let clientNoncePrefix = Data(clientOKMData.suffix(4))
    clientOKMData.resetBytes(in: 0..<clientOKMData.count)

    // Derive server-direction key material (32-byte key + 4-byte nonce prefix = 36 bytes)
    let serverInfo = Data("BlazeBinarySession-server".utf8)
    let serverOKM = HKDF<SHA256>.deriveKey(
        inputKeyMaterial: inputKeyMaterial,
        salt: salt,
        info: serverInfo,
        outputByteCount: 36
    )
    var serverOKMData = serverOKM.withUnsafeBytes { Data($0) }
    guard serverOKMData.count == 36 else {
        serverOKMData.resetBytes(in: 0..<serverOKMData.count)
        throw BlazeBinaryError.encryptionFailed("HKDF server output length mismatch: expected 36, got \(serverOKMData.count)")
    }
    let serverKey = SymmetricKey(data: serverOKMData.prefix(32))
    let serverNoncePrefix = Data(serverOKMData.suffix(4))
    serverOKMData.resetBytes(in: 0..<serverOKMData.count)

    // Derive authentication key (reserved for future use)
    let authOKM = HKDF<SHA256>.deriveKey(
        inputKeyMaterial: inputKeyMaterial,
        salt: salt,
        info: config.hkdfInfo,
        outputByteCount: 32
    )
    var authOKMData = authOKM.withUnsafeBytes { Data($0) }
    let authenticationKey = SymmetricKey(data: authOKMData)
    authOKMData.resetBytes(in: 0..<authOKMData.count)

    // Assign send/receive based on role
    switch role {
    case .client:
        return BlazeSessionKeyMaterial(
            sendKey: clientKey,
            receiveKey: serverKey,
            authenticationKey: authenticationKey,
            sendNoncePrefix: clientNoncePrefix,
            receiveNoncePrefix: serverNoncePrefix
        )
    case .server:
        return BlazeSessionKeyMaterial(
            sendKey: serverKey,
            receiveKey: clientKey,
            authenticationKey: authenticationKey,
            sendNoncePrefix: serverNoncePrefix,
            receiveNoncePrefix: clientNoncePrefix
        )
    }
}

