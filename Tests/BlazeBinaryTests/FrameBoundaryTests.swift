import XCTest
import Foundation
@testable import BlazeBinary

final class Frameboundaryteststests: XCTestCase {
    /// Tests for frame boundary cases and buffer management.
    struct FrameBoundaryTests {
        func testFrameExactlyAtMaxSize() throws {
            // Frame exactly at 5MB limit
            let payload = Data(repeating: 0xAA, count: BlazeFrameEncoder.maxFrameSize)
            let frame = try BlazeFrameEncoder.encodeFrame(payload)
            let parser = BlazeFrameParser()
            try parser.append(frame)
            let extracted = try parser.nextFrame()
            XCTAssert(extracted != nil)
            XCTAssert(extracted?.count == BlazeFrameEncoder.maxFrameSize)
        }
        func testFrameOneByteOverMaxSize() throws {
            // Frame one byte over 5MB limit
            let payload = Data(repeating: 0xAA, count: BlazeFrameEncoder.maxFrameSize + 1)
            XCTAssertThrowsError(try BlazeFrameEncoder.encodeFrame(payload)) { error in
                XCTAssertTrue(error is BlazeBinaryError)
                if let bbError = error as? BlazeBinaryError {
                    XCTAssertEqual(bbError, BlazeBinaryError.oversizedFrame)
                }
            }
        }
        func testFrameOneByteUnderMaxSize() throws {
            // Frame one byte under 5MB limit
            let payload = Data(repeating: 0xAA, count: BlazeFrameEncoder.maxFrameSize - 1)
            let frame = try BlazeFrameEncoder.encodeFrame(payload)
            let parser = BlazeFrameParser()
            try parser.append(frame)
            let extracted = try parser.nextFrame()
            XCTAssert(extracted != nil)
            XCTAssert(extracted?.count == BlazeFrameEncoder.maxFrameSize - 1)
        }
        func testBufferExactlyAtMaxSize() throws {
            // Buffer exactly at 10MB limit
            let parser = BlazeFrameParser()
            // Fill buffer to exactly maxBufferSize
            // Create frames that sum to exactly 10MB
            let frameSize = 1000
            let frameCount = BlazeFrameParser.maxBufferSize / (frameSize + 4) // +4 for length prefix
            var totalAppended = 0
            for i in 0..<frameCount {
                let payload = Data(repeating: UInt8(i % 256), count: frameSize)
                let frame = try BlazeFrameEncoder.encodeFrame(payload)
                if totalAppended + frame.count <= BlazeFrameParser.maxBufferSize {
                    try parser.append(frame)
                    totalAppended += frame.count
                } else {
                    break
                }
            }
            // Should be able to extract frames
            var extractedCount = 0
            while let _ = try parser.nextFrame() {
                extractedCount += 1
            }
            XCTAssert(extractedCount > 0)
        }
        func testBufferOneByteOverMaxSize() throws {
            // Buffer one byte over 10MB limit
            let parser = BlazeFrameParser()
            // Fill buffer to maxBufferSize
            let fillSize = BlazeFrameParser.maxBufferSize
            let fillData = Data(repeating: 0xAA, count: fillSize)
            try parser.append(fillData)
            // Try to append one more byte
            let oneMoreByte = Data([0xBB])
            XCTAssertThrowsError(try parser.append(oneMoreByte)) { error in
                XCTAssertTrue(error is BlazeBinaryError)
                if let bbError = error as? BlazeBinaryError {
                    XCTAssertEqual(bbError, BlazeBinaryError.oversizedFrame)
                }
            }
        }
        func testFrameLengthPrefixAtBoundary() throws {
            // Test frame with length prefix exactly at maxFrameSize
            var frame = Data()
            let maxLength = UInt32(BlazeFrameEncoder.maxFrameSize).bigEndian
            frame.append(contentsOf: withUnsafeBytes(of: maxLength) { Data($0) })
            frame.append(Data(repeating: 0xAA, count: BlazeFrameEncoder.maxFrameSize))
            let parser = BlazeFrameParser()
            try parser.append(frame)
            let extracted = try parser.nextFrame()
            XCTAssert(extracted != nil)
            XCTAssert(extracted?.count == BlazeFrameEncoder.maxFrameSize)
        }
        func testFrameLengthPrefixOneOverBoundary() throws {
            // Test frame with length prefix one byte over maxFrameSize
            var frame = Data()
            let overLength = UInt32(BlazeFrameEncoder.maxFrameSize + 1).bigEndian
            frame.append(contentsOf: withUnsafeBytes(of: overLength) { Data($0) })
            let parser = BlazeFrameParser()
            try parser.append(frame)
            XCTAssertThrowsError(try parser.nextFrame()) { error in
                XCTAssertTrue(error is BlazeBinaryError)
                if let bbError = error as? BlazeBinaryError {
                    XCTAssertEqual(bbError, BlazeBinaryError.invalidFrameLength)
                }
            }
        }
        func testMultipleFramesNearBufferLimit() throws {
            // Test multiple frames that approach but don't exceed buffer limit
            let parser = BlazeFrameParser()
            let frameSize = 10000
            let maxFrames = (BlazeFrameParser.maxBufferSize / (frameSize + 4)) - 1
            for i in 0..<maxFrames {
                let payload = Data(repeating: UInt8(i % 256), count: frameSize)
                let frame = try BlazeFrameEncoder.encodeFrame(payload)
                try parser.append(frame)
            }
            // Should be able to extract all frames
            var extractedCount = 0
            while let _ = try parser.nextFrame() {
                extractedCount += 1
            }
            XCTAssert(extractedCount == maxFrames)
        }
        func testFrameParserStateAfterNil() throws {
            // Test that parser state is consistent after returning nil
            let payload = Data([0x01, 0x02, 0x03])
            let frame = try BlazeFrameEncoder.encodeFrame(payload)
            let parser = BlazeFrameParser()
            // Append partial frame
            try parser.append(frame.prefix(5))
            let result1 = try parser.nextFrame()
            XCTAssert(result1 == nil)
            // State should be consistent - can continue
            _ = parser.bufferSize
            try parser.append(frame.suffix(from: 5))
            let result2 = try parser.nextFrame()
            XCTAssert(result2 == payload)
            // Buffer should be empty after extraction
            XCTAssert(parser.bufferSize == 0)
        }
        func testFrameParserAtomicExtraction() throws {
            // Test that frame extraction is atomic (all-or-nothing)
            let payload1 = Data([0x01, 0x02])
            let payload2 = Data([0x03, 0x04])
            let frame1 = try BlazeFrameEncoder.encodeFrame(payload1)
            let frame2 = try BlazeFrameEncoder.encodeFrame(payload2)
            let parser = BlazeFrameParser()
            try parser.append(frame1)
            try parser.append(frame2)
            // Extract first frame
            let extracted1 = try parser.nextFrame()
            XCTAssert(extracted1 == payload1)
            // Buffer should only contain second frame now
            let extracted2 = try parser.nextFrame()
            XCTAssert(extracted2 == payload2)
            // No more frames
            XCTAssert(try parser.nextFrame() == nil)
        }
    }
}
