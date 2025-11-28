//
//  HBCompression.swift
//  Hyperbasis
//
//  Compression utilities for world map data.
//

import Foundation
import Compression

/// Compression utilities for world map data
enum HBCompression {

    /// Compresses data using the specified level
    /// - Parameters:
    ///   - data: The data to compress
    ///   - level: Compression level
    /// - Returns: Compressed data
    /// - Throws: HBStorageError.compressionFailed if compression fails
    static func compress(_ data: Data, level: HBCompressionLevel) throws -> Data {
        switch level {
        case .none:
            return data
        case .balanced:
            return try compressZlib(data)
        }
    }

    /// Decompresses data
    /// - Parameter data: The compressed data
    /// - Returns: Decompressed data
    /// - Throws: HBStorageError.decompressionFailed if decompression fails
    static func decompress(_ data: Data) throws -> Data {
        do {
            return try decompressZlib(data)
        } catch {
            throw HBStorageError.decompressionFailed(underlying: error)
        }
    }

    // MARK: - Zlib Implementation

    private static func compressZlib(_ data: Data) throws -> Data {
        guard !data.isEmpty else { return data }

        var sourceBuffer = [UInt8](data)
        // Allocate destination buffer - compressed data should be smaller but allocate same size for safety
        var destinationBuffer = [UInt8](repeating: 0, count: data.count)

        let compressedSize = compression_encode_buffer(
            &destinationBuffer,
            destinationBuffer.count,
            &sourceBuffer,
            sourceBuffer.count,
            nil,
            COMPRESSION_ZLIB
        )

        guard compressedSize > 0 else {
            throw HBStorageError.compressionFailed
        }

        return Data(destinationBuffer.prefix(compressedSize))
    }

    private static func decompressZlib(_ data: Data) throws -> Data {
        guard !data.isEmpty else { return data }

        var sourceBuffer = [UInt8](data)

        // Start with 4x the compressed size, grow if needed
        var destinationBuffer = [UInt8](repeating: 0, count: data.count * 4)

        var decompressedSize = compression_decode_buffer(
            &destinationBuffer,
            destinationBuffer.count,
            &sourceBuffer,
            sourceBuffer.count,
            nil,
            COMPRESSION_ZLIB
        )

        // If buffer was too small (decompressed size equals buffer size), try larger
        if decompressedSize == destinationBuffer.count {
            destinationBuffer = [UInt8](repeating: 0, count: data.count * 10)
            decompressedSize = compression_decode_buffer(
                &destinationBuffer,
                destinationBuffer.count,
                &sourceBuffer,
                sourceBuffer.count,
                nil,
                COMPRESSION_ZLIB
            )
        }

        // If still too small, try even larger (for highly compressed data)
        if decompressedSize == destinationBuffer.count {
            destinationBuffer = [UInt8](repeating: 0, count: data.count * 50)
            decompressedSize = compression_decode_buffer(
                &destinationBuffer,
                destinationBuffer.count,
                &sourceBuffer,
                sourceBuffer.count,
                nil,
                COMPRESSION_ZLIB
            )
        }

        guard decompressedSize > 0 else {
            throw HBStorageError.decompressionFailed(underlying: nil)
        }

        return Data(destinationBuffer.prefix(decompressedSize))
    }
}
