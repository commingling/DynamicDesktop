import Cocoa
import AVFoundation

enum AmbientSoundType: String, CaseIterable, Identifiable {
    case auto = "auto"
    case ocean = "Ocean.m4a"
    case boat = "Boat.m4a"
    case stream = "Stream.m4a"
    case rain = "Rain.m4a"
    case rainOnRoof = "RainOnRoof.m4a"
    case quietNight = "QuietNight.m4a"
    case night = "Night.m4a"
    case fire = "Fire.m4a"
    case pinkNoise = "PinkNoise.m4a"
    case wind = "BrownNoise.m4a"
    case whiteNoise = "WhiteNoise.m4a"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .auto: return "🎯 智能匹配当前壁纸 (推荐)"
        case .ocean: return "🌊 浪涌海滩 (Ocean)"
        case .boat: return "🛶 泛舟轻波 (Boat - 极柔和推荐)"
        case .stream: return "🏞️ 山涧溪流 (Stream)"
        case .rain: return "🌧️ 淅沥细雨 (Rain)"
        case .rainOnRoof: return "🏠 雨打屋檐 (Rain on Roof)"
        case .quietNight: return "🌙 幽静夜晚 (Quiet Night)"
        case .night: return "🦗 静谧夏夜 (Night)"
        case .fire: return "🔥 温暖篝火 (Fire)"
        case .pinkNoise: return "🌸 柔和粉红噪 (Pink Noise - 舒缓降噪)"
        case .wind: return "💨 旷野自然风 (Natural Wind)"
        case .whiteNoise: return "🤫 专注白噪音 (White Noise)"
        }
    }
}

class AmbientSoundManager: NSObject {
    static let shared = AmbientSoundManager()
    
    private let soundDir = "/System/Library/PrivateFrameworks/HearingUtilities.framework/Versions/A/Resources"
    
    private let keyEnabled = "AmbientSoundEnabled"
    private let keyVolume = "AmbientSoundVolume"
    private let keySoundType = "AmbientSoundType"
    private let keyWarmFilter = "AmbientSoundWarmFilter"
    
    private var activePlayer: AVAudioPlayer?
    private var fadingPlayer: AVAudioPlayer?
    private var currentPlayingFile: String?
    
    private var audioCache: [String: Data] = [:]
    private let processQueue = DispatchQueue(label: "com.liuming.dynamicdesktop.audioprocessor", qos: .userInitiated)
    private var currentFileRequestToken = UUID()
    
