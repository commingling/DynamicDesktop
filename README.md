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
* **独立屏幕控制**：完美支持多显示器（如 MacBook 内建 Liquid Retina 屏 + 外接 4K/5K 显示器），可指定任意一台显示器动起来，也可全部动起来。
* **100% 原生系统壁纸**：自动读取 Mac 本地已缓存的 Apple 官方动态壁纸视频（如金门大桥夜景、加州航拍等），无需下载臃肿的第三方资源。
* **极致性能与事件穿透**：基于 AppKit + AVFoundation 原生硬件解码，CPU 占用率接近 0%，窗口置于桌面底层（`kCGDesktopWindowLevel + 1`），所有桌面文件图标与窗口均浮于上方，鼠标点击完全穿透。

---

## 🌟 核心功能 (Key Features)

- [x] **状态感知菜单栏图标**：桌面运动时图标为实心高亮（`display.fill`），静止时为线框（`display`）。
- [x] **多显示器独立切换**：一键切换指定屏幕或所有屏幕的动静状态。
- [x] **原生壁纸自动探测**：自动识别系统当前选中的动态壁纸，并支持在已缓存的多个 Apple 原生动态壁纸之间一键切换。
- [x] **极低功耗**：由 Apple Silicon M 系列芯片硬件解码器直接渲染，发热与功耗极低。
- [x] **开机自启动**：集成 macOS `SMAppService`，支持一键设置开机自启。
- [x] **可选桌面悬浮控制胶囊**：如果喜欢在桌面上悬浮控制，也可随时从菜单栏勾选开启毛玻璃悬浮胶囊。

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

# 安装至应用程序目录
cp -R DynamicDesktop.app /Applications/
open /Applications/DynamicDesktop.app
```

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
