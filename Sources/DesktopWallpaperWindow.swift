import Cocoa
import AVFoundation

class DesktopWallpaperWindow: NSWindow {
    let screenTarget: NSScreen
    private var queuePlayer: AVQueuePlayer?
    private var playerLooper: AVPlayerLooper?
    private var playerLayer: AVPlayerLayer?
    
    init(screen: NSScreen, videoURL: URL) {
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
        
        setupPlayer(url: videoURL)
    }
    
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    
    private func setupPlayer(url: URL) {
        let playerItem = AVPlayerItem(url: url)
        let player = AVQueuePlayer(playerItem: playerItem)
        player.isMuted = true
        player.automaticallyWaitsToMinimizeStalling = false
        self.playerLooper = AVPlayerLooper(player: player, templateItem: playerItem)
        self.queuePlayer = player
        
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
    
    func start() {
        self.orderFrontRegardless()
        queuePlayer?.play()
    }
    
    func stop() {
        queuePlayer?.pause()
        self.orderOut(nil)
    }
    
    func switchVideo(url: URL) {
        let playerItem = AVPlayerItem(url: url)
        let newPlayer = AVQueuePlayer(playerItem: playerItem)
        newPlayer.isMuted = true
        newPlayer.automaticallyWaitsToMinimizeStalling = false
        let newLooper = AVPlayerLooper(player: newPlayer, templateItem: playerItem)
        
        // Smooth cross-fade transition
        CATransaction.begin()
        let transition = CATransition()
        transition.type = .fade
        transition.duration = 0.5
        contentView?.layer?.add(transition, forKey: "fadeTransition")
        
        queuePlayer?.pause()
        self.playerLooper = newLooper
        self.queuePlayer = newPlayer
        self.playerLayer?.player = newPlayer
        newPlayer.play()
        CATransaction.commit()
    }
    
    func updateFrame(screen: NSScreen) {
        self.setFrame(screen.frame, display: true)
        self.playerLayer?.frame = NSRect(origin: .zero, size: screen.frame.size)
    }
    
    deinit {
        queuePlayer?.pause()
        queuePlayer = nil
        playerLooper = nil
    }
}
