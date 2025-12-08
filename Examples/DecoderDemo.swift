#!/usr/bin/env swift
//
// DecoderDemo.swift
// BlazeBinary Examples
//
// Copyright (c) 2025 Michael Danylchuk
// MIT License
//
// This example demonstrates basic decoding with BlazeBinary.

import Foundation
import BlazeBinary

// Define a complex type with multiple fields
struct UserProfile: BlazeBinaryCodable, Equatable {
    var username: String
    var email: String?
    var age: Int
    var tags: [String]
    
    func blazeEncode(to encoder: BlazeBinaryEncoder) throws {
        encoder.encode(username)
        try encoder.encode(email)
        encoder.encode(age)
        try encoder.encode(tags)
    }
    
    init(from decoder: BlazeBinaryDecoder) throws {
        self.username = try decoder.decodeString()
        self.email = try decoder.decodeOptional(String.self)
        self.age = try decoder.decodeInt()
        self.tags = try decoder.decodeArray(String.self)
    }
}

print("=== BlazeBinary Decoder Demo ===\n")

// Create a user profile
let profile = UserProfile(
    username: "alice",
    email: "alice@example.com",
    age: 30,
    tags: ["swift", "developer", "open-source"]
)

print("Original profile:")
print("  Username: \(profile.username)")
print("  Email: \(profile.email ?? "nil")")
print("  Age: \(profile.age)")
print("  Tags: \(profile.tags.joined(separator: ", "))")
print()

// Encode
let encoder = BlazeBinaryEncoder()
try encoder.encode(profile)
let encodedData = encoder.encodedData()

print("Encoded:")
print("  Size: \(encodedData.count) bytes")
print()

// Decode
let decoder = BlazeBinaryDecoder(data: encodedData)
let decoded = try decoder.decode(UserProfile.self)

print("Decoded profile:")
print("  Username: \(decoded.username)")
print("  Email: \(decoded.email ?? "nil")")
print("  Age: \(decoded.age)")
print("  Tags: \(decoded.tags.joined(separator: ", "))")
print()

if decoded == profile {
    print("✅ Round-trip successful!")
} else {
    print("❌ Round-trip failed!")
}

// Test with nil email
print("\n--- Testing Optional Field (nil) ---\n")

let profileNoEmail = UserProfile(
    username: "bob",
    email: nil,
    age: 25,
    tags: []
)

let encoder2 = BlazeBinaryEncoder()
try encoder2.encode(profileNoEmail)
let encodedData2 = encoder2.encodedData()

let decoder2 = BlazeBinaryDecoder(data: encodedData2)
let decoded2 = try decoder2.decode(UserProfile.self)

print("Original: email = \(profileNoEmail.email?.description ?? "nil")")
print("Decoded: email = \(decoded2.email?.description ?? "nil")")

if decoded2.email == nil {
    print("✅ Optional nil encoding/decoding successful!")
} else {
    print("❌ Optional nil handling failed!")
}

print("\n=== Demo Complete ===")

