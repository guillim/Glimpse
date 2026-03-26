import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate {

    private var desktopWindowController: DesktopWindowController?
    private var keyMonitor: Any?
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupKeyboardShortcut()
        setupPowerNotifications()
        DispatchQueue.main.async {
            self.desktopWindowController = DesktopWindowController()
            self.desktopWindowController?.showWindow(nil)
            self.setupMenuBarItem()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let monitor = keyMonitor { NSEvent.removeMonitor(monitor) }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ app: NSApplication) -> Bool {
        return false
    }

    // MARK: - Private

    private func setupPowerNotifications() {
        let wsNC = NSWorkspace.shared.notificationCenter
        wsNC.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            self?.desktopWindowController?.setPaused(true)
        }
        wsNC.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.desktopWindowController?.setPaused(false)
        }

        let dnc = DistributedNotificationCenter.default()
        dnc.addObserver(forName: NSNotification.Name("com.apple.screensaver.didstart"), object: nil, queue: .main) { [weak self] _ in
            self?.desktopWindowController?.setPaused(true)
        }
        dnc.addObserver(forName: NSNotification.Name("com.apple.screensaver.didstop"), object: nil, queue: .main) { [weak self] _ in
            self?.desktopWindowController?.setPaused(false)
        }
    }

    private func setupMenuBarItem() {
        if statusItem == nil {
            statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            if let button = statusItem?.button {
                button.image = NSImage(systemSymbolName: "photo.on.rectangle", accessibilityDescription: "Glimpse")
            }
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Exit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: ""))
        statusItem?.menu = menu
    }

    private func setupKeyboardShortcut() {
        keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            guard event.modifierFlags.contains(.control),
                  event.charactersIgnoringModifiers == "x" else { return }
            NSApp.terminate(nil)
        }
    }
}
