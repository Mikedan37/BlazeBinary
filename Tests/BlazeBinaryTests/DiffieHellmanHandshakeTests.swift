//
//  DiffieHellmanHandshakeTests.swift
//  BlazeBinary
//
//  Copyright (c) 2025 Michael Danylchuk
//  MIT License
//

import XCTest
@testable import BlazeBinary

final class DiffieHellmanHandshakeTests: XCTestCase {
    
    func testHandshakeKeyAgreement() throws {
        // Client side
        var clientHandshake = BlazeSecureHandshake(role: .client)
        let clientHello = clientHandshake.makeClientHello()
        
        // Server side
        var serverHandshake = BlazeSecureHandshake(role: .server)
        let serverHello = serverHandshake.makeServerHello()
        
        // Exchange public keys
        try clientHandshake.receiveRemotePublicKey(serverHello)
        try serverHandshake.receiveRemotePublicKey(clientHello)
        
        // Derive session keys (should produce matching keys)
        let clientKeys = try clientHandshake.deriveSessionKeys()
        let serverKeys = try serverHandshake.deriveSessionKeys()
        
        // Client's send key should match server's receive key (and vice versa)
        XCTAssertEqual(
            clientKeys.sendKey.withUnsafeBytes { Data($0) },
            serverKeys.receiveKey.withUnsafeBytes { Data($0) }
        )
        XCTAssertEqual(
            clientKeys.receiveKey.withUnsafeBytes { Data($0) },
            serverKeys.sendKey.withUnsafeBytes { Data($0) }
        )
        XCTAssertEqual(
            clientKeys.authenticationKey.withUnsafeBytes { Data($0) },
            serverKeys.authenticationKey.withUnsafeBytes { Data($0) }
        )
    }
    
    func testHandshakeMismatchedKeys() throws {
        var clientHandshake = BlazeSecureHandshake(role: .client)
        let clientHello = clientHandshake.makeClientHello()
        
        var serverHandshake = BlazeSecureHandshake(role: .server)
        let serverHello = serverHandshake.makeServerHello()
        
        // Exchange keys correctly
        try clientHandshake.receiveRemotePublicKey(serverHello)
        try serverHandshake.receiveRemotePublicKey(clientHello)
        
        // Create a different server handshake with different keys
        var differentServer = BlazeSecureHandshake(role: .server)
        let differentServerHello = differentServer.makeServerHello()
        
        // Client receives different key
        var clientWithDifferentKey = BlazeSecureHandshake(role: .client)
        try clientWithDifferentKey.receiveRemotePublicKey(differentServerHello)
        try differentServer.receiveRemotePublicKey(clientWithDifferentKey.makeClientHello())
        
        // Keys should be different
        let originalKeys = try clientHandshake.deriveSessionKeys()
        let differentKeys = try clientWithDifferentKey.deriveSessionKeys()
        
        let originalEnc = originalKeys.encryptionKey.withUnsafeBytes { Data($0) }
        let differentEnc = differentKeys.encryptionKey.withUnsafeBytes { Data($0) }
        
        XCTAssertNotEqual(originalEnc, differentEnc)
    }
    
    func testHandshakeWithoutRemoteKey() {
        let handshake = BlazeSecureHandshake(role: .client)
        
        // Should fail if remote key not received
        XCTAssertThrowsError(try handshake.deriveSessionKeys()) { error in
            XCTAssertTrue(error is BlazeBinaryError)
        }
    }
    
    func testHandshakeInvalidPublicKey() {
        var handshake = BlazeSecureHandshake(role: .client)
        
        // Invalid key (wrong length)
        let invalidKey = Data([0x01, 0x02, 0x03]) // Too short
        
        XCTAssertThrowsError(try handshake.receiveRemotePublicKey(invalidKey)) { error in
            XCTAssertTrue(error is BlazeBinaryError)
        }
    }
}

