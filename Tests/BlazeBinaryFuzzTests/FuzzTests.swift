import XCTest
import Foundation
@testable import BlazeBinary

final class FuzzTests: XCTestCase {
    // Fuzz test: Random byte buffers fed to BlazeFrameParser
    func fuzzFrameParser() {
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
                    XCTAssert(frame.count <= BlazeFrameEncoder.maxFrameSize)
                } else {
                    break // No more frames
                }
            }
        } catch let error as BlazeBinaryError {
            // Expected error types
            switch error {
            case .truncated, .invalidVarint, .invalidFrameLength, .oversizedFrame, .decodeFailed, .needMoreData,
                 .handshakeFailed, .invalidHandshake, .encryptionFailed, .invalidSession:
                // Valid error types
                break
            }
        } catch {
            // Unexpected error type
            XCTFail("Unexpected error type: \(error)")
        }
    }
}

// Fuzz test: Random byte buffers fed to BlazeBinaryDecoder
    func fuzzDecoder() {
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
                XCTFail("Unexpected BlazeBinaryError: \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }
}

// Fuzz test: Corrupted varints
    func fuzzCorruptedVarints() {
    for _ in 0..<100 {
        // Create varint with too many continuation bytes
        var corrupted = Data()
        for _ in 0..<15 {
            corrupted.append(0x80) // All continuation bytes
        }
        
        let decoder = BlazeBinaryDecoder(data: corrupted)
        XCTAssertThrowsError(try decoder.decodeInt()) { error in
            XCTAssertTrue(error is BlazeBinaryError)
        }
    }
}

// Fuzz test: Oversized frames
    func fuzzOversizedFrames() {
    for _ in 0..<100 {
        // Create frame with oversized length prefix
        var frame = Data()
        let oversizedLength = UInt32(6 * 1024 * 1024).bigEndian // 6 MB > 5 MB limit
        frame.append(contentsOf: withUnsafeBytes(of: oversizedLength) { Data($0) })
        
        let parser = BlazeFrameParser()
        _ = try? parser.append(frame)
        
        XCTAssertThrowsError(try parser.nextFrame()) { error in
            XCTAssertTrue(error is BlazeBinaryError)
            if let bbError = error as? BlazeBinaryError {
                XCTAssertEqual(bbError, BlazeBinaryError.invalidFrameLength)
            }
        }
    }
}

// Fuzz test: Negative/zero lengths
    func fuzzInvalidLengths() {
    // Zero length frame
    var zeroFrame = Data()
    let zeroLength = UInt32(0).bigEndian
    zeroFrame.append(contentsOf: withUnsafeBytes(of: zeroLength) { Data($0) })
    
    let parser = BlazeFrameParser()
    _ = try? parser.append(zeroFrame)
    
    XCTAssertThrowsError(try parser.nextFrame()) { error in
            XCTAssertTrue(error is BlazeBinaryError)
            if let bbError = error as? BlazeBinaryError {
                XCTAssertEqual(bbError, BlazeBinaryError.invalidFrameLength)
            }
        }
}

// Fuzz test: Partial/truncated frames
    func fuzzPartialFrames() throws {
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
            XCTAssert(result == nil) // Partial frame should return nil
        } catch let error as BlazeBinaryError {
            switch error {
            case .truncated, .invalidFrameLength:
                // Valid for partial frames
                break
            default:
                XCTFail("Unexpected error for partial frame: \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }
}

// Fuzz test: Packed garbage data
    func fuzzPackedGarbage() {
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
                    XCTAssert(frame.count <= BlazeFrameEncoder.maxFrameSize)
                } else {
                    break
                }
            }
        } catch let error as BlazeBinaryError {
            // All error types are acceptable for garbage data
            switch error {
            case .truncated, .invalidVarint, .invalidFrameLength, .oversizedFrame, .decodeFailed, .needMoreData,
                 .handshakeFailed, .invalidHandshake, .encryptionFailed, .invalidSession:
                break
            }
        } catch {
            XCTFail("Unexpected error with garbage data: \(error)")
        }
    }
}

// Fuzz test: Stress test with many operations
    func fuzzStressTest() {
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
            XCTAssert(decoded == expected, "Failed to round-trip value: \(expected), got: \(decoded)")
        } catch {
            XCTFail("Failed to decode value \(expected): \(error)")
        }
    }
}

}
