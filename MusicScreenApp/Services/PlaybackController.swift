import AppKit
import Foundation
import os

enum PlaybackCommand: Equatable, Hashable, Sendable {
    case previousTrack
    case togglePlayPause
    case nextTrack
}

protocol PlaybackController: Sendable {
    func previousTrack() async throws
    func togglePlayPause() async throws
    func nextTrack() async throws
}

extension PlaybackController {
    func perform(_ command: PlaybackCommand) async throws {
        switch command {
        case .previousTrack:
            try await previousTrack()
        case .togglePlayPause:
            try await togglePlayPause()
        case .nextTrack:
            try await nextTrack()
        }
    }
}

enum PlaybackControlError: Error, Equatable, Sendable {
    case appNotRunning(MusicSource)
    case automationPermissionRequired(MusicSource)
    case commandFailed(source: MusicSource, code: Int, message: String)

    var userMessage: String {
        switch self {
        case .appNotRunning(.appleMusic):
            "Open Apple Music"
        case .appNotRunning(.spotify):
            "Open Spotify"
        case .appNotRunning(.demo):
            "Playback Command Failed"
        case .automationPermissionRequired:
            "Automation Permission Required"
        case .commandFailed:
            "Playback Command Failed"
        }
    }

    static func mapAppleScriptError(
        source: MusicSource,
        code: Int,
        message: String
    ) -> PlaybackControlError {
        if code == -1743 {
            return .automationPermissionRequired(source)
        }
        return .commandFailed(source: source, code: code, message: message)
    }
}

actor AppleMusicPlaybackController: PlaybackController {
    private let executor = AppleScriptPlaybackExecutor(
        source: .appleMusic,
        bundleIdentifier: AppleMusicClient.musicBundleIdentifier,
        applicationName: "Music"
    )

    func previousTrack() throws {
        try executor.execute(.previousTrack)
    }

    func togglePlayPause() throws {
        try executor.execute(.togglePlayPause)
    }

    func nextTrack() throws {
        try executor.execute(.nextTrack)
    }
}

actor SpotifyPlaybackController: PlaybackController {
    private let executor = AppleScriptPlaybackExecutor(
        source: .spotify,
        bundleIdentifier: SpotifyAutomationClient.bundleIdentifier,
        applicationName: "Spotify"
    )

    func previousTrack() throws {
        try executor.execute(.previousTrack)
    }

    func togglePlayPause() throws {
        try executor.execute(.togglePlayPause)
    }

    func nextTrack() throws {
        try executor.execute(.nextTrack)
    }
}

private final class AppleScriptPlaybackExecutor: @unchecked Sendable {
    private let source: MusicSource
    private let bundleIdentifier: String
    private let scripts: [PlaybackCommand: NSAppleScript]
    private let logger: Logger

    init(source: MusicSource, bundleIdentifier: String, applicationName: String) {
        self.source = source
        self.bundleIdentifier = bundleIdentifier
        logger = Logger(subsystem: "com.example.MusicScreen", category: "PlaybackControl")
        scripts = [
            .previousTrack: NSAppleScript(source: "tell application \"\(applicationName)\" to previous track"),
            .togglePlayPause: NSAppleScript(source: "tell application \"\(applicationName)\" to playpause"),
            .nextTrack: NSAppleScript(source: "tell application \"\(applicationName)\" to next track")
        ].compactMapValues { $0 }
    }

    func execute(_ command: PlaybackCommand) throws {
        guard !NSRunningApplication.runningApplications(
            withBundleIdentifier: bundleIdentifier
        ).isEmpty else {
            throw PlaybackControlError.appNotRunning(source)
        }

        guard let script = scripts[command] else {
            throw PlaybackControlError.commandFailed(
                source: source,
                code: -1,
                message: "Could not create the playback AppleScript."
            )
        }

        var errorInfo: NSDictionary?
        _ = script.executeAndReturnError(&errorInfo)
        guard let errorInfo else { return }

        let code = errorInfo[NSAppleScript.errorNumber] as? Int ?? -1
        let message = errorInfo[NSAppleScript.errorMessage] as? String ?? "Unknown AppleScript error"
        let label = String(describing: command)
        logger.error(
            "\(self.source.displayName, privacy: .public) command[\(label, privacy: .public)] failed: \(code, privacy: .public) \(message, privacy: .public)"
        )
        throw PlaybackControlError.mapAppleScriptError(
            source: source,
            code: code,
            message: message
        )
    }
}

struct PlaybackControllerSet: Sendable {
    let appleMusic: any PlaybackController
    let spotify: any PlaybackController

    init(
        appleMusic: any PlaybackController = AppleMusicPlaybackController(),
        spotify: any PlaybackController = SpotifyPlaybackController()
    ) {
        self.appleMusic = appleMusic
        self.spotify = spotify
    }

    func controller(for source: MusicSource) -> (any PlaybackController)? {
        switch source {
        case .appleMusic: appleMusic
        case .spotify: spotify
        case .demo: nil
        }
    }
}

enum PlaybackRouting {
    static func activeSource(
        selection: ProviderSelection,
        track: NowPlayingTrack?
    ) -> MusicSource? {
        guard let track, track.playbackState != .stopped else { return nil }
        switch selection {
        case .automatic:
            guard track.playbackState == .playing else { return nil }
            return track.source == .demo ? nil : track.source
        case .appleMusic:
            return track.source == .appleMusic ? .appleMusic : nil
        case .spotify:
            return track.source == .spotify ? .spotify : nil
        case .demo:
            return nil
        }
    }
}

struct PlaybackCommandContext: Equatable, Sendable {
    let selection: ProviderSelection
    let source: MusicSource
    let trackID: String

    static func make(
        selection: ProviderSelection,
        track: NowPlayingTrack?
    ) -> PlaybackCommandContext? {
        guard let track,
              let source = PlaybackRouting.activeSource(selection: selection, track: track)
        else { return nil }
        return PlaybackCommandContext(selection: selection, source: source, trackID: track.id)
    }

    func matches(selection: ProviderSelection, track: NowPlayingTrack?) -> Bool {
        Self.make(selection: selection, track: track) == self
    }
}

struct PlaybackCommandGate: Sendable {
    private(set) var commandInFlight: PlaybackCommand?

    mutating func begin(_ command: PlaybackCommand) -> Bool {
        guard commandInFlight == nil else { return false }
        commandInFlight = command
        return true
    }

    mutating func finish() {
        commandInFlight = nil
    }
}

enum PlaybackControlPresentation {
    static func playPauseSymbol(for state: NowPlayingTrack.PlaybackState?) -> String {
        state == .playing ? "pause.fill" : "play.fill"
    }
}
