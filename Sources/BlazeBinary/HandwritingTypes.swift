//
// HandwritingTypes.swift
// BlazeBinary
//
// Copyright (c) 2025 Michael Danylchuk
// MIT License
//

import Foundation

/// Request for handwriting continuation prediction.
/// Contains the text that appears before the cursor for context.
///
/// Encoding is deterministic: same input always produces identical bytes.
/// Uses UTF-8 encoding with varint length prefix.
public struct HandwritingContinuationRequest: BlazeBinaryCodable, Equatable {
    /// The text that appears before the cursor position.
    public var textBefore: String
    
    /// Creates a new handwriting continuation request.
    /// - Parameter textBefore: The text that appears before the cursor
    public init(textBefore: String) {
        self.textBefore = textBefore
    }
    
    // MARK: - BlazeBinaryCodable
    
    /// Encodes the request deterministically using UTF-8 with varint length prefix.
    public func blazeEncode(to encoder: BlazeBinaryEncoder) throws {
        encoder.encode(textBefore)
    }
    
    /// Decodes the request from binary format.
    public init(from decoder: BlazeBinaryDecoder) throws {
        self.textBefore = try decoder.decodeString()
    }
}

/// Response containing predicted text continuation for handwriting.
///
/// Encoding is deterministic: same input always produces identical bytes.
/// Uses UTF-8 encoding with varint length prefix.
public struct HandwritingContinuationResponse: BlazeBinaryCodable, Equatable {
    /// The predicted text continuation.
    public var predictedText: String
    
    /// Creates a new handwriting continuation response.
    /// - Parameter predictedText: The predicted text continuation
    public init(predictedText: String) {
        self.predictedText = predictedText
    }
    
    // MARK: - BlazeBinaryCodable
    
    /// Encodes the response deterministically using UTF-8 with varint length prefix.
    public func blazeEncode(to encoder: BlazeBinaryEncoder) throws {
        encoder.encode(predictedText)
    }
    
    /// Decodes the response from binary format.
    public init(from decoder: BlazeBinaryDecoder) throws {
        self.predictedText = try decoder.decodeString()
    }
}

