# Changelog

All notable changes to BlazeBinary will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.3.0] - 2025-02-XX - Protocol v1.3.0 (FROZEN)

### Status
**Protocol v1.3.0 is FROZEN** - This is the production-ready release candidate. The specification will not change except for bug fixes in patch versions (v1.3.x).

### Production Readiness
- **Comprehensive Testing**: Full test suite with unit, integration, fuzz, and property tests
- **Security Review**: Complete security audit with threat model and hardening
- **Performance Benchmarks**: Comprehensive benchmark suite with percentile tracking
- **Fuzzing Infrastructure**: Automated fuzzing for robustness
- **Documentation**: Complete specification, API stability guarantees, and failure semantics
- **Examples**: Production-ready example applications

### Added - Production Features
- **API Stability Documentation**: [API_STABILITY.md](Docs/Core/API_STABILITY.md) - Clear API stability guarantees
- **Versioning Policy**: [VERSIONING.md](Docs/Core/VERSIONING.md) - Semantic versioning rules
- **Failure Semantics**: [FAILURE_SEMANTICS.md](Docs/Core/FAILURE_SEMANTICS.md) - Complete error handling specification
- **Security Review**: [SECURITY_REVIEW.md](Docs/Security/SECURITY_REVIEW.md) - Comprehensive security analysis
- **Performance Tracking**: [PERFORMANCE_TRACKING.md](Docs/Performance/PERFORMANCE_TRACKING.md) - CI/CD performance monitoring
- **Fuzzing Documentation**: [FUZZING.md](Docs/Performance/FUZZING.md) - Fuzzing infrastructure and strategies
- **Frozen Specification**: [SPECIFICATION_v1.3.md](Docs/Core/SPECIFICATION_v1.3.md) - Production-ready protocol specification

### Enhanced - Testing & Quality
- **Comprehensive Fuzz Tests**: Automated fuzzing for frame parser, decoder, compression, and encryption
- **Performance Benchmarks**: Detailed benchmark suite with percentile analysis (p50, p90, p95, p99)
- **Example Applications**: EchoClient, SecureChat, FileSender examples
- **Benchmark Infrastructure**: Automated benchmark runner with JSON/Markdown output

### Documentation
- Complete documentation reorganization into Core/, Security/, Crypto/, Performance/ directories
- All documentation links verified and working
- Mermaid diagrams for architecture and protocol flows
- Professional, production-ready documentation structure

### Backwards Compatibility
- **100% backwards compatible** with v1.0, v1.1, and v1.2
- All existing APIs remain stable
- Protocol v1.3 decoders handle all prior versions

## [1.2.0] - 2025-02-XX - Protocol v1.2 (Secure Session Mode)

### Added - Streaming & Performance Features
- **Streaming Compression**: Chunked compression for large payloads
  - `BlazeStreamingCompressor`: Incremental compression with configurable chunk size
  - `BlazeStreamingDecompressor`: Incremental decompression
  - Supports LZ4 and LZFSE compression modes
  - See [FRAME_PROTOCOL.md](Docs/Core/FRAME_PROTOCOL.md) for details

- **Incremental Decoding**: Process huge payloads in chunks
  - `BlazeIncrementalDecoder`: Decode fields incrementally without loading entire payload
  - `decodeDataIncremental()`, `decodeStringIncremental()`: Field-level incremental decoding
  - `decodeArrayIncremental()`: Array processing with callbacks
  - See [ARCHITECTURE.md](Docs/Core/ARCHITECTURE.md) for details

- **Backpressure Support**: Flow control for frame parser
  - `BackpressureConfig`: Configurable high/low water marks
  - `BlazeFrameParser.hasBackpressure`: Backpressure state property
  - `append()` returns backpressure state for flow control
  - Default: 8MB high water mark, 2MB low water mark
  - See [FRAME_PROTOCOL.md](Docs/Core/FRAME_PROTOCOL.md) for details

### Added - Error Handling
- **Connection-Level Typed Errors**: Noise Protocol-style error taxonomy
  - `DisconnectReason`: 11 standard disconnect reasons + application-defined
  - `ProtocolError`: Protocol-level errors (frame format, size violations, etc.)
  - `CryptoError`: Cryptographic errors (authentication, decryption, nonce, etc.)
  - `BlazeBinaryError` extensions: Automatic conversion to typed errors
  - See [SPECIFICATION.md](Docs/Core/SPECIFICATION.md) for error taxonomy

