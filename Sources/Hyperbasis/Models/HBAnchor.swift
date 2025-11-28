//
//  HBAnchor.swift
//  Hyperbasis
//
//  Represents a placed object in AR space with position, rotation, and custom metadata.
//

import Foundation
import simd

/// Represents a placed object in AR space with position, rotation, and custom metadata.
/// An anchor belongs to a single HBSpace and can be persisted across sessions.
public struct HBAnchor: Codable, Identifiable, Equatable {

    // MARK: - Properties

    /// Unique identifier for this anchor
    public let id: UUID

    /// The space this anchor belongs to
    public let spaceId: UUID

    /// The 4x4 transformation matrix stored as 16 floats
    /// Contains position (translation) and rotation of the anchor in 3D space
    /// Stored in column-major order to match simd_float4x4
    public var transform: [Float]

    /// Custom user data associated with this anchor
    /// Examples: {"text": "Buy milk", "color": "yellow", "type": "sticky_note"}
    public var metadata: [String: AnyCodableValue]

    /// When this anchor was first created
    public let createdAt: Date

    /// When this anchor was last modified
    public var updatedAt: Date

    /// When this anchor was deleted (nil if not deleted)
    /// Used for soft delete - anchor is hidden but not removed until sync
    public var deletedAt: Date?

    // MARK: - Initialization

    /// Creates a new HBAnchor from a simd_float4x4 transform
    /// - Parameters:
    ///   - id: Unique identifier (defaults to new UUID)
    ///   - spaceId: The parent space's identifier
    ///   - transform: The 4x4 transformation matrix from ARKit
    ///   - metadata: Custom user data (defaults to empty)
    public init(
        id: UUID = UUID(),
        spaceId: UUID,
        transform: simd_float4x4,
        metadata: [String: AnyCodableValue] = [:]
    ) {
        self.id = id
        self.spaceId = spaceId
        self.transform = Self.flatten(transform)
        self.metadata = metadata
        self.createdAt = Date()
        self.updatedAt = Date()
        self.deletedAt = nil
    }

    /// Creates an HBAnchor from already-flattened transform data
    /// Use this when loading from storage
    /// - Parameters:
    ///   - id: Unique identifier
    ///   - spaceId: The parent space's identifier
    ///   - transform: Pre-flattened transform (16 floats)
    ///   - metadata: Custom user data
    ///   - createdAt: Original creation timestamp
    ///   - updatedAt: Last modification timestamp
    ///   - deletedAt: Deletion timestamp (nil if not deleted)
    public init(
        id: UUID,
        spaceId: UUID,
        transform: [Float],
        metadata: [String: AnyCodableValue],
        createdAt: Date,
        updatedAt: Date,
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.spaceId = spaceId
        self.transform = transform
        self.metadata = metadata
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }
}

// MARK: - Transform Conversion

extension HBAnchor {

    /// Converts a simd_float4x4 matrix to a flat array of 16 floats
    /// Stored in column-major order (how simd stores matrices)
    /// - Parameter matrix: The 4x4 transformation matrix
    /// - Returns: Array of 16 floats
    public static func flatten(_ matrix: simd_float4x4) -> [Float] {
        return [
            // Column 0
            matrix.columns.0.x, matrix.columns.0.y, matrix.columns.0.z, matrix.columns.0.w,
            // Column 1
            matrix.columns.1.x, matrix.columns.1.y, matrix.columns.1.z, matrix.columns.1.w,
            // Column 2
            matrix.columns.2.x, matrix.columns.2.y, matrix.columns.2.z, matrix.columns.2.w,
            // Column 3 (contains translation/position)
            matrix.columns.3.x, matrix.columns.3.y, matrix.columns.3.z, matrix.columns.3.w
        ]
    }

    /// Converts the flat array back to a simd_float4x4 matrix
    /// - Returns: The 4x4 transformation matrix
    /// - Throws: HBAnchorError.invalidTransform if array doesn't have exactly 16 elements
    public func simdTransform() throws -> simd_float4x4 {
        try Self.unflatten(transform)
    }

