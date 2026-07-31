import AppKit
import Foundation
import os

struct AppleMusicSnapshot: Sendable {
    let playbackState: NowPlayingTrack.PlaybackState
    let title: String
    let artist: String
    let album: String?
    let persistentID: String?
    let databaseID: Int32?

    var stableID: String {
        if let persistentID, !persistentID.isEmpty {
            return "apple-persistent:\(persistentID)"
        }
        if let databaseID {
            return "apple-database:\(databaseID)"
        }
        return "apple-metadata:\(title)\u{1f}\(artist)\u{1f}\(album ?? "")"
    }
}

enum AppleMusicClientError: LocalizedError, Sendable {
    case scriptCreationFailed
    case scriptFailed(code: Int, message: String)
    case malformedResponse

    var errorDescription: String? {
        switch self {
        case .scriptCreationFailed:
            "Could not create the Apple Music automation script."
        case let .scriptFailed(code, message):
            "Apple Music automation failed (\(code)): \(message)"
        case .malformedResponse:
            "Apple Music returned an unexpected response."
        }
    }
}

actor AppleMusicClient {
    static let musicBundleIdentifier = "com.apple.Music"

    private let stateScript: NSAppleScript?
    private let titleScript: NSAppleScript?
    private let artistScript: NSAppleScript?
    private let albumScript: NSAppleScript?
    private let persistentIDScript: NSAppleScript?
    private let databaseIDScript: NSAppleScript?
    private let artworkScript: NSAppleScript?
    private let logger = Logger(subsystem: "com.example.MusicScreen", category: "AppleMusicClient")

    init() {
        stateScript = NSAppleScript(source: "tell application \"Music\" to return player state as text")
        titleScript = NSAppleScript(source: """
        tell application "Music"
            return name of current track
        end tell
        """)
        artistScript = NSAppleScript(source: "tell application \"Music\" to return artist of current track")
        albumScript = NSAppleScript(source: "tell application \"Music\" to return album of current track")
        persistentIDScript = NSAppleScript(source: "tell application \"Music\" to return persistent ID of current track")
        databaseIDScript = NSAppleScript(source: "tell application \"Music\" to return database ID of current track")
        artworkScript = NSAppleScript(source: Self.artworkScriptSource)
    }

    nonisolated func isRunning() -> Bool {
        !NSRunningApplication.runningApplications(
            withBundleIdentifier: Self.musicBundleIdentifier
        ).isEmpty
    }

    func fetchSnapshot() throws -> AppleMusicSnapshot? {
        guard isRunning() else { return nil }
        guard let stateScript,
              let titleScript,
              let artistScript,
              let albumScript,
              let persistentIDScript,
              let databaseIDScript
        else {
            throw AppleMusicClientError.scriptCreationFailed
        }

        let rawState = try execute(stateScript, label: "playerState").stringValue?.trimmed ?? ""
        guard let playbackState = NowPlayingTrack.PlaybackState(rawValue: rawState)
        else {
            throw AppleMusicClientError.malformedResponse
        }

        if playbackState == .stopped {
            return AppleMusicSnapshot(
                playbackState: .stopped,
                title: "",
                artist: "",
                album: nil,
                persistentID: nil,
                databaseID: nil
            )
        }

        let rawTitle = try execute(titleScript, label: "title").stringValue?.trimmed
        let rawArtist = try execute(artistScript, label: "artist").stringValue?.trimmed
        let rawAlbum = try execute(albumScript, label: "album").stringValue?.trimmed
        // Identifier access can be denied independently from playback metadata.
        // It must never suppress a valid title/artist/album result.
        let rawPersistentID = try? execute(persistentIDScript, label: "persistentID").stringValue?.trimmed
        let databaseValue = (try? execute(databaseIDScript, label: "databaseID").int32Value) ?? 0

#if DEBUG
        logger.debug(
            "Raw metadata before fallback — title=\(rawTitle ?? "<nil>", privacy: .public), artist=\(rawArtist ?? "<nil>", privacy: .public), album=\(rawAlbum ?? "<nil>", privacy: .public), persistentID=\(rawPersistentID ?? "<nil>", privacy: .private(mask: .hash)), databaseID=\(databaseValue, privacy: .public)"
        )
#endif

        guard let title = rawTitle?.nilIfEmpty,
              let artist = rawArtist?.nilIfEmpty
        else {
            throw AppleMusicClientError.malformedResponse
        }

        return AppleMusicSnapshot(
            playbackState: playbackState,
            title: title,
            artist: artist,
            album: rawAlbum?.nilIfEmpty,
            persistentID: rawPersistentID?.nilIfEmpty,
            databaseID: databaseValue == 0 ? nil : databaseValue
        )
    }

    func fetchArtwork(expectedTrackID: String) throws -> Data? {
        guard isRunning() else { return nil }
        guard let artworkScript else { throw AppleMusicClientError.scriptCreationFailed }

        let response = try execute(artworkScript, label: "artwork")
        guard response.numberOfItems >= 3 else {
            throw AppleMusicClientError.malformedResponse
        }

        let persistentID = response.at(1)?.stringValue?.trimmed.nilIfEmpty
        let databaseValue = response.at(2)?.int32Value ?? 0
        let currentID: String
        if let persistentID {
            currentID = "apple-persistent:\(persistentID)"
        } else if databaseValue != 0 {
            currentID = "apple-database:\(databaseValue)"
        } else {
            return nil
        }

        guard currentID == expectedTrackID else {
#if DEBUG
            logger.debug("Discarding stale artwork response because the track ID changed")
#endif
            return nil
        }

        let artworkDescriptor = response.at(3)
        let artworkData = artworkDescriptor?.data
#if DEBUG
        let artworkType = artworkDescriptor.map { String(format: "0x%08X", $0.descriptorType) } ?? "<nil>"
        logger.debug(
            "Artwork descriptor — descriptorType=\(artworkType, privacy: .public), byteCount=\(artworkData?.count ?? 0, privacy: .public), trackIDMatches=true"
        )
#endif
        return artworkData
    }

    private func execute(_ script: NSAppleScript, label: String) throws -> NSAppleEventDescriptor {
        var errorInfo: NSDictionary?
        let response = script.executeAndReturnError(&errorInfo)
        let errorNumber = errorInfo?[NSAppleScript.errorNumber] as? Int
        let errorMessage = errorInfo?[NSAppleScript.errorMessage] as? String

#if DEBUG
        let descriptorType = String(format: "0x%08X", response.descriptorType)
        let errorDescription = String(describing: errorInfo)
        logger.debug(
            "AppleScript[\(label, privacy: .public)] success=\(errorInfo == nil, privacy: .public) descriptorType=\(descriptorType, privacy: .public) stringValue=\(response.stringValue ?? "<nil>", privacy: .public) errorDictionary=\(errorDescription, privacy: .public) errorNumber=\(errorNumber.map(String.init) ?? "<nil>", privacy: .public) errorMessage=\(errorMessage ?? "<nil>", privacy: .public)"
        )
#endif

        if let errorInfo {
            let code = errorInfo[NSAppleScript.errorNumber] as? Int ?? -1
            let message = errorInfo[NSAppleScript.errorMessage] as? String ?? "Unknown AppleScript error"
            throw AppleMusicClientError.scriptFailed(code: code, message: message)
        }
        return response
    }

    private static let artworkScriptSource = """
    with timeout of 3 seconds
        tell application id "com.apple.Music"
            set activeTrack to current track
            set trackPersistentID to ""
            set trackDatabaseID to 0
            set artworkBytes to missing value
            try
                set trackPersistentID to persistent ID of activeTrack
            end try
            try
                set trackDatabaseID to database ID of activeTrack
            end try
            try
                if (count of artworks of activeTrack) > 0 then
                    set artworkBytes to raw data of artwork 1 of activeTrack
                end if
            end try
            return {trackPersistentID, trackDatabaseID, artworkBytes}
        end tell
    end timeout
    """
}

private extension NSAppleEventDescriptor {
    func at(_ index: Int) -> NSAppleEventDescriptor? {
        atIndex(index)
    }
}

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
