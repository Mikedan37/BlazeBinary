# BlazeBinary

A deterministic, zero-copy, Swift-native binary encoding format with optional encryption and compression. **Transport-agnostic** - works with any byte stream (TCP, UDP, IPC, shared memory, files, etc.).

## Features

- **Deterministic encoding** (same input → same bytes)
- **Zero-copy decoding** for high performance
- **Compact binary representation**
- **Codable support** (typed serialization)
- **Varint encoding** for integers
- **Optional compression**: LZ4 / LZFSE
- **Built-in encryption**:
  - X25519 key exchange
  - ChaCha20-Poly1305 AEAD
- **Frame builder/parser utilities**
- **High-performance**: 1–3M ops/sec on Apple Silicon

## Example

```swift
struct Message: Codable {
    let text: String
    let count: Int
}

let encoded = try BlazeBinary.encode(Message(text: "Hello", count: 42))
let decoded = try BlazeBinary.decode(encoded, as: Message.self)
```

## Installing

```swift
.package(url: "https://github.com/<your-user>/BlazeBinary.git", from: "0.1.0")
```

## Benchmarks

We provide microbenchmarks only (no transport benchmarks):

| Operation | Throughput |
|-----------|------------|
| Varint Encode | ~2.5M ops/sec |
| Varint Decode | ~2.8M ops/sec |
| Codable Encode | ~1.8M ops/sec |
| Codable Decode | ~2.0M ops/sec |
| AEAD Encrypt | ~45K ops/sec |
| AEAD Decrypt | ~50K ops/sec |

Run with:

```bash
swift run BlazeBinaryBenchmarks
```

## Tests

- Deterministic encoding tests
- Round-trip Codable tests
- AEAD encryption tests
- X25519 exchange tests
- Frame parser tests

## Transport-Agnostic Design

BlazeBinary is **transport-agnostic**. It provides encoding/decoding, framing, and optional encryption. You provide the transport layer:

- Works with **any byte stream**: TCP, UDP, Unix sockets, shared memory, files, custom transports
- No networking code in BlazeBinary
- Frame format is transport-independent
- Use with your preferred transport protocol

## Status

BlazeBinary is stable and production-focused.

## License

MIT
