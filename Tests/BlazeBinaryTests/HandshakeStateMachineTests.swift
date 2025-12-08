//
// HandshakeStateMachineTests.swift
// BlazeBinary
//
// Copyright (c) 2025 Michael Danylchuk
// MIT License
//

import XCTest
import Foundation
@testable import BlazeBinary

/// Handshake state machine tests.
///
/// Tests valid handshake sequences and invalid sequences (negative tests).
final class HandshakeStateMachineTests: XCTestCase {
    
    // MARK: - Valid Sequence Tests
    
    func testValidSequenceClientHelloServerHelloFinish() throws {
        // Valid sequence: ClientHello → ServerHello → Finish (derive keys)
        var client = BlazeSecureHandshake(role: .client)
        var server = BlazeSecureHandshake(role: .server)
        
        // Step 1: ClientHello
        let clientHello = client.makeClientHello()
        XCTAssertEqual(clientHello.count, 36, "ClientHello must be 36 bytes")
        
        // Step 2: ServerHello
        try server.receiveRemotePublicKey(clientHello)
        let serverHello = server.makeServerHello()
        XCTAssertEqual(serverHello.count, 36, "ServerHello must be 36 bytes")
        
        // Step 3: Finish (derive keys)
        try client.receiveRemotePublicKey(serverHello)
        let clientKeys = try client.deriveSessionKeys()
        let serverKeys = try server.deriveSessionKeys()
        
        // Both must derive same keys
        XCTAssertEqual(
            clientKeys.encryptionKey.withUnsafeBytes { Data($0) },
            serverKeys.encryptionKey.withUnsafeBytes { Data($0) },
            "Both parties must derive identical keys"
        )
    }
    
    // MARK: - Invalid Sequence Tests
    
    func testMissingClientHello() throws {
        var server = BlazeSecureHandshake(role: .server)
        
        // Server tries to send ServerHello without receiving ClientHello
        let serverHello = server.makeServerHello()
        
        // Server can create ServerHello, but cannot derive keys without remote key
        XCTAssertThrowsError(try server.deriveSessionKeys()) { error in
            XCTAssertTrue(error is BlazeBinaryError)
            if case BlazeBinaryError.handshakeFailed(let message) = error {
                XCTAssertTrue(message.contains("Remote public key") || message.contains("not received"))
            } else {
                XCTFail("Expected handshakeFailed error, got: \(error)")
            }
        }
    }
    
    func testMissingServerHello() throws {
        var client = BlazeSecureHandshake(role: .client)
        
        // Client sends ClientHello but never receives ServerHello
        let clientHello = client.makeClientHello()
        
        // Client cannot derive keys without remote key
        XCTAssertThrowsError(try client.deriveSessionKeys()) { error in
            XCTAssertTrue(error is BlazeBinaryError)
        }
    }
    
    func testOutOfOrderMessages() throws {
        var client = BlazeSecureHandshake(role: .client)
        var server = BlazeSecureHandshake(role: .server)
        
        // Server tries to send ServerHello before receiving ClientHello
        let serverHello = server.makeServerHello()
        
        // Client receives ServerHello (out of order)
        // This should work syntactically, but keys won't match
        try client.receiveRemotePublicKey(serverHello)
        
        // Client sends ClientHello
        let clientHello = client.makeClientHello()
        try server.receiveRemotePublicKey(clientHello)
        
        // Both derive keys
        // Note: In X25519, the order doesn't matter - both parties derive the same shared secret
        // regardless of who sends first. This is a property of Diffie-Hellman key exchange.
        // The test expectation is incorrect - keys will be the same even if messages are out of order.
        let clientKeys = try client.deriveSessionKeys()
        let serverKeys = try server.deriveSessionKeys()
        
        // Keys will be the same because X25519 key agreement is commutative
        let clientKeyData = clientKeys.encryptionKey.withUnsafeBytes { Data($0) }
        let serverKeyData = serverKeys.encryptionKey.withUnsafeBytes { Data($0) }
        XCTAssertEqual(clientKeyData, serverKeyData, "X25519 key agreement is commutative - keys should match regardless of order")
    }
    
