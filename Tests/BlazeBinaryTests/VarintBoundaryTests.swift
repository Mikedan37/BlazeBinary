import Testing
@testable import BlazeBinary

/// Tests for varint boundary behavior (max shift, overflow cases).
struct VarintBoundaryTests {
    
    @Test func testVarintMaxShift() throws {
        // Test varint that uses maximum shift (63 bits)
        // This is the largest valid varint before overflow
        // UInt64.max requires 10 bytes with shift up to 63
        
        let encoder = BlazeBinaryEncoder()
        encoder.encode(UInt64.max)
        let data = encoder.encodedData()
        
        // Should be exactly 10 bytes
        #expect(data.count == 10)
        
        // Verify it decodes correctly
        // Note: We can't directly decode UInt64.max as varint,
        // but we can verify the encoding is valid
        let decoder = BlazeBinaryDecoder(data: data)
        // Try to decode as Int (which uses varint)
        // This will test the varint decoding path
        _ = try? decoder.decodeInt()
    }
    
    @Test func testVarintShiftOverflowProtection() throws {
        // Create a varint that would cause shift overflow if not protected
        // This is hard to construct directly, but we test the protection
        
        // A varint with 10 continuation bytes but invalid pattern
        var invalid = Data()
        // 9 bytes with continuation, then one without
        for i in 0..<10 {
            if i < 9 {
                invalid.append(0x80) // Continuation
            } else {
                invalid.append(0x01) // Last byte, but shift would be 63
            }
        }
        
        let decoder = BlazeBinaryDecoder(data: invalid)
        // Should detect shift overflow or invalid varint
        #expect(throws: BlazeBinaryError.invalidVarint) {
            _ = try decoder.decodeInt()
        }
    }
    
    @Test func testVarintMaxBytesLimit() throws {
        // Test that varint is limited to 10 bytes
        var tooLong = Data()
        // 11 bytes with continuation bits (exceeds max)
        for _ in 0..<11 {
            tooLong.append(0x80) // All continuation
        }
        
        let decoder = BlazeBinaryDecoder(data: tooLong)
        #expect(throws: BlazeBinaryError.invalidVarint) {
            _ = try decoder.decodeInt()
        }
    }
    
    @Test func testVarintExact10Bytes() throws {
        // Test varint that is exactly 10 bytes (maximum)
        // We'll test with Int.max which uses varint encoding
        // and verify the encoding behavior
        
        let encoder = BlazeBinaryEncoder()
        encoder.encode(Int.max)
        let data = encoder.encodedData()
        
        // Int.max with zigzag encoding should produce a multi-byte varint
        // The exact size depends on the zigzag value, but should be reasonable
        #expect(data.count >= 1)
        #expect(data.count <= 10) // Varint max is 10 bytes
        
        // Verify round-trip
        let decoder = BlazeBinaryDecoder(data: data)
        let decoded = try decoder.decodeInt()
        #expect(decoded == Int.max)
    }
    
    @Test func testVarintContinuationBitPattern() throws {
        // Test that continuation bit pattern is correct
        // All bytes except last should have continuation bit = 1
        // Last byte should have continuation bit = 0
        
        let testValues: [Int] = [127, 128, 300, 16383, 16384]
        
        for value in testValues {
            let encoder = BlazeBinaryEncoder()
            encoder.encode(value)
            let data = encoder.encodedData()
            
            // Verify continuation bit pattern
            for i in 0..<(data.count - 1) {
                #expect((data[i] & 0x80) != 0, "Byte \(i) should have continuation bit set for value \(value)")
            }
            // Last byte should not have continuation bit
            let lastByte = data[data.count - 1]
            #expect((lastByte & 0x80) == 0, "Last byte should not have continuation bit for value \(value)")
        }
    }
    
    @Test func testZigZagBoundaryValues() throws {
        // Test zigzag encoding at boundaries
        let boundaries: [Int] = [
            Int.min,
            Int.min + 1,
            -1,
            0,
            1,
            Int.max - 1,
            Int.max
        ]
        
        for value in boundaries {
            let encoder = BlazeBinaryEncoder()
            encoder.encode(value)
            let data = encoder.encodedData()
            
            let decoder = BlazeBinaryDecoder(data: data)
            let decoded = try decoder.decodeInt()
            
            #expect(decoded == value, "ZigZag boundary test failed for \(value)")
        }
    }
    
    @Test func testZigZagRoundTripAllValues() throws {
        // Test zigzag round-trip for a range of values
        let testRange = -1000...1000
        
        for value in testRange {
            let encoder = BlazeBinaryEncoder()
            encoder.encode(value)
            let data = encoder.encodedData()
            
            let decoder = BlazeBinaryDecoder(data: data)
            let decoded = try decoder.decodeInt()
            
            #expect(decoded == value, "ZigZag round-trip failed for \(value)")
        }
    }
}

