import Foundation

/// Errors that can occur during BlazeBinary encoding or decoding operations.
public enum BlazeBinaryError: Error {
    /// Data is truncated or incomplete
    case truncated
    
    /// Invalid varint encoding detected
    case invalidVarint
    
    /// Frame length prefix is invalid
    case invalidFrameLength
    
    /// Frame size exceeds maximum allowed (5 MB)
    case oversizedFrame
    
    /// Decoding operation failed with a specific reason
    case decodeFailed(String)
    
    /// More data is needed to complete the operation
    case needMoreData
}

