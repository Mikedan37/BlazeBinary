# BlazeBinary Security Review

_Last updated: February 2025 (Protocol v1.3)_

This document provides a comprehensive security review of BlazeBinary Protocol v1.3, documenting cryptographic primitives, assumptions, and non-goals.

## Cryptographic Primitives

### Key Agreement: X25519

**Algorithm**: X25519 (Curve25519 Diffie-Hellman)  
**Standard**: RFC 7748  
**Security Level**: 128 bits  
**Key Size**: 32 bytes (256 bits)

**Properties**:
- **Fast**: Efficient scalar multiplication
- **Small**: 32-byte public keys
- **Secure**: 128-bit security level
- **Standard**: Widely deployed, well-reviewed

**Implementation**:
- Uses `swift-crypto` `Curve25519.KeyAgreement`
- Ephemeral keys generated per handshake
- Perfect forward secrecy (PFS)

### Key Derivation: HKDF-SHA256

**Algorithm**: HKDF (HMAC-based Key Derivation Function) with SHA-256  
**Standard**: RFC 5869  
**Security Level**: 256 bits (SHA-256)

**Structure**:
1. **Extract**: `PRK = HMAC-SHA256(salt, sharedSecret)`
   - Default salt: zero-length (nil)
2. **Expand**: `OKM = HKDF-Expand(PRK, info, L=64)`
   - Default info: `"BlazeBinarySession"` (UTF-8)
   - Output: 64 bytes
3. **Split**:
   - `encryptionKey = OKM[0..<32]`
   - `authenticationKey = OKM[32..<64]`

**Properties**:
- Cryptographically independent keys
- No key reuse across sessions
- Configurable salt and info

**Implementation**:
- Uses `swift-crypto` `HKDF<SHA256>`
- Random 4-byte nonce prefix per session

### Encryption: ChaCha20-Poly1305

**Algorithm**: ChaCha20-Poly1305 AEAD  
**Standard**: RFC 8439  
**Security Level**: 128 bits  
**Nonce Size**: 12 bytes (96 bits)  
**Tag Size**: 16 bytes (128 bits)

**Properties**:
- **Authenticated Encryption**: Confidentiality + authentication
- **Stream Cipher**: ChaCha20 for encryption
- **MAC**: Poly1305 for authentication
- **Fast**: Optimized for software

**Nonce Construction**:
```
nonce = noncePrefix (4 bytes) || counter (8 bytes, big-endian)
```

**AAD (Additional Authenticated Data)**:
```
AAD = frameType (1 byte) || "BlazeBinaryFrame" (16 bytes UTF-8)
```

**Implementation**:
- Uses `swift-crypto` `ChaChaPoly`
- Constant-time tag verification (provided by swift-crypto)
- Strict nonce uniqueness enforcement

## Security Assumptions

### 1. Entropy Requirements

**Assumption**: Cryptographically secure random number generation

**Required For**:
- Private key generation (X25519)
- Nonce prefix generation (4 bytes per session)
- Handshake nonces (if used)

**Implementation**:
- Uses `SecRandomCopyBytes` (macOS/iOS)
- Uses `/dev/urandom` (Linux)
- Provided by `swift-crypto`

**Verification**: Entropy sources are platform-provided and cryptographically secure.

### 2. Counter Monotonicity

**Assumption**: Counters are strictly monotonic (no reuse)

**Required For**:
- Nonce uniqueness
- Replay protection

**Implementation**:
- Send counter: Starts at 0, increments for each frame
- Receive counter: Tracks highest seen, rejects <= recvCounter
- Strict replay protection enabled by default

**Verification**: Counter validation in `BlazeSecureSession.decryptFramePayload()`

### 3. Key Material Security

**Assumption**: Session keys remain secret

**Required For**:
- Confidentiality
- Authentication

**Protection**:
- Ephemeral keys (PFS)
- Keys never transmitted
- Keys derived from shared secret
- Keys cleared when session ends

**Verification**: Keys are stored in memory only, never logged or transmitted.

### 4. AAD Integrity

**Assumption**: AAD cannot be tampered with

**Required For**:
- Cross-protocol attack prevention
- Frame type integrity

**Protection**:
- AAD included in Poly1305 tag
- Frame type in AAD
- Context string prevents cross-protocol attacks

**Verification**: AAD construction in `BlazeSecureSession.makeEncryptedFrame()`

## Security Guarantees

### ✅ Provided Guarantees

| Guarantee | Status | Implementation |
|-----------|--------|----------------|
| **Confidentiality** | ✅ Yes | ChaCha20 encryption |
| **Authentication** | ✅ Yes | Poly1305 tag verification |
| **Perfect Forward Secrecy** | ✅ Yes | Ephemeral X25519 keys |
| **Replay Protection** | ✅ Yes | Strict counter validation |
| **Nonce Uniqueness** | ✅ Yes | Counter + random prefix |
| **Key Independence** | ✅ Yes | HKDF key derivation |
| **Memory Safety** | ✅ Yes | Swift memory management |

### ⚠️ Partial Guarantees

