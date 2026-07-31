import Foundation
import Testing
@testable import MusicScreen

struct MusicScreenTests {
    @Test func spotifySnapshotParsing() throws {
        let snapshot = try SpotifySnapshotParser.parse(
            state: " playing\n",
            title: "긴 제목 🎵",
            artist: "Artist",
            album: "Album",
            trackID: "spotify:track:123",
            spotifyURL: "spotify:track:123",
            artworkURL: "https://i.scdn.co/image/example"
        )
        #expect(snapshot.playbackState == .playing)
        #expect(snapshot.stableID == "spotify:track:123")
        #expect(snapshot.title == "긴 제목 🎵")
        #expect(snapshot.artworkURL?.scheme == "https")
    }

    @Test func spotifyMissingAndMalformedValues() {
        #expect(throws: SpotifyAutomationError.self) {
            try SpotifySnapshotParser.parse(
                state: "playing",
                title: "",
                artist: "Artist",
                album: nil,
                trackID: nil,
                spotifyURL: nil,
                artworkURL: nil
            )
        }
        #expect(throws: SpotifyAutomationError.self) {
            try SpotifySnapshotParser.parse(
                state: "unknown",
                title: "Title",
                artist: "Artist",
                album: nil,
                trackID: nil,
                spotifyURL: nil,
                artworkURL: nil
            )
        }
    }

    @Test func artworkURLValidation() {
        #expect(SpotifyArtworkLoader.isValidArtworkURL(URL(string: "https://i.scdn.co/image/a")!))
        #expect(!SpotifyArtworkLoader.isValidArtworkURL(URL(string: "http://i.scdn.co/image/a")!))
        #expect(!SpotifyArtworkLoader.isValidArtworkURL(URL(string: "file:///tmp/a.jpg")!))
    }

    @Test func staleArtworkIdentityIsRejected() {
        let oldURL = URL(string: "https://i.scdn.co/image/old")!
        let newURL = URL(string: "https://i.scdn.co/image/new")!
        #expect(SpotifyProvider.isCurrentArtworkResponse(
            responseTrackID: "new",
            responseURL: newURL,
            currentTrackID: "new",
            currentURL: newURL
        ))
        #expect(!SpotifyProvider.isCurrentArtworkResponse(
            responseTrackID: "old",
            responseURL: oldURL,
            currentTrackID: "new",
            currentURL: newURL
        ))
    }

    @Test func autoSelectionAndSpotifyFailureFallback() async throws {
        let apple = StubProvider(name: "Apple", result: .track(Self.track(source: .appleMusic, state: .paused)))
        let spotify = StubProvider(name: "Spotify", result: .track(Self.track(source: .spotify, state: .playing)))
        let coordinator = ProviderCoordinator(
            selection: .automatic,
            appleMusic: apple,
            spotify: spotify,
            demo: StubProvider(name: "Demo", result: .none)
        )
        #expect(try await coordinator.fetchNowPlaying()?.source == .spotify)

        await apple.setResult(.track(Self.track(source: .appleMusic, state: .playing)))
        await spotify.setResult(.failure)
        #expect(try await coordinator.fetchNowPlaying()?.source == .appleMusic)
    }

    @Test func cacheRoundTripAndDuplicateSuppression() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MusicScreenTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let writer = NowPlayingCacheWriter(directoryURL: directory)
        let track = Self.track(source: .spotify, state: .paused, artworkData: Self.onePixelPNG)
        let first = try await writer.write(track, at: Date())
        let duplicate = try await writer.write(track, at: first.writtenAt.addingTimeInterval(1))
        #expect(first.revision == duplicate.revision)
        #expect(first.artworkURL != nil)

        let reader = NowPlayingCacheReader(directoryURL: directory)
        let result = await reader.poll(at: first.writtenAt.addingTimeInterval(2))
        #expect(result.state == .fresh)
        #expect(result.track?.title == track.title)
        #expect(result.track?.artworkData != nil)

        try Data("{".utf8).write(to: first.metadataURL, options: .atomic)
        let malformed = await reader.poll(at: first.writtenAt.addingTimeInterval(3))
        #expect(malformed.track?.id == track.id)
        #expect(malformed.state == .malformed)
    }

    @MainActor
    @Test func monitorStartStopCancelsPollingTask() {
        let monitor = NowPlayingMonitor(provider: StubProvider(name: "Stub", result: .none))
        #expect(!monitor.isMonitoring)
        monitor.start()
        #expect(monitor.isMonitoring)
        monitor.stop()
        #expect(!monitor.isMonitoring)
    }

    private static func track(
        source: MusicSource,
        state: NowPlayingTrack.PlaybackState,
        artworkData: Data? = nil
    ) -> NowPlayingTrack {
        NowPlayingTrack(
            id: "\(source.rawValue)-track",
            title: "Title",
            artist: "Artist",
            album: "Album",
            artworkData: artworkData,
            artworkURL: nil,
            playbackState: state,
            source: source,
            updatedAt: Date()
        )
    }

    private static let onePixelPNG = Data(base64Encoded:
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
    )!
}

private enum StubResult: Sendable {
    case track(NowPlayingTrack)
    case none
    case failure
}

private enum StubError: Error {
    case failed
}

private actor StubProvider: MusicProvider {
    nonisolated let providerName: String
    private var result: StubResult

    init(name: String, result: StubResult) {
        providerName = name
        self.result = result
    }

    func setResult(_ result: StubResult) {
        self.result = result
    }

    func isAvailable() async -> Bool {
        if case .none = result { return false }
        return true
    }

    func fetchNowPlaying() async throws -> NowPlayingTrack? {
        switch result {
        case let .track(track): track
        case .none: nil
        case .failure: throw StubError.failed
        }
    }
}
