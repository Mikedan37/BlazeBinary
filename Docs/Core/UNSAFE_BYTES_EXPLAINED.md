# Understanding `withUnsafeBytes` and Buffer Access in Swift

_Last updated: December 2025_  
_Protocol Version: v1.3.0_

## Overview

Swift's `Data` type provides a safe, high-level interface for working with binary data. However, when you need to read or write raw bytes (for performance or interoperability), you need to access the underlying memory buffer. This document explains how `withUnsafeBytes` works and why we use it in BlazeBinary.

---

## What is `withUnsafeBytes`?

`withUnsafeBytes` is a method on `Data` (and other types like `Array`, `String`, etc.) that gives you temporary, read-only access to the underlying raw memory buffer as a pointer to bytes.

### Basic Syntax

```swift
let data = Data([0x01, 0x02, 0x03, 0x04])

let result = data.withUnsafeBytes { bytes -> ReturnType in
    // 'bytes' is a UnsafeRawBufferPointer
    // You can access bytes[0], bytes[1], etc.
    // Do your work here
    return someValue
}
```

### Key Characteristics

1. **Temporary Access**: The closure is the only place where you can safely access the buffer. Once the closure returns, the pointer becomes invalid.

2. **Read-Only**: By default, `withUnsafeBytes` gives you read-only access. For write access, you'd use `withUnsafeMutableBytes`.

3. **Bounds Checking**: You must check `bytes.count` before accessing indices. The buffer might be smaller than you expect.

4. **No Memory Management**: Swift manages the memory lifecycle. You don't need to allocate or deallocate anything.

---

## Why Use `withUnsafeBytes` Instead of Direct Access?

### Problem: Direct Subscript Access Can Crash

```swift
// UNSAFE - Can crash on Linux or with certain Data representations
let byte = buffer[0]  // Might crash if buffer is empty or in certain states
let subdata = buffer.subdata(in: 2..<6)  // Can crash with invalid ranges
```

**Why it crashes:**
- `Data` can have different internal representations (contiguous vs. non-contiguous)
- On Linux, `Data` subscript access is stricter and can crash with invalid indices
- `subdata` creates a new `Data` object, which can fail if the range is invalid or the Data is in a certain state

### Solution: Use `withUnsafeBytes`

```swift
// Met SAFE - Always bounds-checked
let byte = buffer.withUnsafeBytes { bytes -> UInt8 in
    guard bytes.count >= 1 else {
        return 0xFF  // Sentinel value for error
    }
    return bytes[0]
}
```

**Why it's safer:**
- Direct access to the underlying memory buffer
- You control the bounds checking
- Works consistently across platforms (macOS, Linux, iOS)
- No intermediate `Data` object creation

---

## How Buffers Work in Swift

### Memory Layout

When you create a `Data` object:

```swift
let data = Data([0x01, 0x02, 0x03, 0x04])
```

Swift stores this in memory as a contiguous sequence of bytes:

```
Memory Address:  [0x1000] [0x1001] [0x1002] [0x1003]
Value:           0x01     0x02     0x03     0x04
Index:            [0]      [1]      [2]      [3]
```

### `UnsafeRawBufferPointer`

When you call `withUnsafeBytes`, Swift gives you an `UnsafeRawBufferPointer`:

```swift
data.withUnsafeBytes { bytes in
    // 'bytes' is UnsafeRawBufferPointer
    // bytes.baseAddress - pointer to first byte
    // bytes.count - number of bytes
    // bytes[index] - access byte at index
}
```

**Important**: This is a "raw" pointer, meaning it points to untyped memory (just bytes). You can read it as any type, but you must be careful about alignment and endianness.

---

## Real Example from BlazeBinary

### Reading a Big-Endian UInt32

In BlazeBinary, we need to read a 4-byte big-endian integer from bytes 2-5 of a frame:

