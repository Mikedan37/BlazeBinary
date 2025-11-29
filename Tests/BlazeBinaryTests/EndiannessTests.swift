import Testing
@testable import BlazeBinary

@Test func testLittleEndianUInt32() throws {
    // Test that encoding/decoding preserves little-endian format
    let value: UInt32 = 0x12345678
    
    let encoder = BlazeBinaryEncoder()
    encoder.encode(value)
    let data = encoder.encodedData()
    
    // Verify byte order: 0x78, 0x56, 0x34, 0x12 (little-endian)
    #expect(data[0] == 0x78)
    #expect(data[1] == 0x56)
    #expect(data[2] == 0x34)
    #expect(data[3] == 0x12)
    
    let decoder = BlazeBinaryDecoder(data: data)
    let decoded = try decoder.decodeUInt32()
    #expect(decoded == value)
}

@Test func testLittleEndianUInt64() throws {
    let value: UInt64 = 0x0123456789ABCDEF
    
    let encoder = BlazeBinaryEncoder()
    encoder.encode(value)
    let data = encoder.encodedData()
    
    // Verify byte order (little-endian)
    #expect(data[0] == 0xEF)
    #expect(data[1] == 0xCD)
    #expect(data[2] == 0xAB)
    #expect(data[3] == 0x89)
    #expect(data[4] == 0x67)
    #expect(data[5] == 0x45)
    #expect(data[6] == 0x23)
    #expect(data[7] == 0x01)
    
    let decoder = BlazeBinaryDecoder(data: data)
    let decoded = try decoder.decodeUInt64()
    #expect(decoded == value)
}

@Test func testBigEndianFrameLength() throws {
    // Frame length prefix is big-endian
    let payload = Data([0x01, 0x02, 0x03, 0x04])
    let frame = try BlazeFrameEncoder.encodeFrame(payload)
    
    // Length should be 4, encoded as big-endian: 0x00, 0x00, 0x00, 0x04
    #expect(frame[0] == 0x00)
    #expect(frame[1] == 0x00)
    #expect(frame[2] == 0x00)
    #expect(frame[3] == 0x04)
    
    // Verify round-trip
    let parser = BlazeFrameParser()
    try parser.append(frame)
    let decoded = try parser.nextFrame()
    #expect(decoded == payload)
}

@Test func testEndiannessRoundTrip() throws {
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
        #expect(decoded == value, "Failed for value: \(String(value, radix: 16))")
    }
}

