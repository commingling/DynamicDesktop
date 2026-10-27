import Foundation

struct WallpaperAsset: Identifiable, Equatable {
    let id: String
    let name: String
    let chineseName: String?
    let englishName: String?
    let url: URL
    
    init(id: String, name: String, chineseName: String? = nil, englishName: String? = nil, url: URL) {
        self.id = id
        self.name = name
        self.chineseName = chineseName
        self.englishName = englishName
        self.url = url
    }
    
    var fileSize: Int64 {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attrs?[.size] as? Int64) ?? 0
    }
    
    var formattedFileSize: String {
        let bytes = fileSize
        guard bytes > 0 else { return "" }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
    
    static func == (lhs: WallpaperAsset, rhs: WallpaperAsset) -> Bool {
        return lhs.id == rhs.id
    }
}

struct WallpaperNameInfo {
    let display: String
    let chinese: String?
    let english: String?
}

class WallpaperDetector {
    static let shared = WallpaperDetector()
    
    let videosDir = URL(fileURLWithPath: NSString(string: "~/Library/Application Support/com.apple.wallpaper/aerials/videos").expandingTildeInPath)
    private let manifestFile = URL(fileURLWithPath: NSString(string: "~/Library/Application Support/com.apple.wallpaper/aerials/manifest/entries.json").expandingTildeInPath)
    private let loctableFile = URL(fileURLWithPath: NSString(string: "~/Library/Application Support/com.apple.wallpaper/aerials/manifest/TVIdleScreenStrings.bundle/Contents/Resources/Localizable.nocache.loctable").expandingTildeInPath)
    private let indexPlist = URL(fileURLWithPath: NSString(string: "~/Library/Application Support/com.apple.wallpaper/Store/Index.plist").expandingTildeInPath)
    
    private init() {
        WallpaperDownloader.shared.nameResolver = { [weak self] id in
            self?.getNamesMap()[id]?.display
        }
    }
    
    private var cachedLocalization: [String: String]?
    
    /// Loads Apple's official localized strings table (.loctable plist)
    func getLocalizedStrings() -> [String: String] {
        if let cached = cachedLocalization { return cached }
        
        guard let data = try? Data(contentsOf: loctableFile),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else {
            return [:]
        }
        
        let preferred = Locale.preferredLanguages
        let isTrad = preferred.contains { $0.hasPrefix("zh-Hant") || $0.hasPrefix("zh-TW") || $0.hasPrefix("zh-HK") }
        
        var dict: [String: String] = [:]
        if isTrad {
            if let zhTW = plist["zh_TW"] as? [String: String] { dict = zhTW }
            else if let zhHK = plist["zh_HK"] as? [String: String] { dict = zhHK }
            else if let zhCN = plist["zh_CN"] as? [String: String] { dict = zhCN }
        } else {
            if let zhCN = plist["zh_CN"] as? [String: String] { dict = zhCN }
            else if let zhTW = plist["zh_TW"] as? [String: String] { dict = zhTW }
        }
        
        cachedLocalization = dict
        return dict
    }
    
