import AppKit
import CryptoKit
import Foundation
import os

struct CacheWriteReceipt: Sendable {
    let metadataURL: URL
    let artworkURL: URL?
    let revision: UInt64
    let wroteArtwork: Bool
    let isReady: Bool
    let writtenAt: Date
}

actor NowPlayingCacheWriter {
    private let logger = Logger(subsystem: "com.example.MusicScreen", category: "CacheWriter")
    private var revision: UInt64?
    private var lastArtworkTrackID: String?
    private var lastArtworkRelativePath: String?

    func write(_ track: NowPlayingTrack, at writtenAt: Date = Date()) throws -> CacheWriteReceipt {
        let fileManager = FileManager.default
        let artworkDirectory = NowPlayingCacheLocation.artworkDirectoryURL(fileManager: fileManager)
        try fileManager.createDirectory(at: artworkDirectory, withIntermediateDirectories: true)
        try restoreStateIfNeeded(fileManager: fileManager)

        var wroteArtwork = false
        var artworkRelativePath: String?
        if track.id == lastArtworkTrackID,
           let lastArtworkRelativePath,
           let existingURL = NowPlayingCacheLocation.artworkURL(
                forRelativePath: lastArtworkRelativePath,
                fileManager: fileManager
           ),
           fileManager.fileExists(atPath: existingURL.path) {
            artworkRelativePath = lastArtworkRelativePath
        } else if let artworkData = track.artworkData,
                  let encodedArtwork = Self.normalizedArtwork(artworkData) {
            let filename = "artwork-\(Self.digest(track.id)).\(encodedArtwork.extension)"
            let artworkURL = artworkDirectory.appendingPathComponent(filename, isDirectory: false)
            if !fileManager.fileExists(atPath: artworkURL.path) {
                try encodedArtwork.data.write(to: artworkURL, options: [.atomic])
                wroteArtwork = true
            }
            artworkRelativePath = "Artwork/\(filename)"
            lastArtworkTrackID = track.id
            lastArtworkRelativePath = artworkRelativePath
        } else {
            lastArtworkTrackID = track.id
            lastArtworkRelativePath = nil
        }

        let nextRevision = (revision ?? 0) &+ 1
        let metadata = CachedNowPlayingMetadata(
            schemaVersion: CachedNowPlayingMetadata.currentSchemaVersion,
            revision: nextRevision,
            trackID: track.id,
            title: track.title,
            artist: track.artist,
            album: track.album,
            playbackState: track.playbackState,
            source: track.source,
            updatedAt: writtenAt,
            artworkRelativePath: artworkRelativePath
        )
        let metadataData = try NowPlayingCacheLocation.encoder.encode(metadata)
        let metadataURL = NowPlayingCacheLocation.metadataURL(fileManager: fileManager)
        try metadataData.write(to: metadataURL, options: [.atomic])
        revision = nextRevision

        let artworkURL = artworkRelativePath.flatMap {
            NowPlayingCacheLocation.artworkURL(forRelativePath: $0, fileManager: fileManager)
        }
        logger.info(
            "Committed shared cache revision \(nextRevision, privacy: .public); artworkWritten=\(wroteArtwork, privacy: .public)"
        )
        return CacheWriteReceipt(
            metadataURL: metadataURL,
            artworkURL: artworkURL,
            revision: nextRevision,
            wroteArtwork: wroteArtwork,
            isReady: artworkRelativePath == nil || artworkURL != nil,
            writtenAt: writtenAt
        )
    }

    private func restoreStateIfNeeded(fileManager: FileManager) throws {
        guard revision == nil else { return }
        let metadataURL = NowPlayingCacheLocation.metadataURL(fileManager: fileManager)
        guard fileManager.fileExists(atPath: metadataURL.path) else {
            revision = 0
            return
        }
        do {
            let data = try Data(contentsOf: metadataURL)
            let metadata = try NowPlayingCacheLocation.decoder.decode(
                CachedNowPlayingMetadata.self,
                from: data
            )
            revision = metadata.revision
            lastArtworkTrackID = metadata.trackID
            lastArtworkRelativePath = metadata.artworkRelativePath
        } catch {
            revision = 0
            logger.error("Starting a new cache revision sequence: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func digest(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private static func normalizedArtwork(_ data: Data) -> (data: Data, extension: String)? {
        guard !data.isEmpty, data.count <= NowPlayingCachePolicy.maximumArtworkBytes else { return nil }
        if data.starts(with: [0xFF, 0xD8, 0xFF]) {
            return (data, "jpg")
        }
        if data.starts(with: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) {
            return (data, "png")
        }
        guard let image = NSImage(data: data),
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let jpeg = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.9])
        else {
            return nil
        }
        return (jpeg, "jpg")
    }
}
