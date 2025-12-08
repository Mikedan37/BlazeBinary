# BlazeBinary Documentation Index

_Last updated: February 2025_

BlazeBinary is a deterministic binary encoding format and transport framing protocol designed for high-performance distributed systems. It provides compact binary representation, guaranteed determinism (same input → same bytes), and cross-platform compatibility.

## Documentation Overview

### Core Specifications

- **[SPECIFICATION.md](SPECIFICATION.md)** – Formal RFC-style specification for the on-wire format. Defines the encoding rules, type system, frame protocol, and normative requirements for implementations.

- **[ENCODING_MODEL.md](ENCODING_MODEL.md)** – Detailed explanation of the type system, field encoding strategies, and optimization techniques. Describes how different Swift types are encoded into binary format.

- **[FRAME_PROTOCOL.md](FRAME_PROTOCOL.md)** – Frame structure and handshake flow documentation. Covers the frame header format, frame types, incremental parsing, and state machine for network transport.

- **[ARCHITECTURE.md](ARCHITECTURE.md)** – Internal layering and implementation structure. Describes the component breakdown, data flow, and design decisions behind the BlazeBinary implementation.

### Security & Performance

- **[THREAT_MODEL.md](THREAT_MODEL.md)** – Comprehensive threat model identifying attack surfaces, potential vulnerabilities, and mitigations. Covers malformed records, buffer overflows, and security guarantees.

- **[BENCHMARKS.md](BENCHMARKS.md)** – Performance results and methodology. Includes comparisons with JSON, CBOR, and MessagePack, along with encoding/decoding throughput measurements.

### Design & Planning

- **[RATIONALE.md](RATIONALE.md)** – Explanation of why BlazeBinary exists in the presence of JSON, CBOR, MessagePack, Protobuf, etc. Includes design goals, comparisons, design philosophy, and positioning within the Blaze ecosystem.

- **[ROADMAP.md](ROADMAP.md)** – Future work and planned enhancements. Outlines upcoming features, cross-language implementations, and tooling improvements.

- **[CROSS_LANGUAGE_DECODER.md](CROSS_LANGUAGE_DECODER.md)** – Guide for implementing BlazeBinary decoders in other languages (Rust, Go, Python, JavaScript). Includes decoding algorithms, type mappings, and implementation checklist. **Future work**.

### Diagrams

The `DIAGRAMS/` directory contains Mermaid.js diagram source files referenced by the documentation:

- `blaze_record.mmd` – Record structure diagram
- `field_encoding.mmd` – Field encoding flow
- `frame_flow.mmd` – Frame processing flow
- `handshake_state_machine.mmd` – Handshake protocol state machine
- `crc_flow.mmd` – CRC32 integrity checking flow
- `buffer_layout.mmd` – Buffer memory layout

## Suggested Reading Order

For new users and contributors, we recommend reading the documentation in this order:

1. **[README.md](../README.md)** – Start here for an overview of BlazeBinary, its features, and quickstart examples.

2. **[SPECIFICATION.md](SPECIFICATION.md)** – Understand the formal encoding format, type system, and protocol requirements.

3. **[ENCODING_MODEL.md](ENCODING_MODEL.md)** – Learn how different types are encoded, including optimizations and encoding strategies.

4. **[FRAME_PROTOCOL.md](FRAME_PROTOCOL.md)** – Understand the frame-based transport protocol for network communication.

5. **[ARCHITECTURE.md](ARCHITECTURE.md)** – Explore the internal implementation structure and design decisions.

6. **[THREAT_MODEL.md](THREAT_MODEL.md)** and **[BENCHMARKS.md](BENCHMARKS.md)** – Review security considerations and performance characteristics.

7. **[RATIONALE.md](RATIONALE.md)** – Understand the design decisions and how BlazeBinary compares to other formats.

## Additional Resources

- **[SECURITY.md](../SECURITY.md)** – Security policy and responsible disclosure process
- **[CONTRIBUTING.md](../CONTRIBUTING.md)** – Guidelines for contributing to BlazeBinary
- **[CHANGELOG.md](../CHANGELOG.md)** – Version history and changes
- **[Issues.md](../Issues.md)** – Known issues and feature requests

## Tools

- **[blaze CLI](../Tools/blaze/)** – Minimal preview CLI tool for encoding JSON to BlazeBinary format. Full functionality will be released in a later minor version.

---

### Related Documents

- [Specification](SPECIFICATION.md)
- [Architecture](ARCHITECTURE.md)
- [Encoding Model](ENCODING_MODEL.md)
- [Frame Protocol](FRAME_PROTOCOL.md)

