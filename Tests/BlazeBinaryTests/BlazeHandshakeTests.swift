//
// BlazeHandshakeTests.swift
// BlazeBinaryTests
//
// Copyright (c) 2025 Michael Danylchuk
// MIT License
//

import XCTest
@testable import BlazeBinary
import Crypto

final class BlazeHandshakeTests: XCTestCase {
    
    // MARK: - Key Agreement Tests
    
    func testClientServerKeyAgreement() throws {
        // Create client and server handshakes
        var clientHandshake = BlazeSecureHandshake(role: .client)
        var serverHandshake = BlazeSecureHandshake(role: .server)
        
        // Exchange public keys
        let clientHello = clientHandshake.makeClientHello()
        let serverHello = serverHandshake.makeServerHello()
        
        // Both parties derive session keys
        let clientKeys = try clientHandshake.processInboundMessage(serverHello)
        let serverKeys = try serverHandshake.processInboundMessage(clientHello)
        
        // Verify keys are complementary (client's sendKey == server's receiveKey and vice versa)
        XCTAssertEqual(clientKeys.sendKey.withUnsafeBytes { Data($0) }, serverKeys.receiveKey.withUnsafeBytes { Data($0) })
        XCTAssertEqual(clientKeys.receiveKey.withUnsafeBytes { Data($0) }, serverKeys.sendKey.withUnsafeBytes { Data($0) })
        XCTAssertEqual(clientKeys.authenticationKey.withUnsafeBytes { Data($0) }, serverKeys.authenticationKey.withUnsafeBytes { Data($0) })
        // Nonce prefixes are deterministically derived per direction
        XCTAssertEqual(clientKeys.sendNoncePrefix, serverKeys.receiveNoncePrefix)
        XCTAssertEqual(clientKeys.receiveNoncePrefix, serverKeys.sendNoncePrefix)
    }
    
    func testKeyAgreementWithMakeOutboundMessage() throws {
        // Test convenience method
        var clientHandshake = BlazeSecureHandshake(role: .client)
        var serverHandshake = BlazeSecureHandshake(role: .server)

        let clientHello = clientHandshake.makeOutboundMessage()
        let serverHello = serverHandshake.makeOutboundMessage()

        let clientKeys = try clientHandshake.processInboundMessage(serverHello)
        let serverKeys = try serverHandshake.processInboundMessage(clientHello)

        // Client's send key should match server's receive key
        XCTAssertEqual(clientKeys.sendKey.withUnsafeBytes { Data($0) }, serverKeys.receiveKey.withUnsafeBytes { Data($0) })
    }
    
    func testDifferentHandshakesProduceDifferentKeys() throws {
        // Two separate handshakes should produce different keys
        var handshake1 = BlazeSecureHandshake(role: .client)
        var handshake2 = BlazeSecureHandshake(role: .client)
        let server1 = BlazeSecureHandshake(role: .server)
        let server2 = BlazeSecureHandshake(role: .server)
        
        _ = handshake1.makeClientHello()
        _ = handshake2.makeClientHello()
        let serverHello1 = server1.makeServerHello()
        let serverHello2 = server2.makeServerHello()
        
        let keys1 = try handshake1.processInboundMessage(serverHello1)
        let keys2 = try handshake2.processInboundMessage(serverHello2)
        
        // Keys should be different (different nonce prefixes)
        XCTAssertNotEqual(keys1.noncePrefix, keys2.noncePrefix)
    }
    
    // MARK: - Handshake Message Format Tests
    
    func testClientHelloFormat() {
        let handshake = BlazeSecureHandshake(role: .client)
        let clientHello = handshake.makeClientHello()
        
        // Should be 36 bytes: 1 (version) + 1 (type) + 2 (flags) + 32 (key)
        XCTAssertEqual(clientHello.count, 36)
        
        // Check version
        XCTAssertEqual(clientHello[0], 0x01)
        
        // Check type (clientHello = 0x01)
        XCTAssertEqual(clientHello[1], 0x01)
        
        // Check flags (should be 0x0000)
        XCTAssertEqual(clientHello[2], 0x00)
        XCTAssertEqual(clientHello[3], 0x00)
        
        // Check public key length (bytes 4-35)
        let publicKey = clientHello.subdata(in: 4..<36)
        XCTAssertEqual(publicKey.count, 32)
    }
    
    func testServerHelloFormat() {
        let handshake = BlazeSecureHandshake(role: .server)
        let serverHello = handshake.makeServerHello()
        
        // Should be 36 bytes
        XCTAssertEqual(serverHello.count, 36)
        
        // Check version
        XCTAssertEqual(serverHello[0], 0x01)
        
        // Check type (serverHello = 0x02)
        XCTAssertEqual(serverHello[1], 0x02)
        
        // Check flags
        XCTAssertEqual(serverHello[2], 0x00)
        XCTAssertEqual(serverHello[3], 0x00)
        
        // Check public key length
        let publicKey = serverHello.subdata(in: 4..<36)
        XCTAssertEqual(publicKey.count, 32)
    }
    
    func testLocalPublicKeyData() {
        let handshake = BlazeSecureHandshake(role: .client)
        let publicKeyData = handshake.localPublicKeyData()
        
        // X25519 public keys are 32 bytes
        XCTAssertEqual(publicKeyData.count, 32)
        
        // Should match the key in clientHello
        let clientHello = handshake.makeClientHello()
        let keyFromHello = clientHello.subdata(in: 4..<36)
        XCTAssertEqual(publicKeyData, keyFromHello)
    }
    
