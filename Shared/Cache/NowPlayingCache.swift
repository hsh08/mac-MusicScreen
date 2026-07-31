import AppKit
import Darwin
import Foundation
import os

enum NowPlayingCachePolicy {
    static let pollingInterval = Duration.seconds(1)
    static let staleAfter: TimeInterval = 10
    static let staleRetention: TimeInterval = 15
    static let maximumArtworkBytes = 10 * 1_024 * 1_024
}

struct CachedNowPlayingMetadata: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let revision: UInt64
    let trackID: String
    let title: String
    let artist: String
    let album: String?
    let playbackState: NowPlayingTrack.PlaybackState
    let source: MusicSource
    let updatedAt: Date
    let artworkRelativePath: String?
}

enum NowPlayingCacheLocation {
    static let metadataFilename = "now-playing.json"
    private static let applicationDirectoryName = "com.example.MusicScreen"
    private static let cacheDirectoryName = "NowPlayingCache"

    /// Foundation's home-directory URL is container-relative inside Apple's legacy
    /// screen-saver host. The POSIX account record provides the physical user home to
    /// both processes without embedding a username or an absolute path.
    static func directoryURL(fileManager: FileManager = .default) -> URL {
        physicalHomeDirectoryURL(fileManager: fileManager)
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent(applicationDirectoryName, isDirectory: true)
            .appendingPathComponent(cacheDirectoryName, isDirectory: true)
    }

    private static func physicalHomeDirectoryURL(fileManager: FileManager) -> URL {
        if let account = getpwuid(getuid()), let home = account.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: home), isDirectory: true)
        }
        return fileManager.homeDirectoryForCurrentUser
    }

    static func metadataURL(fileManager: FileManager = .default) -> URL {
        directoryURL(fileManager: fileManager)
            .appendingPathComponent(metadataFilename, isDirectory: false)
    }

    static func artworkDirectoryURL(fileManager: FileManager = .default) -> URL {
        directoryURL(fileManager: fileManager)
            .appendingPathComponent("Artwork", isDirectory: true)
    }

    static func artworkURL(
        forRelativePath relativePath: String,
        fileManager: FileManager = .default
    ) -> URL? {
        artworkURL(
            forRelativePath: relativePath,
            directoryURL: directoryURL(fileManager: fileManager)
        )
    }

    static func artworkURL(forRelativePath relativePath: String, directoryURL: URL) -> URL? {
        guard !relativePath.isEmpty, !relativePath.hasPrefix("/") else { return nil }
        let directory = directoryURL.standardizedFileURL
        let candidate = directory
            .appendingPathComponent(relativePath, isDirectory: false)
            .standardizedFileURL
        let directoryPrefix = directory.path.hasSuffix("/") ? directory.path : directory.path + "/"
        guard candidate.path.hasPrefix(directoryPrefix) else { return nil }
        return candidate
    }

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

enum SharedCacheState: String, Sendable {
    case fresh
    case stale
    case expired
    case missing
    case malformed
}

struct SharedCachePollResult: Sendable {
    let track: NowPlayingTrack?
    let state: SharedCacheState
    let revision: UInt64?
}

