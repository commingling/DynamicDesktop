import Cocoa
import AVFoundation

extension Notification.Name {
    static let wallpaperStateChanged = Notification.Name("wallpaperStateChangedNotification")
}

class WallpaperEngine {
    static let shared = WallpaperEngine()
    
    private(set) var currentWallpaper: WallpaperAsset?
    private var sharedPlayer: AVQueuePlayer?
    private var sharedLooper: AVPlayerLooper?
    
    private var windows: [CGDirectDisplayID: DesktopWallpaperWindow] = [:]
    private var autoSwitchTimer: Timer?
    
    // Settings Keys
    private let keyAutoSwitchInterval = "AutoSwitchInterval"
    private let keyAutoSwitchShuffle = "AutoSwitchShuffle"
    private let keyLastWallpaperID = "LastSelectedWallpaperID"
    
    var autoSwitchInterval: TimeInterval {
        get {
            return UserDefaults.standard.double(forKey: keyAutoSwitchInterval)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: keyAutoSwitchInterval)
            startAutoSwitchTimer()
            notifyChange()
        }
    }
    
    var isShuffleEnabled: Bool {
        get {
            return UserDefaults.standard.bool(forKey: keyAutoSwitchShuffle)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: keyAutoSwitchShuffle)
            notifyChange()
        }
    }
    
    init() {
        // Load initial wallpaper
        let all = WallpaperDetector.shared.getAllWallpapers()
        if let savedID = UserDefaults.standard.string(forKey: keyLastWallpaperID),
           let saved = all.first(where: { $0.id == savedID }) {
            self.currentWallpaper = saved
        } else {
            self.currentWallpaper = WallpaperDetector.shared.getActiveWallpaper() ?? all.first
        }
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        
        startAutoSwitchTimer()
    }
    
    private func displayID(for screen: NSScreen) -> CGDirectDisplayID? {
        guard let num = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }
        return CGDirectDisplayID(num.uint32Value)
    }
    
    func isScreenAnimating(_ screen: NSScreen) -> Bool {
        guard let did = displayID(for: screen) else { return false }
        return windows[did] != nil
    }
    
    func isAnyScreenAnimating() -> Bool {
        return !windows.isEmpty
    }
    
    private func ensureSharedPlayer(for asset: WallpaperAsset) {
        let playerItem = AVPlayerItem(url: asset.url)
        let player = AVQueuePlayer(playerItem: playerItem)
        player.isMuted = true
        player.automaticallyWaitsToMinimizeStalling = false
        self.sharedLooper = AVPlayerLooper(player: player, templateItem: playerItem)
        self.sharedPlayer = player
    }
    
    /// Starts dynamic wallpaper on a specific screen using the shared player
    func startScreen(_ screen: NSScreen) {
        guard let did = displayID(for: screen) else { return }
        guard let wallpaper = currentWallpaper ?? WallpaperDetector.shared.getActiveWallpaper() else { return }
        self.currentWallpaper = wallpaper
        
        if sharedPlayer == nil {
            ensureSharedPlayer(for: wallpaper)
        }
        
        if let existing = windows[did] {
            existing.attachPlayer(sharedPlayer)
            existing.start()
        } else {
            let win = DesktopWallpaperWindow(screen: screen, player: sharedPlayer)
            windows[did] = win
            win.start()
        }
        
        sharedPlayer?.play()
        notifyChange()
    }
    
    /// Stops dynamic wallpaper on a specific screen
    func stopScreen(_ screen: NSScreen) {
        guard let did = displayID(for: screen) else { return }
        if let win = windows[did] {
            win.stop()
            windows.removeValue(forKey: did)
        }
        if windows.isEmpty {
            sharedPlayer?.pause()
        }
        notifyChange()
    }
    
    /// Toggles a specific screen on or off
    func toggleScreen(_ screen: NSScreen) {
        if isScreenAnimating(screen) {
            stopScreen(screen)
        } else {
            startScreen(screen)
        }
    }
    
    func toggleScreen(screen: NSScreen) {
        toggleScreen(screen)
    }
    
    /// Starts dynamic wallpaper on ALL connected screens simultaneously
    func startAll() {
        for screen in NSScreen.screens {
            startScreen(screen)
        }
    }
    
    /// Stops dynamic wallpaper on ALL screens
    func stopAll() {
        sharedPlayer?.pause()
        for (_, win) in windows {
            win.stop()
        }
        windows.removeAll()
        notifyChange()
    }
    
    /// Toggles all screens on or off together
    func toggleAll() {
        let allAnimating = NSScreen.screens.allSatisfy { isScreenAnimating($0) }
        if allAnimating {
            stopAll()
        } else {
            startAll()
        }
    }
    
    /// Sets a new wallpaper and synchronizes it across all currently active screens
    func setWallpaper(_ asset: WallpaperAsset) {
        self.currentWallpaper = asset
        UserDefaults.standard.set(asset.id, forKey: keyLastWallpaperID)
        
        let oldPlayer = sharedPlayer
        oldPlayer?.pause()
        
        // Create new synchronized player for this wallpaper
        ensureSharedPlayer(for: asset)
        
        if windows.isEmpty {
            // If no screen was running, start all screens so user sees the change
            startAll()
        } else {
            // Update all currently active screen windows with the new player
            for (_, win) in windows {
                win.attachPlayer(sharedPlayer)
            }
            sharedPlayer?.play()
            notifyChange()
        }
    }
    
    /// Cycles to the next available wallpaper
    func switchToNextWallpaper() {
        let all = WallpaperDetector.shared.getAllWallpapers()
        guard !all.isEmpty else { return }
        
        let nextWallpaper: WallpaperAsset
        if isShuffleEnabled && all.count > 1 {
            let candidates = all.filter { $0.id != self.currentWallpaper?.id }
            nextWallpaper = candidates.randomElement() ?? all[0]
        } else {
            if let current = currentWallpaper, let idx = all.firstIndex(of: current) {
                let nextIdx = (idx + 1) % all.count
                nextWallpaper = all[nextIdx]
            } else {
                nextWallpaper = all[0]
            }
        }
        
        setWallpaper(nextWallpaper)
    }
    
    private func startAutoSwitchTimer() {
        autoSwitchTimer?.invalidate()
        autoSwitchTimer = nil
        
        let interval = autoSwitchInterval
        guard interval > 0 else { return }
        
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            if self.isAnyScreenAnimating() {
                self.switchToNextWallpaper()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.autoSwitchTimer = timer
    }
    
    private func notifyChange() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .wallpaperStateChanged, object: nil)
        }
    }
    
    @objc private func screenParametersChanged() {
        let validScreenIDs = Set(NSScreen.screens.compactMap { displayID(for: $0) })
        for (did, win) in windows {
            if !validScreenIDs.contains(did) {
                win.stop()
                windows.removeValue(forKey: did)
            }
        }
        for screen in NSScreen.screens {
            if let did = displayID(for: screen), let win = windows[did] {
                win.updateFrame(screen: screen)
            }
        }
        notifyChange()
    }
}
