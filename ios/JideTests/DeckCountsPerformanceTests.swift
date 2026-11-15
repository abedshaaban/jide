import SwiftData
import XCTest
@testable import Jide

/// Decks tab counts on the real store: 3000 words with three cards each, plus character parts.
final class DeckCountsPerformanceTests: StoreTestCase {
    static let scopes: [DeckScope] = [.all, .components, .leeches]
        + DeckScope.frequencyDecks(wordCount: Library.shared.words.count)
        + (1...6).map { .hsk($0) }

    func seedReal() throws {
        Seeder.run(context, words: Library.shared.words, components: Library.shared.components,
                   version: Library.shared.dataVersion, defaults: defaults)
        try context.save()
    }

    func testDeckCountsSpeed() throws {
        try seedReal()
        let options = XCTMeasureOptions()
        options.iterationCount = 5
        measure(metrics: [XCTClockMetric()], options: options) {
            // Fresh context each time, like opening the tab after the store was faulted out.
            let ctx = ModelContext(container)
            _ = StudyQueue.counts(Self.scopes, ctx)
        }
    }

    /// Decks tab counts must agree with what a study session would actually queue.
    func testDeckCountsMatchSessionQueue() throws {
        try seedReal()
        let deck = Deck(name: "Mine")
        context.insert(deck)
        let now = Date()
        let cards = try cards()
        for (i, c) in cards.enumerated() {
            switch i % 7 {
            case 0: c.stateRaw = CardState.review.rawValue; c.due = now.addingTimeInterval(-86_400)
            case 1: c.stateRaw = CardState.review.rawValue; c.due = now.addingTimeInterval(5 * 86_400)
            case 2: c.stateRaw = CardState.learning.rawValue; c.due = now.addingTimeInterval(60)
            case 3: c.stateRaw = CardState.relearning.rawValue; c.due = now.addingTimeInterval(3600)
            case 4: c.suspended = i % 2 == 0; c.isLeech = true
            default: break
            }
        }
        deck.wordIDs = Array(Set(cards.prefix(200).compactMap { $0.word?.id }))
        defaults.set(20, forKey: SettingsKey.newPerDay)
        try context.save()

        let scopes = Self.scopes + [.custom(deck.id, deck.name)]
        let fast = StudyQueue.counts(scopes, context, now: now)
        for s in scopes {
            XCTAssertEqual(fast[s.id], StudyQueue.counts(s, context, now: now), s.id)
        }
        XCTAssertGreaterThan(fast["all"]?.review ?? 0, 0)
        XCTAssertGreaterThan(fast["all"]?.learning ?? 0, 0)
        XCTAssertEqual(fast["all"]?.new, 20)
        XCTAssertGreaterThan(fast["leeches"]?.total ?? 0, 0)
        XCTAssertGreaterThan(fast["components"]?.total ?? 0, 0)
    }
}
