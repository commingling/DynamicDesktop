import Cocoa
import AVFoundation

class DesktopWallpaperWindow: NSWindow {
    private var playerLayer: AVPlayerLayer?
    private var stillLayer: CALayer?

    init(screen: NSScreen) {
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        level = NSWindow.Level(Int(CGWindowLevelForKey(.desktopWindow)) + 1)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        ignoresMouseEvents = true
        isOpaque = true
        backgroundColor = .black
        hasShadow = false

        let containerView = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
        containerView.wantsLayer = true

        let still = CALayer()
        still.frame = containerView.bounds
        still.contentsGravity = .resizeAspectFill
        still.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        containerView.layer?.addSublayer(still)
        stillLayer = still

        let video = AVPlayerLayer()
        video.frame = containerView.bounds
        video.videoGravity = .resizeAspectFill
        video.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        video.isHidden = true
        containerView.layer?.addSublayer(video)
        playerLayer = video

        contentView = containerView
        setFrame(screen.frame, display: true)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    private func fadeTransition() {
        let transition = CATransition()
        transition.type = .fade
        transition.duration = 0.5
        contentView?.layer?.add(transition, forKey: "fadeTransition")
    }

    func showPlayer(_ player: AVPlayer?) {
        fadeTransition()
        playerLayer?.player = player
        playerLayer?.isHidden = false
    }

    func showStill(_ image: CGImage) {
        fadeTransition()
        stillLayer?.contents = image
        playerLayer?.isHidden = true
        playerLayer?.player = nil
    }

    func start() {
        orderFrontRegardless()
    }

    func stop() {
        orderOut(nil)
        playerLayer?.player = nil
    }

    func updateFrame(screen: NSScreen) {
        setFrame(screen.frame, display: true)
    }
}
