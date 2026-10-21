import Foundation

struct WallpaperAsset: Identifiable, Equatable {
    let id: String
    let name: String
    let url: URL
    
    static func == (lhs: WallpaperAsset, rhs: WallpaperAsset) -> Bool {
        return lhs.id == rhs.id
    }
}

class WallpaperDetector {
    static let shared = WallpaperDetector()
    
    private let videosDir = URL(fileURLWithPath: NSString(string: "~/Library/Application Support/com.apple.wallpaper/aerials/videos").expandingTildeInPath)
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
        guard let files = try? FileManager.default.contentsOfDirectory(at: videosDir, includingPropertiesForKeys: nil) else {
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
            if a.id == activeID { return true }
            if b.id == activeID { return false }
            return a.name < b.name
        }
    }
    
    func getActiveWallpaper() -> WallpaperAsset? {
        let all = getAllWallpapers()
        if let activeID = getActiveAssetID(), let found = all.first(where: { $0.id == activeID }) {
            return found
        }
        return all.first
    }
}
