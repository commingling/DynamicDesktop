import Cocoa
import Foundation

extension Notification.Name { static let wallpaperStateChanged = Notification.Name("testWallpaperStateChanged") }
struct WallpaperAsset { let name: String }
class WallpaperEngine {
    static let shared = WallpaperEngine()
    var currentWallpaper: WallpaperAsset? = nil
    func isAnyScreenAnimating() -> Bool { true }
}

// Shadow AVAudioPlayer in the test module so no device receives audio.
class AVAudioPlayer {
    var isPlaying = false
    var volume: Float = 0
    var numberOfLoops = 0
    required init(data: Data) throws {}
    @discardableResult func prepareToPlay() -> Bool { true }
    @discardableResult func play() -> Bool { isPlaying = true; return true }
    func pause() { isPlaying = false }
    func stop() { isPlaying = false }
    func setVolume(_ value: Float, fadeDuration: TimeInterval) { volume = value }
}

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fputs("FAIL: \(message)\n", stderr); exit(1) }
}

let suite = ProcessInfo.processInfo.environment["DYNAMICDESKTOP_TEST_DEFAULTS"]!
let defaults = UserDefaults(suiteName: suite)!
defaults.removePersistentDomain(forName: suite)
defaults.set(true, forKey: "AmbientSoundEnabled")
defaults.set(true, forKey: "AmbientSoundWarmFilter")
defaults.set("auto", forKey: "AmbientSoundType")
let manager = AmbientSoundManager()
manager.audioCache["Ocean.m4a_warm"] = Data([1])
manager.audioCache["Stream.m4a_warm"] = Data([1])
let engine = WallpaperEngine.shared
engine.currentWallpaper = WallpaperAsset(name: "Beach")
manager.updateForWallpaper(engine.currentWallpaper)
require(manager.activePlayer?.isPlaying == true, "explicit beach sound did not start")
let beachPlayer = manager.activePlayer
engine.currentWallpaper = WallpaperAsset(name: "City Sunrise")
manager.updateForWallpaper(engine.currentWallpaper)
require(manager.activePlayer?.volume == 0, "unknown scene did not fade audio")
RunLoop.main.run(until: Date().addingTimeInterval(0.35))
require(beachPlayer?.isPlaying == false, "unknown scene did not pause audio")

engine.currentWallpaper = WallpaperAsset(name: "Beach")
manager.play()
require(manager.activePlayer?.isPlaying == true, "matched scene did not resume audio")
engine.currentWallpaper = WallpaperAsset(name: "City Sunrise")
manager.updateForWallpaper(engine.currentWallpaper)
engine.currentWallpaper = WallpaperAsset(name: "Beach")
manager.updateForWallpaper(engine.currentWallpaper)
RunLoop.main.run(until: Date().addingTimeInterval(0.35))
require(manager.activePlayer?.isPlaying == true && (manager.activePlayer?.volume ?? 0) > 0,
        "old unmatched-scene fade interrupted resumed audio")

let oldToken = UUID()
manager.currentFileRequestToken = oldToken
manager.pendingFile = "Stream.m4a"
engine.currentWallpaper = WallpaperAsset(name: "City Sunrise")
manager.updateForWallpaper(engine.currentWallpaper)
require(manager.currentFileRequestToken != oldToken && manager.pendingFile == nil,
        "unknown scene did not invalidate pending audio")
manager.selectedType = .stream
require(manager.activePlayer?.isPlaying == true && manager.currentPlayingFile == "Stream.m4a",
        "manual selection did not play on an unmatched scene")
RunLoop.main.run(until: Date().addingTimeInterval(0.4))
require(manager.activePlayer?.isPlaying == true, "old fade paused manual audio")
defaults.removePersistentDomain(forName: suite)
print("Ambient playback state tests passed")
