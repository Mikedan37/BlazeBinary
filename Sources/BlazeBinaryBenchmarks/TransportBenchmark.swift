//
// TransportBenchmark.swift
// BlazeBinaryBenchmarks
//
// Benchmarks comparing BlazeBinary performance over TCP vs UDP
//

import Foundation
import Network
import BlazeBinary

// MARK: - Transport Benchmark Results

struct TransportBenchmarkResult {
    let protocolName: String
    let frameSize: Int
    let iterations: Int
    let totalTime: TimeInterval
    let throughput: Double  // frames/sec
    let bandwidth: Double   // MB/s
    let latency: LatencyMetrics
    let overhead: OverheadMetrics
    
    struct LatencyMetrics {
        let p50: TimeInterval
        let p90: TimeInterval
        let p95: TimeInterval
        let p99: TimeInterval
        let min: TimeInterval
        let max: TimeInterval
        let mean: TimeInterval
    }
    
    struct OverheadMetrics {
        let headerBytes: Int
        let totalBytes: Int
        let overheadPercent: Double
    }
}

// MARK: - Transport Benchmark Runner

class TransportBenchmarkRunner {
    private let port: UInt16 = 8888
    private var tcpListener: NWListener?
    private var udpListener: NWListener?
    
    func runTCPBenchmark(frameSize: Int, iterations: Int) throws -> TransportBenchmarkResult {
        print("  Setting up TCP benchmark (frame size: \(frameSize) bytes, iterations: \(iterations))...")
        
        // Create test payload
        let payload = Data(repeating: 0x42, count: frameSize)
        let frame = try BlazeFrameEncoder.encodeFrame(payload)
        let totalFrameSize = frame.count
        
        // Setup TCP listener
        let tcpParams = NWParameters(tls: nil, tcp: NWProtocolTCP.Options())
        tcpParams.requiredInterfaceType = .loopback
        let listener = try NWListener(using: tcpParams, on: NWEndpoint.Port(rawValue: port)!)
        
        var receivedFrames = 0
        var latencies: [TimeInterval] = []
        var startTime: Date?
        var endTime: Date?
        
        let semaphore = DispatchSemaphore(value: 0)
        var connection: NWConnection?
        
        listener.newConnectionHandler = { newConnection in
            connection = newConnection
            newConnection.start(queue: .global())
            
            // Start receiving
            func receiveLoop() {
                newConnection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, isComplete, error in
                    if let error = error {
                        print("    TCP receive error: \(error)")
                        semaphore.signal()
                        return
                    }
                    
                    if let data = data {
                        let receiveTime = Date()
                        let parser = BlazeFrameParser()
                        do {
                            try parser.append(data)
                            if let _ = try parser.nextFrame() {
                                receivedFrames += 1
                                
                                if receivedFrames == 1 {
                                    startTime = receiveTime
                                }
                                
                                if receivedFrames == iterations {
                                    endTime = receiveTime
                                    semaphore.signal()
                                    return
                                }
                            }
                        } catch {
                            print("    TCP parse error: \(error)")
                        }
                    }
                    
                    if !isComplete {
                        receiveLoop()
                    }
                }
            }
            receiveLoop()
        }
        
        listener.start(queue: .global())
        
        // Wait a bit for listener to be ready
        Thread.sleep(forTimeInterval: 0.1)
        
        // Create client connection
        let clientParams = NWParameters(tls: nil, tcp: NWProtocolTCP.Options())
        clientParams.requiredInterfaceType = .loopback
        let client = NWConnection(host: NWEndpoint.Host("127.0.0.1"), port: NWEndpoint.Port(rawValue: port)!, using: clientParams)
        
        var clientStartTime: Date?
        var sendLatencies: [TimeInterval] = []
        
        client.stateUpdateHandler = { state in
            if state == .ready {
                clientStartTime = Date()
                
                // Send frames
                for i in 0..<iterations {
                    let sendStart = Date()
                    client.send(content: frame, completion: .contentProcessed { error in
                        if error == nil {
                            let sendLatency = Date().timeIntervalSince(sendStart)
                            sendLatencies.append(sendLatency)
                        }
                    })
                    
                    // Small delay to avoid overwhelming
                    if i % 100 == 0 && i > 0 {
                        Thread.sleep(forTimeInterval: 0.001)
                    }
                }
            }
        }
        
        client.start(queue: .global())
        
        // Wait for completion
        let timeout = semaphore.wait(timeout: .now() + 30)
        if timeout == .timedOut {
            throw NSError(domain: "TransportBenchmark", code: 1, userInfo: [NSLocalizedDescriptionKey: "TCP benchmark timed out"])
        }
        
        client.cancel()
        listener.cancel()
        
        guard let start = startTime, let end = endTime else {
            throw NSError(domain: "TransportBenchmark", code: 2, userInfo: [NSLocalizedDescriptionKey: "TCP benchmark failed to complete"])
        }
        
        let totalTime = end.timeIntervalSince(start)
        let throughput = Double(iterations) / totalTime
        let bandwidth = (Double(totalFrameSize * iterations) / totalTime) / (1024 * 1024) // MB/s
        