    var isEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: keyEnabled) == nil {
                return true
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
    
    /// Warm Filter (耳机柔和降噪 / 暖音模式): Eliminates high-frequency treble hiss and Bluetooth static/crackling
    var isWarmFilterEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: keyWarmFilter) == nil {
                return true // Enabled by default to protect earphone users!
            }
            return UserDefaults.standard.bool(forKey: keyWarmFilter)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: keyWarmFilter)
            reloadCurrentSound()
            notifyChange()
        }
    }
    
    var volume: Float {
        get {
            if UserDefaults.standard.object(forKey: keyVolume) == nil {
                return 0.15 // Default 15%: comfortable and soothing for earphones
            }
            return UserDefaults.standard.float(forKey: keyVolume)
        }
        set {
            let clamped = max(0.0, min(1.0, newValue))
            UserDefaults.standard.set(clamped, forKey: keyVolume)
            if let player = activePlayer, player.isPlaying {
                player.setVolume(clamped, fadeDuration: 0.2)
            }
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
            return "Boat.m4a"
        }
        
        if name.contains("beach") || name.contains("coast") || name.contains("sea") ||
           name.contains("ocean") || name.contains("underwater") || name.contains("shark") ||
           name.contains("coral") || name.contains("reef") || name.contains("dubai") ||
           name.contains("goa") || name.contains("hawaii") || name.contains("marshalls") ||
           name.contains("bay") {
            return "Ocean.m4a"
        } else if name.contains("rain") || name.contains("storm") || name.contains("cloud") || name.contains("fog") {
            return "RainOnRoof.m4a"
        } else if name.contains("river") || name.contains("stream") || name.contains("lake") ||
                  name.contains("waterfall") || name.contains("yosemite") || name.contains("iceland") {
            return "Stream.m4a"
        } else if name.contains("sunset") || name.contains("sunrise") || name.contains("fire") ||
                  name.contains("sequoia") || name.contains("golden gate sun") {
            return "Fire.m4a"
        } else if name.contains("night") || name.contains("dark") || name.contains("moon") ||
                  name.contains("city") || name.contains("stars") {
            return "QuietNight.m4a"
        } else if name.contains("desert") || name.contains("canyon") || name.contains("grand canyon") ||
                  name.contains("dune") || name.contains("space") || name.contains("earth") {
            return "BrownNoise.m4a"
        }
        
        return "Boat.m4a"
    }
    
    func getCurrentSoundName() -> String {
        let warmTag = isWarmFilterEnabled ? " [耳机柔和]" : ""
        if selectedType == .auto {
            let matchedFile = matchSound(for: WallpaperEngine.shared.currentWallpaper)
            let matchedType = AmbientSoundType(rawValue: matchedFile) ?? .boat
            return "\(matchedType.displayName) (智能匹配)\(warmTag)"
        } else {
            return "\(selectedType.displayName)\(warmTag)"
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
        
        if targetFile == currentPlayingFile && activePlayer != nil && activePlayer?.isPlaying == true {
            return
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
        
        if let player = activePlayer, currentPlayingFile == targetFile {
            if !player.isPlaying {
                player.volume = 0.0
                player.play()
                player.setVolume(self.volume, fadeDuration: 0.35)
            }
        } else {
            switchAudioFile(targetFile)
        }
    }
    
    func pause() {
        guard let player = activePlayer, player.isPlaying else { return }
        player.setVolume(0.0, fadeDuration: 0.25)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self = self else { return }
            if !WallpaperEngine.shared.isAnyScreenAnimating() || !self.isEnabled {
                self.activePlayer?.pause()
            }
        }
    }
    
    private func reloadCurrentSound() {
        guard let currentFile = currentPlayingFile else { return }
        switchAudioFile(currentFile, forceReload: true)
    }
    
    private func switchAudioFile(_ filename: String, forceReload: Bool = false) {
        if !forceReload && filename == currentPlayingFile && activePlayer != nil && activePlayer?.isPlaying == true {
            return
        }
        
        let filePath = (soundDir as NSString).appendingPathComponent(filename)
        guard FileManager.default.fileExists(atPath: filePath) else {
            print("Ambient sound file not found at: \(filePath)")
            return
        }
        
        currentPlayingFile = filename
        let requestToken = UUID()
        self.currentFileRequestToken = requestToken
        let warm = self.isWarmFilterEnabled
        let cacheKey = "\(filename)_\(warm ? "warm" : "raw")"
        
        if let cachedData = audioCache[cacheKey] {
            playWAVData(cachedData, filename: filename, token: requestToken)
            return
        }
        
        let fileURL = URL(fileURLWithPath: filePath)
        processQueue.async { [weak self] in
            guard let self = self else { return }
            let wavData = Self.processAudioFile(fileURL: fileURL, warmFilter: warm)
            DispatchQueue.main.async {
                guard self.currentFileRequestToken == requestToken else { return }
                if let data = wavData {
                    self.audioCache[cacheKey] = data
                    self.playWAVData(data, filename: filename, token: requestToken)
                }
            }
        }
    }
    
    private func playWAVData(_ data: Data, filename: String, token: UUID) {
        guard self.currentFileRequestToken == token else { return }
        guard self.isEnabled && WallpaperEngine.shared.isAnyScreenAnimating() else { return }
        
        do {
            let newPlayer = try AVAudioPlayer(data: data)
            newPlayer.numberOfLoops = -1
            newPlayer.prepareToPlay()
            newPlayer.volume = 0.0
            newPlayer.play()
            newPlayer.setVolume(self.volume, fadeDuration: 0.4)
            
            // Fade out previous player smoothly to eliminate any click
            if let oldPlayer = self.activePlayer {
                self.fadingPlayer = oldPlayer
                oldPlayer.setVolume(0.0, fadeDuration: 0.35)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                    oldPlayer.stop()
                    if self?.fadingPlayer === oldPlayer {
                        self?.fadingPlayer = nil
                    }
                }
            }
            
            self.activePlayer = newPlayer
            self.currentPlayingFile = filename
        } catch {
            print("Failed to initialize seamless audio player: \(error)")
        }
    }
    
    /// Transforms the raw AAC audio file into a 100% seamless circular PCM loop
    /// with an equal-power crossfade and an optional earphone-friendly 2nd-order Butterworth lowpass filter.
    private static func processAudioFile(fileURL: URL, warmFilter: Bool) -> Data? {
        guard let file = try? AVAudioFile(forReading: fileURL),
              let srcBuffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)),
              (try? file.read(into: srcBuffer)) != nil,
              let srcData = srcBuffer.floatChannelData else {
            return nil
        }
        
        let sampleRate = file.processingFormat.sampleRate
        let channelCount = Int(file.processingFormat.channelCount)
        let L = Int(srcBuffer.frameLength)
        guard L > 1000, channelCount >= 1 else { return nil }
        
        // 1.5 seconds crossfade (or up to 20% of duration if short)
        let crossfadeSec = min(1.5, Double(L) / sampleRate * 0.2)
        let crossfadeFrames = max(100, Int(crossfadeSec * sampleRate))
        let M = L - crossfadeFrames
        guard M > crossfadeFrames else { return nil }
        
        // Butterworth 2nd-order Low-Pass Filter (Cutoff: 5000 Hz, Q: 0.7071)
        // Cuts ear-piercing wave foam treble and Bluetooth compression frizz
        let cutoff: Float = 5000.0
        let w0 = 2.0 * Float.pi * min(cutoff, Float(sampleRate) * 0.45) / Float(sampleRate)
        let cosw0 = cos(w0)
        let alpha = sin(w0) / (2.0 * 0.70710678)
        let b0 = (1.0 - cosw0) / 2.0
        let b1 = 1.0 - cosw0
        let b2 = (1.0 - cosw0) / 2.0
        let a0 = 1.0 + alpha
        let a1 = -2.0 * cosw0
        let a2 = 1.0 - alpha
        
        let cb0 = b0 / a0
        let cb1 = b1 / a0
        let cb2 = b2 / a0
        let ca1 = a1 / a0
        let ca2 = a2 / a0
        
        // Process each channel
        var channelBuffers: [[Float]] = []
        for ch in 0..<channelCount {
            var chBuf = [Float](repeating: 0, count: M)
            let src = srcData[ch]
            
            // 1. Equal-power sinusoidal crossfade: transitions smoothly from tail to head
            for i in 0..<crossfadeFrames {
                let w = Double(i) / Double(crossfadeFrames)
                let gainHead = Float(sin(w * .pi / 2.0))
                let gainTail = Float(cos(w * .pi / 2.0))
                chBuf[i] = src[i] * gainHead + src[M + i] * gainTail
            }
            
            // 2. Loop body
            for i in crossfadeFrames..<M {
                chBuf[i] = src[i]
            }
            
            // 3. Gentle Warm Filter
            if warmFilter {
                var x1: Float = 0, x2: Float = 0
                var y1: Float = 0, y2: Float = 0
                
                // Warm up filter state using the loop's tail for perfect steady-state continuity
                let warmupCount = min(1000, M)
                for i in (M - warmupCount)..<M {
                    let x = chBuf[i]
                    let y = cb0 * x + cb1 * x1 + cb2 * x2 - ca1 * y1 - ca2 * y2
                    x2 = x1; x1 = x; y2 = y1; y1 = y
                }
                
                // Filter the entire loop
                for i in 0..<M {
                    let x = chBuf[i]
                    let y = cb0 * x + cb1 * x1 + cb2 * x2 - ca1 * y1 - ca2 * y2
                    x2 = x1; x1 = x; y2 = y1; y1 = y
                    chBuf[i] = y
                }
            }
            
            channelBuffers.append(chBuf)
        }
        
        // Construct standard 16-bit PCM WAV
        let bytesPerSample = 2
        let byteRate = Int(sampleRate) * channelCount * bytesPerSample
        let blockAlign = channelCount * bytesPerSample
        let dataSize = M * blockAlign
        let totalSize = 44 + dataSize
        
        var data = Data(capacity: totalSize)
        data.append(contentsOf: [UInt8]("RIFF".utf8))
        var chunkSize = UInt32(totalSize - 8).littleEndian
        data.append(Data(bytes: &chunkSize, count: 4))
        data.append(contentsOf: [UInt8]("WAVEfmt ".utf8))
        var subchunk1Size = UInt32(16).littleEndian
        data.append(Data(bytes: &subchunk1Size, count: 4))
        var audioFormat = UInt16(1).littleEndian
        data.append(Data(bytes: &audioFormat, count: 2))
        var numChannels = UInt16(channelCount).littleEndian
        data.append(Data(bytes: &numChannels, count: 2))
        var sRate = UInt32(sampleRate).littleEndian
        data.append(Data(bytes: &sRate, count: 4))
        var bRate = UInt32(byteRate).littleEndian
        data.append(Data(bytes: &bRate, count: 4))
        var bAlign = UInt16(blockAlign).littleEndian
        data.append(Data(bytes: &bAlign, count: 2))
        var bitsPerSample = UInt16(16).littleEndian
        data.append(Data(bytes: &bitsPerSample, count: 2))
        data.append(contentsOf: [UInt8]("data".utf8))
        var dSize = UInt32(dataSize).littleEndian
        data.append(Data(bytes: &dSize, count: 4))
        
        var pcmBytes = [UInt8](repeating: 0, count: dataSize)
        pcmBytes.withUnsafeMutableBytes { rawBuf in
            let int16Ptr = rawBuf.bindMemory(to: Int16.self)
            var idx = 0
            for i in 0..<M {
                for ch in 0..<channelCount {
                    let floatSample = channelBuffers[ch][i]
                    let clamped = max(-1.0, min(1.0, floatSample))
                    int16Ptr[idx] = Int16(clamped * 32767.0).littleEndian
                    idx += 1
                }
            }
        }
        data.append(contentsOf: pcmBytes)
        
        return data
    }
    
    private func notifyChange() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .wallpaperStateChanged, object: nil)
        }
    }
}
