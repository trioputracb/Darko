import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var activity: NSObjectProtocol?
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Prevent App Nap so the schedule timers stay reliable, without
        // disabling system sleep (timers are re-armed on wake).
        activity = ProcessInfo.processInfo.beginActivity(
            options: .userInitiated,
            reason: "Keep the dark mode schedule timers reliable"
        )

        setupStatusItem()

        // Our own appearance changes → refresh the menu bar icon.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appearanceChanged),
            name: .darkoAppearanceChanged,
            object: nil
        )

        AppearanceController.shared.start()
        HotkeyManager.shared.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let activity {
            ProcessInfo.processInfo.endActivity(activity)
        }
        AppearanceController.shared.stop()
        HotkeyManager.shared.stop()
    }

    // MARK: - Status item

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = Self.iconImage(isDark: AppearanceController.shared.isDarkState)
        item.button?.toolTip = "Darko"
        item.button?.target = self
        item.button?.action = #selector(statusItemClicked)
        statusItem = item
    }

    @objc private func statusItemClicked() {
        guard let button = statusItem?.button else { return }
        if let popover, popover.isShown {
            popover.performClose(nil)
        } else {
            showPopover(relativeTo: button)
        }
    }

    private func showPopover(relativeTo button: NSButton) {
        let popover: NSPopover
        if let existing = self.popover {
            popover = existing
        } else {
            popover = NSPopover()
            popover.behavior = .transient
            popover.contentViewController = ContentViewController()
            self.popover = popover
        }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    @objc private func appearanceChanged() {
        statusItem?.button?.image = Self.iconImage(isDark: AppearanceController.shared.isDarkState)
    }

    static func iconImage(isDark: Bool) -> NSImage? {
        let symbol = isDark ? "moon.circle.fill" : "sun.max.circle.fill"
        let image = NSImage(systemSymbolName: symbol,
                            accessibilityDescription: isDark ? "Dark mode active" : "Light mode active")
        image?.isTemplate = true
        return image
    }
}
