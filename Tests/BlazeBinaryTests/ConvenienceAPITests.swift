import Testing
import Foundation
@testable import BlazeBinary

struct TestItem: BlazeBinaryCodable {
    var value: Int
    
    func blazeEncode(to encoder: BlazeBinaryEncoder) throws {
        encoder.encode(value)
    }
    
    init(from decoder: BlazeBinaryDecoder) throws {
        self.value = try decoder.decodeInt()
    }
}

@Test func testEncodeOptionalPresent() throws {
    let encoder = BlazeBinaryEncoder()
    try encoder.encode("Hello" as String?)
    let data = encoder.encodedData()
    
    let decoder = BlazeBinaryDecoder(data: data)
    let decoded = try decoder.decodeOptional(String.self)
    #expect(decoded == "Hello")
}

@Test func testEncodeOptionalNil() throws {
    let encoder = BlazeBinaryEncoder()
    try encoder.encode(nil as String?)
    let data = encoder.encodedData()
    
    let decoder = BlazeBinaryDecoder(data: data)
    let decoded = try decoder.decodeOptional(String.self)
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
        
        func blazeEncode(to encoder: BlazeBinaryEncoder) throws {
            try encoder.encodeCollection(items.map { TestItem(value: $0) })
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

