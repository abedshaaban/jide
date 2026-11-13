import Foundation
import UserNotifications

/// Daily local notification. No push, no server.
enum Reminders {
    static var id = "daily-review"

    static func requestPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    /// The repeating request for a given time. Pure, so it can be tested.
    static func makeRequest(hour: Int, minute: Int) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = "记得 · Time to review"
        content.body = "A few minutes of review keeps your streak going."
        content.sound = .default
        var comps = DateComponents()
        comps.hour = min(max(hour, 0), 23)
        comps.minute = min(max(minute, 0), 59)
        // Hour/minute only: fires at that local wall-clock time, also after time-zone changes.
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
        return UNNotificationRequest(identifier: id, content: content, trigger: trigger)
    }

    static func schedule(hour: Int, minute: Int) {
        let center = UNUserNotificationCenter.current()
        // Same identifier replaces the pending request, so changing the time never leaves a duplicate.
        center.removePendingNotificationRequests(withIdentifiers: [id])
        center.add(makeRequest(hour: hour, minute: minute))
    }

    static func cancel() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
    }

    /// Re-arms the reminder from saved settings (launch, background, time change, import).
    static func refresh() {
        let d = AppSettings.defaults
        guard d.bool(forKey: SettingsKey.reminderEnabled) else { return cancel() }
        schedule(hour: d.integer(forKey: SettingsKey.reminderHour), minute: d.integer(forKey: SettingsKey.reminderMinute))
    }
}
