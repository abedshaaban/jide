import Foundation
import SwiftData

extension Calendar {
    func startOfTomorrow(_ date: Date = Date()) -> Date {
        addingDays(1, to: date)
    }
}

/// Counts and queue building for study sessions.
enum StudyQueue {
    static let learnAhead: TimeInterval = 20 * 60

    struct Counts: Equatable { var learning = 0, review = 0, new = 0
        var total: Int { learning + review + new }
    }

    @MainActor
    static func newIntroducedToday(_ context: ModelContext, now: Date = Date(), calendar: Calendar = .current) -> Int {
        let start = calendar.startOfDay(for: now)
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

    /// The cards a session could draw from now, without loading the whole store: studied cards that are due,
    /// and new cards in rank order until `newRemaining` of them match the scope. `select` applies the exact rules.
    @MainActor
    static func candidates(_ context: ModelContext, scope: DeckScope, customWordIDs: Set<String>, enabled: Set<Direction>,
                           newRemaining: Int, now: Date, calendar: Calendar = .current) -> [Card] {
        let newRaw = CardState.new.rawValue
        let cutoff = max(calendar.startOfTomorrow(now), now.addingTimeInterval(learnAhead))
        var out = (try? context.fetch(FetchDescriptor<Card>(
            predicate: #Predicate { !$0.suspended && $0.stateRaw != newRaw && $0.due <= cutoff }))) ?? []
        guard newRemaining > 0 else { return out }

        let enabledRaw = Set(enabled.map(\.rawValue))
        // A frequency deck far down the list would otherwise page through every card above it.
        var lowest = Int.min, highest = Int.max
        if case .rankRange(let r) = scope { (lowest, highest) = (r.lowerBound, r.upperBound) }
        let page = 300
        var matchedRanks: [Int] = []
        var offset = 0
        while true {
            var d = FetchDescriptor<Card>(
                predicate: #Predicate { !$0.suspended && $0.stateRaw == newRaw && $0.rank >= lowest && $0.rank <= highest },
                sortBy: [SortDescriptor(\.rank), SortDescriptor(\.id)])
            d.fetchLimit = page
            d.fetchOffset = offset
            let cards = (try? context.fetch(d)) ?? []
            for c in cards where enabledRaw.contains(c.directionRaw) && scope.contains(c, customWordIDs: customWordIDs) {
                out.append(c)
                matchedRanks.append(c.rank)
            }
            offset += cards.count
            // Enough once every card of the last needed rank has been seen (ties are ordered in `select`).
            if cards.count < page { break }
            if matchedRanks.count >= newRemaining, let last = cards.last, last.rank > matchedRanks[newRemaining - 1] { break }
        }
        return out
    }

    /// Pure queue selection: due learning/review cards and today's new cards for a scope.
    /// Review cards count as due for the whole calendar day they fall on.
    static func select(from all: [Card], scope: DeckScope, customWordIDs: Set<String>, enabled: Set<Direction>,
                       newRemaining: Int, now: Date, calendar: Calendar = .current) -> (due: [Card], new: [Card]) {
        let enabledRaw = Set(enabled.map(\.rawValue))
        let endOfDay = calendar.startOfTomorrow(now)
        var due: [Card] = []
        var fresh: [Card] = []
        for c in all where !c.suspended && enabledRaw.contains(c.directionRaw)
            && scope.contains(c, customWordIDs: customWordIDs) && c.word != nil {
            switch c.state {
            case .new: fresh.append(c)
            case .learning, .relearning: if c.due <= now.addingTimeInterval(learnAhead) { due.append(c) }
            case .review: if c.due < endOfDay { due.append(c) }
            }
        }
        // Same rank: a character part comes before the word that uses it.
        fresh.sort { ($0.rank, $0.isComponent ? 0 : 1, $0.direction.order) < ($1.rank, $1.isComponent ? 0 : 1, $1.direction.order) }
        due.sort { $0.due < $1.due }
        return (due, Array(fresh.prefix(max(0, newRemaining))))
    }

    @MainActor
    static func build(_ scope: DeckScope, _ context: ModelContext, now: Date = Date()) -> (due: [Card], new: [Card]) {
        let ids = customWordIDs(scope, context)
        let enabled = AppSettings.enabledDirections
        let newRemaining = AppSettings.newPerDay - newIntroducedToday(context, now: now)
        let cards = candidates(context, scope: scope, customWordIDs: ids, enabled: enabled, newRemaining: newRemaining, now: now)
        return select(from: cards, scope: scope, customWordIDs: ids, enabled: enabled, newRemaining: newRemaining, now: now)
    }

    static func counts(due: [Card], new: [Card]) -> Counts {
        var c = Counts()
        for card in due { if card.state == .review { c.review += 1 } else { c.learning += 1 } }
        c.new = new.count
        return c
    }

    @MainActor
    static func counts(_ scope: DeckScope, _ context: ModelContext, now: Date = Date()) -> Counts {
        let (due, fresh) = build(scope, context, now: now)
        return counts(due: due, new: fresh)
    }

    /// The fields queue selection needs, read once from SwiftData so many decks can be counted cheaply.
    struct CardInfo {
        var wordID: String
        var isCustom: Bool
        var rank: Int
        var hsk: Int?
        var directionRaw: String
        var state: CardState
        var due: Date
        var isLeech: Bool

        init(wordID: String, isCustom: Bool = false, rank: Int, hsk: Int? = nil, directionRaw: String,
             state: CardState, due: Date, isLeech: Bool = false) {
            self.wordID = wordID; self.isCustom = isCustom; self.rank = rank; self.hsk = hsk
            self.directionRaw = directionRaw; self.state = state; self.due = due; self.isLeech = isLeech
        }
    }

    /// Same rules as `select`, counting only. Unsuspended cards only.
    static func counts(_ infos: [CardInfo], scopes: [DeckScope], customWordIDs: [String: Set<String>],
                       enabled: Set<Direction>, newRemaining: Int, now: Date,
                       calendar: Calendar = .current) -> [String: Counts] {
        let enabledRaw = Set(enabled.map(\.rawValue))
        let endOfDay = calendar.startOfTomorrow(now)
        let learnUntil = now.addingTimeInterval(learnAhead)
        let active = infos.filter { enabledRaw.contains($0.directionRaw) }
        var out: [String: Counts] = [:]
        for s in scopes {
            let ids = customWordIDs[s.id] ?? []
            var c = Counts()
            for i in active where s.contains(wordID: i.wordID, isCustom: i.isCustom, rank: i.rank, hsk: i.hsk,
                                             isLeech: i.isLeech, customWordIDs: ids) {
                switch i.state {
                case .new: c.new += 1
                case .learning, .relearning: if i.due <= learnUntil { c.learning += 1 }
                case .review: if i.due < endOfDay { c.review += 1 }
                }
            }
            c.new = min(c.new, max(0, newRemaining))
            out[s.id] = c
        }
        return out
    }

    /// One flat fetch of the cards. The word ID comes from the card ID ("<wordID>|<direction>"), the rank from
    /// the card and the HSK level from the bundled list (the store for custom words), so no relationship faults.
    @MainActor
    static func cardInfos(_ context: ModelContext) -> [CardInfo] {
        var customHSK: [String: Int] = [:]
        for w in (try? context.fetch(FetchDescriptor<Word>(predicate: #Predicate { $0.isCustom }))) ?? [] {
            if let h = w.hsk { customHSK[w.id] = h }
        }
        let bundledHSK = Library.shared.hskByWordID
        var d = FetchDescriptor<Card>(predicate: #Predicate { !$0.suspended })
        d.propertiesToFetch = [\.id, \.rank, \.directionRaw, \.stateRaw, \.due, \.isLeech]
        let cards = (try? context.fetch(d)) ?? []
        var out: [CardInfo] = []
        out.reserveCapacity(cards.count)
        for c in cards {
            let wordID = c.wordID
            let isCustom = wordID.hasPrefix("custom:")
            out.append(CardInfo(wordID: wordID, isCustom: isCustom, rank: c.rank,
                                hsk: isCustom ? customHSK[wordID] : bundledHSK[wordID],
                                directionRaw: c.directionRaw, state: c.state, due: c.due, isLeech: c.isLeech))
        }
        return out
    }

    /// Counts for many decks (Decks tab): one read of the store, then plain-value counting.
    @MainActor
    static func counts(_ scopes: [DeckScope], _ context: ModelContext, now: Date = Date()) -> [String: Counts] {
        let decks = (try? context.fetch(FetchDescriptor<Deck>())) ?? []
        var ids: [String: Set<String>] = [:]
        for s in scopes {
            if case .custom(let id, _) = s { ids[s.id] = Set(decks.first { $0.id == id }?.wordIDs ?? []) }
        }
        return counts(cardInfos(context), scopes: scopes, customWordIDs: ids, enabled: AppSettings.enabledDirections,
                      newRemaining: AppSettings.newPerDay - newIntroducedToday(context, now: now), now: now)
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
    /// Increments every time a card is shown, even if it is the same card again.
    @Published private(set) var serial = 0
    @Published private(set) var reviewedCount = 0
    @Published private(set) var waitingUntil: Date?
    @Published var leechAlert: Word?

    private let fsrs: FSRS
    private let leechThreshold: Int
    private let suspendLeeches: Bool

    init(scope: DeckScope, context: ModelContext, now: Date = Date(), fsrs: FSRS = AppSettings.fsrs,
         leechThreshold: Int = AppSettings.leechThreshold, suspendLeeches: Bool = AppSettings.suspendLeeches) {
        self.scope = scope
        self.context = context
        self.fsrs = fsrs
        self.leechThreshold = leechThreshold
        self.suspendLeeches = suspendLeeches
        let (due, fresh) = StudyQueue.build(scope, context, now: now)
        // Interleave new cards between reviews so a session is not all new at the end.
        var q = due
        let step = max(1, due.count / max(1, fresh.count))
        for (i, c) in fresh.enumerated() { q.insert(c, at: min(q.count, (i + 1) * step + i)) }
        queue = q
        startedEmpty = q.isEmpty
        advance()
    }

    var remaining: Int { queue.count + (current == nil ? 0 : 1) }
    /// True when the session started with nothing to study.
    private(set) var startedEmpty = false

    /// A lapse (Again on a review card) that brings the lapse count to the threshold.
    nonisolated static func becomesLeech(before: SchedulingInfo, after: SchedulingInfo, rating: Rating, threshold: Int) -> Bool {
        rating == .again && before.state == .review && after.lapses >= threshold
    }

    func preview() -> [Rating: SchedulingInfo] {
        guard let c = current else { return [:] }
        return fsrs.preview(c.scheduling, now: Date())
    }

    func rate(_ rating: Rating, now: Date = Date()) {
        guard let card = current else { return }
        let before = card.scheduling
        let after = fsrs.schedule(before, rating: rating, now: now)
        card.scheduling = after
        let elapsed = before.lastReview.map { now.timeIntervalSince($0) / 86400 } ?? 0
        context.insert(ReviewLog(date: now, cardID: card.id, rating: rating.rawValue, stateBefore: before.state.rawValue,
                                 elapsedDays: elapsed, scheduledDays: after.intervalDays(from: now),
                                 durationMs: Int(now.timeIntervalSince(shownAt) * 1000)))

        if StudySession.becomesLeech(before: before, after: after, rating: rating, threshold: leechThreshold)
            && !card.isLeech {
            card.isLeech = true
            if suspendLeeches { card.suspended = true }
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
            guard let next = queue.min(by: { $0.due < $1.due }) else { current = nil; return }
            if ignoreDue {
                queue.removeAll { $0.id == next.id }
                current = next
            } else {
                current = nil
                waitingUntil = next.due
            }
        }
        shownAt = Date()
        if current != nil { serial += 1 }
    }
}
