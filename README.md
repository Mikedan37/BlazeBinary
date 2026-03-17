# BlazeBinary

A deterministic, Swift-native binary encoding format with optional encryption and compression. **Transport-agnostic** — works with any byte stream (TCP, Unix sockets, files, shared memory).

## Features

- **Deterministic encoding** (same input → same bytes, on the same platform)
- **Compact binary representation** (varint integers, no field names in the wire format)
- **Optional compression**: LZ4 / LZFSE
- **Built-in encryption**: X25519 key exchange + ChaCha20-Poly1305 AEAD
- **Frame builder/parser** for length-delimited transport
- **One dependency**: `apple/swift-crypto`

## Example

Types conform to `BlazeBinaryCodable` by defining how their fields are written and read:

```swift
struct Message: BlazeBinaryCodable {
    let text: String
    let count: Int

    func blazeEncode(to encoder: BlazeBinaryEncoder) throws {
        encoder.encode(text)
        encoder.encode(count)
    }

    init(from decoder: BlazeBinaryDecoder) throws {
        text = try decoder.decode(String.self)
        count = try decoder.decode(Int.self)
    }
}

// Encode
let encoder = BlazeBinaryEncoder()
try encoder.encode(Message(text: "Hello", count: 42))
let bytes = encoder.encodedData()  // compact binary, no field names

// Decode
let decoder = BlazeBinaryDecoder(data: bytes)
let message = try decoder.decode(Message.self)
```

Or use the convenience helpers:

```swift
let bytes = try serializeMessage(Message(text: "Hello", count: 42))
let message = try deserializeMessage(bytes, as: Message.self)
```

## Installing

```swift
.package(url: "https://github.com/<your-user>/BlazeBinary.git", from: "0.1.0")
```

## Benchmarks

Microbenchmarks on Apple Silicon (M4 Max, release mode):

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
swift run -c release BlazeBinaryBenchmarks
```

## Tests

```bash
swift test
```

42 test files covering encoding, decoding, round-trips, determinism, framing, compression, encryption, key exchange, and handshake state machines. Plus fuzz tests.

## Transport-Agnostic Design

BlazeBinary provides encoding/decoding, framing, and optional encryption. You provide the transport layer — TCP, UDP, Unix sockets, shared memory, files, or anything else that moves bytes.

## Status

BlazeBinary is an exploration of building a binary protocol from scratch in Swift. It works, it's tested, and it's used in personal projects. It has not been audited by a third-party security firm.

## License

MIT
