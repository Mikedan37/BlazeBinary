//
//  DeterminismTests.swift
//  BlazeBinary
//
//  Created by Michael Danylchuk.
//
//  MIT License
//  Copyright (c) 2025 Michael D.
//

import XCTest
import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif
@testable import BlazeBinary

// MARK: - Determinism Tests

/// Tests that encoding the same input multiple times produces identical bytes.
func testDeterministicEncoding_sameInput_sameOutput() throws {
    struct TestRecord: BlazeBinaryCodable, Equatable {
        var id: String
        var count: Int
        var active: Bool
        var data: Data
        
        func blazeEncode(to encoder: BlazeBinaryEncoder) throws {
            try encoder.encode(id)
            try encoder.encode(count)
            try encoder.encode(active)
            try encoder.encode(data)
        }
        
        init(from decoder: BlazeBinaryDecoder) throws {
            self.id = try decoder.decodeString()
            self.count = try decoder.decodeInt()
            self.active = try decoder.decodeBool()
            self.data = try decoder.decodeData()
        }
        
        init(id: String, count: Int, active: Bool, data: Data) {
            self.id = id
            self.count = count
            self.active = active
            self.data = data
        }
    }
    
    let record = TestRecord(
        id: "test-123",
        count: 42,
        active: true,
        data: Data([0x01, 0x02, 0x03])
    )
    
    var previousData: Data?
    for i in 0..<100 {
        let encoder = BlazeBinaryEncoder()
        try encoder.encode(record)
        let data = encoder.encodedData()
        
        if let prev = previousData {
            XCTAssert(data == prev, "Encoding is not deterministic at iteration \(i)")
        }
        previousData = data
    }
}

/// Tests that field order in dictionaries does not affect output (keys are sorted).
func testDeterministicEncoding_fieldOrderDoesNotAffectOutput() throws {
    // Create dictionaries with different key insertion orders
    var dict1: [String: String] = [:]
    dict1["zebra"] = "animal"
    dict1["apple"] = "fruit"
    dict1["banana"] = "fruit"
    
    var dict2: [String: String] = [:]
    dict2["apple"] = "fruit"
    dict2["zebra"] = "animal"
    dict2["banana"] = "fruit"
    
    // Both should produce identical bytes (keys are sorted)
    let encoder1 = BlazeBinaryEncoder()
    try encoder1.encode(dict1)
    let data1 = encoder1.encodedData()
    
    let encoder2 = BlazeBinaryEncoder()
    try encoder2.encode(dict2)
    let data2 = encoder2.encodedData()
    
    XCTAssert(data1 == data2, "Dictionary encoding should be deterministic regardless of insertion order")
}

/// Tests determinism with nested structures.
func testDeterministicEncoding_nestedStructures() throws {
    struct Inner: BlazeBinaryCodable, Equatable {
        var value: Int
        
        init(value: Int) {
            self.value = value
        }
        
        func blazeEncode(to encoder: BlazeBinaryEncoder) throws {
            encoder.encode(value)
        }
        
        init(from decoder: BlazeBinaryDecoder) throws {
            self.value = try decoder.decodeInt()
        }
    }
    
    struct Outer: BlazeBinaryCodable, Equatable {
        var inner: Inner
        var outerValue: Int
        
        init(inner: Inner, outerValue: Int) {
            self.inner = inner
            self.outerValue = outerValue
        }
        
        func blazeEncode(to encoder: BlazeBinaryEncoder) throws {
            try encoder.encode(inner)
            encoder.encode(outerValue)
        }
        
        init(from decoder: BlazeBinaryDecoder) throws {
            self.inner = try Inner(from: decoder)
            self.outerValue = try decoder.decodeInt()
        }
    }
    
    let nested = Outer(inner: Inner(value: 1), outerValue: 2)
    
    var previousData: Data?
    for i in 0..<50 {
        let encoder = BlazeBinaryEncoder()
        try encoder.encode(nested)
        let data = encoder.encodedData()
        
        if let prev = previousData {
            XCTAssert(data == prev, "Nested structure encoding is not deterministic at iteration \(i)")
        }
        previousData = data
    }
}

/// Tests determinism with arrays of various types.
func testDeterministicEncoding_arrays() throws {
    let intArray = [1, 2, 3, 4, 5]
    let stringArray = ["a", "b", "c"]
    let dataArray = [Data([0x01]), Data([0x02]), Data([0x03])]
    
    var previousIntData: Data?
    var previousStringData: Data?
    var previousDataArray: Data?
    
    for i in 0..<50 {
        // Test Int array
        let encoder1 = BlazeBinaryEncoder()
        encoder1.encode(intArray.count)
        for item in intArray {
            encoder1.encode(item)
        }
        let data1 = encoder1.encodedData()
        if let prev = previousIntData {
            XCTAssert(data1 == prev, "Int array encoding is not deterministic at iteration \(i)")
        }
        previousIntData = data1
        
        // Test String array
        let encoder2 = BlazeBinaryEncoder()
        encoder2.encode(stringArray.count)
        for item in stringArray {
            encoder2.encode(item)
        }
        let data2 = encoder2.encodedData()
        if let prev = previousStringData {
            XCTAssert(data2 == prev, "String array encoding is not deterministic at iteration \(i)")
        }
        previousStringData = data2
        
        // Test Data array - encode manually
        let encoder3 = BlazeBinaryEncoder()
        encoder3.encode(dataArray.count)
        // Encode each Data item
        for item in dataArray {
            encoder3.encode(item)
        }
        let data3 = encoder3.encodedData()
        if let prev = previousDataArray {
            XCTAssert(data3 == prev, "Data array encoding is not deterministic at iteration \(i)")
        }
        previousDataArray = data3
    }
}

#if canImport(CoreGraphics)
/// Tests determinism with CoreGraphics types.
func testDeterministicEncoding_coreGraphicsTypes() throws {
    let point = CGPoint(x: 100.5, y: 200.75)
    let size = CGSize(width: 300.0, height: 400.0)
    let rect = CGRect(x: 10, y: 20, width: 100, height: 200)
    
    var previousPointData: Data?
    var previousSizeData: Data?
    var previousRectData: Data?
    
    for i in 0..<50 {
        // Test CGPoint
        let encoder1 = BlazeBinaryEncoder()
        try encoder1.encode(point)
        let data1 = encoder1.encodedData()
        if let prev = previousPointData {
            XCTAssert(data1 == prev, "CGPoint encoding is not deterministic at iteration \(i)")
        }
        previousPointData = data1
        
        // Test CGSize
        let encoder2 = BlazeBinaryEncoder()
        try encoder2.encode(size)
        let data2 = encoder2.encodedData()
        if let prev = previousSizeData {
            XCTAssert(data2 == prev, "CGSize encoding is not deterministic at iteration \(i)")
        }
        previousSizeData = data2
        
        // Test CGRect
        let encoder3 = BlazeBinaryEncoder()
        try encoder3.encode(rect)
        let data3 = encoder3.encodedData()
        if let prev = previousRectData {
            XCTAssert(data3 == prev, "CGRect encoding is not deterministic at iteration \(i)")
        }
        previousRectData = data3
    }
}
#endif

