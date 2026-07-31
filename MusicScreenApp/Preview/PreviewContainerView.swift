import SwiftUI
import os

struct PreviewContainerView: View {
    private static let logger = Logger(subsystem: "com.example.MusicScreen", category: "PreviewContainer")

    @StateObject private var monitor: NowPlayingMonitor
    @StateObject private var companionStatus = CompanionStatusModel()
    @ObservedObject private var settings = SharedSettings.shared
    private let coordinator: ProviderCoordinator

    init() {
        let coordinator = ProviderCoordinator(selection: SharedSettings.shared.musicSource)
        self.coordinator = coordinator
#if DEBUG
        Self.logger.debug(
            "Selected source=\(SharedSettings.shared.musicSource.rawValue, privacy: .public), providerType=\(String(reflecting: type(of: coordinator)), privacy: .public), providerName=\(coordinator.providerName, privacy: .public)"
        )
#endif
        _monitor = StateObject(wrappedValue: NowPlayingMonitor(provider: coordinator))
    }

    var body: some View {
        NowPlayingScreen(track: monitor.track, settings: settings)
            .task {
                await coordinator.setSelection(settings.musicSource)
                monitor.start()
            }
            .onDisappear { monitor.stop() }
            .onChange(of: settings.musicSource) { _, source in
                Task { await coordinator.setSelection(source) }
            }
            .onChange(of: monitor.lastSuccessfulRefreshAt) { _, refreshAt in
                guard let refreshAt else { return }
                companionStatus.updateConnection(
                    isAvailable: monitor.isProviderAvailable,
                    lastRefreshAt: refreshAt,
                    selectedSource: settings.musicSource,
                    activeSource: monitor.track?.source
                )
                if monitor.isProviderAvailable {
                    Task {
                    await companionStatus.persist(monitor.track, refreshAt: refreshAt)
                    }
                }
            }
            .onChange(of: monitor.isProviderAvailable, initial: true) { _, isAvailable in
                companionStatus.updateConnection(
                    isAvailable: isAvailable,
                    lastRefreshAt: monitor.lastSuccessfulRefreshAt,
                    selectedSource: settings.musicSource,
                    activeSource: monitor.track?.source
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
