# Changelog

All notable changes to BlazeBinary will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Cross-language implementation roadmap
- Additional type conformances (CGPoint, CGRect, Dictionary)

### Changed
- Enhanced documentation structure
- Improved error messages

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

