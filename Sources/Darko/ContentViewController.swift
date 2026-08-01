import AppKit
import ServiceManagement

/// Top-down layout container (flipped) so y coordinates run downward.
final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

/// A clean toggle switch drawn from scratch: rounded track + sliding knob.
/// Avoids the native switch's built-in "ON/OFF" label. Toggles on click and
/// fires the target/action, matching the `NSButton` API.
final class ToggleSwitch: NSButton {

    var onColor: NSColor = .controlAccentColor
    var offColor: NSColor = NSColor(white: 0.5, alpha: 0.35)
    var knobColor: NSColor = .white

    private let knobInset: CGFloat = 2

    override var state: NSControl.StateValue {
        didSet { needsDisplay = true }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configure()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func configure() {
        isBordered = false
        setButtonType(.pushOnPushOff)
        title = ""
        wantsLayer = true
        focusRingType = .none
    }

    override func draw(_ dirtyRect: NSRect) {
        let height = bounds.height
        let width = bounds.width

        let track = NSBezierPath(roundedRect: NSRect(x: 0.5, y: 0.5, width: width - 1, height: height - 1),
                                 xRadius: height / 2,
                                 yRadius: height / 2)
        (isOn ? onColor : offColor).setFill()
        track.fill()

        let knobDiameter = height - knobInset * 2
        let knobX = isOn ? width - knobDiameter - knobInset : knobInset
        let knob = NSBezierPath(ovalIn: NSRect(x: knobX, y: knobInset, width: knobDiameter, height: knobDiameter))

        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.25)
        shadow.shadowBlurRadius = 1.5
        shadow.shadowOffset = NSSize(width: 0, height: -0.5)
        shadow.set()
        knobColor.setFill()
        knob.fill()
        NSGraphicsContext.restoreGraphicsState()
    }

    private var isOn: Bool {
        state == .on
    }
}

/// The popover content: toggle button, auto schedule, launch at login, and the
/// global keyboard shortcut recorder. Built with Auto Layout so the popover
/// always sizes itself to fit its content.
final class ContentViewController: NSViewController {

    private let controller = AppearanceController.shared
    private let hotkey = HotkeyManager.shared

    private let contentWidth: CGFloat = 320
    private let sidePadding: CGFloat = 16
    private let rowSpacing: CGFloat = 14
    private let timeStep = 10

    // MARK: - State accessors

    private var isDark: Bool { controller.isDarkState }

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

    private var subtitleText: String {
        if isAutoMode {
            return "\(formatSlot((startMinutes / timeStep) * timeStep)) – \(formatSlot((endMinutes / timeStep) * timeStep))"
        }
        return isDark ? "Dark mode on" : "Light mode on"
    }

    // MARK: - Lifecycle

    override func loadView() {
        view = FlippedView()
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
        refresh()
    }

    @objc private func refresh() {
        view.subviews.forEach { $0.removeFromSuperview() }
        buildUI()
    }

    // MARK: - Layout

