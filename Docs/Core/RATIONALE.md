# BlazeBinary

## Rationale

_Last updated: February 2025_

This document explains why BlazeBinary exists in the presence of established serialization formats like JSON, CBOR, MessagePack, and Protocol Buffers.

## Problem Space

### Overhead of JSON for Local-First & High-Throughput Systems

JSON is ubiquitous and human-readable, but it has significant overhead for performance-critical applications:

- **Text-based encoding**: Requires UTF-8 parsing and string conversion
- **Verbose representation**: Field names are repeated in every record
- **Non-deterministic**: Field order and formatting can vary between implementations
- **Large payload sizes**: 2-3x larger than binary formats for the same data
- **Slow parsing**: Text parsing is inherently slower than binary decoding

For local-first systems that need to:
- Store millions of records efficiently
- Transmit data over constrained networks
- Perform content-addressed storage (hashing)
- Achieve high throughput (millions of ops/sec)

JSON's overhead becomes a significant bottleneck.

### Need for Deterministic Encoding

Deterministic encoding (same input → same bytes) is critical for:

- **Content addressing**: Reliable hashing requires identical bytes for identical data
- **Deduplication**: Detecting duplicate records requires deterministic encoding
- **Testing**: Deterministic encoding enables reliable test comparisons
- **Signatures**: Cryptographic signatures require deterministic serialization
- **Version control**: Binary diffs and versioning systems benefit from determinism

Most existing formats (JSON, CBOR, MessagePack) do not guarantee determinism. Field order, floating-point representation, and optional features can produce different bytes for the same logical data.

### Need for Tight Integration with Swift Types

Swift applications need:

- **Zero code generation**: No external tools or build-time codegen
- **Protocol-based design**: Leverage Swift's type system
- **Type safety**: Compile-time checking, not runtime errors
- **Native Swift types**: Direct encoding of Swift structs, enums, arrays, dictionaries

While Protocol Buffers provides excellent cross-language support, it requires:
- Schema definition files (.proto)
- Code generation step
- External dependencies
- Runtime reflection or generated code

BlazeBinary provides a pure Swift implementation with no code generation, while maintaining cross-language compatibility at the binary format level.

## Design Goals vs Existing Formats

### Deterministic Output

**BlazeBinary**: Guaranteed deterministic encoding. Same input always produces identical bytes, regardless of:
- Field order in dictionaries (keys are sorted)
- Encoding order (fields are encoded in deterministic order)
- Platform endianness (uses little-endian consistently)
- Swift version (format is stable)

**JSON**: Non-deterministic. Field order, whitespace, and formatting can vary.

**CBOR**: Non-deterministic. Map key order is not guaranteed.

**MessagePack**: Non-deterministic. Map key order is not guaranteed.

**Protobuf**: Deterministic only if fields are encoded in field number order (not guaranteed by default).

### Compact Representation

**BlazeBinary**: Optimized for size:
- Varint encoding for small integers (1 byte for 0-127)
- Length-prefixed strings (no null terminators)
- No field names in binary (implicit type from encoding method)
- Efficient array/dictionary encoding

**JSON**: Verbose. Includes field names, quotes, commas, whitespace.

**CBOR**: Compact, similar to BlazeBinary.

**MessagePack**: Compact, similar to BlazeBinary.

**Protobuf**: Very compact, but requires schema.

### Simplicity of Decoder Implementation

**BlazeBinary**: Simple decoder:
- Single-pass parsing
- No schema required
- Clear error messages
- Bounded memory usage

**JSON**: Complex parsing (handles escape sequences, Unicode, etc.).

**CBOR**: Moderate complexity (tag system, indefinite-length items).

**MessagePack**: Simple, similar to BlazeBinary.

**Protobuf**: Requires schema for decoding (or wire format inspection).

### One-Pass Streaming-Friendly Decoding

**BlazeBinary**: Designed for streaming:
- Frame-based protocol with length prefixes
- Incremental frame parsing
- No need to buffer entire message
- Can decode fields as they arrive

**JSON**: Requires full document parsing (or complex streaming parser).

**CBOR**: Supports streaming but with complexity.

**MessagePack**: Supports streaming.

**Protobuf**: Supports streaming but requires schema.

### No Schema Requirement, but Structured Enough for Stability

**BlazeBinary**: No schema required, but:
- Type information is implicit in encoding
- Field order is deterministic
- Format is versioned and stable
- Can evolve schemas with `decodeIfPresent()` and `skipUnknownField()`

