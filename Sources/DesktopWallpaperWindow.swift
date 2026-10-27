import Cocoa
import AVFoundation

class DesktopWallpaperWindow: NSWindow {
    let screenTarget: NSScreen
    private var playerLayer: AVPlayerLayer?
    
    init(screen: NSScreen, player: AVPlayer?) {
        self.screenTarget = screen
        
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        
        self.level = NSWindow.Level(Int(CGWindowLevelForKey(.desktopWindow)) + 1)
        self.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        self.ignoresMouseEvents = true
        self.isOpaque = true
        self.backgroundColor = .black
        self.hasShadow = false
        
        setupLayer(player: player)
    }
    
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    
    private func setupLayer(player: AVPlayer?) {
        let containerView = NSView(frame: NSRect(origin: .zero, size: screenTarget.frame.size))
        containerView.wantsLayer = true
        
        let layer = AVPlayerLayer(player: player)
        layer.frame = containerView.bounds
        layer.videoGravity = .resizeAspectFill
        layer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        containerView.layer?.addSublayer(layer)
        self.playerLayer = layer
        
        self.contentView = containerView
        self.setFrame(screenTarget.frame, display: true)
    }
    
    func attachPlayer(_ player: AVPlayer?) {
        CATransaction.begin()
        let transition = CATransition()
        transition.type = .fade
        transition.duration = 0.5
        contentView?.layer?.add(transition, forKey: "fadeTransition")
        
        self.playerLayer?.player = player
        CATransaction.commit()
    }
    
    func start() {
        self.orderFrontRegardless()
    }
    
    func stop() {
        self.orderOut(nil)
    }
    
    func updateFrame(screen: NSScreen) {
        self.setFrame(screen.frame, display: true)
        self.playerLayer?.frame = NSRect(origin: .zero, size: screen.frame.size)
    }
    
    deinit {
        playerLayer?.player = nil
        playerLayer = nil
    }
}
