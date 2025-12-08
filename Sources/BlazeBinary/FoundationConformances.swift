//
// FoundationConformances.swift
// BlazeBinary
//
// Copyright (c) 2025 Michael Danylchuk
// MIT License
//

import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

// MARK: - CGPoint Conformance

#if canImport(CoreGraphics)
extension CGPoint: BlazeBinaryCodable {
    public func blazeEncode(to encoder: BlazeBinaryEncoder) throws {
        // Encode as Double for platform-independent determinism
        encoder.encode(Double(x))
        encoder.encode(Double(y))
    }
    
    public init(from decoder: BlazeBinaryDecoder) throws {
        let xValue = try decoder.decodeDouble()
        let yValue = try decoder.decodeDouble()
        self.init(x: xValue, y: yValue)
    }
}
#endif

// MARK: - CGSize Conformance

#if canImport(CoreGraphics)
extension CGSize: BlazeBinaryCodable {
    public func blazeEncode(to encoder: BlazeBinaryEncoder) throws {
        // Encode as Double for platform-independent determinism
        encoder.encode(Double(width))
        encoder.encode(Double(height))
    }
    
    public init(from decoder: BlazeBinaryDecoder) throws {
        let widthValue = try decoder.decodeDouble()
        let heightValue = try decoder.decodeDouble()
        self.init(width: widthValue, height: heightValue)
    }
}
#endif

// MARK: - CGRect Conformance

#if canImport(CoreGraphics)
extension CGRect: BlazeBinaryCodable {
    public func blazeEncode(to encoder: BlazeBinaryEncoder) throws {
        // Encode origin and size
        try encoder.encode(origin)
        try encoder.encode(size)
    }
    
    public init(from decoder: BlazeBinaryDecoder) throws {
        let originValue = try CGPoint(from: decoder)
        let sizeValue = try CGSize(from: decoder)
        self.init(origin: originValue, size: sizeValue)
    }
}
#endif

// MARK: - Array Conformance

extension Array: BlazeBinaryEncodable where Element: BlazeBinaryEncodable {
    public func blazeEncode(to encoder: BlazeBinaryEncoder) throws {
        try encoder.encode(self)
    }
}

extension Array: BlazeBinaryDecodable where Element: BlazeBinaryDecodable {
    public init(from decoder: BlazeBinaryDecoder) throws {
        self = try decoder.decodeArray(Element.self)
    }
}

// MARK: - Dictionary Conformance

extension Dictionary: BlazeBinaryEncodable where Key == String, Value == String {
    public func blazeEncode(to encoder: BlazeBinaryEncoder) throws {
        // Encode as array of key-value pairs for deterministic ordering
        // Sort keys to ensure deterministic encoding
        let sortedKeys = keys.sorted()
        // Encode count as Int (uses varint encoding)
        encoder.encode(sortedKeys.count)
        for key in sortedKeys {
            encoder.encode(key)
            encoder.encode(self[key]!)
        }
    }
}

extension Dictionary: BlazeBinaryDecodable where Key == String, Value == String {
    public init(from decoder: BlazeBinaryDecoder) throws {
        // Decode count as Int (uses varint decoding)
        let countInt = try decoder.decodeInt()
        guard countInt >= 0 else {
            throw BlazeBinaryError.decodeFailed("Invalid dictionary count: \(countInt)")
        }
        let count = UInt64(countInt)
        
        guard count <= 10 * 1024 * 1024 else {
            throw BlazeBinaryError.decodeFailed("Dictionary count \(count) exceeds maximum allowed")
        }
        
        var result: [String: String] = [:]
        result.reserveCapacity(Int(count))
        
        for _ in 0..<count {
            let key = try decoder.decodeString()
            let value = try decoder.decodeString()
            result[key] = value
        }
        
        self = result
    }
}

