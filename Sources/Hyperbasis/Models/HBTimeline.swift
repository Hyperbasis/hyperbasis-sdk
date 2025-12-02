//
//  HBTimeline.swift
//  Hyperbasis
//
//  Provides timeline navigation and state reconstruction for a space.
//

import Foundation

/// Provides timeline navigation and state reconstruction for a space
public struct HBTimeline {

    // MARK: - Properties

    /// The space this timeline is for
    public let spaceId: UUID

    /// All events in chronological order
    public let events: [HBAnchorEvent]

    // MARK: - Initialization

    public init(spaceId: UUID, events: [HBAnchorEvent]) {
        self.spaceId = spaceId
        self.events = events.sorted { $0.timestamp < $1.timestamp }
    }

    // MARK: - Timeline Bounds

    /// Earliest event timestamp
    public var startDate: Date? {
        events.first?.timestamp
    }

    /// Latest event timestamp
    public var endDate: Date? {
        events.last?.timestamp
    }

    /// Total time span
    public var duration: TimeInterval? {
        guard let start = startDate, let end = endDate else { return nil }
        return end.timeIntervalSince(start)
    }

    // MARK: - Event Queries

    /// All unique anchor IDs in this timeline
    public var anchorIds: Set<UUID> {
        Set(events.map(\.anchorId))
    }

    /// Events for a specific anchor
    public func events(for anchorId: UUID) -> [HBAnchorEvent] {
        events.filter { $0.anchorId == anchorId }
    }

    /// Events within a date range
    public func events(from: Date, to: Date) -> [HBAnchorEvent] {
        events.filter { $0.timestamp >= from && $0.timestamp <= to }
    }

    /// Events of a specific type
    public func events(ofType type: HBAnchorEvent.EventType) -> [HBAnchorEvent] {
        events.filter { $0.type == type }
    }

    // MARK: - State Reconstruction

    /// Reconstruct the state of all anchors at a given point in time
    /// - Parameter date: The point in time to reconstruct
    /// - Returns: Array of anchors as they existed at that date
    public func state(at date: Date) -> [HBAnchor] {
        // Get all events up to and including date
        let relevantEvents = events.filter { $0.timestamp <= date }

        // Group by anchor and get latest state for each
        var anchorStates: [UUID: AnchorState] = [:]

        for event in relevantEvents {
            switch event.type {
            case .created:
                anchorStates[event.anchorId] = AnchorState(
                    id: event.anchorId,
                    spaceId: event.spaceId,
                    transform: event.transform ?? [],
                    metadata: event.metadata ?? [:],
                    createdAt: event.timestamp,
                    updatedAt: event.timestamp,
                    isDeleted: false
                )

            case .moved:
                if var state = anchorStates[event.anchorId] {
                    state.transform = event.transform ?? state.transform
                    state.updatedAt = event.timestamp
                    anchorStates[event.anchorId] = state
                }

            case .updated:
                if var state = anchorStates[event.anchorId] {
                    state.metadata = event.metadata ?? state.metadata
                    state.updatedAt = event.timestamp
                    anchorStates[event.anchorId] = state
                }

            case .deleted:
                if var state = anchorStates[event.anchorId] {
                    state.isDeleted = true
                    state.updatedAt = event.timestamp
                    anchorStates[event.anchorId] = state
                }

            case .restored:
                if var state = anchorStates[event.anchorId] {
                    state.transform = event.transform ?? state.transform
                    state.metadata = event.metadata ?? state.metadata
                    state.isDeleted = false
                    state.updatedAt = event.timestamp
                    anchorStates[event.anchorId] = state
                }
            }
        }

        // Convert to HBAnchor, excluding deleted
        return anchorStates.values
            .filter { !$0.isDeleted }
            .map { $0.toAnchor() }
    }

    // MARK: - Diff Generation

    /// Generate a diff between two points in time
    public func diff(from fromDate: Date, to toDate: Date) -> HBDiff {
        let fromState = state(at: fromDate)
        let toState = state(at: toDate)

        let fromIds = Set(fromState.map(\.id))
        let toIds = Set(toState.map(\.id))

        // Added: in `to` but not in `from`
        let addedIds = toIds.subtracting(fromIds)
        let added = toState.filter { addedIds.contains($0.id) }

        // Removed: in `from` but not in `to`
        let removedIds = fromIds.subtracting(toIds)
        let removed = fromState.filter { removedIds.contains($0.id) }

        // Common: in both
        let commonIds = fromIds.intersection(toIds)

        var moved: [HBDiff.MovedAnchor] = []
        var updated: [HBDiff.UpdatedAnchor] = []
        var unchanged: [HBAnchor] = []

        for id in commonIds {
            guard let fromAnchor = fromState.first(where: { $0.id == id }),
                  let toAnchor = toState.first(where: { $0.id == id }) else {
                continue
            }

            let transformChanged = fromAnchor.transform != toAnchor.transform
            let metadataChanged = fromAnchor.metadata != toAnchor.metadata

            if transformChanged {
                moved.append(HBDiff.MovedAnchor(
                    anchor: toAnchor,
                    previousTransform: fromAnchor.transform
                ))
            } else if metadataChanged {
                updated.append(HBDiff.UpdatedAnchor(
                    anchor: toAnchor,
                    previousMetadata: fromAnchor.metadata
                ))
            } else {
                unchanged.append(toAnchor)
            }
        }

        return HBDiff(
            spaceId: spaceId,
            fromDate: fromDate,
            toDate: toDate,
            added: added,
            removed: removed,
            moved: moved,
            updated: updated,
            unchanged: unchanged
        )
    }

    // MARK: - UI Helpers

    /// Generate evenly-spaced dates for a timeline scrubber
    /// - Parameters:
    ///   - from: Start date (defaults to timeline start)
    ///   - to: End date (defaults to timeline end)
    ///   - steps: Number of positions on scrubber
    /// - Returns: Array of dates for scrubber positions
    public func scrubberDates(from: Date? = nil, to: Date? = nil, steps: Int = 100) -> [Date] {
        let start = from ?? startDate ?? Date()
        let end = to ?? endDate ?? Date()

        guard start < end, steps > 1 else {
            return [start]
        }

        let interval = end.timeIntervalSince(start) / Double(steps - 1)

        return (0..<steps).map { i in
            start.addingTimeInterval(interval * Double(i))
        }
    }

    /// Find the closest event to a given date
    public func closestEvent(to date: Date) -> HBAnchorEvent? {
        events.min { abs($0.timestamp.timeIntervalSince(date)) < abs($1.timestamp.timeIntervalSince(date)) }
    }

    /// Dates where significant changes occurred (for jump-to functionality)
    public var significantDates: [Date] {
        // Group events by day and return one date per day that had events
        let calendar = Calendar.current
        var seenDays: Set<DateComponents> = []
        var result: [Date] = []

        for event in events {
            let components = calendar.dateComponents([.year, .month, .day], from: event.timestamp)
            if !seenDays.contains(components) {
                seenDays.insert(components)
                result.append(event.timestamp)
            }
        }

        return result
    }
}

// MARK: - Internal Helper

private struct AnchorState {
    var id: UUID
    var spaceId: UUID
    var transform: [Float]
    var metadata: [String: AnyCodableValue]
    var createdAt: Date
    var updatedAt: Date
    var isDeleted: Bool

    func toAnchor() -> HBAnchor {
        HBAnchor(
            id: id,
            spaceId: spaceId,
            transform: transform,
            metadata: metadata,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: nil
        )
    }
}
