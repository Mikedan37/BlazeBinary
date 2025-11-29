import Testing
import Foundation
@testable import BlazeBinary

// Test struct v1 (old format)
struct PersonV1: BlazeBinaryCodable {
    var name: String
    var age: Int
    
    func blazeEncode(to encoder: BlazeBinaryEncoder) throws {
        encoder.encode(name)
        encoder.encode(age)
    }
    
    init(from decoder: BlazeBinaryDecoder) throws {
        self.name = try decoder.decodeString()
        self.age = try decoder.decodeInt()
    }
}

// Test struct v2 (new format with added field)
struct PersonV2: BlazeBinaryCodable {
    var name: String
    var age: Int
    var email: String? // New optional field
    
    func blazeEncode(to encoder: BlazeBinaryEncoder) throws {
        encoder.encode(name)
        encoder.encode(age)
        try encoder.encode(email) // Optional field
    }
    
    init(from decoder: BlazeBinaryDecoder) throws {
        self.name = try decoder.decodeString()
        self.age = try decoder.decodeInt()
        // Try to decode optional field, use nil if not present
        self.email = try? decoder.decodeOptional(String.self)
    }
}

// Test struct v3 (removed field)
struct PersonV3: BlazeBinaryCodable {
    var name: String
    // age field removed
    
    func blazeEncode(to encoder: BlazeBinaryEncoder) throws {
        encoder.encode(name)
    }
    
    init(from decoder: BlazeBinaryDecoder) throws {
        self.name = try decoder.decodeString()
        // Skip age field if present (for backward compatibility)
        // Check if there's remaining data
        if !decoder.remainingData.isEmpty {
            try? decoder.skipUnknownField()
        }
    }
}

@Test func testAddedField() throws {
    // Encode v1
    let v1 = PersonV1(name: "Alice", age: 30)
    let encoder = BlazeBinaryEncoder()
    try encoder.encode(v1)
    let data = encoder.encodedData()
    
    // Decode as v2 (should handle missing email)
    let decoder = BlazeBinaryDecoder(data: data)
    let v2 = try PersonV2(from: decoder)
    
    #expect(v2.name == "Alice")
    #expect(v2.age == 30)
    #expect(v2.email == nil) // Field not in v1 data
}

@Test func testRemovedField() throws {
    // Encode v1 (has age)
    let v1 = PersonV1(name: "Bob", age: 25)
    let encoder = BlazeBinaryEncoder()
    try encoder.encode(v1)
    let data = encoder.encodedData()
    
    // Decode as v3 (age removed, should skip it)
    let decoder = BlazeBinaryDecoder(data: data)
    let v3 = try PersonV3(from: decoder)
    
    #expect(v3.name == "Bob")
}

@Test func testDecodeIfPresent() throws {
    let encoder = BlazeBinaryEncoder()
    encoder.encode("Hello")
    let data = encoder.encodedData()
    
    let decoder = BlazeBinaryDecoder(data: data)
    let present = try decoder.decodeIfPresent(String.self)
    #expect(present == "Hello")
    
    // Try to decode when data is exhausted
    let absent = try decoder.decodeIfPresent(String.self)
    #expect(absent == nil)
}

@Test func testDecodeOptional() throws {
    // Test with present value
    let encoder = BlazeBinaryEncoder()
    try encoder.encode("World" as String?)
    let dataPresent = encoder.encodedData()
    
    let decoderPresent = BlazeBinaryDecoder(data: dataPresent)
    let decodedPresent = try decoderPresent.decodeOptional(String.self)
    #expect(decodedPresent == "World")
    
    // Test with nil value
    let encoderNil = BlazeBinaryEncoder()
    try encoderNil.encode(nil as String?)
    let dataNil = encoderNil.encodedData()
    
    let decoderNil = BlazeBinaryDecoder(data: dataNil)
    let decodedNil = try decoderNil.decodeOptional(String.self)
    #expect(decodedNil == nil)
}

@Test func testSkipUnknownFieldVarint() throws {
    let encoder = BlazeBinaryEncoder()
    encoder.encode(42) // Varint
    encoder.encode("Hello")
    let data = encoder.encodedData()
    
    let decoder = BlazeBinaryDecoder(data: data)
    try decoder.skipUnknownField() // Skip the varint
    let string = try decoder.decodeString()
    #expect(string == "Hello")
}

@Test func testSkipUnknownFieldFixedWidth() throws {
    let encoder = BlazeBinaryEncoder()
    encoder.encode(UInt32(100))
    encoder.encode("World")
    let data = encoder.encodedData()
    
    let decoder = BlazeBinaryDecoder(data: data)
    // Skip UInt32 (4 bytes)
    try decoder.skipUnknownField()
    let string = try decoder.decodeString()
    #expect(string == "World")
}

@Test func testSkipUnknownFieldLengthPrefixed() throws {
    let encoder = BlazeBinaryEncoder()
    encoder.encode(Data([0x01, 0x02, 0x03]))
    encoder.encode("Test")
    let data = encoder.encodedData()
    
    let decoder = BlazeBinaryDecoder(data: data)
    // For length-prefixed fields, decode and discard
    _ = try decoder.decodeData() // Skip the Data field
    let string = try decoder.decodeString()
    #expect(string == "Test")
}

