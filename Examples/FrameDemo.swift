#!/usr/bin/env swift
//
// FrameDemo.swift
// BlazeBinary Examples
//
// Copyright (c) 2025 Michael Danylchuk
// MIT License
//
// This example demonstrates frame encoding and parsing with BlazeBinary.

import Foundation
import BlazeBinary

struct Message: BlazeBinaryCodable, Equatable {
    var text: String
    var priority: Int
    
    func blazeEncode(to encoder: BlazeBinaryEncoder) throws {
        encoder.encode(text)
        encoder.encode(priority)
    }
    
    init(from decoder: BlazeBinaryDecoder) throws {
        self.text = try decoder.decodeString()
        self.priority = try decoder.decodeInt()
    }
}

print("=== BlazeBinary Frame Demo ===\n")

// Create messages
let message1 = Message(text: "Hello", priority: 1)
let message2 = Message(text: "World", priority: 2)
let message3 = Message(text: "BlazeBinary", priority: 3)

print("Messages to encode:")
print("  1. \(message1.text) (priority: \(message1.priority))")
print("  2. \(message2.text) (priority: \(message2.priority))")
print("  3. \(message3.text) (priority: \(message3.priority))")
print()

// Encode messages
let encoder1 = BlazeBinaryEncoder()
try encoder1.encode(message1)
let payload1 = encoder1.encodedData()

let encoder2 = BlazeBinaryEncoder()
try encoder2.encode(message2)
let payload2 = encoder2.encodedData()

let encoder3 = BlazeBinaryEncoder()
try encoder3.encode(message3)
let payload3 = encoder3.encodedData()

// Create frames
let frame1 = try BlazeFrameEncoder.encodeFrame(payload1)
let frame2 = try BlazeFrameEncoder.encodeFrame(payload2)
let frame3 = try BlazeFrameEncoder.encodeFrame(payload3)

print("Frame sizes:")
print("  Frame 1: \(frame1.count) bytes (payload: \(payload1.count) bytes)")
print("  Frame 2: \(frame2.count) bytes (payload: \(payload2.count) bytes)")
print("  Frame 3: \(frame3.count) bytes (payload: \(payload3.count) bytes)")
print()

// Simulate receiving frames (concatenated)
let allFrames = frame1 + frame2 + frame3
print("Simulating network receive: \(allFrames.count) bytes total")
print()

// Parse frames incrementally
let parser = BlazeFrameParser()
try parser.append(allFrames)

var decodedMessages: [Message] = []
var frameCount = 0

while let payload = try parser.nextFrame() {
    frameCount += 1
    let decoder = BlazeBinaryDecoder(data: payload)
    let decoded = try decoder.decode(Message.self)
    decodedMessages.append(decoded)
    
    print("Frame \(frameCount) decoded:")
    print("  Text: \(decoded.text)")
    print("  Priority: \(decoded.priority)")
    print()
}

print("✅ Decoded \(frameCount) frames successfully")
print()

// Verify round-trip
if decodedMessages.count == 3,
   decodedMessages[0] == message1,
   decodedMessages[1] == message2,
   decodedMessages[2] == message3 {
    print("✅ All messages match original!")
} else {
    print("❌ Message mismatch!")
}

// Test partial frame handling
print("\n--- Testing Partial Frame Handling ---\n")

let largeMessage = Message(text: String(repeating: "A", count: 1000), priority: 99)
let encoder4 = BlazeBinaryEncoder()
try encoder4.encode(largeMessage)
let largePayload = encoder4.encodedData()
let largeFrame = try BlazeFrameEncoder.encodeFrame(largePayload)

// Simulate receiving frame in two chunks
let firstChunk = largeFrame.prefix(largeFrame.count / 2)
let secondChunk = largeFrame.suffix(from: largeFrame.count / 2)

let parser2 = BlazeFrameParser()
try parser2.append(firstChunk)

if try parser2.nextFrame() == nil {
    print("✅ Partial frame correctly returns nil (needs more data)")
}

try parser2.append(secondChunk)

if let completePayload = try parser2.nextFrame() {
    let decoder = BlazeBinaryDecoder(data: completePayload)
    let decoded = try decoder.decode(Message.self)
    
    if decoded == largeMessage {
        print("✅ Partial frame handling successful!")
    } else {
        print("❌ Partial frame decoding failed!")
    }
}

print("\n=== Demo Complete ===")

