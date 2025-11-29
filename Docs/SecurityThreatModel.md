# BlazeBinary: Security & Threat Model

**Purpose**: This document describes the security properties of BlazeBinary and the threat model it addresses. It focuses exclusively on the binary codec layer.

For related documentation, see:
- [Spec.md](Spec.md) - Encoding format specification
- [ProductionSafetyProfile.md](ProductionSafetyProfile.md) - Safety guarantees
- [FaultToleranceChecklist.md](FaultToleranceChecklist.md) - Engineering checklist

This document explains why BlazeBinary is safe for processing untrusted binary data.

## Attack Surface

BlazeBinary's attack surface is limited to the binary codec layer:

- **Input**: Binary data (Data type in Swift)
- **Output**: Decoded Swift values or encoding errors
- **No network layer**: BlazeBinary does not handle network protocols, sockets, or transport layers
- **No application logic**: BlazeBinary does not execute application code or interpret decoded values

The only entry point for untrusted data is through:
- `BlazeBinaryDecoder.init(data:maxAllowedLength:)`
- `BlazeFrameParser.append(_:)`

## Protection Against Over-Reads

### Problem

An over-read occurs when a decoder reads beyond the bounds of the input buffer, potentially accessing memory that should not be accessible.

### BlazeBinary Protection

1. **Bounds checking before every read**: The `ensureBytes(_:)` method verifies `offset + count <= data.count` before any read operation.

2. **Fixed-width reads**: UInt32 and UInt64 reads are exactly 4 and 8 bytes respectively. The bounds check ensures these bytes exist before reading.

3. **Varint bounds**: Varint decoding checks bounds before each byte read. The maximum varint size (10 bytes) is known, allowing pre-validation.

4. **Length-prefixed bounds**: After decoding a length prefix, the decoder verifies `offset + length <= data.count` before reading the payload.

### Guarantee

No read operation can access memory beyond the input buffer. All reads are validated before execution.

## Protection Against Buffer Overruns

### Problem

A buffer overrun occurs when data is written beyond the allocated buffer, potentially corrupting adjacent memory.

### BlazeBinary Protection

1. **No writes to input**: The decoder never writes to the input buffer. It is read-only.

2. **Encoder allocation**: The encoder uses Swift's `Data` type which manages its own memory. Appends are handled by Swift's memory management.

3. **Frame parser buffer**: The frame parser uses `Data` which grows dynamically but is bounded by `maxBufferSize` (10 MB). Appends beyond this limit are rejected.

4. **No manual memory management**: BlazeBinary uses Swift's safe memory model. No unsafe pointers are used for writes.

### Guarantee

No buffer overruns can occur. All memory writes are managed by Swift's type system and bounds checking.

## Protection Against Malformed Lengths

### Problem

Malformed length prefixes can cause the decoder to allocate excessive memory or read beyond buffer bounds.

### BlazeBinary Protection

1. **Varint validation**: Length prefixes are decoded as varints with full varint validation (max 10 bytes, shift overflow protection).

2. **Maximum length check**: All decoded lengths are compared against `maxAllowedLength` (default 10 MB). Lengths exceeding this limit are rejected.

3. **Bounds validation**: After length validation, the decoder verifies that sufficient data exists: `offset + length <= data.count`.

4. **Non-negative guarantee**: Lengths are decoded as UInt64, ensuring they are always non-negative. Negative lengths are impossible.

5. **Frame length validation**: Frame length prefixes are validated to be > 0 and <= maxFrameSize (5 MB).

### Guarantee

No malformed length can cause unbounded allocation or over-read. All lengths are validated before use.

## Protection Against Varint Poisoning

### Problem

Malformed varints can cause:
- Integer overflow
- Infinite loops
- Excessive memory allocation
- Buffer over-reads

### BlazeBinary Protection

1. **Byte limit**: Varints are limited to 10 bytes maximum. If 10 bytes are read without termination, `BlazeBinaryError.invalidVarint` is thrown.

2. **Shift overflow protection**: The bit shift accumulator is checked to prevent exceeding 63 bits. If `shift >= 64`, decoding stops with an error.

3. **Continuation bit validation**: The last byte must have continuation bit = 0. Intermediate bytes must have continuation bit = 1. Invalid patterns are detected.

4. **Bounds checking**: Each byte read is validated against available data. Truncated varints are detected.

5. **Mathematical correctness**: The varint decoding algorithm is mathematically sound. Valid varints always decode correctly.

### Guarantee

No varint poisoning can cause security issues. All varints are validated before decoding completes.

## Protection Against Negative Lengths

### Problem

Negative lengths could cause:
- Integer underflow
- Buffer under-reads
- Memory corruption
- Undefined behavior

### BlazeBinary Protection

1. **UInt64 encoding**: Lengths are encoded and decoded as UInt64, which is inherently non-negative.

2. **No signed length types**: BlazeBinary never uses signed integers for lengths. All length operations use unsigned types.

3. **Type system guarantee**: Swift's type system prevents negative values from being assigned to UInt64.

### Guarantee

Negative lengths are impossible. The type system and encoding format prevent negative length values.

## Protection Against Integer Overflow

### Problem

Integer overflow can cause:
- Wraparound to small values
- Incorrect length calculations
- Buffer over-reads
- Memory corruption

### BlazeBinary Protection

1. **Varint shift limit**: Varint decoding limits bit shifts to 63 bits maximum. Shifts beyond this are rejected.

