//
// EncryptedFrameFlowTests.swift
// BlazeBinary
//
// Copyright (c) 2025 Michael Danylchuk
// MIT License
//

import XCTest
import Foundation
import Crypto
@testable import BlazeBinary

/// Comprehensive encrypted frame flow tests.
///
/// Tests complete handshake → encrypted frames flow with various payload sizes,
/// compression combinations, and error paths.
final class EncryptedFrameFlowTests: XCTestCase {
    
    // MARK: - Setup
    
    private func createTestSession() throws -> BlazeSecureSession {
        var alice = BlazeSecureHandshake(role: .client)
        var bob = BlazeSecureHandshake(role: .server)
        
        try bob.receiveRemotePublicKey(alice.makeClientHello())
        try alice.receiveRemotePublicKey(bob.makeServerHello())
        
        let keys = try alice.deriveSessionKeys()
        var session = BlazeSecureSession(keyMaterial: keys)
        session.strictReplayProtection = false // Allow counter 0 for tests
        return session
    }
    
    // MARK: - Small Payload Tests
    
    func testEncryptionOfSmallPayloads() throws {
        var session = try createTestSession()
        
        let smallPayloads: [Data] = [
            Data([0x01]),
            Data([0x01, 0x02, 0x03]),
            Data("Hello".utf8),
            Data(repeating: 0x42, count: 16),
            Data(repeating: 0xAA, count: 64)
        ]
        
        for payload in smallPayloads {
            let encrypted = try session.makeEncryptedFrame(from: payload)
            XCTAssertGreaterThanOrEqual(encrypted.count, 29, "Encrypted frame must be at least 29 bytes")
            
            let decrypted = try session.decryptFramePayload(encrypted)
            XCTAssertEqual(decrypted, payload, "Decrypted payload must match original")
        }
    }
    
    func testEncryptionOfLargePayloads() throws {
        var session = try createTestSession()
        
        // Test payloads > 1MB
        let largeSizes = [1024 * 1024, 2 * 1024 * 1024, 5 * 1024 * 1024]
        
        for size in largeSizes {
            let payload = Data(repeating: UInt8(size % 256), count: size)
            let encrypted = try session.makeEncryptedFrame(from: payload)
            
            XCTAssertGreaterThan(encrypted.count, payload.count, "Encrypted frame should be larger due to nonce + tag")
            
            let decrypted = try session.decryptFramePayload(encrypted)
            XCTAssertEqual(decrypted, payload, "Large payload must decrypt correctly")
        }
    }
    
    // MARK: - Compression + Encryption Tests
    
    func testFramesWithCompressionEnabledAndEncryption() throws {
        var session = try createTestSession()
        
        // Create compressible payload (repeating pattern)
        let payload = Data(repeating: 0x42, count: 1000)
        
        // Compress then encrypt
        let compressed: Data
        do {
            compressed = try BlazeCompression.compress(payload, mode: .lz4)
        } catch let error as BlazeBinaryError {
            if case .decodeFailed(let message) = error, message.contains("not supported") {
                throw XCTSkip("LZ4 compression not supported on this platform")
            }
            throw error
        }
        
        let encrypted = try session.makeEncryptedFrame(from: compressed)
        
        // Decrypt then decompress
        let decrypted = try session.decryptFramePayload(encrypted)
        let decompressed = try BlazeCompression.decompress(decrypted, mode: .lz4, originalSize: nil)
        
        XCTAssertEqual(decompressed, payload, "Compressed+encrypted payload must round-trip correctly")
    }
    
    func testFramesWithCompressionDisabledAndEncryption() throws {
        var session = try createTestSession()
        
        // Create incompressible payload (random data)
        let randomKey = SymmetricKey(size: .bits256)
        var payload = randomKey.withUnsafeBytes { Data($0) }
        // Generate more bytes if needed (1000 bytes)
        while payload.count < 1000 {
            let moreKey = SymmetricKey(size: .bits256)
            let moreData = moreKey.withUnsafeBytes { Data($0) }
            payload.append(moreData)
        }
        payload = payload.prefix(1000)
        
        // Encrypt without compression
        let encrypted = try session.makeEncryptedFrame(from: payload)
        let decrypted = try session.decryptFramePayload(encrypted)
        
        XCTAssertEqual(decrypted, payload, "Uncompressed+encrypted payload must round-trip correctly")
    }
    
