import Foundation

enum ProviderSelection: String, CaseIterable, Identifiable {
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

    @Published var musicSource: ProviderSelection = .appleMusic
    @Published var showsTime = true
    @Published var showsDate = true
    @Published var artworkSize: ArtworkSize = .medium
    @Published var blurRadius = 56.0
    @Published var backgroundDarkness = 0.42
    @Published var showsTitle = true
    @Published var showsArtist = true
}
