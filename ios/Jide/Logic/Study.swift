import Foundation
import SwiftData

extension Calendar {
    func startOfTomorrow(_ date: Date = Date()) -> Date {
        self.date(byAdding: .day, value: 1, to: startOfDay(for: date))!
    }
}

/// Counts and queue building for study sessions.
enum StudyQueue {
    static let learnAhead: TimeInterval = 20 * 60

    struct Counts { var learning = 0, review = 0, new = 0
        var total: Int { learning + review + new }
    }

    @MainActor
    static func newIntroducedToday(_ context: ModelContext, now: Date = Date()) -> Int {
        let start = Calendar.current.startOfDay(for: now)
        let newRaw = CardState.new.rawValue
        let d = FetchDescriptor<ReviewLog>(predicate: #Predicate { $0.date >= start && $0.stateBefore == newRaw })
        return (try? context.fetchCount(d)) ?? 0
    }

    @MainActor
    static func customWordIDs(_ scope: DeckScope, _ context: ModelContext) -> Set<String> {
        guard case .custom(let id, _) = scope else { return [] }
        let d = FetchDescriptor<Deck>(predicate: #Predicate { $0.id == id })
        return Set((try? context.fetch(d))?.first?.wordIDs ?? [])
    }

    /// Cards in scope: (due learning/review cards, new cards available today).
    @MainActor
    static func build(_ scope: DeckScope, _ context: ModelContext, now: Date = Date()) -> (due: [Card], new: [Card]) {
        let enabled = Set(AppSettings.enabledDirections.map(\.rawValue))
        let all = (try? context.fetch(FetchDescriptor<Card>(predicate: #Predicate { !$0.suspended }))) ?? []
        let custom = customWordIDs(scope, context)
        let cards = all.filter { enabled.contains($0.directionRaw) && scope.contains($0, customWordIDs: custom) }
        let endOfDay = Calendar.current.startOfTomorrow(now)
        var due: [Card] = []
        var fresh: [Card] = []
        for c in cards {
            switch c.state {
            case .new: fresh.append(c)
            case .learning, .relearning: if c.due <= now.addingTimeInterval(learnAhead) { due.append(c) }
            case .review: if c.due < endOfDay { due.append(c) }
            }
        }
        let remaining = max(0, AppSettings.newPerDay - newIntroducedToday(context, now: now))
        fresh.sort { ($0.rank, $0.direction.order) < ($1.rank, $1.direction.order) }
        due.sort { $0.due < $1.due }
        return (due, Array(fresh.prefix(remaining)))
    }

    @MainActor
    static func counts(_ scope: DeckScope, _ context: ModelContext, now: Date = Date()) -> Counts {
        let (due, fresh) = build(scope, context, now: now)
        var c = Counts()
        for card in due { if card.state == .review { c.review += 1 } else { c.learning += 1 } }
        c.new = fresh.count
        return c
    }
}

/// One study session. Holds the queue and applies ratings.
@MainActor
final class StudySession: ObservableObject {
    let scope: DeckScope
    private let context: ModelContext
    private var queue: [Card] = []
    private var shownAt = Date()

    @Published private(set) var current: Card?
    @Published private(set) var reviewedCount = 0
    @Published private(set) var waitingUntil: Date?
    @Published var leechAlert: Word?

    init(scope: DeckScope, context: ModelContext) {
        self.scope = scope
        self.context = context
        let (due, fresh) = StudyQueue.build(scope, context)
        // Interleave new cards between reviews so a session is not all new at the end.
        var q = due
        let step = max(1, due.count / max(1, fresh.count))
        for (i, c) in fresh.enumerated() { q.insert(c, at: min(q.count, (i + 1) * step + i)) }
        queue = q
        advance()
    }

    var remaining: Int { queue.count + (current == nil ? 0 : 1) }

    func preview() -> [Rating: SchedulingInfo] {
        guard let c = current else { return [:] }
        return AppSettings.fsrs.preview(c.scheduling, now: Date())
    }

    func rate(_ rating: Rating) {
        guard let card = current else { return }
        let now = Date()
        let before = card.scheduling
        let after = AppSettings.fsrs.schedule(before, rating: rating, now: now)
        card.scheduling = after
        let elapsed = before.lastReview.map { now.timeIntervalSince($0) / 86400 } ?? 0
        context.insert(ReviewLog(date: now, cardID: card.id, rating: rating.rawValue, stateBefore: before.state.rawValue,
                                 elapsedDays: elapsed, scheduledDays: after.intervalDays(from: now),
                                 durationMs: Int(now.timeIntervalSince(shownAt) * 1000)))

        if rating == .again && before.state == .review && after.lapses >= AppSettings.leechThreshold && !card.isLeech {
            card.isLeech = true
            if AppSettings.suspendLeeches { card.suspended = true }
            leechAlert = card.word
        }
        try? context.save()
        reviewedCount += 1

        // Same-session learning steps come back once due.
        if !card.suspended && (after.state == .learning || after.state == .relearning) {
            queue.append(card)
        }
        // Push siblings of this word back so the other directions are not shown right away.
        let wordID = card.word?.id
        let siblings = queue.filter { $0.word?.id == wordID && $0.id != card.id }
        if !siblings.isEmpty && queue.count > siblings.count {
            queue.removeAll { $0.word?.id == wordID && $0.id != card.id }
            queue.append(contentsOf: siblings)
        }
        current = nil
        advance()
    }

    /// Show a learning card early instead of waiting.
    func continueNow() {
        waitingUntil = nil
        advance(ignoreDue: true)
    }

    func advance(ignoreDue: Bool = false) {
        let now = Date()
        waitingUntil = nil
        guard !queue.isEmpty else { current = nil; return }
        // Learning cards that are due take priority; otherwise next non-learning card in order.
        if let i = queue.firstIndex(where: { ($0.state == .learning || $0.state == .relearning) && $0.reps > 0 && $0.due <= now }) {
            current = queue.remove(at: i)
        } else if let i = queue.firstIndex(where: { $0.state == .new || $0.state == .review || ($0.due <= now) }) {
            current = queue.remove(at: i)
        } else {
            // Only future learning cards remain.
            let next = queue.min { $0.due < $1.due }!
            if ignoreDue {
                queue.removeAll { $0.id == next.id }
                current = next
            } else {
                current = nil
                waitingUntil = next.due
            }
        }
        shownAt = Date()
    }
}
