import Foundation
import os

actor ProviderCoordinator: MusicProvider {
    nonisolated let providerName = "Provider Coordinator"

    private struct Candidate: Sendable {
        let track: NowPlayingTrack
        let changedAt: Date
    }

    private let appleMusic: any MusicProvider
    private let spotify: any MusicProvider
    private let demo: any MusicProvider
    private let logger = Logger(subsystem: "com.example.MusicScreen", category: "ProviderCoordinator")
    private var selection: ProviderSelection
    private var candidates: [MusicSource: Candidate] = [:]
    private var lastSelectedTrack: NowPlayingTrack?

    init(
        selection: ProviderSelection,
        appleMusic: any MusicProvider = AppleMusicProvider(),
        spotify: any MusicProvider = SpotifyProvider(),
        demo: any MusicProvider = MockMusicProvider()
    ) {
        self.selection = selection
        self.appleMusic = appleMusic
        self.spotify = spotify
        self.demo = demo
    }

    func setSelection(_ selection: ProviderSelection) {
        guard self.selection != selection else { return }
        self.selection = selection
        logger.info("Provider selection changed to \(selection.rawValue, privacy: .public)")
    }

    func isAvailable() async -> Bool {
        switch selection {
        case .automatic:
            let isAppleMusicAvailable = await appleMusic.isAvailable()
            let isSpotifyAvailable = await spotify.isAvailable()
            return isAppleMusicAvailable || isSpotifyAvailable
        case .appleMusic:
            return await appleMusic.isAvailable()
        case .spotify:
            return await spotify.isAvailable()
        case .demo:
            return true
        }
    }

    func fetchNowPlaying() async throws -> NowPlayingTrack? {
        switch selection {
        case .appleMusic:
            return try await fetchAndRemember(from: appleMusic, source: .appleMusic)
        case .spotify:
            return try await fetchAndRemember(from: spotify, source: .spotify)
        case .demo:
            return try await fetchAndRemember(from: demo, source: .demo)
        case .automatic:
            return try await fetchAutomatic()
        }
    }

    private func fetchAutomatic() async throws -> NowPlayingTrack? {
        // NSAppleScript executes Apple Events through process-global machinery.
        // Query providers sequentially so their script batches never overlap.
        let appleResult = await Self.result(from: appleMusic)
        let spotifyResult = await Self.result(from: spotify)
        var firstError: Error?
        for (source, result) in [(MusicSource.appleMusic, appleResult), (.spotify, spotifyResult)] {
            switch result {
            case let .success(track):
                updateCandidate(track, source: source)
            case let .failure(error):
                firstError = firstError ?? error
            }
        }

        let current = candidates.values.map(\.self)
        let selected = current
            .filter { $0.track.playbackState == .playing }
            .max { $0.changedAt < $1.changedAt }
            ?? current
                .filter { $0.track.playbackState == .paused }
                .max { $0.changedAt < $1.changedAt }
            ?? current.max { $0.changedAt < $1.changedAt }

        if let selected {
            if lastSelectedTrack?.source != selected.track.source {
                logger.info("Provider switched to \(selected.track.source.rawValue, privacy: .public)")
            }
            lastSelectedTrack = selected.track
            return selected.track
        }
        if let lastSelectedTrack { return lastSelectedTrack }
        if let firstError { throw firstError }
        return nil
    }

    private func fetchAndRemember(
        from provider: any MusicProvider,
        source: MusicSource
    ) async throws -> NowPlayingTrack? {
        let track = try await provider.fetchNowPlaying()
        updateCandidate(track, source: source)
        if let track { lastSelectedTrack = track }
        return track
    }

    private func updateCandidate(_ track: NowPlayingTrack?, source: MusicSource) {
        guard let track else {
            candidates.removeValue(forKey: source)
            return
        }
        let previous = candidates[track.source]
        let changedAt = if let previous, previous.track.hasSameSelectionContent(as: track) {
            previous.changedAt
        } else {
            Date()
        }
        candidates[track.source] = Candidate(track: track, changedAt: changedAt)
    }

    private static func result(from provider: any MusicProvider) async -> Result<NowPlayingTrack?, Error> {
        do {
            return .success(try await provider.fetchNowPlaying())
        } catch {
            return .failure(error)
        }
    }
}

private extension NowPlayingTrack {
    func hasSameSelectionContent(as other: NowPlayingTrack) -> Bool {
        id == other.id
            && title == other.title
            && artist == other.artist
            && album == other.album
            && playbackState == other.playbackState
            && source == other.source
    }
}