**JSON**: No schema, but also no type safety or versioning.

**CBOR**: No schema, but tags provide some structure.

**MessagePack**: No schema, minimal structure.

**Protobuf**: Requires schema, but provides strong versioning.

## Comparison Table

| Feature | JSON | CBOR | MessagePack | Protobuf | BlazeBinary |
|---------|------|------|-------------|----------|-------------|
| **Determinism** | No | No | No | Partial | Yes |
| **Text vs Binary** | Text | Binary | Binary | Binary | Binary |
| **Schema Required** | No | No | No | Yes | No |
| **Ease of Implementation** | Medium | Medium | Easy | Hard | Easy |
| **Size Efficiency** | Low | High | High | Very High | High |
| **Streaming Friendliness** | Low | Medium | High | High | High |
| **Type Safety** | No | Partial | No | Yes | Yes (Swift) |
| **Code Generation** | No | No | No | Yes | No |
| **Cross-Language** | Yes | Yes | Yes | Yes | Yes (format) |
| **Zero Dependencies** | Yes | Yes | Yes | No | Yes |

## Why New Instead of Extending Existing

### Tailored to Swift/Blaze Ecosystem

BlazeBinary is designed specifically for:
- Swift's type system and protocols
- The Blaze ecosystem (AgentKit, AgentDaemon, BlazeDB)
- Zero external dependencies
- Pure Swift implementation

Extending an existing format would require:
- Maintaining compatibility with other implementations
- Working around format limitations
- Adding Swift-specific features that don't fit the format

### Tighter Control Over Versioning

BlazeBinary provides:
- Explicit versioning in the format
- Controlled evolution path
- No breaking changes without version bumps
- Clear migration path for format changes

Extending existing formats means:
- Following their versioning model
- Potentially incompatible changes from upstream
- Less control over evolution

### Simpler Mental Model for Low-Level Storage

BlazeBinary's design is:
- Explicit and transparent
- Easy to inspect and debug
- Clear encoding rules
- Minimal magic

This simplicity is valuable for:
- Low-level storage systems (BlazeDB)
- Debugging and inspection
- Understanding performance characteristics
- Implementing in other languages

## Where BlazeBinary Fits in the Blaze Ecosystem

BlazeBinary is the **foundation layer** of the Blaze ecosystem:

1. **BlazeBinary** (this package) – Binary encoding format
2. **BlazeShared** – Protocol structs using BlazeBinary
3. **BlazeDB** – Database using BlazeBinary for storage
4. **AgentCore** – Semantic engine using BlazeBinary
5. **AgentKit** – Agent runtime using BlazeBinary
6. **AgentDaemon** – RPC server using BlazeBinary for transport

Every package in the ecosystem relies on BlazeBinary for:
- Deterministic serialization
- Compact storage
- Fast encoding/decoding
- Cross-version compatibility

## Design Philosophy

BlazeBinary is built on a set of core design principles that guide every implementation decision:

### Minimal Moving Parts

BlazeBinary avoids unnecessary complexity. The encoding format has:
- **No magic bytes**: Every byte has a clear purpose
- **No hidden metadata**: What you encode is what you get
- **No complex state machines**: Simple, linear encoding/decoding
- **No external dependencies**: Pure Swift, Foundation only

This simplicity makes the format:
- Easy to understand and debug
- Predictable in behavior
- Simple to implement in other languages
- Reliable under all conditions

### Predictability Under Load

BlazeBinary is designed to behave consistently regardless of load:

- **No surprise allocations**: Memory usage is predictable
- **No garbage collection pauses**: Swift's ARC provides deterministic cleanup
- **No hidden buffering**: All operations are explicit
- **Bounded memory usage**: Hard limits prevent unbounded growth

This predictability is critical for:
- High-throughput systems (millions of ops/sec)
- Real-time applications
- Resource-constrained environments
- Performance-critical code paths

### Determinism

Deterministic encoding (same input → same bytes) is a first-class requirement:

- **Field order independence**: Dictionary keys are sorted
- **Platform independence**: Little-endian encoding everywhere
- **Version stability**: Format changes require explicit versioning
- **Test reliability**: Deterministic encoding enables reliable test comparisons

Determinism enables:
- Content-addressed storage (reliable hashing)
- Deduplication (detecting duplicate records)
- Cryptographic signatures (deterministic serialization)
- Version control (binary diffs)

