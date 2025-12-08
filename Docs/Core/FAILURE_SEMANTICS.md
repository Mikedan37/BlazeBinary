# BlazeBinary Failure Semantics

_Last updated: February 2025 (Protocol v1.3)_

This document specifies the failure modes and error handling behavior for BlazeBinary Protocol v1.3.

## Error Categories

### 1. Protocol Errors

**Type**: `ProtocolError` (from `ConnectionErrors.swift`)

| Error | Condition | Behavior |
|-------|-----------|----------|
| `frameTooLarge` | Frame size > 5 MB | **Drop connection** + throw error |
| `invalidFrameType` | Unknown frame type | **Drop connection** + throw error |
| `invalidFrameLength` | Length = 0 or > max | **Drop connection** + throw error |
| `bufferOverflow` | Buffer > 10 MB | **Drop connection** + throw error |

**Implementation**:
```swift
// In BlazeFrameParser
guard lengthInt <= maxFrameSize else {
    throw ProtocolError.frameTooLarge
    // Connection should be dropped by caller
}
```

### 2. Crypto Errors

**Type**: `CryptoError` (from `ConnectionErrors.swift`)

| Error | Condition | Behavior |
|-------|-----------|----------|
| `authFailed` | Invalid Poly1305 tag | **Drop connection** + throw error |
| `nonceReuse` | Counter <= recvCounter | **Close session** + throw error |
| `handshakeFailed` | Handshake error | **Drop connection** + throw error |
| `invalidKey` | Invalid key format | **Drop connection** + throw error |

**Implementation**:
```swift
// In BlazeSecureSession.decryptFramePayload
if strictReplayProtection && counter <= recvCounter {
    throw CryptoError.nonceReuse
    // Session must be closed
}

// Tag verification failure
catch {
    throw CryptoError.authFailed
    // Connection must be dropped
}
```

### 3. Compression Errors

**Type**: `CompressionError` (from `ConnectionErrors.swift`)

| Error | Condition | Behavior |
|-------|-----------|----------|
| `invalidStream` | Decompression fails | **Drop connection** + throw error |
| `corruptedData` | Compressed data invalid | **Drop connection** + throw error |

**Implementation**:
```swift
// In BlazeCompression.decompress
guard decompressed.count == originalSize else {
    throw CompressionError.invalidStream
    // Connection must be dropped
}
```

### 4. Decoding Errors

**Type**: `BlazeBinaryError`

| Error | Condition | Behavior |
|-------|-----------|----------|
| `truncated` | Insufficient data | Return `nil` (need more data) |
| `invalidVarint` | Invalid varint encoding | **Drop connection** + throw error |
| `decodeFailed` | Decoding failed | **Drop connection** + throw error |

**Implementation**:
```swift
// In BlazeBinaryDecoder
guard offset + count <= data.count else {
    throw BlazeBinaryError.truncated
    // Parser should wait for more data
}
```

## Failure Response Matrix

### On Malformed Frame

**Condition**: Invalid frame header, length, or structure

**Response**:
1. Throw `ProtocolError.invalidFrameLength` or `ProtocolError.invalidFrameType`
2. **Drop connection** (caller responsibility)
3. Clear parser buffer
4. Log error

**Example**:
```swift
// Invalid frame length
guard lengthInt > 0 && lengthInt <= maxFrameSize else {
    throw ProtocolError.invalidFrameLength
    // Caller must drop connection
}
```

### On Invalid Tag (Authentication Failure)

**Condition**: Poly1305 tag verification fails

**Response**:
1. Throw `CryptoError.authFailed`
2. **Drop connection immediately**
3. Do not process frame
4. Log security event

**Example**:
```swift
// In BlazeSecureSession.decryptFramePayload
do {
    plaintext = try ChaChaPoly.open(sealedBox, using: key, authenticating: aad)
} catch {
    throw CryptoError.authFailed
    // Connection must be dropped
}
```

### On Oversize Payload

**Condition**: Frame or payload exceeds size limits

**Response**:
1. Throw `ProtocolError.frameTooLarge`
2. **Drop connection**
3. Prevent memory exhaustion

**Example**:
```swift
guard payload.count <= maxFrameSize else {
    throw ProtocolError.frameTooLarge
    // Connection must be dropped
}
```

### On Unexpected Frame Type

