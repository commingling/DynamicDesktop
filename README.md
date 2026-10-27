# DynamicDesktop for macOS 🖥️✨

<p align="center">
  <img src="AppIcon.icns" width="128" height="128" alt="DynamicDesktop Icon">
</p>

<p align="center">
  <b>A lightweight, zero-overhead macOS Menu Bar utility to make any display move using native Apple Aerial dynamic wallpapers.</b><br>
  一款轻量级原生 macOS 菜单栏小工具，一键让指定屏幕的桌面动起来，100% 采用 Mac 系统自带的 Apple 官方高画质 Aerial 动态壁纸。
</p>

<p align="center">
  <img src="https://img.shields.io/github/actions/workflow/status/commingling/DynamicDesktop/ci.yml?branch=main&style=flat-square&logo=github&label=CI%20Build" alt="Build Status">
  <img src="https://img.shields.io/github/v/release/commingling/DynamicDesktop?style=flat-square&color=blue" alt="Latest Release">
  <img src="https://img.shields.io/badge/Platform-macOS%2014.0%2B-blue?style=flat-square&logo=apple" alt="macOS 14+">
  <img src="https://img.shields.io/badge/Language-Swift%206-orange?style=flat-square&logo=swift" alt="Swift">
  <img src="https://img.shields.io/badge/Architecture-Apple%20Silicon-purple?style=flat-square" alt="Apple Silicon">
  <img src="https://img.shields.io/badge/License-MIT-green?style=flat-square" alt="MIT License">
</p>

---

## 📖 简介 (Introduction)

在 macOS Sonoma / Sequoia 及更高版本中，Apple 引入了精美绝伦的 4K 景观空中航拍壁纸（Aerial Wallpapers）。然而，系统默认在解锁登录后会将动态壁纸**减速定格为静态图片**，且不支持多显示器独立播放动态壁纸。

**DynamicDesktop** 解决了这个痛点：
* **纯菜单栏常驻**：无需在桌面上堆放悬浮窗，不打扰工作，随时从右上角菜单栏启停。
* **独立屏幕控制**：完美支持多显示器（如 MacBook 内建 Liquid Retina 屏 + 外接 4K/5K 显示器），可指定任意一台显示器动起来，其余屏幕显示同款壁纸的静态画面，也可全部动起来。
* **100% 原生系统壁纸**：自动读取 Mac 本地已缓存的 Apple 官方动态壁纸视频（如金门大桥夜景、加州航拍等），无需下载臃肿的第三方资源。
* **极致性能与事件穿透**：基于 AppKit + AVFoundation 原生硬件解码，CPU 占用率接近 0%，窗口置于桌面底层（`kCGDesktopWindowLevel + 1`），所有桌面文件图标与窗口均浮于上方，鼠标点击完全穿透。

---

## 🌟 核心功能 (Key Features)

