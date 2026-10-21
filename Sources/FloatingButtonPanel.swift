import Cocoa

class FloatingButtonPanel: NSPanel {
    private var targetScreenIndex: Int = 0
    private var actionButton: NSButton!
    private var screenSelectButton: NSPopUpButton!
    private var statusDot: NSTextField!
    
    init() {
        let panelRect = NSRect(x: 100, y: 100, width: 260, height: 46)
        
        super.init(
            contentRect: panelRect,
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        
        self.level = .floating
        self.collectionBehavior = [.canJoinAllSpaces, .stationary]
        self.isMovableByWindowBackground = true
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = true
        
        setupViews()
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(onWallpaperStateChanged),
            name: .wallpaperStateChanged,
            object: nil
        )
        
        // Position on the main screen top-right or center
        if let mainScreen = NSScreen.main {
            let x = mainScreen.visibleFrame.maxX - 280
            let y = mainScreen.visibleFrame.maxY - 70
            self.setFrameOrigin(NSPoint(x: x, y: y))
        }
        
        updateUI()
    }
    
    private func setupViews() {
        let visualEffect = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 260, height: 46))
        visualEffect.material = .hudWindow
        visualEffect.blendingMode = .behindWindow
        visualEffect.state = .active
        visualEffect.wantsLayer = true
        visualEffect.layer?.cornerRadius = 23
        visualEffect.layer?.masksToBounds = true
        visualEffect.layer?.borderWidth = 1.0
        visualEffect.layer?.borderColor = NSColor.white.withAlphaComponent(0.25).cgColor
        
        // Status indicator dot
        statusDot = NSTextField(labelWithString: "●")
        statusDot.font = NSFont.systemFont(ofSize: 10, weight: .bold)
        statusDot.textColor = .systemGray
        statusDot.frame = NSRect(x: 12, y: 17, width: 14, height: 14)
        visualEffect.addSubview(statusDot)
        
        // Screen popup selector
        screenSelectButton = NSPopUpButton(frame: NSRect(x: 26, y: 8, width: 120, height: 30), pullsDown: false)
        screenSelectButton.bezelStyle = .rounded
        screenSelectButton.isBordered = false
        screenSelectButton.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        screenSelectButton.target = self
        screenSelectButton.action = #selector(screenSelectionChanged(_:))
        visualEffect.addSubview(screenSelectButton)
        
        // Main action button: "动起来"
        actionButton = NSButton(frame: NSRect(x: 154, y: 8, width: 92, height: 30))
        actionButton.bezelStyle = .regularSquare
        actionButton.wantsLayer = true
        actionButton.layer?.cornerRadius = 15
        actionButton.layer?.masksToBounds = true
        actionButton.isBordered = false
        actionButton.font = NSFont.systemFont(ofSize: 12, weight: .bold)
        actionButton.target = self
        actionButton.action = #selector(actionButtonClicked)
        visualEffect.addSubview(actionButton)
        
        self.contentView = visualEffect
    }
    
    private var currentTargetScreen: NSScreen? {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return nil }
        if targetScreenIndex >= screens.count {
            targetScreenIndex = 0
        }
        return screens[targetScreenIndex]
    }
    
    func refreshScreens() {
        screenSelectButton.removeAllItems()
        for (i, scr) in NSScreen.screens.enumerated() {
            let name = scr.localizedName
            let title = name.contains("Built-in") || name.contains("Color LCD") ? "💻 内建屏" : "🖥️ \(name.prefix(8))"
            screenSelectButton.addItem(withTitle: title)
            screenSelectButton.lastItem?.tag = i
        }
        if targetScreenIndex < screenSelectButton.numberOfItems {
            screenSelectButton.selectItem(at: targetScreenIndex)
        }
    }
    
    func updateUI() {
        refreshScreens()
        guard let screen = currentTargetScreen else { return }
        
        let isAnimating = WallpaperEngine.shared.isScreenAnimating(screen)
        if isAnimating {
            statusDot.textColor = .systemGreen
            actionButton.title = "静止 ⏸"
            actionButton.layer?.backgroundColor = NSColor.systemGray.withAlphaComponent(0.4).cgColor
            actionButton.contentTintColor = .white
        } else {
            statusDot.textColor = .systemGray
            actionButton.title = "动起来 ▶"
            actionButton.layer?.backgroundColor = NSColor.systemTeal.withAlphaComponent(0.85).cgColor
            actionButton.contentTintColor = .white
        }
    }
    
    @objc private func screenSelectionChanged(_ sender: NSPopUpButton) {
        targetScreenIndex = sender.indexOfSelectedItem
        updateUI()
    }
    
    @objc private func actionButtonClicked() {
        guard let screen = currentTargetScreen else { return }
        WallpaperEngine.shared.toggleScreen(screen: screen)
        updateUI()
    }
    
    @objc private func onWallpaperStateChanged() {
        DispatchQueue.main.async { [weak self] in
            self?.updateUI()
        }
    }
}
