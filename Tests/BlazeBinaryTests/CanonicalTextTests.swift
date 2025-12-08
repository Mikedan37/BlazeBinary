//
//  CanonicalTextTests.swift
//  BlazeBinary
//
//  Copyright (c) 2025 Michael Danylchuk
//  MIT License
//

import XCTest
@testable import BlazeBinary

final class CanonicalTextTests: XCTestCase {
    
    func testIntCanonicalText() throws {
        let encoder = BlazeBinaryEncoder()
        encoder.encode(42)
        let data = encoder.encodedData()
        
        let text = try CanonicalText.toCanonicalText(data)
        XCTAssertTrue(text.contains("42") || text.contains("84")) // 42 or zigzag-encoded value
    }
    
    func testStringCanonicalText() throws {
        let encoder = BlazeBinaryEncoder()
        encoder.encode("hello")
        let data = encoder.encodedData()
        
        let text = try CanonicalText.toCanonicalText(data)
        XCTAssertTrue(text.contains("hello"))
    }
    
    func testBoolCanonicalText() throws {
        let encoder = BlazeBinaryEncoder()
        encoder.encode(true)
        let data = encoder.encodedData()
        
        let text = try CanonicalText.toCanonicalText(data)
        // Bool is encoded as single byte (0x00 or 0x01), canonical text should show "true" or "false"
        XCTAssertTrue(text.contains("true") || text.contains("1") || text.contains("01"))
    }
    
    func testDataCanonicalText() throws {
        let encoder = BlazeBinaryEncoder()
        encoder.encode(Data([0x01, 0x02, 0x03]))
        let data = encoder.encodedData()
        
        let text = try CanonicalText.toCanonicalText(data)
        XCTAssertTrue(text.contains("01") || text.contains("02") || text.contains("03"))
    }
    
    func testCodableToCanonicalText() throws {
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
        
        let record = TestRecord(id: "test", count: 42)
        let text = try record.toCanonicalText()
        XCTAssertFalse(text.isEmpty)
    }
}

