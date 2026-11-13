import SwiftData
import XCTest
@testable import Jide

final class FSRSTests: XCTestCase {
    let utc = Calendar.fixed("UTC")
    var fsrs: FSRS { var f = FSRS(); f.calendar = utc; return f }
    var now: Date { utc.at(2026, 11, 13, 10) }

    private func reviewCard(stability: Double = 10, difficulty: Double = 5, lastReview days: Double = 10) -> SchedulingInfo {
        SchedulingInfo(state: .review, step: 0, stability: stability, difficulty: difficulty,
                       due: now, reps: 5, lapses: 0, lastReview: now.addingTimeInterval(-days * 86400))
    }

    func testNewCardEachRating() {
        let p = fsrs.preview(SchedulingInfo(), now: now)
        XCTAssertEqual(p[.again]?.state, .learning)
        XCTAssertEqual(p[.again]?.due, now.addingTimeInterval(60))
        XCTAssertEqual(p[.hard]?.state, .learning)
        XCTAssertEqual(p[.hard]?.due, now.addingTimeInterval(330), "Hard on step 0 = halfway between 1m and 10m")
        XCTAssertEqual(p[.good]?.state, .learning)
        XCTAssertEqual(p[.good]?.step, 1)
        XCTAssertEqual(p[.good]?.due, now.addingTimeInterval(600))
        XCTAssertEqual(p[.easy]?.state, .review)
        XCTAssertEqual(p[.easy]?.due, utc.date(byAdding: .day, value: 16, to: now), "Easy uses S0(easy) = 15.7d")
        for r in Rating.allCases {
            XCTAssertEqual(p[r]?.reps, 1)
            XCTAssertEqual(p[r]?.lastReview, now)
            XCTAssertEqual(p[r]!.difficulty, fsrs.initialDifficulty(r), accuracy: 1e-9)
        }
        XCTAssertGreaterThan(p[.again]!.difficulty, p[.easy]!.difficulty)
    }

    func testLearningStepsGraduate() {
        var c = fsrs.schedule(SchedulingInfo(), rating: .good, now: now)  // step 1, +10m
        let t1 = now.addingTimeInterval(600)
        c = fsrs.schedule(c, rating: .good, now: t1)
        XCTAssertEqual(c.state, .review)
        XCTAssertGreaterThanOrEqual(c.due, utc.date(byAdding: .day, value: 1, to: t1)!)
    }

    func testLearningAgainGoesBackToFirstStep() {
        var c = fsrs.schedule(SchedulingInfo(), rating: .good, now: now)
        c = fsrs.schedule(c, rating: .again, now: now.addingTimeInterval(600))
        XCTAssertEqual(c.state, .learning)
        XCTAssertEqual(c.step, 0)
        XCTAssertEqual(c.due, now.addingTimeInterval(660))
        XCTAssertEqual(c.lapses, 0, "Lapses only count forgotten review cards")
    }

    func testReviewIntervalsAreOrdered() {
        let p = fsrs.preview(reviewCard(), now: now)
        let days = Rating.allCases.dropFirst().map { p[$0]!.due.timeIntervalSince(now) / 86400 }
        XCTAssertGreaterThanOrEqual(days[0], 1)
        XCTAssertLessThan(days[0], days[1])
        XCTAssertLessThan(days[1], days[2])
        XCTAssertGreaterThan(p[.good]!.stability, 10, "Successful recall grows stability")
        XCTAssertEqual(p[.good]?.state, .review)
    }

    func testHigherRetentionGivesShorterIntervals() {
        var strict = fsrs
        strict.desiredRetention = 0.95
        let loose = fsrs
        XCTAssertLessThan(strict.nextInterval(stability: 30), loose.nextInterval(stability: 30))
        XCTAssertEqual(loose.nextInterval(stability: 30), 30, "At 90% retention the interval equals stability")
        XCTAssertEqual(loose.nextInterval(stability: 0.01), 1)
        XCTAssertEqual(loose.nextInterval(stability: 1e9), loose.maximumInterval)
    }

