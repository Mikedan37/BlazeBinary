# BlazeBinary

## Security Policy

_Last updated: February 2025_

## Supported Versions

We actively support the following versions with security updates:

| Version | Supported          |
| ------- | ------------------ |
| 1.0.x   | y |
| < 1.0   | n |

## Reporting a Vulnerability

If you discover a security vulnerability in BlazeBinary, please report it responsibly.

**Email**: founder@danylchukstudios.dev

**Do not** open a public GitHub issue for security vulnerabilities.

### What to Include

When reporting a vulnerability, please include:

1. **Description**: Clear description of the vulnerability
2. **Impact**: Potential impact and attack scenarios
3. **Proof of Concept**: Steps to reproduce (if possible)
4. **Mitigation**: Suggested fixes (if any)

### Response Timeline

- **Initial Response**: Within 48 hours
- **Status Update**: Within 7 days
- **Resolution**: Depends on severity and complexity

## Security Considerations

### Transport Layer

BlazeBinary is a **binary codec layer** and does not provide transport security. When using BlazeBinary over untrusted networks:

- **Use TLS/SSL**: Always use encrypted transport (TLS 1.2+)
- **Authenticate peers**: Verify the identity of communication partners
- **Validate certificates**: Check certificate chains and revocation

### Frame Tampering

BlazeBinary frames include length prefixes but **no integrity checks** at the frame layer:

- **CRC32**: Optional CRC32 can be added at the application layer
- **Message Authentication**: Use HMAC or AES-GCM for authenticated encryption
- **Replay Protection**: Implement sequence numbers or nonces at the application layer

### Malformed Data

BlazeBinary includes strict validation:

- **Bounds checking**: All reads are validated before execution
- **Size limits**: Maximum frame size (5 MB) and buffer size (10 MB)
- **Type validation**: Invalid encodings are rejected with clear errors

However, **malformed data can still cause denial of service**:

- **Resource exhaustion**: Large but valid payloads can consume memory
- **CPU exhaustion**: Complex varint decoding can consume CPU cycles
- **Mitigation**: Always set appropriate `maxAllowedLength` limits

### Out of Scope

The following are **not** security vulnerabilities in BlazeBinary:

- **Application-level logic errors**: Bugs in code using BlazeBinary
- **Transport-layer attacks**: Network-level attacks (use TLS)
- **Side-channel attacks**: Timing attacks, power analysis (not addressed)
- **Compression bombs**: Extremely large but valid payloads (use size limits)

## Security Best Practices

1. **Validate input sizes**: Always set `maxAllowedLength` appropriately
2. **Use authenticated encryption**: When transmitting over untrusted networks
3. **Monitor resource usage**: Watch for memory and CPU exhaustion
4. **Keep dependencies updated**: Update BlazeBinary when security patches are released
5. **Review decoded data**: Don't trust decoded values without validation

## Scope & Non-Goals

BlazeBinary is a **serialization format**, not a security protocol. It provides deterministic encoding and safe parsing, but does not provide:

- **On-wire confidentiality**: BlazeBinary does not encrypt data. Use transport encryption (e.g., TLS, or AES-GCM at another layer) for confidentiality and strong integrity.
- **Cryptographic integrity**: While CRC32 can detect accidental corruption, it is not cryptographic. Do not treat CRC as cryptographic authentication.
- **Replay protection**: BlazeBinary does not prevent replay attacks. Implement sequence numbers or nonces at the application layer.
- **Side-channel resistance**: BlazeBinary is not specifically hardened against timing or power analysis attacks.

### What BlazeBinary Does Provide

- **Deterministic encoding**: Same input → same bytes (critical for hashing, signatures, deduplication)
- **Memory safety**: Uses Swift's safe memory model; no buffer overflows, no use-after-free
- **Strict validation**: All input is validated before processing; malformed data is rejected with clear errors
- **Bounded resource usage**: Hard limits on frame size, buffer size, and field size prevent unbounded memory allocation

For detailed security guarantees and threat analysis, see [THREAT_MODEL.md](Docs/THREAT_MODEL.md).

## Security Guarantees

BlazeBinary provides the following security guarantees:

- **No buffer overflows**: All reads are bounds-checked
- **No integer overflows**: Varint decoding includes overflow protection
- **Deterministic decoding**: Same input always produces same output
- **Fail-fast errors**: Invalid data is rejected immediately
- **Memory safety**: Uses Swift's safe memory model

## References

- [THREAT_MODEL.md](Docs/THREAT_MODEL.md) - Detailed threat analysis
- [SPECIFICATION.md](Docs/SPECIFICATION.md) - Encoding format specification
- [ARCHITECTURE.md](Docs/ARCHITECTURE.md) - System architecture

