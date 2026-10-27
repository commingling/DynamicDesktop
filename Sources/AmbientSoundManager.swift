import Cocoa
import AVFoundation

enum AmbientSoundType: String, CaseIterable, Identifiable {
    case auto = "auto"
    case ocean = "Ocean.m4a"
    case rain = "Rain.m4a"
    case stream = "Stream.m4a"
    case fire = "Fire.m4a"
    case night = "Night.m4a"
    case quietNight = "QuietNight.m4a"
    case wind = "BrownNoise.m4a"
    case whiteNoise = "WhiteNoise.m4a"
    case boat = "Boat.m4a"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .auto: return "🎯 智能匹配当前壁纸 (推荐)"
        case .ocean: return "🌊 浪涌海滩 (Ocean)"
        case .rain: return "🌧️ 淅沥细雨 (Rain)"
        case .stream: return "🏞️ 山涧溪流 (Stream)"
        case .fire: return "🔥 温暖篝火 (Fire)"
        case .night: return "🦗 静谧夏夜 (Night)"
        case .quietNight: return "🌙 幽静夜晚 (Quiet Night)"
        case .wind: return "💨 旷野自然风 (Natural Wind)"
        case .whiteNoise: return "🤫 专注白噪音 (White Noise)"
        case .boat: return "🛶 泛舟水声 (Boat)"
        }
    }
}

class AmbientSoundManager: NSObject {
    static let shared = AmbientSoundManager()
    
    private let soundDir = "/System/Library/PrivateFrameworks/HearingUtilities.framework/Versions/A/Resources"
    
    private let keyEnabled = "AmbientSoundEnabled"
    private let keyVolume = "AmbientSoundVolume"
    private let keySoundType = "AmbientSoundType"
    
    private var audioPlayer: AVAudioPlayer?
    private var currentPlayingFile: String?
    
    var isEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: keyEnabled) == nil {
                return true // Enabled by default as requested!
            }
            return UserDefaults.standard.bool(forKey: keyEnabled)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: keyEnabled)
            if newValue {
                play()
            } else {
                pause()
            }
            notifyChange()
        }
    }
    
    var volume: Float {
        get {
            if UserDefaults.standard.object(forKey: keyVolume) == nil {
                return 0.25 // Default 25%: comfortable and soothing
            }
            return UserDefaults.standard.float(forKey: keyVolume)
        }
        set {
            let clamped = max(0.0, min(1.0, newValue))
            UserDefaults.standard.set(clamped, forKey: keyVolume)
            audioPlayer?.volume = clamped
            notifyChange()
        }
    }
    
    var selectedType: AmbientSoundType {
        get {
            if let saved = UserDefaults.standard.string(forKey: keySoundType),
               let type = AmbientSoundType(rawValue: saved) {
                return type
            }
            return .auto
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: keySoundType)
            updateForWallpaper(WallpaperEngine.shared.currentWallpaper)
            notifyChange()
        }
    }
    
    override init() {
        super.init()
    }
    
    /// Matches the best Apple ambient sound based on wallpaper name and category
    func matchSound(for wallpaper: WallpaperAsset?) -> String {
        guard let name = wallpaper?.name.lowercased() else {
            return "Stream.m4a"
        }
        
        if name.contains("beach") || name.contains("coast") || name.contains("sea") ||
           name.contains("ocean") || name.contains("underwater") || name.contains("shark") ||
           name.contains("coral") || name.contains("reef") || name.contains("dubai") ||
           name.contains("goa") || name.contains("hawaii") || name.contains("marshalls") ||
           name.contains("bay") {
            return "Ocean.m4a"
        } else if name.contains("rain") || name.contains("storm") || name.contains("cloud") || name.contains("fog") {
            return "Rain.m4a"
        } else if name.contains("river") || name.contains("stream") || name.contains("lake") ||
                  name.contains("waterfall") || name.contains("yosemite") || name.contains("iceland") {
            return "Stream.m4a"
        } else if name.contains("sunset") || name.contains("sunrise") || name.contains("fire") ||
                  name.contains("sequoia") || name.contains("golden gate sun") {
            return "Fire.m4a"
        } else if name.contains("night") || name.contains("dark") || name.contains("moon") ||
                  name.contains("city") || name.contains("stars") {
            return "Night.m4a"
        } else if name.contains("desert") || name.contains("canyon") || name.contains("grand canyon") ||
                  name.contains("dune") || name.contains("space") || name.contains("earth") {
            return "BrownNoise.m4a"
        }
        
        return "Stream.m4a"
    }
    
    func getCurrentSoundName() -> String {
        if selectedType == .auto {
            let matchedFile = matchSound(for: WallpaperEngine.shared.currentWallpaper)
            let matchedType = AmbientSoundType(rawValue: matchedFile) ?? .stream
            return "\(matchedType.displayName) (智能匹配)"
        } else {
            return selectedType.displayName
        }
    }
    
    /// Updates playback when wallpaper changes
    func updateForWallpaper(_ wallpaper: WallpaperAsset?) {
        guard isEnabled && WallpaperEngine.shared.isAnyScreenAnimating() else {
            pause()
            return
        }
        
        let targetFile: String
        if selectedType == .auto {
            targetFile = matchSound(for: wallpaper)
        } else {
            targetFile = selectedType.rawValue
        }
        
        if targetFile == currentPlayingFile && audioPlayer != nil && audioPlayer?.isPlaying == true {
            return // Already playing correct file
        }
        
        switchAudioFile(targetFile)
    }
    
    func play() {
        guard isEnabled && WallpaperEngine.shared.isAnyScreenAnimating() else { return }
        
        let targetFile: String
        if selectedType == .auto {
            targetFile = matchSound(for: WallpaperEngine.shared.currentWallpaper)
        } else {
            targetFile = selectedType.rawValue
        }
        
        if audioPlayer != nil && currentPlayingFile == targetFile {
            audioPlayer?.play()
        } else {
            switchAudioFile(targetFile)
        }
    }
    
    func pause() {
        audioPlayer?.pause()
    }
    
    private func switchAudioFile(_ filename: String) {
        let filePath = (soundDir as NSString).appendingPathComponent(filename)
        let fileURL = URL(fileURLWithPath: filePath)
        
        guard FileManager.default.fileExists(atPath: filePath) else {
            print("Ambient sound file not found at: \(filePath)")
            return
        }
        
        do {
            let player = try AVAudioPlayer(contentsOf: fileURL)
            player.numberOfLoops = -1 // Infinite loop
            player.volume = self.volume
            player.prepareToPlay()
            
            // Crossfade
            self.audioPlayer?.stop()
            self.audioPlayer = player
            self.currentPlayingFile = filename
            player.play()
        } catch {
            print("Failed to initialize ambient sound player: \(error)")
        }
    }
    
    private func notifyChange() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .wallpaperStateChanged, object: nil)
        }
    }
}
