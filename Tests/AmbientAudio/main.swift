import Cocoa
import Foundation

// Isolate the actual audio processor from wallpaper windows and user settings.
extension Notification.Name { static let wallpaperStateChanged = Notification.Name("testWallpaperStateChanged") }
struct WallpaperAsset { let name: String }
class WallpaperEngine {
    static let shared = WallpaperEngine()
    let currentWallpaper: WallpaperAsset? = nil
    func isAnyScreenAnimating() -> Bool { false }
}

let args = CommandLine.arguments
precondition(args.count == 4)
let input = URL(fileURLWithPath: args[1])
guard let raw = AmbientSoundManager.processAudioFile(fileURL: input, warmFilter: false),
      let warm = AmbientSoundManager.processAudioFile(fileURL: input, warmFilter: true) else {
    fatalError("Cannot process audio fixture")
}
try raw.write(to: URL(fileURLWithPath: args[2]))
try warm.write(to: URL(fileURLWithPath: args[3]))
