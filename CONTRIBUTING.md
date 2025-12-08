# Contributing to BlazeBinary

Thank you for your interest in contributing to BlazeBinary! This document provides guidelines for contributing.

## Code of Conduct

- Be respectful and inclusive
- Focus on constructive feedback
- Follow the project's coding standards

## How to Contribute

### Reporting Issues

1. Check if the issue already exists
2. Use clear, descriptive titles
3. Include steps to reproduce
4. Provide expected vs actual behavior
5. Include Swift version and platform information

### Submitting Pull Requests

1. **Fork the repository**
2. **Create a feature branch**: `git checkout -b feature/your-feature-name`
3. **Make your changes**
4. **Add tests**: All new features must include tests
5. **Update documentation**: Update relevant docs if needed
6. **Run tests**: `swift test`
7. **Commit changes**: Use clear, descriptive commit messages
8. **Push to your fork**: `git push origin feature/your-feature-name`
9. **Open a Pull Request**: Provide a clear description

### Pull Request Guidelines

- **Keep PRs focused**: One feature or fix per PR
- **Write tests**: New code must have test coverage
- **Update docs**: Update relevant documentation
- **Follow style**: Match existing code style
- **Pass CI**: All CI checks must pass

## Code Style

### Swift Style

- Follow Swift API Design Guidelines
- Use meaningful variable names
- Add documentation comments for public APIs
- Keep functions focused and small
- Use `@inlinable` for hot paths

### Example

```swift
/// Encodes a value using varint encoding.
/// - Parameter value: The value to encode
@inlinable
public func encode(_ value: Int) {
    // Implementation
}
```

## Testing Requirements

### Test Coverage

- All new features must include tests
- Edge cases must be tested
- Error conditions must be tested
- Round-trip tests for encoding/decoding

### Running Tests

```bash
swift test
```

### Test Structure

```swift
import Testing
import Foundation
@testable import BlazeBinary

@Test func testFeature() throws {
    // Arrange
    let value = ...
    
    // Act
    let result = ...
    
    // Assert
    #expect(result == expected)
}
```

## Documentation

### Code Documentation

- Public APIs must have documentation comments
- Use Swift documentation comment format
- Include parameter descriptions
- Include return value descriptions
- Include throwing behavior

### Example

```swift
/// Encodes a string value.
/// - Parameter value: The string to encode
/// - Note: Strings are encoded as UTF-8 with varint length prefix
public func encode(_ value: String) {
    // Implementation
}
```

## Issue Reporting

### Bug Reports

Include:
- Swift version
- Platform (macOS/iOS/Linux)
- Steps to reproduce
- Expected behavior
- Actual behavior
- Error messages (if any)

### Feature Requests

Include:
- Use case description
- Proposed API (if applicable)
- Alternatives considered
- Impact assessment

## Development Setup

1. Clone the repository
2. Open in Xcode or use Swift Package Manager
3. Run tests: `swift test`
4. Build: `swift build`

## Questions?

- Open a GitHub issue for questions
- Check existing documentation first
- Review open issues and PRs

Thank you for contributing to BlazeBinary!

