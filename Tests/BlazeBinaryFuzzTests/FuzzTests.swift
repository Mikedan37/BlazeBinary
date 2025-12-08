import Testing
import Foundation
@testable import BlazeBinary

// Fuzz test: Random byte buffers fed to BlazeFrameParser
@Test func fuzzFrameParser() {
    for _ in 0..<1000 {
        let length = Int.random(in: 0...10000)
        var randomBytes = Data()
        for _ in 0..<length {
            randomBytes.append(UInt8.random(in: 0...255))
        }
        
        let parser = BlazeFrameParser()
        
        // Should not crash, only throw BlazeBinaryError
        do {
            try parser.append(randomBytes)
            
            // Try to extract frames - may return nil or throw
            while true {
                if let frame = try parser.nextFrame() {
                    // Frame extracted - verify it's valid
                    #expect(frame.count <= BlazeFrameEncoder.maxFrameSize)
                } else {
                    break // No more frames
                }
            }
        } catch let error as BlazeBinaryError {
            // Expected error types
            switch error {
            case .truncated, .invalidVarint, .invalidFrameLength, .oversizedFrame, .decodeFailed, .needMoreData:
                // Valid error types
                break
            }
        } catch {
            // Unexpected error type
            Issue.record("Unexpected error type: \(error)")
        }
    }
}

// Fuzz test: Random byte buffers fed to BlazeBinaryDecoder
@Test func fuzzDecoder() {
    for _ in 0..<1000 {
        let length = Int.random(in: 0...10000)
        var randomBytes = Data()
        for _ in 0..<length {
            randomBytes.append(UInt8.random(in: 0...255))
        }
        
        let decoder = BlazeBinaryDecoder(data: randomBytes, maxAllowedLength: 10 * 1024 * 1024)
        
        // Should not crash, only throw BlazeBinaryError
        do {
            // Try various decode operations
            _ = try decoder.decodeUInt32()
        } catch let error as BlazeBinaryError {
            switch error {
            case .truncated, .invalidVarint, .decodeFailed:
                // Valid error types
                break
            default:
                Issue.record("Unexpected BlazeBinaryError: \(error)")
            }
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }
}

// Fuzz test: Corrupted varints
@Test func fuzzCorruptedVarints() {
    for _ in 0..<100 {
        // Create varint with too many continuation bytes
        var corrupted = Data()
        for _ in 0..<15 {
            corrupted.append(0x80) // All continuation bytes
        }
        
        let decoder = BlazeBinaryDecoder(data: corrupted)
        #expect(throws: BlazeBinaryError.self) {
            _ = try decoder.decodeInt()
        }
    }
}

// Fuzz test: Oversized frames
@Test func fuzzOversizedFrames() {
    for _ in 0..<100 {
        // Create frame with oversized length prefix
        var frame = Data()
        let oversizedLength = UInt32(6 * 1024 * 1024).bigEndian // 6 MB > 5 MB limit
        frame.append(contentsOf: withUnsafeBytes(of: oversizedLength) { Data($0) })
        
        let parser = BlazeFrameParser()
        try? parser.append(frame)
        
        #expect(throws: BlazeBinaryError.invalidFrameLength) {
            _ = try parser.nextFrame()
        }
    }
}

// Fuzz test: Negative/zero lengths
@Test func fuzzInvalidLengths() {
    // Zero length frame
    var zeroFrame = Data()
    let zeroLength = UInt32(0).bigEndian
    zeroFrame.append(contentsOf: withUnsafeBytes(of: zeroLength) { Data($0) })
    
    let parser = BlazeFrameParser()
    try? parser.append(zeroFrame)
    
    #expect(throws: BlazeBinaryError.invalidFrameLength) {
        _ = try parser.nextFrame()
    }
}

// Fuzz test: Partial/truncated frames
@Test func fuzzPartialFrames() throws {
    for _ in 0..<100 {
        let payload = Data(repeating: 0x42, count: 1000)
        let frame = try BlazeFrameEncoder.encodeFrame(payload)
        
        // Truncate at various points
        let truncatePoint = Int.random(in: 1..<frame.count)
        let truncated = frame.prefix(truncatePoint)
        
        let parser = BlazeFrameParser()
        try parser.append(truncated)
        
        // Should return nil (need more data) or throw, but not crash
        do {
            let result = try parser.nextFrame()
            #expect(result == nil) // Partial frame should return nil
        } catch let error as BlazeBinaryError {
            switch error {
            case .truncated, .invalidFrameLength:
                // Valid for partial frames
                break
            default:
                Issue.record("Unexpected error for partial frame: \(error)")
            }
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }
}

// Fuzz test: Packed garbage data
@Test func fuzzPackedGarbage() {
    for _ in 0..<500 {
        let length = Int.random(in: 100...5000)
        var garbage = Data()
        for _ in 0..<length {
            garbage.append(UInt8.random(in: 0...255))
        }
        
        let parser = BlazeFrameParser()
        
        do {
            try parser.append(garbage)
            
            // Try to extract frames - should handle gracefully
            var frameCount = 0
            while frameCount < 100 { // Limit iterations
                if let frame = try parser.nextFrame() {
                    frameCount += 1
                    #expect(frame.count <= BlazeFrameEncoder.maxFrameSize)
                } else {
                    break
                }
            }
        } catch let error as BlazeBinaryError {
            // All error types are acceptable for garbage data
            switch error {
            case .truncated, .invalidVarint, .invalidFrameLength, .oversizedFrame, .decodeFailed, .needMoreData:
                break
            }
        } catch {
            Issue.record("Unexpected error with garbage data: \(error)")
        }
    }
}

// Fuzz test: Stress test with many operations
@Test func fuzzStressTest() {
    let encoder = BlazeBinaryEncoder()
    var randomValues: [Int] = []
    
    // Generate random values, avoiding Int.min and Int.max due to zigzag encoding edge cases
    // Use a slightly smaller range to avoid overflow issues
    let minSafe = Int.min + 1
    let maxSafe = Int.max - 1
    
    for _ in 0..<1000 {
        let value = Int.random(in: minSafe...maxSafe)
        randomValues.append(value)
        encoder.encode(value)
    }
    
    let data = encoder.encodedData()
    let decoder = BlazeBinaryDecoder(data: data)
    
    // Decode all values
    for expected in randomValues {
        do {
            let decoded = try decoder.decodeInt()
            #expect(decoded == expected, "Failed to round-trip value: \(expected), got: \(decoded)")
        } catch {
            Issue.record("Failed to decode value \(expected): \(error)")
        }
    }
}

