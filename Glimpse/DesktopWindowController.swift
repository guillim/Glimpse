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
    private var screenObserver: NSObjectProtocol?
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var globalClickMonitor: Any?

    /// Timer that drops frame rate back to baseline after a boost.
    private var fpsDropTimer: Timer?
    private static let baselineFPS = 3
    private static let boostFPS = 30
    /// How long to hold the boosted frame rate after a change (covers longest transition).
    private static let boostDuration: TimeInterval = 2.0

    /// Called on the main thread with current sessions — used by AppDelegate for menu bar.
    var onSessionsChanged: (([SessionMonitor.Session]) -> Void)?

    init() {
        observeScreenChanges()
        syncScreens()
        startMonitoring()
        setupEventTap()
    }

    deinit {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        if let monitor = globalClickMonitor { NSEvent.removeMonitor(monitor) }
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
            if sessions != self.latestSessions {
                self.boostFrameRate()
            }
            self.latestSessions = sessions
            for entry in self.entries.values {
                entry.scene.updateSessions(sessions)
            }
            self.onSessionsChanged?(sessions)
        }
        sessionMonitor.start()
    }

    // MARK: - Adaptive Frame Rate

    /// Temporarily boost all SKViews to 30fps for smooth animations, then drop back.
    private func boostFrameRate() {
        fpsDropTimer?.invalidate()
        for entry in entries.values {
            entry.skView.preferredFramesPerSecond = Self.boostFPS
        }
        fpsDropTimer = Timer.scheduledTimer(withTimeInterval: Self.boostDuration, repeats: false) { [weak self] _ in
            guard let self else { return }
            for entry in self.entries.values {
                entry.skView.preferredFramesPerSecond = Self.baselineFPS
            }
        }
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
        sv.preferredFramesPerSecond = Self.baselineFPS
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

    // MARK: - Event Tap (click interception)

    /// Installs a CGEventTap to intercept left-clicks before they reach the
    /// desktop.  If the click lands on a character we consume it (preventing
    /// "click wallpaper to show desktop") and activate the session's app.
    /// Falls back to a global monitor if accessibility permissions are missing.
    private func setupEventTap() {
        let mask = CGEventMask(1 << CGEventType.leftMouseDown.rawValue)
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: DesktopWindowController.eventTapCallback,
            userInfo: selfPtr
        ) else {
            setupGlobalClickMonitor()
            return
        }

        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    /// C-compatible callback for the CGEventTap.
    private static let eventTapCallback: CGEventTapCallBack = { _, type, event, refcon in
        guard let refcon else { return Unmanaged.passUnretained(event) }

        // macOS may temporarily disable taps under load — re-enable.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            return Unmanaged.passUnretained(event)
        }

        let controller = Unmanaged<DesktopWindowController>.fromOpaque(refcon).takeUnretainedValue()

        // Convert CG coordinates (top-left origin) → AppKit (bottom-left origin).
        let cgLocation = event.location
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let screenPoint = NSPoint(x: cgLocation.x, y: primaryHeight - cgLocation.y)

        if controller.characterHit(at: screenPoint) {
            return nil  // consume — desktop never sees this click
        }
        return Unmanaged.passUnretained(event)
    }

    /// Fallback when CGEventTap isn't available (no accessibility permissions).
    /// Activates the app but cannot prevent "show desktop".
    private func setupGlobalClickMonitor() {
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            let screenPoint = event.locationInWindow  // screen coords for global monitors
            _ = self?.characterHit(at: screenPoint)
        }
    }

    /// Check if `screenPoint` (AppKit coordinates) hits a character.
    /// If so, activate the session's app and return `true`.
    private func characterHit(at screenPoint: NSPoint) -> Bool {
        for entry in entries.values {
            let windowPoint = entry.window.convertPoint(fromScreen: screenPoint)
            let viewPoint = entry.skView.convert(windowPoint, from: nil)
            let scenePoint = entry.scene.convertPoint(fromView: viewPoint)
            if let node = entry.scene.characterNode(at: scenePoint) {
                entry.scene.activateAppForSession(node.sessionID)
                return true
            }
        }
        return false
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
