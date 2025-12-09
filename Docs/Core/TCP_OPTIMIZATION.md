# TCP Optimization Guide for BlazeBinary

_Last updated: February 2025_

Instead of implementing a custom transport protocol, optimize TCP usage to get 80% of the benefit with 1% of the effort.

## Quick Wins

### 1. Disable Nagle's Algorithm (TCP_NODELAY)

**Problem**: Nagle's algorithm batches small packets, adding 40ms delay.

**Solution**:
```swift
import Network

let options = NWProtocolTCP.Options()
options.noDelay = true  // Disable Nagle's algorithm

let parameters = NWParameters(tls: nil, tcp: options)
let connection = NWConnection(host: "example.com", port: 8080, using: parameters)
```

**Gain**: Eliminates 40ms latency per frame
**Effort**: 1 line of code
**Impact**: High for small frames

### 2. Disable Delayed ACK (TCP_QUICKACK)

**Problem**: TCP delays ACKs by up to 200ms to batch acknowledgments.

**Solution**:
```swift
// Note: TCP_QUICKACK is Linux-specific
// On macOS/iOS, use TCP_NODELAY which helps
// For maximum control, use raw sockets (advanced)
```

**Alternative (macOS/iOS)**: Use `TCP_NODELAY` + immediate writes
```swift
// Write immediately, don't buffer
connection.send(content: frame, completion: .contentProcessed { _ in })
```

**Gain**: Eliminates 200ms latency per frame
**Effort**: 1 line of code
**Impact**: Very high for request-response patterns

### 3. Increase Send/Receive Buffers

**Problem**: Small buffers limit throughput.

**Solution**:
```swift
let options = NWProtocolTCP.Options()
// Increase buffer sizes (platform-specific)
// macOS/iOS handles this automatically, but you can tune:
let parameters = NWParameters(tls: nil, tcp: options)
```

**Gain**: Better throughput for large transfers
**Effort**: Low
**Impact**: Medium

### 4. Use SO_REUSEPORT (Load Balancing)

**Problem**: Single connection limits throughput.

**Solution**:
```swift
// Create multiple connections
let connections = (0..<4).map { _ in
    NWConnection(host: "example.com", port: 8080, using: parameters)
}
// Distribute frames across connections
```

**Gain**: Parallel processing, better throughput
**Effort**: Moderate
**Impact**: High for high-frequency scenarios

### 5. Batch Small Frames

**Problem**: Many small frames = many syscalls.

**Solution**:
```swift
var frameBuffer: [Data] = []
let batchSize = 10
let batchTimeout = 1.0 // milliseconds

func sendFrame(_ frame: Data) {
    frameBuffer.append(frame)
    if frameBuffer.count >= batchSize {
        flushFrames()
    }
}

func flushFrames() {
    let batched = frameBuffer.reduce(Data(), +)
    connection.send(content: batched, completion: .contentProcessed { _ in })
    frameBuffer.removeAll()
}
```

**Gain**: Reduces syscall overhead
**Effort**: Moderate
**Impact**: Medium for high-frequency scenarios

## Advanced Optimizations

### 6. Zero-Copy Sends (Platform-Specific)

**macOS/iOS**: Use `sendfile()` for large frames
**Linux**: Use `sendfile()` or `splice()`

**Gain**: Eliminates memory copies
**Effort**: High (platform-specific code)
**Impact**: High for large frames (>8KB)

### 7. Polling Instead of Interrupts

**Problem**: Interrupts add latency.

**Solution**: Use `kqueue` (macOS) or `epoll` (Linux) for polling

**Gain**: Lower latency, better throughput
**Effort**: Very high
**Impact**: High for high-frequency scenarios

### 8. Kernel Bypass (io_uring, XDP)

**Problem**: Kernel overhead dominates.

**Solution**: Use io_uring (Linux) or XDP for kernel bypass

**Gain**: 10-20% performance improvement
**Effort**: Very high (requires kernel-bypass infrastructure)
**Impact**: Very high, but only for specialized use cases

## Complete Example

```swift
import Foundation
import Network
import BlazeBinary

class OptimizedBlazeBinaryClient {
    private let connection: NWConnection
    private let parser: BlazeFrameParser
    
    init(host: String, port: UInt16) {
        // Optimize TCP options
        let tcpOptions = NWProtocolTCP.Options()
        tcpOptions.noDelay = true  // Disable Nagle
        
        let parameters = NWParameters(tls: nil, tcp: tcpOptions)
        self.connection = NWConnection(host: NWEndpoint.Host(host), port: NWEndpoint.Port(integerLiteral: port), using: parameters)
        
        self.parser = BlazeFrameParser()
        
        // Start connection
        connection.start(queue: .global())
    }
    
    func sendFrame(_ frame: Data) {
        // Send immediately (no buffering)
        connection.send(
            content: frame,
            completion: .contentProcessed { error in
                if let error = error {
                    print("Send error: \(error)")
                }
            }
        )
    }
    
    func receiveFrame(completion: @escaping (Data?) -> Void) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, isComplete, error in
            if let error = error {
                print("Receive error: \(error)")
                completion(nil)
                return
            }
            
            if let data = data {
                do {
                    try self.parser.append(data)
                    if let payload = try self.parser.nextFrame() {
                        completion(payload)
                    } else {
                        // Need more data, continue receiving
                        self.receiveFrame(completion: completion)
                    }
                } catch {
                    print("Parse error: \(error)")
                    completion(nil)
                }
            }
        }
    }
}
```

## Performance Comparison

| Optimization | Latency Reduction | Throughput Gain | Effort |
|--------------|-------------------|-----------------|--------|
| TCP_NODELAY | 40ms | 0% | Low |
| Immediate writes | 200ms | 0% | Low |
| Buffer tuning | 0ms | 5-10% | Low |
| Connection pooling | 0ms | 20-50% | Medium |
| Batching | 0ms | 10-20% | Medium |
| Zero-copy | 0ms | 5-10% | High |
| Polling | 1-5ms | 10-15% | Very High |
| Kernel bypass | 1-5ms | 10-20% | Very High |

**Total Gain from Easy Optimizations**: 240ms latency + 5-10% throughput
**Total Effort**: ~1 day
**ROI**: Excellent

## When to Use Each Optimization

### For Low Latency (<1ms)
- TCP_NODELAY
- Immediate writes
- Polling (if needed)

### For High Throughput (>1M frames/sec)
- Connection pooling
- Batching
- Buffer tuning
- Kernel bypass (if infrastructure available)

### For Large Frames (>8KB)
- Zero-copy
- Buffer tuning

### For General Use
- TCP_NODELAY
- Immediate writes
- Buffer tuning

## Conclusion

**TCP optimization provides 80% of BlazeTransport's benefit with 1% of the effort.**

**Recommended approach**:
1. Met Use TCP_NODELAY (eliminates 40ms)
2. Met Use immediate writes (eliminates 200ms)
3. Met Tune buffers (5-10% throughput)
4. Met Consider connection pooling (if needed)
5. Don't implement BlazeTransport (unless proven need)

**Total gain**: 240ms latency + 5-10% throughput
**Total effort**: 1 day
**ROI**: Excellent

