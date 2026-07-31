import Foundation
import os

@MainActor
final class NowPlayingMonitor: ObservableObject {
    static let pollingInterval = Duration.seconds(1)

    @Published private(set) var track: NowPlayingTrack?
    @Published private(set) var isProviderAvailable = false
    @Published private(set) var lastSuccessfulRefreshAt: Date?
    @Published private(set) var lastErrorMessage: String?

    private let provider: any MusicProvider
    private let logger = Logger(subsystem: "com.example.MusicScreen", category: "NowPlaying")
    private var monitoringTask: Task<Void, Never>?
    private var generation = 0

    var isMonitoring: Bool { monitoringTask != nil }

    init(provider: any MusicProvider) {
        self.provider = provider
    }

    func start() {
        guard monitoringTask == nil else { return }
        generation += 1
        let currentGeneration = generation
        logger.info("Monitoring started for provider: \(self.provider.providerName, privacy: .public)")

        monitoringTask = Task { [weak self, provider] in
            while !Task.isCancelled {
                do {
                    let fetchedTrack = try await provider.fetchNowPlaying()
                    let available = await provider.isAvailable()
                    guard !Task.isCancelled, self?.generation == currentGeneration else { break }

                    if fetchedTrack != self?.track {
                        if let fetchedTrack {
                            self?.logger.info(
                                "Track/state changed: \(fetchedTrack.id, privacy: .private(mask: .hash)) / \(fetchedTrack.playbackState.rawValue, privacy: .public)"
                            )
                        }
                        self?.track = fetchedTrack
#if DEBUG
                        self?.logger.debug(
                            "Published UI track — title=\(fetchedTrack?.title ?? "<nil>", privacy: .public), artist=\(fetchedTrack?.artist ?? "<nil>", privacy: .public), album=\(fetchedTrack?.album ?? "<nil>", privacy: .public)"
                        )
#endif
                    }
                    self?.isProviderAvailable = available
                    self?.lastSuccessfulRefreshAt = Date()
                    self?.lastErrorMessage = nil
                } catch {
                    self?.lastErrorMessage = error.localizedDescription
                    self?.logger.error("Now-playing refresh failed: \(error.localizedDescription, privacy: .public)")
                }

                do {
                    try await Task.sleep(for: Self.pollingInterval)
                } catch {
                    break
                }
            }
        }
    }

    func stop() {
        guard monitoringTask != nil else { return }
        generation += 1
        monitoringTask?.cancel()
        monitoringTask = nil
        logger.info("Monitoring stopped")
    }

    deinit {
        monitoringTask?.cancel()
    }
}
