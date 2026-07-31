import AppKit
import os
import ScreenSaver
import SwiftUI

@objc(MusicScreenSaverView)
final class MusicScreenSaverView: ScreenSaverView {
    private let logger = Logger(subsystem: "com.example.MusicScreen", category: "ScreenSaver")
    private var hostingView: NSHostingView<ScreenSaverHostView>?
    private var monitor: SharedCacheMonitor?

    override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)
        configureView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureView()
    }

    private func configureView() {
        logger.info("Screen saver configured; preview=\(self.isPreview, privacy: .public)")
        animationTimeInterval = 1.0 / 30.0
        let monitor = SharedCacheMonitor()
        let host = NSHostingView(
            rootView: ScreenSaverHostView(
                monitor: monitor,
                settings: SharedSettings.shared
            )
        )
        host.translatesAutoresizingMaskIntoConstraints = false
        addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: leadingAnchor),
            host.trailingAnchor.constraint(equalTo: trailingAnchor),
            host.topAnchor.constraint(equalTo: topAnchor),
            host.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        self.monitor = monitor
        hostingView = host
    }

    override func startAnimation() {
        super.startAnimation()
        logger.info("Screen saver animation started; preview=\(self.isPreview, privacy: .public)")
        monitor?.start()
    }

    override func stopAnimation() {
        monitor?.stop()
        logger.info("Screen saver animation stopped; preview=\(self.isPreview, privacy: .public)")
        super.stopAnimation()
    }

    override func animateOneFrame() {}

    override var hasConfigureSheet: Bool { false }
    override var configureSheet: NSWindow? { nil }
}
