import Foundation
import SwiftData

struct DayCount: Identifiable {
    var day: Date
    var count: Int
    var id: Date { day }
}

struct StatsSnapshot {
    var streak = 0
    var longestStreak = 0
    var reviewedToday = 0
    var totalReviews = 0
    var last30: [DayCount] = []
    var forecast: [DayCount] = []
    var retention30: Double?
    var newCards = 0, learningCards = 0, reviewCards = 0, suspendedCards = 0
    var matureCards = 0
    var leeches: [Card] = []
    var wordsStarted = 0
}

enum StatsBuilder {
    @MainActor
    static func build(_ context: ModelContext, now: Date = Date()) -> StatsSnapshot {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        var s = StatsSnapshot()

        let logs = (try? context.fetch(FetchDescriptor<ReviewLog>())) ?? []
        s.totalReviews = logs.count
        var perDay: [Date: Int] = [:]
        for l in logs { perDay[cal.startOfDay(for: l.date), default: 0] += 1 }
        s.reviewedToday = perDay[today] ?? 0
        (s.streak, s.longestStreak) = streaks(days: Set(perDay.keys), today: today, cal: cal)

        s.last30 = (0..<30).reversed().map { i in
            let d = cal.date(byAdding: .day, value: -i, to: today)!
            return DayCount(day: d, count: perDay[d] ?? 0)
        }

        let monthAgo = cal.date(byAdding: .day, value: -30, to: today)!
        let reviewLogs = logs.filter { $0.date >= monthAgo && $0.stateBefore == CardState.review.rawValue }
        if !reviewLogs.isEmpty {
            s.retention30 = Double(reviewLogs.filter { $0.rating > 1 }.count) / Double(reviewLogs.count)
        }

        let cards = (try? context.fetch(FetchDescriptor<Card>())) ?? []
        let enabled = Set(AppSettings.enabledDirections.map(\.rawValue))
        var forecast: [Date: Int] = [:]
        var started = Set<String>()
        for c in cards {
            if c.suspended { s.suspendedCards += 1 }
            if c.isLeech { s.leeches.append(c) }
            switch c.state {
            case .new: if enabled.contains(c.directionRaw) { s.newCards += 1 }
            case .learning, .relearning: s.learningCards += 1
            case .review:
                s.reviewCards += 1
                if c.stability >= 21 { s.matureCards += 1 }
            }
            if c.state != .new, let w = c.word { started.insert(w.id) }
            if c.state != .new && !c.suspended {
                let d = max(today, cal.startOfDay(for: c.due))
                forecast[d, default: 0] += 1
            }
        }
        s.wordsStarted = started.count
        s.forecast = (0..<14).map { i in
            let d = cal.date(byAdding: .day, value: i, to: today)!
            return DayCount(day: d, count: forecast[d] ?? 0)
        }
        s.leeches.sort { $0.lapses > $1.lapses }
        return s
    }

    /// Current streak counts today if reviewed, otherwise it is still alive from yesterday.
    static func streaks(days: Set<Date>, today: Date, cal: Calendar) -> (current: Int, longest: Int) {
        var current = 0
        var d = days.contains(today) ? today : cal.date(byAdding: .day, value: -1, to: today)!
        while days.contains(d) {
            current += 1
            d = cal.date(byAdding: .day, value: -1, to: d)!
        }
        var longest = 0, run = 0
        var prev: Date?
        for day in days.sorted() {
            if let p = prev, cal.date(byAdding: .day, value: 1, to: p) == day { run += 1 } else { run = 1 }
            longest = max(longest, run)
            prev = day
        }
        return (current, longest)
    }
}
