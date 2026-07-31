import SwiftUI
import os

struct PreviewContainerView: View {
    private static let logger = Logger(subsystem: "com.example.MusicScreen", category: "PreviewContainer")

    @StateObject private var monitor: NowPlayingMonitor
    @StateObject private var companionStatus = CompanionStatusModel()
    @ObservedObject private var settings = SharedSettings.shared

    init() {
        let provider: any MusicProvider = AppleMusicProvider()
#if DEBUG
        Self.logger.debug(
            "Selected source=\(SharedSettings.shared.musicSource.rawValue, privacy: .public), providerType=\(String(reflecting: type(of: provider)), privacy: .public), providerName=\(provider.providerName, privacy: .public)"
        )
#endif
        _monitor = StateObject(wrappedValue: NowPlayingMonitor(provider: provider))
    }

    var body: some View {
        NowPlayingScreen(track: monitor.track, settings: settings)
            .task { monitor.start() }
            .onDisappear { monitor.stop() }
            .onChange(of: monitor.lastSuccessfulRefreshAt) { _, refreshAt in
                guard let refreshAt else { return }
                companionStatus.updateConnection(
                    isAvailable: monitor.isProviderAvailable,
                    lastRefreshAt: refreshAt
                )
                Task {
                    await companionStatus.persist(monitor.track, refreshAt: refreshAt)
                }
            }
            .onChange(of: monitor.isProviderAvailable, initial: true) { _, isAvailable in
                companionStatus.updateConnection(
                    isAvailable: isAvailable,
                    lastRefreshAt: monitor.lastSuccessfulRefreshAt
                )
            }
            .onChange(of: monitor.track, initial: true) { _, track in
#if DEBUG
                Self.logger.debug(
                    "NowPlayingScreen input — title=\(track?.title ?? "<nil>", privacy: .public), artist=\(track?.artist ?? "<nil>", privacy: .public), album=\(track?.album ?? "<nil>", privacy: .public)"
                )
#endif
            }
            .overlay(alignment: .bottomTrailing) {
                CompanionStatusView(status: companionStatus)
                    .frame(width: 285)
                    .padding(18)
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    SettingsLink {
                        Label("Settings", systemImage: "gearshape")
                    }
                    .labelStyle(.iconOnly)
                    .help("Open preview settings")
                }
            }
    }
}
