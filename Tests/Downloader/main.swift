import Foundation

guard CommandLine.arguments.count == 3, let server = URL(string: CommandLine.arguments[1]) else {
    fatalError("Expected server URL and temporary directory")
}
let root = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
let manifest = root.appendingPathComponent("entries.json")
let videos = root.appendingPathComponent("videos", isDirectory: true)
let suiteName = "DynamicDesktop.DownloaderTests.\(UUID().uuidString)"
let defaults = UserDefaults(suiteName: suiteName)!
defaults.set(false, forKey: "AutoDownloadWallpapers")
defer { defaults.removePersistentDomain(forName: suiteName) }

func writeManifest(_ id: String, _ path: String) throws {
    let asset: [String: Any] = ["id": id, "accessibilityLabel": id,
                                "url-4K-SDR-240FPS": server.appendingPathComponent(path).absoluteString]
    try JSONSerialization.data(withJSONObject: ["assets": [asset]]).write(to: manifest)
}

func waitUntil(_ condition: () -> Bool) -> Bool {
    let deadline = Date().addingTimeInterval(5)
    while !condition() && Date() < deadline {
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))
    }
    return condition()
}

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

do {
    let downloader = WallpaperDownloader(manifestURL: manifest, videosDir: videos, defaultsSuiteName: suiteName)

    // A cancelled response must not overwrite the state or destination of a new task.
    try writeManifest("old", "slow")
    downloader.downloadBatch(count: 1)
    require(downloader.isDownloading, "old download did not start")
    require(waitUntil { FileManager.default.fileExists(atPath: root.appendingPathComponent("slow-started").path) }, "old request did not reach the server")
    downloader.pauseDownload()
    try writeManifest("new", "success")
    downloader.downloadBatch(count: 1)
    require(waitUntil { !downloader.isDownloading }, "replacement download timed out")
    let newFile = videos.appendingPathComponent("new.mov")
    require((try? String(contentsOf: newFile, encoding: .utf8)) == "new video", "replacement contents are incorrect")
    RunLoop.main.run(until: Date().addingTimeInterval(1))
    require(!FileManager.default.fileExists(atPath: videos.appendingPathComponent("old.mov").path), "cancelled response was saved")
    require((try? String(contentsOf: newFile, encoding: .utf8)) == "new video", "cancelled response overwrote replacement")

    // URLSession considers an HTTP 404 a completed transfer; it must not be saved.
    try writeManifest("missing", "missing")
    downloader.downloadBatch(count: 1)
    require(downloader.isDownloading, "failed-response download did not start")
    require(waitUntil { !downloader.isDownloading }, "failed-response download timed out")
    require(!FileManager.default.fileExists(atPath: videos.appendingPathComponent("missing.mov").path), "HTTP error body was saved as wallpaper")
    downloader.pauseDownload()
    print("Downloader regression tests passed")
} catch {
    fputs("FAIL: \(error)\n", stderr)
    exit(1)
}
