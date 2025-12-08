# BlazeBinary Protocol v1.3 Specification

**Status**: FROZEN - Production Release Candidate  
**Date**: February 2025  
**Version**: 1.3.0

## Abstract

This document specifies BlazeBinary Protocol v1.3, a deterministic binary encoding format with optional secure session support. This specification is **frozen** and will not change except for bug fixes in patch versions (v1.3.x).

## 1. Protocol Version

**Protocol Version**: 1.3  
**Specification Status**: FROZEN  
**Backwards Compatibility**: 
- v1.3 decoders MUST decode v1.0, v1.1, v1.2 data
- v1.3 encoders MAY produce v1.0-compatible output (schemaVersion=1, no compression, plaintext frames)

## 2. Encoding Format

### 2.1. Varint (LEB128)

**REQUIRED**: All variable-length integers use LEB128 encoding.

**Encoding Rules**:
- Extract 7 bits: `byte = value & 0x7F`
- Set continuation bit if more bits: `byte |= 0x80` (if `value >> 7 != 0`)
- Maximum 10 bytes for 64-bit values
- Last byte MUST have continuation bit = 0

**Examples**:
- `0` → `[0x00]`
- `127` → `[0x7F]`
- `128` → `[0x80, 0x01]`
- `300` → `[0xAC, 0x02]`

### 2.2. Zigzag Encoding (Signed Integers)

**REQUIRED**: Signed integers use zigzag encoding before varint.

**Formula**: `zigzag = (value << 1) ^ (value >> 63)`

**Mapping**:
- `0` → `0`
- `1` → `2`
- `-1` → `1`
- `2` → `4`
- `-2` → `3`

### 2.3. Fixed-Width Types

**REQUIRED**: Little-endian encoding for fixed-width types.

| Type | Size | Encoding |
|------|------|----------|
| `UInt32` | 4 bytes | Little-endian |
| `UInt64` | 8 bytes | Little-endian |
| `Double` | 8 bytes | IEEE 754, little-endian bit pattern |
| `Bool` | 1 byte | `0x00` (false), `0x01` (true) |

### 2.4. Length-Prefixed Types

**REQUIRED**: Varint length prefix followed by payload.

| Type | Format |
|------|--------|
| `String` | `<varint byteCount> <UTF-8 bytes>` |
| `Data` | `<varint length> <raw bytes>` |

**Constraints**:
- Length MUST be ≤ 10,485,760 bytes (10 MB) by default
- Empty strings/data: length = 0, no payload

### 2.5. Arrays

**REQUIRED**: `<varint count> <item1> <item2> ... <itemN>`

- Count MUST be ≤ 10,485,760 elements by default
- Items encoded in order
- Empty array: count = 0

### 2.6. Optionals

**REQUIRED**: `<bool present> <value if present>`

- `present = 0x00`: value absent
- `present = 0x01`: value follows

### 2.7. Schema Versioning

**REQUIRED**: Optional schema version marker for forward compatibility.

**Format**:
- Schema version 1 (default): No marker (backwards compatible)
- Schema version > 1: `[0xFE] <varint schemaVersion> <fields...>`

**Decoder Behavior**:
- If first byte = `0xFE`: Read varint as schema version, then decode fields
- Otherwise: Assume schema version 1

## 3. Frame Protocol v2.0

### 3.1. Frame Header Format

**REQUIRED**: All frames use v2.0 format.

```
Byte 0:   frameType (UInt8)
Byte 1:   compressionMode (UInt8)
Bytes 2-5: payloadLength (UInt32, big-endian)
Bytes 6+:  payload (variable length)
```

**Total Frame Size**: `6 + payloadLength` bytes

### 3.2. Frame Types

| Value | Name | Description |
|-------|------|-------------|
| `0x00` | `plaintext` | Plaintext BlazeBinary payload |
| `0x01` | `encrypted` | Encrypted payload (ChaCha20-Poly1305) |
| `0x02` | `handshake` | Handshake message (X25519) |

### 3.3. Compression Modes

| Value | Name | Algorithm |
|-------|------|-----------|
| `0x00` | `none` | No compression |
| `0x01` | `lz4` | LZ4 compression |
| `0x02` | `lzfse` | LZFSE compression |

**Compressed Frame Format** (when compressionMode != 0x00):
```
[frameType] [compressionMode] [payloadLength] [originalSize: 4 bytes big-endian] [compressedPayload]
```

### 3.4. Frame Constraints

**REQUIRED**:
- Maximum frame size: 5,242,880 bytes (5 MB)
- Maximum buffer size: 10,485,760 bytes (10 MB)
- Minimum frame size: 6 bytes (header only)
- Payload length: `0 <= payloadLength <= 5,242,874`

## 4. Secure Session Protocol

### 4.1. Handshake Message Format

**REQUIRED**: 36-byte handshake message.

```
Byte 0:   handshakeVersion (0x01)
Byte 1:   handshakeType (0x01=clientHello, 0x02=serverHello)
Bytes 2-3: flags (0x0000, reserved)
Bytes 4-35: publicKey (32 bytes, X25519)
```

### 4.2. Key Agreement

**REQUIRED**: X25519 Diffie-Hellman key exchange.

**Process**:
1. Client generates keypair, sends `clientHello` with public key
2. Server generates keypair, sends `serverHello` with public key
3. Both parties derive shared secret: `sharedSecret = X25519(clientPrivate, serverPublic) = X25519(serverPrivate, clientPublic)`

### 4.3. Key Derivation

**REQUIRED**: HKDF-SHA256 key derivation.

