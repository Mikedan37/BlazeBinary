import XCTest
import Foundation
@testable import BlazeBinary

final class RoundTripTestsTests: XCTestCase {
// Test structs
struct PingRequest: BlazeBinaryCodable {
    var id: UUID
    var message: String
    init(id: UUID, message: String) {
        self.id = id
        self.message = message
    }
    func blazeEncode(to encoder: BlazeBinaryEncoder) throws {
        encoder.encode(id.uuidString)
        encoder.encode(message)
    }
    init(from decoder: BlazeBinaryDecoder) throws {
        let idString = try decoder.decodeString()
        guard let uuid = UUID(uuidString: idString) else {
            throw BlazeBinaryError.decodeFailed("Invalid UUID string")
        }
        self.id = uuid
        self.message = try decoder.decodeString()
    }
}
struct WorkStep: BlazeBinaryCodable {
    var description: String
    var completed: Bool
    init(description: String, completed: Bool) {
        self.description = description
        self.completed = completed
    }
    func blazeEncode(to encoder: BlazeBinaryEncoder) throws {
        encoder.encode(description)
        encoder.encode(completed)
    }
    init(from decoder: BlazeBinaryDecoder) throws {
        self.description = try decoder.decodeString()
        self.completed = try decoder.decodeBool()
    }
}
struct WorkPlan: BlazeBinaryCodable {
    var id: UUID
    var goal: String
    var steps: [WorkStep]
    init(id: UUID, goal: String, steps: [WorkStep]) {
        self.id = id
        self.goal = goal
        self.steps = steps
    }
    func blazeEncode(to encoder: BlazeBinaryEncoder) throws {
        encoder.encode(id.uuidString)
        encoder.encode(goal)
        try encoder.encode(steps)
    }
    init(from decoder: BlazeBinaryDecoder) throws {
        let idString = try decoder.decodeString()
        guard let uuid = UUID(uuidString: idString) else {
            throw BlazeBinaryError.decodeFailed("Invalid UUID string")
        }
        self.id = uuid
        self.goal = try decoder.decodeString()
        self.steps = try decoder.decodeArray(WorkStep.self)
    }
}
    func testRoundTripPrimitives() throws {
        let encoder = BlazeBinaryEncoder()
        encoder.encode(UInt32(42))
        encoder.encode(UInt64(123456789))
        encoder.encode(Int(-100))
        encoder.encode(true)
        encoder.encode(false)
        encoder.encode("Hello, World!")
        encoder.encode(Data([0x01, 0x02, 0x03]))
        
        let decoder = BlazeBinaryDecoder(data: encoder.encodedData())
        XCTAssert(try decoder.decodeUInt32() == 42)
        XCTAssert(try decoder.decodeUInt64() == 123456789)
        XCTAssert(try decoder.decodeInt() == -100)
        XCTAssert(try decoder.decodeBool() == true)
        XCTAssert(try decoder.decodeBool() == false)
        XCTAssert(try decoder.decodeString() == "Hello, World!")
        XCTAssert(try decoder.decodeData() == Data([0x01, 0x02, 0x03]))
    }
    func testRoundTripArrays() throws {
        let encoder = BlazeBinaryEncoder()
        let ints: [Int] = [1, 2, 3, 4, 5]
        let strings: [String] = ["a", "b", "c"]
        
        // Encode arrays manually since Int and String don't conform to BlazeBinaryEncodable
        encoder.encode(Int(ints.count))
        for i in ints {
            encoder.encode(i)
    }
    encoder.encode(Int(strings.count))
    for s in strings {
        encoder.encode(s)
    }
    let decoder = BlazeBinaryDecoder(data: encoder.encodedData())
    let count1 = try decoder.decodeInt()
    XCTAssert(count1 == 5)
    for i in 0..<5 {
        XCTAssert(try decoder.decodeInt() == ints[i])
    }
    let count2 = try decoder.decodeInt()
    XCTAssert(count2 == 3)
    for i in 0..<3 {
        XCTAssert(try decoder.decodeString() == strings[i])
    }
}
    func testRoundTripPingRequest() throws {
        let original = PingRequest(
            id: UUID(),
            message: "Hello, BlazeBinary!"
        )
        
        let encoder = BlazeBinaryEncoder()
        try encoder.encode(original)
        
        let decoder = BlazeBinaryDecoder(data: encoder.encodedData())
        let decoded = try decoder.decode(PingRequest.self)
        
        XCTAssert(decoded.id == original.id)
        XCTAssert(decoded.message == original.message)
    }
    func testRoundTripWorkPlan() throws {
        let original = WorkPlan(
            id: UUID(),
            goal: "Build BlazeBinary",
            steps: [
                WorkStep(description: "Design API", completed: true),
                WorkStep(description: "Implement encoder", completed: true),
                WorkStep(description: "Implement decoder", completed: false),
                WorkStep(description: "Write tests", completed: false)
            ]
        )
        
        let encoder = BlazeBinaryEncoder()
        try encoder.encode(original)
        
        let decoder = BlazeBinaryDecoder(data: encoder.encodedData())
        let decoded = try decoder.decode(WorkPlan.self)
        
        XCTAssert(decoded.id == original.id)
        XCTAssert(decoded.goal == original.goal)
        XCTAssert(decoded.steps.count == original.steps.count)
        
        for i in 0..<decoded.steps.count {
            XCTAssert(decoded.steps[i].description == original.steps[i].description)
            XCTAssert(decoded.steps[i].completed == original.steps[i].completed)
    }
}
    func testRoundTripNestedStructs() throws {
        let plan1 = WorkPlan(
            id: UUID(),
            goal: "First goal",
            steps: [
                WorkStep(description: "Step 1", completed: true)
            ]
        )
        
        let plan2 = WorkPlan(
            id: UUID(),
            goal: "Second goal",
            steps: [
                WorkStep(description: "Step 2", completed: false)
            ]
        )
        
        let encoder = BlazeBinaryEncoder()
        try encoder.encode(plan1)
        try encoder.encode(plan2)
        
        let decoder = BlazeBinaryDecoder(data: encoder.encodedData())
        let decoded1 = try decoder.decode(WorkPlan.self)
        let decoded2 = try decoder.decode(WorkPlan.self)
        
        XCTAssert(decoded1.id == plan1.id)
        XCTAssert(decoded1.goal == plan1.goal)
        XCTAssert(decoded2.id == plan2.id)
        XCTAssert(decoded2.goal == plan2.goal)
    }
    func testDeterministicEncoding() throws {
        let request1 = PingRequest(id: UUID(), message: "Test")
        let request2 = PingRequest(id: request1.id, message: "Test")
        
        let encoder1 = BlazeBinaryEncoder()
        let encoder2 = BlazeBinaryEncoder()
        
        try encoder1.encode(request1)
        try encoder2.encode(request2)
        
        let data1 = encoder1.encodedData()
        let data2 = encoder2.encodedData()
        
        // Same input should produce same output
        XCTAssert(data1 == data2)
    }
    func testDeterminism100Iterations() throws {
        // Test determinism with 100 iterations
        struct TestStruct: BlazeBinaryCodable {
            var value: Int
            var text: String
            
            init(value: Int, text: String) {
                self.value = value
                self.text = text
    }
        func blazeEncode(to encoder: BlazeBinaryEncoder) throws {
            encoder.encode(value)
            encoder.encode(text)
        }
        init(from decoder: BlazeBinaryDecoder) throws {
            self.value = try decoder.decodeInt()
            self.text = try decoder.decodeString()
        }
    }
    let original = TestStruct(value: 42, text: "test")
    var previousData: Data?
    for i in 0..<100 {
        let encoder = BlazeBinaryEncoder()
        try encoder.encode(original)
        let data = encoder.encodedData()
        if let prev = previousData {
            XCTAssert(data == prev, "Encoding is not deterministic at iteration \(i)")
        }
        previousData = data
    }
}
}
