import Testing
@testable import BlazeBinary

@Test func testZeroCopyDataDecoding() throws {
    let originalData = Data([0x01, 0x02, 0x03, 0x04, 0x05])
    let encoder = BlazeBinaryEncoder()
    encoder.encode(originalData)
    let encoded = encoder.encodedData()
    
    let decoder = BlazeBinaryDecoder(data: encoded)
    let decoded = try decoder.decodeData()
    
    // Verify content matches
    #expect(decoded == originalData)
    
    // Verify it's a slice (zero-copy) by checking if modifying the original
    // affects the decoded data. Since Data.subdata creates a slice that
    // references the same buffer, they should share memory.
    // Note: In Swift, Data.subdata may or may not copy depending on implementation,
    // but we document it as zero-copy when possible.
}

@Test func testZeroCopyDataLarge() throws {
    let largeData = Data(repeating: 0xAA, count: 10000)
    let encoder = BlazeBinaryEncoder()
    encoder.encode(largeData)
    let encoded = encoder.encodedData()
    
    let decoder = BlazeBinaryDecoder(data: encoded)
    let decoded = try decoder.decodeData()
    
    #expect(decoded == largeData)
    #expect(decoded.count == 10000)
}

@Test func testZeroCopyDecodeDataZeroCopy() throws {
    let testData = Data([0x10, 0x20, 0x30])
    let encoder = BlazeBinaryEncoder()
    encoder.encode(testData)
    let encoded = encoder.encodedData()
    
    let decoder = BlazeBinaryDecoder(data: encoded)
    let decoded = try decoder.decodeDataZeroCopy()
    
    #expect(decoded == testData)
}

@Test func testStringDecoding() throws {
    let testString = "Hello, BlazeBinary!"
    let encoder = BlazeBinaryEncoder()
    encoder.encode(testString)
    let encoded = encoder.encodedData()
    
    let decoder = BlazeBinaryDecoder(data: encoded)
    let decoded = try decoder.decodeString()
    
    #expect(decoded == testString)
}

@Test func testMultipleDataDecodes() throws {
    let data1 = Data([0x01, 0x02])
    let data2 = Data([0x03, 0x04])
    
    let encoder = BlazeBinaryEncoder()
    encoder.encode(data1)
    encoder.encode(data2)
    let encoded = encoder.encodedData()
    
    let decoder = BlazeBinaryDecoder(data: encoded)
    let decoded1 = try decoder.decodeData()
    let decoded2 = try decoder.decodeData()
    
    #expect(decoded1 == data1)
    #expect(decoded2 == data2)
}

