# BlazeBinary is Transport-Agnostic

_Last updated: February 2025_

**Key Point**: BlazeBinary works on **ANY** transport protocol. It's a data encoding/decoding format, not a transport protocol.

## What BlazeBinary Provides

BlazeBinary provides **three independent layers**, all transport-agnostic:

### 1. Encoding/Decoding Layer (Transport-Agnostic)

**What it does**: Converts Swift values ↔ binary bytes

```swift
// Encode
let encoder = BlazeBinaryEncoder()
encoder.encode("Hello")
let data = encoder.encodedData()  // Just bytes - works anywhere!

// Decode
let decoder = BlazeBinaryDecoder(data: data)
let message = try decoder.decodeString()
```

**Works with**:
- TCP
- UDP
- Unix sockets (IPC)
- Shared memory
- Files
- Message queues
- Any byte stream

### 2. Frame Protocol (Transport-Agnostic)

**What it does**: Adds frame boundaries (length prefix + metadata) to delimit messages

```swift
// Create frame (just bytes)
let frame = try BlazeFrameEncoder.encodeFrame(payload)

// Parse frame (from any byte stream)
let parser = BlazeFrameParser()
try parser.append(receivedBytes)  // From TCP, UDP, IPC, etc.
if let payload = try parser.nextFrame() {
    // Got a complete frame!
}
```

**Works with**:
- TCP (byte stream)
- UDP (datagrams - one frame per datagram)
- Unix sockets
- Shared memory
- Any byte stream

**Note**: The frame protocol is just a way to delimit messages. It doesn't care how the bytes are delivered.

### 3. Secure Session (Optional, Transport-Agnostic)

**What it does**: Encrypts/decrypts frames using ChaCha20-Poly1305

```swift
// Encrypt frame
var session = BlazeSecureSession(keyMaterial: keys)
let encrypted = try session.makeEncryptedFrame(from: plaintext)

// Decrypt frame
let decrypted = try session.decryptFramePayload(encrypted)
```

**Works with**:
- TCP
- UDP
- IPC
- Shared memory
- Any transport

**Note**: Encryption is **end-to-end**. It doesn't depend on the transport layer.

## Transport Examples

### Example 1: TCP

```swift
import Network
import BlazeBinary

// Create TCP connection
let connection = NWConnection(host: "example.com", port: 8080, using: .tcp)
connection.start(queue: .global())

// Encode and frame
let encoder = BlazeBinaryEncoder()
encoder.encode("Hello")
let payload = encoder.encodedData()
let frame = try BlazeFrameEncoder.encodeFrame(payload)

// Send over TCP
connection.send(content: frame, completion: .contentProcessed { _ in })

// Receive from TCP
connection.receive { data, _, _, _ in
    let parser = BlazeFrameParser()
    try parser.append(data)
    if let payload = try parser.nextFrame() {
        let decoder = BlazeBinaryDecoder(data: payload)
        let message = try decoder.decodeString()
    }
}
```

### Example 2: UDP

```swift
import Network
import BlazeBinary

// Create UDP connection
let connection = NWConnection(host: "example.com", port: 8080, using: .udp)
connection.start(queue: .global())

// Encode and frame
let encoder = BlazeBinaryEncoder()
encoder.encode("Hello")
let payload = encoder.encodedData()
let frame = try BlazeFrameEncoder.encodeFrame(payload)

// Send over UDP (one frame per datagram)
connection.send(content: frame, completion: .contentProcessed { _ in })

// Receive from UDP
connection.receive { data, _, _, _ in
    // UDP delivers complete datagrams, so frame is complete
    let parser = BlazeFrameParser()
    try parser.append(data)
    if let payload = try parser.nextFrame() {
        let decoder = BlazeBinaryDecoder(data: payload)
        let message = try decoder.decodeString()
    }
}
```

### Example 3: Unix Sockets (IPC)

```swift
import Foundation
import BlazeBinary

// Create Unix socket
let socket = Socket.create(family: .unix, type: .stream, proto: .tcp)
try socket.connect(to: "/tmp/blaze.sock")

// Encode and frame
let encoder = BlazeBinaryEncoder()
encoder.encode("Hello")
let payload = encoder.encodedData()
let frame = try BlazeFrameEncoder.encodeFrame(payload)

// Send over Unix socket
try socket.write(from: frame)

// Receive from Unix socket
var buffer = Data()
try socket.read(into: &buffer)
let parser = BlazeFrameParser()
try parser.append(buffer)
if let payload = try parser.nextFrame() {
    let decoder = BlazeBinaryDecoder(data: payload)
    let message = try decoder.decodeString()
}
```

### Example 4: Shared Memory

