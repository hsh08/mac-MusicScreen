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
    private static let showsTimeKey = "showsTime"
    private static let showsDateKey = "showsDate"
    private static let artworkSizeKey = "artworkSize"
    private static let blurRadiusKey = "blurRadius"
    private static let backgroundDarknessKey = "backgroundDarkness"
    private static let showsTitleKey = "showsTitle"
    private static let showsArtistKey = "showsArtist"
    private let defaults: UserDefaults

    @Published var musicSource: ProviderSelection {
        didSet { defaults.set(musicSource.rawValue, forKey: Self.musicSourceKey) }
    }
    @Published var showsTime: Bool {
        didSet { defaults.set(showsTime, forKey: Self.showsTimeKey) }
    }
    @Published var showsDate: Bool {
        didSet { defaults.set(showsDate, forKey: Self.showsDateKey) }
    }
    @Published var artworkSize: ArtworkSize {
        didSet { defaults.set(artworkSize.rawValue, forKey: Self.artworkSizeKey) }
    }
    @Published var blurRadius: Double {
        didSet { defaults.set(blurRadius, forKey: Self.blurRadiusKey) }
    }
    @Published var backgroundDarkness: Double {
        didSet { defaults.set(backgroundDarkness, forKey: Self.backgroundDarknessKey) }
    }
    @Published var showsTitle: Bool {
        didSet { defaults.set(showsTitle, forKey: Self.showsTitleKey) }
    }
    @Published var showsArtist: Bool {
        didSet { defaults.set(showsArtist, forKey: Self.showsArtistKey) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        musicSource = defaults.string(forKey: Self.musicSourceKey)
            .flatMap(ProviderSelection.init(rawValue:))
            ?? .automatic
        showsTime = defaults.object(forKey: Self.showsTimeKey) as? Bool ?? true
        showsDate = defaults.object(forKey: Self.showsDateKey) as? Bool ?? true
        artworkSize = defaults.string(forKey: Self.artworkSizeKey)
            .flatMap(ArtworkSize.init(rawValue:))
            ?? .medium
        blurRadius = defaults.object(forKey: Self.blurRadiusKey) as? Double ?? 56
        backgroundDarkness = defaults.object(forKey: Self.backgroundDarknessKey) as? Double ?? 0.42
        showsTitle = defaults.object(forKey: Self.showsTitleKey) as? Bool ?? true
        showsArtist = defaults.object(forKey: Self.showsArtistKey) as? Bool ?? true
    }
}
