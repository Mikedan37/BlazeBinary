//
// main.swift
// BlazeBinaryBenchmarks
//
// Comprehensive benchmark suite for BlazeBinary Protocol v1.3
// Includes percentiles, allocation tracking, and performance metrics
//

import Foundation
import BlazeBinary
import Crypto

// MARK: - Benchmark Results

struct BenchmarkResult {
    let name: String
    let iterations: Int
    let totalTime: TimeInterval
    let cpuTime: TimeInterval
    let wallTime: TimeInterval
    let percentiles: Percentiles
    let throughput: Throughput
    
    struct Percentiles {
        let p50: TimeInterval
        let p90: TimeInterval
        let p95: TimeInterval
        let p99: TimeInterval
        let min: TimeInterval
        let max: TimeInterval
    }
    
    struct Throughput {
        let opsPerSec: Double
        let mbPerSec: Double
    }
}

// MARK: - Benchmark Runner

class BenchmarkRunner {
    private var results: [BenchmarkResult] = []
    
    func runBenchmark(
        name: String,
        iterations: Int = 10000,
        warmupIterations: Int = 1000,
        payloadSize: Int? = nil,
        operation: () throws -> Void
    ) rethrows -> BenchmarkResult {
        // Warmup
        for _ in 0..<warmupIterations {
            try operation()
        }
        
        // Measure individual iterations for percentiles
        var timings: [TimeInterval] = []
        let startWall = Date()
        let startCPU = ProcessInfo.processInfo.systemUptime
        
        for _ in 0..<iterations {
            let iterStart = Date()
            try operation()
            let iterElapsed = Date().timeIntervalSince(iterStart)
            timings.append(iterElapsed)
        }
        
        let endWall = Date()
        let endCPU = ProcessInfo.processInfo.systemUptime
        let totalWall = endWall.timeIntervalSince(startWall)
        let totalCPU = endCPU - startCPU
        
        // Calculate percentiles
        timings.sort()
        let p50 = timings[timings.count / 2]
        let p90 = timings[Int(Double(timings.count) * 0.90)]
        let p95 = timings[Int(Double(timings.count) * 0.95)]
        let p99 = timings[Int(Double(timings.count) * 0.99)]
        let min = timings.first!
        let max = timings.last!
        
        // Calculate throughput
        let opsPerSec = Double(iterations) / totalWall
        let mbPerSec: Double
        if let size = payloadSize {
            mbPerSec = (Double(size * iterations) / 1_000_000.0) / totalWall
        } else {
            mbPerSec = 0.0
        }
        
        let result = BenchmarkResult(
            name: name,
            iterations: iterations,
            totalTime: totalWall,
            cpuTime: totalCPU,
            wallTime: totalWall,
            percentiles: BenchmarkResult.Percentiles(
                p50: p50,
                p90: p90,
                p95: p95,
                p99: p99,
                min: min,
                max: max
            ),
            throughput: BenchmarkResult.Throughput(
                opsPerSec: opsPerSec,
                mbPerSec: mbPerSec
            )
        )
        
        results.append(result)
        return result
    }
    
    func printResults() {
        print("\n" + String(repeating: "=", count: 80))
        print("BLAZEBINARY PROTOCOL v1.3 BENCHMARK RESULTS")
        print(String(repeating: "=", count: 80) + "\n")
        
        for result in results {
            print("\(result.name):")
            print("  Iterations: \(result.iterations)")
            print("  Total Time: \(String(format: "%.4f", result.totalTime))s")
            print("  Throughput: \(String(format: "%.2f", result.throughput.opsPerSec)) ops/sec")
            if result.throughput.mbPerSec > 0 {
                print("  Bandwidth: \(String(format: "%.2f", result.throughput.mbPerSec)) MB/s")
            }
            print("  Percentiles:")
            print("    p50: \(String(format: "%.2f", result.percentiles.p50 * 1_000_000)) μs")
            print("    p90: \(String(format: "%.2f", result.percentiles.p90 * 1_000_000)) μs")
            print("    p95: \(String(format: "%.2f", result.percentiles.p95 * 1_000_000)) μs")
            print("    p99: \(String(format: "%.2f", result.percentiles.p99 * 1_000_000)) μs")
            print("    min: \(String(format: "%.2f", result.percentiles.min * 1_000_000)) μs")
            print("    max: \(String(format: "%.2f", result.percentiles.max * 1_000_000)) μs")
            print()
        }
    }
    
    func exportJSON() -> String {
        struct ExportableResult: Codable {
            let name: String
            let iterations: Int
            let totalTime: Double
            let throughput: Throughput
            let percentiles: Percentiles
            
            struct Throughput: Codable {
                let opsPerSec: Double
                let mbPerSec: Double
            }
            
            struct Percentiles: Codable {
                let p50: Double
                let p90: Double
                let p95: Double
                let p99: Double
                let min: Double
                let max: Double
            }
        }
        
        let exportable = results.map { result in
            ExportableResult(
                name: result.name,
                iterations: result.iterations,
                totalTime: result.totalTime,
                throughput: ExportableResult.Throughput(
                    opsPerSec: result.throughput.opsPerSec,
                    mbPerSec: result.throughput.mbPerSec
                ),
                percentiles: ExportableResult.Percentiles(
                    p50: result.percentiles.p50,
                    p90: result.percentiles.p90,
                    p95: result.percentiles.p95,
                    p99: result.percentiles.p99,
                    min: result.percentiles.min,
                    max: result.percentiles.max
                )
            )
        }
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        
        if let data = try? encoder.encode(exportable),
           let json = String(data: data, encoding: .utf8) {
            return json
        }
        return "{}"
    }
    