2. **Length validation**: All lengths are validated against `maxAllowedLength` before use. This prevents overflow in length calculations.

3. **Bounds checking**: Bounds checks use addition that cannot overflow in practice due to length limits:
   - Maximum buffer: 10 MB
   - Maximum frame: 5 MB
   - These values are well below Int.max

4. **Type promotion**: Length calculations use Int for bounds checking, which is 64-bit on modern platforms, providing ample headroom.

### Guarantee

Integer overflow cannot cause security issues. All arithmetic is bounded and validated.

## No Dynamic Memory Allocation Beyond Data Buffers

### Guarantee

BlazeBinary's memory allocation is limited to:

1. **Encoder buffer**: Grows with encoded data, but controlled by application code (not untrusted input during encoding).

2. **Decoder input buffer**: Provided by caller. Decoder does not allocate for input.

3. **Frame parser buffer**: Bounded by `maxBufferSize` (10 MB). Cannot grow beyond this limit.

4. **Decoded values**: Swift's type system manages memory for decoded values. No manual allocation.

### Protection

- No unbounded allocation from untrusted input
- All allocations are bounded by size limits
- Swift's memory management provides safety guarantees

## No Parsing of Recursive Trees

### Guarantee

BlazeBinary does not support recursive or nested structures that could cause stack overflow:

1. **Flat encoding**: Structures are encoded as flat sequences of fields. No recursive encoding.

2. **Bounded depth**: While structures can contain other structures, the depth is limited by:
   - Application code (not untrusted input)
   - Stack depth limits (Swift runtime)
   - No recursive types in the encoding format

3. **No circular references**: The encoding format does not support circular references or back-references.

### Protection

- No stack overflow from deeply nested structures
- No infinite recursion
- Depth is controlled by application code, not untrusted input

## Comparison to JSON for Untrusted Payloads

### JSON Vulnerabilities (Not in BlazeBinary)

1. **Recursive parsing**: JSON parsers can parse deeply nested structures, causing stack overflow.

2. **Unbounded strings**: JSON strings have no inherent size limit, allowing memory exhaustion.

3. **Complex parsing**: JSON parsing involves state machines and recursive descent, increasing attack surface.

4. **Type coercion**: JSON's loose typing can lead to type confusion attacks.

5. **No size limits**: Standard JSON parsers do not enforce size limits by default.

### BlazeBinary Advantages

1. **Flat encoding**: No recursive parsing. Structures are flat sequences.

2. **Hard size limits**: All variable-length fields are limited to 10 MB. Frames limited to 5 MB.

3. **Simple parsing**: Linear parsing with minimal state. No recursive descent.

4. **Strong typing**: Decoded types are determined by application code, not input data.

5. **Built-in limits**: Size limits are enforced by default, not optional.

### Security Improvement

BlazeBinary is safer than JSON for untrusted payloads because:
- Smaller attack surface (flat encoding, no recursion)
- Hard size limits prevent memory exhaustion
- Strong typing prevents type confusion
- Simple parsing reduces bug surface area

## Streaming Parser Denial-of-Service Prevention

### Problem

A malicious sender could send a frame with a large length prefix but never send the payload, causing the receiver to wait indefinitely or allocate excessive memory.

### BlazeBinary Protection

1. **Partial frame handling**: `BlazeFrameParser.nextFrame()` returns `nil` when a frame is incomplete. The parser does not block or allocate for incomplete frames.

2. **Buffer limit**: The parser buffer is limited to 10 MB. If a sender sends many incomplete frames, the buffer limit is reached and `BlazeBinaryError.oversizedFrame` is thrown.

3. **No blocking**: The parser never blocks waiting for data. It returns `nil` immediately if more data is needed.

4. **State machine**: The parser uses a simple state machine:
   - Need 4 bytes for length prefix
   - Need N bytes for payload (where N is from length prefix)
   - Only returns frame when complete

### Guarantee

Streaming parser cannot be used for denial-of-service. Incomplete frames do not cause blocking or unbounded allocation.

## Incremental "needMoreData" State Machine Protection

### State Machine

The frame parser uses a three-state machine:

1. **Waiting for length prefix**: `buffer.count < 4`
   - Action: Return `nil`
   - Protection: No processing of incomplete data

2. **Waiting for payload**: `buffer.count >= 4 && buffer.count < 4 + length`
   - Action: Return `nil`
   - Protection: No extraction of partial payloads

3. **Frame complete**: `buffer.count >= 4 + length`
   - Action: Extract payload and return it
   - Protection: Only complete frames are returned

### Protection Against Partial Reads

1. **Atomic frame extraction**: Frames are only extracted when complete. No partial frames are returned.

2. **Length validation before extraction**: The length prefix is validated before any payload extraction.

3. **Bounds checking**: The complete frame size is verified before extraction.

4. **No state corruption**: Returning `nil` does not modify parser state. The parser can continue when more data arrives.

### Guarantee

The state machine ensures that:
- Partial frames are never returned
- Frame boundaries are respected
- Parser state remains consistent
- No data is lost or corrupted

## Summary

BlazeBinary provides security through:

1. **Bounds checking** preventing over-reads
2. **Size limits** preventing memory exhaustion
3. **Varint validation** preventing poisoning attacks
4. **Type safety** preventing negative lengths and overflow
5. **Bounded allocation** preventing denial-of-service
6. **Flat encoding** preventing recursive attacks
7. **State machine** preventing partial read issues

These protections make BlazeBinary suitable for processing untrusted binary data in production systems.