actor NowPlayingCacheReader {
    private let logger = Logger(subsystem: "com.example.MusicScreen", category: "CacheReader")
    private var lastModificationDate: Date?
    private var lastMetadata: CachedNowPlayingMetadata?
    private var lastTrack: NowPlayingTrack?
    private var didLogMissingMetadata = false
    private var lastReadWasMalformed = false

    private let customDirectoryURL: URL?

    init(directoryURL: URL? = nil) {
        customDirectoryURL = directoryURL
    }

    func poll(at now: Date = Date()) -> SharedCachePollResult {
        let fileManager = FileManager.default
        let directoryURL = customDirectoryURL
            ?? NowPlayingCacheLocation.directoryURL(fileManager: fileManager)
        let metadataURL = directoryURL.appendingPathComponent(
            NowPlayingCacheLocation.metadataFilename,
            isDirectory: false
        )
        let modificationDate: Date?
        do {
            modificationDate = try metadataURL
                .resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate
        } catch {
            modificationDate = nil
            if !didLogMissingMetadata {
                logger.error(
                    "Shared cache metadata unavailable at \(metadataURL.path, privacy: .public): \(error.localizedDescription, privacy: .public)"
                )
                didLogMissingMetadata = true
            }
        }

        if let modificationDate, modificationDate != lastModificationDate {
            do {
                let data = try Data(contentsOf: metadataURL, options: [.mappedIfSafe])
                let metadata = try NowPlayingCacheLocation.decoder.decode(
                    CachedNowPlayingMetadata.self,
                    from: data
                )
                guard metadata.schemaVersion == CachedNowPlayingMetadata.currentSchemaVersion else {
                    throw CocoaError(.coderInvalidValue)
                }

                let artworkData = loadArtworkIfNeeded(
                    for: metadata,
                    directoryURL: directoryURL,
                    fileManager: fileManager
                )
                lastMetadata = metadata
                lastTrack = NowPlayingTrack(
                    id: metadata.trackID,
                    title: metadata.title,
                    artist: metadata.artist,
                    album: metadata.album,
                    artworkData: artworkData,
                    artworkURL: nil,
                    playbackState: metadata.playbackState,
                    source: metadata.source,
                    updatedAt: metadata.updatedAt
                )
                lastModificationDate = modificationDate
                didLogMissingMetadata = false
                lastReadWasMalformed = false
                logger.info("Loaded shared cache revision \(metadata.revision, privacy: .public)")
            } catch {
                lastModificationDate = modificationDate
                lastReadWasMalformed = true
                logger.error("Ignoring malformed shared cache: \(error.localizedDescription, privacy: .public)")
                return retainedResult(at: now)
            }
        } else if modificationDate == nil, lastMetadata == nil {
            return SharedCachePollResult(track: nil, state: .missing, revision: nil)
        }

        return retainedResult(at: now)
    }

    private func retainedResult(at now: Date) -> SharedCachePollResult {
        guard let metadata = lastMetadata, let lastTrack else {
            return SharedCachePollResult(
                track: nil,
                state: lastReadWasMalformed ? .malformed : .missing,
                revision: nil
            )
        }

        let age = max(0, now.timeIntervalSince(metadata.updatedAt))
        if age <= NowPlayingCachePolicy.staleAfter {
            return SharedCachePollResult(
                track: lastTrack,
                state: lastReadWasMalformed ? .malformed : .fresh,
                revision: metadata.revision
            )
        }
        if age <= NowPlayingCachePolicy.staleAfter + NowPlayingCachePolicy.staleRetention {
            return SharedCachePollResult(
                track: lastTrack,
                state: lastReadWasMalformed ? .malformed : .stale,
                revision: metadata.revision
            )
        }
        return SharedCachePollResult(track: nil, state: .expired, revision: metadata.revision)
    }

    private func loadArtworkIfNeeded(
        for metadata: CachedNowPlayingMetadata,
        directoryURL: URL,
        fileManager: FileManager
    ) -> Data? {
        if metadata.trackID == lastMetadata?.trackID,
           metadata.artworkRelativePath == lastMetadata?.artworkRelativePath {
            return lastTrack?.artworkData
        }
        guard let relativePath = metadata.artworkRelativePath,
              let artworkURL = NowPlayingCacheLocation.artworkURL(
                forRelativePath: relativePath,
                directoryURL: directoryURL
              ),
              let data = try? Data(contentsOf: artworkURL, options: [.mappedIfSafe]),
              !data.isEmpty,
              data.count <= NowPlayingCachePolicy.maximumArtworkBytes,
              NSImage(data: data) != nil
        else {
            return nil
        }
        return data
    }
}
