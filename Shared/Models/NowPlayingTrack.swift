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
    /// UI-only playback metadata. The shared cache deliberately does not encode these values.
    let playbackPosition: TimeInterval?
    let duration: TimeInterval?
    let externalURL: URL?

    init(
        id: String,
        title: String,
        artist: String,
        album: String?,
        artworkData: Data?,
        artworkURL: URL?,
        playbackState: PlaybackState,
        source: MusicSource,
        updatedAt: Date,
        playbackPosition: TimeInterval? = nil,
        duration: TimeInterval? = nil,
        externalURL: URL? = nil
    ) {
        self.id = id
        self.title = title
        self.artist = artist
        self.album = album
        self.artworkData = artworkData
        self.artworkURL = artworkURL
        self.playbackState = playbackState
        self.source = source
        self.updatedAt = updatedAt
        self.playbackPosition = playbackPosition
        self.duration = duration
        self.externalURL = externalURL
    }
}
