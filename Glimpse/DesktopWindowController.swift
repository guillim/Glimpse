import AppKit
import SceneKit
import SpriteKit

/// An NSWindowController that pins a borderless, click-through window
/// just above the macOS desktop layer (below Finder icons).
final class DesktopWindowController: NSWindowController {

    private(set) var sceneViewController: SceneViewController?
    private var skView: SKView?

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
        win.isOpaque = true
        win.hasShadow = false
        win.ignoresMouseEvents = true
        win.backgroundColor = .black

        let vc = SceneViewController()
        win.contentViewController = vc
        win.setFrame(screen.frame, display: false)

        self.init(window: win)
        self.sceneViewController = vc

        setupViewSwapObservers()
    }

    override func showWindow(_ sender: Any?) {
        window?.orderFrontRegardless()
        setupOcclusionObserver()
    }

    // MARK: - View Swapping

    private func setupViewSwapObservers() {
        NotificationCenter.default.addObserver(
            forName: .switchToSpriteKit,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let scene = notification.userInfo?["scene"] as? SKScene else { return }
            self?.swapToSpriteKit(scene: scene)
        }

        NotificationCenter.default.addObserver(
            forName: .switchToSceneKit,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.swapToSceneKit()
        }
    }

    private func swapToSpriteKit(scene: SKScene) {
        guard let window = window else { return }

        // Create SKView if needed
        if skView == nil {
            let sv = SKView(frame: window.contentView?.bounds ?? window.frame)
            sv.autoresizingMask = [.width, .height]
            sv.allowsTransparency = false
            sv.preferredFramesPerSecond = 60
            skView = sv
        }

        guard let sv = skView else { return }
        sv.presentScene(scene)

        // Swap: hide the SceneKit content, overlay SKView
        sceneViewController?.view.isHidden = true
        if sv.superview == nil {
            window.contentView?.addSubview(sv)
        }
        sv.isHidden = false
        sv.frame = window.contentView?.bounds ?? window.frame
    }

    private func swapToSceneKit() {
        skView?.presentScene(nil)
        skView?.isHidden = true
        sceneViewController?.view.isHidden = false
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
            self?.sceneViewController?.setOccluded(!visible)
        }
    }
}
