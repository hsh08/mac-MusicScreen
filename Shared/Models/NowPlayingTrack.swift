import Foundation

enum MusicSource: String, Codable, Sendable {
    case appleMusic
    case spotify
    case demo
}

struct NowPlayingTrack: Identifiable, Equatable, Sendable {
    enum PlaybackState: String, Codable, Sendable {
        case playing
        case paused
        case stopped
    }

    let id: String
    let title: String
    let artist: String
    let album: String?
    let artworkData: Data?
    let artworkURL: URL?
    let playbackState: PlaybackState
    let source: MusicSource
    let updatedAt: Date
}
