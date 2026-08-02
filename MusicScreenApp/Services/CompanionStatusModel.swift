import AppKit
import Combine
import Foundation
import os
import ServiceManagement

enum CompanionConnectionState: Equatable, Sendable {
    case connected
    case notRunning
    case permissionRequired
    case noMusicPlaying
    case error

    var label: String {
        switch self {
        case .connected: "Connected"
        case .notRunning: "Not Running"
        case .permissionRequired: "Automation Permission Required"
        case .noMusicPlaying: "No Music Playing"
        case .error: "Unavailable"
        }
    }
}

enum LaunchAtLoginState: Equatable, Sendable {
    case enabled
    case disabled
    case requiresApproval
    case unavailable

    static func map(_ status: SMAppService.Status) -> Self {
        switch status {
        case .enabled: .enabled
        case .notRegistered: .disabled
        case .requiresApproval: .requiresApproval
        case .notFound: .unavailable
        @unknown default: .unavailable
        }
    }
}

@MainActor
final class LaunchAtLoginModel: ObservableObject {
    @Published private(set) var state: LaunchAtLoginState = .disabled
    @Published private(set) var errorMessage: String?

    private let service: SMAppService
    private let logger = Logger(subsystem: "com.example.MusicScreen", category: "LaunchAtLogin")

    init(service: SMAppService = .mainApp) {
        self.service = service
        refresh()
    }

    var isEnabled: Bool { state == .enabled || state == .requiresApproval }

