import XCTest
import Foundation
@testable import BlazeBinary

final class EvolutionTestsTests: XCTestCase {
// Test struct v1 (old format)
struct PersonV1: BlazeBinaryCodable {
    var name: String
    var age: Int
    init(name: String, age: Int) {
        self.name = name
        self.age = age
    }
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
    init(name: String, age: Int, email: String? = nil) {
        self.name = name
        self.age = age
        self.email = email
    }
    func blazeEncode(to encoder: BlazeBinaryEncoder) throws {
        encoder.encode(name)
        encoder.encode(age)
        if let email = email {
            encoder.encode(email)
        }
    }
    init(from decoder: BlazeBinaryDecoder) throws {
        self.name = try decoder.decodeString()
        self.age = try decoder.decodeInt()
        // Try to decode optional field, use nil if not present
        // Check if there's remaining data for the optional field
        if !decoder.remainingData.isEmpty {
            self.email = try? decoder.decodeString()
        } else {
            self.email = nil
        }
    }
}
// Test struct v3 (removed field)
struct PersonV3: BlazeBinaryCodable {
    var name: String
    // age field removed
    init(name: String) {
        self.name = name
    }
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
    func testAddedField() throws {
        // Encode v1
        let v1 = PersonV1(name: "Alice", age: 30)
        let encoder = BlazeBinaryEncoder()
        try encoder.encode(v1)
        let data = encoder.encodedData()
        
        // Decode as v2 (should handle missing email)
        let decoder = BlazeBinaryDecoder(data: data)
        let v2 = try PersonV2(from: decoder)
        
        XCTAssert(v2.name == "Alice")
        XCTAssert(v2.age == 30)
        XCTAssert(v2.email == nil) // Field not in v1 data
    }
    func testRemovedField() throws {
        // Encode v1 (has age)
        let v1 = PersonV1(name: "Bob", age: 25)
        let encoder = BlazeBinaryEncoder()
        try encoder.encode(v1)
        let data = encoder.encodedData()
        
        // Decode as v3 (age removed, should skip it)
        let decoder = BlazeBinaryDecoder(data: data)
        let v3 = try PersonV3(from: decoder)
        
        XCTAssert(v3.name == "Bob")
    }
    func testDecodeIfPresent() throws {
        // Test with a type that conforms to BlazeBinaryCodable
        struct TestStruct: BlazeBinaryCodable {
            var value: Int
            
            init(value: Int) {
                self.value = value
    }
        func blazeEncode(to encoder: BlazeBinaryEncoder) throws {
            encoder.encode(value)
        }
        init(from decoder: BlazeBinaryDecoder) throws {
            self.value = try decoder.decodeInt()
        }
    }
    let encoder = BlazeBinaryEncoder()
    try encoder.encode(TestStruct(value: 42))
    let data = encoder.encodedData()
    let decoder = BlazeBinaryDecoder(data: data)
    let present = try decoder.decodeIfPresent(TestStruct.self)
    XCTAssert(present?.value == 42)
    // Try to decode when data is exhausted
    let absent = try decoder.decodeIfPresent(TestStruct.self)
    XCTAssert(absent == nil)
}
    func testDecodeOptional() throws {
        // Test with a type that conforms to BlazeBinaryCodable
        struct TestStruct: BlazeBinaryCodable {
            var value: Int
            
            init(value: Int) {
                self.value = value
    }
        func blazeEncode(to encoder: BlazeBinaryEncoder) throws {
            encoder.encode(value)
        }
        init(from decoder: BlazeBinaryDecoder) throws {
            self.value = try decoder.decodeInt()
        }
    }
    // Test with present value
    let encoder = BlazeBinaryEncoder()
    try encoder.encode(TestStruct(value: 100) as TestStruct?)
    let dataPresent = encoder.encodedData()
    let decoderPresent = BlazeBinaryDecoder(data: dataPresent)
    let decodedPresent = try decoderPresent.decodeOptional(TestStruct.self)
    XCTAssert(decodedPresent?.value == 100)
    // Test with nil value
    let encoderNil = BlazeBinaryEncoder()
    try encoderNil.encode(nil as TestStruct?)
    let dataNil = encoderNil.encodedData()
    let decoderNil = BlazeBinaryDecoder(data: dataNil)
    let decodedNil = try decoderNil.decodeOptional(TestStruct.self)
    XCTAssert(decodedNil == nil)
}
    func testSkipUnknownFieldVarint() throws {
        let encoder = BlazeBinaryEncoder()
        encoder.encode(42) // Varint
        encoder.encode("Hello")
        let data = encoder.encodedData()
        
        let decoder = BlazeBinaryDecoder(data: data)
        try decoder.skipUnknownField() // Skip the varint
        let string = try decoder.decodeString()
        XCTAssert(string == "Hello")
    }
    func testSkipUnknownFieldFixedWidth() throws {
        let encoder = BlazeBinaryEncoder()
        encoder.encode(UInt32(100))
        encoder.encode("World")
        let data = encoder.encodedData()
        
        let decoder = BlazeBinaryDecoder(data: data)
        // Skip UInt32 (4 bytes)
        try decoder.skipUnknownField()
        let string = try decoder.decodeString()
        XCTAssert(string == "World")
    }
    func testSkipUnknownFieldLengthPrefixed() throws {
        let encoder = BlazeBinaryEncoder()
        encoder.encode(Data([0x01, 0x02, 0x03]))
        encoder.encode("Test")
        let data = encoder.encodedData()
        
        let decoder = BlazeBinaryDecoder(data: data)
        // For length-prefixed fields, decode and discard
        _ = try decoder.decodeData() // Skip the Data field
        let string = try decoder.decodeString()
        XCTAssert(string == "Test")
    }
}
