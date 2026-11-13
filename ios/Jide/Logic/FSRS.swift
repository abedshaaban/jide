import Foundation

/// Card rating. Raw values match the FSRS convention and the backup format.
enum Rating: Int, CaseIterable, Codable, Identifiable {
    case again = 1, hard, good, easy
    var id: Int { rawValue }
    var label: String {
        switch self {
        case .again: "Again"
        case .hard: "Hard"
        case .good: "Good"
        case .easy: "Easy"
        }
    }
}

enum CardState: Int, Codable {
    case new = 0, learning, review, relearning
}

/// The scheduling part of a card, separate from SwiftData so it can be tested and previewed.
struct SchedulingInfo: Equatable {
    var state: CardState = .new
    var step: Int = 0
    var stability: Double = 0
    var difficulty: Double = 0
    var due: Date = .distantPast
    var reps: Int = 0
    var lapses: Int = 0
    var lastReview: Date?

    /// Days until due, as used for display and logging.
    func intervalDays(from now: Date) -> Double { max(0, due.timeIntervalSince(now) / 86400) }
}

/// FSRS-5 scheduler with short learning/relearning steps.
/// Formulas follow the open-spaced-repetition reference implementation.
struct FSRS {
    static let defaultWeights: [Double] = [
        0.40255, 1.18385, 3.173, 15.69105, 7.1949, 0.5345, 1.4604, 0.0046, 1.54575, 0.1192,
        1.01925, 1.9395, 0.11, 0.29605, 2.2698, 0.2315, 2.9898, 0.51655, 0.6621,
    ]
    static let decay = -0.5
    static let factor = 19.0 / 81.0

    var w: [Double] = FSRS.defaultWeights
    var desiredRetention: Double = 0.9
    var learningSteps: [TimeInterval] = [60, 600]
    var relearningSteps: [TimeInterval] = [600]
    var maximumInterval: Int = 36500

    // MARK: Model

    func retrievability(elapsedDays t: Double, stability s: Double) -> Double {
        guard s > 0 else { return 0 }
        return pow(1 + FSRS.factor * t / s, FSRS.decay)
    }

    func nextInterval(stability s: Double) -> Int {
        let raw = s / FSRS.factor * (pow(desiredRetention, 1 / FSRS.decay) - 1)
        return min(max(Int(raw.rounded()), 1), maximumInterval)
    }

    func initialStability(_ r: Rating) -> Double { max(w[r.rawValue - 1], 0.1) }

    func initialDifficulty(_ r: Rating) -> Double {
        clampD(w[4] - exp(w[5] * Double(r.rawValue - 1)) + 1)
    }

    func nextDifficulty(_ d: Double, _ r: Rating) -> Double {
        let delta = -w[6] * Double(r.rawValue - 3)
        let damped = d + delta * (10 - d) / 9
        return clampD(w[7] * initialDifficulty(.easy) + (1 - w[7]) * damped)
    }

    func recallStability(d: Double, s: Double, r: Double, rating: Rating) -> Double {
        let hard = rating == .hard ? w[15] : 1
        let easy = rating == .easy ? w[16] : 1
        return s * (1 + exp(w[8]) * (11 - d) * pow(s, -w[9]) * (exp((1 - r) * w[10]) - 1) * hard * easy)
    }

    func forgetStability(d: Double, s: Double, r: Double) -> Double {
        let sf = w[11] * pow(d, -w[12]) * (pow(s + 1, w[13]) - 1) * exp((1 - r) * w[14])
        return max(0.1, min(sf, s / exp(w[17] * w[18])))
    }

    func shortTermStability(_ s: Double, _ rating: Rating) -> Double {
        max(0.1, s * exp(w[17] * (Double(rating.rawValue) - 3 + w[18])))
    }

    private func clampD(_ d: Double) -> Double { min(max(d, 1), 10) }

    // MARK: Scheduling

    /// Outcome for every rating, used to label buttons.
    func preview(_ card: SchedulingInfo, now: Date) -> [Rating: SchedulingInfo] {
        Dictionary(uniqueKeysWithValues: Rating.allCases.map { ($0, schedule(card, rating: $0, now: now)) })
    }

