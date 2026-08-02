import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: CompanionStatusModel
    @ObservedObject private var settings: SharedSettings

    init(model: CompanionStatusModel) {
        self.model = model
        settings = model.settings
    }

    var body: some View {
        TabView {
            settingsForm
                .tabItem { Label("Settings", systemImage: "gearshape") }

            PreviewContainerView(model: model)
                .frame(minWidth: 720, minHeight: 540)
                .tabItem { Label("Preview", systemImage: "display") }
        }
        .frame(width: 780, height: 650)
        .padding()
        .onAppear { model.settingsWindowOpened() }
        .onDisappear { model.settingsWindowClosed() }
    }

    private var settingsForm: some View {
        Form {
            Section("Music Source") {
                Picker("Music source", selection: $settings.musicSource) {
                    ForEach(ProviderSelection.allCases) { source in
                        Text(source.rawValue).tag(source)
                    }
                }
                statusRow("Connection", model.connectionState.label)
#if DEBUG
                statusRow("Shared cache", model.cacheStatusLabel)
                statusRow(
                    "Last updated",
                    model.lastTrackRefreshAt?.formatted(date: .abbreviated, time: .standard) ?? "Never"
                )
#endif
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
                Slider(value: $settings.blurRadius, in: 20...90) { Text("Background blur") }
                Slider(value: $settings.backgroundDarkness, in: 0.2...0.75) { Text("Background darkness") }
            }

            Section("Track Information") {
                Toggle("Show title", isOn: $settings.showsTitle)
                Toggle("Show artist", isOn: $settings.showsArtist)
            }

            Section("App") {
                Toggle(
                    "Launch at Login",
                    isOn: Binding(
                        get: { model.launchAtLogin.isEnabled },
                        set: { model.launchAtLogin.setEnabled($0) }
                    )
                )
                if model.launchAtLogin.state == .requiresApproval {
                    Text("Allow MusicScreen in System Settings > General > Login Items.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let error = model.launchAtLogin.errorMessage {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
                Button("Open Screen Saver Settings") { model.openScreenSaverSettings() }
                if let message = model.screenSaverSettingsMessage {
                    Text(message).font(.caption).foregroundStyle(.secondary)
                }
            }

            Section("Setup") {
                Text("MusicScreen runs from the menu bar and must stay open to refresh screen saver data. Apple Music or Spotify may request Automation permission.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func statusRow(_ title: String, _ value: String) -> some View {
        LabeledContent(title, value: value)
    }
}
