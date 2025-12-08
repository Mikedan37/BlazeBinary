# BlazeBinary Documentation Index

_Last updated: February 2025_  
_Protocol Version: v1.3.0_

BlazeBinary is a deterministic binary encoding format and transport framing protocol designed for high-performance distributed systems. It provides compact binary representation, guaranteed determinism (same input → same bytes), and cross-platform compatibility.

## Documentation Structure

Documentation is organized into the following categories:

- **[Core](Core/)** - Protocol specifications, architecture, and core concepts
- **[Security](Security/)** - Security documentation, threat models, and reviews
- **[Crypto](Crypto/)** - Cryptographic protocols and secure sessions
- **[Performance](Performance/)** - Benchmarks, fuzzing, and performance tracking
- **[Examples](Examples/)** - Usage examples and patterns
- **[Diagrams](Diagrams/)** - Mermaid diagram source files

---

## Core Documentation

### Protocol Specifications

- **[SPECIFICATION_v1.3.md](Core/SPECIFICATION_v1.3.md)** – **FROZEN** Protocol v1.3 specification. Production-ready, spec-frozen release candidate. Defines encoding rules, frame protocol v2.0, secure sessions, and all normative requirements.

- **[SPECIFICATION.md](Core/SPECIFICATION.md)** – General specification (may be updated for future versions). For v1.3, see SPECIFICATION_v1.3.md.

- **[API_STABILITY.md](Core/API_STABILITY.md)** – API stability guarantees for Protocol v1.3. Defines which APIs are stable, experimental, or internal.

- **[VERSIONING.md](Core/VERSIONING.md)** – Semantic versioning policy. Defines MAJOR.MINOR.PATCH versioning rules and compatibility guarantees.

### Architecture & Design

- **[ARCHITECTURE.md](Core/ARCHITECTURE.md)** – Internal layering and implementation structure. Describes the component breakdown, data flow, and design decisions behind the BlazeBinary implementation.

- **[ENCODING_MODEL.md](Core/ENCODING_MODEL.md)** – Detailed explanation of the type system, field encoding strategies, and optimization techniques. Describes how different Swift types are encoded into binary format.

- **[FRAME_PROTOCOL.md](Core/FRAME_PROTOCOL.md)** – Frame structure and handshake flow documentation. Covers the frame header format, frame types, incremental parsing, and state machine for network transport.

- **[FAILURE_SEMANTICS.md](Core/FAILURE_SEMANTICS.md)** – Failure modes and error handling behavior. Defines how BlazeBinary responds to malformed frames, authentication failures, replay attacks, and other error conditions.

### Reference & Utilities

- **[RATIONALE.md](Core/RATIONALE.md)** – Explanation of why BlazeBinary exists in the presence of JSON, CBOR, MessagePack, Protobuf, etc. Includes design goals, comparisons, design philosophy, and positioning within the Blaze ecosystem.

- **[ROADMAP.md](Core/ROADMAP.md)** – Future work and planned enhancements. Outlines upcoming features, cross-language implementations, and tooling improvements.

- **[CROSS_LANGUAGE_DECODER.md](Core/CROSS_LANGUAGE_DECODER.md)** – Guide for implementing BlazeBinary decoders in other languages (Rust, Go, Python, JavaScript). Includes decoding algorithms, type mappings, and implementation checklist. **Future work**.

- **[HEXDUMP.md](Core/HEXDUMP.md)** – Hex dump utilities for debugging and inspecting binary data. Includes usage examples and integration with tests.

- **[ZERO_COPY_DECODING.md](Core/ZERO_COPY_DECODING.md)** – Experimental zero-copy struct decoding API. Direct memory mapping for fixed-width structs with safety guarantees.

- **[ProductionSafetyProfile.md](Core/ProductionSafetyProfile.md)** – Production safety guarantees and error handling.

- **[FaultToleranceChecklist.md](Core/FaultToleranceChecklist.md)** – Engineering audit checklist.

---

## Developer Documentation

- **[ARCHITECTURE.md](Core/ARCHITECTURE.md)** – System architecture and component design
- **[ENCODING_MODEL.md](Core/ENCODING_MODEL.md)** – Type system and encoding details
- **[FRAME_PROTOCOL.md](Core/FRAME_PROTOCOL.md)** – Frame format and incremental parsing
- **[RATIONALE.md](Core/RATIONALE.md)** – Design rationale and comparisons
- **[ROADMAP.md](Core/ROADMAP.md)** – Future work and enhancements
- **[CROSS_LANGUAGE_DECODER.md](Core/CROSS_LANGUAGE_DECODER.md)** – Cross-language implementation guide
- **[HEXDUMP.md](Core/HEXDUMP.md)** – Hex dump utilities
- **[ZERO_COPY_DECODING.md](Core/ZERO_COPY_DECODING.md)** – Zero-copy decoding API

