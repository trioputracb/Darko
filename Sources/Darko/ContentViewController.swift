import AppKit
import ServiceManagement

/// Top-down layout container (flipped) so y coordinates run downward.
final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

/// The popover content: toggle button, auto schedule, launch at login, and the
/// global keyboard shortcut recorder.
final class ContentViewController: NSViewController {

    private let controller = AppearanceController.shared
    private let hotkey = HotkeyManager.shared

    private let contentWidth: CGFloat = 300
    private let padding: CGFloat = 16
    private let timeStep = 10

    private var cursorY: CGFloat = 0

    private var timeSlots: [Int] { stride(from: 0, to: 24 * 60, by: timeStep).map { $0 } }

    // MARK: - State accessors

    private var isDark: Bool {
        controller.isDarkState
    }

    private var isAutoMode: Bool {
        UserDefaults.standard.bool(forKey: "autoMode")
    }

    private var isLaunchAtLogin: Bool {
        SMAppService.mainApp.status == .enabled
    }

    private var startMinutes: Int {
        UserDefaults.standard.integer(forKey: "startHour") * 60
            + UserDefaults.standard.integer(forKey: "startMinute")
    }

    private var endMinutes: Int {
        UserDefaults.standard.integer(forKey: "endHour") * 60
            + UserDefaults.standard.integer(forKey: "endMinute")
    }

    private func formatSlot(_ minutes: Int) -> String {
        String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }

    private var nextSwitchText: String {
        let cal = Calendar.current
        let now = cal.component(.hour, from: Date()) * 60 + cal.component(.minute, from: Date())
        let start = (startMinutes / timeStep) * timeStep
        let end = (endMinutes / timeStep) * timeStep
        let dark = start < end ? (now >= start && now < end) : (now >= start || now < end)
        return dark
            ? String(format: "Switches to light at %@", formatSlot(end))
            : String(format: "Switches to dark at %@", formatSlot(start))
    }

    // MARK: - Lifecycle

    override func loadView() {
        view = FlippedView(frame: NSRect(x: 0, y: 0, width: contentWidth, height: 100))
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(refresh),
            name: .darkoAppearanceChanged,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(refresh),
            name: .darkoScheduleChanged,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(refresh),
            name: .darkoShortcutChanged,
            object: nil
        )

