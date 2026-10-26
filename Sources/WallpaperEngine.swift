import Cocoa
import AVFoundation

extension Notification.Name {
    static let wallpaperStateChanged = Notification.Name("wallpaperStateChangedNotification")
}

class WallpaperEngine {
    static let shared = WallpaperEngine()
    
    private(set) var currentWallpaper: WallpaperAsset?
    private var windows: [CGDirectDisplayID: DesktopWallpaperWindow] = [:]
    private var autoSwitchTimer: Timer?
    
    // Settings Keys
    private let keySyncAllScreens = "SyncAllScreensOnSwitch"
    private let keyAutoSwitchInterval = "AutoSwitchInterval"
    private let keyAutoSwitchShuffle = "AutoSwitchShuffle"
    private let keyLastWallpaperID = "LastSelectedWallpaperID"
    
    var syncAllScreensOnSwitch: Bool {
        get {
            if UserDefaults.standard.object(forKey: keySyncAllScreens) == nil {
                return true // Default: sync all screens on wallpaper change
            }
            return UserDefaults.standard.bool(forKey: keySyncAllScreens)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: keySyncAllScreens)
            notifyChange()
        }
    }
    
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
        // Load initial wallpaper (saved preference, active system wallpaper, or first available)
        let all = WallpaperDetector.shared.getAllWallpapers()
        if let savedID = UserDefaults.standard.string(forKey: keyLastWallpaperID),
           let saved = all.first(where: { $0.id == savedID }) {
            self.currentWallpaper = saved
        } else {
            self.currentWallpaper = WallpaperDetector.shared.getActiveWallpaper()
        }
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        
        // Start auto switch timer if previously configured
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
    
    func startAnimating(screen: NSScreen) {
        guard let did = displayID(for: screen) else { return }
        if let existing = windows[did] {
            existing.start()
            notifyChange()
            return
        }
        
        guard let wallpaper = currentWallpaper else {
            if let refreshed = WallpaperDetector.shared.getActiveWallpaper() {
                self.currentWallpaper = refreshed
            } else {
                print("No native wallpaper found to animate!")
                return
            }
            return
        }
        
        let window = DesktopWallpaperWindow(screen: screen, videoURL: wallpaper.url)
        windows[did] = window
        window.start()
        notifyChange()
    }
    
    func stopAnimating(screen: NSScreen) {
        guard let did = displayID(for: screen) else { return }
        if let window = windows[did] {
            window.stop()
            windows.removeValue(forKey: did)
            notifyChange()
        }
    }
    
    func toggleScreen(screen: NSScreen) {
        if isScreenAnimating(screen) {
            stopAnimating(screen: screen)
        } else {
            startAnimating(screen: screen)
        }
    }
    
    func startAll() {
        for screen in NSScreen.screens {
            startAnimating(screen: screen)
        }
    }
    
    func stopAll() {
        for (_, win) in windows {
            win.stop()
        }
        windows.removeAll()
        notifyChange()
    }
    
    /// Switches wallpaper. When syncAllScreens is true, all connected screens will be updated/started together.
    func setWallpaper(_ asset: WallpaperAsset, syncAllScreens: Bool? = nil) {
        self.currentWallpaper = asset
        UserDefaults.standard.set(asset.id, forKey: keyLastWallpaperID)
        
        let shouldSync = syncAllScreens ?? self.syncAllScreensOnSwitch
        
        if shouldSync {
            // Apply to ALL connected displays
            for screen in NSScreen.screens {
                guard let did = displayID(for: screen) else { continue }
                if let win = windows[did] {
                    win.switchVideo(url: asset.url)
                } else {
                    // If not currently animating on this screen, create and start it
                    let window = DesktopWallpaperWindow(screen: screen, videoURL: asset.url)
                    windows[did] = window
                    window.start()
                }
            }
        } else {
            // Only update displays that are currently animating
            for (_, win) in windows {
                win.switchVideo(url: asset.url)
            }
        }
        
        notifyChange()
    }
    
    /// Switches to the next available wallpaper
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
        
        setWallpaper(nextWallpaper, syncAllScreens: syncAllScreensOnSwitch)
    }
    
    /// Starts or restarts the auto-switch timer based on autoSwitchInterval
    private func startAutoSwitchTimer() {
        autoSwitchTimer?.invalidate()
        autoSwitchTimer = nil
        
        let interval = autoSwitchInterval
        guard interval > 0 else { return }
        
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            // Only auto-switch if at least one screen is currently animating
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
