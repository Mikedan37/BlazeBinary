//
// BlazeTransportExample.swift
// BlazeBinary Examples
//
// Example implementation of BlazeTransport protocol
// Demonstrates lightweight transport layer for BlazeBinary
//

import Foundation
import BlazeBinary

// MARK: - BlazeTransport Protocol Implementation

/// Minimal transport protocol for BlazeBinary frames
/// Reduces overhead from 54 bytes (TCP) to 8 bytes (BlazeTransport)
public struct BlazeTransportPacket {
    /// Packet flags
    public struct Flags: OptionSet {
        public let rawValue: UInt8
        
        public init(rawValue: UInt8) {
            self.rawValue = rawValue
        }
        
        public static let ack = Flags(rawValue: 1 << 0)  // Acknowledgment
        public static let fin = Flags(rawValue: 1 << 1)  // Finish (close)
        public static let rst = Flags(rawValue: 1 << 2)  // Reset
        
        public var isAck: Bool { contains(.ack) }
        public var isFin: Bool { contains(.fin) }
        public var isRst: Bool { contains(.rst) }
    }
    
    public let flags: Flags
    public let sequenceNumber: UInt32
    public let acknowledgmentNumber: UInt32?  // Only if ACK flag set
    public let windowSize: UInt32?              // Only if ACK flag set
    public let frameData: Data                 // BlazeBinary frame
    
    /// Creates a data packet (no ACK)
    public init(sequenceNumber: UInt32, frameData: Data) {
        self.flags = []
        self.sequenceNumber = sequenceNumber
        self.acknowledgmentNumber = nil
        self.windowSize = nil
        self.frameData = frameData
    }
    
    /// Creates an ACK packet
    public init(sequenceNumber: UInt32, ackNumber: UInt32, windowSize: UInt32) {
        self.flags = .ack
        self.sequenceNumber = sequenceNumber
        self.acknowledgmentNumber = ackNumber
        self.windowSize = windowSize
        self.frameData = Data()
    }
    
    /// Creates a FIN packet
    public init(sequenceNumber: UInt32, isFin: Bool) {
        self.flags = isFin ? .fin : []
        self.sequenceNumber = sequenceNumber
        self.acknowledgmentNumber = nil
        self.windowSize = nil
        self.frameData = Data()
    }
    
    /// Encodes packet to wire format
    public func encode() -> Data {
        var packet = Data()
        
        // Flags (1 byte)
        packet.append(flags.rawValue)
        
        // Sequence number (4 bytes, big-endian)
        var seqNum = sequenceNumber.bigEndian
        packet.append(contentsOf: withUnsafeBytes(of: &seqNum) { Data($0) })
        
        // ACK number and window (only if ACK flag set)
        if flags.contains(.ack), let ackNum = acknowledgmentNumber, let window = windowSize {
            var ackNumBE = ackNum.bigEndian
            packet.append(contentsOf: withUnsafeBytes(of: &ackNumBE) { Data($0) })
            
            var windowBE = window.bigEndian
            packet.append(contentsOf: withUnsafeBytes(of: &windowBE) { Data($0) })
        }
        
        // Frame data
        packet.append(frameData)
        
        return packet
    }
    
    /// Decodes packet from wire format
    public static func decode(from data: Data) throws -> BlazeTransportPacket {
        guard data.count >= 5 else {
            throw BlazeBinaryError.truncated
        }
        
        let flags = Flags(rawValue: data[0])
        
        // Sequence number (bytes 1-4)
        let seqNum = data.withUnsafeBytes { bytes in
            var value: UInt32 = 0
            value |= UInt32(bytes[1]) << 24
            value |= UInt32(bytes[2]) << 16
            value |= UInt32(bytes[3]) << 8
            value |= UInt32(bytes[4])
            return UInt32(bigEndian: value)
        }
        
        var offset = 5
        
        // ACK number and window (if ACK flag set)
        var ackNum: UInt32? = nil
        var window: UInt32? = nil
        
        if flags.contains(.ack) {
            guard data.count >= offset + 8 else {
                throw BlazeBinaryError.truncated
            }
            
            ackNum = data.withUnsafeBytes { bytes in
                var value: UInt32 = 0
                value |= UInt32(bytes[offset]) << 24
                value |= UInt32(bytes[offset + 1]) << 16
                value |= UInt32(bytes[offset + 2]) << 8
                value |= UInt32(bytes[offset + 3])
                return UInt32(bigEndian: value)
            }
            offset += 4
            
            window = data.withUnsafeBytes { bytes in
                var value: UInt32 = 0
                value |= UInt32(bytes[offset]) << 24
                value |= UInt32(bytes[offset + 1]) << 16
                value |= UInt32(bytes[offset + 2]) << 8
                value |= UInt32(bytes[offset + 3])
                return UInt32(bigEndian: value)
            }
            offset += 4
        }
        
        // Frame data (remaining bytes)
        let frameData = data.subdata(in: offset..<data.count)
        
        return BlazeTransportPacket(
            flags: flags,
            sequenceNumber: seqNum,
            acknowledgmentNumber: ackNum,
            windowSize: window,
            frameData: frameData
        )
    }
    
