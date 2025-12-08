import Testing
import Foundation
@testable import BlazeBinary

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

@Test func testRoundTripPrimitives() throws {
    let encoder = BlazeBinaryEncoder()
    encoder.encode(UInt32(42))
    encoder.encode(UInt64(123456789))
    encoder.encode(Int(-100))
    encoder.encode(true)
    encoder.encode(false)
    encoder.encode("Hello, World!")
    encoder.encode(Data([0x01, 0x02, 0x03]))
    
    let decoder = BlazeBinaryDecoder(data: encoder.encodedData())
    #expect(try decoder.decodeUInt32() == 42)
    #expect(try decoder.decodeUInt64() == 123456789)
    #expect(try decoder.decodeInt() == -100)
    #expect(try decoder.decodeBool() == true)
    #expect(try decoder.decodeBool() == false)
    #expect(try decoder.decodeString() == "Hello, World!")
    #expect(try decoder.decodeData() == Data([0x01, 0x02, 0x03]))
}

@Test func testRoundTripArrays() throws {
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
    #expect(count1 == 5)
    for i in 0..<5 {
        #expect(try decoder.decodeInt() == ints[i])
    }
    
    let count2 = try decoder.decodeInt()
    #expect(count2 == 3)
    for i in 0..<3 {
        #expect(try decoder.decodeString() == strings[i])
    }
}

@Test func testRoundTripPingRequest() throws {
    let original = PingRequest(
        id: UUID(),
        message: "Hello, BlazeBinary!"
    )
    
    let encoder = BlazeBinaryEncoder()
    try encoder.encode(original)
    
    let decoder = BlazeBinaryDecoder(data: encoder.encodedData())
    let decoded = try decoder.decode(PingRequest.self)
    
    #expect(decoded.id == original.id)
    #expect(decoded.message == original.message)
}

@Test func testRoundTripWorkPlan() throws {
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
    
    #expect(decoded.id == original.id)
    #expect(decoded.goal == original.goal)
    #expect(decoded.steps.count == original.steps.count)
    
    for i in 0..<decoded.steps.count {
        #expect(decoded.steps[i].description == original.steps[i].description)
        #expect(decoded.steps[i].completed == original.steps[i].completed)
    }
}

@Test func testRoundTripNestedStructs() throws {
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
    
    #expect(decoded1.id == plan1.id)
    #expect(decoded1.goal == plan1.goal)
    #expect(decoded2.id == plan2.id)
    #expect(decoded2.goal == plan2.goal)
}

@Test func testDeterministicEncoding() throws {
    let request1 = PingRequest(id: UUID(), message: "Test")
    let request2 = PingRequest(id: request1.id, message: "Test")
    
    let encoder1 = BlazeBinaryEncoder()
    let encoder2 = BlazeBinaryEncoder()
    
    try encoder1.encode(request1)
    try encoder2.encode(request2)
    
    let data1 = encoder1.encodedData()
    let data2 = encoder2.encodedData()
    
    // Same input should produce same output
    #expect(data1 == data2)
}

@Test func testDeterminism100Iterations() throws {
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
            #expect(data == prev, "Encoding is not deterministic at iteration \(i)")
        }
        previousData = data
    }
}

