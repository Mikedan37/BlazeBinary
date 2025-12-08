//
// HandshakeFuzzTests.swift
// BlazeBinary
//
// Copyright (c) 2025 Michael Danylchuk
// MIT License
//

import XCTest
import Foundation
import Crypto
@testable import BlazeBinary

/// Fuzzing tests for handshake protocol.
///
/// Tests randomized corrupted inputs to ensure no crashes or undefined behavior,
/// and that all invalid inputs are rejected gracefully.
final class HandshakeFuzzTests: XCTestCase {
    
    // MARK: - Cross-Platform Random Helpers
    
    /// Generate random bytes (replaces arc4random_buf)
    private func randomBytes(count: Int) -> Data {
        let randomKey = SymmetricKey(size: .bits256) // 32 bytes
        let randomData = randomKey.withUnsafeBytes { Data($0) }
        // If we need more bytes, generate multiple keys
        if count <= randomData.count {
            return randomData.prefix(count)
        }
        var result = randomData
        while result.count < count {
            let moreKey = SymmetricKey(size: .bits256)
            let moreData = moreKey.withUnsafeBytes { Data($0) }
            result.append(moreData)
        }
        return result.prefix(count)
    }
    
    /// Generate random number in range [0, upperBound) (replaces arc4random_uniform)
    private func randomUniform(_ upperBound: UInt32) -> UInt32 {
        guard upperBound > 0 else { return 0 }
        // Generate random bytes and convert to UInt32
        let randomData = randomBytes(count: 4)
        let value = randomData.withUnsafeBytes { $0.load(as: UInt32.self) }
        return value % upperBound
    }
    
    // MARK: - Public Key Fuzzing
    
    func testFuzzPublicKeys() throws {
        // Fuzz public keys with random data
        for _ in 0..<100 {
            var server = BlazeSecureHandshake(role: .server)
            
            // Generate random public key data
            let randomKey = randomBytes(count: 32)
            
            let randomMessage = makeHandshakeMessage(type: 0x01, publicKey: randomKey)
            
            // Should either accept (valid key) or reject gracefully (invalid key)
            // Must not crash
            _ = try? server.receiveRemotePublicKey(randomMessage)
            
            // If accepted, derivation might fail
            _ = try? server.deriveSessionKeys()
            // Either succeeds or fails gracefully - no crash
        }
    }
    
    func testFuzzPublicKeySizes() throws {
        // Fuzz with various key sizes
        let sizes = [0, 1, 16, 31, 32, 33, 64, 128, 256]
        
        for size in sizes {
            var server = BlazeSecureHandshake(role: .server)
            
            let randomKey = size > 0 ? randomBytes(count: size) : Data()
            
            let message = makeHandshakeMessage(type: 0x01, publicKey: randomKey)
            
            // Must not crash
            _ = try? server.receiveRemotePublicKey(message)
            // Either succeeds or fails gracefully
        }
    }
    
    // MARK: - Nonce Fuzzing
    
    func testFuzzNonces() throws {
        var session = try createTestSession()
        let payload = Data("Test message".utf8)
        let encrypted = try session.makeEncryptedFrame(from: payload)
        
        // Fuzz nonce bytes (bytes 1-12)
        for _ in 0..<50 {
            var fuzzed = encrypted
            let nonceStart = 1
            let nonceEnd = 13
            
            // Randomly flip bits in nonce
            for i in nonceStart..<nonceEnd {
                if randomUniform(2) == 1 {
                    fuzzed[i] ^= UInt8(randomUniform(256))
                }
            }
            
            // Must not crash, should reject gracefully
            _ = try? session.decryptFramePayload(fuzzed) // Either succeeds or fails gracefully
        }
    }
    
    // MARK: - Ciphertext Fuzzing
    
    func testFuzzCiphertextBlocks() throws {
        var session = try createTestSession()
        let payload = Data("Test message for fuzzing".utf8)
        let encrypted = try session.makeEncryptedFrame(from: payload)
        
        // Fuzz ciphertext (bytes 13 to tag start)
        let ciphertextStart = 13
        let tagStart = encrypted.count - 16
        
        for _ in 0..<50 {
            var fuzzed = encrypted
            
            // Randomly corrupt ciphertext
            if tagStart > ciphertextStart {
                for i in ciphertextStart..<tagStart {
                    if randomUniform(4) == 0 { // 25% chance per byte
                        fuzzed[i] ^= UInt8(randomUniform(256))
                    }
                }
            }
            
            // Must not crash, should reject gracefully
            _ = try? session.decryptFramePayload(fuzzed) // Either succeeds or fails gracefully
        }
    }
    
    func testFuzzTag() throws {
        var session = try createTestSession()
        let payload = Data("Test message".utf8)
        let encrypted = try session.makeEncryptedFrame(from: payload)
        
        // Fuzz tag (last 16 bytes)
        for _ in 0..<50 {
            var fuzzed = encrypted
            let tagStart = fuzzed.count - 16
            
            // Randomly flip bits in tag
            for i in tagStart..<fuzzed.count {
                if randomUniform(2) == 1 {
                    fuzzed[i] ^= UInt8(randomUniform(256))
                }
            }
            
            // Must not crash, should reject gracefully
            _ = try? session.decryptFramePayload(fuzzed) // Either succeeds or fails gracefully
        }
    }
    
