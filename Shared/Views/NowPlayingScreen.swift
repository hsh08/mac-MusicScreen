import SwiftUI

struct NowPlayingScreen: View {
    let track: NowPlayingTrack?
    @ObservedObject var settings: SharedSettings

    var body: some View {
        GeometryReader { proxy in
            let compact = proxy.size.height < 560
            let coverSize = min(
                proxy.size.width * (compact ? 0.44 : 0.56),
                min(520, proxy.size.height * settings.artworkSize.scale)
            )

            ZStack {
                BlurredArtworkBackground(
                    artworkData: track?.artworkData,
                    blurRadius: settings.blurRadius,
                    darkness: settings.backgroundDarkness
                )
                .frame(width: proxy.size.width, height: proxy.size.height)
                .id(track?.id ?? "empty-background")

                ZStack {
                    VStack(spacing: compact ? 12 : 20) {
                        ArtworkView(artworkData: track?.artworkData, cornerRadius: compact ? 14 : 22)
                            .frame(width: coverSize, height: coverSize)
                            .id(track?.id ?? "empty-artwork")
                            .transition(.opacity)

                        VStack(spacing: compact ? 3 : 6) {
                            if let track {
                                if settings.showsTitle {
                                    Text(track.title)
                                        .font(.system(size: compact ? 20 : 27, weight: .semibold))
                                        .lineLimit(2)
                                }

                                if settings.showsArtist {
                                    Text(track.artist)
                                        .font(.system(size: compact ? 15 : 19, weight: .regular))
                                        .foregroundStyle(.white.opacity(0.72))
                                        .lineLimit(1)
                                }

                                if let album = track.album {
                                    Text(album)
                                        .font(.system(size: compact ? 13 : 16, weight: .regular))
                                        .foregroundStyle(.white.opacity(0.54))
                                        .lineLimit(1)
                                }
                            } else {
                                Text("No music playing")
                                    .font(.system(size: compact ? 17 : 21, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.72))
                            }
                        }
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: min(640, proxy.size.width * 0.78))
                    }
                    .offset(y: compact ? 26 : 44)

                    ClockView(
                        showsTime: settings.showsTime,
                        showsDate: settings.showsDate,
                        compact: compact
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(.top, compact ? 22 : 40)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 28)
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.28), radius: 8, y: 3)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .animation(.easeInOut(duration: 0.8), value: track?.id)
        }
        .ignoresSafeArea()
    }
}