---

## Performance & Testing

- **[BENCHMARKS.md](Performance/BENCHMARKS.md)** – Performance results and methodology. Includes comparisons with JSON, CBOR, and MessagePack, along with encoding/decoding throughput measurements, percentiles, and performance charts.

- **[FUZZING.md](Performance/FUZZING.md)** – Fuzzing infrastructure and strategies. Documents fuzzing targets, corpus seeds, crash reproducers, and fuzzing best practices for Protocol v1.3.

- **[PERFORMANCE_TRACKING.md](Performance/PERFORMANCE_TRACKING.md)** – Performance tracking infrastructure. Documents CI/CD integration, regression detection, and performance history.

---

## Security Documentation

- **[SECURITY.md](Security/SECURITY.md)** – Comprehensive security documentation. Includes cryptographic protocols, security guarantees, attack surfaces, and best practices.

- **[SECURITY_REVIEW.md](Security/SECURITY_REVIEW.md)** – Comprehensive security review for Protocol v1.3. Documents cryptographic primitives (X25519, HKDF-SHA256, ChaCha20-Poly1305), security assumptions, guarantees, and attack mitigations.

- **[THREAT_MODEL.md](Security/THREAT_MODEL.md)** – Comprehensive threat model identifying attack surfaces, potential vulnerabilities, and mitigations. Covers malformed records, buffer overflows, and security guarantees.

---

## Examples

- **[ProtocolExamples.md](Examples/ProtocolExamples.md)** – Real-world usage examples and patterns. Demonstrates common use cases and best practices.

---

## Diagrams

The `[Diagrams](Diagrams/)` directory contains Mermaid.js diagram source files referenced by the documentation:

- `blaze_record.mmd` – Record structure diagram
- `field_encoding.mmd` – Field encoding flow
- `frame_flow.mmd` – Frame processing flow
- `handshake_state_machine.mmd` – Handshake protocol state machine
- `crc_flow.mmd` – CRC32 integrity checking flow
- `buffer_layout.mmd` – Buffer memory layout

---

## Archive

Historical and internal audit documents are archived in `[Archive/](Archive/)`. For current documentation, see the sections above.

- **[AUDIT_ARCHIVE_NOTES.md](Archive/AUDIT_ARCHIVE_NOTES.md)** – Overview of archived documents and protocol evolution timeline

---

## Suggested Reading Order

For new users and contributors, we recommend reading the documentation in this order:

1. **[README.md](../README.md)** – Start here for an overview of BlazeBinary, its features, and quickstart examples.

2. **[SPECIFICATION_v1.3.md](Core/SPECIFICATION_v1.3.md)** – Understand the frozen Protocol v1.3 specification.

3. **[ENCODING_MODEL.md](Core/ENCODING_MODEL.md)** – Learn how different types are encoded, including optimizations and encoding strategies.

4. **[FRAME_PROTOCOL.md](Core/FRAME_PROTOCOL.md)** – Understand the frame-based transport protocol for network communication.

5. **[ARCHITECTURE.md](Core/ARCHITECTURE.md)** – Explore the internal implementation structure and design decisions.

6. **[THREAT_MODEL.md](Security/THREAT_MODEL.md)** and **[BENCHMARKS.md](Performance/BENCHMARKS.md)** – Review security considerations and performance characteristics.

7. **[RATIONALE.md](Core/RATIONALE.md)** – Understand the design decisions and how BlazeBinary compares to other formats.

---

## Additional Resources

- **[SECURITY.md](../SECURITY.md)** – Security policy and responsible disclosure process
- **[CONTRIBUTING.md](../CONTRIBUTING.md)** – Guidelines for contributing to BlazeBinary
- **[CHANGELOG.md](../CHANGELOG.md)** – Version history and changes
- **[RELEASE.md](../RELEASE.md)** – Release notes and process
- **[Issues.md](../Issues.md)** – Known issues and feature requests

---

## Tools

- **[blaze CLI](../Tools/blaze/)** – Minimal preview CLI tool for encoding JSON to BlazeBinary format. Full functionality will be released in a later minor version.

---

## Related Documents

- [Specification](Core/SPECIFICATION_v1.3.md)
- [Architecture](Core/ARCHITECTURE.md)
- [Encoding Model](Core/ENCODING_MODEL.md)
- [Frame Protocol](Core/FRAME_PROTOCOL.md)
- [Security Review](Security/SECURITY_REVIEW.md)
- [Performance Tracking](Performance/PERFORMANCE_TRACKING.md)
