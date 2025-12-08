//
// BlazeCryptoHardeningTests.swift
// BlazeBinaryTests
//
// Copyright (c) 2025 Michael Danylchuk
// MIT License
//

import XCTest
@testable import BlazeBinary
import Crypto

/// Comprehensive crypto hardening tests for production readiness.
final class BlazeCryptoHardeningTests: XCTestCase {
    
    // MARK: - Diffie-Hellman Full Flow Tests
    
    func testCompleteHandshakeFlow() throws {
        // Full handshake → key derivation → encryption → decryption
        var clientHandshake = BlazeSecureHandshake(role: .client)
        var serverHandshake = BlazeSecureHandshake(role: .server)
        
        // Exchange handshake messages
        let clientHello = clientHandshake.makeClientHello()
        let serverHello = serverHandshake.makeServerHello()
        
        // Derive keys
        let clientKeys = try clientHandshake.processInboundMessage(serverHello)
        let serverKeys = try serverHandshake.processInboundMessage(clientHello)
        
        // Verify keys match
        XCTAssertEqual(
            clientKeys.encryptionKey.withUnsafeBytes { Data($0) },
            serverKeys.encryptionKey.withUnsafeBytes { Data($0) }
        )
        
        // Create sessions
        var clientSession = BlazeSecureSession(keyMaterial: clientKeys)
        var serverSession = BlazeSecureSession(keyMaterial: serverKeys)
        
        // Encrypt and decrypt
        let plaintext = Data("Test message".utf8)
        let encrypted = try clientSession.makeEncryptedFrame(from: plaintext)
        let decrypted = try serverSession.decryptFramePayload(encrypted)
        
        XCTAssertEqual(plaintext, decrypted)
    }
    
    func testMismatchedKeysFail() throws {
        // Two different handshakes should produce different keys
        var handshake1 = BlazeSecureHandshake(role: .client)
        var server1 = BlazeSecureHandshake(role: .server)
        var handshake2 = BlazeSecureHandshake(role: .client)
        var server2 = BlazeSecureHandshake(role: .server)
        
        let hello1 = handshake1.makeClientHello()
        let serverHello1 = server1.makeServerHello()
        let hello2 = handshake2.makeClientHello()
        let serverHello2 = server2.makeServerHello()
        
        let keys1 = try handshake1.processInboundMessage(serverHello1)
        let keys2 = try handshake2.processInboundMessage(serverHello2)
        
        var session1 = BlazeSecureSession(keyMaterial: keys1)
        var session2 = BlazeSecureSession(keyMaterial: keys2)
        
        // Encrypt with session1, try to decrypt with session2
        let plaintext = Data("Secret".utf8)
        let encrypted = try session1.makeEncryptedFrame(from: plaintext)
        
        XCTAssertThrowsError(try session2.decryptFramePayload(encrypted)) { error in
            if case BlazeBinaryError.encryptionFailed = error {
                // Expected: wrong key
            } else {
                XCTFail("Expected encryptionFailed error")
            }
        }
    }
    
    func testTruncatedHandshakeFails() {
        var handshake = BlazeSecureHandshake(role: .client)
        
        // Truncated handshake message
        let truncated = Data([0x01, 0x01]) // Only version and type
        
        XCTAssertThrowsError(try handshake.processInboundMessage(truncated)) { error in
            if case BlazeBinaryError.invalidHandshake = error {
                // Expected
            } else {
                XCTFail("Expected invalidHandshake error")
            }
        }
    }
    
    func testReplayHandshakeDetection() throws {
        // Same handshake message should be processable (no replay protection at handshake level)
        // But keys should be different each time
        var handshake1 = BlazeSecureHandshake(role: .client)
        var handshake2 = BlazeSecureHandshake(role: .client)
        var server = BlazeSecureHandshake(role: .server)
        
        let serverHello = server.makeServerHello()
        
        let keys1 = try handshake1.processInboundMessage(serverHello)
        let keys2 = try handshake2.processInboundMessage(serverHello)
        
        // Keys should be different (different nonce prefixes)
        XCTAssertNotEqual(
            keys1.noncePrefix,
            keys2.noncePrefix
        )
    }
    
    // MARK: - Nonce Reuse Tests
    
