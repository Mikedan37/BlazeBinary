//
// BlazeEncryptionTests.swift
// BlazeBinaryTests
//
// Copyright (c) 2025 Michael Danylchuk
// MIT License
//

import XCTest
@testable import BlazeBinary
import Crypto

final class BlazeEncryptionTests: XCTestCase {
    
    // MARK: - Round-Trip Tests
    
    func testEncryptDecryptRoundTrip() throws {
        // Create a session (simulate handshake)
        var clientHandshake = BlazeSecureHandshake(role: .client)
        let serverHandshake = BlazeSecureHandshake(role: .server)
        
        let clientHello = clientHandshake.makeClientHello()
        let serverHello = serverHandshake.makeServerHello()
        
        let clientKeys = try clientHandshake.processInboundMessage(serverHello)
        let serverKeys = try serverHandshake.processInboundMessage(clientHello)
        
        var clientSession = BlazeSecureSession(keyMaterial: clientKeys)
        var serverSession = BlazeSecureSession(keyMaterial: serverKeys)
        
        // Encrypt plaintext
        let plaintext = Data("Hello, secure world!".utf8)
        let encryptedPayload = try clientSession.makeEncryptedFrame(from: plaintext)
        
        // Decrypt
        let decrypted = try serverSession.decryptFramePayload(encryptedPayload)
        
        XCTAssertEqual(plaintext, decrypted)
    }
    
    func testEncryptDecryptMultipleFrames() throws {
        // Test multiple encrypted frames
        var clientHandshake = BlazeSecureHandshake(role: .client)
        let serverHandshake = BlazeSecureHandshake(role: .server)
        
        let clientHello = clientHandshake.makeClientHello()
        let serverHello = serverHandshake.makeServerHello()
        
        let clientKeys = try clientHandshake.processInboundMessage(serverHello)
        let serverKeys = try serverHandshake.processInboundMessage(clientHello)
        
        var clientSession = BlazeSecureSession(keyMaterial: clientKeys)
        var serverSession = BlazeSecureSession(keyMaterial: serverKeys)
        
        let messages = [
            Data("Message 1".utf8),
            Data("Message 2".utf8),
            Data("Message 3".utf8)
        ]
        
        var encryptedFrames: [Data] = []
        for message in messages {
            let encrypted = try clientSession.makeEncryptedFrame(from: message)
            encryptedFrames.append(encrypted)
        }
        
        // Decrypt all
        for encrypted in encryptedFrames {
            let decrypted = try serverSession.decryptFramePayload(encrypted)
            XCTAssertTrue(messages.contains(decrypted))
        }
    }
    
    func testEncryptDecryptEmptyData() throws {
        var clientHandshake = BlazeSecureHandshake(role: .client)
        let serverHandshake = BlazeSecureHandshake(role: .server)
        
        let clientHello = clientHandshake.makeClientHello()
        let serverHello = serverHandshake.makeServerHello()
        
        let clientKeys = try clientHandshake.processInboundMessage(serverHello)
        let serverKeys = try serverHandshake.processInboundMessage(clientHello)
        
        var clientSession = BlazeSecureSession(keyMaterial: clientKeys)
        var serverSession = BlazeSecureSession(keyMaterial: serverKeys)
        
        let emptyData = Data()
        let encrypted = try clientSession.makeEncryptedFrame(from: emptyData)
        let decrypted = try serverSession.decryptFramePayload(encrypted)
        
        XCTAssertEqual(emptyData, decrypted)
    }
    
    func testEncryptDecryptLargeData() throws {
        var clientHandshake = BlazeSecureHandshake(role: .client)
        let serverHandshake = BlazeSecureHandshake(role: .server)
        
        let clientHello = clientHandshake.makeClientHello()
        let serverHello = serverHandshake.makeServerHello()
        
        let clientKeys = try clientHandshake.processInboundMessage(serverHello)
        let serverKeys = try serverHandshake.processInboundMessage(clientHello)
        
        var clientSession = BlazeSecureSession(keyMaterial: clientKeys)
        var serverSession = BlazeSecureSession(keyMaterial: serverKeys)
        
        // 1 MB of data
        let largeData = Data(repeating: 0xAA, count: 1024 * 1024)
        let encrypted = try clientSession.makeEncryptedFrame(from: largeData)
        let decrypted = try serverSession.decryptFramePayload(encrypted)
        
        XCTAssertEqual(largeData, decrypted)
    }
    
    // MARK: - Wrong Key Tests
    
