//
//  HBCloudStore.swift
//  Hyperbasis
//
//  Handles Supabase cloud storage.
//  NOTE: This requires the Supabase Swift SDK as a dependency.
//

import Foundation

/// Handles Supabase cloud storage
/// NOTE: This requires the Supabase Swift SDK as a dependency
final class HBCloudStore {

    // MARK: - Properties

    private let supabaseUrl: String
    private let supabaseKey: String

    // TODO: Replace with actual Supabase client when SDK is integrated
    // private let client: SupabaseClient

    // MARK: - Initialization

    init(url: String, anonKey: String) {
        self.supabaseUrl = url
        self.supabaseKey = anonKey

        // TODO: Initialize Supabase client
        // self.client = SupabaseClient(supabaseURL: URL(string: url)!, supabaseKey: anonKey)
    }

    // MARK: - Space Operations

    func uploadSpace(_ space: HBStorageSpace) async throws {
        // 1. Upload world map blob to Storage
        let worldMapPath = "worldmaps/\(space.id.uuidString).bin"
        try await uploadBlob(data: space.worldMapData, path: worldMapPath)

        // 2. Get public URL for the blob
        let worldMapUrl = "\(supabaseUrl)/storage/v1/object/public/hyperbasis/\(worldMapPath)"

        // 3. Upsert space metadata to Postgres
        let spaceRow = SpaceRow(
            id: space.id,
            name: space.name,
            worldMapUrl: worldMapUrl,
            isCompressed: space.isCompressed,
            createdAt: space.createdAt,
            updatedAt: space.updatedAt
        )

        try await upsert(table: "spaces", data: spaceRow)
    }

    func downloadSpace(id: UUID) async throws -> HBStorageSpace? {
        // 1. Fetch metadata from Postgres
        guard let row: SpaceRow = try await fetch(table: "spaces", id: id) else {
            return nil
        }

        // 2. Download world map blob from Storage
        let worldMapData = try await downloadBlob(url: row.worldMapUrl)

        return HBStorageSpace(
            id: row.id,
            name: row.name,
            worldMapData: worldMapData,
            createdAt: row.createdAt,
            updatedAt: row.updatedAt,
            isCompressed: row.isCompressed
        )
    }

    func downloadSpacesModifiedSince(_ date: Date) async throws -> [HBStorageSpace] {
        // Fetch all spaces modified since date
        let rows: [SpaceRow] = try await fetchWhere(
            table: "spaces",
            column: "updated_at",
            greaterThan: date
        )

        var spaces: [HBStorageSpace] = []
        for row in rows {
            let worldMapData = try await downloadBlob(url: row.worldMapUrl)
            spaces.append(HBStorageSpace(
                id: row.id,
                name: row.name,
                worldMapData: worldMapData,
                createdAt: row.createdAt,
                updatedAt: row.updatedAt,
                isCompressed: row.isCompressed
            ))
        }

        return spaces
    }

    func deleteSpace(id: UUID) async throws {
        // Delete from Postgres (cascades to anchors)
        try await delete(table: "spaces", id: id)

        // Delete blob from Storage
        let worldMapPath = "worldmaps/\(id.uuidString).bin"
        try await deleteBlob(path: worldMapPath)
    }

    // MARK: - Anchor Operations

    func uploadAnchor(_ anchor: HBAnchor) async throws {
        let row = AnchorRow(
            id: anchor.id,
            spaceId: anchor.spaceId,
            transform: anchor.transform,
            metadata: anchor.metadata,
            createdAt: anchor.createdAt,
            updatedAt: anchor.updatedAt,
            deletedAt: anchor.deletedAt
        )

        try await upsert(table: "anchors", data: row)
    }

    func downloadAnchorsModifiedSince(_ date: Date) async throws -> [HBAnchor] {
        let rows: [AnchorRow] = try await fetchWhere(
            table: "anchors",
            column: "updated_at",
            greaterThan: date
        )

        return rows.map { row in
            HBAnchor(
                id: row.id,
                spaceId: row.spaceId,
                transform: row.transform,
                metadata: row.metadata,
                createdAt: row.createdAt,
                updatedAt: row.updatedAt,
                deletedAt: row.deletedAt
            )
        }
    }

    func purgeDeletedAnchors(before date: Date) async throws {
        // DELETE FROM anchors WHERE deleted_at < date
        try await deleteWhere(
            table: "anchors",
            column: "deleted_at",
            lessThan: date
        )
    }

    // MARK: - Supabase Helpers (TODO: Implement with actual SDK)

    private func uploadBlob(data: Data, path: String) async throws {
        // TODO: Use Supabase Storage SDK
        // try await client.storage.from("hyperbasis").upload(path: path, file: data)

        // Placeholder implementation using URLSession
        guard let url = URL(string: "\(supabaseUrl)/storage/v1/object/hyperbasis/\(path)") else {
            throw HBStorageError.invalidURL(path)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(supabaseKey)", forHTTPHeaderField: "Authorization")
        request.setValue(supabaseKey, forHTTPHeaderField: "apikey")
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.httpBody = data

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw HBStorageError.uploadFailed(underlying: NSError(
                domain: "HBCloudStore",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Upload failed"]
            ))
        }
    }

