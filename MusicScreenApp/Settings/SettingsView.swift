import SwiftUI

struct SettingsView: View {
    @ObservedObject private var settings = SharedSettings.shared

    var body: some View {
        Form {
            Picker("Music source", selection: $settings.musicSource) {
                ForEach(ProviderSelection.allCases) { source in
                    Text(source.rawValue).tag(source)
                }
            }

            Section("Clock") {
                Toggle("Show time", isOn: $settings.showsTime)
                Toggle("Show date", isOn: $settings.showsDate)
            }

            Section("Artwork") {
                Picker("Size", selection: $settings.artworkSize) {
                    ForEach(ArtworkSize.allCases) { size in
                        Text(size.rawValue).tag(size)
                    }
                }
                Slider(value: $settings.blurRadius, in: 20...90) {
                    Text("Background blur")
                }
                Slider(value: $settings.backgroundDarkness, in: 0.2...0.75) {
                    Text("Background darkness")
                }
            }

            Section("Track information") {
                Toggle("Show title", isOn: $settings.showsTitle)
                Toggle("Show artist", isOn: $settings.showsArtist)
            }
        }
        .formStyle(.grouped)
        .frame(width: 440, height: 470)
        .padding()
    }
}