    // MARK: - Validation Tests
    
    func testInvalidHandshakeMessageTooShort() {
        var handshake = BlazeSecureHandshake(role: .client)
        let shortMessage = Data([0x01, 0x01]) // Too short
        
        XCTAssertThrowsError(try handshake.processInboundMessage(shortMessage)) { error in
            if case BlazeBinaryError.invalidHandshake(let message) = error {
                XCTAssertTrue(message.contains("too short"))
            } else {
                XCTFail("Expected invalidHandshake error")
            }
        }
    }
    
    func testInvalidHandshakeVersion() {
        var handshake = BlazeSecureHandshake(role: .client)
        var invalidMessage = Data(count: 36)
        invalidMessage[0] = 0x02 // Invalid version (should be 0x01)
        invalidMessage[1] = 0x01 // Valid type
        
        XCTAssertThrowsError(try handshake.processInboundMessage(invalidMessage)) { error in
            if case BlazeBinaryError.invalidHandshake(let message) = error {
                XCTAssertTrue(message.contains("version"))
            } else {
                XCTFail("Expected invalidHandshake error")
            }
        }
    }
    
    func testInvalidHandshakeType() {
        var handshake = BlazeSecureHandshake(role: .client)
        var invalidMessage = Data(count: 36)
        invalidMessage[0] = 0x01 // Valid version
        invalidMessage[1] = 0x99 // Invalid type
        
        XCTAssertThrowsError(try handshake.processInboundMessage(invalidMessage)) { error in
            if case BlazeBinaryError.invalidHandshake(let message) = error {
                XCTAssertTrue(message.contains("type"))
            } else {
                XCTFail("Expected invalidHandshake error")
            }
        }
    }
    
    func testInvalidPublicKeyLength() {
        var handshake = BlazeSecureHandshake(role: .server)
        // Create message with invalid key length (only 30 bytes instead of 32)
        var invalidMessage = Data(count: 34) // 1 (version) + 1 (type) + 2 (flags) + 30 (key) = 34
        invalidMessage[0] = 0x01
        invalidMessage[1] = 0x01 // clientHello — correct for a server to receive

        // This should fail when trying to parse (message too short)
        XCTAssertThrowsError(try handshake.receiveRemotePublicKey(invalidMessage)) { error in
            if case BlazeBinaryError.invalidHandshake(let message) = error {
                XCTAssertTrue(message.contains("too short") || message.contains("length"))
            } else {
                XCTFail("Expected invalidHandshake error")
            }
        }
    }
    
    func testDeriveSessionKeysWithoutRemoteKey() {
        let handshake = BlazeSecureHandshake(role: .client)
        
        // Try to derive keys without receiving remote key
        XCTAssertThrowsError(try handshake.deriveSessionKeys()) { error in
            if case BlazeBinaryError.handshakeFailed(let message) = error {
                XCTAssertTrue(message.contains("Remote public key not received"))
            } else {
                XCTFail("Expected handshakeFailed error")
            }
        }
    }
    
    // MARK: - Custom Config Tests
    
    func testCustomCryptoConfig() throws {
        let customInfo = Data("CustomAppContext".utf8)
        let customSalt = Data("CustomSalt12345678".utf8) // 16 bytes
        let config = BlazeCryptoConfig(
            hkdfInfo: customInfo,
            hkdfSalt: customSalt
        )
        
        var clientHandshake = BlazeSecureHandshake(role: .client, config: config)
        var serverHandshake = BlazeSecureHandshake(role: .server, config: config)
        
        let clientHello = clientHandshake.makeClientHello()
        let serverHello = serverHandshake.makeServerHello()
        
        // Should still derive complementary keys
        let clientKeys = try clientHandshake.processInboundMessage(serverHello)
        let serverKeys = try serverHandshake.processInboundMessage(clientHello)

        // Client's send key should match server's receive key
        XCTAssertEqual(clientKeys.sendKey.withUnsafeBytes { Data($0) }, serverKeys.receiveKey.withUnsafeBytes { Data($0) })
    }
    
    func testDifferentConfigsProduceDifferentKeys() throws {
        // Handshakes with different configs should produce different keys
        let config1 = BlazeCryptoConfig(hkdfInfo: Data("Context1".utf8))
        let config2 = BlazeCryptoConfig(hkdfInfo: Data("Context2".utf8))
        
        var client1 = BlazeSecureHandshake(role: .client, config: config1)
        let server1 = BlazeSecureHandshake(role: .server, config: config1)
        var client2 = BlazeSecureHandshake(role: .client, config: config2)
        let server2 = BlazeSecureHandshake(role: .server, config: config2)
        
        _ = client1.makeClientHello()
        _ = client2.makeClientHello()
        let serverHello1 = server1.makeServerHello()
        let serverHello2 = server2.makeServerHello()
        
        let keys1 = try client1.processInboundMessage(serverHello1)
        let keys2 = try client2.processInboundMessage(serverHello2)
        
        // Keys should be different due to different HKDF info (authentication key uses config.hkdfInfo)
        XCTAssertNotEqual(keys1.authenticationKey.withUnsafeBytes { Data($0) }, keys2.authenticationKey.withUnsafeBytes { Data($0) })
    }
}

