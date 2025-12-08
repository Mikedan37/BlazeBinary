import XCTest
@testable import BlazeBinary

final class EndiannessTestsTests: XCTestCase {
    func testLittleEndianUInt32() throws {
        // Test that encoding/decoding preserves little-endian format
        let value: UInt32 = 0x12345678
        
        let encoder = BlazeBinaryEncoder()
        encoder.encode(value)
        let data = encoder.encodedData()
        
        // Verify byte order: 0x78, 0x56, 0x34, 0x12 (little-endian)
        XCTAssert(data[0] == 0x78)
        XCTAssert(data[1] == 0x56)
        XCTAssert(data[2] == 0x34)
        XCTAssert(data[3] == 0x12)
        
        let decoder = BlazeBinaryDecoder(data: data)
        let decoded = try decoder.decodeUInt32()
        XCTAssert(decoded == value)
    }
    func testLittleEndianUInt64() throws {
        let value: UInt64 = 0x0123456789ABCDEF
        
        let encoder = BlazeBinaryEncoder()
        encoder.encode(value)
        let data = encoder.encodedData()
        
        // Verify byte order (little-endian)
        XCTAssert(data[0] == 0xEF)
        XCTAssert(data[1] == 0xCD)
        XCTAssert(data[2] == 0xAB)
        XCTAssert(data[3] == 0x89)
        XCTAssert(data[4] == 0x67)
        XCTAssert(data[5] == 0x45)
        XCTAssert(data[6] == 0x23)
        XCTAssert(data[7] == 0x01)
        
        let decoder = BlazeBinaryDecoder(data: data)
        let decoded = try decoder.decodeUInt64()
        XCTAssert(decoded == value)
    }
    func testBigEndianFrameLength() throws {
        // Frame length prefix is big-endian (v2.0 format)
        let payload = Data([0x01, 0x02, 0x03, 0x04])
        let frame = try BlazeFrameEncoder.encodeFrame(payload)
        
        // v2.0 frame format:
        // - Byte 0: frameType (0x00 = plaintext)
        // - Byte 1: compressionMode (0x00 = none)
        // - Bytes 2-5: payloadLength (big-endian UInt32)
        // - Bytes 6+: payload
        
        // Check frameType
        XCTAssert(frame[0] == 0x00, "Frame type should be 0x00 (plaintext)")
        // Check compressionMode
        XCTAssert(frame[1] == 0x00, "Compression mode should be 0x00 (none)")
        // Length should be 4, encoded as big-endian: 0x00, 0x00, 0x00, 0x04
        XCTAssert(frame[2] == 0x00, "Length byte 0 should be 0x00")
        XCTAssert(frame[3] == 0x00, "Length byte 1 should be 0x00")
        XCTAssert(frame[4] == 0x00, "Length byte 2 should be 0x00")
        XCTAssert(frame[5] == 0x04, "Length byte 3 should be 0x04")
        
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
