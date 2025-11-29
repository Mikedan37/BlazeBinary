import Testing
import Foundation
@testable import BlazeBinary

/// Tests for maximum size boundaries (near 5MB frame, near 10MB buffer).
struct MaxSizeBoundaryTests {
    
    @Test func testFrameAtMaxSize() throws {
        // Frame exactly at 5MB limit
        let payload = Data(repeating: 0xAA, count: BlazeFrameEncoder.maxFrameSize)
        
        let frame = try BlazeFrameEncoder.encodeFrame(payload)
        let parser = BlazeFrameParser()
        try parser.append(frame)
        
        let extracted = try parser.nextFrame()
        #expect(extracted != nil)
        #expect(extracted?.count == BlazeFrameEncoder.maxFrameSize)
    }
    
    @Test func testFrameExceedsMaxSize() throws {
        // Frame exceeding 5MB limit
        let payload = Data(repeating: 0xAA, count: BlazeFrameEncoder.maxFrameSize + 1)
        
        #expect(throws: BlazeBinaryError.oversizedFrame) {
            _ = try BlazeFrameEncoder.encodeFrame(payload)
        }
    }
    
    @Test func testFrameJustUnderMaxSize() throws {
        // Frame just under 5MB limit
        let payload = Data(repeating: 0xAA, count: BlazeFrameEncoder.maxFrameSize - 1)
        
        let frame = try BlazeFrameEncoder.encodeFrame(payload)
        let parser = BlazeFrameParser()
        try parser.append(frame)
        
        let extracted = try parser.nextFrame()
        #expect(extracted != nil)
        #expect(extracted?.count == BlazeFrameEncoder.maxFrameSize - 1)
    }
    
    @Test func testDataAtMaxAllowedLength() throws {
        // Data exactly at maxAllowedLength (10MB)
        let data = Data(repeating: 0xBB, count: 10 * 1024 * 1024)
        
        let encoder = BlazeBinaryEncoder()
        encoder.encode(data)
        let encoded = encoder.encodedData()
        
        let decoder = BlazeBinaryDecoder(data: encoded, maxAllowedLength: 10 * 1024 * 1024)
        let decoded = try decoder.decodeData()
        
        #expect(decoded.count == 10 * 1024 * 1024)
    }
    
    @Test func testDataExceedsMaxAllowedLength() throws {
        // Data exceeding maxAllowedLength
        let data = Data(repeating: 0xBB, count: 11 * 1024 * 1024)
        
        let encoder = BlazeBinaryEncoder()
        encoder.encode(data)
        let encoded = encoder.encodedData()
        
        let decoder = BlazeBinaryDecoder(data: encoded, maxAllowedLength: 10 * 1024 * 1024)
        #expect(throws: BlazeBinaryError.decodeFailed) {
            _ = try decoder.decodeData()
        }
    }
    
    @Test func testDataJustUnderMaxAllowedLength() throws {
        // Data just under maxAllowedLength
        let data = Data(repeating: 0xBB, count: 10 * 1024 * 1024 - 1)
        
        let encoder = BlazeBinaryEncoder()
        encoder.encode(data)
        let encoded = encoder.encodedData()
        
        let decoder = BlazeBinaryDecoder(data: encoded, maxAllowedLength: 10 * 1024 * 1024)
        let decoded = try decoder.decodeData()
        
        #expect(decoded.count == 10 * 1024 * 1024 - 1)
    }
    
    @Test func testBufferAtMaxSize() throws {
        // Buffer exactly at 10MB limit
        let parser = BlazeFrameParser()
        
        // Fill buffer to exactly maxBufferSize
        let frameSize = 1000
        let frameCount = BlazeFrameParser.maxBufferSize / (frameSize + 4) // +4 for length prefix
        
        for i in 0..<frameCount {
            let payload = Data(repeating: UInt8(i % 256), count: frameSize)
            let frame = try BlazeFrameEncoder.encodeFrame(payload)
            
            // Check if adding this frame would exceed limit
            if parser.bufferSize + frame.count > BlazeFrameParser.maxBufferSize {
                break
            }
            
            try parser.append(frame)
        }
        
        // Should be able to extract frames
        var extractedCount = 0
        while let _ = try parser.nextFrame() {
            extractedCount += 1
        }
        
        #expect(extractedCount > 0)
    }
    
    @Test func testBufferExceedsMaxSize() throws {
        // Buffer exceeding 10MB limit
        let parser = BlazeFrameParser()
        
        // Try to append data that would exceed limit
        let hugeData = Data(repeating: 0xCC, count: BlazeFrameParser.maxBufferSize + 1)
        
        #expect(throws: BlazeBinaryError.oversizedFrame) {
            try parser.append(hugeData)
        }
    }
    
    @Test func testArrayCountAtMaxAllowedLength() throws {
        // Array with count at maxAllowedLength
        struct Item: BlazeBinaryCodable {
            var value: Int
            
            func blazeEncode(to encoder: BlazeBinaryEncoder) throws {
                encoder.encode(value)
            }
            
            init(from decoder: BlazeBinaryDecoder) throws {
                self.value = try decoder.decodeInt()
            }
        }
        
        // Test that count validation works
        // Create data with large count varint
        var data = encodeVarint(UInt64(10 * 1024 * 1024))
        
        let decoder = BlazeBinaryDecoder(data: data, maxAllowedLength: 10 * 1024 * 1024)
        // Try to decode as array - should validate count
        #expect(throws: BlazeBinaryError.truncated) {
            _ = try decoder.decodeArray(Item.self)
        }
    }
    
    @Test func testArrayCountExceedsMaxAllowedLength() throws {
        // Array count exceeding maxAllowedLength
        struct Item: BlazeBinaryCodable {
            var value: Int
            
            func blazeEncode(to encoder: BlazeBinaryEncoder) throws {
                encoder.encode(value)
            }
            
            init(from decoder: BlazeBinaryDecoder) throws {
                self.value = try decoder.decodeInt()
            }
        }
        
        // Create encoded data with count exceeding limit
        var data = encodeVarint(UInt64(11 * 1024 * 1024))
        // Add one item to make it partially valid
        let encoder = BlazeBinaryEncoder()
        try encoder.encode(Item(value: 1))
        data.append(encoder.encodedData())
        
        let decoder = BlazeBinaryDecoder(data: data, maxAllowedLength: 10 * 1024 * 1024)
        #expect(throws: BlazeBinaryError.decodeFailed) {
            _ = try decoder.decodeArray(Item.self)
        }
    }
}

// Helper to encode varint for testing
func encodeVarint(_ value: UInt64) -> Data {
    var data = Data()
    var v = value
    repeat {
        var byte = UInt8(v & 0x7F)
        v >>= 7
        if v != 0 {
            byte |= 0x80
        }
        data.append(byte)
    } while v != 0
    return data
}

