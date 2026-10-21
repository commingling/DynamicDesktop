import Cocoa
import ServiceManagement

class StatusBarMenuController: NSObject, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var menu: NSMenu!
    private var floatingPanel: FloatingButtonPanel
    
    init(floatingPanel: FloatingButtonPanel) {
        self.floatingPanel = floatingPanel
        super.init()
        
        setupStatusItem()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(onWallpaperStateChanged),
            name: .wallpaperStateChanged,
            object: nil
        )
    }
    
    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        
        updateIcon()
        rebuildMenu()
    }
    
    private func updateIcon() {
        guard let button = statusItem.button else { return }
        
        let anyAnimating = NSScreen.screens.contains { WallpaperEngine.shared.isScreenAnimating($0) }
        
        if anyAnimating {
            let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
            if let img = NSImage(systemSymbolName: "display.fill", accessibilityDescription: "正在运动")?.withSymbolConfiguration(config) {
                button.image = img
            } else {
                button.title = "🖥️✨"
            }
            button.toolTip = "Mac 动态壁纸：正在运动中 (点击查看/切换)"
        } else {
            let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
            if let img = NSImage(systemSymbolName: "display", accessibilityDescription: "已静止")?.withSymbolConfiguration(config) {
                button.image = img
            } else {
                button.title = "🖥️"
            }
            button.toolTip = "Mac 动态壁纸控制 (点击让屏幕动起来)"
        }
    }
    
    func rebuildMenu() {
        menu.removeAllItems()
        
        // Header
        let headerItem = NSMenuItem(title: "🖥️ Mac 动态壁纸控制", action: nil, keyEquivalent: "")
        headerItem.isEnabled = false
        menu.addItem(headerItem)
        menu.addItem(NSMenuItem.separator())
        
        // Connected screens
        let screens = NSScreen.screens
        for (i, screen) in screens.enumerated() {
            let isAnimating = WallpaperEngine.shared.isScreenAnimating(screen)
            let rawName = screen.localizedName
            let screenLabel = rawName.contains("Built-in") || rawName.contains("Color LCD") ? "💻 内建屏幕" : "🖥️ \(rawName)"
            
            let title = isAnimating 
                ? "🟢 \(screenLabel)：正在运动 (点击停止 ⏸)" 
                : "⚪️ \(screenLabel)：点击让它动起来 ▶"
            
            let item = NSMenuItem(
                title: title,
                action: #selector(toggleScreenItemClicked(_:)),
                keyEquivalent: "\(i + 1)"
            )
            item.target = self
            item.tag = i
            menu.addItem(item)
        }
        
        menu.addItem(NSMenuItem.separator())
        
        // Batch controls
        let startAllItem = NSMenuItem(title: "▶ 所有屏幕全部动起来", action: #selector(startAllScreens), keyEquivalent: "")
        startAllItem.target = self
        menu.addItem(startAllItem)
        
        let stopAllItem = NSMenuItem(title: "⏸ 所有屏幕恢复静止", action: #selector(stopAllScreens), keyEquivalent: "")
        stopAllItem.target = self
        menu.addItem(stopAllItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Wallpapers Submenu
        let currentWp = WallpaperEngine.shared.currentWallpaper
        let wpSubmenu = NSMenu()
        let allWallpapers = WallpaperDetector.shared.getAllWallpapers()
        
        for wp in allWallpapers {
            let item = NSMenuItem(title: wp.name, action: #selector(selectWallpaperItemClicked(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = wp
            if currentWp?.id == wp.id {
                item.state = .on
            }
            wpSubmenu.addItem(item)
        }
        
        let currentName = currentWp?.name ?? "默认壁纸"
        let wpMenuItem = NSMenuItem(title: "🌄 切换原生壁纸 (\(currentName))", action: nil, keyEquivalent: "")
        wpMenuItem.submenu = wpSubmenu
        menu.addItem(wpMenuItem)
        
        // Open macOS Wallpaper Settings
        let sysSettingsItem = NSMenuItem(title: "⚙️ 下载更多官方动态壁纸...", action: #selector(openSystemWallpaperSettings), keyEquivalent: "")
        sysSettingsItem.target = self
        menu.addItem(sysSettingsItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Launch at login toggle
        let isLaunchAtLogin = SMAppService.mainApp.status == .enabled
        let launchItem = NSMenuItem(
            title: "开机自动启动",
            action: #selector(toggleLaunchAtLogin),
            keyEquivalent: ""
        )
        launchItem.target = self
        launchItem.state = isLaunchAtLogin ? .on : .off
        menu.addItem(launchItem)
        
        // Floating pill toggle (optional for users who want desktop button)
        let floatingToggle = NSMenuItem(
            title: "在桌面上显示悬浮控制按钮",
            action: #selector(toggleFloatingPanel),
            keyEquivalent: ""
        )
        floatingToggle.target = self
        floatingToggle.state = floatingPanel.isVisible ? .on : .off
        menu.addItem(floatingToggle)
        
        menu.addItem(NSMenuItem.separator())
        
        // Quit
        let quitItem = NSMenuItem(title: "退出", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        
        updateIcon()
    }
    
    func menuWillOpen(_ menu: NSMenu) {
        rebuildMenu()
    }
    
    @objc private func toggleScreenItemClicked(_ sender: NSMenuItem) {
        let screens = NSScreen.screens
        guard sender.tag >= 0 && sender.tag < screens.count else { return }
        let screen = screens[sender.tag]
        WallpaperEngine.shared.toggleScreen(screen: screen)
        rebuildMenu()
    }
    
    @objc private func startAllScreens() {
        WallpaperEngine.shared.startAll()
        rebuildMenu()
    }
    
    @objc private func stopAllScreens() {
        WallpaperEngine.shared.stopAll()
        rebuildMenu()
    }
    
    @objc private func selectWallpaperItemClicked(_ sender: NSMenuItem) {
        guard let wp = sender.representedObject as? WallpaperAsset else { return }
        WallpaperEngine.shared.setWallpaper(wp)
        rebuildMenu()
    }
    
    @objc private func openSystemWallpaperSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Wallpaper-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }
    
    @objc private func toggleLaunchAtLogin() {
        if SMAppService.mainApp.status == .enabled {
            try? SMAppService.mainApp.unregister()
        } else {
            try? SMAppService.mainApp.register()
        }
        rebuildMenu()
    }
    
    @objc private func toggleFloatingPanel() {
        if floatingPanel.isVisible {
            floatingPanel.orderOut(nil)
        } else {
            floatingPanel.makeKeyAndOrderFront(nil)
        }
        rebuildMenu()
    }
    
    @objc private func quitApp() {
        WallpaperEngine.shared.stopAll()
        NSApplication.shared.terminate(nil)
    }
    
    @objc private func onWallpaperStateChanged() {
        DispatchQueue.main.async { [weak self] in
            self?.updateIcon()
            self?.rebuildMenu()
        }
    }
}