| Guarantee | Status | Notes |
|-----------|--------|-------|
| **MITM Protection** | ⚠️ Partial | No public key authentication |
| **Side-Channel Resistance** | ⚠️ Partial | Not specifically hardened |

### ❌ Non-Goals

| Feature | Status | Rationale |
|---------|--------|-----------|
| **Public Key Authentication** | ❌ No | Out of scope (use certificates) |
| **Side-Channel Hardening** | ❌ No | Not required for most use cases |
| **Post-Quantum Security** | ❌ No | Current primitives are classical |

## Attack Vectors & Mitigations

### 1. Replay Attacks

**Attack**: Replaying previously captured encrypted frames

**Mitigation**:
- Strict counter validation
- Reject nonces with counter <= recvCounter
- Session closure on replay detection

**Status**: ✅ Mitigated

### 2. Man-in-the-Middle (MITM)

**Attack**: Intercepting and modifying handshake messages

**Mitigation**:
- None (out of scope)
- **Recommendation**: Use out-of-band key verification or certificates

**Status**: ⚠️ Not mitigated (by design)

### 3. Nonce Reuse

**Attack**: Reusing nonces with same key

**Mitigation**:
- Random 4-byte prefix per session
- Strictly monotonic counters
- Replay protection

**Status**: ✅ Mitigated

### 4. Tag Forgery

**Attack**: Forging authentication tags

**Mitigation**:
- Poly1305 provides 128-bit security
- Tag verification is constant-time (swift-crypto)
- Connection dropped on tag failure

**Status**: ✅ Mitigated

### 5. Key Compromise

**Attack**: Compromising session keys

**Mitigation**:
- Perfect forward secrecy (ephemeral keys)
- Old sessions remain secure
- New handshake required for new session

**Status**: ✅ Mitigated (PFS)

### 6. Resource Exhaustion

**Attack**: Sending oversized frames to exhaust memory

**Mitigation**:
- Hard limits: 5 MB frame, 10 MB buffer
- Immediate rejection of oversized frames
- Connection drop on violation

**Status**: ✅ Mitigated

## Constant-Time Operations

### Current Implementation

**Tag Verification**: Constant-time (provided by `swift-crypto` `ChaChaPoly`)

**Counter Comparison**: Not constant-time (but not security-critical)

**Key Comparison**: Not constant-time (but keys are not compared directly)

### Recommendations

For high-security deployments:
1. Use constant-time counter comparison (if needed)
2. Use constant-time key comparison (if needed)
3. Consider side-channel hardening for sensitive operations

## Security Best Practices

### For Application Developers

1. **Use Secure Random**: Ensure platform provides secure RNG
2. **Verify Keys Out-of-Band**: For MITM protection
3. **Monitor Replay Events**: Log and alert on replay detection
4. **Rotate Sessions**: Periodically re-handshake
5. **Validate Frame Types**: Check frame types match expectations
6. **Handle Errors Properly**: Drop connections on crypto errors

### For Library Maintainers

1. **Keep Dependencies Updated**: Update `swift-crypto` regularly
2. **Security Audits**: Regular security reviews
3. **Fuzz Testing**: Test with malformed inputs
4. **Documentation**: Keep security docs up to date
5. **Vulnerability Disclosure**: Follow responsible disclosure

## Known Limitations

### 1. No Public Key Authentication

**Limitation**: Handshake does not authenticate public keys

**Impact**: Vulnerable to MITM attacks

**Workaround**: Use out-of-band key verification or certificates

### 2. No Side-Channel Hardening

**Limitation**: Not specifically hardened against timing/power analysis

**Impact**: Potential side-channel vulnerabilities

**Workaround**: Use in environments without side-channel threats

### 3. Replay Protection is Strict

**Limitation**: Strict replay protection may reject valid out-of-order frames

**Impact**: Out-of-order delivery not supported

**Workaround**: Disable strict replay protection if out-of-order needed (not recommended)

## Security Recommendations

### For Production Use

1. ✅ **Enable Strict Replay Protection**: Default enabled
2. ✅ **Use Ephemeral Keys**: Default behavior
3. ✅ **Validate Frame Types**: Check all frame types
4. ✅ **Monitor Errors**: Log crypto errors
5. ✅ **Rotate Sessions**: Periodically re-handshake
6. ⚠️ **Verify Keys**: Use out-of-band verification for MITM protection
7. ⚠️ **Use TLS**: For additional transport security (if needed)

### For High-Security Deployments

1. **Side-Channel Hardening**: Consider constant-time implementations
2. **Key Verification**: Implement certificate pinning or key verification
3. **Audit Logging**: Log all security events
4. **Rate Limiting**: Implement rate limiting for handshakes
5. **Intrusion Detection**: Monitor for replay attacks

## References

- [RFC 7748](https://tools.ietf.org/html/rfc7748) - X25519 and X448
- [RFC 5869](https://tools.ietf.org/html/rfc5869) - HKDF
- [RFC 8439](https://tools.ietf.org/html/rfc8439) - ChaCha20-Poly1305
- [swift-crypto](https://github.com/apple/swift-crypto) - Cryptographic primitives

---

**Document Status**: Security Review for Protocol v1.3  
**Next Review**: v2.0 or security incident

