import Foundation

enum ProviderSelection: String, CaseIterable, Identifiable, Sendable {
    case automatic = "Auto"
    case appleMusic = "Apple Music"
    case spotify = "Spotify"
    case demo = "Demo"

    var id: String { rawValue }
}

enum ArtworkSize: String, CaseIterable, Identifiable {
    case small = "Small"
    case medium = "Medium"
    case large = "Large"

    var id: String { rawValue }
    var scale: CGFloat {
        switch self {
        case .small: 0.36
        case .medium: 0.42
        case .large: 0.48
        }
    }
}

@MainActor
final class SharedSettings: ObservableObject {
    static let shared = SharedSettings()

    private static let musicSourceKey = "musicSource"
    private let defaults: UserDefaults

    @Published var musicSource: ProviderSelection {
        didSet { defaults.set(musicSource.rawValue, forKey: Self.musicSourceKey) }
    }
    @Published var showsTime = true
    @Published var showsDate = true
    @Published var artworkSize: ArtworkSize = .medium
    @Published var blurRadius = 56.0
    @Published var backgroundDarkness = 0.42
    @Published var showsTitle = true
    @Published var showsArtist = true

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        musicSource = defaults.string(forKey: Self.musicSourceKey)
            .flatMap(ProviderSelection.init(rawValue:))
            ?? .automatic
    }
}
