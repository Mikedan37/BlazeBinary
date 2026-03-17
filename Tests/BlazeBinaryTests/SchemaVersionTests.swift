//
//  SchemaVersionTests.swift
//  BlazeBinary
//
//  Copyright (c) 2025 Michael Danylchuk
//  MIT License
//

import XCTest
@testable import BlazeBinary

final class SchemaVersionTests: XCTestCase {
    
    func testDefaultSchemaVersionIsOne() {
        let encoder = BlazeBinaryEncoder()
        XCTAssertEqual(encoder.version, 1)
        
        encoder.encode(42)
        let data = encoder.encodedData()
        
        // Default v1 should not include schema version marker
        // 42 encodes as zigzag: 84 = 0x54
        XCTAssertEqual(data[0], 0x54) // Zigzag encoding of 42
        
        let decoder = BlazeBinaryDecoder(data: data)
        XCTAssertEqual(decoder.version, 1)
    }
    
    func testExplicitSchemaVersionOne() {
        let encoder = BlazeBinaryEncoder(schemaVersion: 1)
        XCTAssertEqual(encoder.version, 1)
        
        encoder.encode(42)
        let data = encoder.encodedData()
        
        // v1 should not include schema version marker (backwards compatible)
        // 42 encodes as zigzag: 84 = 0x54
        XCTAssertEqual(data[0], 0x54)
        
        let decoder = BlazeBinaryDecoder(data: data)
        XCTAssertEqual(decoder.version, 1)
    }
    
    func testSchemaVersionTwo() {
        let encoder = BlazeBinaryEncoder(schemaVersion: 2)
        XCTAssertEqual(encoder.version, 2)
        
        encoder.encode(42)
        let data = encoder.encodedData()
        
        // v2 should include schema version marker (0xFE) + varint(2)
        XCTAssertEqual(data[0], 0xFE) // Marker
        XCTAssertEqual(data[1], 0x02) // varint(2)
        XCTAssertEqual(data[2], 0x54) // Encoded value 42 (zigzag: 84 = 0x54)
        
        let decoder = BlazeBinaryDecoder(data: data)
        XCTAssertEqual(decoder.version, 2)
        
        // Should decode the value correctly
        let value = try! decoder.decodeInt()
        XCTAssertEqual(value, 42)
    }
    
    func testSchemaVersionMaxAllowed() {
        // Schema versions are now restricted to 2...127 (single-byte varint)
        // to avoid in-band collision with payload data starting with 0xFE.
        let encoder = BlazeBinaryEncoder(schemaVersion: 127)
        XCTAssertEqual(encoder.version, 127)

        encoder.encode("test")
        let data = encoder.encodedData()

        // v127 should include: 0xFE (marker) + 0x7F (127 as single byte) + encoded string
        XCTAssertEqual(data[0], 0xFE) // Marker
        XCTAssertEqual(data[1], 0x7F) // 127 as single byte (no continuation bit)

        let decoder = BlazeBinaryDecoder(data: data)
        XCTAssertEqual(decoder.version, 127)

        // Should decode the string correctly
        let value = try! decoder.decodeString()
        XCTAssertEqual(value, "test")
    }
    
    func testBackwardsCompatibilityV1Record() {
        // Create a v1 record (no schema version marker)
        let encoder = BlazeBinaryEncoder(schemaVersion: 1)
        encoder.encode("hello")
        encoder.encode(42)
        let v1Data = encoder.encodedData()
        
        // Decoder should detect v1 (no marker)
        let decoder = BlazeBinaryDecoder(data: v1Data)
        XCTAssertEqual(decoder.version, 1)
        
        // Should decode correctly
        let str = try! decoder.decodeString()
        let num = try! decoder.decodeInt()
        XCTAssertEqual(str, "hello")
        XCTAssertEqual(num, 42)
    }
    
    func testV2RecordWithV1Decoder() {
        // Create a v2 record
        let encoder = BlazeBinaryEncoder(schemaVersion: 2)
        encoder.encode("hello")
        encoder.encode(42)
        let v2Data = encoder.encodedData()
        
        // Decoder should detect v2
        let decoder = BlazeBinaryDecoder(data: v2Data)
        XCTAssertEqual(decoder.version, 2)
        
        // Should decode correctly (schema version is skipped automatically)
        let str = try! decoder.decodeString()
        let num = try! decoder.decodeInt()
        XCTAssertEqual(str, "hello")
        XCTAssertEqual(num, 42)
    }
    
    func testRoundTripWithSchemaVersion() {
        struct TestRecord: BlazeBinaryCodable {
            let id: String
            let count: Int
            
            init(id: String, count: Int) {
                self.id = id
                self.count = count
            }
            
            func blazeEncode(to encoder: BlazeBinaryEncoder) throws {
                encoder.encode(id)
                encoder.encode(count)
            }
            
            init(from decoder: BlazeBinaryDecoder) throws {
                self.id = try decoder.decodeString()
                self.count = try decoder.decodeInt()
            }
        }
        
        let record = TestRecord(id: "test123", count: 99)
        
        // Encode with v2
        let encoder = BlazeBinaryEncoder(schemaVersion: 2)
        try! encoder.encode(record)
        let data = encoder.encodedData()
        
        // Decode and verify schema version
        let decoder = BlazeBinaryDecoder(data: data)
        XCTAssertEqual(decoder.version, 2)
        
        // Decode record
        let decoded = try! decoder.decode(TestRecord.self)
        XCTAssertEqual(decoded.id, "test123")
        XCTAssertEqual(decoded.count, 99)
    }
    
    func testInvalidSchemaVersionMarker() {
        // Create data with 0xFE but invalid varint
        let data = Data([0xFE, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x7F]) // Invalid varint
        
        let decoder = BlazeBinaryDecoder(data: data)
        // Should fall back to v1
        XCTAssertEqual(decoder.version, 1)
        XCTAssertEqual(decoder.offset, 0) // Should reset to start
    }
    
    func testSchemaVersionOneDoesNotAddMarker() {
        // Verify that v1 records remain identical to pre-v1.1 format
        let encoder1 = BlazeBinaryEncoder(schemaVersion: 1)
        encoder1.encode(42)
        let data1 = encoder1.encodedData()
        
        // Should be just the encoded value (backwards compatible)
        // 42 encodes as zigzag: 84 = 0x54
        XCTAssertEqual(data1.count, 1)
        XCTAssertEqual(data1[0], 0x54)
    }
}

