//
// SecureChat.swift
// BlazeBinary Examples
//
// Secure chat example with full Diffie-Hellman handshake,
// AEAD encryption, replay protection, and compression
//

import Foundation
import BlazeBinary
import Crypto

/// Secure chat client with full encryption support.
///
/// This example demonstrates:
/// - X25519 Diffie-Hellman handshake
/// - HKDF key derivation
/// - ChaCha20-Poly1305 AEAD encryption
/// - Replay protection
/// - Frame compression
///
/// Usage:
/// ```swift
/// let client = SecureChatClient()
/// let server = SecureChatServer()
///
/// // Handshake
/// let clientHello = try client.initiateHandshake()
/// let serverHello = try server.respondToHandshake(clientHello)
/// try client.completeHandshake(serverHello)
///
/// // Send encrypted message
/// let encrypted = try client.sendEncryptedMessage("Secret message")
/// let decrypted = try server.receiveEncryptedMessage(encrypted)
/// ```
public class SecureChatClient {
    private var handshake: BlazeSecureHandshake?
    private var session: BlazeSecureSession?
    private var messageCounter: UInt64 = 0
    
    /// Initiates a secure handshake.
    /// - Returns: ClientHello frame (ready to send to server)
    /// - Throws: `BlazeBinaryError` if handshake fails
    public func initiateHandshake() throws -> Data {
        var clientHandshake = BlazeSecureHandshake(role: .client)
        let clientHello = clientHandshake.makeOutboundMessage()
        self.handshake = clientHandshake
        
        // Wrap in handshake frame
        return try BlazeFrameEncoder.encodeHandshakeFrame(clientHello)
    }
    
    /// Completes handshake after receiving server response.
    /// - Parameter serverHelloFrame: ServerHello frame from server
    /// - Throws: `BlazeBinaryError` if handshake fails
    public func completeHandshake(_ serverHelloFrame: Data) throws {
        guard var handshake = self.handshake else {
            throw BlazeBinaryError.handshakeFailed("Handshake not initiated")
        }
        
        // Parse serverHello frame
        let parser = BlazeFrameParser()
        try parser.append(serverHelloFrame)
        guard let serverHelloPayload = try parser.nextFrame() else {
            throw BlazeBinaryError.handshakeFailed("Failed to parse serverHello frame")
        }
        
        // Process serverHello and derive keys
        let keys = try handshake.processInboundMessage(serverHelloPayload)
        self.session = BlazeSecureSession(keyMaterial: keys)
        self.handshake = nil // Handshake complete
    }
    
    /// Sends an encrypted message.
    /// - Parameter message: Plaintext message to encrypt
    /// - Returns: Encrypted frame (ready for network transport)
    /// - Throws: `BlazeBinaryError` if encryption fails
    public func sendEncryptedMessage(_ message: String) throws -> Data {
        guard var session = self.session else {
            throw BlazeBinaryError.invalidSession("Session not established")
        }
        
        // Encode message
        let encoder = BlazeBinaryEncoder()
        encoder.encode(message)
        let plaintext = encoder.encodedData()
        
        // Encrypt and wrap in frame
        let encryptedFrame = try BlazeFrameEncoder.encodeEncryptedFrame(plaintext, session: &session)
        self.session = session // Update session state
        
        messageCounter += 1
        return encryptedFrame
    }
    
    /// Receives and decrypts a message.
    /// - Parameter encryptedFrame: Encrypted frame from network
    /// - Returns: Decrypted message string
    /// - Throws: `BlazeBinaryError` if decryption fails
    public func receiveEncryptedMessage(_ encryptedFrame: Data) throws -> String {
        guard var session = self.session else {
            throw BlazeBinaryError.invalidSession("Session not established")
        }
        
        // Parse and decrypt frame
        let parser = BlazeFrameParser(secureSession: session)
        try parser.append(encryptedFrame)
        
        guard let decryptedPayload = try parser.nextFrame() else {
            throw BlazeBinaryError.encryptionFailed("Failed to decrypt frame")
        }
        
        // Decode message
        let decoder = BlazeBinaryDecoder(data: decryptedPayload)
        let message = try decoder.decodeString()
        
        self.session = parser.secureSession // Update session state
        
        return message
    }
}

/// Secure chat server with full encryption support.
public class SecureChatServer {
    private var handshake: BlazeSecureHandshake?
    private var session: BlazeSecureSession?
    