    /// Converts a flat array of 16 floats to a simd_float4x4 matrix
    /// - Parameter array: Array of 16 floats in column-major order
    /// - Returns: The 4x4 transformation matrix
    /// - Throws: HBAnchorError.invalidTransform if array doesn't have exactly 16 elements
    public static func unflatten(_ array: [Float]) throws -> simd_float4x4 {
        guard array.count == 16 else {
            throw HBAnchorError.invalidTransform(count: array.count)
        }

        return simd_float4x4(
            SIMD4<Float>(array[0], array[1], array[2], array[3]),
            SIMD4<Float>(array[4], array[5], array[6], array[7]),
            SIMD4<Float>(array[8], array[9], array[10], array[11]),
            SIMD4<Float>(array[12], array[13], array[14], array[15])
        )
    }

    /// Extracts the position (translation) from the transform
    /// - Returns: SIMD3 containing x, y, z position in meters
    public var position: SIMD3<Float> {
        // Position is stored in the last column (indices 12, 13, 14)
        SIMD3<Float>(transform[12], transform[13], transform[14])
    }
}

// MARK: - Mutations

extension HBAnchor {

    /// Updates the anchor's transform
    /// - Parameter transform: The new 4x4 transformation matrix
    public mutating func update(transform: simd_float4x4) {
        self.transform = Self.flatten(transform)
        self.updatedAt = Date()
    }

    /// Updates a single metadata value
    /// - Parameters:
    ///   - key: The metadata key
    ///   - value: The new value (or nil to remove)
    public mutating func updateMetadata(key: String, value: AnyCodableValue?) {
        if let value = value {
            self.metadata[key] = value
        } else {
            self.metadata.removeValue(forKey: key)
        }
        self.updatedAt = Date()
    }

    /// Replaces all metadata
    /// - Parameter metadata: The new metadata dictionary
    public mutating func update(metadata: [String: AnyCodableValue]) {
        self.metadata = metadata
        self.updatedAt = Date()
    }

    /// Marks the anchor as deleted (soft delete)
    /// The anchor is not removed but marked with a deletion timestamp
    public mutating func markDeleted() {
        self.deletedAt = Date()
        self.updatedAt = Date()
    }

    /// Restores a soft-deleted anchor
    public mutating func restore() {
        self.deletedAt = nil
        self.updatedAt = Date()
    }
}

// MARK: - Computed Properties

extension HBAnchor {

    /// Returns true if the anchor has been soft-deleted
    public var isDeleted: Bool {
        deletedAt != nil
    }

    /// Returns true if the anchor has any metadata
    public var hasMetadata: Bool {
        !metadata.isEmpty
    }

    /// Returns metadata value for a key, or nil if not found
    public func metadata(forKey key: String) -> AnyCodableValue? {
        metadata[key]
    }

    /// Returns string metadata value for a key, or nil if not found or not a string
    public func stringMetadata(forKey key: String) -> String? {
        metadata[key]?.stringValue
    }

    /// Returns int metadata value for a key, or nil if not found or not an int
    public func intMetadata(forKey key: String) -> Int? {
        metadata[key]?.intValue
    }

    /// Returns bool metadata value for a key, or nil if not found or not a bool
    public func boolMetadata(forKey key: String) -> Bool? {
        metadata[key]?.boolValue
    }
}

// MARK: - Validation

extension HBAnchor {

    /// Validates that the anchor data is valid
    /// - Returns: true if transform has 16 elements and spaceId is valid
    public func validate() -> Bool {
        transform.count == 16
    }

    /// Returns the transform as a simd_float4x4 if valid, nil otherwise
    public var validSimdTransform: simd_float4x4? {
        try? simdTransform()
    }
}

// MARK: - Errors

/// Errors that can occur when working with HBAnchor
public enum HBAnchorError: LocalizedError {

