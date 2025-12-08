import XCTest
import Foundation
@testable import BlazeBinary

final class Framestressteststests: XCTestCase {
    /// Stress tests for incremental framing with random chunk boundaries.
    struct FrameStressTests {
        func testIncrementalFramingRandomChunks() throws {
            // Create a payload
            let payload = Data(repeating: 0xAA, count: 1000)
            let frame = try BlazeFrameEncoder.encodeFrame(payload)
            // Split frame into random chunks
            var chunks: [Data] = []
            var remaining = frame
            var chunkSizes = [100, 200, 150, 300, 250] // Various chunk sizes
            for chunkSize in chunkSizes {
                if remaining.count <= chunkSize {
                    chunks.append(remaining)
                    break
                }
                chunks.append(remaining.prefix(chunkSize))
                remaining = remaining.suffix(from: chunkSize)
            }
            if !remaining.isEmpty {
                chunks.append(remaining)
            }
            // Parse incrementally
            let parser = BlazeFrameParser()
            var extractedPayload: Data?
            for chunk in chunks {
                try parser.append(chunk)
                if let payload = try parser.nextFrame() {
                    extractedPayload = payload
                    break
                }
            }
            XCTAssert(extractedPayload != nil)
            XCTAssert(extractedPayload == payload)
        }
        func testMultipleFramesRandomChunks() throws {
            // Create multiple frames
            let payload1 = Data([0x01, 0x02])
            let payload2 = Data([0x03, 0x04, 0x05])
            let payload3 = Data([0x06, 0x07])
            let frame1 = try BlazeFrameEncoder.encodeFrame(payload1)
            let frame2 = try BlazeFrameEncoder.encodeFrame(payload2)
            let frame3 = try BlazeFrameEncoder.encodeFrame(payload3)
            let allFrames = frame1 + frame2 + frame3
            // Split into random chunks
            let chunkSizes = [5, 10, 8, 15, 20, 5]
            var chunks: [Data] = []
            var remaining = allFrames
            for chunkSize in chunkSizes {
                if remaining.isEmpty { break }
                if remaining.count <= chunkSize {
                    chunks.append(remaining)
                    break
                }
                chunks.append(remaining.prefix(chunkSize))
                remaining = remaining.suffix(from: chunkSize)
            }
            if !remaining.isEmpty {
                chunks.append(remaining)
            }
            // Parse incrementally
            let parser = BlazeFrameParser()
            var extractedPayloads: [Data] = []
            for chunk in chunks {
                try parser.append(chunk)
                while let payload = try parser.nextFrame() {
                    extractedPayloads.append(payload)
                }
            }
            XCTAssert(extractedPayloads.count == 3)
            XCTAssert(extractedPayloads[0] == payload1)
            XCTAssert(extractedPayloads[1] == payload2)
            XCTAssert(extractedPayloads[2] == payload3)
        }
        func testFrameBoundaryAtChunkBoundary() throws {
            // Test frame boundary exactly at chunk boundary
            let payload1 = Data([0x01, 0x02])
            let payload2 = Data([0x03, 0x04])
            let frame1 = try BlazeFrameEncoder.encodeFrame(payload1)
            let frame2 = try BlazeFrameEncoder.encodeFrame(payload2)
            // Split exactly at frame boundary
            let chunk1 = frame1
            let chunk2 = frame2
            let parser = BlazeFrameParser()
            try parser.append(chunk1)
            let payload1Extracted = try parser.nextFrame()
            XCTAssert(payload1Extracted == payload1)
            try parser.append(chunk2)
            let payload2Extracted = try parser.nextFrame()
            XCTAssert(payload2Extracted == payload2)
        }
        func testPartialLengthPrefix() throws {
            // Length prefix split across chunks
            let payload = Data([0x01, 0x02, 0x03])
            let frame = try BlazeFrameEncoder.encodeFrame(payload)
            // Split length prefix (4 bytes) across chunks
            let chunk1 = frame.prefix(2) // First 2 bytes of length prefix
            let chunk2 = frame.suffix(from: 2) // Rest of frame
            let parser = BlazeFrameParser()
            try parser.append(chunk1)
            let result1 = try parser.nextFrame()
            XCTAssert(result1 == nil) // Need more data
            try parser.append(chunk2)
            let result2 = try parser.nextFrame()
            XCTAssert(result2 == payload)
        }
        func testManySmallFrames() throws {
            // Test parsing many small frames
            let frameCount = 1000
            var frames: [Data] = []
            for i in 0..<frameCount {
                let payload = Data([UInt8(i % 256)])
                let frame = try BlazeFrameEncoder.encodeFrame(payload)
                frames.append(frame)
            }
            let allFrames = frames.reduce(Data(), +)
            let parser = BlazeFrameParser()
            try parser.append(allFrames)
            var extractedCount = 0
            while let _ = try parser.nextFrame() {
                extractedCount += 1
            }
            XCTAssert(extractedCount == frameCount)
        }
        func testLargeFrameNearLimit() throws {
            // Test frame near 5MB limit
            let payloadSize = BlazeFrameEncoder.maxFrameSize - 100 // Just under limit
            let payload = Data(repeating: 0xAA, count: payloadSize)
            let frame = try BlazeFrameEncoder.encodeFrame(payload)
            let parser = BlazeFrameParser()
            try parser.append(frame)
            let extracted = try parser.nextFrame()
            XCTAssert(extracted != nil)
            XCTAssert(extracted?.count == payloadSize)
        }
        func testBufferNearLimit() throws {
            // Test buffer near 10MB limit
            let parser = BlazeFrameParser()
            // Add frames until near limit
            let frameSize = 1000
            let maxFrames = (BlazeFrameParser.maxBufferSize / frameSize) - 1
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
        func testBufferExceedsLimit() throws {
            // Test that buffer limit is enforced
            let parser = BlazeFrameParser()
            // Create data that exceeds buffer limit
            let hugeData = Data(repeating: 0xAA, count: BlazeFrameParser.maxBufferSize + 1)
            XCTAssertThrowsError(try parser.append(hugeData)) { error in
                XCTAssertTrue(error is BlazeBinaryError)
                if let bbError = error as? BlazeBinaryError {
                    XCTAssertEqual(bbError, BlazeBinaryError.oversizedFrame)
                }
            }
        }
    }
}
