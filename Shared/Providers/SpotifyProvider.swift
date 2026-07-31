import AppKit
import Foundation
import ImageIO
import os

actor SpotifyProvider: MusicProvider {
    nonisolated let providerName = "Spotify"

    static let stoppedTrackRetention: Duration = .seconds(15)

    private let client: SpotifyAutomationClient
    private let artworkLoader: SpotifyArtworkLoader
    private let logger = Logger(subsystem: "com.example.MusicScreen", category: "SpotifyProvider")
    private var lastTrack: NowPlayingTrack?
    private var stoppedAt: ContinuousClock.Instant?
    private var artworkTask: Task<Void, Never>?
    private var artworkTrackID: String?
    private var artworkURL: URL?
    private var artworkData: Data?

    init(
        client: SpotifyAutomationClient = SpotifyAutomationClient(),
        artworkLoader: SpotifyArtworkLoader = SpotifyArtworkLoader()
    ) {
        self.client = client
        self.artworkLoader = artworkLoader
    }

    func isAvailable() async -> Bool {
        client.isRunning()
    }

    func fetchNowPlaying() async throws -> NowPlayingTrack? {
        guard let snapshot = try await client.fetchSnapshot() else {
            clearRetainedTrack()
            return nil
        }
        if snapshot.playbackState == .stopped {
            return retainedStoppedTrack()
        }

        stoppedAt = nil
        prepareArtwork(for: snapshot)
        let resolvedArtwork = artworkTrackID == snapshot.stableID ? artworkData : nil
        let candidate = NowPlayingTrack(
            id: snapshot.stableID,
            title: snapshot.title,
            artist: snapshot.artist,
            album: snapshot.album,
            artworkData: resolvedArtwork,
            artworkURL: snapshot.artworkURL,
            playbackState: snapshot.playbackState,
            source: .spotify,
            updatedAt: Date()
        )
        if let lastTrack, lastTrack.hasSameDisplayContent(as: candidate) {
            return lastTrack
        }
        self.lastTrack = candidate
        return candidate
    }

    private func prepareArtwork(for snapshot: SpotifySnapshot) {
        let trackID = snapshot.stableID
        guard artworkTrackID != trackID || artworkURL != snapshot.artworkURL else { return }

        artworkTask?.cancel()
        artworkTrackID = trackID
        artworkURL = snapshot.artworkURL
        artworkData = nil
        guard let url = snapshot.artworkURL else { return }

        artworkTask = Task { [weak self, artworkLoader] in
            do {
                let data = try await artworkLoader.data(from: url)
                guard !Task.isCancelled else { return }
                await self?.acceptArtwork(data, for: trackID, url: url)
            } catch is CancellationError {
                return
            } catch {
                await self?.logArtworkFailure(error)
            }
        }
    }

    private func acceptArtwork(_ data: Data, for trackID: String, url: URL) {
        guard Self.isCurrentArtworkResponse(
            responseTrackID: trackID,
            responseURL: url,
            currentTrackID: artworkTrackID,
            currentURL: artworkURL
        ) else {
            logger.debug("Discarded stale Spotify artwork response")
            return
        }
        artworkData = data
    }

    nonisolated static func isCurrentArtworkResponse(
        responseTrackID: String,
        responseURL: URL,
        currentTrackID: String?,
        currentURL: URL?
    ) -> Bool {
        responseTrackID == currentTrackID && responseURL == currentURL
    }

    private func logArtworkFailure(_ error: Error) {
        logger.error("Spotify artwork download failed: \(error.localizedDescription, privacy: .public)")
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
                source: .spotify,
                updatedAt: Date()
            )
            self.lastTrack = stoppedTrack
            return stoppedTrack
        }
        guard let stoppedAt,
              stoppedAt.duration(to: clock.now) < Self.stoppedTrackRetention
        else {
            clearRetainedTrack()
            return nil
        }
        return lastTrack
    }

    private func clearRetainedTrack() {
        artworkTask?.cancel()
        artworkTask = nil
        lastTrack = nil
        stoppedAt = nil
        artworkTrackID = nil
        artworkURL = nil
        artworkData = nil
    }
}

enum SpotifyArtworkError: LocalizedError, Sendable {
    case invalidURL
    case invalidResponse
    case invalidStatus(Int)
    case invalidContentType(String?)
    case tooLarge
    case invalidImage

    var errorDescription: String? {
        switch self {
        case .invalidURL: "Spotify artwork URL must be HTTPS."
        case .invalidResponse: "Spotify artwork returned a non-HTTP response."
        case let .invalidStatus(code): "Spotify artwork returned HTTP \(code)."
        case let .invalidContentType(type): "Spotify artwork returned invalid content type \(type ?? "<missing>")."
        case .tooLarge: "Spotify artwork exceeded the 10 MB limit."
        case .invalidImage: "Spotify artwork data could not be decoded as an image."
        }
    }
}

actor SpotifyArtworkLoader {
    static let maximumBytes = 10 * 1_024 * 1_024

    private let session: URLSession
    private var cache: [URL: Data] = [:]
    private var insertionOrder: [URL] = []
    private var totalBytes = 0
    private let maximumCacheBytes = 24 * 1_024 * 1_024

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 5
            configuration.timeoutIntervalForResource = 8
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            self.session = URLSession(configuration: configuration)
        }
    }

    func data(from url: URL) async throws -> Data {
        guard Self.isValidArtworkURL(url) else { throw SpotifyArtworkError.invalidURL }
        if let cached = cache[url] { return cached }

        var request = URLRequest(url: url, timeoutInterval: 5)
        request.setValue("bytes=0-\(Self.maximumBytes)", forHTTPHeaderField: "Range")
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse else {
            throw SpotifyArtworkError.invalidResponse
        }
        guard (200...299).contains(http.statusCode) else {
            throw SpotifyArtworkError.invalidStatus(http.statusCode)
        }
        let contentType = http.value(forHTTPHeaderField: "Content-Type")?.lowercased()
        guard contentType?.hasPrefix("image/") == true else {
            throw SpotifyArtworkError.invalidContentType(contentType)
        }
        guard data.count <= Self.maximumBytes,
              response.expectedContentLength <= 0 || response.expectedContentLength <= Int64(Self.maximumBytes)
        else {
            throw SpotifyArtworkError.tooLarge
        }
        guard !data.isEmpty,
              CGImageSourceCreateWithData(data as CFData, nil) != nil,
              NSImage(data: data) != nil
        else {
            throw SpotifyArtworkError.invalidImage
        }
        insert(data, for: url)
        return data
    }

    nonisolated static func isValidArtworkURL(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https" && url.host?.isEmpty == false
    }

    private func insert(_ data: Data, for url: URL) {
        if let previous = cache.updateValue(data, forKey: url) {
            totalBytes -= previous.count
        } else {
            insertionOrder.append(url)
        }
        totalBytes += data.count
        while totalBytes > maximumCacheBytes, let oldest = insertionOrder.first {
            insertionOrder.removeFirst()
            if let removed = cache.removeValue(forKey: oldest) {
                totalBytes -= removed.count
            }
        }
    }
}

private extension NowPlayingTrack {
    func hasSameDisplayContent(as other: NowPlayingTrack) -> Bool {
        id == other.id
            && title == other.title
            && artist == other.artist
            && album == other.album
            && artworkData == other.artworkData
            && artworkURL == other.artworkURL
            && playbackState == other.playbackState
            && source == other.source
    }
}