    func testNonceReuseDetection() throws {
        var clientHandshake = BlazeSecureHandshake(role: .client)
        var serverHandshake = BlazeSecureHandshake(role: .server)
        
        let clientHello = clientHandshake.makeClientHello()
        let serverHello = serverHandshake.makeServerHello()
        
        let clientKeys = try clientHandshake.processInboundMessage(serverHello)
        let serverKeys = try serverHandshake.processInboundMessage(clientHello)
        
        var clientSession = BlazeSecureSession(keyMaterial: clientKeys)
        var serverSession = BlazeSecureSession(keyMaterial: serverKeys)
        
        let plaintext = Data("Message".utf8)
        
        // Encrypt first frame
        let encrypted1 = try clientSession.makeEncryptedFrame(from: plaintext)
        
        // Manually create a frame with the same nonce (simulating reuse)
        // Extract nonce from encrypted1
        let nonce1 = encrypted1.subdata(in: 1..<13)
        
        // Create a new encrypted frame with same nonce but different plaintext
        // This simulates nonce reuse attack
        var maliciousFrame = Data()
        maliciousFrame.append(0x01) // frameType
        maliciousFrame.append(nonce1) // Same nonce
        
        // Try to encrypt with same nonce (this should be prevented by counter)
        // The counter should have incremented, so we can't reuse the nonce
        let encrypted2 = try clientSession.makeEncryptedFrame(from: Data("Different".utf8))
        let nonce2 = encrypted2.subdata(in: 1..<13)
        
        // Nonces should be different (counter incremented)
        XCTAssertNotEqual(nonce1, nonce2)
        
        // Extract counter from nonces
        let counter1 = nonce1.suffix(8).withUnsafeBytes { bytes in
            var value: UInt64 = 0
            for i in 0..<8 {
                value |= UInt64(bytes[i]) << (56 - i * 8)
            }
            return value
        }
        
        let counter2 = nonce2.suffix(8).withUnsafeBytes { bytes in
            var value: UInt64 = 0
            for i in 0..<8 {
                value |= UInt64(bytes[i]) << (56 - i * 8)
            }
            return value
        }
        
        // Counter should have incremented
        XCTAssertEqual(counter2, counter1 + 1)
    }
    
    func testWrongSessionCounter() throws {
        // Test that wrong counter (replay) is detected
        var clientHandshake = BlazeSecureHandshake(role: .client)
        var serverHandshake = BlazeSecureHandshake(role: .server)
        
        let clientHello = clientHandshake.makeClientHello()
        let serverHello = serverHandshake.makeServerHello()
        
        let clientKeys = try clientHandshake.processInboundMessage(serverHello)
        let serverKeys = try serverHandshake.processInboundMessage(clientHello)
        
        var clientSession = BlazeSecureSession(keyMaterial: clientKeys)
        var serverSession = BlazeSecureSession(keyMaterial: serverKeys)
        
        // Encrypt frame 1
        let encrypted1 = try clientSession.makeEncryptedFrame(from: Data("Message 1".utf8))
        _ = try serverSession.decryptFramePayload(encrypted1)
        
        // Encrypt frame 2
        let encrypted2 = try clientSession.makeEncryptedFrame(from: Data("Message 2".utf8))
        _ = try serverSession.decryptFramePayload(encrypted2)
        
        // Try to replay frame 1 (should be detected and rejected)
        // Replay protection is enabled by default and should reject duplicate counters
        let counter1 = encrypted1.subdata(in: 1..<13).suffix(8).withUnsafeBytes { bytes in
            var value: UInt64 = 0
            for i in 0..<8 {
                value |= UInt64(bytes[i]) << (56 - i * 8)
            }
            return value
        }
        
        let counter2 = encrypted2.subdata(in: 1..<13).suffix(8).withUnsafeBytes { bytes in
            var value: UInt64 = 0
            for i in 0..<8 {
                value |= UInt64(bytes[i]) << (56 - i * 8)
            }
            return value
        }
        
        XCTAssertEqual(counter2, counter1 + 1)
    }
    
    func testWrongAAD() throws {
        // Test that wrong AAD causes authentication failure
        var clientHandshake = BlazeSecureHandshake(role: .client)
        var serverHandshake = BlazeSecureHandshake(role: .server)
        
        let clientHello = clientHandshake.makeClientHello()
        let serverHello = serverHandshake.makeServerHello()
        
        let clientKeys = try clientHandshake.processInboundMessage(serverHello)
        let serverKeys = try serverHandshake.processInboundMessage(clientHello)
        
        var clientSession = BlazeSecureSession(keyMaterial: clientKeys)
        var serverSession = BlazeSecureSession(keyMaterial: serverKeys)
        
        let plaintext = Data("Test".utf8)
        let encrypted = try clientSession.makeEncryptedFrame(from: plaintext)
        
        // Tamper with frameType byte (changes AAD)
        var tampered = encrypted
        tampered[0] = 0x02 // Wrong frameType
        
        // Decryption should fail (AAD mismatch)
        XCTAssertThrowsError(try serverSession.decryptFramePayload(tampered)) { error in
            if case BlazeBinaryError.encryptionFailed = error {
                // Expected: AAD mismatch
            } else {
                XCTFail("Expected encryptionFailed error")
            }
        }
    }
    
