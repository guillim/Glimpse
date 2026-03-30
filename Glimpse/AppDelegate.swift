import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate {

    private var desktopWindowController: DesktopWindowController?
    private var keyMonitor: Any?
    private var statusItem: NSStatusItem?
    private var currentSessions: [SessionMonitor.Session] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupKeyboardShortcut()
        setupPowerNotifications()
        DispatchQueue.main.async {
            self.desktopWindowController = DesktopWindowController()
            self.desktopWindowController?.showWindow(nil)
            self.setupMenuBarItem()
            self.desktopWindowController?.agentScene?.onSessionsChanged = { [weak self] sessions in
                self?.currentSessions = sessions
                self?.rebuildMenu()
            }
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

        rebuildMenu()
    }

    private func rebuildMenu() {
        let menu = NSMenu()

        if currentSessions.isEmpty {
            let noAgents = NSMenuItem(title: "No agents active", action: nil, keyEquivalent: "")
            noAgents.isEnabled = false
            menu.addItem(noAgents)
        } else {
            for session in currentSessions {
                let activityLabel = activityString(session.activity)
                let isAsking = session.activity == .asking

                let title = "\(session.projectName)  \(activityLabel)\(isAsking ? "  🔔" : "")"
                let item = NSMenuItem(title: title, action: #selector(menuItemClicked(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = session.id
                menu.addItem(item)
            }
        }

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Exit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: ""))
        statusItem?.menu = menu
    }

    @objc private func menuItemClicked(_ sender: NSMenuItem) {
        guard let sessionID = sender.representedObject as? String else { return }
        desktopWindowController?.agentScene?.activateAppForSession(sessionID)
    }

    private func activityString(_ activity: SessionMonitor.Activity) -> String {
        switch activity {
        case .reading:    return "reading"
        case .writing:    return "writing"
        case .running:    return "running"
        case .testing:    return "testing"
        case .building:   return "building"
        case .committing: return "committing"
        case .thinking:   return "thinking"
        case .processing: return "processing"
        case .spawning:   return "spawning"
        case .searching:  return "searching"
        case .asking:     return "asking"
        case .done:       return "done"
        case .sleeping:   return "idle"
        }
    }

    private func setupKeyboardShortcut() {
        keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            guard event.modifierFlags.contains(.control),
                  event.charactersIgnoringModifiers == "x" else { return }
            NSApp.terminate(nil)
        }
    }
}
