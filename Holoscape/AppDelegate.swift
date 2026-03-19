import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate {

    private var desktopWindowController: DesktopWindowController?
    private var keyMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupKeyboardShortcut()
        // Defer window creation one run-loop cycle so NSScreen is fully available
        DispatchQueue.main.async {
            self.desktopWindowController = DesktopWindowController()
            self.desktopWindowController?.showWindow(nil)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let monitor = keyMonitor { NSEvent.removeMonitor(monitor) }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ app: NSApplication) -> Bool {
        return false
    }

    // MARK: - Private

    private func setupKeyboardShortcut() {
        keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            // Ctrl+X
            if event.modifierFlags.contains(.control) && event.charactersIgnoringModifiers == "x" {
                NSApp.terminate(nil)
            }
        }
    }
}
