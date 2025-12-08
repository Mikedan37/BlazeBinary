//
//  IncrementalDecodingTests.swift
//  BlazeBinary
//
//  Copyright (c) 2025 Michael Danylchuk
//  MIT License
//

import XCTest
@testable import BlazeBinary

final class IncrementalDecodingTests: XCTestCase {
    
    func testIncrementalDataDecoding() throws {
        let decoder = BlazeIncrementalDecoder()
        
        // Encode a large data field
        let encoder = BlazeBinaryEncoder()
        let largeData = Data(repeating: 0xAA, count: 10000)
        encoder.encode(largeData)
        let encoded = encoder.encodedData()
        
        // Append in chunks
        let chunk1 = encoded.prefix(100)
        let chunk2 = encoded.suffix(from: 100)
        
        decoder.append(chunk1)
        var decoded = try decoder.decodeDataIncremental()
        XCTAssertNil(decoded) // Not enough data yet
        
        decoder.append(chunk2)
        decoded = try decoder.decodeDataIncremental()
        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded, largeData)
    }
    
    func testIncrementalStringDecoding() throws {
        let decoder = BlazeIncrementalDecoder()
        
        // Encode a string
        let encoder = BlazeBinaryEncoder()
        encoder.encode("Hello, World!")
        let encoded = encoder.encodedData()
        
        // Append in chunks
        decoder.append(encoded.prefix(5))
        var decoded = try decoder.decodeStringIncremental()
        XCTAssertNil(decoded) // Not enough data yet
        
        decoder.append(encoded.suffix(from: 5))
        decoded = try decoder.decodeStringIncremental()
        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded, "Hello, World!")
    }
    
    func testIncrementalDecoderBufferSize() {
        let decoder = BlazeIncrementalDecoder()
        XCTAssertEqual(decoder.bufferSize, 0)
        
        decoder.append(Data([0x01, 0x02, 0x03]))
        XCTAssertEqual(decoder.bufferSize, 3)
    }
    
    func testIncrementalDecoderClear() {
        let decoder = BlazeIncrementalDecoder()
        decoder.append(Data([0x01, 0x02, 0x03]))
        XCTAssertEqual(decoder.bufferSize, 3)
        
        decoder.clear()
        XCTAssertEqual(decoder.bufferSize, 0)
        XCTAssertEqual(decoder.currentOffset, 0)
    }
}

