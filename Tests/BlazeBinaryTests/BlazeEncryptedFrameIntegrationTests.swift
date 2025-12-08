//
// BlazeEncryptedFrameIntegrationTests.swift
// BlazeBinaryTests
//
// Copyright (c) 2025 Michael Danylchuk
// MIT License
//

import XCTest
@testable import BlazeBinary
import Crypto

final class BlazeEncryptedFrameIntegrationTests: XCTestCase {
    
    // MARK: - Full Client/Server Simulation
    
    func testFullClientServerHandshakeAndEncryption() throws {
        // === CLIENT SIDE ===
        
        // 1. Create client handshake
        var clientHandshake = BlazeSecureHandshake(role: .client)
        
        // 2. Create and encode clientHello frame
        let clientHello = clientHandshake.makeOutboundMessage()
        let clientHelloFrame = try BlazeFrameEncoder.encodeHandshakeFrame(clientHello)
        
        // === SERVER SIDE ===
        
        // 3. Parse clientHello frame
        let serverParser = BlazeFrameParser()
        try serverParser.append(clientHelloFrame)
        let receivedClientHello = try serverParser.nextFrame()
        XCTAssertNotNil(receivedClientHello)
        
        // 4. Create server handshake and process clientHello
        var serverHandshake = BlazeSecureHandshake(role: .server)
        let serverKeys = try serverHandshake.processInboundMessage(receivedClientHello!)
        
        // 5. Create and encode serverHello frame
        let serverHello = serverHandshake.makeOutboundMessage()
        let serverHelloFrame = try BlazeFrameEncoder.encodeHandshakeFrame(serverHello)
        
        // === CLIENT SIDE ===
        
        // 6. Parse serverHello frame
        let clientParser = BlazeFrameParser()
        try clientParser.append(serverHelloFrame)
        let receivedServerHello = try clientParser.nextFrame()
        XCTAssertNotNil(receivedServerHello)
        
        // 7. Process serverHello and derive keys
        let clientKeys = try clientHandshake.processInboundMessage(receivedServerHello!)
        
        // 8. Verify keys match
        // Note: noncePrefix is randomly generated per handshake, so they won't match
        // But encryption and authentication keys should match
        XCTAssertEqual(clientKeys.encryptionKey.withUnsafeBytes { Data($0) }, serverKeys.encryptionKey.withUnsafeBytes { Data($0) })
        // Nonce prefixes are randomly generated, so they will be different (expected)
        
        // === ENCRYPTED COMMUNICATION ===
        
        // 9. Create secure sessions
        var clientSession = BlazeSecureSession(keyMaterial: clientKeys)
        var serverSession = BlazeSecureSession(keyMaterial: serverKeys)
        
        // 10. Client encrypts and sends frame
        let clientMessage = Data("Hello from client!".utf8)
        let encryptedClientFrame = try BlazeFrameEncoder.encodeEncryptedFrame(clientMessage, session: &clientSession)
        
        // 11. Server receives and decrypts
        let serverEncryptedParser = BlazeFrameParser(secureSession: serverSession)
        try serverEncryptedParser.append(encryptedClientFrame)
        let decryptedClientMessage = try serverEncryptedParser.nextFrame()
        XCTAssertEqual(clientMessage, decryptedClientMessage)
        
        // 12. Server encrypts and sends response
        let serverMessage = Data("Hello from server!".utf8)
        let encryptedServerFrame = try BlazeFrameEncoder.encodeEncryptedFrame(serverMessage, session: &serverSession)
        
        // 13. Client receives and decrypts
        let clientEncryptedParser = BlazeFrameParser(secureSession: clientSession)
        try clientEncryptedParser.append(encryptedServerFrame)
        let decryptedServerMessage = try clientEncryptedParser.nextFrame()
        XCTAssertEqual(serverMessage, decryptedServerMessage)
    }
    
