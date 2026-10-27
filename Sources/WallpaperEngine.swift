import Cocoa
import AVFoundation

extension Notification.Name {
    static let wallpaperStateChanged = Notification.Name("wallpaperStateChangedNotification")
}

class WallpaperEngine {
    static let shared = WallpaperEngine()
    
    private(set) var currentWallpaper: WallpaperAsset?
    private(set) var stillFrameError: String?
    private var sharedPlayer: AVQueuePlayer?
    private var sharedLooper: AVPlayerLooper?
    
    private var windows: [CGDirectDisplayID: DesktopWallpaperWindow] = [:]
    private var animatingScreenIDs: Set<CGDirectDisplayID> = []
    private var wallpaperIsDisplayed = false
    private var stillImage: CGImage?
    private var stillImageWallpaperID: String?
    private var imageGenerator: AVAssetImageGenerator?
    private var imageGeneration = 0
    private var autoSwitchTimer: Timer?
    private var savedAnimatingScreenIDs: Set<CGDirectDisplayID> = []
    private var isRestoringState = false
    
    // Settings Keys
    private let keyAutoSwitchInterval = "AutoSwitchInterval"
    private let keyAutoSwitchShuffle = "AutoSwitchShuffle"
    private let keyLastWallpaperID = "LastSelectedWallpaperID"
    private let keySessionEnabled = "WallpaperSessionEnabled"
    private let keyAnimatingDisplayIDs = "WallpaperAnimatingDisplayIDs"
    
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
        savedAnimatingScreenIDs = Set((UserDefaults.standard.array(forKey: keyAnimatingDisplayIDs) as? [NSNumber] ?? []).map { CGDirectDisplayID($0.uint32Value) })
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
    
    /// Restore the last user-selected motion states without changing the saved
    /// configuration for displays that are currently disconnected.
    func restorePreviousSession() {
        guard UserDefaults.standard.bool(forKey: keySessionEnabled),
              let wallpaper = currentWallpaper ?? WallpaperDetector.shared.getActiveWallpaper() else { return }
        currentWallpaper = wallpaper
        wallpaperIsDisplayed = true
        isRestoringState = true
        for screen in NSScreen.screens {
            guard let id = displayID(for: screen), savedAnimatingScreenIDs.contains(id) else { continue }
            startScreen(screen)
        }
        isRestoringState = false
        if stillImageWallpaperID == wallpaper.id {
            updateStaticScreens()
        } else if imageGenerator == nil {
            requestStillImage(for: wallpaper)
        }
        notifyChange()
    }

    private func saveMotionState() {
        guard !isRestoringState else { return }
        UserDefaults.standard.set(wallpaperIsDisplayed, forKey: keySessionEnabled)
        UserDefaults.standard.set(savedAnimatingScreenIDs.sorted().map { NSNumber(value: $0) }, forKey: keyAnimatingDisplayIDs)
    }

