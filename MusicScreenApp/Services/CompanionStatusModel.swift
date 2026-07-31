import Foundation
import os

@MainActor
final class CompanionStatusModel: ObservableObject {
    @Published private(set) var isProviderConnected = false
    @Published private(set) var providerLabel = "Auto"
    @Published private(set) var lastTrackRefreshAt: Date?
    @Published private(set) var cacheWriteSucceeded: Bool?
    @Published private(set) var isScreenSaverDataReady = false
    @Published private(set) var cacheErrorMessage: String?

    private let writer = NowPlayingCacheWriter()
    private let logger = Logger(subsystem: "com.example.MusicScreen", category: "CompanionStatus")

    func updateConnection(
        isAvailable: Bool,
        lastRefreshAt: Date?,
        selectedSource: ProviderSelection,
        activeSource: MusicSource?
    ) {
        isProviderConnected = isAvailable
        providerLabel = activeSource?.displayName ?? selectedSource.rawValue
        lastTrackRefreshAt = lastRefreshAt
    }

    func persist(_ track: NowPlayingTrack?, refreshAt: Date) async {
        guard let track else { return }
        do {
            let receipt = try await writer.write(track, at: refreshAt)
            cacheWriteSucceeded = true
            isScreenSaverDataReady = receipt.isReady
            cacheErrorMessage = nil
        } catch {
            cacheWriteSucceeded = false
            isScreenSaverDataReady = false
            cacheErrorMessage = error.localizedDescription
            logger.error("Shared cache write failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}

private extension MusicSource {
    var displayName: String {
        switch self {
        case .appleMusic: "Apple Music"
        case .spotify: "Spotify"
        case .demo: "Demo"
        }
    }
}
