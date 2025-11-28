//
//  HBLocalStore.swift
//  Hyperbasis
//
//  Handles local file system storage.
//

import Foundation

/// Handles local file system storage
final class HBLocalStore {

    // MARK: - Properties

    /// Base directory for all Hyperbasis data
    private let baseDirectory: URL

    /// Last sync date with cloud
    var lastSyncDate: Date? {
        get { UserDefaults.standard.object(forKey: "HBLastSyncDate") as? Date }
        set { UserDefaults.standard.set(newValue, forKey: "HBLastSyncDate") }
    }

    // MARK: - Initialization

    init() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.baseDirectory = documents.appendingPathComponent("Hyperbasis", isDirectory: true)

        // Create directories if needed
        try? createDirectories()
    }

    /// Initialize with a custom base directory (for testing)
    init(baseDirectory: URL) {
        self.baseDirectory = baseDirectory
        try? createDirectories()
    }

    private func createDirectories() throws {
        let fm = FileManager.default
        try fm.createDirectory(at: spacesDirectory, withIntermediateDirectories: true)
        try fm.createDirectory(at: anchorsDirectory, withIntermediateDirectories: true)
        try fm.createDirectory(at: worldMapsDirectory, withIntermediateDirectories: true)
    }

    // MARK: - Directory Paths

    private var spacesDirectory: URL {
        baseDirectory.appendingPathComponent("spaces", isDirectory: true)
    }

    private var anchorsDirectory: URL {
        baseDirectory.appendingPathComponent("anchors", isDirectory: true)
    }

    private var worldMapsDirectory: URL {
        baseDirectory.appendingPathComponent("worldmaps", isDirectory: true)
    }

    private var pendingOperationsFile: URL {
        baseDirectory.appendingPathComponent("pending_operations.json")
    }

    // MARK: - Space Operations

    func saveSpace(_ space: HBStorageSpace) throws {
        // Save metadata as JSON
        let metadataURL = spacesDirectory.appendingPathComponent("\(space.id.uuidString).json")
        let metadata = SpaceMetadata(
            id: space.id,
            name: space.name,
            createdAt: space.createdAt,
            updatedAt: space.updatedAt,
            isCompressed: space.isCompressed
        )
        let metadataData = try JSONEncoder.hyperbasis.encode(metadata)
        try metadataData.write(to: metadataURL)

        // Save world map as binary
        let worldMapURL = worldMapsDirectory.appendingPathComponent("\(space.id.uuidString).bin")
        try space.worldMapData.write(to: worldMapURL)
    }

    func loadSpace(id: UUID) throws -> HBStorageSpace? {
        let metadataURL = spacesDirectory.appendingPathComponent("\(id.uuidString).json")
        let worldMapURL = worldMapsDirectory.appendingPathComponent("\(id.uuidString).bin")

        guard FileManager.default.fileExists(atPath: metadataURL.path) else {
            return nil
        }

        let metadataData = try Data(contentsOf: metadataURL)
        let metadata = try JSONDecoder.hyperbasis.decode(SpaceMetadata.self, from: metadataData)
        let worldMapData = try Data(contentsOf: worldMapURL)

        return HBStorageSpace(
            id: metadata.id,
            name: metadata.name,
            worldMapData: worldMapData,
            createdAt: metadata.createdAt,
            updatedAt: metadata.updatedAt,
            isCompressed: metadata.isCompressed
        )
    }

    func loadAllSpaces() throws -> [HBStorageSpace] {
        let fm = FileManager.default

        guard fm.fileExists(atPath: spacesDirectory.path) else {
            return []
        }

        let files = try fm.contentsOfDirectory(at: spacesDirectory, includingPropertiesForKeys: nil)

        return try files
            .filter { $0.pathExtension == "json" }
            .compactMap { url -> HBStorageSpace? in
                let id = UUID(uuidString: url.deletingPathExtension().lastPathComponent)
                guard let id = id else { return nil }
                return try loadSpace(id: id)
            }
    }

    func loadSpacesModifiedSince(_ date: Date) throws -> [HBStorageSpace] {
        try loadAllSpaces().filter { $0.updatedAt > date }
    }

    func deleteSpace(id: UUID) throws {
        let metadataURL = spacesDirectory.appendingPathComponent("\(id.uuidString).json")
        let worldMapURL = worldMapsDirectory.appendingPathComponent("\(id.uuidString).bin")

        try? FileManager.default.removeItem(at: metadataURL)
        try? FileManager.default.removeItem(at: worldMapURL)

        // Also delete all anchors for this space
        let anchors = try loadAnchors(spaceId: id)
        for anchor in anchors {
            try? deleteAnchorFile(id: anchor.id)
        }
    }

    // MARK: - Anchor Operations

    func saveAnchor(_ anchor: HBAnchor) throws {
        let url = anchorsDirectory.appendingPathComponent("\(anchor.id.uuidString).json")
        let data = try JSONEncoder.hyperbasis.encode(anchor)
        try data.write(to: url)
    }

    func loadAnchor(id: UUID) throws -> HBAnchor? {
        let url = anchorsDirectory.appendingPathComponent("\(id.uuidString).json")

        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }

        let data = try Data(contentsOf: url)
        return try JSONDecoder.hyperbasis.decode(HBAnchor.self, from: data)
    }

    func loadAnchors(spaceId: UUID) throws -> [HBAnchor] {
        let fm = FileManager.default

        guard fm.fileExists(atPath: anchorsDirectory.path) else {
            return []
        }

        let files = try fm.contentsOfDirectory(at: anchorsDirectory, includingPropertiesForKeys: nil)

        return try files
            .filter { $0.pathExtension == "json" }
            .compactMap { url -> HBAnchor? in
                let data = try Data(contentsOf: url)
                let anchor = try JSONDecoder.hyperbasis.decode(HBAnchor.self, from: data)
                return anchor.spaceId == spaceId ? anchor : nil
            }
    }

    func loadAnchorsModifiedSince(_ date: Date) throws -> [HBAnchor] {
        let fm = FileManager.default

        guard fm.fileExists(atPath: anchorsDirectory.path) else {
            return []
        }

        let files = try fm.contentsOfDirectory(at: anchorsDirectory, includingPropertiesForKeys: nil)

        return try files
            .filter { $0.pathExtension == "json" }
            .compactMap { url -> HBAnchor? in
                let data = try Data(contentsOf: url)
                let anchor = try JSONDecoder.hyperbasis.decode(HBAnchor.self, from: data)
                return anchor.updatedAt > date ? anchor : nil
            }
    }

    func deleteAnchorFile(id: UUID) throws {
        let url = anchorsDirectory.appendingPathComponent("\(id.uuidString).json")
        try FileManager.default.removeItem(at: url)
    }

    func purgeDeletedAnchors(before date: Date) throws {
        let fm = FileManager.default

        guard fm.fileExists(atPath: anchorsDirectory.path) else {
            return
        }

        let files = try fm.contentsOfDirectory(at: anchorsDirectory, includingPropertiesForKeys: nil)

        for url in files where url.pathExtension == "json" {
            let data = try Data(contentsOf: url)
            let anchor = try JSONDecoder.hyperbasis.decode(HBAnchor.self, from: data)

            if let deletedAt = anchor.deletedAt, deletedAt < date {
                try fm.removeItem(at: url)
            }
        }
    }

    // MARK: - Pending Operations

    func loadPendingOperations() -> [HBPendingOperation] {
        guard let data = try? Data(contentsOf: pendingOperationsFile) else {
            return []
        }
        return (try? JSONDecoder.hyperbasis.decode([HBPendingOperation].self, from: data)) ?? []
    }

    func savePendingOperations(_ operations: [HBPendingOperation]) throws {
        let data = try JSONEncoder.hyperbasis.encode(operations)
        try data.write(to: pendingOperationsFile)
    }

    // MARK: - Utilities

    func clearAll() throws {
        try FileManager.default.removeItem(at: baseDirectory)
        try createDirectories()
    }

    func totalSize() throws -> Int {
        let fm = FileManager.default
        var size = 0

        guard fm.fileExists(atPath: baseDirectory.path) else {
            return 0
        }

        if let enumerator = fm.enumerator(at: baseDirectory, includingPropertiesForKeys: [.fileSizeKey]) {
            for case let url as URL in enumerator {
                let resourceValues = try url.resourceValues(forKeys: [.fileSizeKey])
                size += resourceValues.fileSize ?? 0
            }
        }

        return size
    }
}

// MARK: - Supporting Types

private struct SpaceMetadata: Codable {
    let id: UUID
    var name: String?
    let createdAt: Date
    var updatedAt: Date
    var isCompressed: Bool
}

// MARK: - JSON Encoder/Decoder Extensions

extension JSONEncoder {
    static var hyperbasis: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

extension JSONDecoder {
    static var hyperbasis: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