    func testLapseMovesToRelearning() {
        let before = reviewCard(stability: 20)
        let c = fsrs.schedule(before, rating: .again, now: now)
        XCTAssertEqual(c.state, .relearning)
        XCTAssertEqual(c.lapses, 1)
        XCTAssertEqual(c.due, now.addingTimeInterval(600))
        XCTAssertLessThan(c.stability, 20)
        let back = fsrs.schedule(c, rating: .good, now: now.addingTimeInterval(600))
        XCTAssertEqual(back.state, .review)
        XCTAssertEqual(back.lapses, 1)
    }

    func testLeechRule() {
        var before = reviewCard()
        before.lapses = 7
        let after = fsrs.schedule(before, rating: .again, now: now)
        XCTAssertTrue(StudySession.becomesLeech(before: before, after: after, rating: .again, threshold: 8))
        XCTAssertFalse(StudySession.becomesLeech(before: before, after: after, rating: .again, threshold: 9))
        let good = fsrs.schedule(before, rating: .good, now: now)
        XCTAssertFalse(StudySession.becomesLeech(before: before, after: good, rating: .good, threshold: 8))
        // Again while still learning is not a lapse.
        var learning = before
        learning.state = .learning
        let l = fsrs.schedule(learning, rating: .again, now: now)
        XCTAssertFalse(StudySession.becomesLeech(before: learning, after: l, rating: .again, threshold: 8))
    }

    func testOneDayIntervalStaysOnNextCalendarDayAcrossDST() {
        // US spring forward: 2026-03-08 02:00 -> 03:00 in New York.
        let ny = Calendar.fixed("America/New_York")
        let lateEvening = ny.at(2026, 3, 7, 23, 30)
        let due = lateEvening.addingDays(1, calendar: ny)
        let comps = ny.dateComponents([.day, .hour, .minute], from: due)
        XCTAssertEqual(comps.day, 8)
        XCTAssertEqual(comps.hour, 23)
        XCTAssertEqual(comps.minute, 30)
        XCTAssertEqual(due.timeIntervalSince(lateEvening), 23 * 3600, "The DST day is 23 hours long")
    }

    func testFormatInterval() {
        XCTAssertEqual(formatInterval(from: now, to: now.addingTimeInterval(30)), "1m")
        XCTAssertEqual(formatInterval(from: now, to: now.addingTimeInterval(600)), "10m")
        XCTAssertEqual(formatInterval(from: now, to: now.addingTimeInterval(3 * 3600)), "3h")
        XCTAssertEqual(formatInterval(from: now, to: now.addingTimeInterval(4 * 86400)), "4d")
        XCTAssertEqual(formatInterval(from: now, to: now.addingTimeInterval(-100)), "1m")
    }
}

/// Queue selection around midnight and time zones.
@MainActor
final class StudyQueueTests: StoreTestCase {
    private func reviewCard(due: Date) throws -> Card {
        seedFixture()
        let c = try XCTUnwrap(try word("你").card(.hanziToMeaning))
        c.scheduling = SchedulingInfo(state: .review, stability: 5, difficulty: 5, due: due, reps: 3,
                                      lastReview: due.addingTimeInterval(-5 * 86400))
        return c
    }

    private func isDue(_ card: Card, now: Date, calendar: Calendar) throws -> Bool {
        let (due, _) = StudyQueue.select(from: try cards(), scope: .all, customWordIDs: [], enabled: Set(Direction.allCases),
                                         newRemaining: 0, now: now, calendar: calendar)
        return due.contains { $0.id == card.id }
    }

    func testReviewDueLaterTodayCountsTodayButNotTomorrowsCard() throws {
        let cal = Calendar.fixed("Europe/Paris")
        let card = try reviewCard(due: cal.at(2026, 11, 13, 23, 59))
        XCTAssertTrue(try isDue(card, now: cal.at(2026, 11, 13, 8, 0), calendar: cal))
        card.due = cal.at(2026, 11, 14, 0, 1)
        XCTAssertFalse(try isDue(card, now: cal.at(2026, 11, 13, 23, 58), calendar: cal), "Due after midnight = tomorrow")
        XCTAssertTrue(try isDue(card, now: cal.at(2026, 11, 14, 0, 0), calendar: cal), "Shows from midnight on")
    }