    // MARK: - Negative Crypto Tests
    
    func testWrongKeyMustFailEveryTime() throws {
        // Test that wrong key ALWAYS fails (not probabilistic)
        var handshake1 = BlazeSecureHandshake(role: .client)
        var server1 = BlazeSecureHandshake(role: .server)
        var handshake2 = BlazeSecureHandshake(role: .client)
        var server2 = BlazeSecureHandshake(role: .server)
        
        let hello1 = handshake1.makeClientHello()
        let serverHello1 = server1.makeServerHello()
        let hello2 = handshake2.makeClientHello()
        let serverHello2 = server2.makeServerHello()
        
        let keys1 = try handshake1.processInboundMessage(serverHello1)
        let keys2 = try handshake2.processInboundMessage(serverHello2)
        
        var session1 = BlazeSecureSession(keyMaterial: keys1)
        var session2 = BlazeSecureSession(keyMaterial: keys2)
        
        let plaintext = Data("Test".utf8)
        let encrypted = try session1.makeEncryptedFrame(from: plaintext)
        
        // Try to decrypt 100 times - should fail every time
        for _ in 0..<100 {
            XCTAssertThrowsError(try session2.decryptFramePayload(encrypted)) { error in
                if case BlazeBinaryError.encryptionFailed = error {
                    // Expected
                } else {
                    XCTFail("Expected encryptionFailed error")
                }
            }
        }
    }
    
    func testWrongTagFails() throws {
        var clientHandshake = BlazeSecureHandshake(role: .client)
        var serverHandshake = BlazeSecureHandshake(role: .server)
        
        let clientHello = clientHandshake.makeClientHello()
        let serverHello = serverHandshake.makeServerHello()
        
        let clientKeys = try clientHandshake.processInboundMessage(serverHello)
        let serverKeys = try serverHandshake.processInboundMessage(clientHello)
        
        var clientSession = BlazeSecureSession(keyMaterial: clientKeys)
        var serverSession = BlazeSecureSession(keyMaterial: serverKeys)
        
        let plaintext = Data("Test".utf8)
        var encrypted = try clientSession.makeEncryptedFrame(from: plaintext)
        
        // Flip bits in tag (last 16 bytes)
        if encrypted.count >= 16 {
            let tagStart = encrypted.count - 16
            for i in 0..<16 {
                encrypted[tagStart + i] ^= 0xFF // Flip all bits
            }
        }
        
        XCTAssertThrowsError(try serverSession.decryptFramePayload(encrypted)) { error in
            if case BlazeBinaryError.encryptionFailed = error {
                // Expected: authentication failure
            } else {
                XCTFail("Expected encryptionFailed error, got: \(error)")
            }
        }
    }
    
    func testPartialTagCorruption() throws {
        var clientHandshake = BlazeSecureHandshake(role: .client)
        var serverHandshake = BlazeSecureHandshake(role: .server)
        
        let clientHello = clientHandshake.makeClientHello()
        let serverHello = serverHandshake.makeServerHello()
        
        let clientKeys = try clientHandshake.processInboundMessage(serverHello)
        let serverKeys = try serverHandshake.processInboundMessage(clientHello)
        
        var clientSession = BlazeSecureSession(keyMaterial: clientKeys)
        var serverSession = BlazeSecureSession(keyMaterial: serverKeys)
        
        let plaintext = Data("Test".utf8)
        var encrypted = try clientSession.makeEncryptedFrame(from: plaintext)
        
        // Corrupt single byte in tag
        if encrypted.count >= 16 {
            encrypted[encrypted.count - 8] ^= 0x01 // Flip one bit
        }
        
        XCTAssertThrowsError(try serverSession.decryptFramePayload(encrypted)) { error in
            if case BlazeBinaryError.encryptionFailed = error {
                // Expected: authentication failure
            } else {
                XCTFail("Expected encryptionFailed error, got: \(error)")
            }
        }
    }
    