### Enhanced - Encryption Testing
- **Full AEAD Verification Tests**: Comprehensive encryption test suite
  - Tamper detection: Corrupted tag, ciphertext, partial corruption
  - Wrong key rejection: Authentication failure on key mismatch
  - Wrong nonce rejection: Authentication failure on nonce mismatch
  - Replay detection: Counter tracking for replay prevention
  - Truncated frame handling: Proper error handling for incomplete frames
  - AAD protection: Frame type tampering detection
  - 12 comprehensive tests covering all failure modes

### Testing
- **StreamingCompressionTests**: 3 tests for chunked compression
- **IncrementalDecodingTests**: 4 tests for incremental decoding
- **BackpressureTests**: 5 tests for backpressure state machine
- **ConnectionErrorTests**: 6 tests for typed error system
- **EncryptedFrameTests**: Enhanced with 12 comprehensive AEAD tests

### Dependencies
- No new dependencies (uses existing Compression framework)

### Backwards Compatibility
- All new features are opt-in and fully backwards compatible
- Existing APIs unchanged
- Default configurations work with existing code

### Added - Secure Session Mode
- **X25519 Diffie-Hellman Handshake**: Full key agreement implementation
  - Client/server roles with one-round-trip handshake
  - X25519 key exchange for shared secret establishment
  - Handshake message format (36 bytes: version, type, flags, public key)
  - See [HANDSHAKE.md](Docs/Crypto/HANDSHAKE.md) for protocol specification

- **HKDF-SHA256 Key Derivation**: Session key derivation from shared secrets
  - HKDF-Extract and HKDF-Expand phases
  - Derives 64 bytes: 32 for encryption, 32 for authentication
  - Configurable HKDF info and salt parameters
  - Random 4-byte nonce prefix generation
  - See [ENCRYPTION.md](Docs/Crypto/ENCRYPTION.md) for key schedule details

- **ChaCha20-Poly1305 AEAD Encryption**: Authenticated encryption for frames
  - 12-byte nonces (4-byte prefix + 8-byte counter)
  - Separate send/recv counters for bidirectional communication
  - AAD includes frame type and context string
  - Automatic decryption in `BlazeFrameParser` when secure session provided
  - See [ENCRYPTION.md](Docs/Crypto/ENCRYPTION.md) for encryption specification

- **Backwards Compatible Frame Extensions**: Optional secure session support
  - Frame type byte: 0x00 (plaintext), 0x01 (encrypted), 0x02 (handshake)
  - Plaintext frames continue to work unchanged
  - Mixed plaintext and encrypted frames in same stream
  - See [FRAME_PROTOCOL.md](Docs/Core/FRAME_PROTOCOL.md) for frame format

- **New APIs**:
  - `BlazeSecureHandshake`: Handshake protocol implementation
  - `BlazeSecureSession`: Frame encryption/decryption
  - `BlazeCryptoConfig`: Crypto configuration
  - `BlazeSessionKeyMaterial`: Derived session keys
  - `BlazeFrameEncoder.encodeEncryptedFrame()`: Encrypt and encode frames
  - `BlazeFrameEncoder.encodeHandshakeFrame()`: Encode handshake frames
  - `BlazeFrameParser(secureSession:)`: Parser with automatic decryption

- **New Error Types**:
  - `BlazeBinaryError.handshakeFailed`: Handshake operation failed
  - `BlazeBinaryError.invalidHandshake`: Invalid handshake message
  - `BlazeBinaryError.encryptionFailed`: Encryption/decryption failed
  - `BlazeBinaryError.invalidSession`: Invalid session state

- **Comprehensive Test Suite**:
  - `BlazeHandshakeTests`: Key agreement, message format, validation
  - `BlazeEncryptionTests`: Round-trip, tampering, nonce increment
  - `BlazeEncryptedFrameIntegrationTests`: Full client/server simulation

- **Documentation**:
  - [ENCRYPTION.md](Docs/Crypto/ENCRYPTION.md): Complete encryption specification
  - [HANDSHAKE.md](Docs/Crypto/HANDSHAKE.md): Handshake protocol specification
  - Updated [FRAME_PROTOCOL.md](Docs/Core/FRAME_PROTOCOL.md): Secure session extensions
  - Updated [README.md](README.md): Secure Session Mode section

### Dependencies
- Added `swift-crypto` package (v3.0.0+) for cryptographic primitives

## [Unreleased] - Protocol v1.1

### Added - Tier 1 Features
- **Schema Versioning**: Optional schema version field for forward compatibility
  - Encoder supports `schemaVersion` parameter (default: 1)
  - Decoder automatically detects schema version
  - Backwards compatible with v1.0 (v1 records have no marker)
  - See [SPECIFICATION.md](Docs/Core/SPECIFICATION.md) for details

