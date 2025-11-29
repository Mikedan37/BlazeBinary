import Foundation

/// Frame encoder for IPC/socket communication.
public enum BlazeFrameEncoder {
    /// Maximum allowed frame size (5 MB)
    public static let maxFrameSize = 5 * 1024 * 1024
    
    /// Encodes a payload into a frame with big-endian length prefix.
    /// Format: <UInt32 lengthPrefix bigEndian> <binaryPayload>
    /// - Parameter payload: The binary payload to encode
    /// - Returns: The encoded frame data
    /// - Throws: `BlazeBinaryError.oversizedFrame` if payload exceeds maxFrameSize
    @inlinable
    public static func encodeFrame(_ payload: Data) throws -> Data {
        guard payload.count <= maxFrameSize else {
            throw BlazeBinaryError.oversizedFrame
        }
        
        var frame = Data()
        let length = UInt32(payload.count).bigEndian
        frame.append(contentsOf: withUnsafeBytes(of: length) { Data($0) })
        frame.append(payload)
        return frame
    }
}

/// Streaming frame parser for incremental frame decoding.
public class BlazeFrameParser {
    /// Maximum allowed buffer size (10 MB)
    public static let maxBufferSize = 10 * 1024 * 1024
    
    private var buffer: Data
    private let maxFrameSize: Int
    
    /// Creates a new frame parser.
    /// - Parameter maxFrameSize: Maximum allowed frame size (default: 5 MB)
    public init(maxFrameSize: Int = BlazeFrameEncoder.maxFrameSize) {
        self.buffer = Data()
        self.maxFrameSize = maxFrameSize
    }
    
    /// Appends data to the internal buffer and checks for buffer overflow.
    /// 
    /// This method is used for incremental frame parsing. Data can be appended
    /// in chunks as it arrives, and `nextFrame()` can be called to extract
    /// complete frames when available.
    /// 
    /// - Parameter data: The data to append to the internal buffer
    /// - Throws: `BlazeBinaryError.oversizedFrame` if appending would cause buffer to exceed maxBufferSize (10 MB)
    /// - Note: The buffer size is checked after appending. If the buffer exceeds the limit,
    ///   the error is thrown and the buffer state remains unchanged (the append is not applied).
    public func append(_ data: Data) throws {
        let newSize = buffer.count + data.count
        guard newSize <= Self.maxBufferSize else {
            throw BlazeBinaryError.oversizedFrame
        }
        buffer.append(data)
    }
    
    /// Attempts to extract the next complete frame from the buffer.
    /// 
    /// This method implements the frame parsing state machine:
    /// 1. If buffer has < 4 bytes: returns nil (need length prefix)
    /// 2. If length prefix is invalid (0 or > maxFrameSize): throws `BlazeBinaryError.invalidFrameLength`
    /// 3. If buffer has < 4 + length bytes: returns nil (need more payload data)
    /// 4. If frame is complete: extracts payload, removes frame from buffer, returns payload
    /// 
    /// - Returns: The frame payload if a complete frame is available, nil if more data is needed
    /// - Throws: `BlazeBinaryError.invalidFrameLength` if the length prefix is invalid (0 or exceeds maxFrameSize)
    /// - Note: This method never throws for partial frames. It only throws for invalid frame lengths.
    ///   Partial frames return nil, allowing the caller to append more data and try again.
    @inlinable
    public func nextFrame() throws -> Data? {
        // Need at least 4 bytes for length prefix
        guard buffer.count >= 4 else {
            return nil // Need more data
        }
        
        // Read length prefix (big-endian UInt32)
        let length = buffer.withUnsafeBytes { bytes in
            UInt32(bigEndian: bytes.load(as: UInt32.self))
        }
        
        let lengthInt = Int(length)
        
        // Validate frame length (must be > 0 and <= maxFrameSize)
        guard lengthInt > 0 else {
            throw BlazeBinaryError.invalidFrameLength
        }
        
        guard lengthInt <= maxFrameSize else {
            throw BlazeBinaryError.invalidFrameLength
        }
        
        // Check if we have the complete frame (4-byte header + payload)
        let totalFrameSize = 4 + lengthInt
        guard buffer.count >= totalFrameSize else {
            return nil // Need more data
        }
        
        // Extract frame payload (zero-copy slice)
        let payload = buffer.subdata(in: 4..<totalFrameSize)
        
        // Remove processed frame from buffer
        buffer.removeFirst(totalFrameSize)
        
        return payload
    }
    
    /// Returns the current buffer size in bytes.
    /// 
    /// This can be used to monitor buffer growth and ensure it stays within limits.
    /// - Returns: The number of bytes currently in the buffer
    public var bufferSize: Int {
        return buffer.count
    }
    
    /// Clears the internal buffer, resetting the parser to its initial state.
    /// 
    /// This is useful for resetting the parser after an error or when starting
    /// a new stream. After clearing, the parser is ready to accept new data via `append()`.
    public func clear() {
        buffer.removeAll()
    }
}

