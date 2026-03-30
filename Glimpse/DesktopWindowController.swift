import AppKit
import SpriteKit

/// Manages one borderless desktop-level window per connected screen,
/// each hosting a mirrored SpriteKit scene of agent characters.
final class DesktopWindowController {

    /// Per-screen resources.
    private struct ScreenEntry {
        let window: NSWindow
        let skView: SKView
        let scene: AgentMonitorScene
    }

    /// Active screen entries keyed by display ID (stable across NSScreen instances).
    private var entries: [CGDirectDisplayID: ScreenEntry] = [:]

    private let sessionMonitor = SessionMonitor()
    private var latestSessions: [SessionMonitor.Session] = []
    private var clickMonitor: Any?
    private var screenObserver: NSObjectProtocol?

    /// Called on the main thread with current sessions — used by AppDelegate for menu bar.
    var onSessionsChanged: (([SessionMonitor.Session]) -> Void)?

    init() {
        setupClickMonitor()
        observeScreenChanges()
        syncScreens()
        startMonitoring()
    }

    deinit {
        if let monitor = clickMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let observer = screenObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        sessionMonitor.stop()
        for entry in entries.values {
            entry.window.orderOut(nil)
        }
    }

    // MARK: - Session Monitoring

    private func startMonitoring() {
        sessionMonitor.onUpdate = { [weak self] sessions in
            guard let self else { return }
            self.latestSessions = sessions
            for entry in self.entries.values {
                entry.scene.updateSessions(sessions)
            }
            self.onSessionsChanged?(sessions)
        }
        sessionMonitor.start()
    }

    // MARK: - Screen Sync

    private func observeScreenChanges() {
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.syncScreens()
        }
    }

    private func syncScreens() {
        let currentScreens = NSScreen.screens
        var currentDisplayIDs = Set<CGDirectDisplayID>()

        for screen in currentScreens {
            let displayID = Self.displayID(for: screen)
            currentDisplayIDs.insert(displayID)

            if let existing = entries[displayID] {
                // Screen still present — update frame if changed
                let frame = screen.frame
                if existing.window.frame != frame {
                    existing.window.setFrame(frame, display: true)
                    existing.scene.size = frame.size
                }
            } else {
                // New screen — create entry
                let entry = makeScreenEntry(for: screen)
                entries[displayID] = entry
                entry.scene.updateSessions(latestSessions)
            }
        }

        // Remove entries for disconnected screens
        let staleIDs = Set(entries.keys).subtracting(currentDisplayIDs)
        for id in staleIDs {
            if let entry = entries.removeValue(forKey: id) {
                entry.window.orderOut(nil)
            }
        }
    }

    private func makeScreenEntry(for screen: NSScreen) -> ScreenEntry {
        let frame = screen.frame

        let win = NSWindow(
            contentRect: frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false,
            screen: screen
        )
        win.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) + 1)
        win.collectionBehavior = [.stationary, .canJoinAllSpaces]
        win.isOpaque = false
        win.hasShadow = false
        win.ignoresMouseEvents = true
        win.backgroundColor = .clear
        win.setFrame(frame, display: false)
        win.orderFrontRegardless()

        let sv = SKView(frame: CGRect(origin: .zero, size: frame.size))
        sv.autoresizingMask = [.width, .height]
        sv.allowsTransparency = true
        sv.preferredFramesPerSecond = 30
        win.contentView?.addSubview(sv)

        let scene = AgentMonitorScene(size: frame.size)
        scene.scaleMode = .resizeFill
        sv.presentScene(scene)

        setupOcclusionObserver(for: win, skView: sv)

        return ScreenEntry(window: win, skView: sv, scene: scene)
    }

    private static func displayID(for screen: NSScreen) -> CGDirectDisplayID {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return screen.deviceDescription[key] as? CGDirectDisplayID ?? 0
    }

    // MARK: - Click Monitor

    private func setupClickMonitor() {
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            self?.handleGlobalClick(event)
        }
    }

    private func handleGlobalClick(_ event: NSEvent) {
        let screenPoint = event.locationInWindow

        for entry in entries.values {
            let windowPoint = entry.window.convertPoint(fromScreen: screenPoint)
            let viewPoint = entry.skView.convert(windowPoint, from: nil)
            let scenePoint = entry.scene.convertPoint(fromView: viewPoint)

            if let node = entry.scene.characterNode(at: scenePoint) {
                entry.scene.activateAppForSession(node.sessionID)
                return
            }
        }
    }

    // MARK: - Power Management

    func setPaused(_ paused: Bool) {
        for entry in entries.values {
            entry.skView.isPaused = paused
        }
    }

    // MARK: - Occlusion

    private func setupOcclusionObserver(for window: NSWindow, skView: SKView) {
        NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeOcclusionStateNotification,
            object: window,
            queue: .main
        ) { _ in
            let visible = window.occlusionState.contains(.visible)
            skView.isPaused = !visible
        }
    }

    // MARK: - App Activation (forwarded from AppDelegate menu)

    func activateAppForSession(_ sessionID: String) {
        entries.values.first?.scene.activateAppForSession(sessionID)
    }
}