    func refresh() {
        state = .map(service.status)
    }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try service.register()
            } else {
                try service.unregister()
            }
            errorMessage = nil
            refresh()
            logger.info("Launch at login registration result: \(String(describing: self.state), privacy: .public)")
        } catch {
            refresh()
            errorMessage = error.localizedDescription
            logger.error("Launch at login registration failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}

@MainActor
final class CompanionStatusModel: ObservableObject {
    @Published private(set) var track: NowPlayingTrack?
    @Published private(set) var isProviderConnected = false
    @Published private(set) var providerLabel = "Auto"
    @Published private(set) var connectionState: CompanionConnectionState = .noMusicPlaying
    @Published private(set) var lastTrackRefreshAt: Date?
    @Published private(set) var cacheWriteSucceeded: Bool?
    @Published private(set) var isScreenSaverDataReady = false
    @Published private(set) var cacheErrorMessage: String?
    @Published private(set) var screenSaverSettingsMessage: String?
    @Published var showsSetupGuide: Bool

    let settings: SharedSettings
    let launchAtLogin: LaunchAtLoginModel

    private let coordinator: ProviderCoordinator
    private let monitor: NowPlayingMonitor
    private let writer: NowPlayingCacheWriter
    private let defaults: UserDefaults
    private let logger = Logger(subsystem: "com.example.MusicScreen", category: "Companion")
    private var cancellables = Set<AnyCancellable>()
    private var sourceChangeTask: Task<Void, Never>?
    private var didLogMenuBarCreation = false
    private var isStarted = false

    private static let setupGuideSeenKey = "hasSeenCompanionSetupGuide"

    init(
        settings: SharedSettings = .shared,
        coordinator: ProviderCoordinator? = nil,
        writer: NowPlayingCacheWriter = NowPlayingCacheWriter(),
        launchAtLogin: LaunchAtLoginModel = LaunchAtLoginModel(),
        defaults: UserDefaults = .standard,
        startsImmediately: Bool = true
    ) {
        self.settings = settings
        self.coordinator = coordinator ?? ProviderCoordinator(selection: settings.musicSource)
        self.writer = writer
        self.launchAtLogin = launchAtLogin
        self.defaults = defaults
        monitor = NowPlayingMonitor(provider: self.coordinator)
        showsSetupGuide = !defaults.bool(forKey: Self.setupGuideSeenKey)

        bindMonitor()
        bindSettings()
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.stop() }
        }

        logger.info("App launched")
        if startsImmediately { start() }
    }

    var isMonitoring: Bool { monitor.isMonitoring }
    var monitorIdentity: ObjectIdentifier { ObjectIdentifier(monitor) }
    var monitoringGeneration: Int { monitor.generation }
    var selectedSourceLabel: String { settings.musicSource.rawValue }
    var currentTrackTitle: String { track?.title ?? "No music playing" }
    var currentArtistLabel: String { track?.artist ?? "Start playback in Apple Music or Spotify" }
    var cacheStatusLabel: String {
        Self.cacheStatusLabel(
            writeSucceeded: cacheWriteSucceeded,
            lastRefreshAt: lastTrackRefreshAt
        )
    }

    static func cacheStatusLabel(
        writeSucceeded: Bool?,
        lastRefreshAt: Date?,
        now: Date = Date()
    ) -> String {
        if writeSucceeded == false { return "Cache Write Failed" }
        guard let lastRefreshAt else { return "Waiting for Track Data" }
        if now.timeIntervalSince(lastRefreshAt) > NowPlayingCachePolicy.staleAfter {
            return "Cache Stale"
        }
        return writeSucceeded == true ? "Shared Cache Saved" : "Waiting for Track Data"
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true
        monitor.start()
    }

    func stop() {
        guard isStarted else { return }
        isStarted = false
        sourceChangeTask?.cancel()
        sourceChangeTask = nil
        monitor.stop()
    }

    func noteMenuBarCreated() {
        guard !didLogMenuBarCreation else { return }
        didLogMenuBarCreation = true
        logger.info("Menu bar created")
    }

    func dismissSetupGuide() {
        defaults.set(true, forKey: Self.setupGuideSeenKey)
        showsSetupGuide = false
    }

    func openScreenSaverSettings() {
        let deepLink = URL(string: "x-apple.systempreferences:com.apple.ScreenSaver-Settings.extension")!
        if NSWorkspace.shared.open(deepLink) {
            screenSaverSettingsMessage = nil
            return
        }

        let settingsURL = URL(fileURLWithPath: "/System/Applications/System Settings.app")
        if NSWorkspace.shared.open(settingsURL) {
            screenSaverSettingsMessage = "Open Screen Saver in System Settings."
        } else {
            screenSaverSettingsMessage = "Could not open System Settings. Open Screen Saver settings manually."
        }
    }

    func openAutomationPrivacySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") else { return }
        NSWorkspace.shared.open(url)
    }

    func openCurrentTrack() {
        guard let track else { return }
        switch track.source {
        case .spotify:
            guard let url = track.externalURL else { return }
            _ = NSWorkspace.shared.open(url)
        case .appleMusic:
            let musicAppURL = URL(fileURLWithPath: "/System/Applications/Music.app")
            NSWorkspace.shared.openApplication(
                at: musicAppURL,
                configuration: NSWorkspace.OpenConfiguration()
            ) { _, _ in }
        case .demo:
            break
        }
    }

    func quit() {
        logger.info("App quit")
        stop()
        NSApplication.shared.terminate(nil)
    }

    func settingsWindowOpened() {
        logger.info("Settings window opened")
        launchAtLogin.refresh()
    }

    func settingsWindowClosed() {
        logger.info("Settings window closed")
    }

    private func bindMonitor() {
        monitor.$track
            .sink { [weak self] track in
                self?.track = track
                self?.refreshConnectionState()
            }
            .store(in: &cancellables)

        monitor.$isProviderAvailable
            .sink { [weak self] isAvailable in
                self?.isProviderConnected = isAvailable
                self?.refreshConnectionState()
            }
            .store(in: &cancellables)

        monitor.$lastErrorMessage
            .sink { [weak self] _ in self?.refreshConnectionState() }
            .store(in: &cancellables)

        monitor.$lastSuccessfulRefreshAt
            .compactMap { $0 }
            .sink { [weak self] refreshAt in
                guard let self else { return }
                lastTrackRefreshAt = refreshAt
                providerLabel = track?.source.displayName ?? settings.musicSource.rawValue
                refreshConnectionState()
                guard isProviderConnected, let track else { return }
                Task { await self.persist(track, refreshAt: refreshAt) }
            }
            .store(in: &cancellables)
    }

    private func bindSettings() {
        settings.$musicSource
            .dropFirst()
            .sink { [weak self] source in
                guard let self else { return }
                sourceChangeTask?.cancel()
                monitor.stop()
                sourceChangeTask = Task { [weak self, coordinator] in
                    await coordinator.setSelection(source)
                    guard !Task.isCancelled else { return }
                    await MainActor.run {
                        guard let self, self.isStarted else { return }
                        self.providerLabel = source.rawValue
                        self.logger.info("Source changed to \(source.rawValue, privacy: .public)")
                        self.monitor.start()
                    }
                }
            }
            .store(in: &cancellables)
    }

    private func refreshConnectionState() {
        providerLabel = track?.source.displayName ?? settings.musicSource.rawValue
        if let error = monitor.lastErrorMessage {
            connectionState = Self.connectionState(errorMessage: error)
        } else if !isProviderConnected {
            connectionState = .notRunning
        } else if track == nil {
            connectionState = .noMusicPlaying
        } else {
            connectionState = .connected
        }
    }

    static func connectionState(errorMessage: String?) -> CompanionConnectionState {
        guard let errorMessage else { return .connected }
        let normalized = errorMessage.lowercased()
        if normalized.contains("permission") || normalized.contains("-1743") {
            return .permissionRequired
        }
        return .error
    }

    private func persist(_ track: NowPlayingTrack, refreshAt: Date) async {
        do {
            let previousRevision = await writer.currentRevision
            let receipt = try await writer.write(track, at: refreshAt)
            cacheWriteSucceeded = true
            isScreenSaverDataReady = receipt.isReady
            cacheErrorMessage = nil
            if receipt.revision == previousRevision {
#if DEBUG
                logger.debug("Cache write skipped because unchanged")
#endif
            } else {
                logger.info("Cache written at revision \(receipt.revision, privacy: .public)")
            }
        } catch {
            cacheWriteSucceeded = false
            isScreenSaverDataReady = false
            cacheErrorMessage = error.localizedDescription
            logger.error("Shared cache write failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    deinit {
        sourceChangeTask?.cancel()
    }
}

extension MusicSource {
    var displayName: String {
        switch self {
        case .appleMusic: "Apple Music"
        case .spotify: "Spotify"
        case .demo: "Demo"
        }
    }
}