    func testDayBoundaryFollowsCurrentTimeZone() throws {
        let card = try reviewCard(due: ISO8601DateFormatter().date(from: "2026-11-14T06:00:00Z")!)
        let now = ISO8601DateFormatter().date(from: "2026-11-13T20:00:00Z")!
        XCTAssertFalse(try isDue(card, now: now, calendar: .fixed("UTC")), "Still the 13th in UTC")
        XCTAssertTrue(try isDue(card, now: now, calendar: .fixed("Asia/Tokyo")), "Already the 14th in Tokyo")
    }

    func testNewCardLimitAndOrder() throws {
        seedFixture()
        let (_, fresh) = StudyQueue.select(from: try cards(), scope: .all, customWordIDs: [],
                                           enabled: [.hanziToMeaning, .audioToHanzi], newRemaining: 3, now: Date())
        XCTAssertEqual(fresh.map(\.id), ["zh:你|hanzi_meaning", "zh:你|audio_hanzi", "zh:好|hanzi_meaning"])
        let none = StudyQueue.select(from: try cards(), scope: .all, customWordIDs: [], enabled: Set(Direction.allCases),
                                     newRemaining: -2, now: Date())
        XCTAssertTrue(none.new.isEmpty)
    }

    func testSuspendedAndScopeFiltering() throws {
        seedFixture()
        try word("你").card(.hanziToMeaning)?.suspended = true
        let hsk = StudyQueue.select(from: try cards(), scope: .rankRange(2...3), customWordIDs: [],
                                    enabled: Set(Direction.allCases), newRemaining: 100, now: Date())
        XCTAssertEqual(Set(hsk.new.compactMap { $0.word?.simplified }), ["好", "中国"])
        let all = StudyQueue.select(from: try cards(), scope: .all, customWordIDs: [], enabled: Set(Direction.allCases),
                                    newRemaining: 100, now: Date())
        XCTAssertEqual(all.new.count, 8)
    }
}

@MainActor
final class StudySessionTests: StoreTestCase {
    func testLeechFlaggedAndOptionallySuspended() throws {
        seedFixture()
        let card = try XCTUnwrap(try word("你").card(.hanziToMeaning))
        card.scheduling = SchedulingInfo(state: .review, stability: 3, difficulty: 7, due: Date().addingTimeInterval(-60),
                                         reps: 20, lapses: 7, lastReview: Date().addingTimeInterval(-3 * 86400))
        defaults.set(0, forKey: SettingsKey.newPerDay)
        let session = StudySession(scope: .all, context: context, leechThreshold: 8, suspendLeeches: true)
        XCTAssertEqual(session.current?.id, card.id)
        session.rate(.again)
        XCTAssertTrue(card.isLeech)
        XCTAssertTrue(card.suspended)
        XCTAssertEqual(card.lapses, 8)
        XCTAssertEqual(session.leechAlert?.simplified, "你")
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ReviewLog>()), 1)
    }

    func testSameCardShownAgainBumpsSerial() throws {
        seedFixture()
        defaults.set(1, forKey: SettingsKey.newPerDay)
        AppSettings.enabledDirections = [.hanziToMeaning]
        let session = StudySession(scope: .all, context: context)
        let first = session.current?.id
        let s0 = session.serial
        session.rate(.again)                // only card, back in 1 minute
        XCTAssertNil(session.current)
        XCTAssertNotNil(session.waitingUntil)
        session.continueNow()
        XCTAssertEqual(session.current?.id, first)
        XCTAssertEqual(session.serial, s0 + 1, "The view resets the revealed state on serial changes")
    }

    func testEmptySession() throws {
        seedFixture()
        defaults.set(0, forKey: SettingsKey.newPerDay)
        let session = StudySession(scope: .all, context: context)
        XCTAssertTrue(session.startedEmpty)
        XCTAssertNil(session.current)
    }

    func testNewCardsCountAgainstDailyLimit() throws {
        seedFixture()
        defaults.set(2, forKey: SettingsKey.newPerDay)
        let s1 = StudySession(scope: .all, context: context)
        XCTAssertEqual(s1.remaining, 2)
        s1.rate(.easy)
        let s2 = StudySession(scope: .all, context: context)
        XCTAssertEqual(StudyQueue.counts(.all, context).new, 1)
        XCTAssertEqual(s2.remaining, 1)
    }
}
