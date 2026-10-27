import Cocoa
import ServiceManagement

class StatusBarMenuController: NSObject, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var menu: NSMenu!
    private var floatingPanel: FloatingButtonPanel?
    private var isMenuOpen: Bool = false
    private var downloadMenuItem: NSMenuItem?
    private var downloadStatusItem: NSMenuItem?
    private var pauseDownloadItem: NSMenuItem?
    private var nextDownloadItem: NSMenuItem?
    private var batchDownloadItem: NSMenuItem?
    
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
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(onDownloadProgress),
            name: .wallpaperDownloadProgress,
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
        
        let isAnimating = WallpaperEngine.shared.isAnyScreenAnimating()
        
        if isAnimating {
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
            button.toolTip = "Mac 动态壁纸控制 (点击展开菜单)"
        }
    }
    
    func rebuildMenu() {
        menu.removeAllItems()
        downloadMenuItem = nil
        downloadStatusItem = nil
        pauseDownloadItem = nil
        nextDownloadItem = nil
        batchDownloadItem = nil
        
        // Header
        let headerItem = NSMenuItem(title: "🖥️ Mac 动态壁纸控制台", action: nil, keyEquivalent: "")
        headerItem.isEnabled = false
        menu.addItem(headerItem)
        menu.addItem(NSMenuItem.separator())
        
        // 1. Master Control (All screens together)
        let screens = NSScreen.screens
        let allAnimating = !screens.isEmpty && screens.allSatisfy { WallpaperEngine.shared.isScreenAnimating($0) }
        let batchTitle = allAnimating
            ? "⏸ 所有屏幕显示静态壁纸"
            : "▶ 所有屏幕播放动态壁纸"
        let batchItem = NSMenuItem(title: batchTitle, action: #selector(toggleAllScreensClicked), keyEquivalent: "a")
        batchItem.target = self
        menu.addItem(batchItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // 2. Individual Screen Controls (单独开启/停止某个屏幕)
        let sectionHeader = NSMenuItem(title: "💻 各屏幕动静设置（壁纸相同）：", action: nil, keyEquivalent: "")
        sectionHeader.isEnabled = false
        menu.addItem(sectionHeader)
        
        for (i, screen) in screens.enumerated() {
            let isAnim = WallpaperEngine.shared.isScreenAnimating(screen)
            let rawName = screen.localizedName
            let screenLabel = rawName.contains("Built-in") || rawName.contains("Color LCD") ? "💻 内建屏幕" : "🖥️ \(rawName)"
            let statusText = isAnim ? "🟢 动态播放（点击设为静态）" : "⚪️ 静态／未启用（点击播放）"
            
            let item = NSMenuItem(
                title: "  \(screenLabel)：\(statusText)",
                action: #selector(toggleIndividualScreenClicked(_:)),
                keyEquivalent: "\(i + 1)"
            )
            item.target = self
            item.representedObject = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
            menu.addItem(item)
        }
        
        menu.addItem(NSMenuItem.separator())
        
        // 3. Quick Action: Next Wallpaper
        let nextWpItem = NSMenuItem(
            title: "⏭ 立即切换至下一张壁纸 (⌘N)",
            action: #selector(nextWallpaperClicked),
            keyEquivalent: "n"
        )
        nextWpItem.target = self
        menu.addItem(nextWpItem)
        
        if let currentWp = WallpaperEngine.shared.currentWallpaper {
            let sizeLabel = currentWp.formattedFileSize.isEmpty ? "" : " (\(currentWp.formattedFileSize))"
            let deleteCurrentItem = NSMenuItem(
                title: "🗑️ 删除当前壁纸并换下一张\(sizeLabel)...",
                action: #selector(deleteCurrentWallpaperClicked),
                keyEquivalent: ""
            )
            deleteCurrentItem.target = self
            menu.addItem(deleteCurrentItem)
        }
        
        // 4. Auto-switch timer submenu
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
        
        // 5. Wallpapers Submenu
        let currentWp = WallpaperEngine.shared.currentWallpaper
        let wpSubmenu = NSMenu()
        let allWallpapers = WallpaperDetector.shared.getAllWallpapers()
        
        if let current = currentWp {
            let delCurItem = NSMenuItem(
                title: "🗑️ 删除当前壁纸「\(current.name)」(\(current.formattedFileSize))...",
                action: #selector(deleteCurrentWallpaperClicked),
                keyEquivalent: ""
            )
            delCurItem.target = self
            wpSubmenu.addItem(delCurItem)
            
            let revealCurItem = NSMenuItem(
                title: "📂 在访达 (Finder) 中定位当前壁纸文件...",
                action: #selector(revealCurrentWallpaperInFinderClicked),
                keyEquivalent: ""
            )
            revealCurItem.target = self
            wpSubmenu.addItem(revealCurItem)
            
            wpSubmenu.addItem(NSMenuItem.separator())
        }
        
        let chooseHeader = NSMenuItem(title: "点击选择壁纸：", action: nil, keyEquivalent: "")
        chooseHeader.isEnabled = false
        wpSubmenu.addItem(chooseHeader)
        
        for wp in allWallpapers {
            let title = wp.formattedFileSize.isEmpty ? wp.name : "\(wp.name) (\(wp.formattedFileSize))"
            let item = NSMenuItem(title: title, action: #selector(selectWallpaperItemClicked(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = wp
            if currentWp?.id == wp.id {
                item.state = .on
            }
            wpSubmenu.addItem(item)
        }
        
        let currentName = currentWp?.name ?? "默认壁纸"
        let wpMenuItem = NSMenuItem(title: "🌄 切换原生壁纸 (已就绪 \(allWallpapers.count) 款) - 当前: \(currentName)", action: nil, keyEquivalent: "")
        wpMenuItem.submenu = wpSubmenu
        menu.addItem(wpMenuItem)
        if WallpaperEngine.shared.stillFrameError != nil {
            let warning = NSMenuItem(title: "⚠️ 静态画面加载失败，请重新选择壁纸重试", action: nil, keyEquivalent: "")
            warning.isEnabled = false
            menu.addItem(warning)
        }

        // Ambient Sound Submenu
        let soundMgr = AmbientSoundManager.shared
        let soundSubmenu = NSMenu()
        
        let soundToggleItem = NSMenuItem(
            title: "开启自然环境氛围音",
            action: #selector(toggleAmbientSoundClicked),
            keyEquivalent: ""
        )
        soundToggleItem.target = self
        soundToggleItem.state = soundMgr.isEnabled ? .on : .off
        soundSubmenu.addItem(soundToggleItem)

        let warmFilterItem = NSMenuItem(
            title: "🎧 柔和模式（降低高频）",
            action: #selector(toggleWarmFilterClicked),
            keyEquivalent: ""
        )
        warmFilterItem.target = self
        warmFilterItem.state = soundMgr.isWarmFilterEnabled ? .on : .off
        soundSubmenu.addItem(warmFilterItem)
        
        soundSubmenu.addItem(NSMenuItem.separator())
        
        let soundSection = NSMenuItem(title: "声音选择：", action: nil, keyEquivalent: "")
        soundSection.isEnabled = false
        soundSubmenu.addItem(soundSection)
        
        for soundType in AmbientSoundType.allCases {
            let item = NSMenuItem(title: soundType.displayName, action: #selector(selectSoundTypeClicked(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = soundType
            if soundMgr.selectedType == soundType {
                item.state = .on
            }
            soundSubmenu.addItem(item)
        }
        
        soundSubmenu.addItem(NSMenuItem.separator())
        
        let volSection = NSMenuItem(title: "音量大小：", action: nil, keyEquivalent: "")
        volSection.isEnabled = false
        soundSubmenu.addItem(volSection)
        
        let volumes: [(title: String, val: Float)] = [
            ("🔈 8% (微风细语 - 耳机极轻柔)", 0.08),
            ("🔉 15% (柔和伴奏 - 耳机推荐)", 0.15),
            ("🔉 25% (清晰自然 - 外放推荐)", 0.25),
            ("🔊 40% (沉浸自然)", 0.40),
            ("🔊 60%", 0.60),
            ("🔊 80%", 0.80),
            ("🔊 100%", 1.00)
        ]
        
        for vol in volumes {
            let item = NSMenuItem(title: vol.title, action: #selector(selectVolumeClicked(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = vol.val
            if abs(soundMgr.volume - vol.val) < 0.04 {
                item.state = .on
            }
            soundSubmenu.addItem(item)
        }
        
        let currentSoundLabel = soundMgr.isEnabled ? soundMgr.getCurrentSoundName() : "已关闭"
        let soundMenuItem = NSMenuItem(title: "🎵 官方自然环境音 (当前: \(currentSoundLabel))", action: nil, keyEquivalent: "")
        soundMenuItem.submenu = soundSubmenu
        menu.addItem(soundMenuItem)
        
        // 6. Auto Download Submenu
        let dlSubmenu = NSMenu()
        dlSubmenu.autoenablesItems = false
        let downloader = WallpaperDownloader.shared
        let downloadedCount = downloader.getDownloadedCount()
        let totalCount = downloader.getTotalCount()
        let undownloadedCount = max(0, totalCount - downloadedCount)
        
        let autoDlItem = NSMenuItem(
            title: "自动在后台下载官方壁纸",
            action: #selector(toggleAutoDownloadClicked),
            keyEquivalent: ""
        )
        autoDlItem.target = self
        autoDlItem.state = downloader.isAutoDownloadEnabled ? .on : .off
        dlSubmenu.addItem(autoDlItem)
        dlSubmenu.addItem(NSMenuItem.separator())
        
        let statusItem = NSMenuItem(title: "当前没有正在进行的下载", action: nil, keyEquivalent: "")
        statusItem.isEnabled = false
        statusItem.isHidden = !downloader.isDownloading
        dlSubmenu.addItem(statusItem)
        downloadStatusItem = statusItem

        let pauseItem = NSMenuItem(title: "⏹ 暂停下载", action: #selector(pauseDownloadClicked), keyEquivalent: "")
        pauseItem.target = self
        pauseItem.isHidden = !downloader.isDownloading
        dlSubmenu.addItem(pauseItem)
        pauseDownloadItem = pauseItem

        let nextDlItem = NSMenuItem(title: "⬇️ 立即下载下一款官方壁纸", action: #selector(downloadNextClicked), keyEquivalent: "")
        nextDlItem.target = self
        nextDlItem.isEnabled = undownloadedCount > 0
        nextDlItem.isHidden = downloader.isDownloading
        dlSubmenu.addItem(nextDlItem)
        nextDownloadItem = nextDlItem

        let batch5Item = NSMenuItem(title: "⬇️ 批量下载 5 款壁纸", action: #selector(downloadBatch5Clicked), keyEquivalent: "")
        batch5Item.target = self
        batch5Item.isEnabled = undownloadedCount > 0
        batch5Item.isHidden = downloader.isDownloading
        dlSubmenu.addItem(batch5Item)
        batchDownloadItem = batch5Item
        
        let dlHeaderTitle: String
        if downloader.isDownloading, let asset = downloader.currentAsset {
            let pct = Int(downloader.progress * 100)
            dlHeaderTitle = "📥 官方壁纸下载 [正在下载 \(asset.name) \(pct)%]"
        } else {
            dlHeaderTitle = "📥 官方壁纸下载管理 (已就绪 \(downloadedCount)/\(totalCount) 款)"
        }
        
        let dlMenuItem = NSMenuItem(title: dlHeaderTitle, action: nil, keyEquivalent: "")
        dlMenuItem.submenu = dlSubmenu
        menu.addItem(dlMenuItem)
        downloadMenuItem = dlMenuItem
        updateVisibleDownloadProgress()
        
        // 7. Wallpaper Storage Management & Cleanup Submenu
        let cleanSubmenu = NSMenu()
        let totalSizeStr = WallpaperDetector.shared.getTotalWallpapersSize()
        
        let storageHeader = NSMenuItem(
            title: "💾 共下载 \(allWallpapers.count) 款 4K 壁纸，占用空间 \(totalSizeStr)",
            action: nil,
            keyEquivalent: ""
        )
        storageHeader.isEnabled = false
        cleanSubmenu.addItem(storageHeader)
        
        let openFolderItem = NSMenuItem(
            title: "📂 在访达中打开壁纸文件夹 (支持批量预览与删除)...",
            action: #selector(openWallpapersFolderInFinderClicked),
            keyEquivalent: ""
        )
        openFolderItem.target = self
        cleanSubmenu.addItem(openFolderItem)
        
        cleanSubmenu.addItem(NSMenuItem.separator())
        
        if let current = currentWp {
            let delCur = NSMenuItem(
                title: "🗑️ 删除当前正在播放的壁纸「\(current.name)」(\(current.formattedFileSize))...",
                action: #selector(deleteCurrentWallpaperClicked),
                keyEquivalent: ""
            )
            delCur.target = self
            cleanSubmenu.addItem(delCur)
            cleanSubmenu.addItem(NSMenuItem.separator())
        }
        
        let delListHeader = NSMenuItem(title: "点击将指定壁纸移入废纸篓（按大小降序）：", action: nil, keyEquivalent: "")
        delListHeader.isEnabled = false
        cleanSubmenu.addItem(delListHeader)
        
        let sortedBySize = allWallpapers.sorted { $0.fileSize > $1.fileSize }
        for wp in sortedBySize {
            let isCurrent = (wp.id == currentWp?.id)
            let currentTag = isCurrent ? " [当前播放]" : ""
            let sizeLabel = wp.formattedFileSize.isEmpty ? "" : " (\(wp.formattedFileSize))"
            let title = "🗑️ \(wp.name)\(sizeLabel)\(currentTag)"
            let item = NSMenuItem(title: title, action: #selector(deleteSpecificWallpaperClicked(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = wp
            cleanSubmenu.addItem(item)
        }
        
        let cleanMenuItem = NSMenuItem(title: "🗑️ 壁纸空间管理与删除 (已占用: \(totalSizeStr))", action: nil, keyEquivalent: "")
        cleanMenuItem.submenu = cleanSubmenu
        menu.addItem(cleanMenuItem)
        
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
    
    @objc private func toggleAllScreensClicked() {
        WallpaperEngine.shared.toggleAll()
    }
    
    @objc private func toggleIndividualScreenClicked(_ sender: NSMenuItem) {
        guard let displayID = sender.representedObject as? NSNumber,
              let screen = NSScreen.screens.first(where: {
                  ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber) == displayID
              }) else { return }
        WallpaperEngine.shared.toggleScreen(screen)
    }
    
    @objc private func nextWallpaperClicked() {
        WallpaperEngine.shared.switchToNextWallpaper()
    }
    
    @objc private func autoSwitchIntervalClicked(_ sender: NSMenuItem) {
        guard let seconds = sender.representedObject as? Double else { return }
        WallpaperEngine.shared.autoSwitchInterval = seconds
    }
    
    @objc private func toggleShuffleClicked() {
        WallpaperEngine.shared.isShuffleEnabled.toggle()
    }
    
    @objc private func selectWallpaperItemClicked(_ sender: NSMenuItem) {
        guard let wp = sender.representedObject as? WallpaperAsset else { return }
        WallpaperEngine.shared.setWallpaper(wp)
    }
    
    @objc private func toggleAutoDownloadClicked() {
        WallpaperDownloader.shared.isAutoDownloadEnabled.toggle()
    }
    
    @objc private func toggleAmbientSoundClicked() {
        AmbientSoundManager.shared.isEnabled.toggle()
        rebuildMenu()
    }
    
    @objc private func toggleWarmFilterClicked() {
        AmbientSoundManager.shared.isWarmFilterEnabled.toggle()
        rebuildMenu()
    }
    
    @objc private func selectSoundTypeClicked(_ sender: NSMenuItem) {
        guard let type = sender.representedObject as? AmbientSoundType else { return }
        AmbientSoundManager.shared.selectedType = type
        rebuildMenu()
    }
    
    @objc private func selectVolumeClicked(_ sender: NSMenuItem) {
        guard let vol = sender.representedObject as? Float else { return }
        AmbientSoundManager.shared.volume = vol
        rebuildMenu()
    }
    
    @objc private func downloadNextClicked() {
        WallpaperDownloader.shared.downloadBatch(count: 1)
    }
    
    @objc private func downloadBatch5Clicked() {
        WallpaperDownloader.shared.downloadBatch(count: 5)
    }
    
    @objc private func pauseDownloadClicked() {
        WallpaperDownloader.shared.pauseDownload()
    }
    
    @objc private func deleteCurrentWallpaperClicked() {
        guard let current = WallpaperEngine.shared.currentWallpaper else { return }
        confirmAndDeleteWallpaper(current)
    }
    
    @objc private func deleteSpecificWallpaperClicked(_ sender: NSMenuItem) {
        guard let wp = sender.representedObject as? WallpaperAsset else { return }
        confirmAndDeleteWallpaper(wp)
    }
    
    @objc private func revealCurrentWallpaperInFinderClicked() {
        guard let current = WallpaperEngine.shared.currentWallpaper else { return }
        NSWorkspace.shared.activateFileViewerSelecting([current.url])
    }
    
    @objc private func openWallpapersFolderInFinderClicked() {
        NSWorkspace.shared.open(WallpaperDetector.shared.videosDir)
    }
    
    private func confirmAndDeleteWallpaper(_ wp: WallpaperAsset) {
        let all = WallpaperDetector.shared.getAllWallpapers()
        if all.count <= 1 {
            let alert = NSAlert()
            alert.messageText = "无法删除壁纸"
            alert.informativeText = "「\(wp.name)」是当前仅有的一张壁纸。请至少保留一张壁纸，或下载其他壁纸后再删除。"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "知道了")
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
            return
        }
        
        let isCurrent = (WallpaperEngine.shared.currentWallpaper?.id == wp.id)
        let alert = NSAlert()
        alert.messageText = "确定将壁纸移入废纸篓吗？"
        let switchNote = isCurrent ? "\n\n⚠️ 这是当前正在播放的壁纸，删除后将自动为您切换至下一张壁纸。" : ""
        let sizeNote = wp.formattedFileSize.isEmpty ? "" : "\n文件大小：\(wp.formattedFileSize)"
        alert.informativeText = "壁纸名称：\(wp.name)\(sizeNote)\(switchNote)"
        alert.alertStyle = .critical
        let deleteBtn = alert.addButton(withTitle: "移入废纸篓")
        deleteBtn.hasDestructiveAction = true
        alert.addButton(withTitle: "取消")
        
        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            let success = WallpaperEngine.shared.deleteWallpaper(wp)
            if success {
                rebuildMenu()
            } else {
                let failAlert = NSAlert()
                failAlert.messageText = "删除失败"
                failAlert.informativeText = "无法将壁纸移入废纸篓，请检查文件权限或直接在访达中清理。"
                failAlert.alertStyle = .warning
                failAlert.addButton(withTitle: "确定")
                NSApp.activate(ignoringOtherApps: true)
                failAlert.runModal()
            }
        }
    }
    
    @objc private func openSystemWallpaperSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Wallpaper-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }
    
    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                if SMAppService.mainApp.status != .requiresApproval {
                    try SMAppService.mainApp.register()
                }
                if SMAppService.mainApp.status == .requiresApproval {
                    let alert = NSAlert()
                    alert.messageText = "需要允许开机自动启动"
                    alert.informativeText = "请在系统设置的“通用 > 登录项”中允许 DynamicDesktop。"
                    alert.runModal()
                }
            }
        } catch {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "无法更改开机自动启动设置"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
        rebuildMenu()
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
            if !self.isMenuOpen {
                self.rebuildMenu()
            } else {
                self.updateVisibleDownloadProgress()
            }
        }
    }

    @objc private func onDownloadProgress() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            // The menu is rebuilt before opening; only update visible progress here.
            guard self.isMenuOpen else { return }
            self.updateVisibleDownloadProgress()
        }
    }

    private func updateVisibleDownloadProgress() {
        let downloader = WallpaperDownloader.shared
        downloadStatusItem?.isHidden = !downloader.isDownloading
        pauseDownloadItem?.isHidden = !downloader.isDownloading
        nextDownloadItem?.isHidden = downloader.isDownloading
        batchDownloadItem?.isHidden = downloader.isDownloading
        if downloader.isDownloading, let asset = downloader.currentAsset {
            let percent = Int(downloader.progress * 100)
            downloadMenuItem?.title = "📥 官方壁纸下载 [正在下载 \(asset.name) \(percent)%]"
            downloadStatusItem?.title = "⏳ 正在下载: \(asset.name) (\(percent)%)"
        } else {
            let downloadedCount = downloader.getDownloadedCount()
            let totalCount = downloader.getTotalCount()
            downloadMenuItem?.title = "📥 官方壁纸下载管理 (已就绪 \(downloadedCount)/\(totalCount) 款)"
            downloadStatusItem?.title = "当前没有正在进行的下载"
            nextDownloadItem?.isEnabled = downloadedCount < totalCount
            batchDownloadItem?.isEnabled = downloadedCount < totalCount
        }
    }
}