    /// Responds to client handshake.
    /// - Parameter clientHelloFrame: ClientHello frame from client
    /// - Returns: ServerHello frame (ready to send to client)
    /// - Throws: `BlazeBinaryError` if handshake fails
    public func respondToHandshake(_ clientHelloFrame: Data) throws -> Data {
        // Parse clientHello frame
        let parser = BlazeFrameParser()
        try parser.append(clientHelloFrame)
        guard let clientHelloPayload = try parser.nextFrame() else {
            throw BlazeBinaryError.handshakeFailed("Failed to parse clientHello frame")
        }
        
        // Create server handshake and process clientHello
        var serverHandshake = BlazeSecureHandshake(role: .server)
        let keys = try serverHandshake.processInboundMessage(clientHelloPayload)
        
        // Create serverHello
        let serverHello = serverHandshake.makeOutboundMessage()
        self.handshake = serverHandshake
        self.session = BlazeSecureSession(keyMaterial: keys)
        
        // Wrap in handshake frame
        return try BlazeFrameEncoder.encodeHandshakeFrame(serverHello)
    }
    
    /// Receives and decrypts a message.
    /// - Parameter encryptedFrame: Encrypted frame from client
    /// - Returns: Decrypted message string
    /// - Throws: `BlazeBinaryError` if decryption fails
    public func receiveEncryptedMessage(_ encryptedFrame: Data) throws -> String {
        guard var session = self.session else {
            throw BlazeBinaryError.invalidSession("Session not established")
        }
        
        // Parse and decrypt frame
        let parser = BlazeFrameParser(secureSession: session)
        try parser.append(encryptedFrame)
        
        guard let decryptedPayload = try parser.nextFrame() else {
            throw BlazeBinaryError.encryptionFailed("Failed to decrypt frame")
        }
        
        // Decode message
        let decoder = BlazeBinaryDecoder(data: decryptedPayload)
        let message = try decoder.decodeString()
        
        self.session = parser.secureSession // Update session state
        
        return message
    }
    
    /// Sends an encrypted message.
    /// - Parameter message: Plaintext message to encrypt
    /// - Returns: Encrypted frame (ready for network transport)
    /// - Throws: `BlazeBinaryError` if encryption fails
    public func sendEncryptedMessage(_ message: String) throws -> Data {
        guard var session = self.session else {
            throw BlazeBinaryError.invalidSession("Session not established")
        }
        
        // Encode message
        let encoder = BlazeBinaryEncoder()
        encoder.encode(message)
        let plaintext = encoder.encodedData()
        
        // Encrypt and wrap in frame
        let encryptedFrame = try BlazeFrameEncoder.encodeEncryptedFrame(plaintext, session: &session)
        self.session = session // Update session state
        
        return encryptedFrame
    }
}

// MARK: - Example Usage

func runSecureChatExample() {
    print("=== BlazeBinary Secure Chat Example ===\n")
    
    let client = SecureChatClient()
    let server = SecureChatServer()
    
    do {
        // Step 1: Handshake
        print("1. Initiating handshake...")
        let clientHello = try client.initiateHandshake()
        print("   ClientHello sent: \(clientHello.count) bytes")
        
        print("2. Server responding...")
        let serverHello = try server.respondToHandshake(clientHello)
        print("   ServerHello sent: \(serverHello.count) bytes")
        
        print("3. Client completing handshake...")
        try client.completeHandshake(serverHello)
        print("   ✅ Handshake complete!")
        
        // Step 2: Encrypted communication
        print("\n4. Sending encrypted message...")
        let message = "This is a secret message!"
        let encrypted = try client.sendEncryptedMessage(message)
        print("   Encrypted frame: \(encrypted.count) bytes")
        
        print("5. Server decrypting...")
        let decrypted = try server.receiveEncryptedMessage(encrypted)
        print("   Decrypted: \(decrypted)")
        
        // Step 3: Server response
        print("\n6. Server sending encrypted response...")
        let response = "Message received: \(decrypted)"
        let encryptedResponse = try server.sendEncryptedMessage(response)
        print("   Encrypted response: \(encryptedResponse.count) bytes")
        
        print("7. Client decrypting response...")
        let decryptedResponse = try client.receiveEncryptedMessage(encryptedResponse)
        print("   Response: \(decryptedResponse)")
        
        print("\n✅ Secure chat example completed successfully!")
        print("   - Handshake: X25519 key exchange")
        print("   - Encryption: ChaCha20-Poly1305 AEAD")
        print("   - Replay protection: Enabled")
        
    } catch {
        print("❌ Error: \(error)")
    }
}

// Run example if executed directly
if CommandLine.arguments.contains("--run-secure-chat") {
    runSecureChatExample()
}

