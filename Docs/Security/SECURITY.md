# BlazeBinary Security Documentation

_Last updated: December 2025_

This document provides comprehensive security documentation for BlazeBinary, including cryptographic protocols, security guarantees, attack surfaces, and best practices.

## Table of Contents

1. [Security Overview](#security-overview)
2. [Cryptographic Protocols](#cryptographic-protocols)
3. [Handshake Protocol](#handshake-protocol)
4. [Encryption Protocol](#encryption-protocol)
5. [Security Guarantees](#security-guarantees)
6. [Attack Surfaces](#attack-surfaces)
7. [Threat Mitigations](#threat-mitigations)
8. [Best Practices](#best-practices)

## Security Overview

BlazeBinary provides **optional** secure session mode with:

- **X25519 Diffie-Hellman** key agreement for establishing shared secrets
- **HKDF-SHA256** key derivation for session key generation
- **ChaCha20-Poly1305** AEAD encryption for frame payloads
- **Explicit compression mode** (v2.0) eliminating autodetection false positives

### Security Model

```mermaid
graph TB
    A[BlazeBinary Security Model] --> B[Codec Layer]
    A --> C[Frame Layer]
    A --> D[Secure Session Layer]
    
    B --> B1[Memory Safety]
    B --> B2[Input Validation]
    B --> B3[Bounds Checking]
    
    C --> C1[Frame Size Limits]
    C --> C2[Frame Type Validation]
    C --> C3[Backpressure]
    
    D --> D1[X25519 Key Agreement]
    D --> D2[HKDF Key Derivation]
    D --> D3[ChaCha20-Poly1305 AEAD]
    
    style A fill:#2c3e50,color:#ffffff
    style D fill:#e74c3c,color:#ffffff
    style B1 fill:#27ae60,color:#ffffff
    style B2 fill:#27ae60,color:#ffffff
    style B3 fill:#27ae60,color:#ffffff
```

## Cryptographic Protocols

### X25519 Diffie-Hellman Key Agreement

BlazeBinary uses X25519 (Curve25519) for key agreement:

- **Security Level**: 128 bits
- **Key Size**: 32 bytes (public and private)
- **Standard**: RFC 7748
- **Properties**: Fast, secure, widely deployed

```mermaid
sequenceDiagram
    participant A as Alice (Client)
    participant B as Bob (Server)
    
    Note over A: Generate X25519 keypair<br/>(privateKey_A, publicKey_A)
    A->>B: clientHello(publicKey_A)
    
    Note over B: Generate X25519 keypair<br/>(privateKey_B, publicKey_B)
    Note over B: Compute shared secret<br/>X25519(privateKey_B, publicKey_A)
    B->>A: serverHello(publicKey_B)
    
    Note over A: Compute shared secret<br/>X25519(privateKey_A, publicKey_B)
    
    Note over A,B: Both compute identical<br/>shared secret
```

### HKDF-SHA256 Key Derivation

Session keys are derived using HKDF-SHA256:

```mermaid
flowchart TD
    A[Shared Secret<br/>32 bytes from X25519] --> B[HKDF-Extract<br/>salt, sharedSecret]
    B --> C[PRK<br/>Pseudo-Random Key<br/>32 bytes]
    C --> D[HKDF-Expand<br/>PRK, info, L=64]
    D --> E[OKM<br/>Output Key Material<br/>64 bytes]
    E --> F[encryptionKey<br/>bytes 0-31<br/>32 bytes]
    E --> G[authenticationKey<br/>bytes 32-63<br/>32 bytes]
    H[SecRandomCopyBytes] --> I[noncePrefix<br/>4 bytes]
    
    style A fill:#2c3e50,color:#ffffff
    style C fill:#34495e,color:#ffffff
    style E fill:#34495e,color:#ffffff
    style F fill:#27ae60,color:#ffffff
    style G fill:#27ae60,color:#ffffff
    style I fill:#27ae60,color:#ffffff
```

**Key Derivation Process**:

1. **Extract Phase**:
   ```
   PRK = HMAC-SHA256(salt, sharedSecret)
   ```
   - Default: `salt = nil` (zero-length salt)

2. **Expand Phase**:
   ```
   OKM = HKDF-Expand(PRK, info, L = 64)
   ```
   - Default: `info = "BlazeBinarySession"` (UTF-8)
   - Output: 64 bytes

3. **Key Splitting**:
   ```
   encryptionKey = OKM[0..<32]
   authenticationKey = OKM[32..<64]
   ```

4. **Nonce Prefix**:
   ```
   noncePrefix = Random(4 bytes)  // SecRandomCopyBytes
   ```

### ChaCha20-Poly1305 AEAD Encryption

Frame payloads are encrypted using ChaCha20-Poly1305:

- **Algorithm**: ChaCha20 stream cipher + Poly1305 MAC
- **Key Size**: 32 bytes (256 bits)
- **Nonce Size**: 12 bytes (96 bits)
- **Tag Size**: 16 bytes (128 bits)
- **Standard**: RFC 8439

```mermaid
flowchart LR
    P[Plaintext<br/>Payload] --> ENC[ChaCha20-Poly1305<br/>Encrypt]
    ENC --> CT[Ciphertext<br/>+ Tag]
    CT --> FRAME[Frame Encoder<br/>v2.0 Format]
    FRAME --> W[Wire<br/>Network]
    
    K[encryptionKey<br/>32 bytes] --> ENC
    N[Nonce<br/>12 bytes<br/>prefix + counter] --> ENC
    A[AAD<br/>frameType + context] --> ENC
    
    style P fill:#2c3e50,color:#ffffff
    style ENC fill:#e74c3c,color:#ffffff
    style CT fill:#34495e,color:#ffffff
    style FRAME fill:#27ae60,color:#ffffff
    style W fill:#3498db,color:#ffffff
```

## Handshake Protocol

### Full Handshake Flow

```mermaid
sequenceDiagram
    participant C as Client
    participant S as Server
    
    Note over C: Generate X25519 keypair<br/>localPrivateKey_C, localPublicKey_C
    C->>S: clientHello<br/>(version=0x01, type=0x01, publicKey_C)
    
    Note over S: Generate X25519 keypair<br/>localPrivateKey_S, localPublicKey_S
    Note over S: Receive publicKey_C
    Note over S: Compute sharedSecret =<br/>X25519(localPrivateKey_S, publicKey_C)
    Note over S: Derive session keys via HKDF
    S->>C: serverHello<br/>(version=0x01, type=0x02, publicKey_S)
    
    Note over C: Receive publicKey_S
    Note over C: Compute sharedSecret =<br/>X25519(localPrivateKey_C, publicKey_S)
    Note over C: Derive session keys via HKDF
    
    Note over C,S: Both parties have<br/>identical session keys
    Note over C,S: Can now encrypt/decrypt frames
```

### Handshake State Machine

```mermaid
stateDiagram-v2
    [*] --> Init
    
    state Init {
        [*] --> ClientInit: role = .client
        [*] --> ServerInit: role = .server
    }
    
    ClientInit --> SentClientHello: makeClientHello()
    ServerInit --> WaitingForClientHello: ready
    
    WaitingForClientHello --> ReceivedClientHello: receiveRemotePublicKey()
    ReceivedClientHello --> SentServerHello: makeServerHello()
    
    SentClientHello --> WaitingForServerHello: sent
    WaitingForServerHello --> ReceivedServerHello: receiveRemotePublicKey()
    
    ReceivedServerHello --> KeysDerived: deriveSessionKeys()
    SentServerHello --> KeysDerived: deriveSessionKeys()
    
    KeysDerived --> [*]
    
    note right of KeysDerived
        Session keys ready:
        - encryptionKey (32 bytes)
        - authenticationKey (32 bytes)
        - noncePrefix (4 bytes)
    end note
```

### Handshake Message Format

```
Byte 0:   handshakeVersion (0x01)
Byte 1:   handshakeType (0x01 = clientHello, 0x02 = serverHello)
Bytes 2-3: flags (0x0000, reserved)
Bytes 4-35: publicKey (32 bytes, X25519)
```

**Total**: 36 bytes

## Encryption Protocol

### Frame Format (v2.0)

BlazeBinary v2.0 uses explicit frame format:

```
Byte 0:   frameType (0x00 = plaintext, 0x01 = encrypted, 0x02 = handshake)
Byte 1:   compressionMode (0x00 = none, 0x01 = LZ4, 0x02 = LZFSE)
Bytes 2-5: payloadLength (UInt32 big-endian)
Bytes 6+: payload (compressed or raw)
```

### Encrypted Frame Layout

```mermaid
graph LR
    A[Encrypted Frame] --> B[Frame Header<br/>6 bytes]
    A --> C[Encrypted Payload]
    
    B --> B1[frameType: 0x01<br/>1 byte]
    B --> B2[compressionMode: 0x00<br/>1 byte]
    B --> B3[payloadLength<br/>4 bytes]
    
    C --> C1[frameType: 0x01<br/>1 byte]
    C --> C2[Nonce: 12 bytes<br/>prefix + counter]
    C --> C3[Ciphertext<br/>N bytes]
    C --> C4[Tag: 16 bytes<br/>Poly1305]
    
    style A fill:#2c3e50,color:#ffffff
    style B fill:#34495e,color:#ffffff
    style C fill:#e74c3c,color:#ffffff
```

**Encrypted Payload Structure**:
- Byte 0: `frameType = 0x01` (for AAD)
- Bytes 1-12: Nonce (4-byte prefix + 8-byte counter, big-endian)
- Bytes 13..(N+12): Ciphertext
- Bytes (N+13)..(N+28): Poly1305 tag (16 bytes)

### Nonce Construction

```mermaid
graph TD
    A[Nonce Construction] --> B[noncePrefix<br/>4 bytes<br/>Random per session]
    A --> C[counter<br/>8 bytes<br/>Big-endian UInt64]
    B --> D[Nonce<br/>12 bytes total]
    C --> D
    
    D --> E[ChaCha20-Poly1305<br/>Encryption]
    
    style A fill:#2c3e50,color:#ffffff
    style D fill:#e74c3c,color:#ffffff
    style E fill:#27ae60,color:#ffffff
```

**Nonce Properties**:
- **Unique per frame**: Counter increments for each encrypted frame
- **Separate counters**: `sendCounter` for outbound, `recvCounter` for inbound
- **No reuse**: Each frame uses a unique nonce
- **Random prefix**: 4-byte prefix ensures nonce uniqueness across sessions

### AAD (Additional Authenticated Data)

AAD prevents cross-protocol attacks and ensures frame type integrity:

```
AAD = frameType (1 byte) || "BlazeBinaryFrame" (16 bytes UTF-8)
```

- `frameType = 0x01` for encrypted frames
- Static context string: "BlazeBinaryFrame"
- Included in Poly1305 tag calculation but not encrypted

## Security Guarantees

### Cryptographic Guarantees

| Guarantee | Status | Notes |
|-----------|--------|-------|
| **Confidentiality** | ✅ Yes | ChaCha20-Poly1305 provides encryption |
| **Authentication** | ✅ Yes | Poly1305 tag verifies integrity |
| **Perfect Forward Secrecy** | ✅ Yes | Ephemeral X25519 keys |
| **Replay Protection** | ⚠️ Partial | Counter tracking, no automatic rejection |
| **MITM Protection** | ❌ No | No public key authentication |
| **Key Compromise** | ✅ Yes | Old sessions remain secure (PFS) |

### Memory Safety Guarantees

- ✅ **No buffer overflows**: All reads are bounds-checked
- ✅ **No use-after-free**: Swift memory management
- ✅ **No double-free**: Swift ARC
- ✅ **Safe pointer operations**: Uses Swift safe APIs

### Input Validation Guarantees

- ✅ **Frame size limits**: 5 MB maximum
- ✅ **Length validation**: All lengths validated before use
- ✅ **Type validation**: Frame types and compression modes validated
- ✅ **Key validation**: Public keys validated (size, format)

## Attack Surfaces

### 1. Handshake Attacks

```mermaid
graph TD
    A[Handshake Attack Surfaces] --> B[Invalid Public Key]
    A --> C[Key Replay]
    A --> D[Man-in-the-Middle]
    A --> E[Version Mismatch]
    
    B --> B1[Wrong Size]
    B --> B2[Not on Curve]
    B --> B3[All Zeroes]
    B --> B4[Random Garbage]
    
    C --> C1[Replayed clientHello]
    C --> C2[Replayed serverHello]
    
    D --> D1[Intercept & Replace Keys]
    D --> D2[No Authentication]
    
    E --> E1[Unsupported Version]
    E --> E2[Version Downgrade]
    
    style A fill:#e74c3c,color:#ffffff
    style B1 fill:#27ae60,color:#ffffff
    style B2 fill:#27ae60,color:#ffffff
    style B3 fill:#27ae60,color:#ffffff
    style B4 fill:#27ae60,color:#ffffff
```

**Mitigations**:
- ✅ Public key size validation (must be 32 bytes)
- ✅ Public key format validation (X25519)
- ✅ Version check (must be 0x01)
- ⚠️ No MITM protection (requires out-of-band verification)

### 2. Encryption Attacks

```mermaid
graph TD
    A[Encryption Attack Surfaces] --> B[Nonce Reuse]
    A --> C[Key Reuse]
    A --> D[Tag Tampering]
    A --> E[Ciphertext Tampering]
    A --> F[Truncation]
    
    B --> B1[Counter Overflow]
    B --> B2[Session Reuse]
    
    C --> C1[Key Derivation Failure]
    C --> C2[Key Leakage]
    
    D --> D1[Tag Corruption]
    D --> D2[Tag Replacement]
    
    E --> E1[Bit Flipping]
    E --> E2[Partial Corruption]
    
    F --> F1[Truncated Ciphertext]
    F --> F2[Truncated Tag]
    
    style A fill:#e74c3c,color:#ffffff
    style B1 fill:#27ae60,color:#ffffff
    style B2 fill:#27ae60,color:#ffffff
    style D1 fill:#27ae60,color:#ffffff
    style D2 fill:#27ae60,color:#ffffff
```

**Mitigations**:
- ✅ Unique nonces per frame (counter + random prefix)
- ✅ Separate send/recv counters
- ✅ Poly1305 tag verification (tampering detected)
- ✅ AAD includes frame type (cross-protocol protection)

### 3. Frame Protocol Attacks

```mermaid
graph TD
    A[Frame Protocol Attacks] --> B[Oversized Frames]
    A --> C[Malformed Headers]
    A --> D[Compression Autodetection]
    A --> E[Frame Reordering]
    
    B --> B1[Memory Exhaustion]
    B --> B2[DoS]
    
    C --> C1[Invalid frameType]
    C --> C2[Invalid compressionMode]
    C --> C3[Invalid length]
    
    D --> D1[False Positives]
    D --> D2[Security Bypass]
    
    E --> E1[Application Confusion]
    
    style A fill:#e74c3c,color:#ffffff
    style B1 fill:#27ae60,color:#ffffff
    style B2 fill:#27ae60,color:#ffffff
    style D1 fill:#27ae60,color:#ffffff
    style D2 fill:#27ae60,color:#ffffff
```

**Mitigations**:
- ✅ Frame size limit (5 MB)
- ✅ Explicit compression mode (v2.0, no autodetection)
- ✅ Frame type validation
- ✅ Header validation

## Threat Mitigations

### Error Conditions State Machine

```mermaid
stateDiagram-v2
    [*] --> ValidInput
    
    ValidInput --> InvalidKey: Invalid public key
    ValidInput --> InvalidNonce: Nonce reuse detected
    ValidInput --> InvalidTag: Tag verification fails
    ValidInput --> InvalidFrame: Malformed frame
    ValidInput --> OversizedFrame: Frame > 5MB
    
    InvalidKey --> Error: BlazeBinaryError.invalidHandshake
    InvalidNonce --> Error: BlazeBinaryError.encryptionFailed
    InvalidTag --> Error: BlazeBinaryError.encryptionFailed
    InvalidFrame --> Error: BlazeBinaryError.invalidFrameLength
    OversizedFrame --> Error: BlazeBinaryError.oversizedFrame
    
    Error --> [*]
    
    note right of Error
        All errors are:
        - Type-safe (BlazeBinaryError)
        - Descriptive (localizedDescription)
        - Non-fatal (no crashes)
    end note
```

### Attack Response Matrix

| Attack | Detection | Response | Severity |
|--------|-----------|----------|----------|
| Invalid public key | ✅ Size/format check | Reject with error | Low |
| Nonce reuse | ⚠️ Counter tracking | Log warning | Medium |
| Tag tampering | ✅ Poly1305 verification | Reject with error | High |
| Ciphertext tampering | ✅ Poly1305 verification | Reject with error | High |
| Oversized frame | ✅ Size check | Reject with error | Medium |
| Malformed frame | ✅ Header validation | Reject with error | Low |
| Compression false positive | ✅ Explicit mode (v2.0) | N/A (eliminated) | None |

## Best Practices

### For Application Developers

1. **Always validate handshake keys**: Use out-of-band verification (certificates, key fingerprints)
2. **Monitor nonce counters**: Detect potential nonce reuse or replay attacks
3. **Set appropriate limits**: Configure `maxFrameSize` based on use case
4. **Use compression judiciously**: Only compress when beneficial, use explicit mode
5. **Implement replay protection**: Use application-level sequence numbers
6. **Rotate keys regularly**: Establish new sessions periodically
7. **Monitor error rates**: High error rates may indicate attacks

### For Library Maintainers

1. **Keep dependencies updated**: Swift Crypto, Compression framework
2. **Regular security audits**: Review cryptographic implementations
3. **Fuzz testing**: Test with randomized corrupted inputs
4. **Clear error messages**: Help developers understand failures
5. **Documentation**: Keep security docs up to date
6. **Version compatibility**: Maintain backwards compatibility carefully

### Security Checklist

- [ ] Handshake keys validated out-of-band
- [ ] Frame size limits configured appropriately
- [ ] Nonce counters monitored for anomalies
- [ ] Error handling implemented for all failure modes
- [ ] Compression mode explicitly set (v2.0)
- [ ] Session keys rotated periodically
- [ ] Replay protection implemented at application layer
- [ ] Security updates applied promptly

## Related Documents

- [THREAT_MODEL.md](THREAT_MODEL.md) - Detailed threat model
- [HANDSHAKE.md](HANDSHAKE.md) - Handshake protocol specification
- [ENCRYPTION.md](ENCRYPTION.md) - Encryption protocol details
- [FRAME_PROTOCOL.md](FRAME_PROTOCOL.md) - Frame format specification
- [ARCHITECTURE.md](ARCHITECTURE.md) - System architecture

---

**Security Contact**: See [SECURITY.md](../SECURITY.md) for reporting security vulnerabilities.

