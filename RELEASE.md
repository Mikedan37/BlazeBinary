# Release Preparation Guide

This document provides guidance for creating release tags for BlazeBinary.

## Checklist for Tagging v0.1.0

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

### For Initial Release (v0.1.0)

```bash
# Ensure you're on the main branch with latest changes
git checkout main
git pull origin main

# Verify everything is clean
git status

# Create annotated tag
git tag -a v0.1.0 -m "Initial public release of BlazeBinary

- Complete encoding/decoding engine
- Frame protocol support
- Comprehensive test suite
- Full documentation
- MIT License"

# Push tag to remote
git push origin v0.1.0
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
## BlazeBinary v0.1.0

### Added
- Complete encoding/decoding engine
- Frame protocol support
- Comprehensive test suite
- Full documentation

### Changed
- Initial public release

### Security
- Strict bounds checking
- Size limit enforcement
- Memory safety guarantees

### Documentation
- Complete specification (RFC-style)
- Architecture documentation
- Performance benchmarks
- Threat model analysis

See [CHANGELOG.md](CHANGELOG.md) for complete details.
```

## Post-Release

After creating a release:

1. Update CHANGELOG.md with release date
2. Create GitHub release with release notes
3. Announce release (if applicable)
4. Monitor for issues

## Version History

- **v0.1.0**: Initial public release (2025-01-XX)