    /// Transform array doesn't have exactly 16 elements
    case invalidTransform(count: Int)

    /// Anchor has already been deleted
    case alreadyDeleted

    /// Metadata key not found
    case metadataKeyNotFound(key: String)

    public var errorDescription: String? {
        switch self {
        case .invalidTransform(let count):
            return "Invalid transform: expected 16 floats, got \(count)"
        case .alreadyDeleted:
            return "Anchor has already been deleted"
        case .metadataKeyNotFound(let key):
            return "Metadata key not found: \(key)"
        }
    }
}

// MARK: - AnyCodableValue

/// A type-erased Codable value for storing dynamic metadata
/// Supports: String, Int, Double, Bool, Array, Dictionary, and null
public enum AnyCodableValue: Codable, Equatable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case array([AnyCodableValue])
    case dictionary([String: AnyCodableValue])
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
            return
        }

        if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
            return
        }

        if let int = try? container.decode(Int.self) {
            self = .int(int)
            return
        }

        if let double = try? container.decode(Double.self) {
            self = .double(double)
            return
        }

        if let string = try? container.decode(String.self) {
            self = .string(string)
            return
        }

        if let array = try? container.decode([AnyCodableValue].self) {
            self = .array(array)
            return
        }

        if let dictionary = try? container.decode([String: AnyCodableValue].self) {
            self = .dictionary(dictionary)
            return
        }

        throw DecodingError.typeMismatch(
            AnyCodableValue.self,
            DecodingError.Context(
                codingPath: decoder.codingPath,
                debugDescription: "Unable to decode AnyCodableValue"
            )
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch self {
        case .string(let value):
            try container.encode(value)
        case .int(let value):
            try container.encode(value)
        case .double(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .dictionary(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }

    // MARK: - Convenience Accessors

    /// Returns the underlying String value, or nil if not a string
    public var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    /// Returns the underlying Int value, or nil if not an int
    public var intValue: Int? {
        if case .int(let value) = self { return value }
        return nil
    }

    /// Returns the underlying Double value, or nil if not a double
    public var doubleValue: Double? {
        if case .double(let value) = self { return value }
        return nil
    }

    /// Returns the underlying Bool value, or nil if not a bool
    public var boolValue: Bool? {
        if case .bool(let value) = self { return value }
        return nil
    }

    /// Returns the underlying Array value, or nil if not an array
    public var arrayValue: [AnyCodableValue]? {
        if case .array(let value) = self { return value }
        return nil
    }

    /// Returns the underlying Dictionary value, or nil if not a dictionary
    public var dictionaryValue: [String: AnyCodableValue]? {
        if case .dictionary(let value) = self { return value }
        return nil
    }

    /// Returns true if the value is null
    public var isNull: Bool {
        if case .null = self { return true }
        return false
    }
}

// MARK: - ExpressibleBy Protocols

extension AnyCodableValue: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        self = .string(value)
    }
}

extension AnyCodableValue: ExpressibleByIntegerLiteral {
    public init(integerLiteral value: Int) {
        self = .int(value)
    }
}

extension AnyCodableValue: ExpressibleByFloatLiteral {
    public init(floatLiteral value: Double) {
        self = .double(value)
    }
}

extension AnyCodableValue: ExpressibleByBooleanLiteral {
    public init(booleanLiteral value: Bool) {
        self = .bool(value)
    }
}

extension AnyCodableValue: ExpressibleByArrayLiteral {
    public init(arrayLiteral elements: AnyCodableValue...) {
        self = .array(elements)
    }
}

extension AnyCodableValue: ExpressibleByDictionaryLiteral {
    public init(dictionaryLiteral elements: (String, AnyCodableValue)...) {
        self = .dictionary(Dictionary(uniqueKeysWithValues: elements))
    }
}

extension AnyCodableValue: ExpressibleByNilLiteral {
    public init(nilLiteral: ()) {
        self = .null
    }
}