### Binary Transparency

BlazeBinary provides complete transparency:

- **No hidden allocations**: All memory operations are explicit
- **No magic numbers**: Every byte is documented
- **No implicit conversions**: Type handling is explicit
- **No hidden state**: Decoder state is explicit and inspectable

This transparency enables:
- Debugging and inspection
- Performance analysis
- Security auditing
- Cross-language implementation

### Explicit Over Implicit

BlazeBinary favors explicit operations:

- **Explicit encoding methods**: `encoder.encode(value)` not magic
- **Explicit type handling**: No implicit type coercion
- **Explicit error handling**: All errors are typed and documented
- **Explicit bounds checking**: All reads are validated

This explicitness provides:
- Type safety at compile time
- Clear error messages
- Predictable behavior
- Easy debugging

### Platform-First Approach

BlazeBinary is optimized for Apple platforms:

- **Apple Silicon optimization**: Leverages ARM64 efficiently
- **Swift-native**: Uses Swift's type system and protocols
- **Foundation integration**: Works seamlessly with Foundation types
- **Xcode tooling**: Full IDE support

While cross-platform compatible, the primary target is:
- macOS (Apple Silicon and Intel)
- iOS/iPadOS
- Swift-based server applications

### Memory Safety Through Explicit Byte Reading

BlazeBinary prevents alignment issues and buffer overflows:

- **Manual byte reading**: No unsafe pointer loads
- **Bounds checking**: All reads are validated
- **Size limits**: Hard limits prevent unbounded growth
- **Zero-copy where safe**: Returns slices when possible

This approach ensures:
- No misaligned pointer crashes
- No buffer overflows
- No use-after-free errors
- Safe operation on all platforms

### Favor Linear-Time Over "Clever" Abstractions

BlazeBinary prioritizes predictable performance:

- **Linear-time operations**: O(n) complexity, no hidden O(n²)
- **No complex algorithms**: Simple, straightforward code
- **No premature optimization**: Optimize only where measured
- **Clear performance characteristics**: Easy to reason about

This approach provides:
- Predictable performance
- Easy optimization
- Simple implementation
- Reliable behavior

## References

- [Benchmarks](BENCHMARKS.md) – Performance comparisons
- [Specification](SPECIFICATION_v1.3.md) – Formal format specification
- [Encoding Model](ENCODING_MODEL.md) – Encoding strategies and optimizations

---

## Canonical Text Format (Protocol v1.1)

BlazeBinary Protocol v1.1 introduces a canonical text formatter for debugging and inspection purposes.

### Purpose

The canonical text format provides a stable, human-readable representation of BlazeBinary-encoded data, useful for:

- **Debugging**: Inspect encoded data in a readable format
- **Testing**: Compare encoded data across runs
- **Documentation**: Show example encoded values
- **Development**: Understand encoding structure

### Characteristics

The canonical formatter ensures:

- **Sorted Keys**: Dictionary keys are sorted for stable output
- **Stable Numeric Formats**: Numbers use consistent formatting
- **Stable Unicode Escapes**: Unicode characters use consistent escape sequences
- **Deterministic Output**: Same input always produces same text representation

### Usage

```swift
import BlazeBinary

// Encode data
let encoder = BlazeBinaryEncoder()
encoder.encode("hello")
encoder.encode(42)
let data = encoder.encodedData()

// Convert to canonical text
let text = try CanonicalText.toCanonicalText(data)
print(text) // Stable text representation

// Or use extension method
struct MyRecord: BlazeBinaryCodable { ... }
let record = MyRecord(...)
let text = try record.toCanonicalText()
```

### Use Cases

1. **Test Assertions**: Compare canonical text instead of binary data
2. **Debug Logging**: Log encoded data in readable format
3. **Documentation**: Include canonical text examples in docs
4. **Development Tools**: CLI tools can output canonical text

### Limitations

- Developer-only utility (not for production serialization)
- Requires schema knowledge for complex types
- Performance overhead (not optimized for speed)

---

### Related Documents

- [Specification](SPECIFICATION_v1.3.md)
- [Encoding Model](ENCODING_MODEL.md)
- [Benchmarks](BENCHMARKS.md)
- [Architecture](ARCHITECTURE.md)
- [Cross-Language Decoder](CROSS_LANGUAGE_DECODER.md)