    func testWrongKeyDecryptionFails() throws {
        // Create two separate sessions with different keys
        var handshake1 = BlazeSecureHandshake(role: .client)
        let server1 = BlazeSecureHandshake(role: .server)
        var handshake2 = BlazeSecureHandshake(role: .client)
        let server2 = BlazeSecureHandshake(role: .server)
        
        _ = handshake1.makeClientHello()
        let serverHello1 = server1.makeServerHello()
        _ = handshake2.makeClientHello()
        let serverHello2 = server2.makeServerHello()
        
        let keys1 = try handshake1.processInboundMessage(serverHello1)
        let keys2 = try handshake2.processInboundMessage(serverHello2)
        
        var session1 = BlazeSecureSession(keyMaterial: keys1)
        let session2 = BlazeSecureSession(keyMaterial: keys2)
        
        // Encrypt with session1
        let plaintext = Data("Secret message".utf8)
        let encrypted = try session1.makeEncryptedFrame(from: plaintext)
        
        // Try to decrypt with session2 (wrong key)
        XCTAssertThrowsError(try session2.decryptFramePayload(encrypted)) { error in
            if case BlazeBinaryError.encryptionFailed = error {
                // Expected: decryption should fail
            } else {
                XCTFail("Expected encryptionFailed error")
            }
        }
    }
    
    // MARK: - Tampering Tests
    
    func testTamperedCiphertextFails() throws {
        var clientHandshake = BlazeSecureHandshake(role: .client)
        let serverHandshake = BlazeSecureHandshake(role: .server)
        
        let clientHello = clientHandshake.makeClientHello()
        let serverHello = serverHandshake.makeServerHello()
        
        let clientKeys = try clientHandshake.processInboundMessage(serverHello)
        let serverKeys = try serverHandshake.processInboundMessage(clientHello)
        
        var clientSession = BlazeSecureSession(keyMaterial: clientKeys)
        var serverSession = BlazeSecureSession(keyMaterial: serverKeys)
        
        let plaintext = Data("Original message".utf8)
        var encrypted = try clientSession.makeEncryptedFrame(from: plaintext)
        
        // Tamper with ciphertext (flip a bit)
        let tamperIndex = 20 // Somewhere in the ciphertext
        if tamperIndex < encrypted.count {
            encrypted[tamperIndex] ^= 0x01 // Flip bit
        }
        
        // Decryption should fail
        XCTAssertThrowsError(try serverSession.decryptFramePayload(encrypted)) { error in
            if case BlazeBinaryError.encryptionFailed = error {
                // Expected: authentication should fail
            } else {
                XCTFail("Expected encryptionFailed error")
            }
        }
    }
    
    func testTamperedTagFails() throws {
        var clientHandshake = BlazeSecureHandshake(role: .client)
        let serverHandshake = BlazeSecureHandshake(role: .server)
        
        let clientHello = clientHandshake.makeClientHello()
        let serverHello = serverHandshake.makeServerHello()
        
        let clientKeys = try clientHandshake.processInboundMessage(serverHello)
        let serverKeys = try serverHandshake.processInboundMessage(clientHello)
        
        var clientSession = BlazeSecureSession(keyMaterial: clientKeys)
        var serverSession = BlazeSecureSession(keyMaterial: serverKeys)
        
        let plaintext = Data("Original message".utf8)
        var encrypted = try clientSession.makeEncryptedFrame(from: plaintext)
        
        // Tamper with tag (last 16 bytes)
        if encrypted.count >= 16 {
            let tagStart = encrypted.count - 16
            encrypted[tagStart] ^= 0x01 // Flip bit in tag
        }
        
        // Decryption should fail
        XCTAssertThrowsError(try serverSession.decryptFramePayload(encrypted)) { error in
            if case BlazeBinaryError.encryptionFailed = error {
                // Expected: tag verification should fail
            } else {
                XCTFail("Expected encryptionFailed error")
            }
        }
    }
    
    func testTamperedNonceFails() throws {
        var clientHandshake = BlazeSecureHandshake(role: .client)
        let serverHandshake = BlazeSecureHandshake(role: .server)
        
        let clientHello = clientHandshake.makeClientHello()
        let serverHello = serverHandshake.makeServerHello()
        
        let clientKeys = try clientHandshake.processInboundMessage(serverHello)
        let serverKeys = try serverHandshake.processInboundMessage(clientHello)
        
        var clientSession = BlazeSecureSession(keyMaterial: clientKeys)
        var serverSession = BlazeSecureSession(keyMaterial: serverKeys)
        
        let plaintext = Data("Original message".utf8)
        var encrypted = try clientSession.makeEncryptedFrame(from: plaintext)
        
        // Tamper with nonce (bytes 1-12)
        if encrypted.count > 12 {
            encrypted[5] ^= 0x01 // Flip bit in nonce
        }
        
        // Decryption should fail
        XCTAssertThrowsError(try serverSession.decryptFramePayload(encrypted)) { error in
            if case BlazeBinaryError.encryptionFailed = error {
                // Expected: decryption with wrong nonce should fail
            } else {
                XCTFail("Expected encryptionFailed error")
            }
        }
    }
    
    // MARK: - Nonce Increment Tests
    
