import AppKit
import SwiftUI

struct ArtworkView: View {
    let artworkData: Data?
    var cornerRadius: CGFloat = 22
    var showsShadow = true

    private var image: NSImage? {
        artworkData.flatMap(NSImage.init(data:))
    }

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    LinearGradient(
                        colors: [Color(red: 0.19, green: 0.21, blue: 0.27), .black],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    Image(systemName: "music.note")
                        .font(.system(size: 58, weight: .light))
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .shadow(color: showsShadow ? .black.opacity(0.4) : .clear, radius: 26, y: 14)
        .accessibilityLabel("Album artwork")
    }
}
