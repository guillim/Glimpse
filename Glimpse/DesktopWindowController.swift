import AppKit
import SpriteKit

/// An NSWindowController that pins a borderless, click-through window
/// just above the macOS desktop layer (below Finder icons).
final class DesktopWindowController: NSWindowController {

    private(set) var skView: SKView?
    private(set) var agentScene: AgentMonitorScene?
    private var clickMonitor: Any?

    convenience init() {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let win = NSWindow(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false,
            screen: screen
        )

        win.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) + 1)
        win.collectionBehavior = [.stationary, .canJoinAllSpaces]
        win.isOpaque = false
        win.hasShadow = false
        win.ignoresMouseEvents = true  // fully click-through, we use global monitor instead
        win.backgroundColor = .clear

        self.init(window: win)
        win.setFrame(screen.frame, display: false)
    }

    override func showWindow(_ sender: Any?) {
        guard let window = window else { return }
        window.orderFrontRegardless()

        let frame = window.frame
        let sv = SKView(frame: CGRect(origin: .zero, size: frame.size))
        sv.autoresizingMask = [.width, .height]
        sv.allowsTransparency = true
        sv.preferredFramesPerSecond = 30
        skView = sv

        if let contentView = window.contentView {
            contentView.addSubview(sv)
        }

        let scene = AgentMonitorScene(size: frame.size)
        scene.scaleMode = .resizeFill
        sv.presentScene(scene)
        agentScene = scene

        setupOcclusionObserver()
        setupClickMonitor()
    }

    // MARK: - Click Monitor

    /// Global event monitor that detects clicks on character nodes.
    /// Works regardless of window level — bypasses macOS desktop click handling.
    private func setupClickMonitor() {
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            self?.handleGlobalClick(event)
        }
    }

    private func handleGlobalClick(_ event: NSEvent) {
        guard let scene = agentScene, let skView = skView else { return }

        let screenPoint = event.locationInWindow
        guard let window = window else { return }
        let windowPoint = window.convertPoint(fromScreen: screenPoint)
        let viewPoint = skView.convert(windowPoint, from: nil)
        let scenePoint = scene.convertPoint(fromView: viewPoint)

        if let node = scene.characterNode(at: scenePoint) {
            scene.activateAppForSession(node.sessionID)
        }
    }

    deinit {
        if let monitor = clickMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    // MARK: - Power Management

    /// Pause/resume rendering when the window is occluded or the system sleeps.
    func setPaused(_ paused: Bool) {
        skView?.isPaused = paused
    }

    // MARK: - Occlusion

    private func setupOcclusionObserver() {
        guard let window = window else { return }
        NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeOcclusionStateNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            let visible = window.occlusionState.contains(.visible)
            self?.skView?.isPaused = !visible
        }
    }
}
