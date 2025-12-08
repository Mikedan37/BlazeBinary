import XCTest
import Foundation
@testable import BlazeBinary

final class StressTestsTests: XCTestCase {
    func testStressRoundTrip() throws {
        // Stress test with 10,000 round-trip encodes
        struct TestStruct: BlazeBinaryCodable {
            var id: UUID
            var count: Int
            var name: String
            
            init(id: UUID, count: Int, name: String) {
                self.id = id
                self.count = count
                self.name = name
    }
        func blazeEncode(to encoder: BlazeBinaryEncoder) throws {
            encoder.encode(id.uuidString)
            encoder.encode(count)
            encoder.encode(name)
        }
        init(from decoder: BlazeBinaryDecoder) throws {
            let idString = try decoder.decodeString()
            guard let uuid = UUID(uuidString: idString) else {
                throw BlazeBinaryError.decodeFailed("Invalid UUID")
            }
            self.id = uuid
            self.count = try decoder.decodeInt()
            self.name = try decoder.decodeString()
        }
    }
    for i in 0..<10000 {
        let original = TestStruct(
            id: UUID(),
            count: i,
            name: "Item \(i)"
        )
        let encoder = BlazeBinaryEncoder()
        try encoder.encode(original)
        let data = encoder.encodedData()
        let decoder = BlazeBinaryDecoder(data: data)
        let decoded = try decoder.decode(TestStruct.self)
        XCTAssert(decoded.id == original.id)
        XCTAssert(decoded.count == original.count)
        XCTAssert(decoded.name == original.name)
    }
}
    func testStressArrays() throws {
        struct Item: BlazeBinaryCodable {
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
    // Test with large arrays
    for size in [10, 100, 1000, 10000] {
        var items: [Item] = []
        for i in 0..<size {
            items.append(Item(value: i))
        }
        let encoder = BlazeBinaryEncoder()
        try encoder.encode(items)
        let data = encoder.encodedData()
        let decoder = BlazeBinaryDecoder(data: data)
        let decoded = try decoder.decodeArray(Item.self)
        XCTAssert(decoded.count == size)
        for i in 0..<size {
            XCTAssert(decoded[i].value == i)
        }
    }
}
    func testStressFrames() throws {
        // Stress test frame encoding/decoding
        for i in 0..<1000 {
            let payload = Data(repeating: UInt8(i % 256), count: 100)
            let frame = try BlazeFrameEncoder.encodeFrame(payload)
            
            let parser = BlazeFrameParser()
            try parser.append(frame)
            let decoded = try parser.nextFrame()
            
            XCTAssert(decoded != nil)
            XCTAssert(decoded == payload)
    }
}
    func testStressMultipleFrames() throws {
        let parser = BlazeFrameParser()
        
        // Encode 100 frames
        var frames: [Data] = []
        for i in 0..<100 {
            let payload = Data([UInt8(i)])
            let frame = try BlazeFrameEncoder.encodeFrame(payload)
            frames.append(frame)
    }
    // Concatenate all frames
    let allFrames = frames.reduce(Data(), +)
    try parser.append(allFrames)
    // Decode all frames
    var decodedCount = 0
    while let frame = try parser.nextFrame() {
        XCTAssert(frame.count == 1)
        XCTAssert(frame[0] == UInt8(decodedCount))
        decodedCount += 1
    }
    XCTAssert(decodedCount == 100)
}
}