    // MARK: - Entire Handshake Message Fuzzing
    
    func testFuzzHandshakeMessages() throws {
        // Fuzz entire handshake messages
        for _ in 0..<100 {
            var server = BlazeSecureHandshake(role: .server)
            
            // Generate random message of various sizes
            let size = Int(randomUniform(100)) + 1
            let randomMessage = randomBytes(count: size)
            
            // Must not crash
            _ = try? server.receiveRemotePublicKey(randomMessage)
            // Either succeeds or fails gracefully
        }
    }
    
    func testFuzzHandshakeMessageHeaders() throws {
        // Fuzz handshake message headers specifically
        var server = BlazeSecureHandshake(role: .server)
        
        for _ in 0..<50 {
            var message = Data()
            
            // Random version
            message.append(UInt8(randomUniform(256)))
            // Random type
            message.append(UInt8(randomUniform(256)))
            // Random flags
            message.append(UInt8(randomUniform(256)))
            message.append(UInt8(randomUniform(256)))
            // Random key data
            let keySize = Int(randomUniform(64))
            let randomKey = keySize > 0 ? randomBytes(count: keySize) : Data()
            message.append(randomKey)
            
            // Must not crash
            _ = try? server.receiveRemotePublicKey(message)
        }
    }
    
    // MARK: - Frame Fuzzing
    
    func testFuzzEncryptedFrames() throws {
        var session = try createTestSession()
        let payload = Data("Test message".utf8)
        let encrypted = try session.makeEncryptedFrame(from: payload)
        
        // Fuzz entire encrypted frames
        for _ in 0..<100 {
            var fuzzed = encrypted
            
            // Randomly corrupt random bytes
            for i in 0..<fuzzed.count {
                if randomUniform(10) == 0 { // 10% chance per byte
                    fuzzed[i] ^= UInt8(randomUniform(256))
                }
            }
            
            // Must not crash
            _ = try? session.decryptFramePayload(fuzzed) // Either succeeds or fails gracefully
        }
    }
    
    func testFuzzFrameSizes() throws {
        var session = try createTestSession()
        
        // Test various frame sizes
        for _ in 0..<20 {
            let size = Int(randomUniform(1000)) + 1
            let randomFrame = randomBytes(count: size)
            
            // Must not crash
            let result = try? session.decryptFramePayload(randomFrame)
            _ = result
        }
    }
    
    func testFuzzTruncatedFrames() throws {
        var session = try createTestSession()
        let payload = Data("Test message for truncation".utf8)
        let encrypted = try session.makeEncryptedFrame(from: payload)
        
        // Fuzz by truncating at various points
        for _ in 0..<50 {
            let truncatePoint = Int(randomUniform(UInt32(encrypted.count)))
            let truncated = encrypted.prefix(truncatePoint)
            
            // Must not crash
            let result = try? session.decryptFramePayload(truncated)
            _ = result
        }
    }
    
    // MARK: - Edge Cases
    
    func testFuzzAllZeroes() throws {
        // Test with all-zero inputs
        var server = BlazeSecureHandshake(role: .server)
        let zeroMessage = Data(repeating: 0x00, count: 36)
        
        // Must not crash
        _ = try? server.receiveRemotePublicKey(zeroMessage)
    }
    
    func testFuzzAllOnes() throws {
        // Test with all-ones inputs
        var server = BlazeSecureHandshake(role: .server)
        let onesMessage = Data(repeating: 0xFF, count: 36)
        
        // Must not crash
        _ = try? server.receiveRemotePublicKey(onesMessage)
    }
    
    func testFuzzRepeatingPatterns() throws {
        // Test with repeating patterns
        let patterns: [UInt8] = [0x00, 0x01, 0x42, 0xAA, 0xFF]
        
        for pattern in patterns {
            var server = BlazeSecureHandshake(role: .server)
            let patternMessage = Data(repeating: pattern, count: 36)
            
            // Must not crash
            _ = try? server.receiveRemotePublicKey(patternMessage)
        }
    }
    
    // MARK: - Helper Methods
    
    private func createTestSession() throws -> BlazeSecureSession {
        var alice = BlazeSecureHandshake(role: .client)
        var bob = BlazeSecureHandshake(role: .server)
        
        try bob.receiveRemotePublicKey(alice.makeClientHello())
        try alice.receiveRemotePublicKey(bob.makeServerHello())
        
        let keys = try alice.deriveSessionKeys()
        return BlazeSecureSession(keyMaterial: keys)
    }
    
    private func makeHandshakeMessage(type: UInt8, publicKey: Data) -> Data {
        var message = Data()
        message.append(0x01) // version
        message.append(type)
        message.append(contentsOf: [0x00, 0x00]) // flags
        message.append(publicKey)
        return message
    }
}

