import Foundation

struct WallpaperAsset: Identifiable, Equatable {
    let id: String
    let name: String
    let url: URL
    
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

class WallpaperDetector {
    static let shared = WallpaperDetector()
    
    let videosDir = URL(fileURLWithPath: NSString(string: "~/Library/Application Support/com.apple.wallpaper/aerials/videos").expandingTildeInPath)
    private let manifestFile = URL(fileURLWithPath: NSString(string: "~/Library/Application Support/com.apple.wallpaper/aerials/manifest/entries.json").expandingTildeInPath)
    private let indexPlist = URL(fileURLWithPath: NSString(string: "~/Library/Application Support/com.apple.wallpaper/Store/Index.plist").expandingTildeInPath)
    
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
    
    func getNamesMap() -> [String: String] {
        var namesMap: [String: String] = [:]
        if let manifestData = try? Data(contentsOf: manifestFile),
           let json = try? JSONSerialization.jsonObject(with: manifestData) as? [String: Any],
           let assets = json["assets"] as? [[String: Any]] {
            for asset in assets {
                if let id = asset["id"] as? String, let name = asset["accessibilityLabel"] as? String {
                    namesMap[id] = name
                }
            }
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
            let name = namesMap[assetID] ?? "原生动态壁纸 (\(assetID.prefix(6)))"
            results.append(WallpaperAsset(id: assetID, name: name, url: file))
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
