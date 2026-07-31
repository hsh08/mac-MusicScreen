import SwiftUI

@main
struct MusicScreenApp: App {
    var body: some Scene {
        WindowGroup {
            PreviewContainerView()
                .frame(minWidth: 720, minHeight: 620)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1100, height: 820)

        Settings {
            SettingsView()
        }
    }
}
