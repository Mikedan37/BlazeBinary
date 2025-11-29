# BlazeBinary: Architecture Overview

**Purpose**: This document provides a high-level overview of BlazeBinary's architecture, components, and data flow. For detailed specifications, see [Spec.md](Spec.md) and [FrameProtocol.md](FrameProtocol.md).

This document describes how BlazeBinary works at the system level, focusing on component interactions and design decisions.

## Components

BlazeBinary consists of four main components:

1. **BlazeBinaryEncoder**: Converts Swift values to binary format
2. **BlazeBinaryDecoder**: Converts binary format to Swift values
3. **BlazeFrameEncoder**: Wraps binary data in frames with length prefixes
4. **BlazeFrameParser**: Incrementally extracts frames from streaming data

### Component Responsibilities

#### BlazeBinaryEncoder

- Encodes Swift values to deterministic binary format
- Manages encoding state (accumulated binary data)
- Provides encoding methods for all supported types
- Ensures deterministic output (same input → same bytes)

#### BlazeBinaryDecoder

- Decodes binary format to Swift values
- Manages decoding state (input data, read offset)
- Validates all decoded data (bounds, lengths, formats)
- Throws specific errors for invalid data

#### BlazeFrameEncoder

- Wraps binary payloads in frames
- Adds 4-byte big-endian length prefix
- Validates frame size limits (5 MB maximum)
- Provides frame encoding for transport protocols

#### BlazeFrameParser

- Incrementally parses frames from streaming data
- Manages buffer state (accumulated data, frame boundaries)
- Validates frame length prefixes
- Returns complete frames or nil (need more data)

## Encoding Flow

```
┌──────────────┐
│  Swift Value │
│  (Input)     │
└──────┬───────┘
       │
       ▼
┌──────────────────┐
│ BlazeBinary      │
│ Encoder          │
│                  │
│ - Varint encode  │
│ - Fixed-width     │
│ - Length-prefix   │
│ - Array encode   │
└──────┬───────────┘
       │
       ▼
┌──────────────┐
│  Binary Data │
│  (Output)    │
└──────────────┘
```

### Encoding Process

1. **Create encoder**: `BlazeBinaryEncoder()`
2. **Encode values**: Call `encode()` methods for each value
3. **Get result**: Call `encodedData()` to get binary Data

### Encoding Types

- **Varints**: Integers encoded as LEB128 (with zigzag for signed)
- **Fixed-width**: UInt32, UInt64, Bool (little-endian)
- **Length-prefixed**: Data, String (varint length + payload)
- **Arrays**: Varint count + encoded elements
- **Custom types**: Via `BlazeBinaryEncodable` protocol

## Decoding Flow

```
┌──────────────┐
│  Binary Data │
│  (Input)     │
└──────┬───────┘
       │
       ▼
┌──────────────────┐
│ BlazeBinary      │
│ Decoder          │
│                  │
│ - Varint decode  │
│ - Fixed-width     │
│ - Length-prefix   │
│ - Array decode   │
│ - Validation     │
└──────┬───────────┘
       │
       ▼
┌──────────────┐
│  Swift Value │
│  (Output)    │
└──────────────┘
```

### Decoding Process

1. **Create decoder**: `BlazeBinaryDecoder(data:maxAllowedLength:)`
2. **Decode values**: Call `decode()` methods in same order as encoding
3. **Handle errors**: Catch `BlazeBinaryError` for invalid data

### Decoding Types

- **Varints**: Decoded with validation (max 10 bytes, shift limits)
- **Fixed-width**: UInt32, UInt64, Bool (little-endian, validated)
- **Length-prefixed**: Data, String (length validated, bounds checked)
- **Arrays**: Count validated, elements decoded individually
- **Custom types**: Via `BlazeBinaryDecodable` protocol

## Frame Parsing (Incremental Streaming)

```
┌─────────────────┐
│  Streaming Data │
│  (Chunks)       │
└────────┬────────┘
         │
         ▼
┌──────────────────┐
│ BlazeFrame       │
│ Parser           │
│                  │
│ - Buffer data    │
│ - Extract frames │
│ - Validate       │
└────────┬─────────┘
         │
         ▼
┌─────────────────┐
│  Complete Frames│
│  (Payloads)     │
└─────────────────┘
```

### Frame Parser State Machine

```
State 1: Waiting for Length Prefix
  Condition: buffer.count < 4
  Action: Return nil (need more data)

State 2: Waiting for Payload
  Condition: buffer.count >= 4 && buffer.count < 4 + length
  Action: Return nil (need more data)

State 3: Frame Complete
  Condition: buffer.count >= 4 + length
  Action: Extract payload, remove from buffer, return payload
```