```swift
// OLD WAY - Using subdata (can crash)
let lengthBytes = buffer.subdata(in: 2..<6)  // Creates new Data object
let length = lengthBytes.withUnsafeBytes { bytes in
    var value: UInt32 = 0
    value |= UInt32(bytes[0]) << 24
    value |= UInt32(bytes[1]) << 16
    value |= UInt32(bytes[2]) << 8
    value |= UInt32(bytes[3])
    return value
}
```

**Problems:**
1. `subdata` can crash if buffer is in certain states
2. Creates unnecessary intermediate `Data` object
3. Two `withUnsafeBytes` calls (inefficient)

```swift
// Met NEW WAY - Direct access (safe and efficient)
let length = buffer.withUnsafeBytes { bytes -> UInt32 in
    guard bytes.count >= 6 else {
        return UInt32(0)  // Not enough data
    }
    var value: UInt32 = 0
    value |= UInt32(bytes[2]) << 24  // Read directly from buffer
    value |= UInt32(bytes[3]) << 16
    value |= UInt32(bytes[4]) << 8
    value |= UInt32(bytes[5])
    return value
}
```

**Benefits:**
1. Direct access - no intermediate objects
2. Single `withUnsafeBytes` call
3. Explicit bounds checking
4. Works consistently across platforms

---

## Reading Multiple Bytes Safely

### Pattern: Read Two Bytes

```swift
let (byte0, byte1) = buffer.withUnsafeBytes { bytes -> (UInt8, UInt8) in
    guard bytes.count >= 2 else {
        return (0xFF, 0xFF)  // Sentinel values for error
    }
    return (bytes[0], bytes[1])
}

// Check for error
guard byte0 != 0xFF && byte1 != 0xFF else {
    throw BlazeBinaryError.decodeFailed("Invalid buffer state")
}
```

### Pattern: Read with Validation

```swift
let frameType = buffer.withUnsafeBytes { bytes -> UInt8 in
    guard bytes.count >= 1 else {
        return 0xFF  // Invalid sentinel
    }
    return bytes[0]
}

guard frameType != 0xFF else {
    return nil  // Invalid buffer
}
```

---

## Endianness and Byte Ordering

### Big-Endian (Network Byte Order)

In BlazeBinary, we use big-endian for frame lengths:

```swift
// Bytes: [0x00, 0x00, 0x01, 0x00] = 256 in big-endian
let value = buffer.withUnsafeBytes { bytes -> UInt32 in
    guard bytes.count >= 4 else { return 0 }
    var result: UInt32 = 0
    result |= UInt32(bytes[0]) << 24  // Most significant byte first
    result |= UInt32(bytes[1]) << 16
    result |= UInt32(bytes[2]) << 8
    result |= UInt32(bytes[3])
    return result
}
```

**Why big-endian?**
- Network protocols typically use big-endian
- Consistent across different CPU architectures
- Easier to debug (human-readable in hex dumps)

### Little-Endian Alternative

If you needed little-endian:

```swift
result |= UInt32(bytes[0])
result |= UInt32(bytes[1]) << 8
result |= UInt32(bytes[2]) << 16
result |= UInt32(bytes[3]) << 24  // Least significant byte first
```

---

## Safety Best Practices

### 1. Always Bounds Check

```swift
// BAD
let byte = buffer.withUnsafeBytes { bytes in
    return bytes[0]  // Can crash if bytes.count == 0
}

// Met GOOD
let byte = buffer.withUnsafeBytes { bytes -> UInt8 in
    guard bytes.count >= 1 else {
        return 0xFF  // Sentinel value
    }
    return bytes[0]
}
```

### 2. Use Sentinel Values

```swift
// Return invalid sentinel values for error cases
guard bytes.count >= 2 else {
    return (0xFF, 0xFF)  // Invalid - check this after closure
}
```

### 3. Validate After Access

```swift
let (byte0, byte1) = buffer.withUnsafeBytes { ... }
guard byte0 != 0xFF && byte1 != 0xFF else {
    // Handle error
    return nil
}
```

### 4. Don't Store Pointers