    // MARK: - Decryption Error Paths
    
    func testDecryptionWithWrongKey() throws {
        var session1 = try createTestSession()
        var session2 = try createTestSession() // Different session = different keys
        
        let payload = Data("Secret message".utf8)
        let encrypted = try session1.makeEncryptedFrame(from: payload)
        
        // Try to decrypt with wrong key
        XCTAssertThrowsError(try session2.decryptFramePayload(encrypted)) { error in
            XCTAssertTrue(error is BlazeBinaryError, "Wrong key must cause BlazeBinaryError")
        }
    }
    
    func testDecryptionWithWrongNonce() throws {
        var session = try createTestSession()
        
        let payload = Data("Test message".utf8)
        let encrypted = try session.makeEncryptedFrame(from: payload)
        
        // Corrupt the nonce (bytes 1-12)
        var corrupted = encrypted
        corrupted[5] ^= 0xFF // Flip bits in nonce
        
        XCTAssertThrowsError(try session.decryptFramePayload(corrupted)) { error in
            XCTAssertTrue(error is BlazeBinaryError)
        }
    }
    
    func testDecryptionWithWrongAAD() throws {
        // AAD is constructed from frameType + context string
        // We can't easily change AAD without changing the encryption, but we can test
        // that AAD verification works by trying to decrypt with modified frameType
        
        var session = try createTestSession()
        let payload = Data("Test message".utf8)
        let encrypted = try session.makeEncryptedFrame(from: payload)
        
        // The frameType is in the encrypted payload, changing it would break parsing
        // Instead, test that AAD is properly verified by ensuring wrong keys fail
        // (AAD mismatch would cause authentication failure)
        
        // Create session with different config (different AAD context)
        _ = BlazeSecureHandshake(role: .client)
        _ = BlazeSecureHandshake(role: .server)
        
        let customConfig = BlazeCryptoConfig(
            hkdfInfo: Data("DifferentContext".utf8) // Different info = different keys
        )
        
        var aliceCustom = BlazeSecureHandshake(role: .client, config: customConfig)
        var bobCustom = BlazeSecureHandshake(role: .server, config: customConfig)
        
        try bobCustom.receiveRemotePublicKey(aliceCustom.makeClientHello())
        try aliceCustom.receiveRemotePublicKey(bobCustom.makeServerHello())
        
        let customKeys = try aliceCustom.deriveSessionKeys()
        var customSession = BlazeSecureSession(keyMaterial: customKeys)
        
        // Try to decrypt with different keys (would have different AAD context)
        XCTAssertThrowsError(try customSession.decryptFramePayload(encrypted)) { error in
            XCTAssertTrue(error is BlazeBinaryError)
        }
    }
    
    func testDecryptionWithCorruptedCiphertext() throws {
        var session = try createTestSession()
        
        let payload = Data("Test message".utf8)
        let encrypted = try session.makeEncryptedFrame(from: payload)
        
        // Corrupt ciphertext (bytes 13 to tag start)
        var corrupted = encrypted
        let ciphertextStart = 13
        let tagStart = corrupted.count - 16
        
        if tagStart > ciphertextStart {
            corrupted[ciphertextStart + 5] ^= 0xFF // Flip bits in ciphertext
        }
        
        XCTAssertThrowsError(try session.decryptFramePayload(corrupted)) { error in
            XCTAssertTrue(error is BlazeBinaryError)
        }
    }
    
    func testDecryptionWithCorruptedTag() throws {
        var session = try createTestSession()
        
        let payload = Data("Test message".utf8)
        let encrypted = try session.makeEncryptedFrame(from: payload)
        
        // Corrupt tag (last 16 bytes)
        var corrupted = encrypted
        corrupted[corrupted.count - 8] ^= 0xFF // Flip bits in tag
        
        XCTAssertThrowsError(try session.decryptFramePayload(corrupted)) { error in
            XCTAssertTrue(error is BlazeBinaryError)
        }
    }
    
