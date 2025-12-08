//
//  ConnectionErrors.swift
//  BlazeBinary
//
//  Copyright (c) 2025 Michael Danylchuk
//  MIT License
//

import Foundation

/// Disconnect reasons for connection-level errors (similar to Noise Protocol).
public enum DisconnectReason: UInt8, Error, Equatable {
    /// No error (normal closure)
    case noError = 0x00
    
    /// Protocol violation
    case protocolError = 0x01
    
    /// Internal error
    case internalError = 0x02
    
    /// Cryptographic error (authentication failure, etc.)
    case cryptoError = 0x03
    
    /// Frame too large
    case frameTooLarge = 0x04
    
    /// Buffer overflow
    case bufferOverflow = 0x05
    
    /// Invalid handshake
    case invalidHandshake = 0x06
    
    /// Replay detected
    case replayDetected = 0x07
    
    /// Rate limit exceeded
    case rateLimitExceeded = 0x08
    
    /// Unsupported version
    case unsupportedVersion = 0x09
    
    /// Timeout
    case timeout = 0x0A
    
    /// Application-defined reason (0x10-0xFF)
    /// Use `applicationDefinedValue` to get the raw value
    case applicationDefined = 0x10
    
    /// Gets the raw value for application-defined reasons.
    /// For standard reasons, returns the case's rawValue.
    /// For application-defined (0x10-0xFF), returns the actual value.
    public func rawValue(forApplicationValue appValue: UInt8? = nil) -> UInt8 {
        if self == .applicationDefined, let value = appValue {
            return value
        }
        return self.rawValue
    }
    
    public static func == (lhs: DisconnectReason, rhs: DisconnectReason) -> Bool {
        return lhs.rawValue == rhs.rawValue
    }
}

/// Protocol-level errors for connection management.
public enum ProtocolError: Error, Equatable {
    /// Invalid frame format
    case invalidFrameFormat(String)
    
    /// Frame size violation
    case frameSizeViolation(actual: Int, max: Int)
    
    /// Buffer size violation
    case bufferSizeViolation(actual: Int, max: Int)
    
    /// Invalid frame type
    case invalidFrameType(UInt8)
    
    /// Unsupported protocol version
    case unsupportedVersion(UInt32)
    
    /// Handshake failure
    case handshakeFailure(String)
    
    /// Rate limit exceeded
    case rateLimitExceeded
    
    /// Timeout
    case timeout
    
    public static func == (lhs: ProtocolError, rhs: ProtocolError) -> Bool {
        switch (lhs, rhs) {
        case (.invalidFrameFormat(let lhsMsg), .invalidFrameFormat(let rhsMsg)):
            return lhsMsg == rhsMsg
        case (.frameSizeViolation(let lhsActual, let lhsMax), .frameSizeViolation(let rhsActual, let rhsMax)):
            return lhsActual == rhsActual && lhsMax == rhsMax
        case (.bufferSizeViolation(let lhsActual, let lhsMax), .bufferSizeViolation(let rhsActual, let rhsMax)):
            return lhsActual == rhsActual && lhsMax == rhsMax
        case (.invalidFrameType(let lhsType), .invalidFrameType(let rhsType)):
            return lhsType == rhsType
        case (.unsupportedVersion(let lhsVer), .unsupportedVersion(let rhsVer)):
            return lhsVer == rhsVer
        case (.handshakeFailure(let lhsMsg), .handshakeFailure(let rhsMsg)):
            return lhsMsg == rhsMsg
        case (.rateLimitExceeded, .rateLimitExceeded),
             (.timeout, .timeout):
            return true
        default:
            return false
        }
    }
}

/// Cryptographic errors for secure session operations.
public enum CryptoError: Error, Equatable {
    /// Authentication failure (tag verification failed)
    case authenticationFailed
    
    /// Decryption failure
    case decryptionFailed(String)
    
    /// Invalid nonce
    case invalidNonce
    
    /// Nonce reuse detected
    case nonceReuse
    
    /// Key derivation failure
    case keyDerivationFailed(String)
    
    /// Invalid key material
    case invalidKeyMaterial
    
    /// Handshake failure
    case handshakeFailure(String)
    
    public static func == (lhs: CryptoError, rhs: CryptoError) -> Bool {
        switch (lhs, rhs) {
        case (.authenticationFailed, .authenticationFailed),
             (.invalidNonce, .invalidNonce),
             (.nonceReuse, .nonceReuse),
             (.invalidKeyMaterial, .invalidKeyMaterial):
            return true
        case (.decryptionFailed(let lhsMsg), .decryptionFailed(let rhsMsg)),
             (.keyDerivationFailed(let lhsMsg), .keyDerivationFailed(let rhsMsg)),
             (.handshakeFailure(let lhsMsg), .handshakeFailure(let rhsMsg)):
            return lhsMsg == rhsMsg
        default:
            return false
        }
    }
}

/// Helper to convert BlazeBinaryError to connection-level errors.
public extension BlazeBinaryError {
    /// Converts to a DisconnectReason for connection-level signaling.
    var disconnectReason: DisconnectReason {
        switch self {
        case .invalidFrameLength, .oversizedFrame:
            return .frameTooLarge
        case .handshakeFailed, .invalidHandshake:
            return .invalidHandshake
        case .encryptionFailed, .invalidSession:
            return .cryptoError
        case .truncated, .invalidVarint, .decodeFailed:
            return .protocolError
        case .needMoreData:
            return .noError // Not an error, just need more data
        }
    }
    
    /// Converts to a ProtocolError if applicable.
    var protocolError: ProtocolError? {
        switch self {
        case .invalidFrameLength:
            return .frameSizeViolation(actual: 0, max: BlazeFrameEncoder.maxFrameSize)
        case .oversizedFrame:
            return .bufferSizeViolation(actual: 0, max: BlazeFrameParser.maxBufferSize)
        case .handshakeFailed(let msg), .invalidHandshake(let msg):
            return .handshakeFailure(msg)
        default:
            return nil
        }
    }
    
    /// Converts to a CryptoError if applicable.
    var cryptoError: CryptoError? {
        switch self {
        case .encryptionFailed(let msg):
            if msg.contains("authentication") || msg.contains("tag") {
                return .authenticationFailed
            }
            return .decryptionFailed(msg)
        case .invalidSession(let msg):
            return .invalidKeyMaterial
        default:
            return nil
        }
    }
}

