import Testing
import Foundation
@testable import BlazeBinary

struct TestItem: BlazeBinaryCodable {
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

@Test func testEncodeOptionalPresent() throws {
    // Test with a type that conforms to BlazeBinaryDecodable
    let encoder = BlazeBinaryEncoder()
    try encoder.encode(TestItem(value: 42) as TestItem?)
    let data = encoder.encodedData()
    
    let decoder = BlazeBinaryDecoder(data: data)
    let decoded = try decoder.decodeOptional(TestItem.self)
    #expect(decoded?.value == 42)
}

@Test func testEncodeOptionalNil() throws {
    // Test with a type that conforms to BlazeBinaryDecodable
    let encoder = BlazeBinaryEncoder()
    try encoder.encode(nil as TestItem?)
    let data = encoder.encodedData()
    
    let decoder = BlazeBinaryDecoder(data: data)
    let decoded = try decoder.decodeOptional(TestItem.self)
    #expect(decoded == nil)
}

@Test func testEncodeCollection() throws {
    let items = [
        TestItem(value: 1),
        TestItem(value: 2),
        TestItem(value: 3)
    ]
    
    let encoder = BlazeBinaryEncoder()
    try encoder.encodeCollection(items)
    let data = encoder.encodedData()
    
    let decoder = BlazeBinaryDecoder(data: data)
    let decoded = try decoder.decodeCollection() as [TestItem]
    
    #expect(decoded.count == 3)
    #expect(decoded[0].value == 1)
    #expect(decoded[1].value == 2)
    #expect(decoded[2].value == 3)
}

@Test func testEncodeEmptyCollection() throws {
    let items: [TestItem] = []
    
    let encoder = BlazeBinaryEncoder()
    try encoder.encodeCollection(items)
    let data = encoder.encodedData()
    
    let decoder = BlazeBinaryDecoder(data: data)
    let decoded = try decoder.decodeCollection() as [TestItem]
    
    #expect(decoded.isEmpty)
}

@Test func testNestedCollections() throws {
    struct NestedItem: BlazeBinaryCodable {
        var items: [Int]
        
        init(items: [Int]) {
            self.items = items
        }
        
        func blazeEncode(to encoder: BlazeBinaryEncoder) throws {
            try encoder.encode(items.map { TestItem(value: $0) })
        }
        
        init(from decoder: BlazeBinaryDecoder) throws {
            let decoded = try decoder.decodeCollection() as [TestItem]
            self.items = decoded.map { $0.value }
        }
    }
    
    let nested = NestedItem(items: [1, 2, 3, 4, 5])
    let encoder = BlazeBinaryEncoder()
    try encoder.encode(nested)
    let data = encoder.encodedData()
    
    let decoder = BlazeBinaryDecoder(data: data)
    let decoded = try decoder.decode(NestedItem.self)
    
    #expect(decoded.items == [1, 2, 3, 4, 5])
}