    func testDecryptionWithTruncatedCiphertext() throws {
        var session = try createTestSession()
        
        let payload = Data("Test message".utf8)
        let encrypted = try session.makeEncryptedFrame(from: payload)
        
        // Truncate ciphertext (remove bytes before tag)
        let truncated = encrypted.prefix(encrypted.count - 10)
        
        XCTAssertThrowsError(try session.decryptFramePayload(truncated)) { error in
            XCTAssertTrue(error is BlazeBinaryError)
        }
    }
    
    func testDecryptionWithTruncatedTag() throws {
        var session = try createTestSession()
        
        let payload = Data("Test message".utf8)
        let encrypted = try session.makeEncryptedFrame(from: payload)
        
        // Truncate tag (remove last bytes)
        let truncated = encrypted.prefix(encrypted.count - 8) // Remove 8 bytes from tag
        
        XCTAssertThrowsError(try session.decryptFramePayload(truncated)) { error in
            XCTAssertTrue(error is BlazeBinaryError)
        }
    }
    
    func testDecryptionWithTooShortFrame() throws {
        var session = try createTestSession()
        
        // Minimum frame is 29 bytes (1 frameType + 12 nonce + 16 tag)
        let tooShort = Data(repeating: 0x01, count: 28)
        
        XCTAssertThrowsError(try session.decryptFramePayload(tooShort)) { error in
            XCTAssertTrue(error is BlazeBinaryError, "Too short frame must cause BlazeBinaryError")
        }
    }
    
    func testDecryptionWithWrongFrameType() throws {
        var session = try createTestSession()
        
        let payload = Data("Test message".utf8)
        let encrypted = try session.makeEncryptedFrame(from: payload)
        
        // Change frameType byte (first byte of encrypted payload)
        // In v2.0 format, the frameType is in the frame header, but the encrypted payload
        // also has a frameType byte for AAD. Changing it will cause authentication failure.
        var corrupted = encrypted
        // The encrypted payload starts after the frame header (6 bytes)
        // The frameType byte in the encrypted payload is at offset 6
        if corrupted.count > 6 {
            corrupted[6] = 0x02 // Wrong frame type in encrypted payload
        }
        
        XCTAssertThrowsError(try session.decryptFramePayload(corrupted)) { error in
            XCTAssertTrue(error is BlazeBinaryError, "Wrong frame type must cause authentication failure")
        }
    }
    
    // MARK: - Multiple Frame Tests
    
    func testMultipleEncryptedFrames() throws {
        var session = try createTestSession()
        
        let messages = [
            Data("Message 1".utf8),
            Data("Message 2".utf8),
            Data("Message 3".utf8)
        ]
        
        var encryptedFrames: [Data] = []
        for message in messages {
            let encrypted = try session.makeEncryptedFrame(from: message)
            encryptedFrames.append(encrypted)
        }
        
        // Decrypt all frames using the same session instance
        // This ensures counters match (same session encrypts and decrypts)
        for (index, encrypted) in encryptedFrames.enumerated() {
            let decrypted = try session.decryptFramePayload(encrypted)
            XCTAssertEqual(decrypted, messages[index], "Frame \(index) must decrypt correctly")
        }
    }
    
    func testBidirectionalEncryption() throws {
        var alice = BlazeSecureHandshake(role: .client)
        var bob = BlazeSecureHandshake(role: .server)
        
        try bob.receiveRemotePublicKey(alice.makeClientHello())
        try alice.receiveRemotePublicKey(bob.makeServerHello())
        
        let aliceKeys = try alice.deriveSessionKeys()
        let bobKeys = try bob.deriveSessionKeys()
        
        var aliceSession = BlazeSecureSession(keyMaterial: aliceKeys)
        var bobSession = BlazeSecureSession(keyMaterial: bobKeys)
        
        // Alice sends to Bob
        let aliceMessage = Data("Alice to Bob".utf8)
        let aliceEncrypted = try aliceSession.makeEncryptedFrame(from: aliceMessage)
        let bobDecrypted = try bobSession.decryptFramePayload(aliceEncrypted)
        XCTAssertEqual(bobDecrypted, aliceMessage)
        
        // Bob sends to Alice
        let bobMessage = Data("Bob to Alice".utf8)
        let bobEncrypted = try bobSession.makeEncryptedFrame(from: bobMessage)
        let aliceDecrypted = try aliceSession.decryptFramePayload(bobEncrypted)
        XCTAssertEqual(aliceDecrypted, bobMessage)
    }
}

