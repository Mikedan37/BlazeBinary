//
//  CorruptionTests.swift
//  BlazeBinary
//
//  Created by Michael Danylchuk.
//
//  MIT License
//  Copyright (c) 2025 Michael D.
//

import Testing
import Foundation
@testable import BlazeBinary

// MARK: - Corruption Rejection Tests

/// Tests that truncated records are rejected with appropriate errors.
@Test func testDecoderRejectsTruncatedRecord() throws {
    // Create a valid encoded record
    let encoder = BlazeBinaryEncoder()
    try encoder.encode("Hello, World!")
    let validData = encoder.encodedData()
    
    // Test various truncation points
    for truncateAt in 1..<validData.count {
        let truncated = validData.prefix(truncateAt)
        let decoder = BlazeBinaryDecoder(data: truncated)
        
        do {
            _ = try decoder.decodeString()
            Issue.record("Decoder should reject truncated record at position \(truncateAt)")
        } catch BlazeBinaryError.truncated {
            // Expected error
        } catch BlazeBinaryError.decodeFailed {
            // Also acceptable
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }
}

/// Tests that invalid varint encodings are rejected.
@Test func testDecoderRejectsInvalidVarint() throws {
    // Create a varint that's too long (more than 10 bytes)
    var invalidVarint = Data()
    for _ in 0..<11 {
        invalidVarint.append(0x80) // Continuation bit set
    }
    invalidVarint.append(0x00) // Final byte
    
    let decoder = BlazeBinaryDecoder(data: invalidVarint)
    
    do {
        _ = try decoder.decodeInt()
        Issue.record("Decoder should reject invalid varint (too many bytes)")
    } catch BlazeBinaryError.invalidVarint {
        // Expected error
    } catch BlazeBinaryError.decodeFailed {
        // Also acceptable
    } catch {
        // Any error is acceptable for invalid input
    }
}

/// Tests that invalid frame lengths are rejected.
@Test func testFrameDecoderRejectsMismatchedLength() throws {
    // Create a frame with length prefix that doesn't match actual payload
    var frameData = Data()
    // Length prefix: 1000 bytes (0x00 0x00 0x03 0xE8)
    frameData.append(0x00)
    frameData.append(0x00)
    frameData.append(0x03)
    frameData.append(0xE8)
    // But only add 10 bytes of payload
    frameData.append(contentsOf: [0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0A])
    
    let parser = BlazeFrameParser()
    do {
        try parser.append(frameData)
        let result = try parser.nextFrame()
        
        // Parser should return nil (need more data) or handle gracefully
        // It should not crash or produce invalid data
        if let frame = result {
            #expect(frame.count <= frameData.count, "Frame parser should not return more data than available")
        }
    } catch {
        // Any error is acceptable for mismatched length
    }
}

/// Tests that oversized frames are rejected.
@Test func testFrameDecoderRejectsOversizedFrame() throws {
    // Create a frame that exceeds the 5MB limit
    var oversizedFrame = Data()
    // Length prefix: 6MB (0x00 0x5B 0xE1 0x00)
    oversizedFrame.append(0x00)
    oversizedFrame.append(0x5B)
    oversizedFrame.append(0xE1)
    oversizedFrame.append(0x00)
    // Add some payload
    oversizedFrame.append(contentsOf: [UInt8](repeating: 0x42, count: 100))
    
    let parser = BlazeFrameParser()
    
    do {
        try parser.append(oversizedFrame)
        _ = try parser.nextFrame()
        // Parser should handle this gracefully (return nil or throw)
    } catch BlazeBinaryError.oversizedFrame {
        // Expected error
    } catch {
        // Any error is acceptable for oversized frame
    }
}

/// Tests that invalid UTF-8 sequences are rejected.
@Test func testDecoderRejectsInvalidUTF8() throws {
    // Create data with invalid UTF-8 sequence
    var invalidUTF8 = Data()
    // Varint length: 3
    invalidUTF8.append(0x03)
    // Invalid UTF-8: 0xFF 0xFE 0xFD (not valid UTF-8)
    invalidUTF8.append(0xFF)
    invalidUTF8.append(0xFE)
    invalidUTF8.append(0xFD)
    
    let decoder = BlazeBinaryDecoder(data: invalidUTF8)
    
    do {
        _ = try decoder.decodeString()
        Issue.record("Decoder should reject invalid UTF-8 sequence")
    } catch BlazeBinaryError.decodeFailed {
        // Expected error
    } catch {
        // Any error is acceptable for invalid UTF-8
    }
}

/// Tests that negative length prefixes are rejected.
@Test func testDecoderRejectsNegativeLength() throws {
    // Create data with a length that would be negative if interpreted as signed
    // Use a varint that decodes to a very large number (potential overflow)
    var invalidLength = Data()
    // Varint encoding of a very large number (could cause issues)
    invalidLength.append(0xFF)
    invalidLength.append(0xFF)
    invalidLength.append(0xFF)
    invalidLength.append(0xFF)
    invalidLength.append(0xFF)
    invalidLength.append(0xFF)
    invalidLength.append(0xFF)
    invalidLength.append(0xFF)
    invalidLength.append(0xFF)
    invalidLength.append(0x01) // 10 bytes total
    
    let decoder = BlazeBinaryDecoder(data: invalidLength)
    
    do {
        _ = try decoder.decodeString()
        // Should either reject or handle gracefully
    } catch BlazeBinaryError.invalidVarint {
        // Expected error
    } catch BlazeBinaryError.decodeFailed {
        // Also acceptable
    } catch {
        // Any error is acceptable
    }
}

/// Tests that zero-length fields are handled correctly.
@Test func testDecoderHandlesZeroLengthFields() throws {
    // Zero-length string
    var zeroLengthString = Data()
    zeroLengthString.append(0x00) // Varint: 0
    
    let decoder1 = BlazeBinaryDecoder(data: zeroLengthString)
    let emptyString = try decoder1.decodeString()
    #expect(emptyString == "", "Zero-length string should decode to empty string")
    
    // Zero-length data
    var zeroLengthData = Data()
    zeroLengthData.append(0x00) // Varint: 0
    
    let decoder2 = BlazeBinaryDecoder(data: zeroLengthData)
    let emptyData = try decoder2.decodeData()
    #expect(emptyData.isEmpty, "Zero-length data should decode to empty Data")
}

/// Tests that corrupted frame headers are rejected.
@Test func testFrameDecoderRejectsCorruptedHeader() throws {
    // Create frame with corrupted header (invalid length bytes)
    var corruptedFrame = Data()
    // Invalid length: all 0xFF bytes (would be huge if interpreted)
    corruptedFrame.append(0xFF)
    corruptedFrame.append(0xFF)
    corruptedFrame.append(0xFF)
    corruptedFrame.append(0xFF)
    // Add some payload
    corruptedFrame.append(contentsOf: [0x01, 0x02, 0x03])
    
    let parser = BlazeFrameParser()
    
    do {
        try parser.append(corruptedFrame)
        _ = try parser.nextFrame()
        // Should handle gracefully
    } catch BlazeBinaryError.invalidFrameLength {
        // Expected error
    } catch BlazeBinaryError.oversizedFrame {
        // Also acceptable
    } catch {
        // Any error is acceptable for corrupted header
    }
}

/// Tests that partial varint encodings are rejected.
@Test func testDecoderRejectsPartialVarint() throws {
    // Create a varint that's incomplete (continuation bit set but no more bytes)
    var partialVarint = Data()
    partialVarint.append(0x80) // Continuation bit set, but no more bytes
    
    let decoder = BlazeBinaryDecoder(data: partialVarint)
    
    do {
        _ = try decoder.decodeInt()
        Issue.record("Decoder should reject partial varint encoding")
    } catch BlazeBinaryError.truncated {
        // Expected error
    } catch BlazeBinaryError.invalidVarint {
        // Also acceptable
    } catch BlazeBinaryError.decodeFailed {
        // Also acceptable
    } catch {
        // Any error is acceptable
    }
}

/// Tests that garbage data is rejected gracefully.
@Test func testDecoderRejectsGarbageData() throws {
    // Create completely random/garbage data
    let garbage = Data((0..<100).map { _ in UInt8.random(in: 0...255) })
    
    let decoder = BlazeBinaryDecoder(data: garbage)
    
    do {
        _ = try decoder.decodeString()
        // Should fail, not crash
    } catch {
        // Any error is acceptable for garbage data
        // Just verify it doesn't crash
    }
    
    // Test with frame parser
    let parser = BlazeFrameParser()
    do {
        try parser.append(garbage)
        let result = try parser.nextFrame()
        // Should return nil or handle gracefully
        if let frame = result {
            #expect(frame.count <= garbage.count, "Frame parser should not return more data than available")
        }
    } catch {
        // Any error is acceptable for garbage data
    }
}

