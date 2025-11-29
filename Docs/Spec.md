# BlazeBinary Specification

This document provides a complete specification of the BlazeBinary encoding format.

## Table of Contents

1. [Varint Encoding (LEB128)](#varint-encoding-leb128)
2. [Zigzag Encoding](#zigzag-encoding)
3. [Fixed-Width Encoding](#fixed-width-encoding)
4. [Length-Prefixed Encoding](#length-prefixed-encoding)
5. [Zero-Copy Requirements](#zero-copy-requirements)
6. [Maximum Allowed Sizes](#maximum-allowed-sizes)

---

## Varint Encoding (LEB128)

Varints use LEB128 (Little-Endian Base 128) encoding. Each byte contains 7 bits of data and 1 continuation bit.

### Encoding Rules

1. Extract the lower 7 bits of the value
2. If there are more bits to encode, set the continuation bit (bit 7) to 1
3. Append the byte to the output
4. Right-shift the value by 7 bits
5. Repeat until all bits are encoded

### Decoding Rules

1. Read bytes until a byte with continuation bit = 0 is found
2. Extract the 7 data bits from each byte
3. Combine bits using left-shift: `result |= (byte & 0x7F) << (7 * byteIndex)`
4. Maximum of 10 bytes for 64-bit values

### Examples

```
Value: 0
Encoded: [0x00]

Value: 127
Encoded: [0x7F]

Value: 128
Encoded: [0x80, 0x01]
  Byte 0: 0x80 = 0b10000000 (continuation bit = 1, data = 0)
  Byte 1: 0x01 = 0b00000001 (continuation bit = 0, data = 1)
  Result: (0 & 0x7F) + ((1 & 0x7F) << 7) = 0 + (1 << 7) = 128 ✓

Value: 300
Encoded: [0xAC, 0x02]
  Byte 0: 0xAC = 172, but 172 & 0x7F = 44
  Byte 1: 0x02 = 2
  Result: 44 + (2 << 7) = 44 + 256 = 300 ✓
```

### Validation

- Maximum 10 bytes for 64-bit varints
- Continuation bit must be 0 on the last byte
- Shift must not exceed 63 bits (overflow protection)

---

## Zigzag Encoding

Signed integers (`Int`) are encoded using zigzag encoding before varint encoding. This maps signed integers to unsigned integers, ensuring efficient varint encoding for negative values.

### Encoding Formula

```
zigzag = (value << 1) ^ (value >> 63)
```

Where:
- `value << 1`: Left shift by 1 (multiply by 2)
- `value >> 63`: Arithmetic right shift (sign extension)
- `^`: XOR operation

### Decoding Formula

```
value = (zigzag >> 1) ^ (-(zigzag & 1))
```

Where:
- `zigzag >> 1`: Right shift by 1 (divide by 2)
- `zigzag & 1`: Extract least significant bit
- `-(zigzag & 1)`: Negate (0 → 0, 1 → -1)
- `^`: XOR operation

### Mapping Table

| Signed Value | Zigzag Value | Varint Bytes | Notes |
|--------------|--------------|--------------|-------|
| 0            | 0            | [0x00]       | Zero maps to zero |
| 1            | 2            | [0x02]       | Positive values → even zigzag |
| -1           | 1            | [0x01]       | Negative values → odd zigzag |
| 2            | 4            | [0x04]       | |
| -2           | 3            | [0x03]       | |
| 127          | 254          | [0xFE, 0x01] | |
| -128         | 255          | [0xFF, 0x01] | |
| Int.max      | UInt64.max-1 | 10 bytes     | Maximum signed value |
| Int.min      | UInt64.max   | 10 bytes     | Minimum signed value |

### Implementation Details

- Zigzag encoding is a bijection: every signed integer maps to a unique unsigned integer
- Encoding and decoding are mathematically reversible
- The formula works for all 64-bit signed integers
- After zigzag encoding, the value is encoded as a standard LEB128 varint

---

## Fixed-Width Encoding

### UInt32

- **Size**: 4 bytes
- **Endianness**: Little-endian
- **Format**: `[LSB, ..., MSB]`

Example: `0x12345678` → `[0x78, 0x56, 0x34, 0x12]`

### UInt64

- **Size**: 8 bytes
- **Endianness**: Little-endian
- **Format**: `[LSB, ..., MSB]`

Example: `0x0123456789ABCDEF` → `[0xEF, 0xCD, 0xAB, 0x89, 0x67, 0x45, 0x23, 0x01]`

### Bool

- **Size**: 1 byte
- **Values**: `0x00` (false), `0x01` (true)
- **Invalid**: Any other value causes decode error

---

## Length-Prefixed Encoding

### Data

Format: `<varint length> <bytes>`

```
Length: varint (LEB128)
Payload: N bytes where N = length
```

### String

Format: `<varint byteCount> <utf8 bytes>`

1. Convert string to UTF-8 bytes
2. Encode byte count as varint
3. Append UTF-8 bytes

**Validation**: UTF-8 must be valid, or decode fails.

### Arrays

Format: `<varint count> <item1> <item2> ... <itemN>`

Each item is encoded according to its `BlazeBinaryEncodable` implementation.

---

## Zero-Copy Requirements

### Data Decoding

When decoding `Data` values:

1. **Preferred**: Return a `Data` slice that references the original buffer
2. **Fallback**: Copy if slice is not possible (implementation-dependent)

**Implementation Note**: `Data.subdata(in:)` in Swift creates a slice that may or may not share the underlying buffer depending on the Swift version and Data implementation. The API documents this as "zero-copy when possible."

### String Decoding

Strings are always copied (UTF-8 decoding requires allocation). However, the underlying UTF-8 bytes may be accessed via zero-copy if the String implementation supports it.

### Verification

To verify zero-copy behavior:

```swift
let original = Data([...])
let decoded = try decoder.decodeData()

// If zero-copy, modifying the original buffer (if mutable)
// may affect decoded (implementation-dependent)
```

**Note**: In practice, `Data` in Swift is value-typed and immutable, so true zero-copy sharing is limited. The API provides `decodeDataZeroCopy()` as an explicit zero-copy variant.

---

## Maximum Allowed Sizes

### Variable-Length Fields

- **Default Maximum**: 10 MB (10,485,760 bytes)
- **Configurable**: Via `BlazeBinaryDecoder.init(maxAllowedLength:)`
- **Applies To**: Data, String, Array counts

### Frame Limits

- **Max Frame Size**: 5 MB (5,242,880 bytes)
- **Max Buffer Size**: 10 MB (10,485,760 bytes)
- **Enforced By**: `BlazeFrameEncoder` and `BlazeFrameParser`

### Validation

All length prefixes are validated:

1. Varint length must decode successfully
2. Length must not exceed `maxAllowedLength`
3. Sufficient bytes must be available (bounds checking)
4. Frame lengths must be > 0 and <= maxFrameSize

### Error Cases

- **Oversized Data**: `BlazeBinaryError.decodeFailed("Data length X exceeds maximum allowed Y")`
- **Oversized Frame**: `BlazeBinaryError.oversizedFrame`
- **Invalid Frame Length**: `BlazeBinaryError.invalidFrameLength`
- **Truncated Data**: `BlazeBinaryError.truncated`

---

## Deterministic Encoding

### Field Order

Fields MUST be encoded in the order specified by `blazeEncode(to:)`. The decoder MUST decode in the exact same order.

### No Metadata

BlazeBinary does not encode:
- Field names
- Type information
- Version numbers
- Schema metadata

All structure is implicit in the encoding order.

### Round-Trip Guarantee

For any value `v` of type `T: BlazeBinaryCodable`:

```swift
let encoder = BlazeBinaryEncoder()
try encoder.encode(v)
let data = encoder.encodedData()

let decoder = BlazeBinaryDecoder(data: data)
let decoded = try decoder.decode(T.self)

// decoded == v (value equality)
```

---

## Frame Format

See [FrameProtocol.md](./FrameProtocol.md) for complete frame specification.

### Quick Reference

- **Length Prefix**: 4 bytes, big-endian UInt32
- **Payload**: BlazeBinary-encoded data
- **Total**: 4 + payload.length bytes

---

## Implementation Notes

### Bounds Checking

All decode operations perform strict bounds checking:

```swift
guard offset + requiredBytes <= data.count else {
    throw BlazeBinaryError.truncated
}
```

### Error Handling

- Errors are thrown immediately (fail-fast)
- No partial decoding on error
- All errors are `BlazeBinaryError` enum cases

### Performance

- Hot paths are marked `@inlinable`
- Zero-copy where possible
- Minimal allocations
- O(1) for fixed-width types
- O(log n) for varints
- O(n) for length-prefixed types

---

## Version History

- **v1.0**: Initial specification
  - Varint encoding
  - Zigzag encoding
  - Fixed-width little-endian
  - Length-prefixed encoding
  - Frame format
  - Zero-copy support