    private init(flags: Flags, sequenceNumber: UInt32, acknowledgmentNumber: UInt32?, windowSize: UInt32?, frameData: Data) {
        self.flags = flags
        self.sequenceNumber = sequenceNumber
        self.acknowledgmentNumber = acknowledgmentNumber
        self.windowSize = windowSize
        self.frameData = frameData
    }
}

// MARK: - BlazeTransport Connection

/// Simplified transport connection for BlazeBinary frames
public class BlazeTransportConnection {
    private var sendSequenceNumber: UInt32
    private var receiveSequenceNumber: UInt32
    private var lastAcknowledgedSequence: UInt32
    private var windowSize: UInt32
    private var unacknowledgedFrames: [UInt32: Data] = [:]
    
    public init(initialSequenceNumber: UInt32? = nil) {
        // Use random initial sequence number to prevent hijacking
        self.sendSequenceNumber = initialSequenceNumber ?? UInt32.random(in: 1...UInt32.max)
        self.receiveSequenceNumber = 0
        self.lastAcknowledgedSequence = 0
        self.windowSize = 16  // Default window: 16 frames
    }
    
    /// Sends a BlazeBinary frame over the transport
    public func sendFrame(_ frame: Data) throws -> BlazeTransportPacket {
        // Check window
        let unackedCount = sendSequenceNumber - lastAcknowledgedSequence
        guard unackedCount < windowSize else {
            throw BlazeBinaryError.oversizedFrame  // Window full
        }
        
        // Create packet
        let packet = BlazeTransportPacket(
            sequenceNumber: sendSequenceNumber,
            frameData: frame
        )
        
        // Store for retransmission
        unacknowledgedFrames[sendSequenceNumber] = frame
        
        // Increment sequence number
        sendSequenceNumber += 1
        
        return packet
    }
    
    /// Receives a transport packet and extracts the frame
    public func receivePacket(_ packet: BlazeTransportPacket) throws -> (frame: Data?, ack: BlazeTransportPacket?) {
        var ackPacket: BlazeTransportPacket? = nil
        
        // Handle ACK
        if packet.flags.contains(.ack), let ackNum = packet.acknowledgmentNumber {
            // Update last acknowledged sequence
            if ackNum > lastAcknowledgedSequence {
                // Remove acknowledged frames from retransmission buffer
                for seq in lastAcknowledgedSequence..<ackNum {
                    unacknowledgedFrames.removeValue(forKey: seq)
                }
                lastAcknowledgedSequence = ackNum
            }
            
            // Update window size
            if let window = packet.windowSize {
                windowSize = window
            }
        }
        
        // Handle data frame
        if !packet.frameData.isEmpty {
            // Validate sequence number (simple check - should be next expected)
            // In production, handle out-of-order frames
            if packet.sequenceNumber == receiveSequenceNumber {
                receiveSequenceNumber += 1
                
                // Generate ACK
                ackPacket = BlazeTransportPacket(
                    sequenceNumber: sendSequenceNumber,
                    ackNumber: receiveSequenceNumber - 1,
                    windowSize: windowSize
                )
                
                return (packet.frameData, ackPacket)
            } else {
                // Out-of-order frame - buffer it (simplified: just reject)
                throw BlazeBinaryError.decodeFailed("Out-of-order frame")
            }
        }
        
        return (nil, ackPacket)
    }
    
    /// Handles FIN packet
    public func handleFin() -> BlazeTransportPacket? {
        // Send FIN-ACK
        return BlazeTransportPacket(
            sequenceNumber: sendSequenceNumber,
            ackNumber: receiveSequenceNumber,
            windowSize: windowSize
        )
    }
}

// MARK: - Example Usage

func demonstrateBlazeTransport() {
    print("=== BlazeTransport Example ===\n")
    
    // Create connection
    let connection = BlazeTransportConnection()
    
    // Encode a BlazeBinary message
    let encoder = BlazeBinaryEncoder()
    encoder.encode("Hello, BlazeTransport!")
    let payload = encoder.encodedData()
    
    // Create BlazeBinary frame
    let frame = try! BlazeFrameEncoder.encodeFrame(payload)
    print("BlazeBinary frame size: \(frame.count) bytes")
    
    // Send via transport
    let packet = try! connection.sendFrame(frame)
    let packetData = packet.encode()
    print("Transport packet size: \(packetData.count) bytes")
    print("Overhead: \(packetData.count - frame.count) bytes (vs TCP's 54 bytes)")
    
    // Simulate receiving
    let receivedPacket = try! BlazeTransportPacket.decode(from: packetData)
    let (receivedFrame, ack) = try! connection.receivePacket(receivedPacket)
    
    if let frame = receivedFrame {
        print("Received frame: \(frame.count) bytes")
        
        // Parse frame
        let parser = BlazeFrameParser()
        try! parser.append(frame)
        if let payload = try! parser.nextFrame() {
            let decoder = BlazeBinaryDecoder(data: payload)
            let message = try! decoder.decodeString()
            print("Decoded message: \(message)")
        }
    }
    
    if let ack = ack {
        print("ACK generated: seq=\(ack.sequenceNumber), ack=\(ack.acknowledgmentNumber ?? 0)")
    }
    
    print("\n✅ BlazeTransport example completed!")
}

// Run example if executed directly
if CommandLine.arguments.contains("--run-transport") {
    demonstrateBlazeTransport()
}

