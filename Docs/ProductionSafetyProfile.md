# BlazeBinary: Production Safety Profile

**Purpose**: This document describes the safety guarantees, validation mechanisms, and error handling in BlazeBinary. It provides a complete safety profile for production deployment.

For related documentation, see:
- [Spec.md](Spec.md) - Encoding format specification
- [SecurityThreatModel.md](SecurityThreatModel.md) - Security analysis
- [FaultToleranceChecklist.md](FaultToleranceChecklist.md) - Engineering checklist

This document explains what safety guarantees BlazeBinary provides and how they are enforced.

## Deterministic Encoding

### Guarantee

BlazeBinary provides deterministic encoding: identical input values always produce identical byte sequences. This property is critical for:

- Cryptographic hashing of encoded data
- Content-addressable storage systems
- Deterministic testing and validation
- Reproducible serialization

### Implementation

Determinism is achieved through:

1. **Fixed encoding order**: Fields are encoded in the exact order specified by `blazeEncode(to:)`. No reflection or dynamic field ordering.

2. **No metadata**: BlazeBinary does not encode field names, type information, timestamps, or any other variable metadata that could cause non-deterministic output.

3. **Fixed-width primitives**: UInt32, UInt64, and Bool use fixed-width little-endian encoding with no padding or alignment variations.

4. **Deterministic varint encoding**: LEB128 varint encoding produces the same byte sequence for the same integer value across all invocations.

5. **Zigzag encoding**: Signed integers use deterministic zigzag encoding before varint encoding, ensuring consistent representation.

### Byte Layout Guarantee

For any value `v` of type `T: BlazeBinaryCodable`:

```
encode(v) == encode(v)  (always true)
```

This guarantee holds regardless of:
- Execution environment
- Swift version (within compatibility range)
- Platform endianness (encoding uses explicit little-endian)
- Memory layout
- Compiler optimizations

## Length-Prefix and Varint Validation

### Varint Validation

Varints (LEB128 encoding) are validated with strict rules:

1. **Maximum byte limit**: A varint cannot exceed 10 bytes. If 10 bytes are read without a termination byte (continuation bit = 0), `BlazeBinaryError.invalidVarint` is thrown.

2. **Shift overflow protection**: The bit shift accumulator is checked to prevent exceeding 63 bits (for 64-bit integers). If shift >= 64, `BlazeBinaryError.invalidVarint` is thrown.

3. **Continuation bit validation**: The last byte of a varint must have its continuation bit (bit 7) set to 0. Intermediate bytes must have it set to 1.

4. **Bounds checking**: Each byte read is validated against the available data. If insufficient bytes are available, `BlazeBinaryError.truncated` is thrown.

### Length-Prefix Validation

Length prefixes (used for Data, String, and arrays) are validated as follows:

1. **Varint decoding**: The length is decoded as a varint with all varint validation rules applied.

2. **Maximum length check**: The decoded length is compared against `maxAllowedLength` (default: 10 MB). If exceeded, `BlazeBinaryError.decodeFailed` is thrown with a descriptive message.

3. **Bounds checking**: After length validation, the decoder verifies that `offset + length <= data.count`. If not, `BlazeBinaryError.truncated` is thrown.

4. **Non-negative requirement**: Lengths are decoded as UInt64, ensuring they are always non-negative. Negative lengths cannot occur.

## Strict Size Limits

### Frame Limits

- **Maximum frame size**: 5 MB (5,242,880 bytes)
- **Maximum buffer size**: 10 MB (10,485,760 bytes)

These limits are enforced at multiple levels:

1. **Frame encoding**: `BlazeFrameEncoder.encodeFrame()` validates payload size before encoding. If payload exceeds 5 MB, `BlazeBinaryError.oversizedFrame` is thrown.

2. **Frame parsing**: `BlazeFrameParser.nextFrame()` validates the length prefix. If the declared length exceeds `maxFrameSize`, `BlazeBinaryError.invalidFrameLength` is thrown.

3. **Buffer management**: `BlazeFrameParser.append()` checks buffer size after each append. If buffer exceeds 10 MB, `BlazeBinaryError.oversizedFrame` is thrown.

### Variable-Length Field Limits

- **Default maximum**: 10 MB (10,485,760 bytes)
- **Configurable**: Via `BlazeBinaryDecoder.init(maxAllowedLength:)`

This limit applies to:
- Data fields
- String fields (UTF-8 byte count)
- Array element counts

## Error Handling

### BlazeBinaryError Cases

#### truncated

**When thrown**: Insufficient data is available to complete a decode operation.

**Examples**:
- Reading a UInt32 when only 2 bytes remain
- Decoding a varint that is incomplete
- Reading a Data field where the payload is shorter than the declared length

**Safety guarantee**: No partial data is returned. The decoder state remains consistent.

#### invalidVarint

**When thrown**: A varint encoding is malformed.

**Examples**:
- More than 10 bytes read without termination
- Bit shift overflow (shift >= 64)
- Invalid continuation bit pattern

**Safety guarantee**: Decoder stops immediately. No state corruption occurs.

#### invalidFrameLength

**When thrown**: A frame length prefix is invalid.

**Examples**:
- Length prefix is 0
- Length prefix exceeds maxFrameSize (5 MB)
- Length prefix would cause buffer overflow

**Safety guarantee**: Frame parser rejects the frame. Buffer state remains valid.

#### oversizedFrame

**When thrown**: A frame or buffer exceeds size limits.

**Examples**:
- Frame payload exceeds 5 MB during encoding
- Buffer exceeds 10 MB during append
- Variable-length field exceeds maxAllowedLength

**Safety guarantee**: Operation is rejected before any allocation or processing occurs.

