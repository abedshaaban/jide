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

    static func registerDefaults(_ d: UserDefaults = AppSettings.defaults) {
        d.register(defaults: [
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
    /// Settings store. `.standard` in normal use; a separate suite under tests so the owner's settings are untouched.
    static var defaults: UserDefaults = .standard
    private static var d: UserDefaults { defaults }

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

/// How the app was launched. Unit and UI tests get their own store, settings and recordings
/// so running tests on the owner's phone never touches real progress.
enum AppEnvironment {
    enum Mode { case normal, unitTest, uiTest }

    static let mode: Mode = {
        let p = ProcessInfo.processInfo
        if p.arguments.contains("-uitest") { return .uiTest }
        if p.environment["XCTestConfigurationFilePath"] != nil { return .unitTest }
        return .normal
    }()

    static var isTesting: Bool { mode != .normal }

    /// Sets up isolated storage for test modes. Call once, before anything reads settings.
    static func configure() {
        switch mode {
        case .normal:
            removeUITestLeftovers()
        case .unitTest:
            AppSettings.defaults = UserDefaults(suiteName: "jide.unittests")!
            RecordingStore.baseDirectory = FileManager.default.temporaryDirectory.appending(path: "JideUnitTests")
        case .uiTest:
            let suite = "jide.uitest"
            UserDefaults.standard.removePersistentDomain(forName: suite)
            AppSettings.defaults = UserDefaults(suiteName: suite)!
            // Not under Documents: that folder is visible in the Files app.
            let base = FileManager.default.temporaryDirectory.appending(path: "UITest")
            try? FileManager.default.removeItem(at: base)
            RecordingStore.baseDirectory = base
            Reminders.id = "daily-review-uitest"
        }
    }

    /// Store, settings and files a UI-test run leaves behind; removed on the next normal launch.
    private static func removeUITestLeftovers() {
        let fm = FileManager.default
        for suffix in ["", "-wal", "-shm"] {
            try? fm.removeItem(at: URL(fileURLWithPath: uiTestStoreURL.path + suffix))
        }
        try? fm.removeItem(at: URL.documentsDirectory.appending(path: "UITest"))
        try? fm.removeItem(at: fm.temporaryDirectory.appending(path: "UITest"))
        UserDefaults.standard.removePersistentDomain(forName: "jide.uitest")
    }

    /// SwiftData store location for UI tests; wiped on every UI-test launch.
    static var uiTestStoreURL: URL {
        URL.applicationSupportDirectory.appending(path: "UITest.store")
    }
}