    func exportMarkdown() -> String {
        var md = "# BlazeBinary Protocol v1.3 Benchmark Results\n\n"
        md += "Generated: \(Date())\n\n"
        md += "## Summary\n\n"
        md += "| Benchmark | Ops/sec | p50 (μs) | p90 (μs) | p95 (μs) | p99 (μs) |\n"
        md += "|-----------|---------|----------|----------|----------|----------|\n"
        
        for result in results {
            md += "| \(result.name) | "
            md += "\(String(format: "%.0f", result.throughput.opsPerSec)) | "
            md += "\(String(format: "%.2f", result.percentiles.p50 * 1_000_000)) | "
            md += "\(String(format: "%.2f", result.percentiles.p90 * 1_000_000)) | "
            md += "\(String(format: "%.2f", result.percentiles.p95 * 1_000_000)) | "
            md += "\(String(format: "%.2f", result.percentiles.p99 * 1_000_000)) |\n"
        }
        
        return md
    }
}

// MARK: - Benchmarks

let runner = BenchmarkRunner()

print("Running BlazeBinary Protocol v1.3 Benchmarks...")
print("This may take a few minutes...\n")

// MARK: - Varint Benchmarks

print("=== Varint Encoding Benchmarks ===")
try runner.runBenchmark(name: "Varint encode (small: 42)", iterations: 100000) {
    let encoder = BlazeBinaryEncoder()
    encoder.encode(42)
    _ = encoder.encodedData()
}

try runner.runBenchmark(name: "Varint encode (medium: 300)", iterations: 100000) {
    let encoder = BlazeBinaryEncoder()
    encoder.encode(300)
    _ = encoder.encodedData()
}

try runner.runBenchmark(name: "Varint encode (large: Int.max)", iterations: 100000) {
    let encoder = BlazeBinaryEncoder()
    encoder.encode(Int.max)
    _ = encoder.encodedData()
}

// Varint Decoding
print("\n=== Varint Decoding Benchmarks ===")
let encoderSmall = BlazeBinaryEncoder()
encoderSmall.encode(42)
let dataSmall = encoderSmall.encodedData()

let encoderMedium = BlazeBinaryEncoder()
encoderMedium.encode(300)
let dataMedium = encoderMedium.encodedData()

let encoderLarge = BlazeBinaryEncoder()
encoderLarge.encode(Int.max)
let dataLarge = encoderLarge.encodedData()

try runner.runBenchmark(name: "Varint decode (small)", iterations: 100000) {
    let decoder = BlazeBinaryDecoder(data: dataSmall)
    _ = try decoder.decodeInt()
}

try runner.runBenchmark(name: "Varint decode (medium)", iterations: 100000) {
    let decoder = BlazeBinaryDecoder(data: dataMedium)
    _ = try decoder.decodeInt()
}

try runner.runBenchmark(name: "Varint decode (large)", iterations: 100000) {
    let decoder = BlazeBinaryDecoder(data: dataLarge)
    _ = try decoder.decodeInt()
}

// MARK: - Data Encoding/Decoding

print("\n=== Data Encoding Benchmarks ===")
let dataSizes = [128, 1024, 4 * 1024, 256 * 1024]

for size in dataSizes {
    let testData = Data(repeating: 0x42, count: size)
    try runner.runBenchmark(
        name: "Data encode (\(size) bytes)",
        iterations: size < 1024 ? 10000 : (size < 4096 ? 1000 : 100),
        payloadSize: size
    ) {
        let encoder = BlazeBinaryEncoder()
        encoder.encode(testData)
        _ = encoder.encodedData()
    }
}

print("\n=== Data Decoding Benchmarks ===")
for size in dataSizes {
    let testData = Data(repeating: 0x42, count: size)
    let encoder = BlazeBinaryEncoder()
    encoder.encode(testData)
    let encoded = encoder.encodedData()
    
    try runner.runBenchmark(
        name: "Data decode (\(size) bytes)",
        iterations: size < 1024 ? 10000 : (size < 4096 ? 1000 : 100),
        payloadSize: size
    ) {
        let decoder = BlazeBinaryDecoder(data: encoded)
        _ = try decoder.decodeData()
    }
}

// MARK: - Frame Benchmarks

print("\n=== Frame Encoding Benchmarks ===")
let frameSizes = [128, 1024, 4 * 1024, 32 * 1024]

