import Foundation
import os

@MainActor
final class SharedCacheMonitor: ObservableObject {
    @Published private(set) var track: NowPlayingTrack?
    @Published private(set) var cacheState: SharedCacheState = .missing

    private let reader = NowPlayingCacheReader()
    private let logger = Logger(subsystem: "com.example.MusicScreen", category: "SaverCacheMonitor")
    private var monitoringTask: Task<Void, Never>?

    func start() {
        guard monitoringTask == nil else { return }
        logger.info("Shared cache monitoring started")
        monitoringTask = Task { [weak self, reader] in
            while !Task.isCancelled {
                let result = await reader.poll()
                guard !Task.isCancelled else { break }
                if result.track != self?.track || result.state != self?.cacheState {
                    self?.track = result.track
                    self?.cacheState = result.state
                    self?.logger.info(
                        "Shared cache state=\(result.state.rawValue, privacy: .public), revision=\(result.revision.map(String.init) ?? "<nil>", privacy: .public)"
                    )
                }
                do {
                    try await Task.sleep(for: NowPlayingCachePolicy.pollingInterval)
                } catch {
                    break
                }
            }
        }
    }

    func stop() {
        monitoringTask?.cancel()
        monitoringTask = nil
        logger.info("Shared cache monitoring stopped")
    }

    deinit {
        monitoringTask?.cancel()
    }
}