    func testDuplicateClientHello() throws {
        var client = BlazeSecureHandshake(role: .client)
        var server = BlazeSecureHandshake(role: .server)
        
        let clientHello1 = client.makeClientHello()
        let clientHello2 = client.makeClientHello() // Duplicate
        
        // Server receives first ClientHello
        try server.receiveRemotePublicKey(clientHello1)
        
        // Server receives duplicate ClientHello (overwrites previous)
        try server.receiveRemotePublicKey(clientHello2)
        
        // This should still work (last one wins)
        let serverHello = server.makeServerHello()
        try client.receiveRemotePublicKey(serverHello)
        
        let clientKeys = try client.deriveSessionKeys()
        let serverKeys = try server.deriveSessionKeys()
        
        // Keys should match (same public keys)
        XCTAssertEqual(
            clientKeys.encryptionKey.withUnsafeBytes { Data($0) },
            serverKeys.encryptionKey.withUnsafeBytes { Data($0) },
            "Duplicate ClientHello should still produce matching keys"
        )
    }
    
    func testDuplicateServerHello() throws {
        var client = BlazeSecureHandshake(role: .client)
        var server = BlazeSecureHandshake(role: .server)
        
        let clientHello = client.makeClientHello()
        try server.receiveRemotePublicKey(clientHello)
        
        let serverHello1 = server.makeServerHello()
        let serverHello2 = server.makeServerHello() // Duplicate
        
        // Client receives first ServerHello
        try client.receiveRemotePublicKey(serverHello1)
        
        // Client receives duplicate ServerHello (overwrites previous)
        try client.receiveRemotePublicKey(serverHello2)
        
        let clientKeys = try client.deriveSessionKeys()
        let serverKeys = try server.deriveSessionKeys()
        
        // Keys should match (same public keys)
        XCTAssertEqual(
            clientKeys.encryptionKey.withUnsafeBytes { Data($0) },
            serverKeys.encryptionKey.withUnsafeBytes { Data($0) },
            "Duplicate ServerHello should still produce matching keys"
        )
    }
    
    func testMixedProtocolVersions() throws {
        var server = BlazeSecureHandshake(role: .server)
        
        // Create handshake message with wrong version
        var invalidMessage = Data()
        invalidMessage.append(0x02) // Wrong version (should be 0x01)
        invalidMessage.append(0x01) // ClientHello type
        invalidMessage.append(contentsOf: [0x00, 0x00]) // Flags
        invalidMessage.append(Data(repeating: 0x42, count: 32)) // Public key
        
        XCTAssertThrowsError(try server.receiveRemotePublicKey(invalidMessage)) { error in
            XCTAssertTrue(error is BlazeBinaryError)
            if case BlazeBinaryError.invalidHandshake(let message) = error {
                XCTAssertTrue(message.contains("version") || message.contains("0x01") || message.contains("Unsupported"))
            } else {
                XCTFail("Expected invalidHandshake error, got: \(error)")
            }
        }
    }
    
    func testInvalidFrameTypesDuringHandshake() throws {
        var server = BlazeSecureHandshake(role: .server)
        
        // Create handshake message with invalid type
        var invalidMessage = Data()
        invalidMessage.append(0x01) // Version
        invalidMessage.append(0xFF) // Invalid type (should be 0x01 or 0x02)
        invalidMessage.append(contentsOf: [0x00, 0x00]) // Flags
        invalidMessage.append(Data(repeating: 0x42, count: 32)) // Public key
        
        XCTAssertThrowsError(try server.receiveRemotePublicKey(invalidMessage)) { error in
            XCTAssertTrue(error is BlazeBinaryError)
            if case BlazeBinaryError.invalidHandshake(let message) = error {
                XCTAssertTrue(message.contains("type") || message.contains("Invalid") || message.contains("0x01") || message.contains("0x02"))
            } else {
                XCTFail("Expected invalidHandshake error, got: \(error)")
            }
        }
    }
    
    func testPayloadTooShort() throws {
        var server = BlazeSecureHandshake(role: .server)
        
        // Handshake message too short (minimum 36 bytes)
        let tooShort = Data(repeating: 0x01, count: 35)
        
        XCTAssertThrowsError(try server.receiveRemotePublicKey(tooShort)) { error in
            XCTAssertTrue(error is BlazeBinaryError)
            if case BlazeBinaryError.invalidHandshake(let message) = error {
                XCTAssertTrue(message.contains("short") || message.contains("too short") || message.contains("36"))
            } else {
                XCTFail("Expected invalidHandshake error, got: \(error)")
            }
        }
    }
    
