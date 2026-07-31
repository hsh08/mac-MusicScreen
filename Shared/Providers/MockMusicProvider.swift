import Foundation

actor MockMusicProvider: MusicProvider {
    nonisolated let providerName = "Demo"

    private let track: NowPlayingTrack

    init(bundle: Bundle = .main) {
        let artworkData = bundle.url(forResource: "SampleArtwork", withExtension: "svg")
            .flatMap { try? Data(contentsOf: $0) }
        track = NowPlayingTrack(
            id: "demo-midnight-drive",
            title: "Midnight Drive",
            artist: "Neon Coast",
            album: "Afterglow",
            artworkData: artworkData,
            artworkURL: nil,
            playbackState: .playing,
            source: .demo,
            updatedAt: Date()
        )
    }

    func isAvailable() async -> Bool { true }

    func fetchNowPlaying() async throws -> NowPlayingTrack? { track }
}
