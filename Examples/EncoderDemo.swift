#!/usr/bin/env swift
//
// EncoderDemo.swift
// BlazeBinary Examples
//
// Copyright (c) 2025 Michael Danylchuk
// MIT License
//
// This example demonstrates basic encoding with BlazeBinary.

import Foundation
import BlazeBinary

// Define a simple message type
struct Message: BlazeBinaryCodable, Equatable {
    var id: String
    var count: Int
    var active: Bool
    
    func blazeEncode(to encoder: BlazeBinaryEncoder) throws {
        encoder.encode(id)
        encoder.encode(count)
        encoder.encode(active)
    }
    
    init(from decoder: BlazeBinaryDecoder) throws {
        self.id = try decoder.decodeString()
        self.count = try decoder.decodeInt()
        self.active = try decoder.decodeBool()
    }
}

print("=== BlazeBinary Encoder Demo ===\n")

// Create a message
let message = Message(id: "demo-123", count: 42, active: true)
print("Original message:")
print("  ID: \(message.id)")
print("  Count: \(message.count)")
print("  Active: \(message.active)")
print()

// Encode the message
let encoder = BlazeBinaryEncoder()
try encoder.encode(message)
let encodedData = encoder.encodedData()

print("Encoded data:")
print("  Size: \(encodedData.count) bytes")
print("  Hex: \(encodedData.map { String(format: "%02X", $0) }.joined(separator: " "))")
print()

// Verify deterministic encoding
let encoder2 = BlazeBinaryEncoder()
try encoder2.encode(message)
let encodedData2 = encoder2.encodedData()

if encodedData == encodedData2 {
    print("✅ Deterministic encoding verified (same input → same bytes)")
} else {
    print("❌ Encoding is not deterministic!")
}
print()

// Decode to verify round-trip
let decoder = BlazeBinaryDecoder(data: encodedData)
let decoded = try decoder.decode(Message.self)

print("Decoded message:")
print("  ID: \(decoded.id)")
print("  Count: \(decoded.count)")
print("  Active: \(decoded.active)")
print()

if decoded == message {
    print("✅ Round-trip encoding/decoding successful!")
} else {
    print("❌ Round-trip failed!")
}

print("\n=== Demo Complete ===")