    func testPayloadTooLarge() throws {
        var server = BlazeSecureHandshake(role: .server)
        
        // Handshake message too large (should be exactly 36 bytes)
        var tooLarge = Data(repeating: 0x01, count: 37)
        tooLarge[0] = 0x01 // Version
        tooLarge[1] = 0x01 // Type
        // Rest is padding
        
        // This might be accepted (extra bytes ignored) or rejected
        // Test that it doesn't crash
        let result = try? server.receiveRemotePublicKey(tooLarge)
        // If accepted, key derivation might fail due to invalid key
        if result != nil {
            XCTAssertThrowsError(try server.deriveSessionKeys()) { error in
                XCTAssertTrue(error is BlazeBinaryError)
            }
        }
    }
    
    func testMalformedMessageHeaders() throws {
        var server = BlazeSecureHandshake(role: .server)
        
        // Test various malformed headers
        let testCases: [(Data, String)] = [
            // Empty message
            (Data(), "empty"),
            // Missing version
            (Data([0x01]), "missing version"),
            // Missing type
            (Data([0x01, 0x01]), "missing type"),
            // Missing flags
            (Data([0x01, 0x01, 0x00]), "missing flags"),
            // Missing key
            (Data([0x01, 0x01, 0x00, 0x00]), "missing key")
        ]
        
        for (malformed, description) in testCases {
            XCTAssertThrowsError(try server.receiveRemotePublicKey(malformed), "\(description) should be rejected") { error in
                XCTAssertTrue(error is BlazeBinaryError)
            }
        }
    }
    
    func testHandshakeWithEmptyPublicKey() throws {
        var server = BlazeSecureHandshake(role: .server)
        
        // Create message with empty public key (wrong size)
        var message = Data()
        message.append(0x01) // Version
        message.append(0x01) // Type
        message.append(contentsOf: [0x00, 0x00]) // Flags
        // No public key (should be 32 bytes)
        
        XCTAssertThrowsError(try server.receiveRemotePublicKey(message)) { error in
            XCTAssertTrue(error is BlazeBinaryError)
        }
    }
    
    func testHandshakeWithPartialPublicKey() throws {
        var server = BlazeSecureHandshake(role: .server)
        
        // Create message with partial public key
        var message = Data()
        message.append(0x01) // Version
        message.append(0x01) // Type
        message.append(contentsOf: [0x00, 0x00]) // Flags
        message.append(Data(repeating: 0x42, count: 16)) // Only 16 bytes instead of 32
        
        XCTAssertThrowsError(try server.receiveRemotePublicKey(message)) { error in
            XCTAssertTrue(error is BlazeBinaryError)
        }
    }
    
    // MARK: - State Transition Tests
    
    func testCannotDeriveKeysBeforeReceivingRemoteKey() throws {
        var client = BlazeSecureHandshake(role: .client)
        
        // Try to derive keys before receiving remote key
        XCTAssertThrowsError(try client.deriveSessionKeys()) { error in
            XCTAssertTrue(error is BlazeBinaryError)
            if case BlazeBinaryError.handshakeFailed(let message) = error {
                XCTAssertTrue(message.contains("Remote public key") || message.contains("not received"))
            } else {
                XCTFail("Expected handshakeFailed error, got: \(error)")
            }
        }
    }
    
    func testCanDeriveKeysAfterReceivingRemoteKey() throws {
        var client = BlazeSecureHandshake(role: .client)
        var server = BlazeSecureHandshake(role: .server)
        
        // Complete handshake
        try server.receiveRemotePublicKey(client.makeClientHello())
        try client.receiveRemotePublicKey(server.makeServerHello())
        
        // Now both can derive keys
        XCTAssertNoThrow(try client.deriveSessionKeys())
        XCTAssertNoThrow(try server.deriveSessionKeys())
    }
    
    func testMultipleKeyDerivationsProduceSameKeys() throws {
        var client = BlazeSecureHandshake(role: .client)
        var server = BlazeSecureHandshake(role: .server)
        
        // Complete handshake
        try server.receiveRemotePublicKey(client.makeClientHello())
        try client.receiveRemotePublicKey(server.makeServerHello())
        
        // Derive keys multiple times
        let keys1 = try client.deriveSessionKeys()
        let keys2 = try client.deriveSessionKeys()
        
        // Should produce same keys (deterministic)
        XCTAssertEqual(
            keys1.encryptionKey.withUnsafeBytes { Data($0) },
            keys2.encryptionKey.withUnsafeBytes { Data($0) },
            "Multiple derivations should produce same keys"
        )
    }
}

