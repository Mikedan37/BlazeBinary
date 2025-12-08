//
// BlazeBinaryError.swift
// BlazeBinary
//
// Copyright (c) 2025 Michael Danylchuk
// MIT License
//

import Foundation

/// Errors that can occur during BlazeBinary encoding or decoding operations.
public enum BlazeBinaryError: Error, Equatable {
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
    
    // MARK: - Encryption Errors
    
    /// Handshake operation failed
    case handshakeFailed(String)
    
    /// Invalid handshake message format
    case invalidHandshake(String)
    
    /// Encryption/decryption operation failed
    case encryptionFailed(String)
    
    /// Invalid encryption key or session state
    case invalidSession(String)
    
    public static func == (lhs: BlazeBinaryError, rhs: BlazeBinaryError) -> Bool {
        switch (lhs, rhs) {
        case (.truncated, .truncated),
             (.invalidVarint, .invalidVarint),
             (.invalidFrameLength, .invalidFrameLength),
             (.oversizedFrame, .oversizedFrame),
             (.needMoreData, .needMoreData):
            return true
        case (.decodeFailed(let lhsMsg), .decodeFailed(let rhsMsg)),
             (.handshakeFailed(let lhsMsg), .handshakeFailed(let rhsMsg)),
             (.invalidHandshake(let lhsMsg), .invalidHandshake(let rhsMsg)),
             (.encryptionFailed(let lhsMsg), .encryptionFailed(let rhsMsg)),
             (.invalidSession(let lhsMsg), .invalidSession(let rhsMsg)):
            return lhsMsg == rhsMsg
        default:
            return false
        }
    }
}

