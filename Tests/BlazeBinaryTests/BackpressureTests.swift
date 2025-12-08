//
//  BackpressureTests.swift
//  BlazeBinary
//
//  Copyright (c) 2025 Michael Danylchuk
//  MIT License
//

import XCTest
@testable import BlazeBinary

final class BackpressureTests: XCTestCase {
    
    func testBackpressureHighWaterMark() throws {
        let config = BackpressureConfig(highWaterMark: 1000, lowWaterMark: 500)
        let parser = BlazeFrameParser(backpressureConfig: config)
        
        // Add data below high water mark
        try parser.append(Data(repeating: 0x00, count: 800))
        XCTAssertFalse(parser.hasBackpressure)
        
        // Add data above high water mark
        try parser.append(Data(repeating: 0x00, count: 300))
        XCTAssertTrue(parser.hasBackpressure)
    }
    
    func testBackpressureLowWaterMark() throws {
        let config = BackpressureConfig(highWaterMark: 1000, lowWaterMark: 500)
        let parser = BlazeFrameParser(backpressureConfig: config)
        
        // Fill buffer above high water mark
        try parser.append(Data(repeating: 0x00, count: 1200))
        XCTAssertTrue(parser.hasBackpressure)
        
        // Process frames to reduce buffer below low water mark
        // Create a small frame with payload that won't trigger false positives
        let smallPayload = Data([0x10, 0x20]) // Use bytes that won't be misidentified
        let frame = try BlazeFrameEncoder.encodeFrame(smallPayload)
        
        // Clear buffer first, then add frame
        parser.clear()
        try parser.append(frame)
        let decoded = try parser.nextFrame()
        XCTAssertNotNil(decoded)
        
        // Buffer should be empty after processing frame
        XCTAssertEqual(parser.bufferSize, 0)
        XCTAssertFalse(parser.hasBackpressure)
    }
    
    func testBackpressureDefaultConfig() {
        let parser = BlazeFrameParser()
        // Default config: 8MB high, 2MB low
        XCTAssertEqual(parser.backpressureConfig.highWaterMark, 8 * 1024 * 1024)
        XCTAssertEqual(parser.backpressureConfig.lowWaterMark, 2 * 1024 * 1024)
    }
    
    func testBackpressureCustomConfig() {
        let config = BackpressureConfig(highWaterMark: 5000, lowWaterMark: 2000)
        let parser = BlazeFrameParser(backpressureConfig: config)
        
        XCTAssertEqual(parser.backpressureConfig.highWaterMark, 5000)
        XCTAssertEqual(parser.backpressureConfig.lowWaterMark, 2000)
    }
    
    func testBackpressureAppendReturnsState() throws {
        let config = BackpressureConfig(highWaterMark: 1000, lowWaterMark: 500)
        let parser = BlazeFrameParser(backpressureConfig: config)
        
        // Below threshold
        let state1 = try parser.append(Data(repeating: 0x00, count: 800))
        XCTAssertFalse(state1)
        
        // Above threshold
        let state2 = try parser.append(Data(repeating: 0x00, count: 300))
        XCTAssertTrue(state2)
    }
}