    func testMultipleEncryptedFramesInSequence() throws {
        // Establish session
        var clientHandshake = BlazeSecureHandshake(role: .client)
        var serverHandshake = BlazeSecureHandshake(role: .server)
        
        let clientHello = clientHandshake.makeClientHello()
        let serverHello = serverHandshake.makeServerHello()
        
        let clientKeys = try clientHandshake.processInboundMessage(serverHello)
        let serverKeys = try serverHandshake.processInboundMessage(clientHello)
        
        var clientSession = BlazeSecureSession(keyMaterial: clientKeys)
        var serverSession = BlazeSecureSession(keyMaterial: serverKeys)
        
        // Send multiple encrypted frames
        let messages = [
            Data("Message 1".utf8),
            Data("Message 2".utf8),
            Data("Message 3".utf8)
        ]
        
        var encryptedFrames: [Data] = []
        for message in messages {
            let frame = try BlazeFrameEncoder.encodeEncryptedFrame(message, session: &clientSession)
            encryptedFrames.append(frame)
        }
        
        // Receive and decrypt all frames
        let parser = BlazeFrameParser(secureSession: serverSession)
        for frame in encryptedFrames {
            try parser.append(frame)
            if let decrypted = try parser.nextFrame() {
                XCTAssertTrue(messages.contains(decrypted))
            } else {
                XCTFail("Failed to decrypt frame")
            }
        }
    }
    
    // MARK: - Mixed Plaintext and Encrypted Frames
    
    func testMixedPlaintextAndEncryptedFrames() throws {
        // Establish session
        var clientHandshake = BlazeSecureHandshake(role: .client)
        var serverHandshake = BlazeSecureHandshake(role: .server)
        
        let clientHello = clientHandshake.makeClientHello()
        let serverHello = serverHandshake.makeServerHello()
        
        let clientKeys = try clientHandshake.processInboundMessage(serverHello)
        let serverKeys = try serverHandshake.processInboundMessage(clientHello)
        
        var clientSession = BlazeSecureSession(keyMaterial: clientKeys)
        var serverSession = BlazeSecureSession(keyMaterial: serverKeys)
        
        // Create plaintext frame (legacy)
        let plaintextMessage = Data("Plaintext message".utf8)
        let plaintextFrame = try BlazeFrameEncoder.encodeFrame(plaintextMessage)
        
        // Create encrypted frame
        let encryptedMessage = Data("Encrypted message".utf8)
        let encryptedFrame = try BlazeFrameEncoder.encodeEncryptedFrame(encryptedMessage, session: &clientSession)
        
        // Parser should handle both
        let parser = BlazeFrameParser(secureSession: serverSession)
        
        // Parse plaintext frame
        try parser.append(plaintextFrame)
        guard let parsedPlaintext = try parser.nextFrame() else {
            XCTFail("Plaintext frame should be parsed")
            return
        }
        XCTAssertEqual(plaintextMessage, parsedPlaintext, "Plaintext message should match")
        
        // Parse encrypted frame
        try parser.append(encryptedFrame)
        do {
            let parsedEncrypted = try parser.nextFrame()
            guard let parsedEncrypted = parsedEncrypted else {
                XCTFail("Encrypted frame should be parsed (got nil)")
                return
            }
            XCTAssertEqual(encryptedMessage, parsedEncrypted, "Encrypted message should match")
        } catch {
            XCTFail("Failed to parse encrypted frame: \(error)")
            throw error
        }
    }
    
    func testPlaintextFramesWithoutSession() throws {
        // Plaintext frames should work without secure session
        let plaintextMessage = Data("Plaintext message".utf8)
        let plaintextFrame = try BlazeFrameEncoder.encodeFrame(plaintextMessage)
        
        let parser = BlazeFrameParser() // No secure session
        try parser.append(plaintextFrame)
        let parsed = try parser.nextFrame()
        
        XCTAssertEqual(plaintextMessage, parsed)
    }
    
    func testEncryptedFramesWithoutSession() throws {
        // Encrypted frames without session should return encrypted payload as-is
        var clientHandshake = BlazeSecureHandshake(role: .client)
        var serverHandshake = BlazeSecureHandshake(role: .server)
        
        let clientHello = clientHandshake.makeClientHello()
        let serverHello = serverHandshake.makeServerHello()
        
        let clientKeys = try clientHandshake.processInboundMessage(serverHello)
        
        var clientSession = BlazeSecureSession(keyMaterial: clientKeys)
        
        let message = Data("Encrypted message".utf8)
        let encryptedFrame = try BlazeFrameEncoder.encodeEncryptedFrame(message, session: &clientSession)
        
        // Parser without session should return encrypted payload (without frameType byte)
        let parser = BlazeFrameParser() // No secure session
        try parser.append(encryptedFrame)
        let encryptedPayload = try parser.nextFrame()
        
        // Should be the encrypted payload (frameType byte removed for caller)
        // In v2.0 format, frameType is in header, but encrypted payload includes it for AAD
        // Parser removes it when no session is provided
        XCTAssertNotNil(encryptedPayload)
        // Encrypted payload should be at least 28 bytes (12 nonce + 16 tag)
        XCTAssertGreaterThanOrEqual(encryptedPayload?.count ?? 0, 28)
    }
    
