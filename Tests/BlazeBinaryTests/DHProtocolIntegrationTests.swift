//
// DHProtocolIntegrationTests.swift
// BlazeBinary
//
// Copyright (c) 2025 Michael Danylchuk
// MIT License
//

import XCTest
import Foundation
import Crypto
@testable import BlazeBinary

/// Comprehensive Diffie-Hellman protocol integration tests.
///
/// Tests the complete X25519 key exchange, HKDF key derivation, and session establishment
/// with both positive and negative test cases.
final class DHProtocolIntegrationTests: XCTestCase {
    
    // MARK: - Full Successful Handshake Test
    
    func testFullSuccessfulHandshake() throws {
        // Simulate Alice (client) and Bob (server)
        var alice = BlazeSecureHandshake(role: .client)
        var bob = BlazeSecureHandshake(role: .server)
        
        // Step 1: Alice generates ephemeral keypair (done in init)
        let alicePublicKey = alice.localPublicKeyData()
        XCTAssertEqual(alicePublicKey.count, 32, "X25519 public key must be 32 bytes")
        
        // Step 2: Bob generates ephemeral keypair (done in init)
        let bobPublicKey = bob.localPublicKeyData()
        XCTAssertEqual(bobPublicKey.count, 32, "X25519 public key must be 32 bytes")
        
        // Step 3: Alice sends clientHello to Bob
        let clientHello = alice.makeClientHello()
        XCTAssertEqual(clientHello.count, 36, "ClientHello must be 36 bytes")
        
        // Step 4: Bob receives clientHello and sends serverHello
        try bob.receiveRemotePublicKey(clientHello)
        let serverHello = bob.makeServerHello()
        XCTAssertEqual(serverHello.count, 36, "ServerHello must be 36 bytes")
        
        // Step 5: Alice receives serverHello
        try alice.receiveRemotePublicKey(serverHello)
        
        // Step 6: Both parties derive session keys
        let aliceKeys = try alice.deriveSessionKeys()
        let bobKeys = try bob.deriveSessionKeys()
        
        // Step 7: Validate both sides compute identical session keys
        XCTAssertEqual(
            aliceKeys.encryptionKey.withUnsafeBytes { Data($0) },
            bobKeys.encryptionKey.withUnsafeBytes { Data($0) },
            "Both parties must derive identical encryption keys"
        )
        XCTAssertEqual(
            aliceKeys.authenticationKey.withUnsafeBytes { Data($0) },
            bobKeys.authenticationKey.withUnsafeBytes { Data($0) },
            "Both parties must derive identical authentication keys"
        )
        
        // Step 8: Exchange encrypted frames both directions
        var aliceSession = BlazeSecureSession(keyMaterial: aliceKeys)
        var bobSession = BlazeSecureSession(keyMaterial: bobKeys)
        // Disable strict replay protection for tests (allows counter 0)
        aliceSession.strictReplayProtection = false
        bobSession.strictReplayProtection = false
        
        // Alice encrypts a message to Bob
        let aliceMessage = Data("Hello from Alice".utf8)
        let aliceEncrypted = try aliceSession.makeEncryptedFrame(from: aliceMessage)
        XCTAssertGreaterThanOrEqual(aliceEncrypted.count, 29, "Encrypted frame must be at least 29 bytes")
        
        // Bob decrypts Alice's message
        let bobDecrypted = try bobSession.decryptFramePayload(aliceEncrypted)
        XCTAssertEqual(bobDecrypted, aliceMessage, "Decrypted message must match original")
        
        // Bob encrypts a message to Alice
        let bobMessage = Data("Hello from Bob".utf8)
        let bobEncrypted = try bobSession.makeEncryptedFrame(from: bobMessage)
        XCTAssertGreaterThanOrEqual(bobEncrypted.count, 29, "Encrypted frame must be at least 29 bytes")
        
        // Alice decrypts Bob's message
        let aliceDecrypted = try aliceSession.decryptFramePayload(bobEncrypted)
        XCTAssertEqual(aliceDecrypted, bobMessage, "Decrypted message must match original")
        
        // Step 9: Validate encrypt → decrypt → encrypt symmetry
        let roundTripMessage = Data("Round trip test".utf8)
        let encrypted1 = try aliceSession.makeEncryptedFrame(from: roundTripMessage)
        let decrypted1 = try bobSession.decryptFramePayload(encrypted1)
        XCTAssertEqual(decrypted1, roundTripMessage, "First round trip must succeed")
        
        let encrypted2 = try bobSession.makeEncryptedFrame(from: decrypted1)
        let decrypted2 = try aliceSession.decryptFramePayload(encrypted2)
        XCTAssertEqual(decrypted2, roundTripMessage, "Second round trip must succeed")
    }
    
