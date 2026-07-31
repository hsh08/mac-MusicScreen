import SwiftUI

struct ScreenSaverHostView: View {
    @ObservedObject var monitor: SharedCacheMonitor
    @ObservedObject var settings: SharedSettings

    var body: some View {
        NowPlayingScreen(track: monitor.track, settings: settings)
    }
}