    func testNonceIncrements() throws {
        var clientHandshake = BlazeSecureHandshake(role: .client)
        let serverHandshake = BlazeSecureHandshake(role: .server)
        
        let clientHello = clientHandshake.makeClientHello()
        let serverHello = serverHandshake.makeServerHello()
        
        let clientKeys = try clientHandshake.processInboundMessage(serverHello)
        let serverKeys = try serverHandshake.processInboundMessage(clientHello)
        
        var clientSession = BlazeSecureSession(keyMaterial: clientKeys)
        
        let plaintext = Data("Message".utf8)
        
        // Encrypt multiple frames
        let encrypted1 = try clientSession.makeEncryptedFrame(from: plaintext)
        let encrypted2 = try clientSession.makeEncryptedFrame(from: plaintext)
        let encrypted3 = try clientSession.makeEncryptedFrame(from: plaintext)
        
        // Extract nonces (bytes 1-12 after frameType)
        let nonce1 = encrypted1.subdata(in: 1..<13)
        let nonce2 = encrypted2.subdata(in: 1..<13)
        let nonce3 = encrypted3.subdata(in: 1..<13)
        
        // Nonces should be different (counter increments)
        XCTAssertNotEqual(nonce1, nonce2)
        XCTAssertNotEqual(nonce2, nonce3)
        XCTAssertNotEqual(nonce1, nonce3)
        
        // Extract counters (last 8 bytes of nonce, big-endian)
        let counter1 = nonce1.suffix(8).withUnsafeBytes { bytes in
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
        
        let counter2 = nonce2.suffix(8).withUnsafeBytes { bytes in
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
        
        let counter3 = nonce3.suffix(8).withUnsafeBytes { bytes in
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
        
        // Counters should increment
        XCTAssertEqual(counter1, 0)
        XCTAssertEqual(counter2, 1)
        XCTAssertEqual(counter3, 2)
    }
    
    // MARK: - Format Tests
    
    func testEncryptedFrameFormat() throws {
        var clientHandshake = BlazeSecureHandshake(role: .client)
        let serverHandshake = BlazeSecureHandshake(role: .server)
        
        _ = clientHandshake.makeClientHello()
        let serverHello = serverHandshake.makeServerHello()
        
        let clientKeys = try clientHandshake.processInboundMessage(serverHello)
        
        var clientSession = BlazeSecureSession(keyMaterial: clientKeys)
        
        let plaintext = Data("Test".utf8)
        let encrypted = try clientSession.makeEncryptedFrame(from: plaintext)
        
        // Check format: frameType (1) + nonce (12) + ciphertext (N) + tag (16)
        XCTAssertGreaterThanOrEqual(encrypted.count, 1 + 12 + 16) // Minimum size
        
        // Check frameType
        XCTAssertEqual(encrypted[0], 0x01) // SecureFrameType.encrypted
        
        // Check nonce length (bytes 1-12)
        let nonce = encrypted.subdata(in: 1..<13)
        XCTAssertEqual(nonce.count, 12)
        
        // Check tag is last 16 bytes
        let tag = encrypted.suffix(16)
        XCTAssertEqual(tag.count, 16)
    }
    
    // MARK: - Error Tests
    
    func testDecryptTooShortPayload() {
        var clientHandshake = BlazeSecureHandshake(role: .client)
        let serverHandshake = BlazeSecureHandshake(role: .server)
        let serverHello = serverHandshake.makeServerHello()
        let keys = try! clientHandshake.processInboundMessage(serverHello)
        var session = BlazeSecureSession(keyMaterial: keys)
        
        // Too short (minimum is 29: 1 frameType + 12 nonce + 16 tag)
        let tooShort = Data([0x01]) // Just frameType
        
        XCTAssertThrowsError(try session.decryptFramePayload(tooShort)) { error in
            if case BlazeBinaryError.encryptionFailed(let message) = error {
                XCTAssertTrue(message.contains("too short"))
            } else {
                XCTFail("Expected encryptionFailed error")
            }
        }
    }
    
    func testDecryptWrongFrameType() {
        var clientHandshake = BlazeSecureHandshake(role: .client)
        let serverHandshake = BlazeSecureHandshake(role: .server)
        let serverHello = serverHandshake.makeServerHello()
        let keys = try! clientHandshake.processInboundMessage(serverHello)
        var session = BlazeSecureSession(keyMaterial: keys)
        
        // Wrong frame type (0x02 = handshake, not encrypted)
        var wrongType = Data(count: 29)
        wrongType[0] = 0x02
        
        XCTAssertThrowsError(try session.decryptFramePayload(wrongType)) { error in
            if case BlazeBinaryError.encryptionFailed(let message) = error {
                XCTAssertTrue(message.contains("frame type"))
            } else {
                XCTFail("Expected encryptionFailed error")
            }
        }
    }
}