**Process**:
1. Extract: `PRK = HMAC-SHA256(salt, sharedSecret)`
   - Default salt: zero-length (nil)
2. Expand: `OKM = HKDF-Expand(PRK, info, L=64)`
   - Default info: `"BlazeBinarySession"` (UTF-8)
   - Output length: 64 bytes
3. Split:
   - `encryptionKey = OKM[0..<32]`
   - `authenticationKey = OKM[32..<64]`
4. Generate: `noncePrefix = Random(4 bytes)`

### 4.4. Encrypted Frame Format

**REQUIRED**: ChaCha20-Poly1305 AEAD encryption.

**Frame Structure**:
```
[frameType=0x01] [compressionMode] [payloadLength] [encryptedPayload]
```

**Encrypted Payload Structure**:
```
Byte 0:   frameType = 0x01 (for AAD)
Bytes 1-12: nonce (4-byte prefix || 8-byte counter, big-endian)
Bytes 13..(N+12): ciphertext
Bytes (N+13)..(N+28): Poly1305 tag (16 bytes)
```

**Minimum Size**: 29 bytes (1 + 12 + 0 + 16)

### 4.5. Nonce Construction

**REQUIRED**: `nonce = noncePrefix || counter.bigEndianBytes`

- `noncePrefix`: 4 random bytes (generated during key derivation)
- `counter`: 8-byte big-endian counter
- Total: 12 bytes (96 bits)

**Counter Rules**:
- Send counter: Starts at 0, increments for each encrypted frame
- Receive counter: Tracks highest seen counter
- **MUST NOT** reuse nonces with same key
- **MUST** reject nonces with counter <= previous counter (replay protection)

### 4.6. AAD (Additional Authenticated Data)

**REQUIRED**: `AAD = frameType || "BlazeBinaryFrame"`

- `frameType`: 1 byte (0x01 for encrypted frames)
- Context string: "BlazeBinaryFrame" (16 bytes UTF-8)

## 5. Error Handling

### 5.1. Error Types

| Error | Description |
|-------|-------------|
| `truncated` | Insufficient data |
| `invalidVarint` | Invalid varint encoding |
| `invalidFrameLength` | Invalid frame length |
| `oversizedFrame` | Frame exceeds 5 MB |
| `decodeFailed` | Decoding failed |
| `needMoreData` | More data needed |
| `handshakeFailed` | Handshake operation failed |
| `invalidHandshake` | Invalid handshake message |
| `encryptionFailed` | Encryption/decryption failed |
| `invalidSession` | Invalid session state |

### 5.2. Error Semantics

**REQUIRED**: All errors MUST be thrown as `BlazeBinaryError` or sub-types.

**Behavior**:
- Malformed frame: Drop connection
- Invalid tag: Drop connection, return `CryptoError.authFailed`
- Oversize payload: Throw `ProtocolError.frameTooLarge`
- Unexpected frame type: Throw `ProtocolError.invalidFrameType`
- Decompression error: Throw `CompressionError.invalidStream`
- Nonce reuse: Immediately close session

## 6. Backwards Compatibility

### 6.1. Legacy Frame Format (v1.0/v1.1)

**Parser Behavior**:
- If frame starts with 4-byte length (no frameType byte): Treat as v1.0/v1.1
- Legacy format: `[4-byte length] [payload]`
- Compression detection: If first payload byte is 0x01 or 0x02, treat as compression mode

### 6.2. Schema Version Compatibility

- v1.3 decoders MUST decode v1.0 records (no schema version marker)
- v1.3 encoders MAY produce v1.0-compatible records (schemaVersion=1)

## 7. Security Requirements

### 7.1. Cryptographic Primitives

**REQUIRED**:
- X25519 for key agreement (RFC 7748)
- HKDF-SHA256 for key derivation (RFC 5869)
- ChaCha20-Poly1305 for AEAD (RFC 8439)

### 7.2. Nonce Requirements

**REQUIRED**:
- Nonces MUST be unique per key
- Nonces MUST NOT be reused
- Counters MUST be strictly monotonic
- Replayed nonces MUST be rejected

### 7.3. Constant-Time Operations

**REQUIRED**: All cryptographic comparisons MUST use constant-time operations.

### 7.4. Entropy Requirements

**REQUIRED**:
- Private keys: Cryptographically secure random (32 bytes)
- Nonce prefixes: Cryptographically secure random (4 bytes)
- Handshake nonces: Cryptographically secure random

## 8. Implementation Requirements

### 8.1. Bounds Checking

**REQUIRED**: All reads MUST be bounds-checked before execution.

### 8.2. Size Limits

**REQUIRED**:
- Frame size: 5 MB maximum
- Buffer size: 10 MB maximum
- Field size: 10 MB maximum (configurable)

### 8.3. Determinism

**REQUIRED**: Same input MUST produce identical output.

## 9. Test Requirements

**REQUIRED**: All implementations MUST pass:
- Varint encoding/decoding tests
- Zigzag encoding/decoding tests
- Frame parsing tests
- Handshake flow tests
- Encryption/decryption tests
- Replay protection tests
- Tampering detection tests

## 10. References

- [LEB128](https://en.wikipedia.org/wiki/LEB128) - Variable-length integer encoding
- [RFC 7748](https://tools.ietf.org/html/rfc7748) - X25519 and X448
- [RFC 5869](https://tools.ietf.org/html/rfc5869) - HKDF
- [RFC 8439](https://tools.ietf.org/html/rfc8439) - ChaCha20-Poly1305

---

**Document Status**: FROZEN - Protocol v1.3.0  
**Next Version**: v2.0 (breaking changes)  
**Patch Versions**: v1.3.x (bug fixes only)

