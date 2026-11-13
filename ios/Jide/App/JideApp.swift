import Darwin
import OSLog
import SwiftData
import SwiftUI

let appLog = Logger(subsystem: "com.abedshaaban.jide", category: "app")

@main
struct JideApp: App {
    let container: ModelContainer?
    let containerError: String?

    init() {
        AppEnvironment.configure()
        SettingsKey.registerDefaults()
        let schema = Schema([Word.self, Card.self, ReviewLog.self, Deck.self])
        let config: ModelConfiguration
        switch AppEnvironment.mode {
        case .normal:
            // Default store in Application Support of this bundle ID; survives weekly re-signing.
            config = ModelConfiguration(schema: schema)
        case .unitTest:
            config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        case .uiTest:
            let url = AppEnvironment.uiTestStoreURL
            for suffix in ["", "-wal", "-shm"] {
                try? FileManager.default.removeItem(at: URL(fileURLWithPath: url.path + suffix))
            }
            config = ModelConfiguration(schema: schema, url: url)
        }
        do {
            container = try ModelContainer(for: schema, configurations: config)
            containerError = nil
        } catch {
            // Never delete or replace the store here: the owner's data matters more than launching.
            container = nil
            containerError = error.localizedDescription
            appLog.error("ModelContainer failed: \(error.localizedDescription, privacy: .public)")
        }
        if AppEnvironment.mode != .unitTest { Library.shared.preload() }
    }

    var body: some Scene {
        WindowGroup {
            if let container {
                RootView()
                    .modelContainer(container)
                    .defaultAppStorage(AppSettings.defaults)
                    .modifier(UITestAppearance())
            } else {
                StoreErrorView(message: containerError ?? "Unknown error")
            }
        }
    }
}

/// UI tests can force dark mode and the largest accessibility text size to check layouts.
struct UITestAppearance: ViewModifier {
    func body(content: Content) -> some View {
        let args = ProcessInfo.processInfo.arguments
        if AppEnvironment.mode == .uiTest && args.contains("-uitest-ax") {
            content
                .preferredColorScheme(args.contains("-uitest-dark") ? .dark : nil)
                .dynamicTypeSize(.accessibility5)
        } else if AppEnvironment.mode == .uiTest && args.contains("-uitest-dark") {
            content.preferredColorScheme(.dark)
        } else {
            content
        }
    }
}

struct StoreErrorView: View {
    var message: String
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill").font(.largeTitle).foregroundStyle(.orange)
            Text("Couldn't open your data").font(.headline)
            Text("Your data has not been changed. Reinstall the previous build from Xcode, then export a backup.")
                .multilineTextAlignment(.center)
            Text(message).font(.caption).foregroundStyle(.secondary)
        }
        .padding()
    }
}

/// Process start to first interactive frame, logged on every launch.
enum LaunchTimer {
    static func processStart() -> Date? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0 else { return nil }
        let tv = info.kp_proc.p_starttime
        return Date(timeIntervalSince1970: Double(tv.tv_sec) + Double(tv.tv_usec) / 1_000_000)
    }

    static func markReady(seeded: Seeder.Outcome) {
        guard let start = processStart() else { return }
        let ms = Int(Date().timeIntervalSince(start) * 1000)
        appLog.notice("launch ready in \(ms, privacy: .public) ms (seed: \(String(describing: seeded), privacy: .public))")
        print("[launch] ready in \(ms) ms seed=\(seeded)")
    }
}

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var phase
    @State private var ready = false

    var body: some View {
        Group {
            if AppEnvironment.mode == .unitTest {
                Text("Running unit tests")
            } else if ready {
                TabView {
                    TodayView().tabItem { Label("Today", systemImage: "sun.max.fill") }
                        .accessibilityIdentifier("tab.today")
                    DecksView().tabItem { Label("Decks", systemImage: "rectangle.stack.fill") }
                    BrowseView().tabItem { Label("Words", systemImage: "character.book.closed.fill") }
                    StatsView().tabItem { Label("Stats", systemImage: "chart.bar.fill") }
                    SettingsView().tabItem { Label("Settings", systemImage: "gearshape.fill") }
                }
            } else {
                VStack(spacing: 12) {
                    Text("记得").font(.system(size: 56))
                    ProgressView("Preparing words…")
                }
            }
        }
        .task {
            guard !ready, AppEnvironment.mode != .unitTest else { return }
            AudioSessionConfig.startObserving()
            await Task.yield()
            let outcome = Seeder.run(context)
            ready = true
            LaunchTimer.markReady(seeded: outcome)
            Seeder.pruneRecordings(context)
            Reminders.refresh()
        }
        .onChange(of: phase) { _, p in
            if p == .background {
                VoiceRecorder.current?.stop()
                Reminders.refresh()
            }
        }
    }
}
