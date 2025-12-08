//
// EchoClient.swift
// BlazeBinary Examples
//
// Simple echo client example using plaintext frames
// Demonstrates basic frame encoding/decoding
//

import Foundation
import BlazeBinary

/// Simple echo client using BlazeBinary plaintext frames.
///
/// This example demonstrates:
/// - Frame encoding for network transport
/// - Frame parsing for receiving data
/// - Basic client-server communication pattern
///
/// Usage:
/// ```swift
/// let client = EchoClient()
/// try client.sendMessage("Hello, server!")
/// let response = try client.receiveMessage()
/// print("Echo: \(response)")
/// ```
public class EchoClient {
    private var parser: BlazeFrameParser
    private var receivedFrames: [Data] = []
    
    public init() {
        self.parser = BlazeFrameParser()
    }
    
    /// Sends a plaintext message as a BlazeBinary frame.
    /// - Parameter message: The message to send
    /// - Returns: Encoded frame data (ready for network transport)
    /// - Throws: `BlazeBinaryError` if encoding fails
    public func sendMessage(_ message: String) throws -> Data {
        // Encode message as BlazeBinary
        let encoder = BlazeBinaryEncoder()
        encoder.encode(message)
        let payload = encoder.encodedData()
        
        // Wrap in frame
        let frame = try BlazeFrameEncoder.encodeFrame(payload)
        return frame
    }
    
    /// Receives a frame and decodes the message.
    /// - Parameter frameData: Raw frame data from network
    /// - Returns: Decoded message string
    /// - Throws: `BlazeBinaryError` if decoding fails
    public func receiveMessage(from frameData: Data) throws -> String {
        // Parse frame
        try parser.append(frameData)
        
        guard let payload = try parser.nextFrame() else {
            throw BlazeBinaryError.needMoreData
        }
        
        // Decode message
        let decoder = BlazeBinaryDecoder(data: payload)
        let message = try decoder.decodeString()
        
        return message
    }
    
    /// Simulates echo server behavior (for testing).
    /// - Parameter frame: Incoming frame
    /// - Returns: Echo frame (same message)
    /// - Throws: `BlazeBinaryError` if processing fails
    public func echoServer(_ frame: Data) throws -> Data {
        let message = try receiveMessage(from: frame)
        return try sendMessage(message)
    }
}

// MARK: - Example Usage

func runEchoClientExample() {
    print("=== BlazeBinary Echo Client Example ===\n")
    
    let client = EchoClient()
    
    // Send a message
    do {
        let message = "Hello, BlazeBinary!"
        print("Sending: \(message)")
        
        let frame = try client.sendMessage(message)
        print("Frame size: \(frame.count) bytes")
        
        // Simulate echo server
        let echoFrame = try client.echoServer(frame)
        print("Received echo frame: \(echoFrame.count) bytes")
        
        // Decode echo
        let echoMessage = try client.receiveMessage(from: echoFrame)
        print("Echo response: \(echoMessage)")
        
        print("\n✅ Echo client example completed successfully!")
    } catch {
        print("❌ Error: \(error)")
    }
}

// Run example if executed directly
if CommandLine.arguments.contains("--run-echo") {
    runEchoClientExample()
}

