//
// Protocols.swift
// BlazeBinary
//
// Copyright (c) 2025 Michael Danylchuk
// MIT License
//

/// Protocol for types that can be encoded to binary format.
public protocol BlazeBinaryEncodable {
    /// Encodes the value into binary format using the provided encoder.
    /// - Parameter encoder: The encoder to use for encoding
    /// - Throws: `BlazeBinaryError` if encoding fails
    func blazeEncode(to encoder: BlazeBinaryEncoder) throws
}

/// Protocol for types that can be decoded from binary format.
public protocol BlazeBinaryDecodable {
    /// Creates a new instance by decoding from binary format using the provided decoder.
    /// - Parameter decoder: The decoder to use for decoding
    /// - Throws: `BlazeBinaryError` if decoding fails
    init(from decoder: BlazeBinaryDecoder) throws
}

/// Convenience typealias for types that are both encodable and decodable.
public typealias BlazeBinaryCodable = BlazeBinaryEncodable & BlazeBinaryDecodable

