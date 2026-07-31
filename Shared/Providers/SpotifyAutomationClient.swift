import AppKit
import Foundation
import os

struct SpotifySnapshot: Sendable {
    let playbackState: NowPlayingTrack.PlaybackState
    let title: String
    let artist: String
    let album: String?
    let trackID: String?
    let spotifyURL: String?
    let artworkURL: URL?

    var stableID: String {
        if let trackID, !trackID.isEmpty { return trackID }
        if let spotifyURL, !spotifyURL.isEmpty { return spotifyURL }
        return "spotify-metadata:\(title)\u{1f}\(artist)\u{1f}\(album ?? "")"
    }
}

enum SpotifySnapshotParser {
    static func parse(
        state: String,
        title: String?,
        artist: String?,
        album: String?,
        trackID: String?,
        spotifyURL: String?,
        artworkURL: String?
    ) throws -> SpotifySnapshot {
        let normalizedState = state.spotifyTrimmed
        guard let playbackState = NowPlayingTrack.PlaybackState(rawValue: normalizedState) else {
            throw SpotifyAutomationError.malformedResponse(field: "player state")
        }
        guard playbackState != .stopped else {
            return SpotifySnapshot(
                playbackState: .stopped,
                title: "",
                artist: "",
                album: nil,
                trackID: nil,
                spotifyURL: nil,
                artworkURL: nil
            )
        }

        guard let title = title?.spotifyTrimmed.spotifyNilIfEmpty,
              let artist = artist?.spotifyTrimmed.spotifyNilIfEmpty
        else {
            throw SpotifyAutomationError.unsupportedContent
        }
        return SpotifySnapshot(
            playbackState: playbackState,
            title: title,
            artist: artist,
            album: album?.spotifyTrimmed.spotifyNilIfEmpty,
            trackID: trackID?.spotifyTrimmed.spotifyNilIfEmpty,
            spotifyURL: spotifyURL?.spotifyTrimmed.spotifyNilIfEmpty,
            artworkURL: artworkURL
                .flatMap { URL(string: $0.spotifyTrimmed) }
        )
    }
}

enum SpotifyAutomationError: LocalizedError, Sendable {
    case scriptCreationFailed
    case permissionDenied
    case scriptFailed(code: Int, message: String)
    case malformedResponse(field: String)
    case unsupportedContent

    var errorDescription: String? {
        switch self {
        case .scriptCreationFailed:
            "Could not create the Spotify automation script."
        case .permissionDenied:
            "Spotify automation permission is required. Enable MusicScreen in System Settings > Privacy & Security > Automation."
        case let .scriptFailed(code, message):
            "Spotify automation failed (\(code)): \(message)"
        case let .malformedResponse(field):
            "Spotify returned an unexpected \(field) value."
        case .unsupportedContent:
            "Spotify is playing content without usable track metadata."
        }
    }
}

actor SpotifyAutomationClient {
    static let bundleIdentifier = "com.spotify.client"

    private let stateScript: NSAppleScript?
    private let titleScript: NSAppleScript?
    private let artistScript: NSAppleScript?
    private let albumScript: NSAppleScript?
    private let trackIDScript: NSAppleScript?
    private let spotifyURLScript: NSAppleScript?
    private let artworkURLScript: NSAppleScript?
    private let logger = Logger(subsystem: "com.example.MusicScreen", category: "SpotifyAutomation")

    init() {
        stateScript = NSAppleScript(source: "tell application \"Spotify\" to return player state as text")
        titleScript = NSAppleScript(source: "tell application \"Spotify\" to return name of current track")
        artistScript = NSAppleScript(source: "tell application \"Spotify\" to return artist of current track")
        albumScript = NSAppleScript(source: "tell application \"Spotify\" to return album of current track")
        trackIDScript = NSAppleScript(source: "tell application \"Spotify\" to return id of current track")
        spotifyURLScript = NSAppleScript(source: "tell application \"Spotify\" to return spotify url of current track")
        artworkURLScript = NSAppleScript(source: "tell application \"Spotify\" to return artwork url of current track")
    }

    nonisolated func isRunning() -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleIdentifier).isEmpty
    }

    func fetchSnapshot() throws -> SpotifySnapshot? {
        guard isRunning() else { return nil }
        guard let stateScript,
              let titleScript,
              let artistScript,
              let albumScript,
              let trackIDScript,
              let spotifyURLScript,
              let artworkURLScript
        else {
            throw SpotifyAutomationError.scriptCreationFailed
        }

        let snapshot = try SpotifySnapshotParser.parse(
            state: string(from: stateScript, label: "playerState"),
            title: string(from: titleScript, label: "title"),
            artist: string(from: artistScript, label: "artist"),
            album: optionalString(from: albumScript, label: "album"),
            trackID: optionalString(from: trackIDScript, label: "trackID"),
            spotifyURL: optionalString(from: spotifyURLScript, label: "spotifyURL"),
            artworkURL: optionalString(from: artworkURLScript, label: "artworkURL")
        )

#if DEBUG
        logger.debug(
            "Spotify metadata — title=\(snapshot.title, privacy: .public), artist=\(snapshot.artist, privacy: .public), album=\(snapshot.album ?? "<nil>", privacy: .public), state=\(snapshot.playbackState.rawValue, privacy: .public), artworkURL=\(snapshot.artworkURL?.absoluteString ?? "<nil>", privacy: .public)"
        )
#endif
        return snapshot
    }

    private func string(from script: NSAppleScript, label: String) throws -> String {
        let descriptor = try execute(script, label: label)
        guard let value = descriptor.stringValue?.spotifyTrimmed else {
            throw SpotifyAutomationError.malformedResponse(field: label)
        }
        return value
    }

    private func optionalString(from script: NSAppleScript, label: String) throws -> String? {
        try string(from: script, label: label).spotifyNilIfEmpty
    }

    private func execute(_ script: NSAppleScript, label: String) throws -> NSAppleEventDescriptor {
        var errorInfo: NSDictionary?
        let response = script.executeAndReturnError(&errorInfo)
        if let errorInfo {
            let code = errorInfo[NSAppleScript.errorNumber] as? Int ?? -1
            let message = errorInfo[NSAppleScript.errorMessage] as? String ?? "Unknown AppleScript error"
            logger.error("Spotify AppleScript[\(label, privacy: .public)] failed: \(code, privacy: .public) \(message, privacy: .public)")
            if code == -1743 { throw SpotifyAutomationError.permissionDenied }
            throw SpotifyAutomationError.scriptFailed(code: code, message: message)
        }
        return response
    }
}

private extension String {
    var spotifyTrimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var spotifyNilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