- [x] **官方自然环境氛围音联动**：内置联动 Apple 官方系统级高品质自然环境音（海浪波涛、山涧溪流、淅沥细雨、温暖篝火、静谧夏夜、自然风等）。支持根据当前壁纸智能识别匹配，支持 10%~100% 独立音量微调与随时静音，打造沉浸式白噪音专注空间。
- [x] **官方壁纸自动后台下载**：自动接入 Apple 官方 4K/HDR Aerial 航拍壁纸 CDN，在后台静默自动下载剩余官方壁纸（全量 164 款），无需手动在系统设置中逐个点击下载！
- [x] **下载进度实时感知**：菜单栏实时显示下载状态与百分比进度（`⏳ 正在下载: Yosemite (42%)`），支持随时暂停或批量下载。
- [x] **多屏幕同步切换**：切换壁纸时，所有连接的屏幕（如内建屏幕与外接 4K 屏）同步平滑淡入切换至全新壁纸。
- [x] **自动定时轮播壁纸**：支持灵活设定自动切换周期（**1分钟、3分钟、5分钟、10分钟、15分钟、30分钟、1小时**），多壁纸自动循环，常换常新。
- [x] **随机与顺序播放**：支持按列表顺序循环或开启 **🔀 随机切换 (Shuffle)**。
- [x] **快捷一键切壁纸**：菜单中提供 `⏭ 立即切换至下一张壁纸`，支持快捷键 `⌘N` 随时一键切新壁纸。
- [x] **状态感知菜单栏图标**：桌面运动时图标为实心高亮（`display.fill`），静止时为线框（`display`）。
- [x] **多显示器独立/统一控制**：既可一键全屏动起来，也可单独切换指定屏幕的动静状态；各屏幕使用同一款壁纸，静态画面取自该壁纸视频。
- [x] **平滑淡入淡出**：切换壁纸采用 CoreAnimation 交叉渐变动画，避免任何黑屏或闪烁。
- [x] **极低功耗**：由 Apple Silicon M 系列芯片硬件解码器直接渲染，发热与功耗极低。
- [x] **开机自启动**：集成 macOS `SMAppService`，支持一键设置开机自启。
- [x] **可选桌面悬浮控制胶囊**：如果喜欢在桌面上悬浮控制，也可随时从菜单栏勾选开启毛玻璃悬浮胶囊。

### 一屏动态、一屏静态

在菜单栏的“各屏幕动静设置”中，点击需要播放的屏幕即可；其他屏幕会显示同款壁纸的视频静帧。再次点击播放中的屏幕可将它设为静态，切换壁纸时各屏幕的动静状态会保留。静态画面是视频中的一帧，动态屏播放后两边的画面不会始终完全相同。退出应用后会恢复显示各屏原有的系统桌面。

---

## 🛠️ 构建与安装 (Build & Install)

### 方式一：直接下载使用 (Pre-built Release)
1. 前往 [Releases 页面](https://github.com/commingling/DynamicDesktop/releases) 下载最新的 `DynamicDesktop-v1.0.0-arm64.zip`。
2. 解压并将 `DynamicDesktop.app` 拖入 `/Applications/`（应用程序目录）。
3. 首次启动如遇系统安全提示，前往「系统设置 ➔ 隐私与安全性」点击「仍要打开」即可。

### 方式二：源码编译安装 (Build from Source)
```bash
git clone https://github.com/commingling/DynamicDesktop.git
cd DynamicDesktop

# 运行构建脚本（包含图标打包与 App Bundle 组装）
chmod +x build.sh
./build.sh

# 默认编译为当前机器的架构；也可指定 arm64 或 x86_64
# BUILD_ARCH=arm64 ./build.sh

# 安装至应用程序目录
cp -R DynamicDesktop.app /Applications/
open /Applications/DynamicDesktop.app
```

构建产物的最低系统版本为 macOS 14.0。CI 构建产物为 Apple Silicon（arm64）版本。

---

## 📂 项目架构 (Architecture)

```text
DynamicDesktop/
├── Sources/
│   ├── main.swift                    # 应用入口与生命周期管理
│   ├── WallpaperDetector.swift       # 自动探测系统原生壁纸与元数据
│   ├── DesktopWallpaperWindow.swift  # 桌面底层无缝循环视频播放窗口 (AVQueuePlayer)
│   ├── WallpaperEngine.swift         # 多显示器状态调度中心
│   ├── StatusBarMenuController.swift # 顶部菜单栏控制器 (NSStatusItem)
│   └── FloatingButtonPanel.swift     # 可选的桌面半透明悬浮控制胶囊
├── build.sh                          # 原生 Swift 编译与打包脚本
├── AppIcon.icns                      # 应用程序高清图标
├── LICENSE                           # MIT 开源协议
└── README.md                         # 项目说明文档
```

---

## 📄 开源协议 (License)

本项目基于 [MIT 协议](LICENSE) 开源。
