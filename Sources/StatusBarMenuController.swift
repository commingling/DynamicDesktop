import Cocoa
import ServiceManagement

class StatusBarMenuController: NSObject, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var menu: NSMenu!
    private var floatingPanel: FloatingButtonPanel?
    private var isMenuOpen: Bool = false
    
    override init() {
        super.init()
        
        setupStatusItem()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(onWallpaperStateChanged),
            name: .wallpaperStateChanged,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(onWallpaperStateChanged),
            name: .wallpaperDownloadCompleted,
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
        let headerItem = NSMenuItem(title: "🖥️ Mac 动态壁纸控制台", action: nil, keyEquivalent: "")
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
        
        // Quick Action: Next Wallpaper
        let nextWpItem = NSMenuItem(
            title: "⏭ 立即切换至下一张壁纸",
            action: #selector(nextWallpaperClicked),
            keyEquivalent: "n"
        )
        nextWpItem.target = self
        menu.addItem(nextWpItem)
        
        // Auto-switch timer submenu
        let autoSubmenu = NSMenu()
        let currentInterval = WallpaperEngine.shared.autoSwitchInterval
        
        let intervals: [(title: String, seconds: Double)] = [
            ("关闭", 0),
            ("1 分钟 (快速体验)", 60),
            ("3 分钟", 180),
            ("5 分钟", 300),
            ("10 分钟 (推荐)", 600),
            ("15 分钟", 900),
            ("30 分钟", 1800),
            ("1 小时", 3600)
        ]
        
        for option in intervals {
            let item = NSMenuItem(title: option.title, action: #selector(autoSwitchIntervalClicked(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = option.seconds
            if currentInterval == option.seconds {
                item.state = .on
            }
            autoSubmenu.addItem(item)
        }
        
        autoSubmenu.addItem(NSMenuItem.separator())
        
        // Shuffle toggle
        let shuffleItem = NSMenuItem(
            title: "🔀 随机切换壁纸 (Shuffle)",
            action: #selector(toggleShuffleClicked),
            keyEquivalent: ""
        )
        shuffleItem.target = self
        shuffleItem.state = WallpaperEngine.shared.isShuffleEnabled ? .on : .off
        autoSubmenu.addItem(shuffleItem)
        
        // Sync all screens toggle
        let syncAllItem = NSMenuItem(
            title: "🖥️ 切换壁纸时同步所有屏幕",
            action: #selector(toggleSyncAllScreensClicked),
            keyEquivalent: ""
        )
        syncAllItem.target = self
        syncAllItem.state = WallpaperEngine.shared.syncAllScreensOnSwitch ? .on : .off
        autoSubmenu.addItem(syncAllItem)
        
        let autoIntervalLabel: String
        if currentInterval == 0 {
            autoIntervalLabel = "关闭"
        } else if currentInterval < 60 {
            autoIntervalLabel = "\(Int(currentInterval))秒"
        } else if currentInterval < 3600 {
            autoIntervalLabel = "\(Int(currentInterval / 60))分钟"
        } else {
            autoIntervalLabel = "\(Int(currentInterval / 3600))小时"
        }
        
        let timerMenuItem = NSMenuItem(title: "⏰ 自动定时切换壁纸 (当前: \(autoIntervalLabel))", action: nil, keyEquivalent: "")
        timerMenuItem.submenu = autoSubmenu
        menu.addItem(timerMenuItem)
        
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
        let wpMenuItem = NSMenuItem(title: "🌄 切换原生壁纸 (已下载 \(allWallpapers.count) 款) - \(currentName)", action: nil, keyEquivalent: "")
        wpMenuItem.submenu = wpSubmenu
        menu.addItem(wpMenuItem)
        
        // Auto Download Submenu
        let dlSubmenu = NSMenu()
        let downloader = WallpaperDownloader.shared
        let downloadedCount = downloader.getDownloadedCount()
        let totalCount = downloader.getTotalCount()
        let undownloadedCount = max(0, totalCount - downloadedCount)
        
        // Auto download toggle
        let autoDlItem = NSMenuItem(
            title: "自动在后台下载官方壁纸 (无需手动下载)",
            action: #selector(toggleAutoDownloadClicked),
            keyEquivalent: ""
        )
        autoDlItem.target = self
        autoDlItem.state = downloader.isAutoDownloadEnabled ? .on : .off
        dlSubmenu.addItem(autoDlItem)
        dlSubmenu.addItem(NSMenuItem.separator())
        
        if downloader.isDownloading, let asset = downloader.currentAsset {
            let pct = Int(downloader.progress * 100)
            let statusItem = NSMenuItem(title: "⏳ 正在下载: \(asset.name) (\(pct)%)", action: nil, keyEquivalent: "")
            statusItem.isEnabled = false
            dlSubmenu.addItem(statusItem)
            
            let pauseItem = NSMenuItem(title: "⏹ 暂停下载", action: #selector(pauseDownloadClicked), keyEquivalent: "")
            pauseItem.target = self
            dlSubmenu.addItem(pauseItem)
        } else {
            let nextDlItem = NSMenuItem(title: "⬇️ 立即下载下一款官方壁纸", action: #selector(downloadNextClicked), keyEquivalent: "")
            nextDlItem.target = self
            nextDlItem.isEnabled = undownloadedCount > 0
            dlSubmenu.addItem(nextDlItem)
            
            let batch5Item = NSMenuItem(title: "⬇️ 批量下载 5 款壁纸", action: #selector(downloadBatch5Clicked), keyEquivalent: "")
            batch5Item.target = self
            batch5Item.isEnabled = undownloadedCount > 0
            dlSubmenu.addItem(batch5Item)
            
            let allDlItem = NSMenuItem(title: "⬇️ 下载全部剩余官方壁纸 (\(undownloadedCount) 款)", action: #selector(downloadAllClicked), keyEquivalent: "")
            allDlItem.target = self
            allDlItem.isEnabled = undownloadedCount > 0
            dlSubmenu.addItem(allDlItem)
        }
        
        let dlHeaderTitle: String
        if downloader.isDownloading, let asset = downloader.currentAsset {
            let pct = Int(downloader.progress * 100)
            dlHeaderTitle = "📥 官方壁纸自动下载 [正在下载 \(asset.name) \(pct)%]"
        } else {
            dlHeaderTitle = "📥 官方壁纸自动下载 (已就绪 \(downloadedCount)/\(totalCount) 款)"
        }
        
        let dlMenuItem = NSMenuItem(title: dlHeaderTitle, action: nil, keyEquivalent: "")
        dlMenuItem.submenu = dlSubmenu
        menu.addItem(dlMenuItem)
        
        // Open macOS Wallpaper Settings
        let sysSettingsItem = NSMenuItem(title: "⚙️ 打开 macOS 原生壁纸系统设置...", action: #selector(openSystemWallpaperSettings), keyEquivalent: "")
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
        
        // Optional floating panel (disabled and hidden by default)
        let isFloatingVisible = floatingPanel?.isVisible == true
        let floatingToggle = NSMenuItem(
            title: isFloatingVisible ? "隐藏桌面上显示的悬浮菜单" : "在桌面上显示悬浮控制菜单",
            action: #selector(toggleFloatingPanel),
            keyEquivalent: ""
        )
        floatingToggle.target = self
        floatingToggle.state = isFloatingVisible ? .on : .off
        menu.addItem(floatingToggle)
        
        menu.addItem(NSMenuItem.separator())
        
        // Quit
        let quitItem = NSMenuItem(title: "退出", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        
        updateIcon()
    }
    
    // MARK: - NSMenuDelegate
    
    func menuWillOpen(_ menu: NSMenu) {
        if menu == self.menu {
            isMenuOpen = true
            rebuildMenu()
        }
    }
    
    func menuDidClose(_ menu: NSMenu) {
        if menu == self.menu {
            isMenuOpen = false
        }
    }
    
    @objc private func toggleScreenItemClicked(_ sender: NSMenuItem) {
        let screens = NSScreen.screens
        guard sender.tag >= 0 && sender.tag < screens.count else { return }
        let screen = screens[sender.tag]
        WallpaperEngine.shared.toggleScreen(screen: screen)
    }
    
    @objc private func startAllScreens() {
        WallpaperEngine.shared.startAll()
    }
    
    @objc private func stopAllScreens() {
        WallpaperEngine.shared.stopAll()
    }
    
    @objc private func nextWallpaperClicked() {
        WallpaperEngine.shared.switchToNextWallpaper()
    }
    
    @objc private func autoSwitchIntervalClicked(_ sender: NSMenuItem) {
        guard let seconds = sender.representedObject as? Double else { return }
        WallpaperEngine.shared.autoSwitchInterval = seconds
        if seconds > 0 && !WallpaperEngine.shared.isAnyScreenAnimating() {
            WallpaperEngine.shared.startAll()
        }
    }
    
    @objc private func toggleShuffleClicked() {
        WallpaperEngine.shared.isShuffleEnabled.toggle()
    }
    
    @objc private func toggleSyncAllScreensClicked() {
        WallpaperEngine.shared.syncAllScreensOnSwitch.toggle()
    }
    
    @objc private func selectWallpaperItemClicked(_ sender: NSMenuItem) {
        guard let wp = sender.representedObject as? WallpaperAsset else { return }
        WallpaperEngine.shared.setWallpaper(wp)
    }
    
    @objc private func toggleAutoDownloadClicked() {
        WallpaperDownloader.shared.isAutoDownloadEnabled.toggle()
    }
    
    @objc private func downloadNextClicked() {
        WallpaperDownloader.shared.downloadBatch(count: 1)
    }
    
    @objc private func downloadBatch5Clicked() {
        WallpaperDownloader.shared.downloadBatch(count: 5)
    }
    
    @objc private func downloadAllClicked() {
        WallpaperDownloader.shared.downloadAll()
    }
    
    @objc private func pauseDownloadClicked() {
        WallpaperDownloader.shared.pauseDownload()
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
    }
    
    @objc private func toggleFloatingPanel() {
        if let panel = floatingPanel {
            if panel.isVisible {
                panel.orderOut(nil)
            } else {
                panel.makeKeyAndOrderFront(nil)
            }
        } else {
            let panel = FloatingButtonPanel()
            panel.makeKeyAndOrderFront(nil)
            self.floatingPanel = panel
        }
    }
    
    @objc private func quitApp() {
        floatingPanel?.orderOut(nil)
        floatingPanel = nil
        WallpaperDownloader.shared.pauseDownload()
        WallpaperEngine.shared.stopAll()
        NSApplication.shared.terminate(nil)
    }
    
    @objc private func onWallpaperStateChanged() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.updateIcon()
            // CRUCIAL: Do NOT rebuild menu while user has it open!
            if !self.isMenuOpen {
                self.rebuildMenu()
            }
        }
    }
}
