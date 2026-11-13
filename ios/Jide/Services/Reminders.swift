import Foundation
import UserNotifications

/// Daily local notification. No push, no server.
enum Reminders {
    static let id = "daily-review"

    static func requestPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    static func schedule(hour: Int, minute: Int, dueCount: Int? = nil) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [id])
        let content = UNMutableNotificationContent()
        content.title = "记得 · Time to review"
        if let n = dueCount, n > 0 {
            content.body = "\(n) cards are waiting. Keep your streak going."
        } else {
            content.body = "A few minutes of review keeps your streak going."
        }
        content.sound = .default
        var comps = DateComponents()
        comps.hour = hour
        comps.minute = minute
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }

    static func cancel() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
    }

    /// Re-arms the reminder from saved settings, e.g. when the app goes to the background.
    static func refresh(dueCount: Int? = nil) {
        let d = UserDefaults.standard
        guard d.bool(forKey: SettingsKey.reminderEnabled) else { return cancel() }
        schedule(hour: d.integer(forKey: SettingsKey.reminderHour), minute: d.integer(forKey: SettingsKey.reminderMinute),
                 dueCount: dueCount)
    }
}