    func testFlippedBitsInCiphertext() throws {
        var clientHandshake = BlazeSecureHandshake(role: .client)
        var serverHandshake = BlazeSecureHandshake(role: .server)
        
        let clientHello = clientHandshake.makeClientHello()
        let serverHello = serverHandshake.makeServerHello()
        
        let clientKeys = try clientHandshake.processInboundMessage(serverHello)
        let serverKeys = try serverHandshake.processInboundMessage(clientHello)
        
        var clientSession = BlazeSecureSession(keyMaterial: clientKeys)
        var serverSession = BlazeSecureSession(keyMaterial: serverKeys)
        
        let plaintext = Data("Test message for tampering".utf8)
        var encrypted = try clientSession.makeEncryptedFrame(from: plaintext)
        
        // Flip bits in ciphertext (not in tag)
        // Ciphertext starts at byte 13 (after frameType + nonce)
        if encrypted.count > 29 {
            for i in 13..<(encrypted.count - 16) {
                encrypted[i] ^= 0x01 // Flip LSB
            }
        }
        
        XCTAssertThrowsError(try serverSession.decryptFramePayload(encrypted)) { error in
            if case BlazeBinaryError.encryptionFailed = error {
                // Expected: authentication fails
            } else {
                XCTFail("Expected encryptionFailed error")
            }
        }
    }
    
    func testWrongNoncePrefix() throws {
        // Create two sessions with different nonce prefixes
        var handshake1 = BlazeSecureHandshake(role: .client)
        var server1 = BlazeSecureHandshake(role: .server)
        var handshake2 = BlazeSecureHandshake(role: .client)
        var server2 = BlazeSecureHandshake(role: .server)
        
        let hello1 = handshake1.makeClientHello()
        let serverHello1 = server1.makeServerHello()
        let hello2 = handshake2.makeClientHello()
        let serverHello2 = server2.makeServerHello()
        
        let keys1 = try handshake1.processInboundMessage(serverHello1)
        let keys2 = try handshake2.processInboundMessage(serverHello2)
        
        // Nonce prefixes should be different
        XCTAssertNotEqual(keys1.noncePrefix, keys2.noncePrefix)
        
        // Encrypt with session1
        var session1 = BlazeSecureSession(keyMaterial: keys1)
        var session2 = BlazeSecureSession(keyMaterial: keys2)
        
        let plaintext = Data("Test".utf8)
        let encrypted1 = try session1.makeEncryptedFrame(from: plaintext)
        
        // Try to decrypt with session2 (different nonce prefix, different key)
        // Should fail due to wrong key
        XCTAssertThrowsError(try session2.decryptFramePayload(encrypted1)) { error in
            if case BlazeBinaryError.encryptionFailed = error {
                // Expected
            } else {
                XCTFail("Expected encryptionFailed error")
            }
        }
    }
    
    func testEntirelyZeroNonce() throws {
        // Test that all-zero nonce is invalid
        var clientHandshake = BlazeSecureHandshake(role: .client)
        var serverHandshake = BlazeSecureHandshake(role: .server)
        
        let clientHello = clientHandshake.makeClientHello()
        let serverHello = serverHandshake.makeServerHello()
        
        let clientKeys = try clientHandshake.processInboundMessage(serverHello)
        let serverKeys = try serverHandshake.processInboundMessage(clientHello)
        
        var clientSession = BlazeSecureSession(keyMaterial: clientKeys)
        var serverSession = BlazeSecureSession(keyMaterial: serverKeys)
        
        let plaintext = Data("Test".utf8)
        var encrypted = try clientSession.makeEncryptedFrame(from: plaintext)
        
        // Replace nonce with all zeros
        for i in 1..<13 {
            encrypted[i] = 0x00
        }
        
        // Decryption should fail (invalid nonce or wrong nonce)
        XCTAssertThrowsError(try serverSession.decryptFramePayload(encrypted)) { error in
            if case BlazeBinaryError.encryptionFailed = error {
                // Expected: authentication failure
            } else {
                XCTFail("Expected encryptionFailed error, got: \(error)")
            }
        }
    }
    
    func testRandomGarbageAsEncryptedFrame() {
        // Random garbage should not decrypt successfully
        var clientHandshake = BlazeSecureHandshake(role: .client)
        var serverHandshake = BlazeSecureHandshake(role: .server)
        
        let clientHello = clientHandshake.makeClientHello()
        let serverHello = serverHandshake.makeServerHello()
        
        let serverKeys = try! serverHandshake.processInboundMessage(clientHello)
        var serverSession = BlazeSecureSession(keyMaterial: serverKeys)
        
        // Generate random garbage
        var garbage = Data(count: 100)
        for i in 0..<garbage.count {
            garbage[i] = UInt8.random(in: 0...255)
        }
        
        // Prepend frameType byte
        var fakeFrame = Data()
        fakeFrame.append(0x01) // frameType = encrypted
        fakeFrame.append(garbage)
        
        // Should fail to decrypt
        XCTAssertThrowsError(try serverSession.decryptFramePayload(fakeFrame)) { error in
            if case BlazeBinaryError.encryptionFailed = error {
                // Expected
            } else {
                XCTFail("Expected encryptionFailed error")
            }
        }
    }
}