    func getActiveAssetID() -> String? {
        guard let data = try? Data(contentsOf: indexPlist),
              let obj = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
              let all = obj["AllSpacesAndDisplays"] as? [String: Any],
              let desktop = all["Desktop"] as? [String: Any],
              let content = desktop["Content"] as? [String: Any],
              let choices = content["Choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let configData = firstChoice["Configuration"] as? Data,
              let configPlist = try? PropertyListSerialization.propertyList(from: configData, options: [], format: nil) as? [String: Any],
              let assetID = configPlist["assetID"] as? String else {
            return nil
        }
        return assetID
    }
    
    /// Builds a dictionary of wallpaper ID to localized names (Chinese prioritized, paired with English)
    func getNamesMap() -> [String: WallpaperNameInfo] {
        var namesMap: [String: WallpaperNameInfo] = [:]
        let locDict = getLocalizedStrings()
        
        guard let manifestData = try? Data(contentsOf: manifestFile),
              let json = try? JSONSerialization.jsonObject(with: manifestData) as? [String: Any],
              let assets = json["assets"] as? [[String: Any]] else {
            return [:]
        }
        
        for asset in assets {
            guard let id = asset["id"] as? String else { continue }
            let locKey = asset["localizedNameKey"] as? String
            let shotID = asset["shotID"] as? String
            let accLabel = asset["accessibilityLabel"] as? String
            
            // 1. Look up official Chinese name from Apple's loctable
            var zhName: String?
            if let key = locKey, let val = locDict[key] {
                zhName = val
            } else if let shot = shotID, let val = locDict["\(shot)_NAME"] {
                zhName = val
            } else if let shot = shotID, let val = locDict[shot] {
                zhName = val
            }
            
            // Refine generic light/dark names
            if zhName == "浅色" || zhName == "深色" {
                zhName = "macOS 索诺玛 (\(zhName!))"
            }
            
            // 2. Clean English name (filter out camera sensor codes with underscores)
            let rawEn = accLabel?.trimmingCharacters(in: .whitespacesAndNewlines)
            let isCode = (rawEn?.contains("_") == true) || (rawEn?.count ?? 0) < 2
            let cleanEn = (isCode ? nil : rawEn)
            
            // 3. Compose display name: "中文名称 (English Name)"
            let displayName: String
            if let zh = zhName, !zh.isEmpty {
                if let en = cleanEn, !en.isEmpty, en.lowercased() != zh.lowercased(), !zh.contains(en) {
                    displayName = "\(zh) (\(en))"
                } else {
                    displayName = zh
                }
            } else if let en = cleanEn, !en.isEmpty {
                displayName = en
            } else {
                displayName = "原生动态壁纸 (\(id.prefix(6)))"
            }
            
            namesMap[id] = WallpaperNameInfo(display: displayName, chinese: zhName, english: cleanEn)
        }
        
        return namesMap
    }
    
    func getAllWallpapers() -> [WallpaperAsset] {
        let namesMap = getNamesMap()
        guard let files = try? FileManager.default.contentsOfDirectory(at: videosDir, includingPropertiesForKeys: [.fileSizeKey]) else {
            return []
        }
        
        var results: [WallpaperAsset] = []
        for file in files where file.pathExtension.lowercased() == "mov" {
            let assetID = file.deletingPathExtension().lastPathComponent
            let info = namesMap[assetID]
            let name = info?.display ?? "原生动态壁纸 (\(assetID.prefix(6)))"
            results.append(WallpaperAsset(
                id: assetID,
                name: name,
                chineseName: info?.chinese,
                englishName: info?.english,
                url: file
            ))
        }
        
        // Sort so the active one is first, then alphabetical
        let activeID = getActiveAssetID()
        return results.sorted { a, b in
            let aIsActive = a.id == activeID
            let bIsActive = b.id == activeID
            if aIsActive != bIsActive { return aIsActive }
            if a.name != b.name { return a.name.localizedStandardCompare(b.name) == .orderedAscending }
            return a.id < b.id
        }
    }
    
    func getTotalWallpapersSize() -> String {
        let all = getAllWallpapers()
        let totalBytes = all.reduce(Int64(0)) { $0 + $1.fileSize }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: totalBytes)
    }
    
    func getActiveWallpaper() -> WallpaperAsset? {
        let all = getAllWallpapers()
        if let activeID = getActiveAssetID(), let found = all.first(where: { $0.id == activeID }) {
            return found
        }
        return all.first
    }
    
    /// Moves a wallpaper video file to the system Trash (or deletes it permanently if Trash is unavailable)
    func deleteWallpaperFile(_ asset: WallpaperAsset) -> Result<Void, Error> {
        do {
            var trashURL: NSURL?
            try FileManager.default.trashItem(at: asset.url, resultingItemURL: &trashURL)
            return .success(())
        } catch {
            do {
                try FileManager.default.removeItem(at: asset.url)
                return .success(())
            } catch let err {
                return .failure(err)
            }
        }
    }
}
