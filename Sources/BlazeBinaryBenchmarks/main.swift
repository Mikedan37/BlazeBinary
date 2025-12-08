import Foundation
import BlazeBinary

func measure(_ name: String, iterations: Int = 10000, _ block: () throws -> Void) rethrows {
    let start = CFAbsoluteTimeGetCurrent()
    for _ in 0..<iterations {
        try block()
    }
    let elapsed = CFAbsoluteTimeGetCurrent() - start
    
    // Ensure each benchmark runs <0.1 seconds
    if elapsed > 0.1 {
        print("⚠️  \(name): WARNING - took \(String(format: "%.4f", elapsed))s (target: <0.1s)")
    }
    
    let opsPerSec = Double(iterations) / elapsed
    print("\(name): \(String(format: "%.2f", opsPerSec)) ops/sec (\(String(format: "%.4f", elapsed))s total)")
}

// Benchmark: Varint Encode
print("=== Varint Encode Benchmarks ===")
measure("Varint encode (small)", iterations: 100000) {
    let encoder = BlazeBinaryEncoder()
    encoder.encode(42)
    _ = encoder.encodedData()
}

measure("Varint encode (medium)", iterations: 100000) {
    let encoder = BlazeBinaryEncoder()
    encoder.encode(300)
    _ = encoder.encodedData()
}

measure("Varint encode (large)", iterations: 100000) {
    let encoder = BlazeBinaryEncoder()
    encoder.encode(Int.max)
    _ = encoder.encodedData()
}

// Benchmark: Varint Decode
print("\n=== Varint Decode Benchmarks ===")
let encoderSmall = BlazeBinaryEncoder()
encoderSmall.encode(42)
let dataSmall = encoderSmall.encodedData()

let encoderMedium = BlazeBinaryEncoder()
encoderMedium.encode(300)
let dataMedium = encoderMedium.encodedData()

let encoderLarge = BlazeBinaryEncoder()
encoderLarge.encode(Int.max)
let dataLarge = encoderLarge.encodedData()

try measure("Varint decode (small)", iterations: 100000) {
    let decoder = BlazeBinaryDecoder(data: dataSmall)
    _ = try decoder.decodeInt()
}

try measure("Varint decode (medium)", iterations: 100000) {
    let decoder = BlazeBinaryDecoder(data: dataMedium)
    _ = try decoder.decodeInt()
}

try measure("Varint decode (large)", iterations: 100000) {
    let decoder = BlazeBinaryDecoder(data: dataLarge)
    _ = try decoder.decodeInt()
}

// Benchmark: Data Encoding
print("\n=== Data Encode Benchmarks ===")
let sizes = [1024, 8 * 1024, 32 * 1024, 256 * 1024]

for size in sizes {
    let testData = Data(repeating: 0x42, count: size)
    measure("Data encode (\(size) bytes)", iterations: 1000) {
        let encoder = BlazeBinaryEncoder()
        encoder.encode(testData)
        _ = encoder.encodedData()
    }
}

// Benchmark: Data Decoding
print("\n=== Data Decode Benchmarks ===")
for size in sizes {
    let testData = Data(repeating: 0x42, count: size)
    let encoder = BlazeBinaryEncoder()
    encoder.encode(testData)
    let encoded = encoder.encodedData()
    
    try measure("Data decode (\(size) bytes)", iterations: 1000) {
        let decoder = BlazeBinaryDecoder(data: encoded)
        _ = try decoder.decodeData()
    }
}

// Benchmark: Frame Encoding
print("\n=== Frame Encode Benchmarks ===")
let frameSizes = [1024, 8 * 1024, 32 * 1024]

for size in frameSizes {
    let payload = Data(repeating: 0xAA, count: size)
    try measure("Frame encode (\(size) bytes)", iterations: 1000) {
        _ = try BlazeFrameEncoder.encodeFrame(payload)
    }
}

// Benchmark: Frame Decoding
print("\n=== Frame Decode Benchmarks ===")
for size in frameSizes {
    let payload = Data(repeating: 0xAA, count: size)
    let frame = try BlazeFrameEncoder.encodeFrame(payload)
    
    try measure("Frame decode (\(size) bytes)", iterations: 1000) {
        let parser = BlazeFrameParser()
        try parser.append(frame)
        _ = try parser.nextFrame()
    }
}

// Benchmark: Partial Frame Parsing
print("\n=== Partial Frame Parse Benchmarks ===")
let payload = Data(repeating: 0xBB, count: 1024)
let frame = try BlazeFrameEncoder.encodeFrame(payload)

// Simulate partial frame arrival
let firstHalf = frame.prefix(frame.count / 2)
let secondHalf = frame.suffix(from: frame.count / 2)

try measure("Partial frame parse", iterations: 10000) {
    let parser = BlazeFrameParser()
    try parser.append(firstHalf)
    _ = try parser.nextFrame() // Should return nil
    try parser.append(secondHalf)
    _ = try parser.nextFrame() // Should return payload
}

print("\n=== Benchmarks Complete ===")

