# BlazeBinary API Stability Guarantee

_Last updated: February 2025 (Protocol v1.3)_

This document defines the API stability guarantees for BlazeBinary Protocol v1.3 and future versions.

## Stability Levels

### 🔒 Stable APIs (v1.3+)

These APIs are **frozen** and will not change in incompatible ways. Breaking changes will only occur in major version bumps (v2.0+).

#### Core Encoding/Decoding

- `BlazeBinaryEncoder` class
  - `init(schemaVersion:)`
  - `encodedData() -> Data`
  - `encode(_ value: Int)`
  - `encode(_ value: UInt32)`
  - `encode(_ value: UInt64)`
  - `encode(_ value: Bool)`
  - `encode(_ value: Double)`
  - `encode(_ value: Data)`
  - `encode(_ value: String)`
  - `encode<T: BlazeBinaryEncodable>(_ value: T) throws`
  - `encode<T: BlazeBinaryEncodable>(_ array: [T]) throws`
  - `encode<T: BlazeBinaryEncodable>(_ value: T?) throws`
  - `encodeCollection<T>(_ items: [T]) throws`

- `BlazeBinaryDecoder` class
  - `init(data:maxAllowedLength:)`
  - `version: UInt32`
  - `remainingData: Data`
  - `decodeInt() throws -> Int`
  - `decodeUInt32() throws -> UInt32`
  - `decodeUInt64() throws -> UInt64`
  - `decodeBool() throws -> Bool`
  - `decodeDouble() throws -> Double`
  - `decodeData() throws -> Data`
  - `decodeString() throws -> String`
  - `decode<T: BlazeBinaryDecodable>(_ type: T.Type) throws -> T`
  - `decodeArray<T>(_ type: T.Type) throws -> [T]`
  - `decodeCollection<T>() throws -> [T]`
  - `decodeIfPresent<T>(_ type: T.Type) throws -> T?`
  - `decodeOptional<T>(_ type: T.Type) throws -> T?`
  - `skipUnknownField() throws`
  - `decodeDataZeroCopy() throws -> Data`

#### Protocols

- `BlazeBinaryEncodable` protocol
- `BlazeBinaryDecodable` protocol
- `BlazeBinaryCodable` typealias

#### Frame Protocol

- `BlazeFrameEncoder` enum
  - `maxFrameSize: Int` (static, constant: 5 MB)
  - `encodeFrame(_:compressionMode:) throws -> Data`
  - `encodeEncryptedFrame(_:session:) throws -> Data`
  - `encodeHandshakeFrame(_:) throws -> Data`

- `BlazeFrameParser` class
  - `maxBufferSize: Int` (static, constant: 10 MB)
  - `init(maxFrameSize:secureSession:)`
  - `append(_:) throws`
  - `nextFrame() throws -> Data?`
  - `bufferSize: Int`
  - `clear()`
  - `secureSession: BlazeSecureSession?`

#### Secure Session APIs

- `BlazeSecureHandshake` struct
  - `init(role:config:)`
  - `role: BlazeHandshakeRole`
  - `localPublicKeyData() -> Data`
  - `makeClientHello() -> Data`
  - `makeServerHello() -> Data`
  - `makeOutboundMessage() -> Data`
  - `receiveRemotePublicKey(_:) throws`
  - `deriveSessionKeys() throws -> BlazeSessionKeyMaterial`
  - `processInboundMessage(_:) throws -> BlazeSessionKeyMaterial`

- `BlazeSecureSession` struct
  - `init(keyMaterial:)`
  - `makeEncryptedFrame(from:) throws -> Data`
  - `decryptFramePayload(_:) throws -> Data`
  - `buildHandshakeFrame(_:) -> Data`
  - `parseHandshakeFrame(_:) throws -> Data`
  - `encryptFrame(_:) throws -> Data` (convenience)
  - `decryptFrame(_:) throws -> Data` (convenience)

- `BlazeCryptoConfig` struct
  - `init(cipherSuite:hkdfInfo:hkdfSalt:)`
  - `cipherSuite: CipherSuite`
  - `hkdfInfo: Data`
  - `hkdfSalt: Data?`

- `BlazeSessionKeyMaterial` struct
  - `encryptionKey: SymmetricKey`
  - `authenticationKey: SymmetricKey`
  - `noncePrefix: Data`

- `BlazeHandshakeRole` enum
  - `case client`
  - `case server`

#### Error Types

- `BlazeBinaryError` enum
  - All cases are stable

#### Compression

- `CompressionMode` enum
  - `case none`
  - `case lz4`
  - `case lzfse`

- `BlazeCompression` enum
  - `compress(_:mode:) throws -> Data`
  - `decompress(_:mode:originalSize:) throws -> Data`

### ⚠️ Experimental APIs

These APIs may change in minor versions (v1.4, v1.5, etc.):

- `BlazeIncrementalDecoder` class
- `BlazeStreamingCompressor` class
- `BlazeStreamingDecompressor` class
- `BackpressureConfig` struct
- `HandwritingContinuationRequest` struct
- `HandwritingContinuationResponse` struct

### 🔧 Internal APIs

These are not part of the public API and may change at any time:

- All `internal` or `@usableFromInline` members
- Private implementation details
- Test utilities

## Versioning Policy

### Major Versions (v2.0, v3.0, ...)

Breaking changes:
- Removal of stable APIs
- Incompatible changes to stable API signatures
- Breaking changes to on-wire format
- Breaking changes to frame protocol

### Minor Versions (v1.4, v1.5, ...)

Non-breaking additions:
- New APIs (methods, types, enum cases)
- New optional parameters
- New error cases
- Backwards-compatible protocol extensions
- Performance improvements

### Patch Versions (v1.3.1, v1.3.2, ...)

Bug fixes only:
- No API changes
- No on-wire format changes
- Security fixes
- Performance fixes

## Migration Guide

When upgrading between versions:

1. **Patch versions**: No changes required
2. **Minor versions**: Review CHANGELOG.md for new APIs
3. **Major versions**: See migration guide in release notes

## Deprecation Policy

1. APIs will be marked `@available(*, deprecated)` for at least one minor version
2. Deprecation warnings will include migration guidance
3. Deprecated APIs will be removed in the next major version

## On-Wire Format Stability

The binary encoding format is **frozen** for Protocol v1.3:

- Varint encoding (LEB128)
- ZigZag encoding for signed integers
- Little-endian fixed-width integers
- Frame format v2.0
- Handshake message format
- Encrypted frame format

Future versions will maintain backwards compatibility for decoding v1.3 data.

## Examples

### ✅ Safe to Use (Stable)

```swift
let encoder = BlazeBinaryEncoder()
try encoder.encode(42)
let data = encoder.encodedData()

let decoder = BlazeBinaryDecoder(data: data)
let value = try decoder.decodeInt()
```

### ⚠️ May Change (Experimental)

```swift
let incremental = BlazeIncrementalDecoder()
// This API may change in v1.4+
```

### ❌ Not Public API

```swift
// Don't rely on internal implementation details
// These may change without notice
```

---

**Related Documents**:
- [SPECIFICATION_v1.3.md](SPECIFICATION_v1.3.md) - Protocol specification
- [VERSIONING.md](VERSIONING.md) - Semantic versioning rules
- [CHANGELOG.md](../CHANGELOG.md) - Version history

