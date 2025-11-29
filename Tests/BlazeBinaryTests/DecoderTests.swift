import Testing
@testable import BlazeBinary

@Test func testDecodeUInt32() throws {
    var data = Data()
    data.append(contentsOf: [0x78, 0x56, 0x34, 0x12])
    
    let decoder = BlazeBinaryDecoder(data: data)
    let value = try decoder.decodeUInt32()
    
    #expect(value == 0x12345678)
}

@Test func testDecodeUInt64() throws {
    var data = Data()
    data.append(contentsOf: [0xEF, 0xCD, 0xAB, 0x89, 0x67, 0x45, 0x23, 0x01])
    
    let decoder = BlazeBinaryDecoder(data: data)
    let value = try decoder.decodeUInt64()
    
    #expect(value == 0x0123456789ABCDEF)
}

@Test func testDecodeBool() throws {
    var data = Data()
    data.append(contentsOf: [1, 0])
    
    let decoder = BlazeBinaryDecoder(data: data)
    let trueValue = try decoder.decodeBool()
    let falseValue = try decoder.decodeBool()
    
    #expect(trueValue == true)
    #expect(falseValue == false)
}

@Test func testDecodeBoolInvalid() throws {
    var data = Data()
    data.append(2) // Invalid bool value
    
    let decoder = BlazeBinaryDecoder(data: data)
    
    #expect(throws: BlazeBinaryError.self) {
        _ = try decoder.decodeBool()
    }
}

@Test func testDecodeVarint() throws {
    // Encode some values and decode them
    let encoder = BlazeBinaryEncoder()
    encoder.encode(0)
    encoder.encode(127)
    encoder.encode(128)
    encoder.encode(300)
    
    let decoder = BlazeBinaryDecoder(data: encoder.encodedData())
    #expect(try decoder.decodeInt() == 0)
    #expect(try decoder.decodeInt() == 127)
    #expect(try decoder.decodeInt() == 128)
    #expect(try decoder.decodeInt() == 300)
}

@Test func testDecodeString() throws {
    let encoder = BlazeBinaryEncoder()
    encoder.encode("Hello")
    encoder.encode("")
    
    let decoder = BlazeBinaryDecoder(data: encoder.encodedData())
    #expect(try decoder.decodeString() == "Hello")
    #expect(try decoder.decodeString() == "")
}

@Test func testDecodeData() throws {
    let testData = Data([0x01, 0x02, 0x03])
    let encoder = BlazeBinaryEncoder()
    encoder.encode(testData)
    
    let decoder = BlazeBinaryDecoder(data: encoder.encodedData())
    let decoded = try decoder.decodeData()
    
    #expect(decoded == testData)
}

@Test func testDecodeTruncated() throws {
    var data = Data()
    data.append(contentsOf: [0x78, 0x56]) // Only 2 bytes for UInt32
    
    let decoder = BlazeBinaryDecoder(data: data)
    
    #expect(throws: BlazeBinaryError.truncated) {
        _ = try decoder.decodeUInt32()
    }
}

@Test func testDecodeOversizedData() throws {
    let encoder = BlazeBinaryEncoder()
    // Encode a length that exceeds maxAllowedLength
    let hugeLength = UInt64(20 * 1024 * 1024) // 20 MB
    var data = Data()
    // Encode varint for huge length
    var v = hugeLength
    repeat {
        var byte = UInt8(v & 0x7F)
        v >>= 7
        if v != 0 {
            byte |= 0x80
        }
        data.append(byte)
    } while v != 0
    
    let decoder = BlazeBinaryDecoder(data: data, maxAllowedLength: 10 * 1024 * 1024)
    
    #expect(throws: BlazeBinaryError.self) {
        _ = try decoder.decodeData()
    }
}