### Frame Format

```
┌─────────────────────────────────────────┐
│              Frame Structure            │
├─────────────────────────────────────────┤
│                                         │
│  ┌──────────────┐  ┌─────────────────┐ │
│  │ Length Prefix│  │  Payload        │ │
│  │ (4 bytes BE) │  │  (BlazeBinary)  │ │
│  └──────────────┘  └─────────────────┘ │
│                                         │
│  Total: 4 + payload.length bytes       │
│                                         │
└─────────────────────────────────────────┘
```

### Incremental Parsing

1. **Append data**: `parser.append(chunk)` - adds data to buffer
2. **Extract frames**: `parser.nextFrame()` - returns complete frame or nil
3. **Repeat**: Continue appending and extracting until no more frames

### Partial Frame Handling

When a frame is incomplete:
- `nextFrame()` returns `nil` (not an error)
- Parser state remains valid
- More data can be appended via `append()`
- Frame extraction resumes when complete

## Why Deterministic Binary Formats Aid Performance

### Predictable Layout

Deterministic encoding produces predictable byte layouts:
- Field positions are known
- Lengths are encoded before data
- No variable metadata to parse

### Efficient Parsing

- **Linear parsing**: Decoder reads sequentially, no backtracking
- **No lookahead**: Each field can be decoded immediately
- **Minimal state**: Decoder only tracks offset, no complex state machine

### Cache Efficiency

- **Deterministic hashing**: Same values produce same bytes, enabling content-addressable storage
- **Deduplication**: Identical values can be deduplicated efficiently
- **Comparison**: Encoded data can be compared byte-for-byte

### Memory Efficiency

- **Zero-copy decoding**: Data fields can be returned as slices
- **Bounded allocation**: Size limits prevent unbounded growth
- **No recursion**: Flat encoding avoids stack overhead

### Network Efficiency

- **Compact encoding**: Varints use fewer bytes for small values
- **No padding**: Fixed-width types use exact byte counts
- **Frame boundaries**: Clear frame boundaries aid streaming

## Component Interaction Diagram

```
┌─────────────────────────────────────────────────────────┐
│                  BlazeBinary System                     │
├─────────────────────────────────────────────────────────┤
│                                                         │
│  Encoding Path:                                         │
│    Swift Value                                          │
│         │                                               │
│         ▼                                               │
│    BlazeBinaryEncoder                                   │
│         │                                               │
│         ▼                                               │
│    Binary Data                                          │
│         │                                               │
│         ▼                                               │
│    BlazeFrameEncoder (optional)                         │
│         │                                               │
│         ▼                                               │
│    Framed Data                                          │
│                                                         │
│  Decoding Path:                                         │
│    Framed Data (optional)                              │
│         │                                               │
│         ▼                                               │
│    BlazeFrameParser                                     │
│         │                                               │
│         ▼                                               │
│    Binary Data                                          │
│         │                                               │
│         ▼                                               │
│    BlazeBinaryDecoder                                   │
│         │                                               │
│         ▼                                               │
│    Swift Value                                          │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

## Data Flow Example

### Complete Encoding/Decoding Cycle

```
1. Encode Swift value:
   encoder = BlazeBinaryEncoder()
   encoder.encode(42)
   encoder.encode("Hello")
   binaryData = encoder.encodedData()

2. Optionally wrap in frame:
   frame = BlazeFrameEncoder.encodeFrame(binaryData)

3. Stream frame (simulated):
   parser = BlazeFrameParser()
   parser.append(frame)
   payload = parser.nextFrame()

4. Decode binary data:
   decoder = BlazeBinaryDecoder(data: payload)
   value1 = decoder.decodeInt()      // 42
   value2 = decoder.decodeString()   // "Hello"
```

## Protocol Support

### BlazeBinaryEncodable

Types implement `blazeEncode(to:)` to define encoding:
- Control field order
- Encode nested structures
- Handle custom types

### BlazeBinaryDecodable

Types implement `init(from:)` to define decoding:
- Decode fields in same order as encoding
- Handle schema evolution
- Validate decoded data

### BlazeBinaryCodable

Convenience typealias for types that are both encodable and decodable.

## Summary

BlazeBinary's architecture provides:

1. **Simple components**: Four focused components with clear responsibilities
2. **Linear flow**: Encoding and decoding follow straightforward paths
3. **Incremental parsing**: Frame parser supports streaming use cases
4. **Deterministic encoding**: Predictable byte layouts aid performance
5. **Type safety**: Protocol-based design ensures compile-time safety
6. **Validation**: Decoder validates all data before use

This architecture makes BlazeBinary suitable for production use in systems requiring reliable, efficient, and secure binary serialization.

