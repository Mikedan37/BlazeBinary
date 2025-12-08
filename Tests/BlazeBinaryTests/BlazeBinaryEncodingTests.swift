import XCTest
import Foundation

final class BlazeBinaryEncodingTestsTests: XCTestCase {
#if canImport(CoreGraphics)
#endif
// MARK: - Round-Trip Helper
/// Performs a round-trip encoding/decoding test.
/// - Parameter value: The value to encode and decode
/// - Returns: `true` if the decoded value equals the original value
/// - Throws: Any encoding or decoding errors
func roundTrip<T: BlazeBinaryCodable>(_ value: T) throws -> Bool where T: Equatable {
    let encoder = BlazeBinaryEncoder()
    try encoder.encode(value)
    let data = encoder.encodedData()
    let decoder = BlazeBinaryDecoder(data: data)
    let decoded = try decoder.decode(T.self)
    return decoded == value
    }
// MARK: - CGPoint Tests
#if canImport(CoreGraphics)
    func test_encode_decode_point() throws {
        let point = CGPoint(x: 42.5, y: 100.75)
        
        let encoder = BlazeBinaryEncoder()
        try encoder.encode(point)
        let data = encoder.encodedData()
        
        let decoder = BlazeBinaryDecoder(data: data)
        let decoded = try decoder.decode(CGPoint.self)
        
        XCTAssert(decoded.x == point.x)
        XCTAssert(decoded.y == point.y)
        
        // Test round-trip
        let roundTripResult = try roundTrip(point)
        XCTAssert(roundTripResult)
    }
    func test_encode_decode_large_point_array() throws {
        // Create a large array of points
        var points: [CGPoint] = []
        for i in 0..<1000 {
            points.append(CGPoint(x: Double(i), y: Double(i * 2)))
    }
    let encoder = BlazeBinaryEncoder()
    try encoder.encode(points)
    let data = encoder.encodedData()
    let decoder = BlazeBinaryDecoder(data: data)
    let decoded = try decoder.decodeArray(CGPoint.self)
    XCTAssert(decoded.count == points.count)
    for i in 0..<points.count {
        XCTAssert(decoded[i].x == points[i].x)
        XCTAssert(decoded[i].y == points[i].y)
    }
    // Test round-trip
    let roundTripResult = try roundTrip(points)
    XCTAssert(roundTripResult)
}
#endif
// MARK: - CGRect Tests
#if canImport(CoreGraphics)
    func test_encode_decode_rect() throws {
        let rect = CGRect(x: 10.0, y: 20.0, width: 100.0, height: 200.0)
        
        let encoder = BlazeBinaryEncoder()
        try encoder.encode(rect)
        let data = encoder.encodedData()
        
        let decoder = BlazeBinaryDecoder(data: data)
        let decoded = try decoder.decode(CGRect.self)
        
        XCTAssert(decoded.origin.x == rect.origin.x)
        XCTAssert(decoded.origin.y == rect.origin.y)
        XCTAssert(decoded.size.width == rect.size.width)
        XCTAssert(decoded.size.height == rect.size.height)
        
        // Test round-trip
        let roundTripResult = try roundTrip(rect)
        XCTAssert(roundTripResult)
    }
#endif
// MARK: - Dictionary Tests
    func test_encode_decode_string_dict() throws {
        let dict: [String: String] = [
            "key1": "value1",
            "key2": "value2",
            "key3": "value3",
            "alpha": "beta",
            "zebra": "animal"
        ]
        
        let encoder = BlazeBinaryEncoder()
        try encoder.encode(dict)
        let data = encoder.encodedData()
        
        let decoder = BlazeBinaryDecoder(data: data)
        let decoded = try decoder.decode([String: String].self)
        
        XCTAssert(decoded.count == dict.count)
        for (key, value) in dict {
            XCTAssert(decoded[key] == value)
    }
    // Test round-trip
    let roundTripResult = try roundTrip(dict)
    XCTAssert(roundTripResult)
    // Test empty dictionary
    let emptyDict: [String: String] = [:]
    let emptyRoundTrip = try roundTrip(emptyDict)
    XCTAssert(emptyRoundTrip)
}
// MARK: - Round-Trip Consistency Tests
    func test_roundtrip_consistency() throws {
        #if canImport(CoreGraphics)
        // Test CGPoint
        let point1 = CGPoint(x: 1.5, y: 2.5)
        let point2 = CGPoint(x: 1.5, y: 2.5)
        
        let encoder1 = BlazeBinaryEncoder()
        try encoder1.encode(point1)
        let data1 = encoder1.encodedData()
        
        let encoder2 = BlazeBinaryEncoder()
        try encoder2.encode(point2)
        let data2 = encoder2.encodedData()
        
        // Same input should produce same output
        XCTAssert(data1 == data2)
        
        // Test CGRect
        let rect1 = CGRect(x: 10, y: 20, width: 100, height: 200)
        let rect2 = CGRect(x: 10, y: 20, width: 100, height: 200)
        
        let encoder3 = BlazeBinaryEncoder()
        try encoder3.encode(rect1)
        let data3 = encoder3.encodedData()
        
        let encoder4 = BlazeBinaryEncoder()
        try encoder4.encode(rect2)
        let data4 = encoder4.encodedData()
        
        XCTAssert(data3 == data4)
        #endif
        
        // Test Dictionary
        let dict1: [String: String] = ["a": "1", "b": "2", "c": "3"]
        let dict2: [String: String] = ["a": "1", "b": "2", "c": "3"]
        
        let encoder5 = BlazeBinaryEncoder()
        try encoder5.encode(dict1)
        let data5 = encoder5.encodedData()
        
        let encoder6 = BlazeBinaryEncoder()
        try encoder6.encode(dict2)
        let data6 = encoder6.encodedData()
        
        // Dictionary encoding should be deterministic (sorted keys)
        XCTAssert(data5 == data6)
    }
// MARK: - Deterministic Encoding Tests
    func test_deterministic_encoding() throws {
        #if canImport(CoreGraphics)
        // Test CGPoint deterministic encoding
        let point = CGPoint(x: 42.5, y: 100.75)
        
        var previousData: Data?
        for _ in 0..<100 {
            let encoder = BlazeBinaryEncoder()
            try encoder.encode(point)
            let data = encoder.encodedData()
            
            if let prev = previousData {
                // Every encoding should produce identical bytes
                XCTAssert(data == prev)
    }
        previousData = data
    }
    // Test CGRect deterministic encoding
    let rect = CGRect(x: 10.0, y: 20.0, width: 100.0, height: 200.0)
    var previousRectData: Data?
    for _ in 0..<100 {
        let encoder = BlazeBinaryEncoder()
        try encoder.encode(rect)
        let data = encoder.encodedData()
        if let prev = previousRectData {
            XCTAssert(data == prev)
        }
        previousRectData = data
    }
    // Test array of CGPoint deterministic encoding
    let points: [CGPoint] = [
        CGPoint(x: 1.0, y: 2.0),
        CGPoint(x: 3.0, y: 4.0),
        CGPoint(x: 5.0, y: 6.0)
    ]
    var previousArrayData: Data?
    for _ in 0..<100 {
        let encoder = BlazeBinaryEncoder()
        try encoder.encode(points)
        let data = encoder.encodedData()
        if let prev = previousArrayData {
            XCTAssert(data == prev)
        }
        previousArrayData = data
    }
    #endif
    // Test Dictionary deterministic encoding
    let dict: [String: String] = [
        "zebra": "animal",
        "alpha": "beta",
        "key1": "value1"
    ]
    var previousDictData: Data?
    for _ in 0..<100 {
        let encoder = BlazeBinaryEncoder()
        try encoder.encode(dict)
        let data = encoder.encodedData()
        if let prev = previousDictData {
            // Dictionary encoding should be deterministic (sorted keys)
            XCTAssert(data == prev)
        }
        previousDictData = data
    }
}
// MARK: - Handwriting Types Tests
    func test_continuation_request_round_trip() throws {
        let request = HandwritingContinuationRequest(textBefore: "Hello, world")
        
        let encoder = BlazeBinaryEncoder()
        try encoder.encode(request)
        let data = encoder.encodedData()
        
        let decoder = BlazeBinaryDecoder(data: data)
        let decoded = try decoder.decode(HandwritingContinuationRequest.self)
        
        XCTAssert(decoded.textBefore == request.textBefore)
        
        // Test round-trip helper
        let roundTripResult = try roundTrip(request)
        XCTAssert(roundTripResult)
        
        // Test empty string
        let emptyRequest = HandwritingContinuationRequest(textBefore: "")
        let emptyRoundTrip = try roundTrip(emptyRequest)
        XCTAssert(emptyRoundTrip)
        
        // Test long string
        let longText = String(repeating: "A", count: 1000)
        let longRequest = HandwritingContinuationRequest(textBefore: longText)
        let longRoundTrip = try roundTrip(longRequest)
        XCTAssert(longRoundTrip)
    }
    func test_continuation_response_round_trip() throws {
        let response = HandwritingContinuationResponse(predictedText: "This is a prediction")
        
        let encoder = BlazeBinaryEncoder()
        try encoder.encode(response)
        let data = encoder.encodedData()
        
        let decoder = BlazeBinaryDecoder(data: data)
        let decoded = try decoder.decode(HandwritingContinuationResponse.self)
        
        XCTAssert(decoded.predictedText == response.predictedText)
        
        // Test round-trip helper
        let roundTripResult = try roundTrip(response)
        XCTAssert(roundTripResult)
        
        // Test empty string
        let emptyResponse = HandwritingContinuationResponse(predictedText: "")
        let emptyRoundTrip = try roundTrip(emptyResponse)
        XCTAssert(emptyRoundTrip)
        
        // Test unicode characters
        let unicodeResponse = HandwritingContinuationResponse(predictedText: "Hello 🌍 你好 مرحبا")
        let unicodeRoundTrip = try roundTrip(unicodeResponse)
        XCTAssert(unicodeRoundTrip)
    }
    func test_encoding_is_deterministic_across_runs() throws {
        // Test HandwritingContinuationRequest deterministic encoding
        let request = HandwritingContinuationRequest(textBefore: "The quick brown fox")
        
        var previousRequestData: Data?
        for _ in 0..<100 {
            let encoder = BlazeBinaryEncoder()
            try encoder.encode(request)
            let data = encoder.encodedData()
            
            if let prev = previousRequestData {
                // Every encoding should produce identical bytes
                XCTAssert(data == prev)
    }
        previousRequestData = data
    }
    // Test HandwritingContinuationResponse deterministic encoding
    let response = HandwritingContinuationResponse(predictedText: "jumps over the lazy dog")
    var previousResponseData: Data?
    for _ in 0..<100 {
        let encoder = BlazeBinaryEncoder()
        try encoder.encode(response)
        let data = encoder.encodedData()
        if let prev = previousResponseData {
            // Every encoding should produce identical bytes
            XCTAssert(data == prev)
        }
        previousResponseData = data
    }
    // Test that same input produces same output
    let request1 = HandwritingContinuationRequest(textBefore: "Same text")
    let request2 = HandwritingContinuationRequest(textBefore: "Same text")
    let encoder1 = BlazeBinaryEncoder()
    try encoder1.encode(request1)
    let data1 = encoder1.encodedData()
    let encoder2 = BlazeBinaryEncoder()
    try encoder2.encode(request2)
    let data2 = encoder2.encodedData()
    XCTAssert(data1 == data2)
    // Test response deterministic encoding
    let response1 = HandwritingContinuationResponse(predictedText: "Same prediction")
    let response2 = HandwritingContinuationResponse(predictedText: "Same prediction")
    let encoder3 = BlazeBinaryEncoder()
    try encoder3.encode(response1)
    let data3 = encoder3.encodedData()
    let encoder4 = BlazeBinaryEncoder()
    try encoder4.encode(response2)
    let data4 = encoder4.encodedData()
    XCTAssert(data3 == data4)
}
}
}
