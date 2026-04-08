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
        guard let baseImage = NSImage(named: "MenuBarIcon") else {
            return nil
        }
        baseImage.isTemplate = true

        guard badge else { return baseImage }

        let size = baseImage.size
        let result = NSImage(size: size, flipped: false) { rect in
            baseImage.draw(in: rect)
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
                let isAsking = session.activity == .asking

                let detail: String
                if isAsking, let q = session.lastAssistantText, !q.isEmpty {
                    let oneLine = q.components(separatedBy: .newlines).first ?? q
                    let trimmed = oneLine.trimmingCharacters(in: .whitespacesAndNewlines)
                    let truncated = trimmed.count > 40 ? String(trimmed.prefix(39)) + "…" : trimmed
                    detail = " — 🔔 \(truncated)"
                } else if isAsking {
                    detail = " — 🔔"
                } else if !session.summary.isEmpty {
                    let oneLine = session.summary.components(separatedBy: .newlines).first ?? session.summary
                    let trimmed = oneLine.trimmingCharacters(in: .whitespacesAndNewlines)
                    let truncated = trimmed.count > 40 ? String(trimmed.prefix(39)) + "…" : trimmed
                    detail = " — \(truncated)"
                } else {
                    detail = ""
                }

                let title = "\(session.projectName)\(detail)"
                let item = NSMenuItem(title: title, action: #selector(menuItemClicked(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = session.id

                let bodyColor: NSColor
                switch CharacterStyle.current {
                case .kawaii:
                    bodyColor = CharacterGenerator.traits(for: session.id).bodyColor
                case .starwars:
                    bodyColor = StarWarsCharacterGenerator.color(for: session.id)
                case .demonslayer:
                    bodyColor = DemonSlayerCharacterGenerator.color(for: session.id)
                case .onepiece:
                    bodyColor = OnePieceCharacterGenerator.color(for: session.id)
                case .dragonball:
                    bodyColor = DragonBallCharacterGenerator.color(for: session.id)
                case .theoffice:
                    bodyColor = OfficeCharacterGenerator.color(for: session.id)
                case .marvel:
                    bodyColor = MarvelCharacterGenerator.color(for: session.id)
                }
                let dot = NSAttributedString(string: "● ", attributes: [.foregroundColor: bodyColor, .font: NSFont.systemFont(ofSize: 14)])
                let text = NSAttributedString(string: title, attributes: [.font: NSFont.menuFont(ofSize: 0)])
                let combined = NSMutableAttributedString()
                combined.append(dot)
                combined.append(text)
                item.attributedTitle = combined

                menu.addItem(item)
            }
        }

        menu.addItem(.separator())

        // Style submenu
        let styleMenu = NSMenu()
        for style in CharacterStyle.allCases {
            let item = NSMenuItem(title: style.displayName, action: #selector(styleSelected(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = style.rawValue
            if style == CharacterStyle.current {
                item.state = .on
            }
            styleMenu.addItem(item)
        }
        let styleItem = NSMenuItem(title: "Style", action: nil, keyEquivalent: "")
        styleItem.submenu = styleMenu
        menu.addItem(styleItem)

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

    @objc private func styleSelected(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let style = CharacterStyle(rawValue: raw) else { return }
        CharacterStyle.current = style
        rebuildMenu()
    }

    private func setupKeyboardShortcut() {
        keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            guard event.modifierFlags.contains(.control),
                  event.charactersIgnoringModifiers == "x" else { return }
            NSApp.terminate(nil)
        }
    }
}
