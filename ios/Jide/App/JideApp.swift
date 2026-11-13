import SwiftData
import SwiftUI

@main
struct JideApp: App {
    let container: ModelContainer

    init() {
        SettingsKey.registerDefaults()
        // Store lives in Application Support of this bundle ID; survives weekly re-signing.
        container = try! ModelContainer(for: Word.self, Card.self, ReviewLog.self, Deck.self)
        Library.shared.preload()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(container)
    }
}

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var phase
    @State private var ready = false

    var body: some View {
        Group {
            if ready {
                TabView {
                    TodayView().tabItem { Label("Today", systemImage: "sun.max.fill") }
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
            if !ready {
                await Task.yield()
                Seeder.run(context)
                ready = true
            }
        }
        .onChange(of: phase) { _, p in
            if p == .background { Reminders.refresh() }
        }
    }
}
