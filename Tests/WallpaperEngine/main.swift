import Cocoa
import AVFoundation

// Test doubles prevent the engine from creating real desktop windows or reading
// the user's wallpaper catalog. The engine and image generation remain real.
struct WallpaperAsset: Identifiable, Equatable {
    let id: String
    let name: String
    let url: URL
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
}

var testCatalog: [WallpaperAsset] = []

class WallpaperDetector {
    static let shared = WallpaperDetector()
    func getAllWallpapers() -> [WallpaperAsset] { testCatalog }
    func getActiveWallpaper() -> WallpaperAsset? { nil }
}

class DesktopWallpaperWindow {
    static var visible: [CGDirectDisplayID: DesktopWallpaperWindow] = [:]
    let id: CGDirectDisplayID
    var still: CGImage?
    var showingPlayer = false
    init(screen: NSScreen) { id = displayID(screen) }
    func showPlayer(_ player: AVPlayer?) { showingPlayer = player != nil }
    func showStill(_ image: CGImage) { still = image; showingPlayer = false }
    func start() { Self.visible[id] = self }
    func stop() { Self.visible.removeValue(forKey: id) }
    func updateFrame(screen: NSScreen) {}
}

func displayID(_ screen: NSScreen) -> CGDirectDisplayID {
    (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as! NSNumber).uint32Value
}
func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fputs("FAIL: \(message)\n", stderr); exit(1) }
}
func waitUntil(_ condition: () -> Bool, seconds: TimeInterval = 8) -> Bool {
    let deadline = Date().addingTimeInterval(seconds)
    while !condition() && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
    return condition()
}
func pixel(_ image: CGImage?) -> [UInt8] {
    guard let image = image else { return [] }
    var bytes = [UInt8](repeating: 0, count: 4)
    guard let ctx = CGContext(data: &bytes, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                              space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return [] }
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
    return bytes
}
func isRed(_ image: CGImage?) -> Bool { let c = pixel(image); return c.count == 4 && c[0] > 180 && c[2] < 70 }
func isBlue(_ image: CGImage?) -> Bool { let c = pixel(image); return c.count == 4 && c[2] > 180 && c[0] < 70 }

let arguments = CommandLine.arguments
require(arguments.count == 2, "expected temporary directory")
let directory = URL(fileURLWithPath: arguments[1], isDirectory: true)
let suite = ProcessInfo.processInfo.environment["DYNAMICDESKTOP_TEST_DEFAULTS"]!
let defaults = UserDefaults(suiteName: suite)!
defaults.removePersistentDomain(forName: suite)
defaults.set(0, forKey: "AutoSwitchInterval")
_ = NSApplication.shared
let screens = NSScreen.screens
if screens.count < 2 {
    print("SKIP: two displays are required for the screen integration smoke test")
    defaults.removePersistentDomain(forName: suite)
    exit(0)
}
let redURL = directory.appendingPathComponent("red.mov")
let blueURL = directory.appendingPathComponent("blue.mov")
try writeVideo(at: redURL, red: 255, green: 0, blue: 0)
try writeVideo(at: blueURL, red: 0, green: 0, blue: 255)
let red = WallpaperAsset(id: "red", name: "red", url: redURL)
let blue = WallpaperAsset(id: "blue", name: "blue", url: blueURL)
testCatalog = [red, blue]
let engine = WallpaperEngine()
engine.restorePreviousSession()
require(!engine.isAnyScreenAnimating(), "a session that was never enabled started automatically")
engine.setWallpaper(red)
engine.stopScreen(screens[1])
engine.stopAll()
engine.startScreen(screens[0])
require(engine.isScreenAnimating(screens[0]), "first screen should animate")
require(!engine.isScreenAnimating(screens[1]), "second screen should be still")
let staticID = displayID(screens[1])
require(waitUntil { isRed(DesktopWallpaperWindow.visible[staticID]?.still) && DesktopWallpaperWindow.visible[staticID]?.showingPlayer == false }, "static screen did not show red wallpaper")

engine.stopScreen(screens[0])
require(!engine.isAnyScreenAnimating(), "stopping the last animated screen did not pause animation")
require(isRed(DesktopWallpaperWindow.visible[displayID(screens[0])]?.still), "stopped screen did not retain the still image")
engine.startScreen(screens[0])
engine.setWallpaper(blue)
require(engine.isScreenAnimating(screens[0]) && !engine.isScreenAnimating(screens[1]), "wallpaper switch changed screen motion states")
require(waitUntil { isBlue(DesktopWallpaperWindow.visible[staticID]?.still) && DesktopWallpaperWindow.visible[staticID]?.showingPlayer == false }, "static screen did not update to blue wallpaper")

// Exercise invalidation while async image generations overlap.
for _ in 0..<4 { engine.setWallpaper(red); engine.setWallpaper(blue) }
require(waitUntil { isBlue(DesktopWallpaperWindow.visible[staticID]?.still) }, "last wallpaper was not displayed")
RunLoop.main.run(until: Date().addingTimeInterval(0.5))
require(isBlue(DesktopWallpaperWindow.visible[staticID]?.still), "an older image replaced the latest wallpaper")
require(engine.isScreenAnimating(screens[0]) && !engine.isScreenAnimating(screens[1]), "rapid switches changed motion states")
engine.setWallpaper(red)
engine.stopAll()
RunLoop.main.run(until: Date().addingTimeInterval(0.5))
require(DesktopWallpaperWindow.visible.isEmpty, "stopped overlays reappeared")
require(!engine.isAnyScreenAnimating(), "player still marked as animating after stop")
// A new engine must restore both the motion state and the static counterpart.
let savedIDs = (defaults.array(forKey: "WallpaperAnimatingDisplayIDs") as? [NSNumber])!.map { $0.uint32Value }
require(savedIDs.contains(displayID(screens[0])) && !savedIDs.contains(displayID(screens[1])), "saved screen motion states are incorrect")
let disconnectedID: UInt32 = 4_294_967_294
defaults.set(savedIDs.map { NSNumber(value: $0) } + [NSNumber(value: disconnectedID)], forKey: "WallpaperAnimatingDisplayIDs")
let restarted = WallpaperEngine()
restarted.restorePreviousSession()
require(restarted.isScreenAnimating(screens[0]) && !restarted.isScreenAnimating(screens[1]), "restart did not restore screen motion states")
require(waitUntil { isRed(DesktopWallpaperWindow.visible[staticID]?.still) }, "restart did not restore the still screen")
require((defaults.array(forKey: "WallpaperAnimatingDisplayIDs") as? [NSNumber])!.contains(NSNumber(value: disconnectedID)), "restoring removed a disconnected display")
restarted.stopAll()
require(defaults.bool(forKey: "WallpaperSessionEnabled"), "stopping the engine erased the saved session")
defaults.removePersistentDomain(forName: suite)
print("Wallpaper engine smoke test passed")