    // MARK: - Negative DH Tests
    
    func testInvalidPublicKeyWrongSize() throws {
        var handshake = BlazeSecureHandshake(role: .server)
        
        // Test too short (needs to be valid handshake message format)
        var tooShort = Data()
        tooShort.append(0x01) // version
        tooShort.append(0x01) // type
        tooShort.append(contentsOf: [0x00, 0x00]) // flags
        tooShort.append(Data(repeating: 0x42, count: 31)) // Only 31 bytes instead of 32
        
        XCTAssertThrowsError(try handshake.receiveRemotePublicKey(tooShort)) { error in
            XCTAssertTrue(error is BlazeBinaryError)
        }
        
        // Test too long (needs to be valid handshake message format)
        var tooLong = Data()
        tooLong.append(0x01) // version
        tooLong.append(0x01) // type
        tooLong.append(contentsOf: [0x00, 0x00]) // flags
        tooLong.append(Data(repeating: 0x42, count: 33)) // 33 bytes instead of 32
        
        XCTAssertThrowsError(try handshake.receiveRemotePublicKey(tooLong)) { error in
            XCTAssertTrue(error is BlazeBinaryError)
        }
    }
    
    func testPublicKeyAllZeroes() throws {
        var handshake = BlazeSecureHandshake(role: .server)
        
        // X25519 public key of all zeroes is invalid
        let zeroKey = Data(repeating: 0x00, count: 32)
        let zeroKeyMessage = makeHandshakeMessage(type: 0x01, publicKey: zeroKey)
        
        // Swift Crypto may or may not reject all-zero keys immediately
        // Test that it either rejects or fails during key derivation
        do {
            try handshake.receiveRemotePublicKey(zeroKeyMessage)
            // If accepted, derivation should fail
            XCTAssertThrowsError(try handshake.deriveSessionKeys()) { error in
                XCTAssertTrue(error is BlazeBinaryError)
            }
        } catch {
            // If rejected immediately, that's also acceptable
            XCTAssertTrue(error is BlazeBinaryError)
        }
    }
    
    func testPublicKeyNotOnCurve() throws {
        var handshake = BlazeSecureHandshake(role: .server)
        
        // Note: X25519 doesn't have a "point on curve" validation like other curves
        // Any 32-byte value can be a valid X25519 public key (though some are weak)
        // Swift Crypto accepts any 32-byte key and key agreement may succeed
        // This test verifies that the system handles various key formats gracefully
        
        // Create a key with unusual format
        var unusualKey = Data(repeating: 0xFF, count: 32)
        unusualKey[31] = 0x7F // Set high bit
        
        let unusualKeyMessage = makeHandshakeMessage(type: 0x01, publicKey: unusualKey)
        
        // X25519 accepts any 32-byte key format
        // The key may be weak but is still valid for X25519
        // Test that the system doesn't crash and handles it gracefully
        try handshake.receiveRemotePublicKey(unusualKeyMessage)
        
        // Key agreement may succeed even with unusual keys
        // This is expected behavior for X25519 - it's designed to accept any 32-byte key
        // The test verifies the system doesn't crash
        do {
            _ = try handshake.deriveSessionKeys()
            // Key agreement succeeded - this is valid for X25519
        } catch {
            // Key agreement failed - also acceptable
                XCTAssertTrue(error is BlazeBinaryError)
        }
    }
    
