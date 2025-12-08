# BlazeBinary Semantic Versioning Policy

_Last updated: February 2025 (Protocol v1.3)_

## Version Format

BlazeBinary uses [Semantic Versioning 2.0.0](https://semver.org/): `MAJOR.MINOR.PATCH`

- **MAJOR**: Breaking changes (v2.0, v3.0, ...)
- **MINOR**: New features, backwards compatible (v1.4, v1.5, ...)
- **PATCH**: Bug fixes only (v1.3.1, v1.3.2, ...)

## Version Components

### Protocol Version

The **protocol version** defines the on-wire format:
- **v1.3**: Current frozen protocol
- Encoded in frame headers and handshake messages
- Backwards compatible with v1.0, v1.1, v1.2

### Library Version

The **library version** (Package.swift) tracks API and implementation:
- May increment independently of protocol version
- Follows semantic versioning rules

## Version Compatibility Matrix

| Library Version | Protocol Version | Decodes | Encodes |
|----------------|------------------|---------|---------|
| v1.3.0 | v1.3 | v1.0, v1.1, v1.2, v1.3 | v1.0, v1.1, v1.2, v1.3 |
| v1.2.0 | v1.2 | v1.0, v1.1, v1.2 | v1.0, v1.1, v1.2 |
| v1.1.0 | v1.1 | v1.0, v1.1 | v1.0, v1.1 |
| v1.0.0 | v1.0 | v1.0 | v1.0 |

## Breaking Changes (MAJOR)

Breaking changes require a MAJOR version bump:

1. **API Removal**: Removing public APIs
2. **Signature Changes**: Changing method signatures incompatibly
3. **On-Wire Format**: Breaking changes to binary encoding
4. **Frame Protocol**: Breaking changes to frame format
5. **Error Types**: Removing or changing error cases

**Example**: v2.0 might change frame format or remove deprecated APIs.

## Non-Breaking Changes (MINOR)

Non-breaking additions in MINOR versions:

1. **New APIs**: Adding new methods, types, enum cases
2. **Optional Parameters**: Adding optional parameters with defaults
3. **New Error Cases**: Adding new error cases (existing code still works)
4. **Performance**: Performance improvements
5. **New Features**: New optional features (encryption, compression, etc.)

**Example**: v1.4 might add new convenience methods or optional features.

## Bug Fixes (PATCH)

Patch versions contain only bug fixes:

1. **Bug Fixes**: Fixing incorrect behavior
2. **Security Fixes**: Security vulnerability patches
3. **Performance Fixes**: Fixing performance regressions
4. **Documentation**: Documentation corrections

**No**:
- API changes
- On-wire format changes
- New features

**Example**: v1.3.1 fixes a varint decoding bug.

## Deprecation Policy

1. **Deprecation Period**: APIs marked deprecated for at least one MINOR version
2. **Warnings**: Deprecation warnings include migration guidance
3. **Removal**: Deprecated APIs removed in next MAJOR version

**Example**:
- v1.3: API marked deprecated
- v1.4: Still available, shows warning
- v2.0: Removed

## Protocol Versioning

### Protocol v1.3 (FROZEN)

**Status**: FROZEN - No changes except bug fixes

**Features**:
- Varint encoding (LEB128)
- Zigzag encoding
- Schema versioning
- Frame protocol v2.0
- Compression (LZ4, LZFSE)
- Secure sessions (X25519, ChaCha20-Poly1305)

**Future Protocol Versions**:
- v2.0: May introduce breaking changes
- v1.4+: May add optional features (backwards compatible)

## Migration Guide

### Upgrading Between Versions

#### Patch Versions (v1.3.0 → v1.3.1)

**No changes required**:
- Drop-in replacement
- Same APIs, same behavior
- Bug fixes only

#### Minor Versions (v1.3 → v1.4)

**Review CHANGELOG.md**:
- New APIs may be available
- Optional new features
- No breaking changes
- Existing code continues to work

#### Major Versions (v1.3 → v2.0)

**Migration required**:
- Review breaking changes in release notes
- Update code for API changes
- Test thoroughly
- May require protocol version upgrade

## Version Detection

### Runtime Version

```swift
// Library version (from Package.swift)
let libraryVersion = "1.3.0"

// Protocol version (from frame/handshake)
let protocolVersion: UInt32 = 1 // From handshake message
```

### Schema Version

```swift
let decoder = BlazeBinaryDecoder(data: data)
let schemaVersion = decoder.version // Detected from data
```

## Examples

### ✅ Safe Upgrades

```swift
// v1.3.0 → v1.3.1 (patch)
// No code changes needed

// v1.3.0 → v1.4.0 (minor)
// Can use new APIs, but not required
// Existing code works unchanged
```

### ⚠️ Requires Migration

```swift
// v1.3.0 → v2.0.0 (major)
// Review breaking changes
// Update code for new APIs
// Test thoroughly
```

## Version History

| Version | Protocol | Date | Status |
|---------|----------|------|--------|
| v1.3.0 | v1.3 | 2025-02 | FROZEN |
| v1.2.0 | v1.2 | 2025-02 | Stable |
| v1.1.0 | v1.1 | 2025-01 | Stable |
| v1.0.0 | v1.0 | 2025-01 | Stable |

---

**Related Documents**:
- [API_STABILITY.md](API_STABILITY.md) - API stability guarantees
- [SPECIFICATION_v1.3.md](SPECIFICATION_v1.3.md) - Protocol specification
- [CHANGELOG.md](../CHANGELOG.md) - Version history

