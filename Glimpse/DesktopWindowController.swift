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

        self.init(window: win)

        let vc = SceneViewController()

        // Wire up view-swap closures BEFORE setting contentViewController,
        // because that triggers viewDidLoad → setupScene → switchToScene.
        vc.onSwitchToSpriteKit = { [weak self] scene in
            self?.swapToSpriteKit(scene: scene)
        }
        vc.onSwitchToSceneKit = { [weak self] in
            self?.swapToSceneKit()
        }

        win.contentViewController = vc
        win.setFrame(screen.frame, display: false)
        self.sceneViewController = vc
    }

    override func showWindow(_ sender: Any?) {
        window?.orderFrontRegardless()
        setupOcclusionObserver()

        // If Pokemon theme was selected during init, the swap couldn't run
        // properly because the view hierarchy wasn't laid out yet.
        // Re-trigger it now that the window is visible and properly sized.
        if let svc = sceneViewController, svc.pokemonScene != nil {
            svc.switchToScene(index: svc.currentSceneIndex)
        }
    }

    // MARK: - View Swapping

    private func swapToSpriteKit(scene: SKScene) {
        guard let window = window else {
            return
        }

        let frame = window.frame

        // Create SKView sized to the WINDOW frame (not contentView which may be zero during init)
        if skView == nil {
            let sv = SKView(frame: CGRect(origin: .zero, size: frame.size))
            sv.autoresizingMask = [.width, .height]
            sv.allowsTransparency = false
            sv.preferredFramesPerSecond = 60
            skView = sv
        }

        guard let sv = skView else { return }

        // Ensure proper frame before presenting scene
        sv.frame = CGRect(origin: .zero, size: frame.size)
        sv.presentScene(scene)

        // Hide SCNView, show SKView. Add SKView directly to window's
        // themeFrame view (not contentView, which IS the SceneViewController's view).
        sceneViewController?.view.isHidden = true
        if sv.superview == nil {
            // Add as sibling of contentView, not child
            if let contentView = window.contentView {
                contentView.superview?.addSubview(sv)
            }
        }
        sv.isHidden = false
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
            self?.skView?.isPaused = !visible
        }
    }
}
