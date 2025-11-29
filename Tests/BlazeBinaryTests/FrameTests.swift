import Testing
@testable import BlazeBinary

@Test func testEncodeFrame() throws {
    let payload = Data([0x01, 0x02, 0x03, 0x04])
    let frame = try BlazeFrameEncoder.encodeFrame(payload)
    
    #expect(frame.count == 8) // 4 bytes length + 4 bytes payload
    
    // Check length prefix (big-endian)
    let length = frame.withUnsafeBytes { bytes in
        UInt32(bigEndian: bytes.load(as: UInt32.self))
    }
    #expect(length == 4)
    
    // Check payload
    #expect(frame[4] == 0x01)
    #expect(frame[5] == 0x02)
    #expect(frame[6] == 0x03)
    #expect(frame[7] == 0x04)
}

@Test func testEncodeOversizedFrame() throws {
    let hugePayload = Data(repeating: 0, count: 6 * 1024 * 1024) // 6 MB
    
    #expect(throws: BlazeBinaryError.oversizedFrame) {
        _ = try BlazeFrameEncoder.encodeFrame(hugePayload)
    }
}

@Test func testFrameParserSingleFrame() throws {
    let payload = Data([0x01, 0x02, 0x03])
    let frame = try BlazeFrameEncoder.encodeFrame(payload)
    
    let parser = BlazeFrameParser()
    try parser.append(frame)
    
    let decoded = try parser.nextFrame()
    #expect(decoded != nil)
    #expect(decoded == payload)
}

@Test func testFrameParserConcatenatedFrames() throws {
    let payload1 = Data([0x01, 0x02])
    let payload2 = Data([0x03, 0x04, 0x05])
    
    let frame1 = try BlazeFrameEncoder.encodeFrame(payload1)
    let frame2 = try BlazeFrameEncoder.encodeFrame(payload2)
    
    let parser = BlazeFrameParser()
    try parser.append(frame1)
    try parser.append(frame2)
    
    let decoded1 = try parser.nextFrame()
    #expect(decoded1 != nil)
    #expect(decoded1 == payload1)
    
    let decoded2 = try parser.nextFrame()
    #expect(decoded2 != nil)
    #expect(decoded2 == payload2)
    
    // Should be nil now
    #expect(try parser.nextFrame() == nil)
}

@Test func testFrameParserPartialFrame() throws {
    let payload = Data([0x01, 0x02, 0x03])
    let frame = try BlazeFrameEncoder.encodeFrame(payload)
    
    let parser = BlazeFrameParser()
    // Append only first 5 bytes (4 byte header + 1 byte payload)
    try parser.append(frame.prefix(5))
    
    // Should return nil (need more data)
    #expect(try parser.nextFrame() == nil)
    
    // Append remaining data
    try parser.append(frame.suffix(from: 5))
    
    let decoded = try parser.nextFrame()
    #expect(decoded != nil)
    #expect(decoded == payload)
}

@Test func testFrameParserInvalidLength() throws {
    var invalidFrame = Data()
    // Set length to exceed max frame size (big-endian)
    let invalidLength = UInt32(6 * 1024 * 1024).bigEndian
    invalidFrame.append(contentsOf: withUnsafeBytes(of: invalidLength) { Data($0) })
    
    let parser = BlazeFrameParser()
    try parser.append(invalidFrame)
    
    #expect(throws: BlazeBinaryError.invalidFrameLength) {
        _ = try parser.nextFrame()
    }
}

@Test func testFrameParserZeroLength() throws {
    var invalidFrame = Data()
    let zeroLength = UInt32(0).bigEndian
    invalidFrame.append(contentsOf: withUnsafeBytes(of: zeroLength) { Data($0) })
    
    let parser = BlazeFrameParser()
    try parser.append(invalidFrame)
    
    #expect(throws: BlazeBinaryError.invalidFrameLength) {
        _ = try parser.nextFrame()
    }
}

@Test func testFrameParserOversizedBuffer() throws {
    let parser = BlazeFrameParser()
    let hugeData = Data(repeating: 0, count: 11 * 1024 * 1024) // 11 MB
    
    #expect(throws: BlazeBinaryError.oversizedFrame) {
        try parser.append(hugeData)
    }
}

@Test func testFrameParserTruncatedPayload() throws {
    var frame = Data()
    // Set length to 10 but only provide 5 bytes
    let length = UInt32(10).bigEndian
    frame.append(contentsOf: withUnsafeBytes(of: length) { Data($0) })
    frame.append(contentsOf: [0x01, 0x02, 0x03, 0x04, 0x05])
    
    let parser = BlazeFrameParser()
    try parser.append(frame)
    
    // Should return nil (need more data)
    #expect(try parser.nextFrame() == nil)
}

@Test func testFrameBoundaryMultipleFrames() throws {
    // Test multiple frames packed together
    let payload1 = Data([0x01])
    let payload2 = Data([0x02, 0x03])
    let payload3 = Data([0x04, 0x05, 0x06])
    
    let frame1 = try BlazeFrameEncoder.encodeFrame(payload1)
    let frame2 = try BlazeFrameEncoder.encodeFrame(payload2)
    let frame3 = try BlazeFrameEncoder.encodeFrame(payload3)
    
    let allFrames = frame1 + frame2 + frame3
    let parser = BlazeFrameParser()
    try parser.append(allFrames)
    
    let decoded1 = try parser.nextFrame()
    #expect(decoded1 == payload1)
    
    let decoded2 = try parser.nextFrame()
    #expect(decoded2 == payload2)
    
    let decoded3 = try parser.nextFrame()
    #expect(decoded3 == payload3)
    
    #expect(try parser.nextFrame() == nil)
}

@Test func testFrameBoundaryPartialFrameAtEnd() throws {
    // Test partial frame at end of buffer
    let payload1 = Data([0x01, 0x02])
    let frame1 = try BlazeFrameEncoder.encodeFrame(payload1)
    
    // Create partial second frame (only length prefix)
    var partialFrame = Data()
    let length = UInt32(100).bigEndian
    partialFrame.append(contentsOf: withUnsafeBytes(of: length) { Data($0) })
    
    let allData = frame1 + partialFrame
    let parser = BlazeFrameParser()
    try parser.append(allData)
    
    // First frame should be complete
    let decoded1 = try parser.nextFrame()
    #expect(decoded1 == payload1)
    
    // Second frame should be nil (partial)
    #expect(try parser.nextFrame() == nil)
}

