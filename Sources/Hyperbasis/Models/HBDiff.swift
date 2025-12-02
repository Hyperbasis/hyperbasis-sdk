//
//  HBDiff.swift
//  Hyperbasis
//
//  Represents the difference between two points in time for a space.
//

import Foundation
import simd

/// Represents the difference between two points in time for a space
public struct HBDiff: Equatable {

    // MARK: - Properties

    /// Space this diff applies to
    public let spaceId: UUID

    /// Start of the diff range
    public let fromDate: Date

    /// End of the diff range
    public let toDate: Date

    /// Anchors that exist in `to` but not in `from`
    public let added: [HBAnchor]

    /// Anchors that existed in `from` but not in `to`
    public let removed: [HBAnchor]

    /// Anchors whose transform changed
    public let moved: [MovedAnchor]

    /// Anchors whose metadata changed (but not transform)
    public let updated: [UpdatedAnchor]

    /// Anchors that exist in both and haven't changed
    public let unchanged: [HBAnchor]

    // MARK: - Nested Types

    public struct MovedAnchor: Equatable {
        public let anchor: HBAnchor              // Current state
        public let previousTransform: [Float]    // Transform at `from` date

        public init(anchor: HBAnchor, previousTransform: [Float]) {
            self.anchor = anchor
            self.previousTransform = previousTransform
        }

        /// Previous position extracted from transform
        public var previousPosition: SIMD3<Float> {
            guard previousTransform.count >= 15 else {
                return SIMD3<Float>(0, 0, 0)
            }
            return SIMD3<Float>(previousTransform[12], previousTransform[13], previousTransform[14])
        }

        /// Current position
        public var currentPosition: SIMD3<Float> {
            anchor.position
        }

        /// Distance moved in meters
        public var distanceMoved: Float {
            simd_distance(previousPosition, currentPosition)
        }
    }

    public struct UpdatedAnchor: Equatable {
        public let anchor: HBAnchor                           // Current state
        public let previousMetadata: [String: AnyCodableValue] // Metadata at `from` date

        public init(anchor: HBAnchor, previousMetadata: [String: AnyCodableValue]) {
            self.anchor = anchor
            self.previousMetadata = previousMetadata
        }

        /// Keys that were added
        public var addedKeys: Set<String> {
            Set(anchor.metadata.keys).subtracting(previousMetadata.keys)
        }

        /// Keys that were removed
        public var removedKeys: Set<String> {
            Set(previousMetadata.keys).subtracting(anchor.metadata.keys)
        }

        /// Keys that changed value
        public var changedKeys: Set<String> {
            let common = Set(anchor.metadata.keys).intersection(previousMetadata.keys)
            return common.filter { anchor.metadata[$0] != previousMetadata[$0] }
        }
    }

    // MARK: - Initialization

    public init(
        spaceId: UUID,
        fromDate: Date,
        toDate: Date,
        added: [HBAnchor] = [],
        removed: [HBAnchor] = [],
        moved: [MovedAnchor] = [],
        updated: [UpdatedAnchor] = [],
        unchanged: [HBAnchor] = []
    ) {
        self.spaceId = spaceId
        self.fromDate = fromDate
        self.toDate = toDate
        self.added = added
        self.removed = removed
        self.moved = moved
        self.updated = updated
        self.unchanged = unchanged
    }

    // MARK: - Computed Properties

    /// Total number of changes
    public var changeCount: Int {
        added.count + removed.count + moved.count + updated.count
    }

    /// Whether any changes occurred
    public var hasChanges: Bool {
        changeCount > 0
    }

    /// All anchors that exist at `to` date
    public var currentAnchors: [HBAnchor] {
        added + moved.map(\.anchor) + updated.map(\.anchor) + unchanged
    }

    /// All anchors that existed at `from` date
    public var previousAnchors: [HBAnchor] {
        removed + moved.map(\.anchor) + updated.map(\.anchor) + unchanged
    }
}

// MARK: - Summary

extension HBDiff {

    /// Human-readable summary of changes
    public var summary: String {
        var parts: [String] = []

        if !added.isEmpty {
            parts.append("\(added.count) added")
        }
        if !removed.isEmpty {
            parts.append("\(removed.count) removed")
        }
        if !moved.isEmpty {
            parts.append("\(moved.count) moved")
        }
        if !updated.isEmpty {
            parts.append("\(updated.count) updated")
        }

        if parts.isEmpty {
            return "No changes"
        }

        return parts.joined(separator: ", ")
    }
}
