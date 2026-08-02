import AppKit
import SwiftUI

struct MenuBarCompanionView: View {
    @ObservedObject var model: CompanionStatusModel
    @ObservedObject private var settings: SharedSettings
    @ObservedObject private var launchAtLogin: LaunchAtLoginModel
    @Environment(\.openSettings) private var openSettings

    init(model: CompanionStatusModel) {
        self.model = model
        settings = model.settings
        launchAtLogin = model.launchAtLogin
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            currentTrack

            Divider()

            sourceSection

            if model.showsSetupGuide {
                setupGuide
            }

            if let message = model.screenSaverSettingsMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            actions

#if DEBUG
            Divider()
            diagnostics
#endif
        }
        .padding(16)
        .frame(width: 340)
        .onAppear { model.noteMenuBarCreated() }
    }

    private var currentTrack: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Current Track")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Button { model.openCurrentTrack() } label: {
                    ArtworkView(
                        artworkData: model.track?.artworkData,
                        cornerRadius: 9,
                        showsShadow: false
                    )
                    .id(model.track?.id ?? "no-track")
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    .frame(width: 72, height: 72)
                    .contentShape(RoundedRectangle(cornerRadius: 9))
                }
                .buttonStyle(.plain)
                .disabled(model.track == nil)
                .help(model.track == nil ? "No music playing" : "Open in \(model.track?.source.displayName ?? "music app")")

                VStack(alignment: .leading, spacing: 4) {
                    Text(model.currentTrackTitle)
                        .font(.headline)
                        .lineLimit(2)
                    Text(model.currentArtistLabel)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if let track = model.track {
                        Text(track.source.displayName)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.tertiary)
                    }
                }
                Spacer(minLength: 0)
            }

            if let track = model.track, PlaybackProgress.hasDuration(track) {
                TimelineView(.periodic(from: .now, by: 0.5)) { context in
                    let progress = PlaybackProgress.values(for: track, at: context.date)
                    VStack(spacing: 4) {
                        ProgressView(value: progress.position, total: progress.duration)
                            .progressViewStyle(.linear)
                            .controlSize(.mini)
                        Text("\(PlaybackProgress.format(progress.position)) / \(PlaybackProgress.format(progress.duration))")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }
            }
        }
        .animation(.easeInOut(duration: 0.3), value: model.track?.id)
    }

    private var sourceSection: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Source")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            sourceButton("Apple Music", selection: .appleMusic)
            sourceButton("Spotify", selection: .spotify)

            if model.connectionState == .permissionRequired {
                Button("Open Automation Privacy Settings") {
                    model.openAutomationPrivacySettings()
                }
                .font(.caption)
            }
        }
    }

    private func sourceButton(_ title: String, selection: ProviderSelection) -> some View {
        Button {
            settings.musicSource = selection
        } label: {
            HStack(spacing: 8) {
                Image(systemName: settings.musicSource == selection ? "circle.inset.filled" : "circle")
                    .foregroundStyle(settings.musicSource == selection ? Color.accentColor : Color.secondary)
                Text(title)
                Spacer()
            }
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var setupGuide: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Setup")
                .font(.headline)
            Text("MusicScreen lives in the menu bar. Keep it running so Apple Music or Spotify can refresh the screen saver cache, then select MusicScreen in Screen Saver settings.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Button("Screen Saver Settings") { model.openScreenSaverSettings() }
                Spacer()
                Button("Got It") { model.dismissSetupGuide() }
            }
            .controlSize(.small)
        }
        .padding(10)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 9))
    }

    private var actions: some View {
        VStack(spacing: 4) {
            Toggle(
                "Launch at Login",
                isOn: Binding(
                    get: { launchAtLogin.isEnabled },
                    set: { launchAtLogin.setEnabled($0) }
                )
            )
            .toggleStyle(.switch)
            .controlSize(.small)
            .padding(.vertical, 4)

            Button {
                model.openScreenSaverSettings()
            } label: {
                actionLabel("Open Screen Saver Settings", symbol: "display")
            }
            Button {
                NSApplication.shared.activate(ignoringOtherApps: true)
                openSettings()
            } label: {
                actionLabel("Open Settings", symbol: "gearshape")
            }
            Button {
                model.quit()
            } label: {
                actionLabel("Quit MusicScreen", symbol: "power")
            }
        }
        .buttonStyle(.plain)
    }

#if DEBUG
    private var diagnostics: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Developer Diagnostics")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            menuStatusRow(model.providerLabel, model.connectionState.label, good: model.connectionState == .connected)
            menuStatusRow("Shared cache", model.cacheStatusLabel, good: model.cacheWriteSucceeded == true)
            menuStatusRow(
                "Screen saver data",
                model.isScreenSaverDataReady ? "Ready" : "Not Ready",
                good: model.isScreenSaverDataReady
            )
            menuStatusRow(
                "Last updated",
                model.lastTrackRefreshAt?.formatted(date: .omitted, time: .standard) ?? "Never",
                good: model.lastTrackRefreshAt != nil
            )
        }
    }
#endif

    private func actionLabel(_ title: String, symbol: String) -> some View {
        Label(title, systemImage: symbol)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
    }

    private func menuStatusRow(_ title: String, _ value: String, good: Bool) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(good ? Color.green : Color.orange)
                .frame(width: 7, height: 7)
            Text(title)
                .foregroundStyle(.secondary)
            Spacer(minLength: 10)
            Text(value)
                .lineLimit(1)
        }
        .font(.caption)
    }
}

enum PlaybackProgress {
    static func hasDuration(_ track: NowPlayingTrack) -> Bool {
        guard let duration = track.duration else { return false }
        return duration.isFinite && duration > 0
    }

    static func values(
        for track: NowPlayingTrack,
        at date: Date
    ) -> (position: TimeInterval, duration: TimeInterval) {
        let duration = max(0, track.duration ?? 0)
        let basePosition = max(0, track.playbackPosition ?? 0)
        let elapsed = track.playbackState == .playing
            ? max(0, date.timeIntervalSince(track.updatedAt))
            : 0
        return (min(basePosition + elapsed, duration), duration)
    }

    static func format(_ interval: TimeInterval) -> String {
        let totalSeconds = max(0, Int(interval.rounded(.down)))
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }
}

struct CompanionStatusView: View {
    @ObservedObject var status: CompanionStatusModel

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            statusRow(status.providerLabel, value: status.connectionState.label, isGood: status.connectionState == .connected)
            statusRow(
                "Last track refresh",
                value: status.lastTrackRefreshAt?.formatted(date: .omitted, time: .standard) ?? "Never",
                isGood: status.lastTrackRefreshAt != nil
            )
            statusRow("Shared cache", value: status.cacheStatusLabel, isGood: status.cacheWriteSucceeded == true)
            statusRow(
                "Screen saver data",
                value: status.isScreenSaverDataReady ? "Ready" : "Not ready",
                isGood: status.isScreenSaverDataReady
            )
        }
        .font(.system(size: 12, weight: .medium))
        .padding(12)
        .background(.black.opacity(0.58), in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(.white.opacity(0.12), lineWidth: 1)
        }
        .foregroundStyle(.white)
        .accessibilityElement(children: .combine)
    }

    private func statusRow(_ label: String, value: String, isGood: Bool) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(isGood ? Color.green : Color.orange)
                .frame(width: 7, height: 7)
            Text(label).foregroundStyle(.white.opacity(0.68))
            Spacer(minLength: 14)
            Text(value).foregroundStyle(.white).lineLimit(1)
        }
    }
}
