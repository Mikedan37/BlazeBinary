import XCTest
@testable import BlazeBinary

final class EndiannessTestsTests: XCTestCase {
    func testBigEndianUInt32() throws {
        // Test that encoding/decoding uses big-endian (network byte order) format
        let value: UInt32 = 0x12345678
        
        let encoder = BlazeBinaryEncoder()
        encoder.encode(value)
        let data = encoder.encodedData()
        
        // Verify byte order: 0x12, 0x34, 0x56, 0x78 (big-endian, network byte order)
        XCTAssert(data[0] == 0x12, "MSB should be first byte")
        XCTAssert(data[1] == 0x34)
        XCTAssert(data[2] == 0x56)
        XCTAssert(data[3] == 0x78, "LSB should be last byte")
        
        let decoder = BlazeBinaryDecoder(data: data)
        let decoded = try decoder.decodeUInt32()
        XCTAssert(decoded == value, "Round-trip should preserve value")
    }
    
    func testBigEndianUInt64() throws {
        let value: UInt64 = 0x0123456789ABCDEF
        
        let encoder = BlazeBinaryEncoder()
        encoder.encode(value)
        let data = encoder.encodedData()
        
        // Verify byte order (big-endian, network byte order)
        XCTAssert(data[0] == 0x01, "MSB should be first byte")
        XCTAssert(data[1] == 0x23)
        XCTAssert(data[2] == 0x45)
        XCTAssert(data[3] == 0x67)
        XCTAssert(data[4] == 0x89)
        XCTAssert(data[5] == 0xAB)
        XCTAssert(data[6] == 0xCD)
        XCTAssert(data[7] == 0xEF, "LSB should be last byte")
        
        let decoder = BlazeBinaryDecoder(data: data)
        let decoded = try decoder.decodeUInt64()
        XCTAssert(decoded == value, "Round-trip should preserve value")
    }
    
    func testBigEndianUInt16() throws {
        // Test UInt16 encoding/decoding with big-endian format
        let value: UInt16 = 0x1234
        
        let encoder = BlazeBinaryEncoder()
        encoder.encode(value)
        let data = encoder.encodedData()
        
        // Verify byte order: 0x12, 0x34 (big-endian, network byte order)
        XCTAssert(data[0] == 0x12, "MSB should be first byte")
        XCTAssert(data[1] == 0x34, "LSB should be second byte")
        
        let decoder = BlazeBinaryDecoder(data: data)
        let decoded = try decoder.decodeUInt16()
        XCTAssert(decoded == value, "Round-trip should preserve value")
    }
    
    func testBigEndianFloat() throws {
        // Test Float (Float32) encoding/decoding with big-endian format
        let value: Float = 1.0
        
        let encoder = BlazeBinaryEncoder()
        encoder.encode(value)
        let data = encoder.encodedData()
        
        // IEEE 754 single precision for 1.0: 0x3F800000
        // Big-endian: [0x3F, 0x80, 0x00, 0x00]
        XCTAssert(data[0] == 0x3F, "First byte should be 0x3F (sign + exponent MSB)")
        XCTAssert(data[1] == 0x80, "Second byte should be 0x80 (exponent LSB + mantissa MSB)")
        XCTAssert(data[2] == 0x00, "Third byte should be 0x00")
        XCTAssert(data[3] == 0x00, "Fourth byte should be 0x00")
        
        let decoder = BlazeBinaryDecoder(data: data)
        let decoded = try decoder.decodeFloat()
        XCTAssert(decoded == value, "Round-trip should preserve value")
    }
    
    func testBigEndianDouble() throws {
        // Test Double encoding/decoding with big-endian format
        let value: Double = 1.0
        
        let encoder = BlazeBinaryEncoder()
        encoder.encode(value)
        let data = encoder.encodedData()
        
        // IEEE 754 double precision for 1.0: 0x3FF0000000000000
        // Big-endian: [0x3F, 0xF0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]
        XCTAssert(data[0] == 0x3F, "First byte should be 0x3F (sign + exponent MSB)")
        XCTAssert(data[1] == 0xF0, "Second byte should be 0xF0 (exponent LSB + mantissa MSB)")
        
        let decoder = BlazeBinaryDecoder(data: data)
        let decoded = try decoder.decodeDouble()
        XCTAssert(decoded == value, "Round-trip should preserve value")
    }
    func testBigEndianFrameLength() throws {
        // Frame length prefix is big-endian (v2.1 format)
        let payload = Data([0x01, 0x02, 0x03, 0x04])
        let frame = try BlazeFrameEncoder.encodeFrame(payload)

        // v2.1 frame format:
        // - Byte 0: 0xBF (magic)
        // - Byte 1: frameType (0x00 = plaintext)
        // - Byte 2: compressionMode (0x00 = none)
        // - Bytes 3-6: payloadLength (big-endian UInt32)
        // - Bytes 7+: payload

        // Check magic
        XCTAssert(frame[0] == 0xBF, "Magic byte should be 0xBF")
        // Check frameType
        XCTAssert(frame[1] == 0x00, "Frame type should be 0x00 (plaintext)")
        // Check compressionMode
        XCTAssert(frame[2] == 0x00, "Compression mode should be 0x00 (none)")
        // Length should be 4, encoded as big-endian: 0x00, 0x00, 0x00, 0x04
        XCTAssert(frame[3] == 0x00, "Length byte 0 should be 0x00")
        XCTAssert(frame[4] == 0x00, "Length byte 1 should be 0x00")
        XCTAssert(frame[5] == 0x00, "Length byte 2 should be 0x00")
        XCTAssert(frame[6] == 0x04, "Length byte 3 should be 0x04")

        // Verify round-trip
        let parser = BlazeFrameParser()
        try parser.append(frame)
        let decoded = try parser.nextFrame()
        XCTAssert(decoded == payload)
    }
    func testEndiannessRoundTrip() throws {
        // Test various values to ensure endianness is consistent
        let testValues: [UInt32] = [
            0,
            1,
            0xFF,
            0xFFFF,
            0xFFFFFF,
            0xFFFFFFFF,
            0x12345678,
            0xABCDEF00
        ]
        
        for value in testValues {
            let encoder = BlazeBinaryEncoder()
            encoder.encode(value)
            let data = encoder.encodedData()
            
            let decoder = BlazeBinaryDecoder(data: data)
            let decoded = try decoder.decodeUInt32()
            XCTAssert(decoded == value, "Failed for value: \(String(value, radix: 16))")
    }
}
}
