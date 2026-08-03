import AppKit
import Darwin
import SwiftUI

@main
struct MusicScreenApp: App {
    @NSApplicationDelegateAdaptor(MusicScreenAppDelegate.self) private var appDelegate
    @StateObject private var model: CompanionStatusModel

    init() {
        _model = StateObject(wrappedValue: CompanionStatusModel(
            startsImmediately: ApplicationLaunchPolicy.shouldStartMonitoring(
                isPrimaryInstance: MusicScreenInstanceLock.shared.isPrimaryInstance,
                isRunningTests: MusicScreenInstanceLock.isRunningTests
            )
        ))
    }

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

@MainActor
private final class MusicScreenAppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        guard !MusicScreenInstanceLock.isRunningTests,
              !MusicScreenInstanceLock.shared.isPrimaryInstance
        else { return }

        if let bundleIdentifier = Bundle.main.bundleIdentifier {
            NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
                .first(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier })?
                .activate()
        }
        NSApplication.shared.terminate(nil)
    }
}

enum ApplicationLaunchPolicy {
    static func shouldStartMonitoring(isPrimaryInstance: Bool, isRunningTests: Bool) -> Bool {
        isPrimaryInstance && !isRunningTests
    }
}

enum ApplicationInstanceLockName {
    private static let fallbackIdentifier = "MusicScreen"
    private static let allowedCharacters = CharacterSet(
        charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-_"
    )

    static func filename(bundleIdentifier: String?) -> String {
        let trimmedIdentifier = bundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines)
        let source = if let trimmedIdentifier, !trimmedIdentifier.isEmpty {
            trimmedIdentifier
        } else {
            fallbackIdentifier
        }
        let normalized = String(source.unicodeScalars.map { scalar in
            allowedCharacters.contains(scalar) ? Character(String(scalar)) : "-"
        })
        let hasUsableCharacter = normalized.unicodeScalars.contains {
            CharacterSet.alphanumerics.contains($0)
        }
        let safeIdentifier = hasUsableCharacter ? normalized : fallbackIdentifier
        return "\(safeIdentifier).instance.lock"
    }

    static func url(bundleIdentifier: String?, in directory: URL) -> URL {
        directory.appendingPathComponent(filename(bundleIdentifier: bundleIdentifier))
    }
}

private final class MusicScreenInstanceLock: @unchecked Sendable {
    static let shared = MusicScreenInstanceLock()
    static let isRunningTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

    let isPrimaryInstance: Bool
    private let fileDescriptor: Int32

    private init() {
        guard !Self.isRunningTests else {
            fileDescriptor = -1
            isPrimaryInstance = true
            return
        }

        let lockURL = ApplicationInstanceLockName.url(
            bundleIdentifier: Bundle.main.bundleIdentifier,
            in: FileManager.default.temporaryDirectory
        )
        let descriptor = open(lockURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        fileDescriptor = descriptor
        isPrimaryInstance = descriptor >= 0 && flock(descriptor, LOCK_EX | LOCK_NB) == 0

        if !isPrimaryInstance, descriptor >= 0 {
            close(descriptor)
        }
    }

    deinit {
        if isPrimaryInstance, fileDescriptor >= 0 {
            flock(fileDescriptor, LOCK_UN)
            close(fileDescriptor)
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
