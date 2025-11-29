# BlazeBinary Frame Protocol

This document describes the frame format used for IPC (Inter-Process Communication) and socket-based protocols.

## Table of Contents

1. [Frame Format](#frame-format)
2. [Frame Encoding](#frame-encoding)
3. [Frame Decoding](#frame-decoding)
4. [Partial Frames](#partial-frames)
5. [Multiple Frames](#multiple-frames)
6. [Error Handling](#error-handling)
7. [Implementation Examples](#implementation-examples)

---

## Frame Format

### Structure

```
┌─────────────────────────────────────────────────────────┐
│                    BlazeBinary Frame                     │
├─────────────────────────────────────────────────────────┤
│                                                          │
│  ┌──────────────────────┐  ┌──────────────────────────┐ │
│  │ Length Prefix        │  │  Payload                 │ │
│  │ (4 bytes, big-endian)│  │  (BlazeBinary encoded)   │ │
│  └──────────────────────┘  └──────────────────────────┘ │
│                                                          │
│  Total Size: 4 + payload.length bytes                   │
│                                                          │
└─────────────────────────────────────────────────────────┘
```

### Length Prefix

- **Size**: 4 bytes
- **Format**: Big-endian UInt32
- **Value**: Payload length in bytes
- **Constraints**: `0 < length <= 5,242,880` (5 MB)
- **Validation**: Length = 0 throws `BlazeBinaryError.invalidFrameLength`
- **Validation**: Length > 5,242,880 throws `BlazeBinaryError.invalidFrameLength`

### Payload

- **Format**: BlazeBinary-encoded data (any valid BlazeBinary encoding)
- **Size**: Variable, must match length prefix exactly
- **Content**: Any valid BlazeBinary encoding (primitives, structs, arrays, etc.)

### Constraints

- **Max Frame Size**: 5 MB (5,242,880 bytes) - enforced in `BlazeFrameEncoder.encodeFrame()`
- **Max Buffer Size**: 10 MB (10,485,760 bytes) - enforced in `BlazeFrameParser.append()`
- **Min Frame Size**: 5 bytes (4-byte header + 1-byte minimum payload)
- **Length Validation**: Length prefix must be > 0 and <= maxFrameSize before payload extraction

---

## Frame Encoding

### API

```swift
let payload = Data([...])  // BlazeBinary-encoded data
let frame = try BlazeFrameEncoder.encodeFrame(payload)
```

### Process

1. **Validate Payload Size**
   ```swift
   guard payload.count <= 5 * 1024 * 1024 else {
       throw BlazeBinaryError.oversizedFrame
   }
   ```

2. **Encode Length Prefix**
   ```swift
   let length = UInt32(payload.count).bigEndian
   // Convert to 4 bytes: [MSB, ..., LSB]
   ```

3. **Concatenate**
   ```swift
   frame = lengthPrefix + payload
   ```

### Example

```swift
let payload = Data([0x01, 0x02, 0x03, 0x04])  // 4 bytes
let frame = try BlazeFrameEncoder.encodeFrame(payload)

// Frame bytes:
// [0x00, 0x00, 0x00, 0x04, 0x01, 0x02, 0x03, 0x04]
//  └─────────┬─────────┘  └──────────┬──────────┘
//    Length (big-endian)      Payload
```

### Binary Layout

For payload of length 1000 (0x000003E8):

```
┌─────────────────────────────────────────────────────────┐
│ Byte 0: 0x00  (MSB of length)                         │
│ Byte 1: 0x00                                           │
│ Byte 2: 0x03                                           │
│ Byte 3: 0xE8  (LSB of length = 1000)                  │
│ Byte 4..1003: Payload bytes                           │
└─────────────────────────────────────────────────────────┘
```

---

## Frame Decoding

### Streaming Parser

The `BlazeFrameParser` handles incremental frame extraction from a stream:

```swift
let parser = BlazeFrameParser()

// Append data as it arrives
try parser.append(receivedData1)
try parser.append(receivedData2)

// Extract complete frames
while let payload = try parser.nextFrame() {
    // Process payload
    let decoder = BlazeBinaryDecoder(data: payload)
    // ... decode your data
}
```

### State Machine

The frame parser implements a strict 3-state machine:

**State 1: Waiting for Length Prefix**
- Condition: `buffer.count < 4`
- Action: Return `nil` (need more data)
- Error: None (partial data is expected)
- Next: Caller should append more data and call `nextFrame()` again

**State 2: Length Prefix Complete, Waiting for Payload**
- Condition: `buffer.count >= 4 && buffer.count < 4 + length`
- Action: 
  1. Read length prefix (big-endian UInt32 from bytes 0-3)
  2. Validate: `length > 0 && length <= maxFrameSize`
  3. If invalid: throw `BlazeBinaryError.invalidFrameLength`
  4. If valid but incomplete: return `nil` (need more payload data)
- Error: Throws `BlazeBinaryError.invalidFrameLength` if length is 0 or > maxFrameSize
- Next: Caller should append more data and call `nextFrame()` again

**State 3: Complete Frame Available**
- Condition: `buffer.count >= 4 + length`
- Action:
  1. Extract payload: `buffer.subdata(in: 4..<(4 + length))`
  2. Remove frame from buffer: `buffer.removeFirst(4 + length)`
  3. Return payload
- Error: None (frame is complete and valid)
- Next: Caller can process payload, then call `nextFrame()` for next frame

**Critical Invariants:**
- Partial frames never throw errors (they return `nil`)
- Invalid frame lengths throw immediately (before any payload processing)
- Frame extraction is atomic (all-or-nothing)
- Buffer state remains consistent after `nil` returns

### Algorithm

```swift
func nextFrame() throws -> Data? {
    // Step 1: Check for length prefix
    guard buffer.count >= 4 else {
        return nil  // Need more data
    }
    
    // Step 2: Read length (big-endian)
    let length = readBigEndianUInt32(buffer[0..<4])
    
    // Step 3: Validate length
    guard length > 0 && length <= maxFrameSize else {
        throw BlazeBinaryError.invalidFrameLength
    }
    
    // Step 4: Check for complete frame
    let totalSize = 4 + length
    guard buffer.count >= totalSize else {
        return nil  // Need more data
    }
    
    // Step 5: Extract payload
    let payload = buffer[4..<(4 + length)]
    
    // Step 6: Remove frame from buffer
    buffer.removeFirst(totalSize)
    
    return payload
}
```

---

## Partial Frames

### Scenario

Network data arrives in chunks. A frame may be split across multiple chunks:

```
Chunk 1: [0x00, 0x00, 0x00, 0x04, 0x01, 0x02]  (6 bytes)
Chunk 2: [0x03, 0x04]  (2 bytes)
```

### Handling

```swift
let parser = BlazeFrameParser()

// Append first chunk
try parser.append(chunk1)
let frame1 = try parser.nextFrame()
// frame1 == nil (partial frame)

// Append second chunk
try parser.append(chunk2)
let frame2 = try parser.nextFrame()
// frame2 == Data([0x01, 0x02, 0x03, 0x04])  (complete)
```

### Visual Representation

```
┌─────────────────────────────────────────────────────────┐
│              Partial Frame Handling                     │
├─────────────────────────────────────────────────────────┤
│                                                          │
│  Time T1: Receive chunk 1                              │
│    Buffer: [0x00, 0x00, 0x00, 0x04, 0x01, 0x02]        │
│    Length: 4                                            │
│    Needed: 4 + 4 = 8 bytes                              │
│    Available: 6 bytes                                  │
│    Result: nil (need 2 more bytes)                      │
│                                                          │
│  Time T2: Receive chunk 2                               │
│    Buffer: [0x00, 0x00, 0x00, 0x04, 0x01, 0x02,        │
│             0x03, 0x04]                                 │
│    Length: 4                                            │
│    Needed: 8 bytes                                      │
│    Available: 8 bytes                                  │
│    Result: Data([0x01, 0x02, 0x03, 0x04])              │
│                                                          │
└─────────────────────────────────────────────────────────┘
```

---

## Multiple Frames

### Concatenated Frames

Multiple frames can be concatenated in a single buffer:

```
Frame 1: [length1(4) + payload1]
Frame 2: [length2(4) + payload2]
Frame 3: [length3(4) + payload3]

Stream: [Frame1][Frame2][Frame3]
```

### Parsing

```swift
let parser = BlazeFrameParser()
try parser.append(allFrames)

// Extract frames sequentially
var frames: [Data] = []
while let payload = try parser.nextFrame() {
    frames.append(payload)
}

// frames contains all payloads in order
```

### Example

```swift
let payload1 = Data([0x01, 0x02])
let payload2 = Data([0x03, 0x04, 0x05])

let frame1 = try BlazeFrameEncoder.encodeFrame(payload1)
let frame2 = try BlazeFrameEncoder.encodeFrame(payload2)

let concatenated = frame1 + frame2

let parser = BlazeFrameParser()
try parser.append(concatenated)

let decoded1 = try parser.nextFrame()  // Data([0x01, 0x02])
let decoded2 = try parser.nextFrame()   // Data([0x03, 0x04, 0x05])
let decoded3 = try parser.nextFrame()  // nil (no more frames)
```

---

## Error Handling

### Error Cases

1. **Invalid Frame Length**
   - Length = 0
   - Length > maxFrameSize (5 MB)
   - Throws: `BlazeBinaryError.invalidFrameLength`

2. **Oversized Buffer**
   - Buffer size > maxBufferSize (10 MB)
   - Throws: `BlazeBinaryError.oversizedFrame`

3. **Truncated Frame**
   - Length prefix indicates frame size, but payload is incomplete
   - `nextFrame()` returns `nil` (need more data)

4. **Corrupted Data**
   - Invalid length prefix (though this is hard to detect)
   - Handled by validation checks

### Example Error Handling

```swift
let parser = BlazeFrameParser()

do {
    try parser.append(data)
    
    while let payload = try parser.nextFrame() {
        // Process payload
    }
} catch BlazeBinaryError.invalidFrameLength {
    // Handle invalid frame length
    print("Invalid frame length")
} catch BlazeBinaryError.oversizedFrame {
    // Handle oversized frame
    print("Frame or buffer too large")
} catch {
    // Other errors
    print("Error: \(error)")
}
```

---

## Implementation Examples

### Server-Side (Encoding)

```swift
func sendMessage(_ message: Message) throws {
    // Encode message
    let encoder = BlazeBinaryEncoder()
    try encoder.encode(message)
    let payload = encoder.encodedData()
    
    // Wrap in frame
    let frame = try BlazeFrameEncoder.encodeFrame(payload)
    
    // Send over network
    socket.write(frame)
}
```

### Client-Side (Decoding)

```swift
class FrameReceiver {
    private let parser = BlazeFrameParser()
    
    func receive(_ data: Data) throws {
        try parser.append(data)
        
        // Process all complete frames
        while let payload = try parser.nextFrame() {
            try processFrame(payload)
        }
    }
    
    private func processFrame(_ payload: Data) throws {
        let decoder = BlazeBinaryDecoder(data: payload)
        let message = try decoder.decode(Message.self)
        
        // Handle message
        handleMessage(message)
    }
}
```

### Complete Example

```swift
// Define message type
struct ChatMessage: BlazeBinaryCodable {
    var from: String
    var text: String
    var timestamp: Int
    
    func blazeEncode(to encoder: BlazeBinaryEncoder) throws {
        encoder.encode(from)
        encoder.encode(text)
        encoder.encode(timestamp)
    }
    
    init(from decoder: BlazeBinaryDecoder) throws {
        self.from = try decoder.decodeString()
        self.text = try decoder.decodeString()
        self.timestamp = try decoder.decodeInt()
    }
}

// Server: Send message
func sendChatMessage(_ message: ChatMessage) throws -> Data {
    let encoder = BlazeBinaryEncoder()
    try encoder.encode(message)
    let payload = encoder.encodedData()
    return try BlazeFrameEncoder.encodeFrame(payload)
}

// Client: Receive message
func receiveChatMessage(_ data: Data) throws -> ChatMessage? {
    let parser = BlazeFrameParser()
    try parser.append(data)
    
    guard let payload = try parser.nextFrame() else {
        return nil  // Need more data
    }
    
    let decoder = BlazeBinaryDecoder(data: payload)
    return try decoder.decode(ChatMessage.self)
}
```

---

## Best Practices

1. **Always check for nil**: `nextFrame()` returns `nil` when more data is needed
2. **Handle errors gracefully**: Invalid frames should not crash the application
3. **Limit buffer size**: Monitor `parser.bufferSize` to prevent memory issues
4. **Clear buffer when needed**: Use `parser.clear()` to reset state
5. **Validate payloads**: After extracting a frame, validate the BlazeBinary data
6. **Use timeouts**: For network protocols, implement timeouts for incomplete frames

---

## Performance Considerations

- **Zero-copy extraction**: Frame payloads are extracted as `Data` slices when possible
- **Efficient buffering**: Buffer grows dynamically, no pre-allocation needed
- **Fast validation**: Length checks are O(1)
- **Minimal allocations**: Frame extraction reuses buffer space

---

## Security Considerations

- **Size limits**: Max frame size prevents memory exhaustion attacks
- **Buffer limits**: Max buffer size prevents buffer overflow attacks
- **Validation**: All lengths are validated before processing
- **Fail-fast**: Invalid frames are rejected immediately

