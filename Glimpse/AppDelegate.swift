import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate {

    private var desktopWindowController: DesktopWindowController?
    private var keyMonitor: Any?
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupKeyboardShortcut()
        setupPowerNotifications()
        // Defer window creation one run-loop cycle so NSScreen is fully available.
        // Menu bar setup happens after so it can read the discovered scene list.
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
        // System sleep / wake
        let wsNC = NSWorkspace.shared.notificationCenter
        wsNC.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            self?.desktopWindowController?.sceneViewController?.setSystemSuspended(true)
        }
        wsNC.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.desktopWindowController?.sceneViewController?.setSystemSuspended(false)
        }

        // Screen saver start / stop
        let dnc = DistributedNotificationCenter.default()
        dnc.addObserver(forName: NSNotification.Name("com.apple.screensaver.didstart"), object: nil, queue: .main) { [weak self] _ in
            self?.desktopWindowController?.sceneViewController?.setSystemSuspended(true)
        }
        dnc.addObserver(forName: NSNotification.Name("com.apple.screensaver.didstop"), object: nil, queue: .main) { [weak self] _ in
            self?.desktopWindowController?.sceneViewController?.setSystemSuspended(false)
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

        let themeItem = NSMenuItem(title: "Theme", action: nil, keyEquivalent: "")
        let themeSubmenu = NSMenu(title: "Theme")

        if let scenes = desktopWindowController?.sceneViewController?.availableScenes {
            for (tag, entry) in scenes.enumerated() {
                let item = NSMenuItem(title: entry.displayName, action: #selector(selectScene(_:)), keyEquivalent: "")
                item.tag = tag
                item.target = self
                themeSubmenu.addItem(item)
            }
        }

        themeSubmenu.addItem(NSMenuItem.separator())
        let customItem = NSMenuItem(title: "Import Custom Model...", action: #selector(importCustomModel), keyEquivalent: "")
        customItem.target = self
        themeSubmenu.addItem(customItem)

        themeItem.submenu = themeSubmenu
        menu.addItem(themeItem)

        menu.addItem(NSMenuItem.separator())
        let exitItem = NSMenuItem(title: "Exit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        menu.addItem(exitItem)

        statusItem?.menu = menu
    }

    @objc private func selectScene(_ sender: NSMenuItem) {
        desktopWindowController?.sceneViewController?.switchToScene(index: sender.tag)
    }

    @objc private func importCustomModel() {
        let panel = NSOpenPanel()
        panel.title = "Import 3D Model"
        panel.allowedContentTypes = [
            .init(filenameExtension: "usdz")!,
            .init(filenameExtension: "obj")!,
            .init(filenameExtension: "dae")!,
            .init(filenameExtension: "scn")!,
        ]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        // Bring the app forward so the open panel is visible.
        NSApp.activate(ignoringOtherApps: true)

        guard panel.runModal() == .OK, let url = panel.url else { return }

        guard let svc = desktopWindowController?.sceneViewController else { return }

        do {
            let newIndex = try svc.importCustomModel(from: url)
            // Rebuild menu bar to include the new entry, then switch to it.
            setupMenuBarItem()
            svc.switchToScene(index: newIndex)
        } catch {
            let alert = NSAlert()
            alert.messageText = "Import Failed"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }

    private func setupKeyboardShortcut() {
        keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.modifierFlags.contains(.control) else { return }
            switch event.charactersIgnoringModifiers {
            case "x":
                // Ctrl+X — quit
                NSApp.terminate(nil)
            case "s":
                // Ctrl+S — cycle to next scene
                self?.desktopWindowController?.sceneViewController?.cycleScene()
            default:
                break
            }
        }
    }
}