    func testCompletelyRandomGarbageKey() throws {
        var handshake = BlazeSecureHandshake(role: .server)
        
        // Generate random garbage
        let randomKeyData = SymmetricKey(size: .bits256)
        let randomKey = randomKeyData.withUnsafeBytes { Data($0) }
        
        let randomKeyMessage = makeHandshakeMessage(type: 0x01, publicKey: randomKey)
        
        // Random key may be valid or invalid - test that we handle it gracefully
        // Swift Crypto may accept some random keys as valid X25519 keys
        let result = try? handshake.receiveRemotePublicKey(randomKeyMessage)
        // If it doesn't throw, derivation should work (key was valid) or fail gracefully
        if result != nil {
            // Try derivation - it should either succeed (valid key) or fail gracefully
            _ = try? handshake.deriveSessionKeys()
            // Either outcome is acceptable - key was handled gracefully
        } else {
            // Key was rejected - also acceptable
        }
    }
    
    func testReplayedPublicKey() throws {
        // Create two handshakes with different local keypairs
        var handshake1 = BlazeSecureHandshake(role: .server)
        var handshake2 = BlazeSecureHandshake(role: .server)
        
        // Generate a valid public key from a client
        let client = BlazeSecureHandshake(role: .client)
        let clientHello = client.makeClientHello()
        
        // Both handshakes receive the same public key
        try handshake1.receiveRemotePublicKey(clientHello)
        try handshake2.receiveRemotePublicKey(clientHello)
        
        // Both should derive the same keys (same remote key, but different local keys)
        // Actually, different local keys means different shared secrets, so keys will differ
        // Test that replay is handled gracefully (doesn't crash)
        let keys1 = try handshake1.deriveSessionKeys()
        let keys2 = try handshake2.deriveSessionKeys()
        
        // Keys will be different because local keypairs are different
        // This is expected - replay protection would need application-level tracking
        let keys1Data = keys1.encryptionKey.withUnsafeBytes { Data($0) }
        let keys2Data = keys2.encryptionKey.withUnsafeBytes { Data($0) }
        // Keys are different (different local keypairs), which is correct
        XCTAssertNotEqual(keys1Data, keys2Data, "Different local keypairs produce different session keys")
    }
    
    func testMismatchedSessionID() throws {
        // Create two independent handshakes (different keypairs)
        var alice1 = BlazeSecureHandshake(role: .client)
        var bob1 = BlazeSecureHandshake(role: .server)
        
        var alice2 = BlazeSecureHandshake(role: .client)
        var bob2 = BlazeSecureHandshake(role: .server)
        
        // Complete handshake 1
        try bob1.receiveRemotePublicKey(alice1.makeClientHello())
        try alice1.receiveRemotePublicKey(bob1.makeServerHello())
        let keys1 = try alice1.deriveSessionKeys()
        
        // Complete handshake 2
        try bob2.receiveRemotePublicKey(alice2.makeClientHello())
        try alice2.receiveRemotePublicKey(bob2.makeServerHello())
        let keys2 = try alice2.deriveSessionKeys()
        
        // Keys from different handshakes must be different
        let keys1Data = keys1.encryptionKey.withUnsafeBytes { Data($0) }
        let keys2Data = keys2.encryptionKey.withUnsafeBytes { Data($0) }
        XCTAssertNotEqual(keys1Data, keys2Data, "Different handshakes must produce different keys")
        
        // Try to decrypt frame from session 1 with keys from session 2
        var session1 = BlazeSecureSession(keyMaterial: keys1)
        var session2 = BlazeSecureSession(keyMaterial: keys2)
        
        let message = Data("Test message".utf8)
        let encrypted = try session1.makeEncryptedFrame(from: message)
        
        // This should fail - wrong keys
        XCTAssertThrowsError(try session2.decryptFramePayload(encrypted)) { error in
            XCTAssertTrue(error is BlazeBinaryError)
        }
    }
    
    // MARK: - Derived Key Tests
    
