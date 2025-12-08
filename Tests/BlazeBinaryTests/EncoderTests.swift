import XCTest
@testable import BlazeBinary

func testEncodeUInt32() {
    let encoder = BlazeBinaryEncoder()
    encoder.encode(UInt32(0x12345678))
    let data = encoder.encodedData()
    
    XCTAssert(data.count == 4)
    XCTAssert(data[0] == 0x78)
    XCTAssert(data[1] == 0x56)
    XCTAssert(data[2] == 0x34)
    XCTAssert(data[3] == 0x12)
}

func testEncodeUInt64() {
    let encoder = BlazeBinaryEncoder()
    encoder.encode(UInt64(0x0123456789ABCDEF))
    let data = encoder.encodedData()
    
    XCTAssert(data.count == 8)
    XCTAssert(data[0] == 0xEF)
    XCTAssert(data[7] == 0x01)
}

func testEncodeBool() {
    let encoder = BlazeBinaryEncoder()
    encoder.encode(true)
    encoder.encode(false)
    let data = encoder.encodedData()
    
    XCTAssert(data.count == 2)
    XCTAssert(data[0] == 1)
    XCTAssert(data[1] == 0)
}

func testEncodeVarint() {
    let encoder = BlazeBinaryEncoder()
    encoder.encode(0)
    encoder.encode(127)
    encoder.encode(128)
    encoder.encode(300)
    let data = encoder.encodedData()
    
    // 0: 1 byte
    // 127: 1 byte
    // 128: 2 bytes (0x80, 0x01)
    // 300: 2 bytes (0xAC, 0x02)
    XCTAssert(data.count >= 6)
}

func testEncodeString() {
    let encoder = BlazeBinaryEncoder()
    encoder.encode("Hello")
    encoder.encode("")
    let data = encoder.encodedData()
    
    // "Hello" = 5 bytes + varint(5) = 1 byte = 6 bytes total
    // "" = 0 bytes + varint(0) = 1 byte = 1 byte total
    XCTAssert(data.count >= 7)
}

func testEncodeData() {
    let encoder = BlazeBinaryEncoder()
    let testData = Data([0x01, 0x02, 0x03])
    encoder.encode(testData)
    let data = encoder.encodedData()
    
    // 3 bytes + varint(3) = 1 byte = 4 bytes total
    XCTAssert(data.count >= 4)
    XCTAssert(data[data.count - 3] == 0x01)
    XCTAssert(data[data.count - 2] == 0x02)
    XCTAssert(data[data.count - 1] == 0x03)
}

