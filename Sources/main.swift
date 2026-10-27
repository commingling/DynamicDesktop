import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusController: StatusBarMenuController?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Pure Menu Bar App: NO desktop windows or panels created on launch!
        self.statusController = StatusBarMenuController()
        WallpaperEngine.shared.restorePreviousSession()
        print("DynamicDesktop started in pure Menu Bar mode.")
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        WallpaperEngine.shared.stopAll()
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