    private func buildUI() {
        let stack = NSStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0

        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.topAnchor),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: sidePadding),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -sidePadding),
            stack.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            view.widthAnchor.constraint(equalToConstant: contentWidth)
        ])

        let inner = stack

        addHeader(to: inner)
        inner.addArrangedSubview(separator())
        addSpacer(inner, 14)

        addPrimaryButton(to: inner)
        addSpacer(inner, 14)

        addToggleRow(icon: "clock.arrow.2.circlepath",
                     title: "Auto mode",
                     isOn: isAutoMode,
                     action: #selector(autoModeToggled(_:)),
                     to: inner)
        addSpacer(inner, 14)

        if isAutoMode {
            addScheduleBlock(to: inner)
            addSpacer(inner, 14)
        }

        addToggleRow(icon: "power",
                     title: "Launch at login",
                     isOn: isLaunchAtLogin,
                     action: #selector(launchAtLoginToggled(_:)),
                     to: inner)
        addSpacer(inner, 14)

        addShortcutRow(to: inner)
        addSpacer(inner, 14)
        inner.addArrangedSubview(separator())
        addSpacer(inner, 8)
        addFooter(to: inner)
        addSpacer(inner, 12)

        // Let Auto Layout compute the height, then tell the popover.
        view.layoutSubtreeIfNeeded()
        preferredContentSize = NSSize(width: contentWidth, height: stack.fittingSize.height)
    }

    private func addSpacer(_ stack: NSStackView, _ height: CGFloat) {
        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.heightAnchor.constraint(equalToConstant: height).isActive = true
        spacer.widthAnchor.constraint(equalToConstant: fullWidth).isActive = true
        stack.addArrangedSubview(spacer)
    }

    private func separator() -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        box.translatesAutoresizingMaskIntoConstraints = false
        box.heightAnchor.constraint(equalToConstant: 1).isActive = true
        box.widthAnchor.constraint(equalToConstant: fullWidth).isActive = true
        return box
    }

    /// Width of each top-level row (stack width minus side padding).
    private var fullWidth: CGFloat {
        contentWidth - sidePadding * 2
    }

    // MARK: - Header

    private func addHeader(to stack: NSStackView) {
        let row = NSStackView()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        row.heightAnchor.constraint(equalToConstant: 42).isActive = true
        row.widthAnchor.constraint(equalToConstant: fullWidth).isActive = true

        let icon = imageView("moon.fill", size: 24)
        icon.contentTintColor = isDark ? .systemPurple : .systemOrange
        row.addArrangedSubview(icon)

        let title = label("Darko", size: 13, weight: .semibold)
        row.addArrangedSubview(title)

        let subtitle = label(subtitleText, size: 11, color: .secondaryLabelColor)
        row.addArrangedSubview(subtitle)

        row.addArrangedSubview(NSView()) // spacer

        stack.addArrangedSubview(row)
    }

    // MARK: - Primary toggle button

    private func addPrimaryButton(to stack: NSStackView) {
        let button = NSButton(title: isDark ? "Switch to Light" : "Switch to Dark",
                              target: self,
                              action: #selector(primaryToggleClicked))
        button.translatesAutoresizingMaskIntoConstraints = false
        button.bezelStyle = .rounded
        button.controlSize = .large
        button.image = NSImage(systemSymbolName: isDark ? "sun.max.fill" : "moon.fill",
                               accessibilityDescription: nil)
        button.imagePosition = .imageLeading
        button.contentTintColor = isDark ? .systemOrange : .systemPurple
        button.heightAnchor.constraint(equalToConstant: 34).isActive = true
        button.widthAnchor.constraint(equalToConstant: fullWidth).isActive = true
        stack.addArrangedSubview(button)
    }

    @objc private func primaryToggleClicked() {
        let newMode = !isDark
        Task { await controller.setDark(newMode) }
    }

    // MARK: - Toggle rows

    private func addToggleRow(icon: String,
                              title: String,
                              isOn: Bool,
                              action: Selector,
                              to stack: NSStackView) {
        let row = NSStackView()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        row.heightAnchor.constraint(equalToConstant: 24).isActive = true
        row.widthAnchor.constraint(equalToConstant: fullWidth).isActive = true

        let iconView = imageView(icon, size: 15)
        iconView.contentTintColor = .secondaryLabelColor
        row.addArrangedSubview(iconView)

        row.addArrangedSubview(label(title, size: 13))

        row.addArrangedSubview(NSView()) // spacer

        let checkbox = ToggleSwitch()
        checkbox.translatesAutoresizingMaskIntoConstraints = false
        checkbox.state = isOn ? .on : .off
        checkbox.target = self
        checkbox.action = action
        checkbox.widthAnchor.constraint(equalToConstant: 40).isActive = true
        checkbox.heightAnchor.constraint(equalToConstant: 22).isActive = true
        row.addArrangedSubview(checkbox)

        stack.addArrangedSubview(row)
    }

    @objc private func autoModeToggled(_ sender: NSButton) {
        let enabled = sender.state == .on
        UserDefaults.standard.set(enabled, forKey: "autoMode")
        controller.autoModeChanged(enabled)
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

    private func addScheduleBlock(to stack: NSStackView) {
        let block = NSStackView()
        block.translatesAutoresizingMaskIntoConstraints = false
        block.orientation = .vertical
        block.alignment = .leading
        block.spacing = 8
        block.widthAnchor.constraint(equalToConstant: fullWidth).isActive = true

        let caption = label("DARK MODE SCHEDULE", size: 10, weight: .semibold, color: .secondaryLabelColor)
        block.addArrangedSubview(caption)

        addTimeRow(icon: "moon.fill", title: "Starts",
                   hour: startMinutes / 60, minute: startMinutes % 60, tag: 0, to: block)
        addTimeRow(icon: "sun.max.fill", title: "Ends",
                   hour: endMinutes / 60, minute: endMinutes % 60, tag: 1, to: block)

        let next = label(nextSwitchText, size: 11, color: .secondaryLabelColor)
        block.addArrangedSubview(next)

        stack.addArrangedSubview(block)
    }

    private func addTimeRow(icon: String,
                            title: String,
                            hour: Int,
                            minute: Int,
                            tag: Int,
                            to stack: NSStackView) {
        let row = NSStackView()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        row.heightAnchor.constraint(equalToConstant: 24).isActive = true
        row.widthAnchor.constraint(equalToConstant: fullWidth).isActive = true

        let iconView = imageView(icon, size: 12)
        iconView.contentTintColor = .tertiaryLabelColor
        row.addArrangedSubview(iconView)

        row.addArrangedSubview(label(title, size: 12))

        row.addArrangedSubview(NSView()) // spacer

        let hours = NSPopUpButton(frame: .zero, pullsDown: false)
        hours.translatesAutoresizingMaskIntoConstraints = false
        hours.addItems(withTitles: (0..<24).map { String(format: "%02d", $0) })
        hours.selectItem(at: max(0, min(23, hour)))
        hours.tag = tag
        hours.target = self
        hours.action = #selector(hourChanged(_:))
        hours.widthAnchor.constraint(equalToConstant: 56).isActive = true
        row.addArrangedSubview(hours)

        let colon = label(":", size: 12, color: .secondaryLabelColor)
        row.addArrangedSubview(colon)

        let minutes = NSPopUpButton(frame: .zero, pullsDown: false)
        minutes.translatesAutoresizingMaskIntoConstraints = false
        let minuteItems = stride(from: 0, to: 60, by: timeStep).map { String(format: "%02d", $0) }
        minutes.addItems(withTitles: minuteItems)
        minutes.selectItem(at: max(0, minuteItems.firstIndex(
            of: String(format: "%02d", (minute / timeStep) * timeStep)) ?? 0))
        minutes.tag = tag
        minutes.target = self
        minutes.action = #selector(minuteChanged(_:))
        minutes.widthAnchor.constraint(equalToConstant: 56).isActive = true
        row.addArrangedSubview(minutes)

        stack.addArrangedSubview(row)
    }

    @objc private func hourChanged(_ sender: NSPopUpButton) {
        guard sender.indexOfSelectedItem >= 0 else { return }
        let defaults = UserDefaults.standard
        if sender.tag == 0 {
            defaults.set(sender.indexOfSelectedItem, forKey: "startHour")
        } else {
            defaults.set(sender.indexOfSelectedItem, forKey: "endHour")
        }
        controller.scheduleChanged()
    }

    @objc private func minuteChanged(_ sender: NSPopUpButton) {
        guard sender.indexOfSelectedItem >= 0 else { return }
        let minutes = sender.indexOfSelectedItem * timeStep
        let defaults = UserDefaults.standard
        if sender.tag == 0 {
            defaults.set(minutes, forKey: "startMinute")
        } else {
            defaults.set(minutes, forKey: "endMinute")
        }
        controller.scheduleChanged()
    }

    // MARK: - Keyboard shortcut

    private func addShortcutRow(to stack: NSStackView) {
        let row = NSStackView()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        row.heightAnchor.constraint(equalToConstant: 24).isActive = true
        row.widthAnchor.constraint(equalToConstant: fullWidth).isActive = true

        let iconView = imageView("command", size: 15)
        iconView.contentTintColor = .secondaryLabelColor
        row.addArrangedSubview(iconView)

        row.addArrangedSubview(label("Keyboard shortcut", size: 13))

        row.addArrangedSubview(NSView()) // spacer

        if hotkey.isRecording {
            let hint = label(hotkey.needsModifierHint ? "Hold ⌘⌥⌃⇧ + key" : "Press keys…",
                             size: 11,
                             color: .systemOrange)
            row.addArrangedSubview(hint)

            let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancelRecording))
            cancel.bezelStyle = .inline
            cancel.font = .systemFont(ofSize: 11)
            row.addArrangedSubview(cancel)
        } else {
            let shortcut = NSButton(title: hotkey.shortcutText, target: self, action: #selector(startRecording))
            shortcut.translatesAutoresizingMaskIntoConstraints = false
            shortcut.bezelStyle = .inline
            shortcut.font = .monospacedSystemFont(ofSize: 11, weight: .medium)
            shortcut.toolTip = "Click to set a global shortcut"
            shortcut.widthAnchor.constraint(greaterThanOrEqualToConstant: 48).isActive = true
            row.addArrangedSubview(shortcut)

            if hotkey.hasShortcut {
                let remove = NSButton(image: NSImage(systemSymbolName: "xmark.circle.fill",
                                                     accessibilityDescription: "Remove shortcut")!,
                                      target: self,
                                      action: #selector(clearShortcut))
                remove.isBordered = false
                remove.contentTintColor = .secondaryLabelColor
                remove.toolTip = "Remove shortcut"
                remove.widthAnchor.constraint(equalToConstant: 20).isActive = true
                row.addArrangedSubview(remove)
            }
        }

        stack.addArrangedSubview(row)
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

    private func addFooter(to stack: NSStackView) {
        let row = NSStackView()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.orientation = .horizontal
        row.alignment = .centerY
        row.heightAnchor.constraint(equalToConstant: 32).isActive = true
        row.widthAnchor.constraint(equalToConstant: fullWidth).isActive = true

        let version = label(appVersion, size: 11, color: .tertiaryLabelColor)
        row.addArrangedSubview(version)

        row.addArrangedSubview(NSView()) // spacer

        let quit = NSButton(title: "Quit", target: self, action: #selector(quitClicked))
        quit.isBordered = false
        quit.font = .systemFont(ofSize: 12)
        row.addArrangedSubview(quit)

        stack.addArrangedSubview(row)
    }

    private var appVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String)
            .map { "v\($0)" } ?? ""
    }

    @objc private func quitClicked() {
        NSApp.terminate(nil)
    }

    // MARK: - Helpers

    private func label(_ text: String, size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor = .labelColor) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = .systemFont(ofSize: size, weight: weight)
        field.textColor = color
        field.lineBreakMode = .byTruncatingTail
        return field
    }

    private func imageView(_ symbol: String, size: CGFloat) -> NSImageView {
        let view = NSImageView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        view.widthAnchor.constraint(equalToConstant: size).isActive = true
        view.heightAnchor.constraint(equalToConstant: size).isActive = true
        return view
    }
}