    private func downloadBlob(url: String) async throws -> Data {
        guard let blobUrl = URL(string: url) else {
            throw HBStorageError.invalidURL(url)
        }

        var request = URLRequest(url: blobUrl)
        request.setValue("Bearer \(supabaseKey)", forHTTPHeaderField: "Authorization")
        request.setValue(supabaseKey, forHTTPHeaderField: "apikey")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw HBStorageError.downloadFailed
        }

        return data
    }

    private func deleteBlob(path: String) async throws {
        // TODO: Use Supabase Storage SDK
        guard let url = URL(string: "\(supabaseUrl)/storage/v1/object/hyperbasis/\(path)") else {
            throw HBStorageError.invalidURL(path)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(supabaseKey)", forHTTPHeaderField: "Authorization")
        request.setValue(supabaseKey, forHTTPHeaderField: "apikey")

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw HBStorageError.fileOperationFailed(underlying: NSError(
                domain: "HBCloudStore",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Delete blob failed"]
            ))
        }
    }

    private func upsert<T: Encodable>(table: String, data: T) async throws {
        // TODO: Use Supabase Postgres SDK
        guard let url = URL(string: "\(supabaseUrl)/rest/v1/\(table)") else {
            throw HBStorageError.invalidURL(table)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(supabaseKey)", forHTTPHeaderField: "Authorization")
        request.setValue(supabaseKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("resolution=merge-duplicates", forHTTPHeaderField: "Prefer")

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        request.httpBody = try encoder.encode(data)

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw HBStorageError.uploadFailed(underlying: NSError(
                domain: "HBCloudStore",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Upsert failed"]
            ))
        }
    }

    private func fetch<T: Decodable>(table: String, id: UUID) async throws -> T? {
        // TODO: Use Supabase Postgres SDK
        guard let url = URL(string: "\(supabaseUrl)/rest/v1/\(table)?id=eq.\(id.uuidString)") else {
            throw HBStorageError.invalidURL(table)
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(supabaseKey)", forHTTPHeaderField: "Authorization")
        request.setValue(supabaseKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw HBStorageError.downloadFailed
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let results = try decoder.decode([T].self, from: data)
        return results.first
    }

    private func fetchWhere<T: Decodable>(table: String, column: String, greaterThan date: Date) async throws -> [T] {
        // TODO: Use Supabase Postgres SDK
        let formatter = ISO8601DateFormatter()
        let dateString = formatter.string(from: date)

        guard let url = URL(string: "\(supabaseUrl)/rest/v1/\(table)?\(column)=gt.\(dateString)") else {
            throw HBStorageError.invalidURL(table)
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(supabaseKey)", forHTTPHeaderField: "Authorization")
        request.setValue(supabaseKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw HBStorageError.downloadFailed
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([T].self, from: data)
    }

    private func delete(table: String, id: UUID) async throws {
        // TODO: Use Supabase Postgres SDK
        guard let url = URL(string: "\(supabaseUrl)/rest/v1/\(table)?id=eq.\(id.uuidString)") else {
            throw HBStorageError.invalidURL(table)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(supabaseKey)", forHTTPHeaderField: "Authorization")
        request.setValue(supabaseKey, forHTTPHeaderField: "apikey")

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw HBStorageError.fileOperationFailed(underlying: NSError(
                domain: "HBCloudStore",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Delete failed"]
            ))
        }
    }

    private func deleteWhere(table: String, column: String, lessThan date: Date) async throws {
        // TODO: Use Supabase Postgres SDK
        let formatter = ISO8601DateFormatter()
        let dateString = formatter.string(from: date)

        guard let url = URL(string: "\(supabaseUrl)/rest/v1/\(table)?\(column)=lt.\(dateString)") else {
            throw HBStorageError.invalidURL(table)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(supabaseKey)", forHTTPHeaderField: "Authorization")
        request.setValue(supabaseKey, forHTTPHeaderField: "apikey")

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw HBStorageError.fileOperationFailed(underlying: NSError(
                domain: "HBCloudStore",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Delete where failed"]
            ))
        }
    }
}

// MARK: - Database Row Types

private struct SpaceRow: Codable {
    let id: UUID
    var name: String?
    var worldMapUrl: String
    var isCompressed: Bool
    let createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case worldMapUrl = "world_map_url"
        case isCompressed = "is_compressed"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

private struct AnchorRow: Codable {
    let id: UUID
    let spaceId: UUID
    var transform: [Float]
    var metadata: [String: AnyCodableValue]
    let createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case spaceId = "space_id"
        case transform
        case metadata
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
    }
}
