//
//  HBSpace.swift
//  Hyperbasis
//
//  Represents a spatial environment containing an ARWorldMap.
//

import Foundation
import ARKit

/// Represents a spatial environment containing an ARWorldMap.
/// A "space" is typically a room or area that has been mapped by ARKit.
public struct HBSpace: Codable, Identifiable, Equatable {

    // MARK: - Properties

    /// Unique identifier for this space
    public let id: UUID

    /// Optional human-readable name (e.g., "Living Room", "Office")
    public var name: String?

    /// Serialized ARWorldMap data
    /// This is the output of NSKeyedArchiver encoding an ARWorldMap
    /// Typical size: 5-50MB depending on environment complexity
    public var worldMapData: Data

    /// When this space was first created
    public let createdAt: Date

    /// When this space was last modified
    public var updatedAt: Date

    // MARK: - Initialization

    /// Creates a new HBSpace from an ARWorldMap
    /// - Parameters:
    ///   - id: Unique identifier (defaults to new UUID)
    ///   - name: Optional human-readable name
    ///   - worldMap: The ARWorldMap to serialize and store
    /// - Throws: HBSpaceError.serializationFailed if ARWorldMap cannot be archived
    public init(
        id: UUID = UUID(),
        name: String? = nil,
        worldMap: ARWorldMap
    ) throws {
        self.id = id
        self.name = name
        self.worldMapData = try Self.serialize(worldMap: worldMap)
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    /// Creates an HBSpace from already-serialized data
    /// Use this when loading from storage
    /// - Parameters:
    ///   - id: Unique identifier
    ///   - name: Optional human-readable name
    ///   - worldMapData: Pre-serialized ARWorldMap data
    ///   - createdAt: Original creation timestamp
    ///   - updatedAt: Last modification timestamp
    public init(
        id: UUID,
        name: String?,
        worldMapData: Data,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.name = name
        self.worldMapData = worldMapData
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - ARWorldMap Serialization

extension HBSpace {

    /// Serializes an ARWorldMap to Data using NSKeyedArchiver
    /// - Parameter worldMap: The ARWorldMap to serialize
    /// - Returns: Serialized Data representation
    /// - Throws: HBSpaceError.serializationFailed if archiving fails
    public static func serialize(worldMap: ARWorldMap) throws -> Data {
        do {
            let data = try NSKeyedArchiver.archivedData(
                withRootObject: worldMap,
                requiringSecureCoding: true
            )
            return data
        } catch {
            throw HBSpaceError.serializationFailed(underlying: error)
        }
    }

    /// Deserializes Data back into an ARWorldMap
    /// - Parameter data: The serialized ARWorldMap data
    /// - Returns: The deserialized ARWorldMap
    /// - Throws: HBSpaceError.deserializationFailed if unarchiving fails
    public static func deserialize(worldMapData data: Data) throws -> ARWorldMap {
        do {
            guard let worldMap = try NSKeyedUnarchiver.unarchivedObject(
                ofClass: ARWorldMap.self,
                from: data
            ) else {
                throw HBSpaceError.deserializationFailed(underlying: nil)
            }
            return worldMap
        } catch let error as HBSpaceError {
            throw error
        } catch {
            throw HBSpaceError.deserializationFailed(underlying: error)
        }
    }

    /// Convenience property to get the deserialized ARWorldMap
    /// - Returns: The ARWorldMap for this space
    /// - Throws: HBSpaceError.deserializationFailed if unarchiving fails
    public func arWorldMap() throws -> ARWorldMap {
        try Self.deserialize(worldMapData: worldMapData)
    }
}

// MARK: - Mutations

extension HBSpace {

    /// Updates the space with a new ARWorldMap
    /// - Parameter worldMap: The new ARWorldMap to store
    /// - Throws: HBSpaceError.serializationFailed if archiving fails
    public mutating func update(worldMap: ARWorldMap) throws {
        self.worldMapData = try Self.serialize(worldMap: worldMap)
        self.updatedAt = Date()
    }

    /// Updates the space name
    /// - Parameter name: The new name (or nil to clear)
    public mutating func update(name: String?) {
        self.name = name
        self.updatedAt = Date()
    }
}

// MARK: - Validation

extension HBSpace {

    /// Validates that the space data is valid and can be deserialized
    /// - Returns: true if the worldMapData can be deserialized to ARWorldMap
    public func validate() -> Bool {
        guard !worldMapData.isEmpty else { return false }

        do {
            _ = try arWorldMap()
            return true
        } catch {
            return false
        }
    }

    /// Returns the size of the world map data in bytes
    public var worldMapSize: Int {
        worldMapData.count
    }

    /// Returns a human-readable string for the world map size
    public var worldMapSizeFormatted: String {
        ByteCountFormatter.string(fromByteCount: Int64(worldMapSize), countStyle: .file)
    }
}

// MARK: - Errors

/// Errors that can occur when working with HBSpace
public enum HBSpaceError: LocalizedError {

    /// ARWorldMap could not be serialized to Data
    case serializationFailed(underlying: Error?)

    /// Data could not be deserialized back to ARWorldMap
    case deserializationFailed(underlying: Error?)

    /// The world map data is empty or invalid
    case invalidWorldMapData

    public var errorDescription: String? {
        switch self {
        case .serializationFailed(let underlying):
            if let underlying = underlying {
                return "Failed to serialize ARWorldMap: \(underlying.localizedDescription)"
            }
            return "Failed to serialize ARWorldMap"

        case .deserializationFailed(let underlying):
            if let underlying = underlying {
                return "Failed to deserialize ARWorldMap: \(underlying.localizedDescription)"
            }
            return "Failed to deserialize ARWorldMap"

        case .invalidWorldMapData:
            return "World map data is empty or invalid"
        }
    }
}