```swift
// BAD - Pointer becomes invalid after closure
let pointer = buffer.withUnsafeBytes { $0.baseAddress }
let byte = pointer?.load(as: UInt8.self)  // CRASH! Pointer is invalid

// Met GOOD - Do all work inside closure
let byte = buffer.withUnsafeBytes { bytes -> UInt8 in
    guard bytes.count >= 1 else { return 0 }
    return bytes[0]
}
```

---

## Performance Considerations

### Why `withUnsafeBytes` is Fast

1. **No Copying**: Direct access to underlying memory
2. **No Allocation**: No intermediate objects created
3. **Compiler Optimization**: Swift can optimize the closure heavily
4. **Cache Friendly**: Sequential memory access patterns

### When to Use

- Reading binary formats (like BlazeBinary frames)
- Converting between byte representations
- Performance-critical code paths
- Interfacing with C APIs

### When NOT to Use

- Simple operations that `Data` handles well (e.g., `data.append()`)
- When you don't need the performance
- If you're not comfortable with bounds checking

---

## Common Patterns in BlazeBinary

### Pattern 1: Read Fixed-Size Value

```swift
// Read 4-byte big-endian UInt32
let value = buffer.withUnsafeBytes { bytes -> UInt32 in
    guard bytes.count >= 4 else { return 0 }
    var result: UInt32 = 0
    result |= UInt32(bytes[0]) << 24
    result |= UInt32(bytes[1]) << 16
    result |= UInt32(bytes[2]) << 8
    result |= UInt32(bytes[3])
    return result
}
```

### Pattern 2: Read Multiple Bytes with Validation

```swift
// Read two bytes with error handling
let (byte0, byte1) = buffer.withUnsafeBytes { bytes -> (UInt8, UInt8) in
    guard bytes.count >= 2 else {
        return (0xFF, 0xFF)
    }
    return (bytes[0], bytes[1])
}
guard byte0 != 0xFF && byte1 != 0xFF else {
    return nil  // Error
}
```

### Pattern 3: Conditional Access

```swift
// Only read if buffer has enough data
guard buffer.count >= 6 else {
    return nil  // Need more data
}
let length = buffer.withUnsafeBytes { bytes -> UInt32 in
    // Safe to access bytes[2] through bytes[5]
    var value: UInt32 = 0
    value |= UInt32(bytes[2]) << 24
    value |= UInt32(bytes[3]) << 16
    value |= UInt32(bytes[4]) << 8
    value |= UInt32(bytes[5])
    return value
}
```

---

## Comparison: `subdata` vs `withUnsafeBytes`

### Using `subdata`

```swift
let subdata = buffer.subdata(in: 2..<6)  // Creates new Data object
let value = subdata.withUnsafeBytes { bytes in
    // Read from subdata
}
```

**Issues:**
- Can crash if range is invalid
- Creates intermediate `Data` object (allocation)
- Two-step process (less efficient)
- Platform-dependent behavior

### Using `withUnsafeBytes` Directly

```swift
let value = buffer.withUnsafeBytes { bytes -> UInt32 in
    guard bytes.count >= 6 else { return 0 }
    // Read directly from original buffer
    var result: UInt32 = 0
    result |= UInt32(bytes[2]) << 24
    // ...
    return result
}
```

**Benefits:**
- No intermediate objects
- Explicit bounds checking
- Single operation
- Consistent across platforms

---

## Summary

1. **`withUnsafeBytes`** gives you temporary, read-only access to raw memory
2. **Always bounds check** before accessing bytes
3. **Use sentinel values** to indicate errors
4. **Don't store pointers** outside the closure
5. **Direct access is safer** than `subdata` for fixed-size reads
6. **Platform consistent** - works the same on macOS, Linux, iOS

In BlazeBinary, we use `withUnsafeBytes` extensively for:
- Reading frame headers (frameType, compressionMode, length)
- Parsing varints (variable-length integers)
- Converting between byte representations
- Ensuring cross-platform compatibility

---

## Related Documents

- [Specification](SPECIFICATION_v1.3.md) - Protocol format details
- [Frame Protocol](FRAME_PROTOCOL.md) - Frame structure
- [Architecture](ARCHITECTURE.md) - Implementation details