    private func displayID(for screen: NSScreen) -> CGDirectDisplayID? {
        guard let num = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }
        return CGDirectDisplayID(num.uint32Value)
    }
    
    func isScreenAnimating(_ screen: NSScreen) -> Bool {
        guard let did = displayID(for: screen) else { return false }
        return animatingScreenIDs.contains(did)
    }
    
    func isAnyScreenAnimating() -> Bool {
        return !animatingScreenIDs.isEmpty
    }
    
    private func ensureSharedPlayer(for asset: WallpaperAsset) {
        let playerItem = AVPlayerItem(url: asset.url)
        // AVPlayerLooper owns the queue and inserts copies of its template item.
        let player = AVQueuePlayer()
        player.isMuted = true
        player.automaticallyWaitsToMinimizeStalling = false
        self.sharedLooper = AVPlayerLooper(player: player, templateItem: playerItem)
        self.sharedPlayer = player
    }
    
    private func window(for screen: NSScreen, id: CGDirectDisplayID) -> DesktopWallpaperWindow {
        if let window = windows[id] { return window }
        let window = DesktopWallpaperWindow(screen: screen)
        windows[id] = window
        return window
    }

    // Decode away from the main thread and ignore completions from older choices.
    private func requestStillImage(for asset: WallpaperAsset) {
        imageGeneration += 1
        let generation = imageGeneration
        if stillFrameError != nil {
            stillFrameError = nil
            notifyChange()
        }
        imageGenerator?.cancelAllCGImageGeneration()
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: asset.url))
        generator.appliesPreferredTrackTransform = true
        imageGenerator = generator
        generator.generateCGImagesAsynchronously(forTimes: [NSValue(time: .zero)]) { [weak self] _, image, _, result, error in
            DispatchQueue.main.async {
                guard let self = self, self.imageGeneration == generation,
                      self.wallpaperIsDisplayed, self.currentWallpaper?.id == asset.id else { return }
                self.imageGenerator = nil
                guard result == .succeeded, let image = image else {
                    print("Could not extract wallpaper frame: \(error?.localizedDescription ?? "unknown error")")
                    if self.stillImageWallpaperID != asset.id {
                        self.stillFrameError = "无法生成静态画面，请重新选择壁纸重试"
                        self.notifyChange()
                    }
                    return
                }
                self.stillFrameError = nil
                self.stillImage = image
                self.stillImageWallpaperID = asset.id
                self.updateStaticScreens()
                self.notifyChange()
            }
        }
    }

    private func updateStaticScreens() {
        guard wallpaperIsDisplayed, let wallpaper = currentWallpaper,
              stillImageWallpaperID == wallpaper.id, let image = stillImage else { return }
        for screen in NSScreen.screens {
            guard let id = displayID(for: screen), !animatingScreenIDs.contains(id) else { continue }
            let window = window(for: screen, id: id)
            window.showStill(image)
            window.start()
        }
    }

    /// Starts dynamic wallpaper on one screen; the other screens show its still frame.
    func startScreen(_ screen: NSScreen) {
        guard let id = displayID(for: screen),
              let wallpaper = currentWallpaper ?? WallpaperDetector.shared.getActiveWallpaper() else { return }
        currentWallpaper = wallpaper
        wallpaperIsDisplayed = true
        if sharedPlayer == nil { ensureSharedPlayer(for: wallpaper) }
        animatingScreenIDs.insert(id)
        if !isRestoringState {
            savedAnimatingScreenIDs.insert(id)
            saveMotionState()
        }
        let window = window(for: screen, id: id)
        window.showPlayer(sharedPlayer)
        window.start()
        sharedPlayer?.play()
        AmbientSoundManager.shared.play()
        if stillImageWallpaperID == wallpaper.id {
            updateStaticScreens()
        } else if imageGenerator == nil {
            requestStillImage(for: wallpaper)
        }
        notifyChange()
    }

    /// Keeps the selected wallpaper visible as a still image on this screen.
    func stopScreen(_ screen: NSScreen) {
        guard let id = displayID(for: screen), animatingScreenIDs.remove(id) != nil else { return }
        if !isRestoringState {
            savedAnimatingScreenIDs.remove(id)
            saveMotionState()
        }
        if let image = stillImage {
            // Keep the previous still visible until the new wallpaper is decoded.
            windows[id]?.showStill(image)
        } else {
            // Do not leave a black window while the first still is being decoded.
            windows.removeValue(forKey: id)?.stop()
        }
        if let wallpaper = currentWallpaper, stillImageWallpaperID != wallpaper.id, imageGenerator == nil {
            requestStillImage(for: wallpaper)
        }
        if animatingScreenIDs.isEmpty {
            sharedPlayer?.pause()
            AmbientSoundManager.shared.pause()
        }
        notifyChange()
    }

    func toggleScreen(_ screen: NSScreen) {
        if isScreenAnimating(screen) { stopScreen(screen) } else { startScreen(screen) }
    }

    func toggleScreen(screen: NSScreen) {
        toggleScreen(screen)
    }

    func startAll() {
        for screen in NSScreen.screens { startScreen(screen) }
        AmbientSoundManager.shared.play()
    }

    /// Remove all overlays, for example when the application quits.
    func stopAll() {
        wallpaperIsDisplayed = false
        stillFrameError = nil
        imageGeneration += 1
        imageGenerator?.cancelAllCGImageGeneration()
        imageGenerator = nil
        animatingScreenIDs.removeAll()
        sharedPlayer?.pause()
        AmbientSoundManager.shared.pause()
        for window in windows.values { window.stop() }
        windows.removeAll()
        notifyChange()
    }

    func toggleAll() {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return }
        if screens.allSatisfy({ isScreenAnimating($0) }) {
            for screen in screens { stopScreen(screen) }
        } else {
            startAll()
        }
    }

    /// Changes the common wallpaper without changing each screen's motion state.
    func setWallpaper(_ asset: WallpaperAsset) {
        currentWallpaper = asset
        UserDefaults.standard.set(asset.id, forKey: keyLastWallpaperID)
        sharedPlayer?.pause()
        ensureSharedPlayer(for: asset)
        if !wallpaperIsDisplayed {
            startAll()
        } else {
            for id in animatingScreenIDs {
                windows[id]?.showPlayer(sharedPlayer)
            }
            if !animatingScreenIDs.isEmpty { sharedPlayer?.play() }
            AmbientSoundManager.shared.updateForWallpaper(asset)
            requestStillImage(for: asset)
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
        for id in windows.keys.filter({ !validScreenIDs.contains($0) }) {
            windows.removeValue(forKey: id)?.stop()
        }
        animatingScreenIDs.formIntersection(validScreenIDs)
        if wallpaperIsDisplayed {
            isRestoringState = true
            for screen in NSScreen.screens {
                guard let id = displayID(for: screen), savedAnimatingScreenIDs.contains(id),
                      !animatingScreenIDs.contains(id) else { continue }
                startScreen(screen)
            }
            isRestoringState = false
        }
        if animatingScreenIDs.isEmpty { sharedPlayer?.pause() }
        for screen in NSScreen.screens {
            if let id = displayID(for: screen), let window = windows[id] {
                window.updateFrame(screen: screen)
            }
        }
        updateStaticScreens()
        notifyChange()
    }
}
