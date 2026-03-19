import AppKit
import SceneKit

/// An NSWindowController that pins a borderless, click-through window
/// just above the macOS desktop layer (below Finder icons).
final class DesktopWindowController: NSWindowController {

    convenience init() {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let win = NSWindow(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false,
            screen: screen
        )

        // Just above the desktop wallpaper, below Finder icons and all other windows
        win.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) + 1)

        win.collectionBehavior = [
            .stationary,
            .canJoinAllSpaces
        ]

        win.isOpaque = true
        win.hasShadow = false
        win.ignoresMouseEvents = true
        win.backgroundColor = .black

        let vc = SceneViewController()
        win.contentViewController = vc
        // Reset frame — contentViewController may resize the window to the vc's preferredContentSize
        win.setFrame(screen.frame, display: false)

        self.init(window: win)
    }

    override func showWindow(_ sender: Any?) {
        window?.orderFrontRegardless()
    }
}
