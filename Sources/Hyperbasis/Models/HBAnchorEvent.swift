//
//  HBAnchorEvent.swift
//  Hyperbasis
//
//  Represents a single change event for an anchor.
//  Events are immutable and append-only for event sourcing.
//

import Foundation

/// Represents a single change event for an anchor
/// Events are immutable and append-only
public struct HBAnchorEvent: Codable, Identifiable, Equatable {

    // MARK: - Properties

    /// Unique identifier for this event
    public let id: UUID

    /// The anchor this event affects
    public let anchorId: UUID

    /// The space this anchor belongs to
    public let spaceId: UUID

    /// Type of change
    public let type: EventType

    /// When this event occurred
    public let timestamp: Date

    /// Version number (increments per anchor)
    public let version: Int

    /// Transform at time of event (for created, moved, restored)
    public let transform: [Float]?

    /// Metadata at time of event (for created, updated, restored)
    public let metadata: [String: AnyCodableValue]?

    /// Actor who made the change (for multi-user, future)
    public let actorId: String?

    // MARK: - Event Types

    public enum EventType: String, Codable {
        case created    // Anchor was created
        case moved      // Transform changed
        case updated    // Metadata changed
        case deleted    // Anchor was soft-deleted
        case restored   // Anchor was restored from deletion
    }

    // MARK: - Initialization

    public init(
        id: UUID = UUID(),
        anchorId: UUID,
        spaceId: UUID,
        type: EventType,
        timestamp: Date = Date(),
        version: Int,
        transform: [Float]? = nil,
        metadata: [String: AnyCodableValue]? = nil,
        actorId: String? = nil
    ) {
        self.id = id
        self.anchorId = anchorId
        self.spaceId = spaceId
        self.type = type
        self.timestamp = timestamp
        self.version = version
        self.transform = transform
        self.metadata = metadata
        self.actorId = actorId
    }
}

// MARK: - Factory Methods

extension HBAnchorEvent {

    /// Create a "created" event for a new anchor
    public static func created(anchor: HBAnchor) -> HBAnchorEvent {
        HBAnchorEvent(
            anchorId: anchor.id,
            spaceId: anchor.spaceId,
            type: .created,
            version: 1,
            transform: anchor.transform,
            metadata: anchor.metadata
        )
    }

    /// Create a "moved" event when transform changes
    public static func moved(anchor: HBAnchor, previousVersion: Int) -> HBAnchorEvent {
        HBAnchorEvent(
            anchorId: anchor.id,
            spaceId: anchor.spaceId,
            type: .moved,
            version: previousVersion + 1,
            transform: anchor.transform
        )
    }

    /// Create an "updated" event when metadata changes
    public static func updated(anchor: HBAnchor, previousVersion: Int) -> HBAnchorEvent {
        HBAnchorEvent(
            anchorId: anchor.id,
            spaceId: anchor.spaceId,
            type: .updated,
            version: previousVersion + 1,
            metadata: anchor.metadata
        )
    }

    /// Create a "deleted" event
    public static func deleted(anchor: HBAnchor, previousVersion: Int) -> HBAnchorEvent {
        HBAnchorEvent(
            anchorId: anchor.id,
            spaceId: anchor.spaceId,
            type: .deleted,
            version: previousVersion + 1
        )
    }

    /// Create a "restored" event
    public static func restored(anchor: HBAnchor, previousVersion: Int) -> HBAnchorEvent {
        HBAnchorEvent(
            anchorId: anchor.id,
            spaceId: anchor.spaceId,
            type: .restored,
            version: previousVersion + 1,
            transform: anchor.transform,
            metadata: anchor.metadata
        )
    }
}

// MARK: - Computed Properties

extension HBAnchorEvent {

    /// Whether this event represents the anchor existing (not deleted)
    public var isActiveState: Bool {
        switch type {
        case .created, .moved, .updated, .restored:
            return true
        case .deleted:
            return false
        }
    }

    /// Whether this event includes transform data
    public var hasTransform: Bool {
        transform != nil
    }

    /// Whether this event includes metadata
    public var hasMetadata: Bool {
        metadata != nil
    }
}
