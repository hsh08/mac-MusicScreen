import AppKit
import SwiftUI

struct BlurredArtworkBackground: View {
    let artworkData: Data?
    let blurRadius: CGFloat
    let darkness: Double

    private var image: NSImage? {
        artworkData.flatMap(NSImage.init(data:))
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.10, green: 0.11, blue: 0.15), .black],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .scaleEffect(1.18)
                    .blur(radius: blurRadius, opaque: true)
                    .transition(.opacity)
            }

            Color.black.opacity(darkness)
        }
        .clipped()
        .animation(.easeInOut(duration: 1.1), value: artworkData)
        .accessibilityHidden(true)
    }
}
