import Foundation

extension Notification.Name {
    static let wallpaperDownloadProgress = Notification.Name("wallpaperDownloadProgressNotification")
    static let wallpaperDownloadCompleted = Notification.Name("wallpaperDownloadCompletedNotification")
}

struct CatalogAsset: Identifiable, Equatable {
    let id: String
    let name: String
    let downloadURL: URL
    let category: String
    
    static func == (lhs: CatalogAsset, rhs: CatalogAsset) -> Bool {
        return lhs.id == rhs.id
    }
}

class WallpaperDownloader: NSObject, URLSessionDownloadDelegate {
    static let shared = WallpaperDownloader()
    
    private let manifestURL = URL(fileURLWithPath: NSString(string: "~/Library/Application Support/com.apple.wallpaper/aerials/manifest/entries.json").expandingTildeInPath)
    private let videosDir = URL(fileURLWithPath: NSString(string: "~/Library/Application Support/com.apple.wallpaper/aerials/videos").expandingTildeInPath)
    
    private let keyAutoDownload = "AutoDownloadWallpapers"
    
    private var session: URLSession!
    private var currentTask: URLSessionDownloadTask?
    private(set) var currentAsset: CatalogAsset?
    private(set) var progress: Double = 0.0 // 0.0 to 1.0
    private(set) var isDownloading: Bool = false
    
    private var queue: [CatalogAsset] = []
    
    var isAutoDownloadEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: keyAutoDownload) == nil {
                return true // Enabled by default as requested!
            }
            return UserDefaults.standard.bool(forKey: keyAutoDownload)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: keyAutoDownload)
            if newValue {
                checkAndStartNextDownload()
            } else {
                pauseDownload()
            }
            notifyProgress()
        }
    }
    
    override init() {
        super.init()
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 1200
        self.session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        
        // Ensure videos directory exists
        try? FileManager.default.createDirectory(at: videosDir, withIntermediateDirectories: true)
        
        // Auto start background download if enabled
        if isAutoDownloadEnabled {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
                self?.checkAndStartNextDownload()
            }
        }
    }
    
    func getFullCatalog() -> [CatalogAsset] {
        guard let data = try? Data(contentsOf: manifestURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let assets = json["assets"] as? [[String: Any]] else {
            return []
        }
        
        var results: [CatalogAsset] = []
        for a in assets {
            guard let id = a["id"] as? String,
                  let urlString = a["url-4K-SDR-240FPS"] as? String,
                  let url = URL(string: urlString) else {
                continue
            }
            let name = (a["accessibilityLabel"] as? String) ?? "Apple 动态壁纸"
            let cat = (a["categories"] as? [String])?.first ?? "aerials"
            results.append(CatalogAsset(id: id, name: name, downloadURL: url, category: cat))
        }
        return results
    }
    
    func getUndownloadedAssets() -> [CatalogAsset] {
        let catalog = getFullCatalog()
        guard let existingFiles = try? FileManager.default.contentsOfDirectory(at: videosDir, includingPropertiesForKeys: nil) else {
            return catalog
        }
        
        let downloadedIDs = Set(existingFiles.map { $0.deletingPathExtension().lastPathComponent })
        return catalog.filter { !downloadedIDs.contains($0.id) }
    }
    
    func getDownloadedCount() -> Int {
        guard let existingFiles = try? FileManager.default.contentsOfDirectory(at: videosDir, includingPropertiesForKeys: nil) else {
            return 0
        }
        return existingFiles.filter { $0.pathExtension.lowercased() == "mov" }.count
    }
    
    func getTotalCount() -> Int {
        return getFullCatalog().count
    }
    
    func checkAndStartNextDownload() {
        guard isAutoDownloadEnabled || !queue.isEmpty else { return }
        guard !isDownloading else { return }
        
        let target: CatalogAsset?
        if !queue.isEmpty {
            target = queue.removeFirst()
        } else if isAutoDownloadEnabled {
            let undownloaded = getUndownloadedAssets()
            target = undownloaded.first
        } else {
            target = nil
        }
        
        guard let asset = target else {
            // All wallpapers downloaded!
            return
        }
        
        startDownload(asset: asset)
    }
    
    func downloadBatch(count: Int) {
        let undownloaded = getUndownloadedAssets()
        let toQueue = undownloaded.prefix(count)
        for item in toQueue where !queue.contains(item) {
            queue.append(item)
        }
        checkAndStartNextDownload()
    }
    
    func downloadAll() {
        let undownloaded = getUndownloadedAssets()
        for item in undownloaded where !queue.contains(item) {
            queue.append(item)
        }
        checkAndStartNextDownload()
    }
    
    func pauseDownload() {
        currentTask?.cancel()
        currentTask = nil
        currentAsset = nil
        isDownloading = false
        progress = 0.0
        queue.removeAll()
        notifyProgress()
    }
    
    private func startDownload(asset: CatalogAsset) {
        self.currentAsset = asset
        self.isDownloading = true
        self.progress = 0.0
        
        let task = session.downloadTask(with: asset.downloadURL)
        self.currentTask = task
        task.resume()
        notifyProgress()
    }
    
    private func notifyProgress() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .wallpaperDownloadProgress, object: nil)
        }
    }
    
    // MARK: - URLSessionDownloadDelegate
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        if totalBytesExpectedToWrite > 0 {
            self.progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
            notifyProgress()
        }
    }
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let asset = currentAsset else { return }
        
        let dest = videosDir.appendingPathComponent("\(asset.id).mov")
        
        // Remove if exists
        try? FileManager.default.removeItem(at: dest)
        
        do {
            try FileManager.default.moveItem(at: location, to: dest)
            print("Successfully downloaded official wallpaper: \(asset.name) (\(asset.id))")
        } catch {
            print("Failed to save wallpaper \(asset.name): \(error)")
        }
        
        self.currentAsset = nil
        self.currentTask = nil
        self.isDownloading = false
        self.progress = 0.0
        
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .wallpaperDownloadCompleted, object: nil)
            NotificationCenter.default.post(name: .wallpaperStateChanged, object: nil)
        }
        
        // Continue downloading next wallpaper after a brief 3 second delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            self?.checkAndStartNextDownload()
        }
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let err = error as NSError?, err.code != NSURLErrorCancelled {
            print("Wallpaper download error: \(err.localizedDescription)")
            self.isDownloading = false
            self.currentAsset = nil
            self.currentTask = nil
            self.progress = 0.0
            notifyProgress()
            
            // Retry next after 15 seconds if auto download is active
            if isAutoDownloadEnabled {
                DispatchQueue.main.asyncAfter(deadline: .now() + 15.0) { [weak self] in
                    self?.checkAndStartNextDownload()
                }
            }
        }
    }
}
