import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate {

    private var desktopWindowController: DesktopWindowController?
    private var keyMonitor: Any?
    private var statusItem: NSStatusItem?
    private var currentSessions: [SessionMonitor.Session] = []
    private var normalIcon: NSImage?
    private var badgedIcon: NSImage?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupKeyboardShortcut()
        setupPowerNotifications()
        DispatchQueue.main.async {
            let controller = DesktopWindowController()
            self.desktopWindowController = controller
            self.setupMenuBarItem()
            controller.onSessionsChanged = { [weak self] sessions in
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

    private func makeIcon(badge: Bool) -> NSImage? {
        guard let baseImage = NSImage(systemSymbolName: "photo.on.rectangle", accessibilityDescription: "Glimpse") else {
            return nil
        }

        let config = NSImage.SymbolConfiguration(pointSize: 16, weight: .regular)
        let configured = baseImage.withSymbolConfiguration(config) ?? baseImage

        guard badge else { return configured }

        let size = configured.size
        let result = NSImage(size: size, flipped: false) { rect in
            configured.draw(in: rect)
            let dotSize: CGFloat = 5
            let dotRect = NSRect(
                x: size.width - dotSize - 0.5,
                y: size.height - dotSize - 0.5,
                width: dotSize,
                height: dotSize
            )
            NSColor.systemOrange.setFill()
            NSBezierPath(ovalIn: dotRect).fill()
            return true
        }
        result.isTemplate = false
        return result
    }

    private func setupMenuBarItem() {
        if statusItem == nil {
            statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            normalIcon = makeIcon(badge: false)
            badgedIcon = makeIcon(badge: true)
            if let button = statusItem?.button {
                button.image = normalIcon
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

        let anyAsking = currentSessions.contains { $0.activity == .asking }
        statusItem?.button?.image = anyAsking ? badgedIcon : normalIcon
    }

    @objc private func menuItemClicked(_ sender: NSMenuItem) {
        guard let sessionID = sender.representedObject as? String else { return }
        desktopWindowController?.activateAppForSession(sessionID)
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