        buildUI()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        buildUI()
    }

    @objc private func refresh() {
        buildUI()
    }

    // MARK: - Layout

    private func buildUI() {
        view.subviews.forEach { $0.removeFromSuperview() }
        cursorY = 0

        headerSection()
        divider()
        primarySection()
        rowSpacing()

        toggleRow(icon: "clock.arrow.2.circlepath",
                  title: "Auto mode",
                  isOn: isAutoMode,
                  action: #selector(autoModeToggled(_:)))
        rowSpacing()

        if isAutoMode {
            scheduleSection()
        }

        toggleRow(icon: "power",
                  title: "Launch at login",
                  isOn: isLaunchAtLogin,
                  action: #selector(launchAtLoginToggled(_:)))
        rowSpacing()

        shortcutSection()
        divider()
        footerSection()

        let height = cursorY
        view.frame = NSRect(x: 0, y: 0, width: contentWidth, height: height)
        preferredContentSize = NSSize(width: contentWidth, height: height)
    }

    /// Registers the next block at the current cursor and advances it.
    @discardableResult
    private func place(_ subview: NSView, height: CGFloat, inset: CGFloat = 0) -> NSView {
        subview.frame = NSRect(x: padding + inset,
                               y: cursorY,
                               width: contentWidth - padding * 2 - inset * 2,
                               height: height)
        view.addSubview(subview)
        cursorY += height
        return subview
    }

    private func rowSpacing(_ space: CGFloat = 14) {
        cursorY += space
    }

    private func divider() {
        let line = NSBox()
        line.boxType = .separator
        line.frame = NSRect(x: 0, y: cursorY, width: contentWidth, height: 1)
        view.addSubview(line)
        cursorY += 1
    }

    // MARK: - Header

    private func headerSection() {
        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: isDark ? "moon.fill" : "sun.max.fill",
                             accessibilityDescription: nil)
        icon.contentTintColor = isDark ? .systemPurple : .systemOrange
        icon.frame = NSRect(x: padding, y: cursorY + 3, width: 22, height: 22)
        view.addSubview(icon)

        let title = NSTextField(labelWithString: "Darko")
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        title.frame = NSRect(x: padding + 30, y: cursorY, width: 100, height: 16)
        view.addSubview(title)

        let subtitle = NSTextField(labelWithString: subtitleText)
        subtitle.font = .systemFont(ofSize: 11)
        subtitle.textColor = .secondaryLabelColor
        subtitle.lineBreakMode = .byTruncatingTail
        subtitle.frame = NSRect(x: padding + 30, y: cursorY + 16, width: 200, height: 14)
        view.addSubview(subtitle)

        cursorY += 30
        rowSpacing(12)
    }

    private var subtitleText: String {
        if isAutoMode {
            return "\(formatSlot((startMinutes / timeStep) * timeStep)) – \(formatSlot((endMinutes / timeStep) * timeStep))"
        }
        return isDark ? "Dark mode on" : "Light mode on"
    }

    // MARK: - Primary toggle button

    private func primarySection() {
        let button = NSButton(title: isDark ? "Switch to Light" : "Switch to Dark",
                              target: self,
                              action: #selector(primaryToggleClicked))
        button.bezelStyle = .rounded
        button.controlSize = .large
        button.image = NSImage(systemSymbolName: isDark ? "sun.max.fill" : "moon.fill",
                               accessibilityDescription: nil)
        button.imagePosition = .imageLeading
        button.contentTintColor = isDark ? .systemOrange : .systemPurple
        place(button, height: 34)
        rowSpacing(14)
    }

    @objc private func primaryToggleClicked() {
        let newMode = !isDark
        Task { await controller.setDark(newMode) }
    }

    // MARK: - Toggle rows

    private func toggleRow(icon: String, title: String, isOn: Bool, action: Selector) {
        let iconView = NSImageView()
        iconView.image = NSImage(systemSymbolName: icon, accessibilityDescription: nil)
        iconView.contentTintColor = .secondaryLabelColor
        iconView.frame = NSRect(x: 0, y: 4, width: 15, height: 15)
        iconView.frame.origin.x = 0

        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 13)
        label.frame = NSRect(x: 24, y: 2, width: contentWidth - padding * 2 - 24 - 60, height: 17)

        let checkbox = NSButton()
        checkbox.setButtonType(.switch)
        checkbox.state = isOn ? .on : .off
        checkbox.tag = -1
        checkbox.target = self
        checkbox.action = action
        checkbox.frame = NSRect(x: contentWidth - padding * 2 - 42, y: 0, width: 42, height: 20)

        let container = FlippedView()
        container.addSubview(iconView)
        container.addSubview(label)
        container.addSubview(checkbox)
        place(container, height: 22)
    }

    @objc private func autoModeToggled(_ sender: NSButton) {
        controller.autoModeChanged(sender.state == .on)
    }

    @objc private func launchAtLoginToggled(_ sender: NSButton) {
        setLaunchAtLogin(sender.state == .on)
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            #if DEBUG
            print("Launch at login \(enabled ? "register" : "unregister") failed: \(error)")
            #endif
        }
    }

    // MARK: - Schedule

    private func scheduleSection() {
        let container = FlippedView()
        let innerX: CGFloat = 30
        let innerWidth = contentWidth - padding * 2 - innerX

        let caption = NSTextField(labelWithString: "DARK MODE SCHEDULE")
        caption.font = .systemFont(ofSize: 10, weight: .semibold)
        caption.textColor = .secondaryLabelColor
        caption.frame = NSRect(x: innerX, y: 0, width: innerWidth, height: 14)
        container.addSubview(caption)

        let (startRow, startPopup) = makeTimeRow(icon: "moon.fill", label: "Starts",
                                                 selected: startMinutes, tag: 0, width: innerWidth)
        startRow.frame = NSRect(x: innerX, y: 22, width: innerWidth, height: 24)
        startPopup.tag = 0
        container.addSubview(startRow)

        let (endRow, endPopup) = makeTimeRow(icon: "sun.max.fill", label: "Ends",
                                             selected: endMinutes, tag: 1, width: innerWidth)
        endRow.frame = NSRect(x: innerX, y: 54, width: innerWidth, height: 24)
        endPopup.tag = 1
        container.addSubview(endRow)

        let next = NSTextField(labelWithString: nextSwitchText)
        next.font = .systemFont(ofSize: 11)
        next.textColor = .secondaryLabelColor
        next.lineBreakMode = .byTruncatingTail
        next.frame = NSRect(x: innerX, y: 86, width: innerWidth, height: 14)
        container.addSubview(next)

        place(container, height: 104)
        rowSpacing(14)
    }

    private func makeTimeRow(icon: String, label: String, selected: Int, tag: Int, width: CGFloat)
        -> (NSView, NSPopUpButton) {
        let row = FlippedView()

        let iconView = NSImageView()
        iconView.image = NSImage(systemSymbolName: icon, accessibilityDescription: nil)
        iconView.contentTintColor = .tertiaryLabelColor
        iconView.frame = NSRect(x: 0, y: 5, width: 12, height: 12)
        row.addSubview(iconView)

        let labelView = NSTextField(labelWithString: label)
        labelView.font = .systemFont(ofSize: 12)
        labelView.frame = NSRect(x: 18, y: 3, width: 80, height: 16)
        row.addSubview(labelView)

        let popup = NSPopUpButton(frame: NSRect(x: width - 90, y: 0, width: 90, height: 22), pullsDown: false)
        popup.addItems(withTitles: timeSlots.map { formatSlot($0) })
        popup.selectItem(at: max(0, timeSlots.firstIndex(of: (selected / timeStep) * timeStep) ?? 0))
        popup.tag = tag
        popup.target = self
        popup.action = #selector(timeChanged(_:))
        row.addSubview(popup)

        return (row, popup)
    }

    @objc private func timeChanged(_ sender: NSPopUpButton) {
        guard sender.indexOfSelectedItem >= 0 else { return }
        let minutes = timeSlots[sender.indexOfSelectedItem]
        let defaults = UserDefaults.standard
        if sender.tag == 0 {
            defaults.set(minutes / 60, forKey: "startHour")
            defaults.set(minutes % 60, forKey: "startMinute")
        } else {
            defaults.set(minutes / 60, forKey: "endHour")
            defaults.set(minutes % 60, forKey: "endMinute")
        }
        controller.scheduleChanged()
    }

    // MARK: - Keyboard shortcut

    private func shortcutSection() {
        let container = FlippedView()

        let iconView = NSImageView()
        iconView.image = NSImage(systemSymbolName: "command", accessibilityDescription: nil)
        iconView.contentTintColor = .secondaryLabelColor
        iconView.frame = NSRect(x: 0, y: 4, width: 15, height: 15)
        container.addSubview(iconView)

        let label = NSTextField(labelWithString: "Keyboard shortcut")
        label.font = .systemFont(ofSize: 13)
        label.frame = NSRect(x: 24, y: 2, width: 150, height: 17)
        container.addSubview(label)

        if hotkey.isRecording {
            let hint = NSTextField(labelWithString: hotkey.needsModifierHint ? "Hold ⌘⌥⌃⇧ + key" : "Press keys…")
            hint.font = .systemFont(ofSize: 11)
            hint.textColor = .systemOrange
            hint.frame = NSRect(x: contentWidth - padding * 2 - 175, y: 4, width: 100, height: 14)
            container.addSubview(hint)

            let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancelRecording))
            cancel.bezelStyle = .inline
            cancel.font = .systemFont(ofSize: 11)
            cancel.frame = NSRect(x: contentWidth - padding * 2 - 60, y: 0, width: 60, height: 22)
            container.addSubview(cancel)
        } else {
            let shortcut = NSButton(title: hotkey.shortcutText, target: self, action: #selector(startRecording))
            shortcut.bezelStyle = .inline
            shortcut.font = .monospacedSystemFont(ofSize: 11, weight: .medium)
            shortcut.toolTip = "Click to set a global shortcut"
            let width = max(50, min(120, shortcut.title.size(withAttributes: [
                .font: shortcut.font as Any
            ]).width + 20))
            shortcut.frame = NSRect(x: contentWidth - padding * 2 - width - (hotkey.hasShortcut ? 24 : 0),
                                    y: 0, width: width, height: 22)
            container.addSubview(shortcut)

            if hotkey.hasShortcut {
                let remove = NSButton(image: NSImage(systemSymbolName: "xmark.circle.fill",
                                                     accessibilityDescription: "Remove shortcut")!,
                                      target: self,
                                      action: #selector(clearShortcut))
                remove.isBordered = false
                remove.contentTintColor = .secondaryLabelColor
                remove.toolTip = "Remove shortcut"
                remove.frame = NSRect(x: contentWidth - padding * 2 - 18, y: 1, width: 20, height: 20)
                container.addSubview(remove)
            }
        }

        place(container, height: 22)
        rowSpacing(14)
    }

    @objc private func startRecording() {
        hotkey.startRecording()
    }

    @objc private func cancelRecording() {
        hotkey.cancelRecording()
    }

    @objc private func clearShortcut() {
        hotkey.clearShortcut()
    }

    // MARK: - Footer

    private func footerSection() {
        let version = NSTextField(labelWithString: appVersion)
        version.font = .systemFont(ofSize: 11)
        version.textColor = .tertiaryLabelColor
        version.frame = NSRect(x: 0, y: 6, width: 60, height: 14)
        view.addSubview(version)

        let quit = NSButton(title: "Quit", target: self, action: #selector(quitClicked))
        quit.isBordered = false
        quit.font = .systemFont(ofSize: 12)
        quit.frame = NSRect(x: contentWidth - padding - 40, y: 2, width: 40, height: 20)
        view.addSubview(quit)

        cursorY += 28
    }

    private var appVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String)
            .map { "v\($0)" } ?? ""
    }

    @objc private func quitClicked() {
        NSApp.terminate(nil)
    }
}
