# BlazeBinary Developer Guide

Complete guide for replacing JSON with BlazeBinary in your Swift application.

## Table of Contents

1. [Installation](#installation)
2. [Quick Start](#quick-start)
3. [Basic Encoding/Decoding](#basic-encodingdecoding)
4. [Codable Integration](#codable-integration)
5. [Primitive Types](#primitive-types)
6. [Collections](#collections)
7. [Optional Values](#optional-values)
8. [Custom Types](#custom-types)
9. [Frames (Message Boundaries)](#frames-message-boundaries)
10. [Encryption (Optional)](#encryption-optional)
11. [Error Handling](#error-handling)
12. [Migration from JSON](#migration-from-json)
13. [Best Practices](#best-practices)
14. [Performance Tips](#performance-tips)

---

## Installation

Add BlazeBinary to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/your-org/BlazeBinary.git", from: "0.1.0")
]
```

Or in Xcode: File → Add Packages → Enter the repository URL.

---

## Quick Start

### Replace JSON Encoding

**Before (JSON):**
```swift
struct User: Codable {
    let id: Int
    let name: String
    let email: String?
}

let user = User(id: 42, name: "Alice", email: "alice@example.com")

// JSON encoding
let jsonData = try JSONEncoder().encode(user)
let jsonString = String(data: jsonData, encoding: .utf8)!
```

**After (BlazeBinary):**
```swift
import BlazeBinary

struct User: BlazeBinaryCodable {
    let id: Int
    let name: String
    let email: String?
    
    // Encoding implementation
    func blazeEncode(to encoder: BlazeBinaryEncoder) throws {
        encoder.encode(id)
        encoder.encode(name)
        try encoder.encode(email)  // Optional handled automatically
    }
    
    // Decoding implementation
    init(from decoder: BlazeBinaryDecoder) throws {
        id = try decoder.decodeInt()
        name = try decoder.decodeString()
        email = try decoder.decodeOptional(String.self)
    }
}

let user = User(id: 42, name: "Alice", email: "alice@example.com")

// BlazeBinary encoding
let encoder = BlazeBinaryEncoder()
try encoder.encode(user)
let binaryData = encoder.encodedData()  // Returns Data, not JSON string
```

---

## Basic Encoding/Decoding

### Encoding a Value

```swift
let encoder = BlazeBinaryEncoder()

// Encode primitives
encoder.encode(42)                    // Int
encoder.encode(3.14)                  // Double
encoder.encode("Hello")               // String
encoder.encode(true)                  // Bool
encoder.encode(someData)              // Data

// Get the encoded bytes
let data = encoder.encodedData()  // Returns Data
```

### Decoding a Value

```swift
let decoder = BlazeBinaryDecoder(data: data)

// Decode in the same order as encoding
let number = try decoder.decodeInt()
let pi = try decoder.decodeDouble()
let text = try decoder.decodeString()
let flag = try decoder.decodeBool()
let data = try decoder.decodeData()
```

**Important:** Decode fields in the exact same order they were encoded.

---

## Codable Integration

### Automatic Codable Support

BlazeBinary provides automatic encoding/decoding for types that conform to `BlazeBinaryCodable`. For simple types, you can use the convenience API:

```swift
struct Message: BlazeBinaryCodable {
    let text: String
    let count: Int
}

// Encode
let encoder = BlazeBinaryEncoder()
try encoder.encode(Message(text: "Hello", count: 42))
let data = encoder.encodedData()

// Decode
let decoder = BlazeBinaryDecoder(data: data)
let message = try decoder.decode(Message.self)
```

### Manual Implementation (Recommended for Control)

For full control over encoding order and schema evolution, implement manually:

```swift
struct User: BlazeBinaryCodable {
    let id: Int
    let name: String
    let email: String?
    let tags: [String]
    
    func blazeEncode(to encoder: BlazeBinaryEncoder) throws {
        encoder.encode(id)
        encoder.encode(name)
        try encoder.encode(email)  // Optional
        try encoder.encode(tags)    // Array
    }
    
    init(from decoder: BlazeBinaryDecoder) throws {
        id = try decoder.decodeInt()
        name = try decoder.decodeString()
        email = try decoder.decodeOptional(String.self)
        tags = try decoder.decodeArray(String.self)
    }
}
```

---

## Primitive Types

### Supported Types

| Type | Encode Method | Decode Method | Notes |
|------|---------------|----------------|-------|
| `Int` | `encoder.encode(value)` | `try decoder.decodeInt()` | Varint (zigzag) |
| `UInt32` | `encoder.encode(value)` | `try decoder.decodeUInt32()` | Big-endian (4 bytes) |
| `UInt64` | `encoder.encode(value)` | `try decoder.decodeUInt64()` | Big-endian (8 bytes) |
| `UInt16` | `encoder.encode(value)` | `try decoder.decodeUInt16()` | Big-endian (2 bytes) |
| `Double` | `encoder.encode(value)` | `try decoder.decodeDouble()` | IEEE-754, big-endian (8 bytes) |
| `Float` | `encoder.encode(value)` | `try decoder.decodeFloat()` | IEEE-754, big-endian (4 bytes) |
| `Bool` | `encoder.encode(value)` | `try decoder.decodeBool()` | 1 byte (0x00=false, 0x01=true) |
| `String` | `encoder.encode(value)` | `try decoder.decodeString()` | UTF-8, length-prefixed |
| `Data` | `encoder.encode(value)` | `try decoder.decodeData()` | Length-prefixed bytes |

### Example: All Primitives

```swift
// Encoding
let encoder = BlazeBinaryEncoder()
encoder.encode(42)                    // Int
encoder.encode(UInt32(100))          // UInt32
encoder.encode(UInt64(200))          // UInt64
encoder.encode(UInt16(50))           // UInt16
encoder.encode(3.14159)               // Double
encoder.encode(Float(2.5))           // Float
encoder.encode(true)                 // Bool
encoder.encode("Hello, World!")      // String
encoder.encode(Data([1, 2, 3, 4]))   // Data

let data = encoder.encodedData()

// Decoding
let decoder = BlazeBinaryDecoder(data: data)
let intValue = try decoder.decodeInt()
let uint32Value = try decoder.decodeUInt32()
let uint64Value = try decoder.decodeUInt64()
let uint16Value = try decoder.decodeUInt16()
let doubleValue = try decoder.decodeDouble()
let floatValue = try decoder.decodeFloat()
let boolValue = try decoder.decodeBool()
let stringValue = try decoder.decodeString()
let dataValue = try decoder.decodeData()
```

### Endianness

**All fixed-width types use big-endian (network byte order)** for cross-language compatibility:

- `UInt16`, `UInt32`, `UInt64`: Big-endian
- `Float` (Float32), `Double` (Float64): IEEE-754 big-endian

This matches Python's `struct.pack('!H')`, `struct.pack('!I')`, `struct.pack('!Q')`, etc.

---

## Collections

### Arrays

```swift
// Encoding an array
let numbers = [1, 2, 3, 4, 5]
let encoder = BlazeBinaryEncoder()
try encoder.encode(numbers)  // Automatically encodes count + elements
let data = encoder.encodedData()

// Decoding an array
let decoder = BlazeBinaryDecoder(data: data)
let decoded = try decoder.decodeArray(Int.self)
```

### Arrays of Custom Types

```swift
struct Point: BlazeBinaryCodable {
    let x: Double
    let y: Double
    
    func blazeEncode(to encoder: BlazeBinaryEncoder) throws {
        encoder.encode(x)
        encoder.encode(y)
    }
    
    init(from decoder: BlazeBinaryDecoder) throws {
        x = try decoder.decodeDouble()
        y = try decoder.decodeDouble()
    }
}

// Encode array of Points
let points = [Point(x: 1.0, y: 2.0), Point(x: 3.0, y: 4.0)]
let encoder = BlazeBinaryEncoder()
try encoder.encode(points)
let data = encoder.encodedData()

// Decode array of Points
let decoder = BlazeBinaryDecoder(data: data)
let decoded = try decoder.decodeArray(Point.self)
```

### Dictionaries

**Note:** Only `[String: String]` dictionaries have built-in support. For other key types, encode as arrays of key-value pairs.

```swift
// Encoding a dictionary
let dict: [String: String] = ["name": "Alice", "city": "NYC"]
let encoder = BlazeBinaryEncoder()
try encoder.encode(dict)  // Keys are sorted for determinism
let data = encoder.encodedData()

// Decoding a dictionary
let decoder = BlazeBinaryDecoder(data: data)
let decoded = try decoder.decode([String: String].self)
```

### Custom Dictionary Encoding

For `[String: Int]` or other types, encode as key-value pairs:

```swift
struct UserScores: BlazeBinaryCodable {
    let scores: [String: Int]
    
    func blazeEncode(to encoder: BlazeBinaryEncoder) throws {
        // Encode as sorted key-value pairs
        let sortedKeys = scores.keys.sorted()
        encoder.encode(sortedKeys.count)
        for key in sortedKeys {
            encoder.encode(key)
            encoder.encode(scores[key]!)
        }
    }
    
    init(from decoder: BlazeBinaryDecoder) throws {
        let count = try decoder.decodeInt()
        var result: [String: Int] = [:]
        for _ in 0..<count {
            let key = try decoder.decodeString()
            let value = try decoder.decodeInt()
            result[key] = value
        }
        self.scores = result
    }
}
```

---

## Optional Values

### Encoding/Decoding Optionals

```swift
struct User: BlazeBinaryCodable {
    let id: Int
    let name: String
    let email: String?  // Optional
    
    func blazeEncode(to encoder: BlazeBinaryEncoder) throws {
        encoder.encode(id)
        encoder.encode(name)
        try encoder.encode(email)  // Handles nil automatically
    }
    
    init(from decoder: BlazeBinaryDecoder) throws {
        id = try decoder.decodeInt()
        name = try decoder.decodeString()
        email = try decoder.decodeOptional(String.self)  // Returns String?
    }
}
```

### Optional Primitives

```swift
// Encoding
let encoder = BlazeBinaryEncoder()
encoder.encode(42)
try encoder.encode(optionalString)  // Can be nil

// Decoding
let decoder = BlazeBinaryDecoder(data: data)
let number = try decoder.decodeInt()
let maybeString = try decoder.decodeOptional(String.self)  // Returns String?
```

---

## Custom Types

### Simple Struct

```swift
struct Person: BlazeBinaryCodable {
    let name: String
    let age: Int
    let height: Double
    
    func blazeEncode(to encoder: BlazeBinaryEncoder) throws {
        encoder.encode(name)
        encoder.encode(age)
        encoder.encode(height)
    }
    
    init(from decoder: BlazeBinaryDecoder) throws {
        name = try decoder.decodeString()
        age = try decoder.decodeInt()
        height = try decoder.decodeDouble()
    }
}
```

### Nested Types

```swift
struct Address: BlazeBinaryCodable {
    let street: String
    let city: String
    let zip: Int
    
    func blazeEncode(to encoder: BlazeBinaryEncoder) throws {
        encoder.encode(street)
        encoder.encode(city)
        encoder.encode(zip)
    }
    
    init(from decoder: BlazeBinaryDecoder) throws {
        street = try decoder.decodeString()
        city = try decoder.decodeString()
        zip = try decoder.decodeInt()
    }
}

struct User: BlazeBinaryCodable {
    let name: String
    let address: Address
    
    func blazeEncode(to encoder: BlazeBinaryEncoder) throws {
        encoder.encode(name)
        try encoder.encode(address)  // Encode nested type
    }
    
    init(from decoder: BlazeBinaryDecoder) throws {
        name = try decoder.decodeString()
        address = try Address(from: decoder)  // Decode nested type
    }
}
```

### Enums

```swift
enum Status: BlazeBinaryCodable {
    case active
    case inactive
    case pending(String)  // Associated value
    
    func blazeEncode(to encoder: BlazeBinaryEncoder) throws {
        switch self {
        case .active:
            encoder.encode(0)  // Tag for active
        case .inactive:
            encoder.encode(1)  // Tag for inactive
        case .pending(let reason):
            encoder.encode(2)  // Tag for pending
            encoder.encode(reason)
        }
    }
    
    init(from decoder: BlazeBinaryDecoder) throws {
        let tag = try decoder.decodeInt()
        switch tag {
        case 0:
            self = .active
        case 1:
            self = .inactive
        case 2:
            let reason = try decoder.decodeString()
            self = .pending(reason)
        default:
            throw BlazeBinaryError.decodeFailed("Invalid Status tag: \(tag)")
        }
    }
}
```

---

## Frames (Message Boundaries)

Frames delimit messages in byte streams. Use frames when sending data over TCP, UDP, or any byte stream.

### Creating a Frame

```swift
// Encode your message
let encoder = BlazeBinaryEncoder()
try encoder.encode(user)
let payload = encoder.encodedData()

// Wrap in a frame
let frame = try BlazeFrameEncoder.encodeFrame(
    payload,
    frameType: 0x01,  // Your message type
    compressionMode: .none
)

// Send frame over your transport (TCP, UDP, etc.)
socket.write(frame)
```

### Parsing Frames from a Stream

```swift
var parser = BlazeFrameParser()
var buffer = Data()

// When you receive bytes from your transport
func onBytesReceived(_ data: Data) throws {
    buffer.append(data)
    
    // Feed bytes to parser
    try parser.append(data)
    
    // Extract complete frames
    while let framePayload = try parser.nextFrame() {
        // Decode the message from frame payload
        let decoder = BlazeBinaryDecoder(data: framePayload)
        let user = try decoder.decode(User.self)
        
        // Process the message
        handleMessage(user)
    }
}
```

### Frame Format

- **Byte 0**: Frame type (0x00 = plaintext, 0x01 = encrypted, 0x02 = handshake)
- **Byte 1**: Compression mode (0x00 = none, 0x01 = LZ4, 0x02 = LZFSE)
- **Bytes 2-5**: Payload length (UInt32, big-endian)
- **Bytes 6+**: Payload data

Maximum frame size: 5 MB (enforced).

---

## Encryption (Optional)

### Simple Encryption Hook

```swift
import Crypto

// Generate or load a symmetric key
let key = SymmetricKey(size: .bits256)

// Encrypt a payload
let payload = encoder.encodedData()
let encrypted = try encryptPayload(payload, using: key)

// Decrypt a payload
let decrypted = try decryptPayload(encrypted, using: key)
let decoder = BlazeBinaryDecoder(data: decrypted)
let user = try decoder.decode(User.self)
```

### Full Secure Session (X25519 Key Exchange)

```swift
import BlazeBinary

// Client side
var clientHandshake = BlazeSecureHandshake(role: .client)
let clientHello = clientHandshake.makeClientHello()
// Send clientHello to server...

// After receiving serverHello
try clientHandshake.receiveRemotePublicKey(serverPublicKey)
let keyMaterial = try clientHandshake.deriveSessionKeys()

// Create secure session
var session = BlazeSecureSession(keyMaterial: keyMaterial)

// Encrypt a frame
let payload = encoder.encodedData()
let encryptedFrame = try session.makeEncryptedFrame(from: payload)

// Decrypt a frame
let decrypted = try session.decryptFramePayload(encryptedFrame)
let decoder = BlazeBinaryDecoder(data: decrypted)
let user = try decoder.decode(User.self)
```

---

## Error Handling

### Error Types

```swift
enum BlazeBinaryError: Error {
    case truncated              // Not enough data
    case decodeFailed(String)   // Decoding error
    case oversizedFrame         // Frame too large
    // ... others
}
```

### Handling Errors

```swift
do {
    let decoder = BlazeBinaryDecoder(data: data)
    let user = try decoder.decode(User.self)
    // Use user...
} catch BlazeBinaryError.truncated {
    // Need more data - wait for more bytes
    print("Need more data")
} catch BlazeBinaryError.decodeFailed(let message) {
    // Decoding failed
    print("Decode error: \(message)")
} catch {
    // Other errors
    print("Error: \(error)")
}
```

---

## Migration from JSON

### Step 1: Replace Codable with BlazeBinaryCodable

**Before:**
```swift
struct User: Codable {
    let id: Int
    let name: String
}
```

**After:**
```swift
struct User: BlazeBinaryCodable {
    let id: Int
    let name: String
    
    func blazeEncode(to encoder: BlazeBinaryEncoder) throws {
        encoder.encode(id)
        encoder.encode(name)
    }
    
    init(from decoder: BlazeBinaryDecoder) throws {
        id = try decoder.decodeInt()
        name = try decoder.decodeString()
    }
}
```

### Step 2: Replace JSONEncoder/JSONDecoder

**Before:**
```swift
// Encoding
let jsonData = try JSONEncoder().encode(user)
let jsonString = String(data: jsonData, encoding: .utf8)!

// Decoding
let jsonData = jsonString.data(using: .utf8)!
let user = try JSONDecoder().decode(User.self, from: jsonData)
```

**After:**
```swift
// Encoding
let encoder = BlazeBinaryEncoder()
try encoder.encode(user)
let binaryData = encoder.encodedData()  // Returns Data, not String

// Decoding
let decoder = BlazeBinaryDecoder(data: binaryData)
let user = try decoder.decode(User.self)
```

### Step 3: Update Network Code

**Before (JSON over HTTP):**
```swift
let jsonData = try JSONEncoder().encode(user)
var request = URLRequest(url: url)
request.httpBody = jsonData
request.setValue("application/json", forHTTPHeaderField: "Content-Type")
```

**After (BlazeBinary over custom transport):**
```swift
let encoder = BlazeBinaryEncoder()
try encoder.encode(user)
let payload = encoder.encodedData()
let frame = try BlazeFrameEncoder.encodeFrame(payload, frameType: 0x01)
// Send frame over your transport (TCP, UDP, etc.)
```

### Step 4: Handle Optionals

JSON handles optionals automatically. BlazeBinary requires explicit handling:

**Before:**
```swift
struct User: Codable {
    let email: String?  // JSON handles this automatically
}
```

**After:**
```swift
struct User: BlazeBinaryCodable {
    let email: String?
    
    func blazeEncode(to encoder: BlazeBinaryEncoder) throws {
        try encoder.encode(email)  // Explicit optional encoding
    }
    
    init(from decoder: BlazeBinaryDecoder) throws {
        email = try decoder.decodeOptional(String.self)  // Explicit optional decoding
    }
}
```

---

## Best Practices

### 1. Always Encode/Decode in the Same Order

```swift
// Encoding order
encoder.encode(id)
encoder.encode(name)
encoder.encode(age)

// Decoding MUST match
let id = try decoder.decodeInt()
let name = try decoder.decodeString()
let age = try decoder.decodeInt()
```

### 2. Use Schema Versions for Evolution

```swift
// Encode with schema version 2
let encoder = BlazeBinaryEncoder(schemaVersion: 2)
try encoder.encode(user)
let data = encoder.encodedData()

// Decode (automatically detects schema version)
let decoder = BlazeBinaryDecoder(data: data)
if decoder.version == 2 {
    // Handle v2 format
} else {
    // Handle v1 format (backwards compatibility)
}
```

### 3. Handle Truncated Data

```swift
var parser = BlazeFrameParser()
var buffer = Data()

func onBytesReceived(_ data: Data) {
    buffer.append(data)
    try parser.append(data)
    
    while let frame = try parser.nextFrame() {
        // Process complete frame
        processFrame(frame)
    }
    
    // Incomplete frames remain in parser's buffer
}
```

### 4. Use Zero-Copy for Large Data

```swift
// For large Data fields, use zero-copy decoding
let dataSlice = try decoder.decodeDataZeroCopy()  // Returns Data slice, no copy
// Use dataSlice directly without copying
```

### 5. Validate Input Sizes

```swift
// Set maximum allowed length for variable-length fields
let decoder = BlazeBinaryDecoder(
    data: data,
    maxAllowedLength: 1024 * 1024  // 1 MB max
)
```

---

## Performance Tips

### 1. Reuse Encoders/Decoders

```swift
// Create once, reuse
let encoder = BlazeBinaryEncoder()

// Encode multiple values
try encoder.encode(user1)
let data1 = encoder.encodedData()

encoder.data.removeAll()  // Clear for next use
try encoder.encode(user2)
let data2 = encoder.encodedData()
```

### 2. Use Frames for Streaming

```swift
// For streaming data, use frame parser
var parser = BlazeFrameParser()

// Append bytes as they arrive
try parser.append(receivedBytes)

// Extract complete frames
while let frame = try parser.nextFrame() {
    processFrame(frame)
}
```

### 3. Batch Operations

```swift
// Encode multiple items efficiently
let encoder = BlazeBinaryEncoder()
for item in items {
    try encoder.encode(item)
}
let allData = encoder.encodedData()
```

### 4. Compression for Large Payloads

```swift
// Compress large payloads
let payload = encoder.encodedData()
let frame = try BlazeFrameEncoder.encodeFrame(
    payload,
    frameType: 0x01,
    compressionMode: .lz4  // Compress if payload > threshold
)
```

---

## Complete Example: API Client

```swift
import BlazeBinary

// Define your message types
struct Request: BlazeBinaryCodable {
    let method: String
    let path: String
    let body: Data?
    
    func blazeEncode(to encoder: BlazeBinaryEncoder) throws {
        encoder.encode(method)
        encoder.encode(path)
        try encoder.encode(body)
    }
    
    init(from decoder: BlazeBinaryDecoder) throws {
        method = try decoder.decodeString()
        path = try decoder.decodeString()
        body = try decoder.decodeOptional(Data.self)
    }
}

struct Response: BlazeBinaryCodable {
    let status: Int
    let body: Data
    
    func blazeEncode(to encoder: BlazeBinaryEncoder) throws {
        encoder.encode(status)
        encoder.encode(body)
    }
    
    init(from decoder: BlazeBinaryDecoder) throws {
        status = try decoder.decodeInt()
        body = try decoder.decodeData()
    }
}

// Client code
class APIClient {
    func sendRequest(_ request: Request) throws -> Response {
        // Encode request
        let encoder = BlazeBinaryEncoder()
        try encoder.encode(request)
        let payload = encoder.encodedData()
        
        // Wrap in frame
        let frame = try BlazeFrameEncoder.encodeFrame(
            payload,
            frameType: 0x01,
            compressionMode: .none
        )
        
        // Send over your transport (TCP, UDP, etc.)
        socket.write(frame)
        
        // Receive response frame
        let responseFrame = socket.read()
        
        // Parse frame
        var parser = BlazeFrameParser()
        try parser.append(responseFrame)
        guard let responsePayload = try parser.nextFrame() else {
            throw BlazeBinaryError.truncated
        }
        
        // Decode response
        let decoder = BlazeBinaryDecoder(data: responsePayload)
        return try decoder.decode(Response.self)
    }
}
```

---

## Summary

**Key Differences from JSON:**

1. **Binary format** - Not human-readable, but much faster and smaller
2. **Deterministic** - Same input always produces same bytes (great for hashing/caching)
3. **Zero-copy** - Efficient decoding for large payloads
4. **Explicit ordering** - Must encode/decode fields in the same order
5. **Big-endian** - All fixed-width types use network byte order
6. **Frame-based** - Use frames for message boundaries in byte streams
7. **Optional encryption** - Built-in ChaCha20-Poly1305 support

**When to Use BlazeBinary:**

- High-performance serialization
- Network protocols (TCP, UDP, custom transports)
- IPC (inter-process communication)
- File storage (deterministic format)
- When you need deterministic encoding (hashing, caching)

**When to Use JSON:**

- Human-readable configuration files
- REST APIs (standard JSON)
- Debugging (readable format)
- When interoperability with non-Swift systems is required

---

For more details, see the [BlazeBinary Documentation](README.md).
