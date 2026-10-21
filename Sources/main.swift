import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate {
    private var floatingPanel: FloatingButtonPanel?
    private var statusController: StatusBarMenuController?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Create the floating panel instance (kept hidden by default)
        let panel = FloatingButtonPanel()
        panel.orderOut(nil)
        self.floatingPanel = panel
        
        // Initialize menu bar status controller (primary UI)
        self.statusController = StatusBarMenuController(floatingPanel: panel)
        
        print("DynamicDesktop Menu Bar app started successfully.")
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