**Condition**: Frame type not recognized or not expected

**Response**:
1. Throw `ProtocolError.invalidFrameType`
2. **Drop connection**
3. Log unexpected frame type

**Example**:
```swift
guard frameType == expectedType else {
    throw ProtocolError.invalidFrameType
    // Connection must be dropped
}
```

### On Decompression Error

**Condition**: Decompression fails or produces wrong size

**Response**:
1. Throw `CompressionError.invalidStream`
2. **Drop connection**
3. Do not process corrupted data

**Example**:
```swift
let decompressed = try BlazeCompression.decompress(data, mode: mode, originalSize: size)
guard decompressed.count == size else {
    throw CompressionError.invalidStream
    // Connection must be dropped
}
```

### On Nonce Reuse

**Condition**: Counter <= recvCounter (replay detected)

**Response**:
1. Throw `CryptoError.nonceReuse`
2. **Close session immediately**
3. Do not process frame
4. Log security event
5. Require new handshake

**Example**:
```swift
// In BlazeSecureSession.decryptFramePayload
if strictReplayProtection && counter <= recvCounter {
    throw CryptoError.nonceReuse
    // Session must be closed, new handshake required
}
```

## Error Propagation

### Frame Parser Errors

```swift
// BlazeFrameParser.nextFrame()
do {
    let payload = try parseFrame()
    return payload
} catch ProtocolError.frameTooLarge {
    // Drop connection
    throw error
} catch BlazeBinaryError.truncated {
    // Need more data
    return nil
} catch {
    // Other errors: drop connection
    throw error
}
```

### Secure Session Errors

```swift
// BlazeSecureSession.decryptFramePayload()
do {
    let plaintext = try decrypt()
    return plaintext
} catch CryptoError.authFailed {
    // Drop connection immediately
    throw error
} catch CryptoError.nonceReuse {
    // Close session, require new handshake
    throw error
} catch {
    throw CryptoError.encryptionFailed(error.localizedDescription)
}
```

## Recovery Strategies

### Recoverable Errors

**Errors that allow continuation**:
- `BlazeBinaryError.truncated`: Wait for more data
- `BlazeBinaryError.needMoreData`: Wait for more data

**Response**: Return `nil`, wait for more data, retry

### Non-Recoverable Errors

**Errors that require connection drop**:
- `ProtocolError.*`: All protocol errors
- `CryptoError.authFailed`: Authentication failure
- `CryptoError.nonceReuse`: Replay detected
- `CompressionError.*`: All compression errors
- `BlazeBinaryError.invalidVarint`: Invalid encoding
- `BlazeBinaryError.decodeFailed`: Decoding failure

**Response**: Drop connection, clear state, log error

## Security Considerations

### Authentication Failures

**Critical**: Authentication failures MUST result in immediate connection termination.

**Rationale**: Invalid tags indicate:
- Tampering
- Key compromise
- Implementation error

**No retries**: Do not attempt to recover from authentication failures.

### Replay Attacks

**Detection**: Counter-based replay detection

**Response**: 
- Reject frame
- Close session
- Require new handshake

**Rationale**: Replayed frames may indicate:
- Man-in-the-middle attack
- Session hijacking
- Network issues

### Resource Exhaustion

**Protection**: Size limits prevent DoS

**Response**:
- Reject oversized frames immediately
- Drop connection
- Log resource exhaustion attempt

## Implementation Checklist

- [x] Protocol errors drop connection
- [x] Crypto errors drop connection or close session
- [x] Compression errors drop connection
- [x] Replay protection rejects nonces
- [x] Authentication failures drop connection
- [x] Size limits enforced
- [x] Error types defined
- [x] Error propagation documented

## Testing Requirements

All failure modes MUST be tested:

1. **Malformed frames**: Invalid length, invalid type
2. **Invalid tags**: Tampered tags, wrong tags
3. **Oversize payloads**: > 5 MB frames
4. **Replay attacks**: Duplicate nonces
5. **Decompression errors**: Corrupted compressed data
6. **Invalid varints**: Malformed varint encodings

---

**Related Documents**:
- [SPECIFICATION_v1.3.md](SPECIFICATION_v1.3.md) - Protocol specification
- [THREAT_MODEL.md](THREAT_MODEL.md) - Security threat model
- [SECURITY.md](SECURITY.md) - Security documentation

