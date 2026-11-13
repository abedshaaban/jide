import Foundation

/// UserDefaults keys. Values are read with @AppStorage in views and exported in backups.
enum SettingsKey {
    static let newPerDay = "newPerDay"
    static let enabledDirections = "enabledDirections"   // comma separated Direction raw values
    static let autoPlayAudio = "autoPlayAudio"
    static let slowRate = "slowRate"
    static let voiceIdentifier = "voiceIdentifier"
    static let desiredRetention = "desiredRetention"
    static let leechThreshold = "leechThreshold"
    static let suspendLeeches = "suspendLeeches"
    static let reminderEnabled = "reminderEnabled"
    static let reminderHour = "reminderHour"
    static let reminderMinute = "reminderMinute"
    static let toneQuizCorrect = "toneQuizCorrect"
    static let toneQuizTotal = "toneQuizTotal"

    /// Keys included in backups, with their types for decoding.
    static let exported: [String] = [
        newPerDay, enabledDirections, autoPlayAudio, slowRate, voiceIdentifier, desiredRetention,
        leechThreshold, suspendLeeches, reminderEnabled, reminderHour, reminderMinute, toneQuizCorrect, toneQuizTotal,
    ]

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            newPerDay: 15,
            enabledDirections: Direction.allCases.map(\.rawValue).joined(separator: ","),
            autoPlayAudio: true,
            slowRate: 0.3,
            voiceIdentifier: "",
            desiredRetention: 0.9,
            leechThreshold: 8,
            suspendLeeches: false,
            reminderEnabled: false,
            reminderHour: 19,
            reminderMinute: 0,
            toneQuizCorrect: 0,
            toneQuizTotal: 0,
        ])
    }
}

enum AppSettings {
    private static var d: UserDefaults { .standard }

    static var newPerDay: Int { d.integer(forKey: SettingsKey.newPerDay) }
    static var desiredRetention: Double { d.double(forKey: SettingsKey.desiredRetention) }
    static var leechThreshold: Int { max(2, d.integer(forKey: SettingsKey.leechThreshold)) }
    static var suspendLeeches: Bool { d.bool(forKey: SettingsKey.suspendLeeches) }
    static var slowRate: Float { Float(d.double(forKey: SettingsKey.slowRate)) }

    static var enabledDirections: Set<Direction> {
        get {
            let raw = d.string(forKey: SettingsKey.enabledDirections) ?? ""
            let set = Set(raw.split(separator: ",").compactMap { Direction(rawValue: String($0)) })
            return set.isEmpty ? [.hanziToMeaning] : set
        }
        set {
            d.set(Direction.allCases.filter(newValue.contains).map(\.rawValue).joined(separator: ","),
                  forKey: SettingsKey.enabledDirections)
        }
    }

    static var fsrs: FSRS {
        var f = FSRS()
        f.desiredRetention = min(max(desiredRetention, 0.7), 0.99)
        return f
    }
}
