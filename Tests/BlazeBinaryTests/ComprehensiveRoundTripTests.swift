import Testing
import Foundation
@testable import BlazeBinary

/// Comprehensive round-trip tests for all primitive and composite types.
struct ComprehensiveRoundTripTests {
    
    // MARK: - Primitive Round-Trip Tests
    
    @Test func testRoundTripUInt32AllValues() throws {
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
            #expect(decoded == value, "Failed for UInt32: \(value)")
        }
    }
    
    @Test func testRoundTripUInt64AllValues() throws {
        let testValues: [UInt64] = [
            0,
            1,
            0xFF,
            0xFFFF,
            0xFFFFFFFF,
            0xFFFFFFFFFFFFFFFF,
            0x0123456789ABCDEF
        ]
        
        for value in testValues {
            let encoder = BlazeBinaryEncoder()
            encoder.encode(value)
            let data = encoder.encodedData()
            
            let decoder = BlazeBinaryDecoder(data: data)
            let decoded = try decoder.decodeUInt64()
            #expect(decoded == value, "Failed for UInt64: \(value)")
        }
    }
    
    @Test func testRoundTripIntAllValues() throws {
        let testValues: [Int] = [
            Int.min,
            Int.min + 1,
            -1000,
            -100,
            -1,
            0,
            1,
            100,
            1000,
            Int.max - 1,
            Int.max
        ]
        
        for value in testValues {
            let encoder = BlazeBinaryEncoder()
            encoder.encode(value)
            let data = encoder.encodedData()
            
            let decoder = BlazeBinaryDecoder(data: data)
            let decoded = try decoder.decodeInt()
            #expect(decoded == value, "Failed for Int: \(value)")
        }
    }
    
    @Test func testRoundTripBool() throws {
        let encoder = BlazeBinaryEncoder()
        encoder.encode(true)
        encoder.encode(false)
        let data = encoder.encodedData()
        
        let decoder = BlazeBinaryDecoder(data: data)
        #expect(try decoder.decodeBool() == true)
        #expect(try decoder.decodeBool() == false)
    }
    
    @Test func testRoundTripStringVariousLengths() throws {
        let testStrings = [
            "",
            "a",
            "Hello",
            "Hello, World!",
            String(repeating: "A", count: 100),
            String(repeating: "测试", count: 50), // Unicode
            "🚀🔥💯" // Emoji
        ]
        
        for str in testStrings {
            let encoder = BlazeBinaryEncoder()
            encoder.encode(str)
            let data = encoder.encodedData()
            
            let decoder = BlazeBinaryDecoder(data: data)
            let decoded = try decoder.decodeString()
            #expect(decoded == str, "Failed for string: '\(str)'")
        }
    }
    
    @Test func testRoundTripDataVariousLengths() throws {
        let testData = [
            Data(),
            Data([0x01]),
            Data([0x01, 0x02, 0x03]),
            Data(repeating: 0xAA, count: 100),
            Data(repeating: 0xFF, count: 1000)
        ]
        
        for data in testData {
            let encoder = BlazeBinaryEncoder()
            encoder.encode(data)
            let encoded = encoder.encodedData()
            
            let decoder = BlazeBinaryDecoder(data: encoded)
            let decoded = try decoder.decodeData()
            #expect(decoded == data, "Failed for Data of length: \(data.count)")
        }
    }
    
    // MARK: - Composite Type Round-Trip Tests
    
    struct SimpleStruct: BlazeBinaryCodable {
        var a: Int
        var b: String
        var c: Bool
        
        init(a: Int, b: String, c: Bool) {
            self.a = a
            self.b = b
            self.c = c
        }
        
        func blazeEncode(to encoder: BlazeBinaryEncoder) throws {
            encoder.encode(a)
            encoder.encode(b)
            encoder.encode(c)
        }
        
        init(from decoder: BlazeBinaryDecoder) throws {
            self.a = try decoder.decodeInt()
            self.b = try decoder.decodeString()
            self.c = try decoder.decodeBool()
        }
    }
    
    @Test func testRoundTripSimpleStruct() throws {
        let original = SimpleStruct(a: 42, b: "test", c: true)
        
        let encoder = BlazeBinaryEncoder()
        try encoder.encode(original)
        let data = encoder.encodedData()
        
        let decoder = BlazeBinaryDecoder(data: data)
        let decoded = try decoder.decode(SimpleStruct.self)
        
        #expect(decoded.a == original.a)
        #expect(decoded.b == original.b)
        #expect(decoded.c == original.c)
    }
    
    struct NestedStruct: BlazeBinaryCodable {
        var inner: SimpleStruct
        var value: Int
        
        init(inner: SimpleStruct, value: Int) {
            self.inner = inner
            self.value = value
        }
        
        func blazeEncode(to encoder: BlazeBinaryEncoder) throws {
            try encoder.encode(inner)
            encoder.encode(value)
        }
        
        init(from decoder: BlazeBinaryDecoder) throws {
            self.inner = try decoder.decode(SimpleStruct.self)
            self.value = try decoder.decodeInt()
        }
    }
    
    @Test func testRoundTripNestedStruct() throws {
        let original = NestedStruct(
            inner: SimpleStruct(a: 10, b: "nested", c: false),
            value: 99
        )
        
        let encoder = BlazeBinaryEncoder()
        try encoder.encode(original)
        let data = encoder.encodedData()
        
        let decoder = BlazeBinaryDecoder(data: data)
        let decoded = try decoder.decode(NestedStruct.self)
        
        #expect(decoded.inner.a == original.inner.a)
        #expect(decoded.inner.b == original.inner.b)
        #expect(decoded.inner.c == original.inner.c)
        #expect(decoded.value == original.value)
    }
    
    struct ArrayStruct: BlazeBinaryCodable {
        var items: [SimpleStruct]
        
        init(items: [SimpleStruct]) {
            self.items = items
        }
        
        func blazeEncode(to encoder: BlazeBinaryEncoder) throws {
            try encoder.encode(items)
        }
        
        init(from decoder: BlazeBinaryDecoder) throws {
            self.items = try decoder.decodeArray(SimpleStruct.self)
        }
    }
    
    @Test func testRoundTripArrayStruct() throws {
        let original = ArrayStruct(items: [
            SimpleStruct(a: 1, b: "one", c: true),
            SimpleStruct(a: 2, b: "two", c: false),
            SimpleStruct(a: 3, b: "three", c: true)
        ])
        
        let encoder = BlazeBinaryEncoder()
        try encoder.encode(original)
        let data = encoder.encodedData()
        
        let decoder = BlazeBinaryDecoder(data: data)
        let decoded = try decoder.decode(ArrayStruct.self)
        
        #expect(decoded.items.count == original.items.count)
        for i in 0..<decoded.items.count {
            #expect(decoded.items[i].a == original.items[i].a)
            #expect(decoded.items[i].b == original.items[i].b)
            #expect(decoded.items[i].c == original.items[i].c)
        }
    }
    
    @Test func testRoundTripEmptyArray() throws {
        let original = ArrayStruct(items: [])
        
        let encoder = BlazeBinaryEncoder()
        try encoder.encode(original)
        let data = encoder.encodedData()
        
        let decoder = BlazeBinaryDecoder(data: data)
        let decoded = try decoder.decode(ArrayStruct.self)
        
        #expect(decoded.items.isEmpty)
    }
    
    // MARK: - Determinism Tests
    
    @Test func testDeterminismPrimitives() throws {
        let values: [(Int, String)] = [
            (42, "test1"),
            (100, "test2"),
            (-50, "test3")
        ]
        
        var previousData: Data?
        
        for _ in 0..<100 {
            let encoder = BlazeBinaryEncoder()
            for (intVal, strVal) in values {
                encoder.encode(intVal)
                encoder.encode(strVal)
            }
            let data = encoder.encodedData()
            
            if let prev = previousData {
                #expect(data == prev, "Encoding is not deterministic")
            }
            previousData = data
        }
    }
    
    @Test func testDeterminismComposite() throws {
        let original = SimpleStruct(a: 42, b: "test", c: true)
        var previousData: Data?
        
        for _ in 0..<100 {
            let encoder = BlazeBinaryEncoder()
            try encoder.encode(original)
            let data = encoder.encodedData()
            
            if let prev = previousData {
                #expect(data == prev, "Encoding is not deterministic")
            }
            previousData = data
        }
    }
    
    // MARK: - Edge Case Tests
    
    @Test func testRoundTripMaxValues() throws {
        let encoder = BlazeBinaryEncoder()
        encoder.encode(UInt32.max)
        encoder.encode(UInt64.max)
        encoder.encode(Int.max)
        encoder.encode(Int.min)
        let data = encoder.encodedData()
        
        let decoder = BlazeBinaryDecoder(data: data)
        #expect(try decoder.decodeUInt32() == UInt32.max)
        #expect(try decoder.decodeUInt64() == UInt64.max)
        #expect(try decoder.decodeInt() == Int.max)
        #expect(try decoder.decodeInt() == Int.min)
    }
    
    @Test func testRoundTripZeroValues() throws {
        let encoder = BlazeBinaryEncoder()
        encoder.encode(UInt32(0))
        encoder.encode(UInt64(0))
        encoder.encode(Int(0))
        encoder.encode(false)
        encoder.encode("")
        encoder.encode(Data())
        let data = encoder.encodedData()
        
        let decoder = BlazeBinaryDecoder(data: data)
        #expect(try decoder.decodeUInt32() == 0)
        #expect(try decoder.decodeUInt64() == 0)
        #expect(try decoder.decodeInt() == 0)
        #expect(try decoder.decodeBool() == false)
        #expect(try decoder.decodeString() == "")
        #expect(try decoder.decodeData().isEmpty)
    }
}

