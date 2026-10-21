import Cocoa
import AVFoundation

extension Notification.Name {
    static let wallpaperStateChanged = Notification.Name("wallpaperStateChangedNotification")
}

class WallpaperEngine {
    static let shared = WallpaperEngine()
    
    private(set) var currentWallpaper: WallpaperAsset?
    private var windows: [CGDirectDisplayID: DesktopWallpaperWindow] = [:]
    
    init() {
        self.currentWallpaper = WallpaperDetector.shared.getActiveWallpaper()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
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
    
    func setWallpaper(_ asset: WallpaperAsset) {
        self.currentWallpaper = asset
        for (_, win) in windows {
            win.switchVideo(url: asset.url)
        }
        notifyChange()
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
