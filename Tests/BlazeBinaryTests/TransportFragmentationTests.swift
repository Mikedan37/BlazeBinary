import Testing
import Foundation
@testable import BlazeBinary

/// Stress tests for frame reassembly under adversarial chunk boundaries.
/// Proves the decoder handles real-world partial reads from OS sockets.
@Suite("Transport Fragmentation Stress")
struct TransportFragmentationTests {

    // MARK: - Single-byte drip feed

    @Test("Single-byte chunk delivery reconstructs frame correctly")
    func singleByteChunks() throws {
        let payload = Data((0..<512).map { UInt8($0 & 0xFF) })
        let frame = try BlazeFrameEncoder.encodeFrame(payload)

        let parser = BlazeFrameParser()
        var decoded: Data?
        for i in 0..<frame.count {
            try parser.append(frame[i...i])
            if let result = try parser.nextFrame() {
                decoded = result
                break
            }
        }
        #expect(decoded == payload)
    }

    // MARK: - Random chunk sizes

    @Test("Random 1-32 byte chunks reconstruct payload")
    func randomChunks() throws {
        let payload = Data(repeating: 0xBE, count: 4096)
        let frame = try BlazeFrameEncoder.encodeFrame(payload)

        let parser = BlazeFrameParser()
        var offset = 0
        var decoded: Data?

        while offset < frame.count {
            let chunkSize = min(Int.random(in: 1...32), frame.count - offset)
            let chunk = frame[offset..<(offset + chunkSize)]
            try parser.append(chunk)
            if let result = try parser.nextFrame() {
                decoded = result
                break
            }
            offset += chunkSize
        }
        #expect(decoded == payload)
    }

    // MARK: - Multiple frames in single buffer

    @Test("Two frames concatenated decode independently")
    func backToBackFrames() throws {
        let p1 = Data(repeating: 0xAA, count: 100)
        let p2 = Data(repeating: 0xBB, count: 200)
        let f1 = try BlazeFrameEncoder.encodeFrame(p1)
        let f2 = try BlazeFrameEncoder.encodeFrame(p2)

        var combined = Data()
        combined.append(f1)
        combined.append(f2)

        let parser = BlazeFrameParser()
        try parser.append(combined)

        let d1 = try parser.nextFrame()
        let d2 = try parser.nextFrame()

        #expect(d1 == p1)
        #expect(d2 == p2)
    }

    // MARK: - Split exactly at header/payload boundary

    @Test("Split at header-payload boundary decodes correctly")
    func headerBoundarySplit() throws {
        let payload = Data(repeating: 0xCC, count: 500)
        let frame = try BlazeFrameEncoder.encodeFrame(payload)

        // v2 frame: 1 type + 1 compression + 4 length = 6 byte header
        let headerSize = 6
        guard frame.count > headerSize else {
            Issue.record("Frame too small for boundary test")
            return
        }

        let parser = BlazeFrameParser()
        try parser.append(frame.prefix(headerSize))
        #expect(try parser.nextFrame() == nil, "Should not decode from header alone")

        try parser.append(frame.suffix(from: headerSize))
        let decoded = try parser.nextFrame()
        #expect(decoded == payload)
    }

    // MARK: - Stress: 100 frames via random chunking

    @Test("100 frames via random chunking all decode correctly")
    func hundredFramesRandomChunks() throws {
        var payloads: [Data] = []
        var combined = Data()
        for i in 0..<100 {
            let size = 50 + (i * 7) % 500
            let payload = Data((0..<size).map { UInt8(($0 + i) & 0xFF) })
            payloads.append(payload)
            combined.append(try BlazeFrameEncoder.encodeFrame(payload))
        }

        let parser = BlazeFrameParser()
        var offset = 0
        var decoded: [Data] = []

        while offset < combined.count {
            let chunkSize = min(Int.random(in: 1...64), combined.count - offset)
            try parser.append(combined[offset..<(offset + chunkSize)])
            offset += chunkSize

            while let frame = try parser.nextFrame() {
                decoded.append(frame)
            }
        }

        #expect(decoded.count == 100)
        for (i, d) in decoded.enumerated() {
            #expect(d == payloads[i], "Frame \(i) mismatch")
        }
    }

    // MARK: - Empty payload

    @Test("Minimal 1-byte payload round-trips through single-byte delivery")
    func minimalPayload() throws {
        let payload = Data([0x42])
        let frame = try BlazeFrameEncoder.encodeFrame(payload)

        let parser = BlazeFrameParser()
        for i in 0..<frame.count {
            try parser.append(frame[i...i])
            if let decoded = try parser.nextFrame() {
                #expect(decoded == payload)
                return
            }
        }
        Issue.record("Minimal payload frame never decoded")
    }

    // MARK: - Max-size payload

    @Test("Near-max-size payload survives chunked delivery")
    func largePayload() throws {
        let payload = Data(repeating: 0xDD, count: 1_000_000)
        let frame = try BlazeFrameEncoder.encodeFrame(payload)

        let parser = BlazeFrameParser()
        var offset = 0
        while offset < frame.count {
            let chunkSize = min(Int.random(in: 1024...8192), frame.count - offset)
            try parser.append(frame[offset..<(offset + chunkSize)])
            offset += chunkSize

            if let decoded = try parser.nextFrame() {
                #expect(decoded.count == payload.count)
                #expect(decoded == payload)
                return
            }
        }
        Issue.record("Large payload never decoded")
    }
}
