import Cocoa
import Foundation

// Test matching without opening a player, accessing user settings, or requiring
// the system's optional audio files.
extension Notification.Name { static let wallpaperStateChanged = Notification.Name("testWallpaperStateChanged") }
struct WallpaperAsset { let name: String }
class WallpaperEngine {
    static let shared = WallpaperEngine()
    let currentWallpaper: WallpaperAsset? = nil
    func isAnyScreenAnimating() -> Bool { false }
}

let cases: [(String, String?)] = [
    ("Golden Gate Sunset", nil),
    ("City Sunrise", nil),
    ("Gray Reef Sharks", nil),
    ("Sea Stars", nil),
    ("Coral Reef", nil),
    ("Sonoma Clouds", nil),
    ("Seattle at night", nil),
    ("Dubai", nil),
    ("Iceland", nil),
    ("Yosemite", nil),
    ("Sequoia Night", nil),
    ("brain training", nil),
    ("rain on a beach", nil),
    ("篝火旁的海浪", nil),
    ("sunset in the forest", nil),
    ("Coastal beach", "Ocean.m4a"),
    ("Ocean WAVES", "Ocean.m4a"),
    ("A shark near the reef", nil),
    ("Steady rain", "Rain.m4a"),
    ("A waterfall and river", "Stream.m4a"),
    ("Campfire", "Fire.m4a"),
    ("海滩与海浪", "Ocean.m4a"),
    ("珊瑚礁与鲨鱼", nil),
    ("山间瀑布", "Stream.m4a"),
    ("溪流与河流", "Stream.m4a"),
    ("下雨和雨滴", "Rain.m4a"),
    ("营火与篝火", "Fire.m4a"),
    ("黄昏云海", nil),
    ("", nil)
]

for (name, expected) in cases {
    let actual = AmbientSoundManager.explicitSoundMatch(for: name)
    guard actual == expected else {
        fputs("FAIL: \(name.debugDescription): expected \(String(describing: expected)), got \(String(describing: actual))\n", stderr)
        exit(1)
    }
}
print("Ambient matching tests passed (\(cases.count) cases)")