    func schedule(_ card: SchedulingInfo, rating: Rating, now: Date) -> SchedulingInfo {
        var c = card
        c.reps += 1
        let elapsed = card.lastReview.map { max(0, now.timeIntervalSince($0) / 86400) } ?? 0

        switch card.state {
        case .new:
            c.stability = initialStability(rating)
            c.difficulty = initialDifficulty(rating)
            applySteps(&c, steps: learningSteps, state: .learning, rating: rating, step: 0, now: now) {
                initialStability($0)
            }

        case .learning, .relearning:
            let steps = card.state == .learning ? learningSteps : relearningSteps
            c.difficulty = nextDifficulty(card.difficulty, rating)
            let stab: (Rating) -> Double = { r in
                if elapsed < 1 { return shortTermStability(card.stability, r) }
                let ret = retrievability(elapsedDays: elapsed, stability: card.stability)
                return r == .again
                    ? forgetStability(d: card.difficulty, s: card.stability, r: ret)
                    : recallStability(d: card.difficulty, s: card.stability, r: ret, rating: r)
            }
            c.stability = stab(rating)
            applySteps(&c, steps: steps, state: card.state, rating: rating, step: card.step, now: now, stabilityFor: stab)

        case .review:
            let r = retrievability(elapsedDays: elapsed, stability: card.stability)
            c.difficulty = nextDifficulty(card.difficulty, rating)
            if rating == .again {
                c.lapses += 1
                c.stability = forgetStability(d: card.difficulty, s: card.stability, r: r)
                if let first = relearningSteps.first {
                    c.state = .relearning
                    c.step = 0
                    c.due = now.addingTimeInterval(first)
                } else {
                    c.due = now.addingDays(nextInterval(stability: c.stability))
                }
            } else {
                let sH = recallStability(d: card.difficulty, s: card.stability, r: r, rating: .hard)
                let sG = recallStability(d: card.difficulty, s: card.stability, r: r, rating: .good)
                let sE = recallStability(d: card.difficulty, s: card.stability, r: r, rating: .easy)
                var iH = nextInterval(stability: sH)
                var iG = nextInterval(stability: sG)
                var iE = nextInterval(stability: sE)
                iH = min(iH, iG)
                iG = max(iG, iH + 1)
                iE = max(iE, iG + 1)
                switch rating {
                case .hard: c.stability = sH; c.due = now.addingDays(iH)
                case .good: c.stability = sG; c.due = now.addingDays(iG)
                default: c.stability = sE; c.due = now.addingDays(iE)
                }
                c.state = .review
                c.step = 0
            }
        }
        c.lastReview = now
        return c
    }

    /// Shared step logic for new, learning and relearning cards.
    private func applySteps(
        _ c: inout SchedulingInfo, steps: [TimeInterval], state: CardState, rating: Rating, step: Int, now: Date,
        stabilityFor: (Rating) -> Double
    ) {
        func graduate(_ r: Rating) {
            var days = nextInterval(stability: stabilityFor(r))
            if r == .easy { days = max(days, nextInterval(stability: stabilityFor(.good)) + 1) }
            c.state = .review
            c.step = 0
            c.due = now.addingDays(days)
        }
        guard !steps.isEmpty else { return rating == .again ? graduate(.hard) : graduate(rating) }
        let current = min(step, steps.count - 1)
        switch rating {
        case .again:
            c.state = state
            c.step = 0
            c.due = now.addingTimeInterval(steps[0])
        case .hard:
            c.state = state
            c.step = current
            let delay = current == 0 && steps.count > 1 ? (steps[0] + steps[1]) / 2 : steps[current] * 1.5
            c.due = now.addingTimeInterval(delay)
        case .good:
            let next = current + 1
            if next < steps.count {
                c.state = state
                c.step = next
                c.due = now.addingTimeInterval(steps[next])
            } else {
                graduate(.good)
            }
        case .easy:
            graduate(.easy)
        }
    }
}

extension Date {
    func addingDays(_ days: Int) -> Date { addingTimeInterval(Double(days) * 86400) }
}

/// Short human label for an interval, e.g. "1m", "10m", "3d", "2mo".
func formatInterval(from now: Date, to due: Date) -> String {
    let s = max(0, due.timeIntervalSince(now))
    switch s {
    case ..<3600: return "\(max(1, Int((s / 60).rounded())))m"
    case ..<86400: return "\(Int((s / 3600).rounded()))h"
    case ..<(86400 * 30): return "\(Int((s / 86400).rounded()))d"
    case ..<(86400 * 365): return String(format: "%.1fmo", s / 86400 / 30)
    default: return String(format: "%.1fy", s / 86400 / 365)
    }
}
