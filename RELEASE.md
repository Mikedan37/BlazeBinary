# Release Preparation Guide

This document provides guidance for creating release tags for BlazeBinary.

## Checklist for Tagging v1.3.0

Before creating a release tag, ensure:

- [x] All tests pass on macOS and Linux
- [x] README updated with v1.3 features
- [x] Docs index created and verified
- [x] All documentation links working
- [x] CI passing
- [x] License headers present
- [x] Protocol v1.3 specification frozen
- [x] API stability documented
- [x] Performance benchmarks complete
- [x] Fuzzing infrastructure in place
- [x] Security review complete

Before creating a release tag, ensure:

- [x] All tests pass on macOS and Linux
- [x] README updated
- [x] Docs index created
- [x] RATIONALE.md added
- [x] Determinism & corruption tests added
- [x] CI passing
- [x] License headers present

### Additional Pre-Release Checks

- [x] Build succeeds on macOS: `swift build`
- [x] Build succeeds on Linux: `swift build` (via CI)
- [x] All tests pass: `swift test`
- [x] Documentation is up to date
- [x] CHANGELOG.md is updated
- [x] Version number is correct in Package.swift
- [x] No build artifacts in repository (check .gitignore)
- [x] All license headers are present in source files
- [x] Zigzag encoding handles all edge cases (Int.min, Int.max, boundary values)
- [x] Alignment issues resolved (no misaligned pointer crashes)
- [x] All test suites passing (VarintTests, FuzzTests, DeterminismTests, CorruptionTests, etc.)

## Creating a Release Tag

### For v1.3.0 Release (Production-Ready)

```bash
# Ensure you're on the main branch with latest changes
git checkout main
git pull origin main

# Verify everything is clean
git status

# Create annotated tag
git tag -a v1.3.0 -m "BlazeBinary v1.3.0 - Production-Ready Release

Protocol v1.3.0 is FROZEN and production-ready.

Features:
- Deterministic binary encoding/decoding
- Secure Session Mode (X25519 + ChaCha20-Poly1305)
- Frame protocol with compression
- Comprehensive test suite
- Full documentation
- Performance benchmarks
- Fuzzing infrastructure
- Security review complete

See CHANGELOG.md for complete details."

# Push tag to remote
git push origin v1.3.0
```

### For Patch Release (v0.1.1)

```bash
git tag -a v0.1.1 -m "Patch release

- Bug fixes
- Documentation updates"

git push origin v0.1.1
```

### For Minor Release (v0.2.0)

```bash
git tag -a v0.2.0 -m "Minor release

- New features
- Performance improvements
- Additional type conformances"

git push origin v0.2.0
```

## Semantic Versioning

BlazeBinary follows [Semantic Versioning](https://semver.org/):

- **MAJOR** (X.0.0): Breaking changes
- **MINOR** (0.X.0): New features, backward compatible
- **PATCH** (0.0.X): Bug fixes, backward compatible

## Release Notes Template

When creating a GitHub release, use this template:

```markdown
## BlazeBinary v1.3.0 - Production-Ready Release

**Protocol v1.3.0 is FROZEN** - This is the production-ready release candidate.

### Added
- Protocol v1.3.0 specification (FROZEN)
- Secure Session Mode (X25519 + ChaCha20-Poly1305)
- Comprehensive test suite (unit, integration, fuzz, property tests)
- Performance benchmarks with percentile tracking
- Fuzzing infrastructure
- Complete documentation reorganization
- API stability guarantees
- Failure semantics documentation
- Security review

### Changed
- Documentation structure reorganized for clarity
- Performance tracking infrastructure
- Enhanced error handling taxonomy

### Security
- Comprehensive security review
- Threat model documentation
- Secure session mode with authenticated encryption
- Strict bounds checking
- Size limit enforcement
- Memory safety guarantees

### Documentation
- Frozen Protocol v1.3 specification
- Complete API stability documentation
- Performance benchmarks and tracking
- Fuzzing strategies and infrastructure
- Security review and threat model

### Performance
- 4.1M ops/sec varint encoding
- 275K ops/sec data encoding (1KB)
- 12K ops/sec AEAD encryption (1KB)
- Comprehensive benchmark suite

See [CHANGELOG.md](CHANGELOG.md) for complete details.
```

## Post-Release

After creating a release:

1. Update CHANGELOG.md with release date
2. Create GitHub release with release notes
3. Announce release (if applicable)
4. Monitor for issues

## Version History

- **v1.3.0**: Production-Ready Release (2025-02-XX)
  - Protocol v1.3.0 FROZEN
  - Complete production readiness audit
  - Comprehensive documentation
  - Performance benchmarks
  - Fuzzing infrastructure
  - Security review
  - See [CHANGELOG.md](CHANGELOG.md) for details

- **v1.2.0**: Secure Session Mode (2025-02-XX)
  - X25519 Diffie-Hellman handshake
  - HKDF-SHA256 key derivation
  - ChaCha20-Poly1305 encrypted frames
  - Full backwards compatibility
  - See [CHANGELOG.md](CHANGELOG.md) for details

- **v0.1.0**: Initial public release (2025-01-XX)

