import Foundation

protocol MusicProvider: Sendable {
    var providerName: String { get }

    func isAvailable() async -> Bool
    func fetchNowPlaying() async throws -> NowPlayingTrack?
}