- **Compression Support**: Optional payload compression
  - LZ4 compression (fast, good ratio)
  - LZFSE compression (Apple's compression, balanced)
  - Frame-level compression with automatic detection
  - Backwards compatible (uncompressed frames work as before)
  - See [FRAME_PROTOCOL.md](Docs/Core/FRAME_PROTOCOL.md) for details

- **Canonical Text Format**: Developer debug formatter
  - `.toCanonicalText()` method for debugging
  - Stable text representation with sorted keys
  - Unicode escape handling
  - See [RATIONALE.md](Docs/Core/RATIONALE.md) for use cases

- **Hex Dump Utilities**: Binary data inspection
  - `HexDump.dump()` for formatted hex output
  - `HexDump.dumpCompact()` for compact format
  - Integrated into test failures for debugging
  - See [HEXDUMP.md](Docs/Core/HEXDUMP.md) for usage

### Added - Tier 2 Features
- **Zero-Copy Struct Decoding**: Experimental Cap'n Proto-style API
  - `decodeZeroCopy<T>()` for fixed-width structs
  - Direct memory mapping onto data buffer
  - Alignment and bounds checking
  - See [ZERO_COPY_DECODING.md](Docs/Core/ZERO_COPY_DECODING.md) for details

### Added - Tier 3 Features (Experimental/Placeholder)
- **Diffie-Hellman Handshake**: X25519 key exchange infrastructure
  - Placeholder for future implementation
  - See [HANDSHAKE.md](Docs/Crypto/HANDSHAKE.md) for planned design

- **Encrypted Frames**: ChaCha20-Poly1305 encryption infrastructure
  - Placeholder for future implementation
  - See [ENCRYPTION.md](Docs/Crypto/ENCRYPTION.md) for planned design

### Changed
- Enhanced documentation structure
- Improved error messages
- Frame format extended for compression (backwards compatible)

### Testing
- SchemaVersionTests: 9 tests covering version detection and compatibility
- CompressionTests: 10 tests for LZ4, LZFSE, and frame integration
- CanonicalTextTests: Basic canonical text formatting tests
- HexDumpTests: Hex dump utility tests

## [0.1.0] - 2025-01-XX

### Added
- **Encoding Engine**: Complete BlazeBinaryEncoder with support for all primitive types
  - Varint encoding (LEB128) for integers
  - Zigzag encoding for signed integers
  - Fixed-width little-endian encoding for UInt32, UInt64, Double
  - Length-prefixed encoding for String and Data
  - Array encoding with varint count prefix
  - Optional encoding with bool flag

- **Decoding Engine**: Complete BlazeBinaryDecoder with strict validation
  - Bounds checking on all reads
  - Varint decoding with overflow protection
  - UTF-8 validation for strings
  - Zero-copy decoding for Data fields
  - Size limit enforcement (configurable maxAllowedLength)

- **Frame Protocol**: Transport framing for network communication
  - Frame encoding with 4-byte big-endian length prefix
  - Incremental frame parsing for streaming protocols
  - Frame type support (handshake, operation, encrypted data)
  - Size limits: 5MB frame, 10MB buffer

- **Type System**: Protocol-based encoding/decoding
  - BlazeBinaryEncodable protocol
  - BlazeBinaryDecodable protocol
  - BlazeBinaryCodable typealias
  - Foundation type conformances (CGPoint, CGRect, Array, Dictionary)

- **Error Handling**: Comprehensive error types
  - BlazeBinaryError enum with specific error cases
  - Fail-fast error handling
  - Clear error messages

- **Documentation**: Complete specification and guides
  - RFC-style SPECIFICATION.md
  - ARCHITECTURE.md with system design
  - ENCODING_MODEL.md with encoding strategies
  - FRAME_PROTOCOL.md with handshake state machine
  - THREAT_MODEL.md with security analysis
  - BENCHMARKS.md with performance data
  - ROADMAP.md with development plans

- **Testing**: Comprehensive test suite
  - Unit tests for all encoding/decoding operations
  - Round-trip tests for determinism
  - Boundary condition tests
  - Fuzz-style tests for malformed input
  - Frame protocol tests
  - Cross-platform compatibility tests

- **Examples**: Usage examples and demos
  - EncoderDemo.swift
  - DecoderDemo.swift
  - FrameDemo.swift

- **CI/CD**: GitHub Actions workflow
  - macOS and Linux builds
  - Automated testing
  - Documentation validation

### Security
- Strict bounds checking prevents buffer overflows
- Size limits prevent resource exhaustion
- Deterministic encoding enables content addressing
- Memory safety through Swift's type system

### Performance
- 3-4x faster encoding/decoding than JSON
- 67% smaller encoded size than JSON
- Zero-copy decoding for Data fields
- Optimized varint encoding for small integers

---

## Version History

- **0.1.0**: Initial public release

