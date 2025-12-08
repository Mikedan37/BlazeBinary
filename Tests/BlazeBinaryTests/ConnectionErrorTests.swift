//
//  ConnectionErrorTests.swift
//  BlazeBinary
//
//  Copyright (c) 2025 Michael Danylchuk
//  MIT License
//

import XCTest
@testable import BlazeBinary

final class ConnectionErrorTests: XCTestCase {
    
    func testDisconnectReasonRawValues() {
        XCTAssertEqual(DisconnectReason.noError.rawValue, 0x00)
        XCTAssertEqual(DisconnectReason.protocolError.rawValue, 0x01)
        XCTAssertEqual(DisconnectReason.cryptoError.rawValue, 0x03)
        XCTAssertEqual(DisconnectReason.frameTooLarge.rawValue, 0x04)
        XCTAssertEqual(DisconnectReason.replayDetected.rawValue, 0x07)
    }
    
    func testDisconnectReasonEquality() {
        XCTAssertEqual(DisconnectReason.noError, DisconnectReason.noError)
        XCTAssertEqual(DisconnectReason.protocolError, DisconnectReason.protocolError)
        XCTAssertNotEqual(DisconnectReason.noError, DisconnectReason.protocolError)
    }
    
    func testProtocolErrorEquality() {
        let error1 = ProtocolError.invalidFrameFormat("test")
        let error2 = ProtocolError.invalidFrameFormat("test")
        let error3 = ProtocolError.invalidFrameFormat("different")
        
        XCTAssertEqual(error1, error2)
        XCTAssertNotEqual(error1, error3)
    }
    
    func testCryptoErrorEquality() {
        XCTAssertEqual(CryptoError.authenticationFailed, CryptoError.authenticationFailed)
        XCTAssertEqual(CryptoError.invalidNonce, CryptoError.invalidNonce)
        XCTAssertNotEqual(CryptoError.authenticationFailed, CryptoError.invalidNonce)
        
        let error1 = CryptoError.decryptionFailed("test")
        let error2 = CryptoError.decryptionFailed("test")
        let error3 = CryptoError.decryptionFailed("different")
        
        XCTAssertEqual(error1, error2)
        XCTAssertNotEqual(error1, error3)
    }
    
    func testBlazeBinaryErrorToDisconnectReason() {
        let error1 = BlazeBinaryError.invalidFrameLength
        XCTAssertEqual(error1.disconnectReason, .frameTooLarge)
        
        let error2 = BlazeBinaryError.handshakeFailed("test")
        XCTAssertEqual(error2.disconnectReason, .invalidHandshake)
        
        let error3 = BlazeBinaryError.encryptionFailed("test")
        XCTAssertEqual(error3.disconnectReason, .cryptoError)
    }
    
    func testBlazeBinaryErrorToProtocolError() {
        let error1 = BlazeBinaryError.invalidFrameLength
        let protocolError1 = error1.protocolError
        XCTAssertNotNil(protocolError1)
        
        let error2 = BlazeBinaryError.handshakeFailed("test")
        let protocolError2 = error2.protocolError
        XCTAssertNotNil(protocolError2)
        if case .handshakeFailure(let msg) = protocolError2! {
            XCTAssertEqual(msg, "test")
        }
    }
    
    func testBlazeBinaryErrorToCryptoError() {
        let error1 = BlazeBinaryError.encryptionFailed("authentication failed")
        let cryptoError1 = error1.cryptoError
        XCTAssertNotNil(cryptoError1)
        XCTAssertEqual(cryptoError1, .authenticationFailed)
        
        let error2 = BlazeBinaryError.encryptionFailed("decryption error")
        let cryptoError2 = error2.cryptoError
        XCTAssertNotNil(cryptoError2)
        if case .decryptionFailed(let msg) = cryptoError2! {
            XCTAssertTrue(msg.contains("decryption"))
        }
    }
}

