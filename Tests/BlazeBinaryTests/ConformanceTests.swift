import Testing
import Foundation
@testable import BlazeBinary

/// Conformance tests verifying the rules in FaultToleranceChecklist.md.
struct ConformanceTests {
    
    // MARK: - Encoder Invariants
    
    @Test func testEncoderDeterministicOutput() throws {
        // Same input always produces same output
        let value = 42
        var previousData: Data?
        
        for _ in 0..<100 {
            let encoder = BlazeBinaryEncoder()
            encoder.encode(value)
            let data = encoder.encodedData()
            
            if let prev = previousData {
                #expect(data == prev)
            }
            previousData = data
        }
    }
    
    @Test func testEncoderNoExternalState() throws {
        // Encoder output depends only on input
        let encoder1 = BlazeBinaryEncoder()
        encoder1.encode(100)
        let data1 = encoder1.encodedData()
        
        let encoder2 = BlazeBinaryEncoder()
        encoder2.encode(100)
        let data2 = encoder2.encodedData()
        
        #expect(data1 == data2)
    }
    
    @Test func testEncoderFieldOrderPreservation() throws {
        struct TestStruct: BlazeBinaryCodable {
            var a: Int
            var b: String
            var c: Bool
            
            init(a: Int, b: String, c: Bool) {
                self.a = a
                self.b = b
                self.c = c
            }
            
            func blazeEncode(to encoder: BlazeBinaryEncoder) throws {
                encoder.encode(a)
                encoder.encode(b)
                encoder.encode(c)
            }
            
            init(from decoder: BlazeBinaryDecoder) throws {
                self.a = try decoder.decodeInt()
                self.b = try decoder.decodeString()
                self.c = try decoder.decodeBool()
            }
        }
        
        let original = TestStruct(a: 1, b: "test", c: true)
        let encoder = BlazeBinaryEncoder()
        try encoder.encode(original)
        let data = encoder.encodedData()
        
        // Decode and verify order
        let decoder = BlazeBinaryDecoder(data: data)
        let decoded = try decoder.decode(TestStruct.self)
        
        #expect(decoded.a == 1)
        #expect(decoded.b == "test")
        #expect(decoded.c == true)
    }
    
    // MARK: - Decoder Invariants
    
    @Test func testDecoderOffsetBounds() throws {
        // Offset always within bounds: 0 <= offset <= data.count
        // We verify this by checking remainingData
        let data = Data([0x01, 0x02, 0x03, 0x04])
        let decoder = BlazeBinaryDecoder(data: data)
        
        // Initially, remainingData should equal full data
        #expect(decoder.remainingData.count == data.count)
        
        _ = try decoder.decodeUInt32()
        
        // After decoding, remainingData should be smaller
        #expect(decoder.remainingData.count < data.count)
    }
    
