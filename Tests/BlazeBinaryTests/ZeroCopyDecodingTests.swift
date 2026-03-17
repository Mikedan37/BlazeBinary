//
//  ZeroCopyDecodingTests.swift
//  BlazeBinary
//
//  Copyright (c) 2025 Michael Danylchuk
//  MIT License
//

import XCTest
@testable import BlazeBinary

final class ZeroCopyDecodingTests: XCTestCase {
    
    struct Point: BlazeBinaryCodable {
        let x: Float
        let y: Float
        
        init(x: Float, y: Float) {
            self.x = x
            self.y = y
        }
        
        func blazeEncode(to encoder: BlazeBinaryEncoder) throws {
            encoder.encode(x.bitPattern)
            encoder.encode(y.bitPattern)
        }
        
        init(from decoder: BlazeBinaryDecoder) throws {
            let xBits = try decoder.decodeUInt32()
            let yBits = try decoder.decodeUInt32()
            self.x = Float(bitPattern: xBits)
            self.y = Float(bitPattern: yBits)
        }
    }
    
    func testZeroCopyDecoding() throws {
        let point = Point(x: 1.5, y: 2.5)
        let encoder = BlazeBinaryEncoder()
        try encoder.encode(point)
        let data = encoder.encodedData()
        
        let decoder = BlazeBinaryDecoder(data: data)
        let decoded = try decoder.decodeZeroCopy(Point.self)
        XCTAssertEqual(decoded.x, point.x, accuracy: 0.001)
        XCTAssertEqual(decoded.y, point.y, accuracy: 0.001)
    }
    
    func testZeroCopyRoundTripsCorrectly() throws {
        let point = Point(x: -42.75, y: 0.0)
        let encoder = BlazeBinaryEncoder()
        try encoder.encode(point)
        let data = encoder.encodedData()
        
        let decoder = BlazeBinaryDecoder(data: data)
        let decoded = try decoder.decodeZeroCopy(Point.self)
        XCTAssertEqual(decoded.x, point.x, accuracy: 0.001)
        XCTAssertEqual(decoded.y, point.y, accuracy: 0.001)
    }
    
    func testZeroCopyBoundsCheck() throws {
        let data = Data([0x01, 0x02, 0x03])
        
        let decoder = BlazeBinaryDecoder(data: data)
        
        XCTAssertThrowsError(try decoder.decodeZeroCopy(Point.self)) { error in
            XCTAssertTrue(error is BlazeBinaryError)
        }
    }
}

