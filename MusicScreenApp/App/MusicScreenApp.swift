import AppKit
import SwiftUI

@main
struct MusicScreenApp: App {
    @StateObject private var model = CompanionStatusModel(
        startsImmediately: ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil
    )

    var body: some Scene {
        MenuBarExtra {
            MenuBarCompanionView(model: model)
        } label: {
            MenuBarStatusIcon(track: model.track)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(model: model)
        }
    }
}

private struct MenuBarStatusIcon: View {
    let track: NowPlayingTrack?

    var body: some View {
        Group {
            if track?.playbackState == .playing, track?.source == .spotify,
               let icon = Self.spotifyIcon {
                Image(nsImage: icon)
                    .frame(width: 16, height: 16)
            } else if track?.playbackState == .playing, track?.source == .appleMusic {
                Image(nsImage: Self.appleMusicIcon)
                    .frame(width: 16, height: 16)
            } else {
                Image(systemName: "music.note")
                    .frame(width: 16, height: 16)
            }
        }
        .frame(width: 16, height: 16)
        .clipped()
        .accessibilityLabel(track?.source.displayName ?? "MusicScreen")
    }

    private static let spotifyIcon: NSImage? = {
        guard let url = Bundle.main.url(forResource: "SpotifyMenuBarIcon", withExtension: "svg"),
              let image = NSImage(contentsOf: url)
        else { return nil }
        image.size = NSSize(width: 16, height: 16)
        image.isTemplate = true
        return image
    }()

    private static let appleMusicIcon: NSImage = {
        let image = NSWorkspace.shared.icon(forFile: "/System/Applications/Music.app")
        image.size = NSSize(width: 16, height: 16)
        return image
    }()
}