    @Test func testDecoderReadBoundsChecking() throws {
        // Every read validates bounds
        let data = Data([0x01, 0x02]) // Only 2 bytes
        
        let decoder = BlazeBinaryDecoder(data: data)
        #expect(throws: BlazeBinaryError.truncated) {
            _ = try decoder.decodeUInt32() // Needs 4 bytes
        }
    }
    
    @Test func testDecoderLengthValidation() throws {
        // All lengths validated before use
        // Create data with large length prefix manually
        var data = testEncodeVarintHelper(UInt64(20 * 1024 * 1024)) // 20 MB
        data.append(Data(repeating: 0xAA, count: 100)) // Some payload
        
        let decoder = BlazeBinaryDecoder(data: data, maxAllowedLength: 10 * 1024 * 1024)
        do {
            _ = try decoder.decodeData()
            Issue.record("Decoder should reject oversized data")
        } catch let error as BlazeBinaryError {
            switch error {
            case .decodeFailed:
                // Expected
                break
            default:
                // Also acceptable
                break
            }
        } catch {
            // Any error is acceptable
        }
    }
    
    @Test func testDecoderVarintValidation() throws {
        // Varints validated (max 10 bytes, shift limits)
        var invalid = Data()
        for _ in 0..<11 {
            invalid.append(0x80)
        }
        
        let decoder = BlazeBinaryDecoder(data: invalid)
        #expect(throws: BlazeBinaryError.invalidVarint) {
            _ = try decoder.decodeInt()
        }
    }
    
    @Test func testDecoderNoPartialDecoding() throws {
        // On error, decoder stops immediately
        let data = Data([0x01, 0x02]) // Incomplete
        
        let decoder = BlazeBinaryDecoder(data: data)
        let initialRemaining = decoder.remainingData.count
        
        do {
            _ = try decoder.decodeUInt32()
        } catch {
            // Error thrown
        }
        
        // Remaining data should be unchanged on error (offset didn't advance)
        #expect(decoder.remainingData.count == initialRemaining)
    }
    
    // MARK: - Frame Parser Invariants
    
    @Test func testFrameParserBufferSizeLimit() throws {
        // Buffer never exceeds maxBufferSize
        let parser = BlazeFrameParser()
        
        #expect(throws: BlazeBinaryError.oversizedFrame) {
            let hugeData = Data(repeating: 0xAA, count: BlazeFrameParser.maxBufferSize + 1)
            try parser.append(hugeData)
        }
    }
    
    @Test func testFrameParserFrameSizeLimit() throws {
        // Frame length never exceeds maxFrameSize
        let parser = BlazeFrameParser()
        
        var frame = Data()
        let oversizedLength = UInt32(BlazeFrameEncoder.maxFrameSize + 1).bigEndian
        frame.append(contentsOf: withUnsafeBytes(of: oversizedLength) { Data($0) })
        
        try parser.append(frame)
        
        #expect(throws: BlazeBinaryError.invalidFrameLength) {
            _ = try parser.nextFrame()
        }
    }
    
    @Test func testFrameParserCompleteFrameRequirement() throws {
        // Frames only extracted when complete
        let payload = Data([0x01, 0x02, 0x03])
        let frame = try BlazeFrameEncoder.encodeFrame(payload)
        
        let parser = BlazeFrameParser()
        // Append partial frame
        try parser.append(frame.prefix(frame.count - 1))
        
        let result = try parser.nextFrame()
        #expect(result == nil) // Not complete
    }
    
    @Test func testFrameParserPartialFrameHandling() throws {
        // Incomplete frames return nil, not error
        let payload = Data([0x01, 0x02])
        let frame = try BlazeFrameEncoder.encodeFrame(payload)
        
        let parser = BlazeFrameParser()
        try parser.append(frame.prefix(5)) // Partial
        
        // Should return nil, not throw
        let result = try parser.nextFrame()
        #expect(result == nil)
    }
    
    @Test func testFrameParserStateConsistency() throws {
        // Parser state remains valid after nil returns
        let payload = Data([0x01, 0x02])
        let frame = try BlazeFrameEncoder.encodeFrame(payload)
        
        let parser = BlazeFrameParser()
        try parser.append(frame.prefix(5))
        
        let result1 = try parser.nextFrame()
        #expect(result1 == nil)
        
        // Add more data
        try parser.append(frame.suffix(from: 5))
        
        let result2 = try parser.nextFrame()
        #expect(result2 == payload)
    }
    
    // MARK: - Bounds Checks
    
    @Test func testBoundsCheckUInt32() throws {
        let data = Data([0x01, 0x02, 0x03]) // Only 3 bytes
        let decoder = BlazeBinaryDecoder(data: data)
        
        #expect(throws: BlazeBinaryError.truncated) {
            _ = try decoder.decodeUInt32() // Needs 4
        }
    }
    
    @Test func testBoundsCheckUInt64() throws {
        let data = Data([0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07]) // Only 7 bytes
        let decoder = BlazeBinaryDecoder(data: data)
        
        #expect(throws: BlazeBinaryError.truncated) {
            _ = try decoder.decodeUInt64() // Needs 8
        }
    }
    
    @Test func testBoundsCheckDataPayload() throws {
        let encoder = BlazeBinaryEncoder()
        encoder.encode(Data(repeating: 0xAA, count: 100))
        let fullData = encoder.encodedData()
        
        let truncated = fullData.prefix(fullData.count - 50)
        let decoder = BlazeBinaryDecoder(data: truncated)
        
        #expect(throws: BlazeBinaryError.truncated) {
            _ = try decoder.decodeData()
        }
    }
    
    // MARK: - Varint Rules
    
    @Test func testVarintEncodingLEB128() throws {
        // Varint uses LEB128 format
        let encoder = BlazeBinaryEncoder()
        encoder.encode(300) // Should encode as [0xAC, 0x02]
        let data = encoder.encodedData()
        
        // Verify LEB128 format
        #expect(data.count >= 2)
        #expect((data[0] & 0x80) != 0) // Continuation bit set
        #expect((data[1] & 0x80) == 0) // Last byte, no continuation
    }
    
    @Test func testVarintDecodingMaxBytes() throws {
        // Varint limited to 10 bytes
        var data = Data()
        for _ in 0..<11 {
            data.append(0x80) // All continuation
        }
        
        let decoder = BlazeBinaryDecoder(data: data)
        #expect(throws: BlazeBinaryError.invalidVarint) {
            _ = try decoder.decodeInt()
        }
    }
    
    // MARK: - ZigZag Correctness
    
    @Test func testZigZagRoundTrip() throws {
        let testValues: [Int] = [0, 1, -1, 2, -2, 127, -128, Int.max, Int.min]
        
        for value in testValues {
            let encoder = BlazeBinaryEncoder()
            encoder.encode(value)
            let data = encoder.encodedData()
            
            let decoder = BlazeBinaryDecoder(data: data)
            let decoded = try decoder.decodeInt()
            
            #expect(decoded == value, "ZigZag failed for \(value)")
        }
    }
    
    // MARK: - Round-Trip Integrity
    
    @Test func testRoundTripIntegrityPrimitives() throws {
        let testCases: [(Any, (BlazeBinaryEncoder) -> Void, (BlazeBinaryDecoder) throws -> Any)] = [
            (UInt32(42), { $0.encode(42) }, { try $0.decodeUInt32() }),
            (UInt64(123), { $0.encode(UInt64(123)) }, { try $0.decodeUInt64() }),
            (Int(-100), { $0.encode(-100) }, { try $0.decodeInt() }),
            (true, { $0.encode(true) }, { try $0.decodeBool() }),
            ("test", { $0.encode("test") }, { try $0.decodeString() }),
            (Data([0x01, 0x02]), { $0.encode(Data([0x01, 0x02])) }, { try $0.decodeData() })
        ]
        
        for (original, encode, decode) in testCases {
            let encoder = BlazeBinaryEncoder()
            encode(encoder)
            let data = encoder.encodedData()
            
            let decoder = BlazeBinaryDecoder(data: data)
            let decoded = try decode(decoder)
            
            // Compare values
            if let orig = original as? UInt32, let dec = decoded as? UInt32 {
                #expect(dec == orig)
            } else if let orig = original as? UInt64, let dec = decoded as? UInt64 {
                #expect(dec == orig)
            } else if let orig = original as? Int, let dec = decoded as? Int {
                #expect(dec == orig)
            } else if let orig = original as? Bool, let dec = decoded as? Bool {
                #expect(dec == orig)
            } else if let orig = original as? String, let dec = decoded as? String {
                #expect(dec == orig)
            } else if let orig = original as? Data, let dec = decoded as? Data {
                #expect(dec == orig)
            }
        }
    }
}

// Helper to encode varint for testing
func testEncodeVarintHelper(_ value: UInt64) -> Data {
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