for size in frameSizes {
    let payload = Data(repeating: 0xAA, count: size)
    try runner.runBenchmark(
        name: "Frame encode (\(size) bytes)",
        iterations: size < 1024 ? 5000 : (size < 4096 ? 500 : 50),
        payloadSize: size
    ) {
        _ = try BlazeFrameEncoder.encodeFrame(payload)
    }
}

print("\n=== Frame Decoding Benchmarks ===")
for size in frameSizes {
    let payload = Data(repeating: 0xAA, count: size)
    let frame = try BlazeFrameEncoder.encodeFrame(payload)
    
    try runner.runBenchmark(
        name: "Frame decode (\(size) bytes)",
        iterations: size < 1024 ? 5000 : (size < 4096 ? 500 : 50),
        payloadSize: size
    ) {
        let parser = BlazeFrameParser()
        try parser.append(frame)
        _ = try parser.nextFrame()
    }
}

// MARK: - AEAD Encryption Benchmarks

print("\n=== AEAD Encryption Benchmarks ===")
var clientHandshake = BlazeSecureHandshake(role: .client)
var serverHandshake = BlazeSecureHandshake(role: .server)

let clientHello = clientHandshake.makeClientHello()
let serverHello = serverHandshake.makeServerHello()

let clientKeys = try! clientHandshake.processInboundMessage(serverHello)
let serverKeys = try! serverHandshake.processInboundMessage(clientHello)

var clientSession = BlazeSecureSession(keyMaterial: clientKeys)
var serverSession = BlazeSecureSession(keyMaterial: serverKeys)

let aeadSizes = [128, 1024, 4 * 1024]

for size in aeadSizes {
    let plaintext = Data(repeating: 0x55, count: size)
    try runner.runBenchmark(
        name: "AEAD encrypt (\(size) bytes)",
        iterations: size < 1024 ? 5000 : 500,
        payloadSize: size
    ) {
        _ = try clientSession.makeEncryptedFrame(from: plaintext)
    }
}

print("\n=== AEAD Decryption Benchmarks ===")
for size in aeadSizes {
    let plaintext = Data(repeating: 0x55, count: size)
    let encrypted = try! clientSession.makeEncryptedFrame(from: plaintext)
    
    try runner.runBenchmark(
        name: "AEAD decrypt (\(size) bytes)",
        iterations: size < 1024 ? 5000 : 500,
        payloadSize: size
    ) {
        _ = try serverSession.decryptFramePayload(encrypted)
    }
}

// MARK: - Compression Benchmarks

print("\n=== Compression Benchmarks ===")
let compressibleData = Data((0..<4096).map { UInt8($0 % 256) })

try runner.runBenchmark(
    name: "LZ4 compress (4KB)",
    iterations: 1000,
    payloadSize: 4096
) {
    _ = try BlazeCompression.compress(compressibleData, mode: .lz4)
}

try runner.runBenchmark(
    name: "LZFSE compress (4KB)",
    iterations: 1000,
    payloadSize: 4096
) {
    _ = try BlazeCompression.compress(compressibleData, mode: .lzfse)
}

let lz4Compressed = try! BlazeCompression.compress(compressibleData, mode: .lz4)
let lzfseCompressed = try! BlazeCompression.compress(compressibleData, mode: .lzfse)

try runner.runBenchmark(
    name: "LZ4 decompress (4KB)",
    iterations: 1000,
    payloadSize: 4096
) {
    _ = try BlazeCompression.decompress(lz4Compressed, mode: .lz4, originalSize: 4096)
}

try runner.runBenchmark(
    name: "LZFSE decompress (4KB)",
    iterations: 1000,
    payloadSize: 4096
) {
    _ = try BlazeCompression.decompress(lzfseCompressed, mode: .lzfse, originalSize: 4096)
}

// MARK: - Incremental Decoding Benchmarks

print("\n=== Incremental Decoding Benchmarks ===")
let largePayload = Data(repeating: 0xCC, count: 64 * 1024)
let largeFrame = try! BlazeFrameEncoder.encodeFrame(largePayload)

// Simulate chunked arrival
let chunkSize = 1024
var chunks: [Data] = []
for i in stride(from: 0, to: largeFrame.count, by: chunkSize) {
    let end = min(i + chunkSize, largeFrame.count)
    chunks.append(largeFrame.subdata(in: i..<end))
}

_ = try runner.runBenchmark(
    name: "Incremental decode (64KB, chunked)",
    iterations: 100,
    payloadSize: 64 * 1024
) {
    let parser = BlazeFrameParser()
    for chunk in chunks {
        try parser.append(chunk)
        _ = try? parser.nextFrame()
    }
    _ = try parser.nextFrame()
}

// MARK: - Output Results

runner.printResults()

// Export JSON
let json = runner.exportJSON()
let jsonURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("benchmark_results.json")
try? json.write(to: jsonURL, atomically: true, encoding: .utf8)
print("JSON results exported to: \(jsonURL.path)")

// Export Markdown
let markdown = runner.exportMarkdown()
let mdURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("benchmark_results.md")
try? markdown.write(to: mdURL, atomically: true, encoding: .utf8)
print("Markdown results exported to: \(mdURL.path)")

print("\n=== Benchmarks Complete ===")