        // Calculate latency percentiles
        let sortedLatencies = sendLatencies.sorted()
        let latencyMetrics = calculatePercentiles(sortedLatencies)
        
        // Calculate overhead
        let tcpHeaderSize = 20  // TCP header
        let ipHeaderSize = 20   // IP header
        let ethernetHeaderSize = 14  // Ethernet header
        let totalHeaderSize = tcpHeaderSize + ipHeaderSize + ethernetHeaderSize
        let totalBytes = totalFrameSize + totalHeaderSize
        let overheadPercent = (Double(totalHeaderSize) / Double(totalBytes)) * 100.0
        
        return TransportBenchmarkResult(
            protocolName: "TCP",
            frameSize: frameSize,
            iterations: iterations,
            totalTime: totalTime,
            throughput: throughput,
            bandwidth: bandwidth,
            latency: latencyMetrics,
            overhead: OverheadMetrics(
                headerBytes: totalHeaderSize,
                totalBytes: totalBytes,
                overheadPercent: overheadPercent
            )
        )
    }
    
    func runUDPBenchmark(frameSize: Int, iterations: Int) throws -> TransportBenchmarkResult {
        print("  Setting up UDP benchmark (frame size: \(frameSize) bytes, iterations: \(iterations))...")
        
        // Create test payload
        let payload = Data(repeating: 0x42, count: frameSize)
        let frame = try BlazeFrameEncoder.encodeFrame(payload)
        let totalFrameSize = frame.count
        
        // Setup UDP listener
        let udpParams = NWParameters(dtls: nil, udp: NWProtocolUDP.Options())
        udpParams.requiredInterfaceType = .loopback
        let listener = try NWListener(using: udpParams, on: NWEndpoint.Port(rawValue: port + 1)!)
        
        var receivedFrames = 0
        var startTime: Date?
        var endTime: Date?
        
        let semaphore = DispatchSemaphore(value: 0)
        
        listener.newConnectionHandler = { newConnection in
            newConnection.start(queue: .global())
            
            // Start receiving
            func receiveLoop() {
                newConnection.receiveMessage { data, context, isComplete, error in
                    if let error = error {
                        print("    UDP receive error: \(error)")
                        semaphore.signal()
                        return
                    }
                    
                    if let data = data {
                        let receiveTime = Date()
                        let parser = BlazeFrameParser()
                        do {
                            try parser.append(data)
                            if let _ = try parser.nextFrame() {
                                receivedFrames += 1
                                
                                if receivedFrames == 1 {
                                    startTime = receiveTime
                                }
                                
                                if receivedFrames == iterations {
                                    endTime = receiveTime
                                    semaphore.signal()
                                    return
                                }
                            }
                        } catch {
                            print("    UDP parse error: \(error)")
                        }
                    }
                    
                    if !isComplete {
                        receiveLoop()
                    }
                }
            }
            receiveLoop()
        }
        
        listener.start(queue: .global())
        
        // Wait a bit for listener to be ready
        Thread.sleep(forTimeInterval: 0.1)
        
        // Create client connection
        let clientParams = NWParameters(dtls: nil, udp: NWProtocolUDP.Options())
        clientParams.requiredInterfaceType = .loopback
        let client = NWConnection(host: NWEndpoint.Host("127.0.0.1"), port: NWEndpoint.Port(rawValue: port + 1)!, using: clientParams)
        
        var sendLatencies: [TimeInterval] = []
        
        client.stateUpdateHandler = { state in
            if state == .ready {
                // Send frames
                for i in 0..<iterations {
                    let sendStart = Date()
                    client.send(content: frame, completion: .contentProcessed { error in
                        if error == nil {
                            let sendLatency = Date().timeIntervalSince(sendStart)
                            sendLatencies.append(sendLatency)
                        }
                    })
                    
                    // Small delay to avoid overwhelming
                    if i % 100 == 0 && i > 0 {
                        Thread.sleep(forTimeInterval: 0.001)
                    }
                }
            }
        }
        
        client.start(queue: .global())
        
        // Wait for completion
        let timeout = semaphore.wait(timeout: .now() + 30)
        if timeout == .timedOut {
            throw NSError(domain: "TransportBenchmark", code: 1, userInfo: [NSLocalizedDescriptionKey: "UDP benchmark timed out"])
        }
        
        client.cancel()
        listener.cancel()
        
        guard let start = startTime, let end = endTime else {
            throw NSError(domain: "TransportBenchmark", code: 2, userInfo: [NSLocalizedDescriptionKey: "UDP benchmark failed to complete"])
        }
        
        let totalTime = end.timeIntervalSince(start)
        let throughput = Double(iterations) / totalTime
        let bandwidth = (Double(totalFrameSize * iterations) / totalTime) / (1024 * 1024) // MB/s
        
        // Calculate latency percentiles
        let sortedLatencies = sendLatencies.sorted()
        let latencyMetrics = calculatePercentiles(sortedLatencies)
        
        // Calculate overhead
        let udpHeaderSize = 8   // UDP header
        let ipHeaderSize = 20    // IP header
        let ethernetHeaderSize = 14  // Ethernet header
        let totalHeaderSize = udpHeaderSize + ipHeaderSize + ethernetHeaderSize
        let totalBytes = totalFrameSize + totalHeaderSize
        let overheadPercent = (Double(totalHeaderSize) / Double(totalBytes)) * 100.0
        
        return TransportBenchmarkResult(
            protocolName: "UDP",
            frameSize: frameSize,
            iterations: iterations,
            totalTime: totalTime,
            throughput: throughput,
            bandwidth: bandwidth,
            latency: latencyMetrics,
            overhead: OverheadMetrics(
                headerBytes: totalHeaderSize,
                totalBytes: totalBytes,
                overheadPercent: overheadPercent
            )
        )
    }
    
    private func calculatePercentiles(_ sorted: [TimeInterval]) -> TransportBenchmarkResult.LatencyMetrics {
        guard !sorted.isEmpty else {
            return TransportBenchmarkResult.LatencyMetrics(
                p50: 0, p90: 0, p95: 0, p99: 0, min: 0, max: 0, mean: 0
            )
        }
        
        let count = sorted.count
        let p50 = sorted[count * 50 / 100]
        let p90 = sorted[count * 90 / 100]
        let p95 = sorted[count * 95 / 100]
        let p99 = sorted[count * 99 / 100]
        let min = sorted.first!
        let max = sorted.last!
        let mean = sorted.reduce(0, +) / Double(count)
        
        return TransportBenchmarkResult.LatencyMetrics(
            p50: p50,
            p90: p90,
            p95: p95,
            p99: p99,
            min: min,
            max: max,
            mean: mean
        )
    }
    
    func compareResults(_ tcp: TransportBenchmarkResult, _ udp: TransportBenchmarkResult) -> String {
        var output = "\n"
        output += "=== TCP vs UDP Comparison (Frame Size: \(tcp.frameSize) bytes) ===\n\n"
        
        // Throughput comparison
        let throughputDiff = ((udp.throughput - tcp.throughput) / tcp.throughput) * 100.0
        output += "Throughput:\n"
        output += "  TCP:  \(String(format: "%.2f", tcp.throughput)) frames/sec\n"
        output += "  UDP:  \(String(format: "%.2f", udp.throughput)) frames/sec\n"
        output += "  Diff: \(String(format: "%.2f", throughputDiff))% (\(udp.throughput > tcp.throughput ? "UDP faster" : "TCP faster"))\n\n"
        
        // Bandwidth comparison
        let bandwidthDiff = ((udp.bandwidth - tcp.bandwidth) / tcp.bandwidth) * 100.0
        output += "Bandwidth:\n"
        output += "  TCP:  \(String(format: "%.2f", tcp.bandwidth)) MB/s\n"
        output += "  UDP:  \(String(format: "%.2f", udp.bandwidth)) MB/s\n"
        output += "  Diff: \(String(format: "%.2f", bandwidthDiff))% (\(udp.bandwidth > tcp.bandwidth ? "UDP faster" : "TCP faster"))\n\n"
        
        // Latency comparison
        output += "Latency (p50):\n"
        output += "  TCP:  \(String(format: "%.3f", tcp.latency.p50 * 1000)) ms\n"
        output += "  UDP:  \(String(format: "%.3f", udp.latency.p50 * 1000)) ms\n"
        let latencyDiff = ((udp.latency.p50 - tcp.latency.p50) / tcp.latency.p50) * 100.0
        output += "  Diff: \(String(format: "%.2f", latencyDiff))% (\(udp.latency.p50 < tcp.latency.p50 ? "UDP faster" : "TCP faster"))\n\n"
        
        // Overhead comparison
        output += "Overhead:\n"
        output += "  TCP:  \(tcp.overhead.headerBytes) bytes header (\(String(format: "%.2f", tcp.overhead.overheadPercent))%)\n"
        output += "  UDP:  \(udp.overhead.headerBytes) bytes header (\(String(format: "%.2f", udp.overhead.overheadPercent))%)\n"
        let overheadDiff = udp.overhead.headerBytes - tcp.overhead.headerBytes
        output += "  Diff: \(overheadDiff) bytes (\(overheadDiff < 0 ? "UDP smaller" : "TCP smaller"))\n\n"
        
        // Summary
        output += "Summary:\n"
        if udp.throughput > tcp.throughput {
            output += "  ✅ UDP has \(String(format: "%.1f", abs(throughputDiff)))% higher throughput\n"
        } else {
            output += "  ✅ TCP has \(String(format: "%.1f", abs(throughputDiff)))% higher throughput\n"
        }
        
        if udp.latency.p50 < tcp.latency.p50 {
            output += "  ✅ UDP has \(String(format: "%.1f", abs(latencyDiff)))% lower latency\n"
        } else {
            output += "  ✅ TCP has \(String(format: "%.1f", abs(latencyDiff)))% lower latency\n"
        }
        
        if udp.overhead.headerBytes < tcp.overhead.headerBytes {
            output += "  ✅ UDP has \(abs(overheadDiff)) bytes less overhead\n"
        } else {
            output += "  ✅ TCP has \(abs(overheadDiff)) bytes less overhead\n"
        }
        
        return output
    }
}