```swift
import Foundation
import BlazeBinary

// Create shared memory
let shm = shm_open("/blaze_shm", O_CREAT | O_RDWR, 0666)
ftruncate(shm, 1024 * 1024)  // 1MB
let ptr = mmap(nil, 1024 * 1024, PROT_READ | PROT_WRITE, MAP_SHARED, shm, 0)

// Encode and frame
let encoder = BlazeBinaryEncoder()
encoder.encode("Hello")
let payload = encoder.encodedData()
let frame = try BlazeFrameEncoder.encodeFrame(payload)

// Write to shared memory
memcpy(ptr, frame.withUnsafeBytes { $0.baseAddress }, frame.count)

// Read from shared memory
let data = Data(bytes: ptr, count: frame.count)
let parser = BlazeFrameParser()
try parser.append(data)
if let payload = try parser.nextFrame() {
    let decoder = BlazeBinaryDecoder(data: payload)
    let message = try decoder.decodeString()
}
```

### Example 5: Files

```swift
import Foundation
import BlazeBinary

// Encode and frame
let encoder = BlazeBinaryEncoder()
encoder.encode("Hello")
let payload = encoder.encodedData()
let frame = try BlazeFrameEncoder.encodeFrame(payload)

// Write to file
try frame.write(to: URL(fileURLWithPath: "/tmp/blaze.bin"))

// Read from file
let data = try Data(contentsOf: URL(fileURLWithPath: "/tmp/blaze.bin"))
let parser = BlazeFrameParser()
try parser.append(data)
if let payload = try parser.nextFrame() {
    let decoder = BlazeBinaryDecoder(data: payload)
    let message = try decoder.decodeString()
}
```

## What BlazeBinary Does NOT Provide

BlazeBinary does **NOT** provide:

1. **Transport protocol** (TCP, UDP, etc.) - You provide this
2. **Connection management** - You handle connections
3. **Reliability** (retransmission, ordering) - Transport provides this
4. **Flow control** - Transport provides this
5. **Network addressing** - Transport provides this

## What BlazeBinary DOES Provide

BlazeBinary provides:

1. **Encoding/Decoding** - Convert values ↔ bytes
2. **Frame Delimiting** - Know where messages start/end
3. **Compression** - Optional LZ4/LZFSE compression
4. **Encryption** - Optional ChaCha20-Poly1305 encryption
5. **Determinism** - Same input → same bytes

## Security Layer

The **BlazeSecureSession** layer provides:

- **End-to-end encryption** - ChaCha20-Poly1305 AEAD
- **Key exchange** - X25519 Diffie-Hellman
- **Authentication** - Poly1305 MAC
- **Replay protection** - Nonce-based

**Important**: This is **application-layer security**, not transport-layer security.

- **TLS/SSL**: Secures the transport (TCP)
- **BlazeSecureSession**: Secures the data (BlazeBinary frames)

You can use **both**:
- TLS secures the connection
- BlazeSecureSession secures the data (defense in depth)

Or use **either**:
- TLS only (standard HTTPS-like)
- BlazeSecureSession only (custom encryption)

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────┐
│ Application Layer                                        │
│ - Your Swift code                                        │
└────────────────────┬────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────┐
│ BlazeBinaryEncoder/Decoder                              │
│ - Encoding/Decoding (transport-agnostic)                │
└────────────────────┬────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────┐
│ BlazeFrameEncoder/Parser                                │
│ - Frame delimiting (transport-agnostic)                  │
└────────────────────┬────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────┐
│ BlazeSecureSession (Optional)                           │
│ - Encryption (transport-agnostic)                        │
└────────────────────┬────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────┐
│ Transport Layer (YOU PROVIDE THIS)                      │
│ - TCP, UDP, Unix sockets, Shared memory, Files, etc.   │
└─────────────────────────────────────────────────────────┘
```

## Key Takeaways

1. **BlazeBinary is transport-agnostic** - Works with any byte stream
2. **You provide the transport** - TCP, UDP, IPC, shared memory, files, etc.
3. **Frames are just bytes** - The frame protocol doesn't care how bytes are delivered
4. **Encryption is optional** - BlazeSecureSession encrypts data, not transport
5. **Security is end-to-end** - Encryption works regardless of transport

## Common Misconceptions

### "BlazeBinary requires TCP"

**Reality**: BlazeBinary works with **any** transport. TCP is just one option.

### "BlazeBinary provides networking"

**Reality**: BlazeBinary provides encoding/decoding and framing. You provide networking.

### "BlazeSecureSession secures the transport"

**Reality**: BlazeSecureSession secures the **data** (application layer), not the transport. It works over any transport.

### "Frames only work over TCP"

**Reality**: Frames work over **any** byte stream - TCP, UDP, IPC, shared memory, files, etc.

## Conclusion

**BlazeBinary is a data encoding/decoding format, not a transport protocol.**

- Works with **any** transport (TCP, UDP, IPC, shared memory, files, etc.)
- Provides encoding/decoding, framing, compression, encryption
- Does **NOT** provide transport, connections, or networking
- You provide the transport layer
- BlazeBinary provides the data layer

**Think of it like JSON**: JSON works over HTTP, WebSockets, files, message queues, etc. BlazeBinary is the same - it's just a data format that works over any transport.

