import SwiftUI

struct PreviewContainerView: View {
    @ObservedObject var model: CompanionStatusModel

    var body: some View {
        NowPlayingScreen(track: model.track, settings: model.settings)
#if DEBUG
            .overlay(alignment: .bottomTrailing) {
                CompanionStatusView(status: model)
                    .frame(width: 285)
                    .padding(18)
            }
#endif
    }
}