#### decodeFailed(String)

**When thrown**: A decoding operation fails for a specific reason.

**Examples**:
- Invalid UTF-8 sequence in String decoding
- Data length exceeds maxAllowedLength
- Array count exceeds maxAllowedLength
- Invalid Bool value (not 0x00 or 0x01)

**Safety guarantee**: Error message provides diagnostic information. Decoder state is consistent.

#### needMoreData

**When thrown**: Used internally by frame parser to indicate partial frame state.

**Safety guarantee**: This is an internal state indicator, not a user-facing error in normal operation.

## Handling of Malformed Data

### Oversized Frames

**Detection**: Frame length prefix validation in `BlazeFrameParser.nextFrame()`.

**Response**: `BlazeBinaryError.invalidFrameLength` is thrown immediately upon reading the length prefix.

**Protection**: Prevents memory exhaustion attacks. No allocation occurs for oversized frames.

### Truncated Frames

**Detection**: Bounds checking in `nextFrame()` after reading length prefix.

**Response**: `nextFrame()` returns `nil` (not an error). The parser waits for more data via `append()`.

**Protection**: Prevents partial frame processing. State machine ensures frames are only returned when complete.

### Invalid Varints

**Detection**: Multiple validation checks in `decodeVarint()`:
- Byte count limit (10 bytes)
- Shift overflow (>= 64 bits)
- Continuation bit validation

**Response**: `BlazeBinaryError.invalidVarint` is thrown.

**Protection**: Prevents integer overflow and infinite loops. Decoder stops immediately.

### Invalid ZigZag Integers

**Detection**: ZigZag decoding is mathematically reversible. Invalid encodings are detected during varint validation (the underlying varint must be valid).

**Response**: If the varint is valid, ZigZag decoding always succeeds. Invalid varints are caught by varint validation.

**Protection**: ZigZag encoding is a bijection. All valid varints decode to valid integers.

### Malformed Arrays

**Detection**: Array decoding validates:
1. Count varint (with varint validation)
2. Count against maxAllowedLength
3. Bounds for each element decode

**Response**: 
- Invalid count varint: `BlazeBinaryError.invalidVarint`
- Count too large: `BlazeBinaryError.decodeFailed`
- Truncated element: `BlazeBinaryError.truncated`

**Protection**: Prevents allocation of oversized arrays. Each element is validated individually.

### Invalid String Lengths

**Detection**: String decoding validates:
1. Length varint (with varint validation)
2. Length against maxAllowedLength
3. UTF-8 validity of decoded bytes

**Response**:
- Invalid length varint: `BlazeBinaryError.invalidVarint`
- Length too large: `BlazeBinaryError.decodeFailed`
- Invalid UTF-8: `BlazeBinaryError.decodeFailed("Invalid UTF-8 encoding")`

**Protection**: Prevents allocation of oversized strings. UTF-8 validation prevents malformed string creation.

## Why Deterministic Byte Layout Matters

### Correctness Guarantees

1. **Hash consistency**: Encoded data can be hashed deterministically. Same input always produces same hash.

2. **Content addressing**: Encoded values can be used as content-addressable keys. Identical values map to identical keys.

3. **Testing**: Round-trip tests are deterministic. Encoded data can be stored in test fixtures and compared byte-for-byte.

4. **Versioning**: Schema evolution can be tested by encoding with old schema and decoding with new schema, with predictable results.

5. **Debugging**: Encoded data can be inspected and compared across runs. Non-determinism would make debugging impossible.

### Performance Implications

1. **Caching**: Encoded data can be cached based on input values. Determinism ensures cache hits are correct.

2. **Deduplication**: Identical values produce identical encodings, enabling efficient deduplication.

3. **Comparison**: Encoded data can be compared byte-for-byte for equality, which is faster than decoding and comparing values.

## Bounds Checking Invariants

The following invariants are maintained throughout decoding:

1. **Offset bounds**: `0 <= offset <= data.count` (always true)

2. **Read bounds**: Before reading N bytes, `offset + N <= data.count` is verified.

3. **Length validation**: All length values are validated before use:
   - `length >= 0` (UInt64 ensures this)
   - `length <= maxAllowedLength`
   - `offset + length <= data.count`

4. **Frame bounds**: Frame parsing validates:
   - `buffer.count >= 4` (before reading length prefix)
   - `length > 0 && length <= maxFrameSize` (length validation)
   - `buffer.count >= 4 + length` (before extracting payload)

These invariants are checked at every decode operation. No operation proceeds without validation.

## Memory Safety

### Allocation Limits

1. **Frame buffers**: Maximum 10 MB per parser instance.

2. **Variable-length fields**: Maximum 10 MB per field (configurable).

3. **Arrays**: Element count limited by maxAllowedLength. Each element allocation is bounded.

### No Unbounded Growth

- Encoder: Grows with encoded data, but encoding is controlled by application code.
- Decoder: Reads from fixed-size input buffer. No dynamic growth.
- Frame parser: Buffer limited to 10 MB. Appends beyond limit are rejected.

### Zero-Copy Safety

Data decoding uses `Data.subdata()` which creates slices. These slices reference the original buffer, but Swift's value semantics ensure memory safety. The original buffer cannot be deallocated while slices exist.

## Summary

BlazeBinary provides production-grade safety through:

1. **Deterministic encoding** for correctness and reproducibility
2. **Strict validation** of all length prefixes and varints
3. **Hard size limits** preventing memory exhaustion
4. **Comprehensive error handling** with specific error types
5. **Bounds checking** at every decode operation
6. **Memory safety** through allocation limits and zero-copy semantics

These guarantees make BlazeBinary suitable for production use in systems requiring reliable, secure, and deterministic binary serialization.

