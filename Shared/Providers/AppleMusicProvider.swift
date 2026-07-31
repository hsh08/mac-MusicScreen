import AppKit
import Foundation
import ImageIO
import os

actor AppleMusicProvider: MusicProvider {
    nonisolated let providerName = "Apple Music"

    /// A stopped player keeps its most recent track briefly before the UI returns to the empty state.
    static let stoppedTrackRetention: Duration = .seconds(15)

    private let client: AppleMusicClient
    private let logger = Logger(subsystem: "com.example.MusicScreen", category: "AppleMusicProvider")
    private var lastTrack: NowPlayingTrack?
    private var stoppedAt: ContinuousClock.Instant?
    private var artworkCache = ArtworkMemoryCache(maximumBytes: 24 * 1_024 * 1_024)

    init(client: AppleMusicClient = AppleMusicClient()) {
        self.client = client
    }

    func isAvailable() async -> Bool {
        let available = client.isRunning()
        logger.debug("Provider availability: \(available, privacy: .public)")
        return available
    }

    func fetchNowPlaying() async throws -> NowPlayingTrack? {
#if DEBUG
        logger.debug("fetchNowPlaying called")
#endif
        guard let snapshot = try await client.fetchSnapshot() else {
            if lastTrack != nil {
                logger.info("Music app is not running; clearing retained track")
            }
            lastTrack = nil
            stoppedAt = nil
            return nil
        }

        if snapshot.playbackState == .stopped {
            return retainedStoppedTrack()
        }

        stoppedAt = nil
        if let lastTrack,
           lastTrack.id == snapshot.stableID,
           lastTrack.title == snapshot.title,
           lastTrack.artist == snapshot.artist,
           lastTrack.album == snapshot.album,
           lastTrack.playbackState == snapshot.playbackState {
            return lastTrack
        }

        let artworkData = await artwork(for: snapshot)
        let track = NowPlayingTrack(
            id: snapshot.stableID,
            title: snapshot.title,
            artist: snapshot.artist,
            album: snapshot.album,
            artworkData: artworkData,
            artworkURL: nil,
            playbackState: snapshot.playbackState,
            source: .appleMusic,
            updatedAt: Date()
        )

        if lastTrack?.id != track.id {
            logger.info("Apple Music track changed: \(track.id, privacy: .private(mask: .hash))")
        } else if lastTrack?.playbackState != track.playbackState {
            logger.info("Playback state changed: \(track.playbackState.rawValue, privacy: .public)")
        }
#if DEBUG
        logger.debug(
            "Returning track — title=\(track.title, privacy: .public), artist=\(track.artist, privacy: .public), album=\(track.album ?? "<nil>", privacy: .public), state=\(track.playbackState.rawValue, privacy: .public)"
        )
#endif
        lastTrack = track
        return track
    }

    private func retainedStoppedTrack() -> NowPlayingTrack? {
        guard let lastTrack else { return nil }
        let clock = ContinuousClock()
        if stoppedAt == nil {
            stoppedAt = clock.now
            let stoppedTrack = NowPlayingTrack(
                id: lastTrack.id,
                title: lastTrack.title,
                artist: lastTrack.artist,
                album: lastTrack.album,
                artworkData: lastTrack.artworkData,
                artworkURL: lastTrack.artworkURL,
                playbackState: .stopped,
                source: lastTrack.source,
                updatedAt: Date()
            )
            self.lastTrack = stoppedTrack
            logger.info("Playback stopped; retaining the last track temporarily")
            return stoppedTrack
        }

        guard let stoppedAt,
              stoppedAt.duration(to: clock.now) < Self.stoppedTrackRetention
        else {
            self.lastTrack = nil
            self.stoppedAt = nil
            logger.info("Stopped-track retention expired")
            return nil
        }
        return lastTrack
    }

    private func artwork(for snapshot: AppleMusicSnapshot) async -> Data? {
        if lastTrack?.id == snapshot.stableID {
            return lastTrack?.artworkData
        }
        if let cached = artworkCache.value(forKey: snapshot.stableID) {
            logger.debug("Artwork cache hit")
            return cached
        }

        logger.debug("Artwork cache miss")
        do {
            guard let data = try await client.fetchArtwork(expectedTrackID: snapshot.stableID)
            else {
                return nil
            }
            let validation = ArtworkMemoryCache.validate(data)
#if DEBUG
            logger.debug(
                "Artwork validation — byteCount=\(data.count, privacy: .public), NSImage=\(validation.hasNSImage, privacy: .public), imageType=\(validation.imageType ?? "<nil>", privacy: .public)"
            )
#endif
            guard validation.hasNSImage, validation.imageType != nil else { return nil }
            artworkCache.insert(data, forKey: snapshot.stableID)
            return data
        } catch {
            logger.error("Artwork lookup failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}

private struct ArtworkMemoryCache: Sendable {
    private let maximumBytes: Int
    private let maximumItemBytes = 10 * 1_024 * 1_024
    private var values: [String: Data] = [:]
    private var insertionOrder: [String] = []
    private var totalBytes = 0

    init(maximumBytes: Int) {
        self.maximumBytes = maximumBytes
    }

    mutating func value(forKey key: String) -> Data? {
        values[key]
    }

    mutating func insert(_ data: Data, forKey key: String) {
        guard data.count <= maximumItemBytes else { return }
        if let oldValue = values.updateValue(data, forKey: key) {
            totalBytes -= oldValue.count
        } else {
            insertionOrder.append(key)
        }
        totalBytes += data.count

        while totalBytes > maximumBytes, let oldestKey = insertionOrder.first {
            insertionOrder.removeFirst()
            if let removed = values.removeValue(forKey: oldestKey) {
                totalBytes -= removed.count
            }
        }
    }

    static func validate(_ data: Data) -> (hasNSImage: Bool, imageType: String?) {
        guard !data.isEmpty, data.count <= 10 * 1_024 * 1_024 else { return (false, nil) }
        let imageSource = CGImageSourceCreateWithData(data as CFData, nil)
        let imageType = imageSource.flatMap { CGImageSourceGetType($0) as String? }
        return (NSImage(data: data) != nil, imageType)
    }
}
