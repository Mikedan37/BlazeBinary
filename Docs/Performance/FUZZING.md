# BlazeBinary Fuzzing Documentation

_Last updated: February 2025 (Protocol v1.3)_

This document describes the fuzzing infrastructure for BlazeBinary Protocol v1.3.

## Overview

BlazeBinary includes comprehensive fuzzing tests to ensure robustness against malformed inputs, edge cases, and adversarial data.

## Fuzzing Targets

### 1. Frame Parser

**Target**: `BlazeFrameParser`

**Fuzzing Strategy**:
- Random byte sequences of varying lengths
- Invalid frame lengths
- Truncated frames
- Oversized frames
- Mixed frame types

**Expected Behavior**:
- Never crashes
- Returns `nil` for incomplete frames
- Throws `BlazeBinaryError` for invalid frames
- Handles all error cases gracefully

### 2. Incremental Decoder

**Target**: `BlazeIncrementalDecoder`

**Fuzzing Strategy**:
- Random data chunks
- Partial records
- Invalid varints
- Truncated fields

**Expected Behavior**:
- Never crashes
- Handles partial data correctly
- Throws appropriate errors for invalid data

### 3. Compression/Decompression

**Target**: `BlazeCompression`

**Fuzzing Strategy**:
- Random data (may not compress well)
- Already compressed data
- Corrupted compressed streams
- Edge case sizes (0, 1, max)

**Expected Behavior**:
- Handles uncompressible data gracefully
- Detects corrupted streams
- Never crashes

### 4. AEAD Decryption

**Target**: `BlazeSecureSession.decryptFramePayload()`

**Fuzzing Strategy**:
- Random garbage as encrypted frames
- Truncated encrypted frames
- Tampered tags
- Invalid nonces
- Wrong frame types

**Expected Behavior**:
- Always throws `BlazeBinaryError.encryptionFailed` or `CryptoError`
- Never crashes
- Never accepts invalid data

### 5. Handshake Protocol

**Target**: `BlazeSecureHandshake`

**Fuzzing Strategy**:
- Invalid handshake versions
- Wrong handshake types
- Invalid public key lengths
- Truncated handshake messages

**Expected Behavior**:
- Throws `BlazeBinaryError.invalidHandshake` for invalid data
- Never crashes
- Validates all inputs

### 6. Varint Encoding/Decoding

**Target**: Varint (LEB128) encoding

**Fuzzing Strategy**:
- Boundary values (0, 1, 127, 128, Int.max, Int.min)
- Random values across full range
- Invalid varint sequences (too many bytes)
- Truncated varints

**Expected Behavior**:
- Round-trip correctness for all valid values
- Throws `BlazeBinaryError.invalidVarint` for invalid sequences
- Never crashes

## Corpus Seeds

Predefined corpus seeds for effective fuzzing:

1. **Empty data**: `Data()`
2. **Single bytes**: `0x00`, `0x01`, `0xFF`
3. **Small varints**: `127`, `128`
4. **Frame structures**: Valid and invalid frame headers
5. **Handshake messages**: Valid and invalid handshake formats

## Crash Reproducers

When fuzzing detects a crash or unexpected behavior:

1. **Log the input**: Save the exact input that caused the issue
2. **Minimize**: Reduce input to smallest reproducing case
3. **Document**: Add to regression test suite
4. **Fix**: Address the root cause

## Minimization

Input minimization strategies:

1. **Size reduction**: Remove bytes that don't affect the crash
2. **Byte mutation**: Try flipping bits to find minimal case
3. **Structure preservation**: Maintain frame structure while minimizing

## Fuzzing Results

### Coverage Goals

- **Frame parser**: 100% error path coverage
- **Decoder**: 100% error path coverage
- **Crypto**: All failure modes tested
- **Handshake**: All validation paths tested

### Known Limitations

- **Compression**: Some random data may not compress (expected)
- **AEAD**: Random data will always fail decryption (expected)
- **Handshake**: Invalid keys will always fail (expected)

## Running Fuzz Tests

```bash
swift test --filter ComprehensiveFuzzTests
```

**Expected Output**:
- All tests pass (no crashes)
- Errors are caught and handled
- No unexpected exceptions

## Continuous Fuzzing

For production deployments:

1. **Run fuzz tests in CI**: Include in test suite
2. **Monitor for regressions**: Track fuzzing results over time
3. **Expand corpus**: Add new seeds as issues are found
4. **Performance**: Ensure fuzzing completes in reasonable time

## Fuzzing Best Practices

1. **Deterministic**: Use seeded random for reproducibility
2. **Comprehensive**: Cover all code paths
3. **Fast**: Complete in reasonable time (< 1 minute)
4. **Isolated**: Each test is independent
5. **Documented**: All fuzzing strategies documented

---

**Related Documents**:
- [THREAT_MODEL.md](THREAT_MODEL.md) - Security threat model
- [FAILURE_SEMANTICS.md](FAILURE_SEMANTICS.md) - Error handling behavior
- [SPECIFICATION_v1.3.md](SPECIFICATION_v1.3.md) - Protocol specification

