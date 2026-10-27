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
    
    private let manifestURL: URL
    private let videosDir: URL
    private let defaultsSuiteName: String?
    private var defaults: UserDefaults {
        defaultsSuiteName.flatMap { UserDefaults(suiteName: $0) } ?? .standard
    }
    
    private let keyAutoDownload = "AutoDownloadWallpapers"
    private let keyDeletedAssetIDs = "DeletedWallpaperAssetIDs"
    
    var deletedAssetIDs: Set<String> {
        get {
            let list = defaults.stringArray(forKey: keyDeletedAssetIDs) ?? []
            return Set(list)
        }
        set {
            defaults.set(Array(newValue), forKey: keyDeletedAssetIDs)
        }
    }
    
    func markAsDeleted(assetID: String) {
        var set = deletedAssetIDs
        set.insert(assetID)
        deletedAssetIDs = set
        if currentAsset?.id == assetID {
            pauseDownload()
        }
    }
    
    func unmarkDeleted(assetID: String) {
        var set = deletedAssetIDs
        set.remove(assetID)
        deletedAssetIDs = set
    }
    
    private var session: URLSession!
    private var currentTask: URLSessionDownloadTask?
    private(set) var currentAsset: CatalogAsset?
    private(set) var progress: Double = 0.0 // 0.0 to 1.0
    private(set) var isDownloading: Bool = false
    
    private var lastReportedPercent: Int = -1
    private var lastReportTime: Date = .distantPast
    
    private var queue: [CatalogAsset] = []
    private var scheduleGeneration = 0
    
    var isAutoDownloadEnabled: Bool {
        get {
            if defaults.object(forKey: keyAutoDownload) == nil {
                return true // Enabled by default as requested
            }
            return defaults.bool(forKey: keyAutoDownload)
        }
        set {
            defaults.set(newValue, forKey: keyAutoDownload)
            if newValue {
                checkAndStartNextDownload()
            } else {
                pauseDownload()
            }
            notifyProgress(force: true)
        }
    }
    
    override convenience init() {
        self.init(
            manifestURL: URL(fileURLWithPath: NSString(string: "~/Library/Application Support/com.apple.wallpaper/aerials/manifest/entries.json").expandingTildeInPath),
            videosDir: URL(fileURLWithPath: NSString(string: "~/Library/Application Support/com.apple.wallpaper/aerials/videos").expandingTildeInPath),
            defaultsSuiteName: nil
        )
    }

    init(manifestURL: URL, videosDir: URL, defaultsSuiteName: String?) {
        self.manifestURL = manifestURL
        self.videosDir = videosDir
        self.defaultsSuiteName = defaultsSuiteName
        super.init()
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 1200
        self.session = URLSession(configuration: config, delegate: self, delegateQueue: OperationQueue.main)
        
        try? FileManager.default.createDirectory(at: videosDir, withIntermediateDirectories: true)
        
        if isAutoDownloadEnabled {
            let generation = scheduleGeneration
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
                guard let self = self, self.scheduleGeneration == generation else { return }
                self.checkAndStartNextDownload()
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
        
        let downloadedIDs = Set(existingFiles.filter { $0.pathExtension.lowercased() == "mov" }
            .map { $0.deletingPathExtension().lastPathComponent })
        let deleted = deletedAssetIDs
        return catalog.filter { !downloadedIDs.contains($0.id) && !deleted.contains($0.id) }
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
    
    private func getFreeDiskSpace() -> Int64 {
        if let attrs = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory()),
           let freeSpace = attrs[.systemFreeSize] as? NSNumber {
            return freeSpace.int64Value
        }
        return 0
    }
    
    func checkAndStartNextDownload() {
        guard isAutoDownloadEnabled || !queue.isEmpty else { return }
        guard !isDownloading else { return }
        
        // Safeguard: Ensure at least 3GB free disk space before downloading 4K videos
        if getFreeDiskSpace() < 3 * 1024 * 1024 * 1024 {
            print("Disk space low (< 3GB), skipping auto download to protect system storage.")
            return
        }
        
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
            return
        }
        
        startDownload(asset: asset)
    }
    
    func downloadBatch(count: Int) {
        let undownloaded = getUndownloadedAssets()
        let toQueue = undownloaded.filter { $0.id != currentAsset?.id && !queue.contains($0) }.prefix(max(0, count))
        for item in toQueue {
            queue.append(item)
        }
        checkAndStartNextDownload()
    }
    
    func downloadAll() {
        let undownloaded = getUndownloadedAssets()
        for item in undownloaded where item.id != currentAsset?.id && !queue.contains(item) {
            queue.append(item)
        }
        checkAndStartNextDownload()
    }
    
    func pauseDownload() {
        scheduleGeneration += 1
        currentTask?.cancel()
        currentTask = nil
        currentAsset = nil
        isDownloading = false
        progress = 0.0
        queue.removeAll()
        notifyProgress(force: true)
    }
    
    private func startDownload(asset: CatalogAsset) {
        self.currentAsset = asset
        self.isDownloading = true
        self.progress = 0.0
        self.lastReportedPercent = -1
        
        let task = session.downloadTask(with: asset.downloadURL)
        self.currentTask = task
        task.resume()
        notifyProgress(force: true)
    }
    
    private func notifyProgress(force: Bool = false) {
        let currentPct = Int(progress * 100)
        let now = Date()
        
        if force || (currentPct != lastReportedPercent && now.timeIntervalSince(lastReportTime) >= 1.5) {
            lastReportedPercent = currentPct
            lastReportTime = now
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .wallpaperDownloadProgress, object: nil)
            }
        }
    }
    
    // All download state and delegate callbacks are confined to the main queue.
    // A cancelled task may still deliver callbacks after another task has started.
    private func isCurrent(_ task: URLSessionTask) -> Bool {
        return currentTask === task
    }

    private func finishCurrentDownload(success: Bool) {
        currentAsset = nil
        currentTask = nil
        isDownloading = false
        progress = 0.0
        notifyProgress(force: true)

        if success {
            NotificationCenter.default.post(name: .wallpaperDownloadCompleted, object: nil)
        }

        let generation = scheduleGeneration
        let delay = success ? 3.0 : 15.0
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self = self, self.scheduleGeneration == generation else { return }
            self.checkAndStartNextDownload()
        }
    }

    // MARK: - URLSessionDownloadDelegate

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard isCurrent(downloadTask), totalBytesExpectedToWrite > 0 else { return }
        progress = min(1.0, max(0.0, Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)))
        notifyProgress()
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard isCurrent(downloadTask), let asset = currentAsset else { return }

        guard let response = downloadTask.response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else {
            print("Wallpaper download failed: unexpected HTTP response for \(asset.name)")
            finishCurrentDownload(success: false)
            return
        }

        let dest = videosDir.appendingPathComponent("\(asset.id).mov")
        do {
            // Never delete an existing system wallpaper: another process may have
            // downloaded it while this task was running.
            if !FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.moveItem(at: location, to: dest)
            }
            print("Successfully downloaded official wallpaper: \(asset.name) (\(asset.id))")
            finishCurrentDownload(success: true)
        } catch {
            print("Failed to save wallpaper \(asset.name): \(error)")
            finishCurrentDownload(success: false)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard isCurrent(task), let error = error else { return }
        print("Wallpaper download error: \(error.localizedDescription)")
        finishCurrentDownload(success: false)
    }
}