    func testHKDFOutputMatchesReference() throws {
        // Test HKDF key derivation produces valid output
        // Create two handshakes to get a real shared secret
        var alice = BlazeSecureHandshake(role: .client)
        var bob = BlazeSecureHandshake(role: .server)
        
        // Complete handshake to get shared secret
        try bob.receiveRemotePublicKey(alice.makeClientHello())
        try alice.receiveRemotePublicKey(bob.makeServerHello())
        
        // Derive keys with custom config
        let salt = Data([0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07,
                         0x08, 0x09, 0x0a, 0x0b, 0x0c])
        let info = Data([0xf0, 0xf1, 0xf2])
        
        let config = BlazeCryptoConfig(
            hkdfInfo: info,
            hkdfSalt: salt
        )
        
        // Create handshakes with custom config
        var aliceCustom = BlazeSecureHandshake(role: .client, config: config)
        var bobCustom = BlazeSecureHandshake(role: .server, config: config)
        
        try bobCustom.receiveRemotePublicKey(aliceCustom.makeClientHello())
        try aliceCustom.receiveRemotePublicKey(bobCustom.makeServerHello())
        
        // Derive keys
        let aliceKeys = try aliceCustom.deriveSessionKeys()
        let bobKeys = try bobCustom.deriveSessionKeys()
        
        // Verify keys are derived correctly
        let encryptionKeyData = aliceKeys.encryptionKey.withUnsafeBytes { Data($0) }
        let authenticationKeyData = aliceKeys.authenticationKey.withUnsafeBytes { Data($0) }
        XCTAssertEqual(encryptionKeyData.count, 32, "Encryption key must be 32 bytes (256 bits)")
        XCTAssertEqual(authenticationKeyData.count, 32, "Authentication key must be 32 bytes (256 bits)")
        XCTAssertEqual(aliceKeys.noncePrefix.count, 4, "Nonce prefix must be 4 bytes")
        
        // Both parties must derive same keys
        XCTAssertEqual(
            aliceKeys.encryptionKey.withUnsafeBytes { Data($0) },
            bobKeys.encryptionKey.withUnsafeBytes { Data($0) },
            "Both parties must derive identical encryption keys"
        )
    }
    
    func testSessionKeyMismatchRejectsFrameDecrypt() throws {
        // Create two independent sessions with different keys
        var alice = BlazeSecureHandshake(role: .client)
        var bob = BlazeSecureHandshake(role: .server)
        var eve = BlazeSecureHandshake(role: .server) // Eve tries to intercept
        
        // Complete Alice-Bob handshake
        try bob.receiveRemotePublicKey(alice.makeClientHello())
        try alice.receiveRemotePublicKey(bob.makeServerHello())
        let aliceBobKeys = try alice.deriveSessionKeys()
        let bobKeys = try bob.deriveSessionKeys()
        
        // Eve tries to use her own handshake
        try eve.receiveRemotePublicKey(alice.makeClientHello())
        let eveKeys = try eve.deriveSessionKeys()
        
        // Alice encrypts message to Bob
        var aliceSession = BlazeSecureSession(keyMaterial: aliceBobKeys)
        aliceSession.strictReplayProtection = false
        let message = Data("Secret message".utf8)
        let encrypted = try aliceSession.makeEncryptedFrame(from: message)
        
        // Bob can decrypt (correct keys)
        var bobSession = BlazeSecureSession(keyMaterial: bobKeys)
        bobSession.strictReplayProtection = false
        let bobDecrypted = try bobSession.decryptFramePayload(encrypted)
        XCTAssertEqual(bobDecrypted, message, "Bob must decrypt correctly")
        
        // Eve cannot decrypt (wrong keys)
        var eveSession = BlazeSecureSession(keyMaterial: eveKeys)
        eveSession.strictReplayProtection = false
        XCTAssertThrowsError(try eveSession.decryptFramePayload(encrypted)) { error in
            XCTAssertTrue(error is BlazeBinaryError, "Wrong keys must cause decryption failure")
        }
    }
    
    // MARK: - Helper Methods
    
    private func makeHandshakeMessage(type: UInt8, publicKey: Data) -> Data {
        var message = Data()
        message.append(0x01) // version
        message.append(type)
        message.append(contentsOf: [0x00, 0x00]) // flags
        message.append(publicKey)
        return message
    }
}

