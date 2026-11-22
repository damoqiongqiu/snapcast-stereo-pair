import AppKit
import Foundation

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var instanceLock: SingleInstanceLock?

    func applicationWillFinishLaunching(_ notification: Notification) {
        if activateExistingInstance() {
            NSApp.terminate(nil)
            return
        }

        let lockURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Snapcast/run/gui.lock")
        instanceLock = SingleInstanceLock(url: lockURL)
        guard instanceLock != nil else {
            _ = activateExistingInstance()
            NSApp.terminate(nil)
            return
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = NSApp.setActivationPolicy(.regular)
        DispatchQueue.main.async {
            self.activateMainWindow()
        }
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        activateMainWindow()
        return true
    }

    private func activateExistingInstance() -> Bool {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier,
              let running = NSRunningApplication.runningApplications(
                withBundleIdentifier: bundleIdentifier
              ).first(where: {
                $0.processIdentifier != ProcessInfo.processInfo.processIdentifier
              }) else {
            return false
        }
        running.activate(options: [.activateAllWindows])
        return true
    }

    private func activateMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.canBecomeMain }) {
            window.deminiaturize(nil)
            window.makeKeyAndOrderFront(nil)
            return
        }
        openWindowFromMenu()
        DispatchQueue.main.async {
            let window = NSApp.windows.first(where: { $0.canBecomeMain })
            window?.deminiaturize(nil)
            window?.makeKeyAndOrderFront(nil)
        }
    }

    private func openWindowFromMenu() {
        guard let mainMenu = NSApp.mainMenu,
              let item = menuItem(
                  titled: "MacBook Stereo Pair",
                  in: mainMenu
              ),
              let action = item.action else {
            return
        }
        NSApp.sendAction(action, to: item.target, from: item)
    }

    private func menuItem(titled title: String, in menu: NSMenu) -> NSMenuItem? {
        for item in menu.items {
            if item.title == title, item.action != nil {
                return item
            }
            if let submenu = item.submenu,
               let match = menuItem(titled: title, in: submenu) {
                return match
            }
        }
        return nil
    }
}
