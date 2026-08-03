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
            artworkURL: "https://i.scdn.co/image/example",
            playbackPosition: "102.5",
            durationMilliseconds: "243000"
        )
        #expect(snapshot.playbackState == .playing)
        #expect(snapshot.stableID == "spotify:track:123")
        #expect(snapshot.title == "긴 제목 🎵")
        #expect(snapshot.artworkURL?.scheme == "https")
        #expect(snapshot.playbackPosition == 102.5)
        #expect(snapshot.duration == 243)
    }

    @Test func playbackProgressFormattingAndInterpolation() {
        let updatedAt = Date(timeIntervalSince1970: 100)
        let track = NowPlayingTrack(
            id: "progress",
            title: "Title",
            artist: "Artist",
            album: nil,
            artworkData: nil,
            artworkURL: nil,
            playbackState: .playing,
            source: .spotify,
            updatedAt: updatedAt,
            playbackPosition: 102,
            duration: 243
        )
        let progress = PlaybackProgress.values(
            for: track,
            at: updatedAt.addingTimeInterval(2.5)
        )
        #expect(progress.position == 104.5)
        #expect(progress.duration == 243)
        #expect(PlaybackProgress.format(102) == "1:42")
        #expect(PlaybackProgress.format(243) == "4:03")
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

    @MainActor
    @Test func companionOwnsOneMonitorAndStopsCleanly() {
        let suiteName = "MusicScreenTests.Companion.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = SharedSettings(defaults: defaults)
        let coordinator = ProviderCoordinator(
            selection: .demo,
            appleMusic: StubProvider(name: "Apple", result: .none),
            spotify: StubProvider(name: "Spotify", result: .none),
            demo: StubProvider(name: "Demo", result: .track(Self.track(source: .demo, state: .playing)))
        )
        let model = CompanionStatusModel(
            settings: settings,
            coordinator: coordinator,
            defaults: defaults,
            startsImmediately: false
        )
        let identity = model.monitorIdentity
        model.start()
        model.start()
        #expect(model.monitorIdentity == identity)
        #expect(model.isMonitoring)
        model.stop()
        #expect(!model.isMonitoring)
    }

    @MainActor
    @Test func sourceChangeCancelsAndReplacesPollingTask() async {
        let suiteName = "MusicScreenTests.SourceChange.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = SharedSettings(defaults: defaults)
        let coordinator = ProviderCoordinator(
            selection: .automatic,
            appleMusic: StubProvider(name: "Apple", result: .none),
            spotify: StubProvider(name: "Spotify", result: .none),
            demo: StubProvider(name: "Demo", result: .none)
        )
        let model = CompanionStatusModel(
            settings: settings,
            coordinator: coordinator,
            defaults: defaults,
            startsImmediately: true
        )
        let initialGeneration = model.monitoringGeneration

        settings.musicSource = .spotify
        try? await Task.sleep(for: .milliseconds(50))

        #expect(model.isMonitoring)
        #expect(model.monitoringGeneration > initialGeneration)
        model.stop()
    }

    @MainActor
    @Test func settingsSaveAndRestore() {
        let suiteName = "MusicScreenTests.Settings.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let first = SharedSettings(defaults: defaults)
        first.musicSource = .spotify
        first.showsTime = false
        first.showsDate = false
        first.showsTitle = false
        first.showsArtist = false
        first.artworkSize = .large
        first.blurRadius = 72
        first.backgroundDarkness = 0.6

        let restored = SharedSettings(defaults: defaults)
        #expect(restored.musicSource == .spotify)
        #expect(!restored.showsTime)
        #expect(!restored.showsDate)
        #expect(!restored.showsTitle)
        #expect(!restored.showsArtist)
        #expect(restored.artworkSize == .large)
        #expect(restored.blurRadius == 72)
        #expect(restored.backgroundDarkness == 0.6)
    }

    @MainActor
    @Test func providerStatusMapping() {
        #expect(CompanionStatusModel.connectionState(errorMessage: nil) == .connected)
        #expect(CompanionStatusModel.connectionState(errorMessage: "Automation permission is required") == .permissionRequired)
        #expect(CompanionStatusModel.connectionState(errorMessage: "Unexpected provider response") == .error)
    }

    @MainActor
    @Test func emptyTrackAndCacheStatusPresentation() {
        let suiteName = "MusicScreenTests.Presentation.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let model = CompanionStatusModel(
            settings: SharedSettings(defaults: defaults),
            defaults: defaults,
            startsImmediately: false
        )
        #expect(model.currentTrackTitle == "No music playing")
        #expect(model.currentArtistLabel == "Start playback in Apple Music or Spotify")
        #expect(CompanionStatusModel.cacheStatusLabel(writeSucceeded: nil, lastRefreshAt: nil) == "Waiting for Track Data")
        #expect(CompanionStatusModel.cacheStatusLabel(
            writeSucceeded: true,
            lastRefreshAt: Date(timeIntervalSince1970: 0),
            now: Date(timeIntervalSince1970: 20)
        ) == "Cache Stale")
    }

    @Test func launchAtLoginStatusMapping() {
        #expect(LaunchAtLoginState.map(.enabled) == .enabled)
        #expect(LaunchAtLoginState.map(.notRegistered) == .disabled)
        #expect(LaunchAtLoginState.map(.requiresApproval) == .requiresApproval)
        #expect(LaunchAtLoginState.map(.notFound) == .unavailable)
    }

    @Test func onlyPrimaryNonTestInstanceStartsMonitoring() {
        #expect(ApplicationLaunchPolicy.shouldStartMonitoring(
            isPrimaryInstance: true,
            isRunningTests: false
        ))
        #expect(!ApplicationLaunchPolicy.shouldStartMonitoring(
            isPrimaryInstance: false,
            isRunningTests: false
        ))
        #expect(!ApplicationLaunchPolicy.shouldStartMonitoring(
            isPrimaryInstance: true,
            isRunningTests: true
        ))
    }

    @Test func instanceLockNameUsesNormalizedBundleIdentifier() {
        #expect(ApplicationInstanceLockName.filename(
            bundleIdentifier: "com.example.MusicScreen"
        ) == "com.example.MusicScreen.instance.lock")
        #expect(ApplicationInstanceLockName.filename(
            bundleIdentifier: "com/example:MusicScreen"
        ) == "com-example-MusicScreen.instance.lock")
    }

    @Test func instanceLockNameUsesSafeFallbackWithoutBundleIdentifier() {
        #expect(ApplicationInstanceLockName.filename(
            bundleIdentifier: nil
        ) == "MusicScreen.instance.lock")
        #expect(ApplicationInstanceLockName.filename(
            bundleIdentifier: " / "
        ) == "MusicScreen.instance.lock")
    }

    @Test func differentBundleIdentifiersUseDifferentLockPaths() {
        let directory = URL(fileURLWithPath: "/tmp", isDirectory: true)
        let production = ApplicationInstanceLockName.url(
            bundleIdentifier: "com.example.MusicScreen",
            in: directory
        )
        let development = ApplicationInstanceLockName.url(
            bundleIdentifier: "com.example.MusicScreen.debug",
            in: directory
        )
        #expect(production != development)
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
