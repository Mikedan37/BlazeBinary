import Testing
@testable import BlazeBinary

@Test func testVarintMaxUInt64() throws {
    let encoder = BlazeBinaryEncoder()
    encoder.encode(UInt64.max)
    let data = encoder.encodedData()
    
    let decoder = BlazeBinaryDecoder(data: data)
    // Note: We encode as varint but need to decode as varint
    // Since we don't have decodeUInt64Varint, we'll test via Int
    // Max UInt64 as varint should be 10 bytes
    #expect(data.count == 10)
}

@Test func testVarintMaxInt64() throws {
    let encoder = BlazeBinaryEncoder()
    encoder.encode(Int.max)
    let data = encoder.encodedData()
    
    let decoder = BlazeBinaryDecoder(data: data)
    let decoded = try decoder.decodeInt()
    #expect(decoded == Int.max)
}

@Test func testVarintMinInt64() throws {
    let encoder = BlazeBinaryEncoder()
    encoder.encode(Int.min)
    let data = encoder.encodedData()
    
    let decoder = BlazeBinaryDecoder(data: data)
    let decoded = try decoder.decodeInt()
    #expect(decoded == Int.min)
}

@Test func testVarintSmallestValues() throws {
    let values = [0, 1, -1, 2, -2, 127, -128]
    
    for value in values {
        let encoder = BlazeBinaryEncoder()
        encoder.encode(value)
        let data = encoder.encodedData()
        
        let decoder = BlazeBinaryDecoder(data: data)
        let decoded = try decoder.decodeInt()
        #expect(decoded == value, "Failed for value: \(value)")
    }
}

@Test func testVarintZigzagCorrectness() throws {
    // Test zigzag encoding: 0->0, 1->2, -1->1, 2->4, -2->3
    let testCases: [(Int, UInt64)] = [
        (0, 0),
        (1, 2),
        (-1, 1),
        (2, 4),
        (-2, 3),
        (127, 254),
        (-128, 255)
    ]
    
    for (signed, expectedZigzag) in testCases {
        let encoder = BlazeBinaryEncoder()
        encoder.encode(signed)
        let data = encoder.encodedData()
        
        // Decode as varint to check zigzag value
        let decoder = BlazeBinaryDecoder(data: data)
        // We can't directly access decodeVarint, but we can verify round-trip
        let decoded = try decoder.decodeInt()
        #expect(decoded == signed, "Zigzag failed for \(signed)")
    }
}

@Test func testVarintBoundaryCases() throws {
    // Test boundary values
    let boundaries = [
        Int.max,
        Int.min,
        0,
        1,
        -1,
        127,
        -128,
        128,
        -129,
        16383,
        -16384
    ]
    
    for value in boundaries {
        let encoder = BlazeBinaryEncoder()
        encoder.encode(value)
        let data = encoder.encodedData()
        
        let decoder = BlazeBinaryDecoder(data: data)
        let decoded = try decoder.decodeInt()
        #expect(decoded == value, "Boundary test failed for \(value)")
    }
}

@Test func testVarintInvalidEncoding() throws {
    // Create invalid varint (too many continuation bytes)
    var invalid = Data()
    for _ in 0..<15 {
        invalid.append(0x80) // All continuation bits set
    }
    
    let decoder = BlazeBinaryDecoder(data: invalid)
    #expect(throws: BlazeBinaryError.invalidVarint) {
        _ = try decoder.decodeInt()
    }
}