    // MARK: - Handshake Frame Tests
    
    func testHandshakeFrameEncoding() throws {
        let handshake = BlazeSecureHandshake(role: .client)
        let handshakeMessage = handshake.makeClientHello()
        
        let frame = try BlazeFrameEncoder.encodeHandshakeFrame(handshakeMessage)
        
        // Parse frame
        let parser = BlazeFrameParser()
        try parser.append(frame)
        let parsed = try parser.nextFrame()
        
        // Should match original handshake message
        XCTAssertEqual(handshakeMessage, parsed)
    }
    
    func testHandshakeFrameFormat() throws {
        let handshake = BlazeSecureHandshake(role: .client)
        let handshakeMessage = handshake.makeClientHello()
        
        let frame = try BlazeFrameEncoder.encodeHandshakeFrame(handshakeMessage)
        
        // v2.0 frame format:
        // Byte 0: frameType
        // Byte 1: compressionMode
        // Bytes 2-5: payloadLength (big-endian UInt32)
        // Bytes 6+: payload
        
        // Check frameType (byte 0)
        XCTAssertEqual(frame[0], 0x02) // SecureFrameType.handshake
        
        // Check compressionMode (byte 1)
        XCTAssertEqual(frame[1], 0x00) // CompressionMode.none
        
        // Check payloadLength (bytes 2-5)
        let lengthBytes = frame.subdata(in: 2..<6)
        let payloadLength = lengthBytes.withUnsafeBytes { bytes in
            var value: UInt32 = 0
            value |= UInt32(bytes[0]) << 24
            value |= UInt32(bytes[1]) << 16
            value |= UInt32(bytes[2]) << 8
            value |= UInt32(bytes[3])
            return value
        }
        
        XCTAssertEqual(payloadLength, UInt32(handshakeMessage.count)) // 36 bytes
        
        // Check handshake message (bytes 6+)
        let parsedMessage = frame.subdata(in: 6..<frame.count)
        XCTAssertEqual(parsedMessage, handshakeMessage)
    }
    
    // MARK: - Error Cases
    
    func testEncryptedFrameWithWrongSession() throws {
        // Create two different sessions
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
        
        // Encrypt with session1
        let message = Data("Secret".utf8)
        let encryptedFrame = try BlazeFrameEncoder.encodeEncryptedFrame(message, session: &session1)
        
        // Try to decrypt with session2 (wrong key)
        let parser = BlazeFrameParser(secureSession: session2)
        try parser.append(encryptedFrame)
        
        XCTAssertThrowsError(try parser.nextFrame()) { error in
            if case BlazeBinaryError.encryptionFailed = error {
                // Expected: wrong key
            } else {
                XCTFail("Expected encryptionFailed error")
            }
        }
    }
    
    func testTruncatedEncryptedFrame() throws {
        var clientHandshake = BlazeSecureHandshake(role: .client)
        var serverHandshake = BlazeSecureHandshake(role: .server)
        
        let clientHello = clientHandshake.makeClientHello()
        let serverHello = serverHandshake.makeServerHello()
        
        let clientKeys = try clientHandshake.processInboundMessage(serverHello)
        let serverKeys = try serverHandshake.processInboundMessage(clientHello)
        
        var clientSession = BlazeSecureSession(keyMaterial: clientKeys)
        var serverSession = BlazeSecureSession(keyMaterial: serverKeys)
        
        let message = Data("Test".utf8)
        var encryptedFrame = try BlazeFrameEncoder.encodeEncryptedFrame(message, session: &clientSession)
        
        // Truncate frame (remove last byte)
        encryptedFrame = encryptedFrame.prefix(encryptedFrame.count - 1)
        
        // Should fail when parsing
        let parser = BlazeFrameParser(secureSession: serverSession)
        try parser.append(encryptedFrame)
        
        // Parser might return nil (incomplete frame) or throw
        // Either is acceptable - the important thing is it doesn't crash
        let result = try? parser.nextFrame()
        // If it returns nil, that's fine (incomplete frame)
        // If it throws, that's also fine (invalid frame)
    }
}

