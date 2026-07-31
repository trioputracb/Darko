import AppKit

/// Single source of truth for the appearance and the automatic schedule.
///
/// Owns the daily toggle timers, re-arms them on wake, and keeps in sync with
/// appearance changes made outside the app (System Settings, shortcuts…).
/// The UI persists settings via `@AppStorage`; this controller re-reads them
/// from `UserDefaults` and writes `isDark`, observed by the menu bar icon.
@MainActor
final class AppearanceController {

    static let shared = AppearanceController()
    private init() {}

    private let defaults = UserDefaults.standard
    private var startTimer: Timer?
    private var endTimer: Timer?

    private enum Key {
        static let isDark = "isDark"
        static let autoMode = "autoMode"
        static let startHour = "startHour"
        static let startMinute = "startMinute"
        static let endHour = "endHour"
        static let endMinute = "endMinute"
    }

    /// Current dark-mode state, as persisted.
    var isDarkState: Bool {
        defaults.bool(forKey: Key.isDark)
    }

    // MARK: - Lifecycle

    func start() {
        // Align the persisted state with the real appearance at launch.
        defaults.set(AppleScriptManager.isSystemDark, forKey: Key.isDark)

        // Appearance changed outside the app → refresh the icon.
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(systemAppearanceChanged),
            name: Notification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil
        )

        // On wake the timers are stale: re-arm them.
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(systemDidWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )

        if defaults.bool(forKey: Key.autoMode) {
            scheduleTimers()
        }
    }

    func stop() {
        cancelTimers()
    }

    // MARK: - Public actions

    /// Manual toggle. Updates the persisted state only on success.
    @discardableResult
    func setDark(_ enabled: Bool) async -> Bool {
        let success = await AppleScriptManager.setDarkMode(enabled)
        if success {
            defaults.set(enabled, forKey: Key.isDark)
            NotificationCenter.default.post(name: .darkoAppearanceChanged, object: nil)
        }
        return success
    }

    /// Toggle triggered by the global keyboard shortcut.
    func toggleFromHotkey() {
        let target = !defaults.bool(forKey: Key.isDark)
        Task { await setDark(target) }
    }

    /// The user (de)activated automatic mode.
    func autoModeChanged(_ enabled: Bool) {
        if enabled {
            scheduleTimers()
        } else {
            cancelTimers()
        }
        NotificationCenter.default.post(name: .darkoScheduleChanged, object: nil)
    }

    /// The user changed the time range.
    func scheduleChanged() {
        guard defaults.bool(forKey: Key.autoMode) else { return }
        scheduleTimers()
        NotificationCenter.default.post(name: .darkoScheduleChanged, object: nil)
    }

    // MARK: - System observers

    @objc private func systemAppearanceChanged() {
        defaults.set(AppleScriptManager.isSystemDark, forKey: Key.isDark)
        NotificationCenter.default.post(name: .darkoAppearanceChanged, object: nil)
    }

    @objc private func systemDidWake() {
        guard defaults.bool(forKey: Key.autoMode) else { return }
        scheduleTimers()
    }

    // MARK: - Timers

    private func scheduleTimers() {
        cancelTimers()

        if let startDate = nextDate(hour: defaults.integer(forKey: Key.startHour),
                                    minute: defaults.integer(forKey: Key.startMinute)) {
            startTimer = makeDailyTimer(firingAt: startDate) { [weak self] in
                await self?.setDark(true)
            }
        }

        if let endDate = nextDate(hour: defaults.integer(forKey: Key.endHour),
                                  minute: defaults.integer(forKey: Key.endMinute)) {
            endTimer = makeDailyTimer(firingAt: endDate) { [weak self] in
                await self?.setDark(false)
            }
        }

        // We may already be inside the range: correct immediately.
        reconcileCurrentState()
    }

    private func cancelTimers() {
        startTimer?.invalidate()
        startTimer = nil
        endTimer?.invalidate()
        endTimer = nil
    }

    private func makeDailyTimer(firingAt date: Date,
                                action: @escaping @Sendable () async -> Void) -> Timer {
        let timer = Timer(fire: date, interval: 86_400, repeats: true) { _ in
            Task { @MainActor in await action() }
        }
        RunLoop.main.add(timer, forMode: .common)
        return timer
    }

    /// Aligns the current appearance with what the time range requires.
    /// Reads natively (no subprocess); only writes when necessary.
    private func reconcileCurrentState() {
        let shouldBeDark = scheduleWantsDark(at: Date())
        guard AppleScriptManager.isSystemDark != shouldBeDark else { return }
        Task { await setDark(shouldBeDark) }
    }

    /// Should dark mode be active at the given instant?
    /// Handles a range that crosses midnight (e.g. 20:00 → 07:00).
    private func scheduleWantsDark(at date: Date) -> Bool {
        let calendar = Calendar.current
        let now = calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
        let start = defaults.integer(forKey: Key.startHour) * 60 + defaults.integer(forKey: Key.startMinute)
        let end = defaults.integer(forKey: Key.endHour) * 60 + defaults.integer(forKey: Key.endMinute)

        return start < end ? (now >= start && now < end) : (now >= start || now < end)
    }

    /// Next occurrence of a given time (today or tomorrow).
    private func nextDate(hour: Int, minute: Int) -> Date? {
        let calendar = Calendar.current
        let now = Date()
        var components = calendar.dateComponents([.year, .month, .day], from: now)
        components.hour = hour
        components.minute = minute
        components.second = 0

        guard let date = calendar.date(from: components) else { return nil }
        return date <= now ? calendar.date(byAdding: .day, value: 1, to: date) : date
    }
}
