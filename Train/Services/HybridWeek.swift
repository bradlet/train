//
//  HybridWeek.swift
//  Train
//
//  The Home hybrid hub (#19, roadmap H1/H2): one week of runs and lifts side
//  by side, and the hybrid hints evaluated over it. Pure and unit-tested; the
//  key-day rule is `PlacementRules`' (#25), so a hint and a board badge never
//  disagree, and hardness only ever comes from `Exercise.isKeyWorkout`.
//

import Foundation

/// One day of the hybrid week strip.
struct HybridDay: Identifiable, Equatable {
    /// The weekday lane (Sunday=0 ... Saturday=6).
    let weekday: Int
    /// Midnight on the day.
    let date: Date
    /// Cardio sessions planned or recorded that day.
    let cardioCount: Int
    /// Of those, how many are recorded.
    let cardioDone: Int
    /// Recorded (else planned) miles that day.
    let miles: Double
    /// Whether a session is marked ⚡ key.
    let hasKey: Bool
    /// Active strength cards in the lane.
    let liftCount: Int
    /// Of those, how many were recorded this week.
    let liftDone: Int
    /// The lane's load (lower / upper / empty).
    let liftLoad: LaneLoad

    var id: Int { weekday }

    /// Whether anything is planned or done that day.
    var hasTraining: Bool { cardioCount > 0 || liftCount > 0 }
}

/// A hybrid hint.
struct HybridHint: Identifiable, Equatable {
    enum Kind: String {
        case legsBeforeKey
        case strengthFloor
        case noRecoveryDay
        case regionGap
    }

    let kind: Kind
    /// The weekday it concerns, for day-specific hints.
    let weekday: Int?
    /// One line for the hub.
    let message: String

    var id: String { kind.rawValue + "#" + (weekday.map(String.init) ?? "") }
}

/// Builds the week strip and the hints.
enum HybridWeek {

    /// Fewer strength days than this a week earns a hint.
    static let strengthFloor = 2
    /// A region untouched this many days earns a hint.
    static let regionGapDays = 14

    /// The week's days in the athlete's week order.
    /// - Parameters:
    ///   - cardio: All cardio exercises.
    ///   - cards: All strength cards.
    ///   - records: All strength records.
    ///   - groups: Movement groups by id.
    ///   - now: Any moment in the week.
    ///   - firstWeekday: Calendar weekday convention (1=Sunday ... 7=Saturday).
    static func days(
        cardio: [Exercise],
        cards: [StrengthExercise],
        records: [StrengthRecord],
        groups: [String: MovementGroup],
        now: Date,
        firstWeekday: Int
    ) -> [HybridDay] {
        let week = StrengthWeek.interval(containing: now, firstWeekday: firstWeekday)
        let inWeek = cardio.filter { $0.date >= week.start && $0.date < week.end }
        let loads = PlacementRules.laneLoads(cards, groups: groups, library: MuscleBalance.bundledLibraryByID)
        let doneSlots = StrengthWeek.recordsBySlot(records, now: now, firstWeekday: firstWeekday)
        return (0..<7).map { offset in
            let date = Calendar.current.date(byAdding: .day, value: offset, to: week.start) ?? week.start
            let weekday = date.weekdayIndex
            let sessions = inWeek.filter { Calendar.current.isDate($0.date, inSameDayAs: date) }
            let lane = StrengthBoardPlanner.lane(cards, day: weekday, offloaded: false)
            return HybridDay(
                weekday: weekday,
                date: date,
                cardioCount: sessions.count,
                cardioDone: sessions.filter(\.isCompleted).count,
                miles: sessions.reduce(0) { $0 + ($1.workout?.distanceMiles ?? $1.distanceMiles) },
                hasKey: sessions.contains(where: \.isKeyWorkout),
                liftCount: lane.count,
                liftDone: lane.filter { doneSlots[$0.id] != nil }.count,
                liftLoad: loads[weekday]
            )
        }
    }

    /// "5 of 9 done": sessions done and planned across both tracks.
    static func progress(_ days: [HybridDay]) -> (done: Int, total: Int) {
        days.reduce((0, 0)) { ($0.0 + $1.cardioDone + $1.liftDone, $0.1 + $1.cardioCount + $1.liftCount) }
    }

    /// The hybrid hints for the week.
    ///
    /// - Legs before a key workout: a lower-body lane the day before a day
    ///   with a session the athlete marked key (never inferred).
    /// - Strength floor: fewer than two strength days this week.
    /// - No recovery day: training on all seven days.
    /// - Region gap: a major region not lifted in 14 days.
    /// A light week relaxes them to nothing (until light weeks exist, #20).
    /// - Parameters:
    ///   - days: The week strip.
    ///   - records: All strength records, for region gaps.
    ///   - lifts: All lifts, for their muscle groups.
    ///   - now: The current moment.
    ///   - isLightWeek: Whether this is a planned light week.
    static func hints(
        _ days: [HybridDay],
        records: [StrengthRecord],
        lifts: [StrengthLift],
        now: Date,
        isLightWeek: Bool = false
    ) -> [HybridHint] {
        guard !isLightWeek, days.count == 7 else { return [] }
        var hints: [HybridHint] = []
        let byWeekday = Dictionary(uniqueKeysWithValues: days.map { ($0.weekday, $0) })

        for day in days where day.liftLoad == .lower && !day.hasKey {
            if byWeekday[(day.weekday + 1) % 7]?.hasKey == true {
                let name = Calendar.current.weekdaySymbols[day.weekday]
                hints.append(HybridHint(kind: .legsBeforeKey, weekday: day.weekday,
                                        message: "Leg day on \(name) is the day before a key workout."))
            }
        }

        let strengthDays = days.filter { $0.liftCount > 0 }.count
        if strengthDays < strengthFloor {
            hints.append(HybridHint(kind: .strengthFloor, weekday: nil,
                                    message: strengthDays == 0
                                        ? "No strength days planned this week. Two keep you durable."
                                        : "Only one strength day this week. Two keep you durable."))
        }

        if days.allSatisfy(\.hasTraining) {
            hints.append(HybridHint(kind: .noRecoveryDay, weekday: nil,
                                    message: "Training all seven days. Keep one as a recovery day."))
        }

        let gaps = untouchedRegions(records: records, lifts: lifts, now: now)
        if !gaps.isEmpty {
            let names = gaps.map(\.rawValue).joined(separator: ", ")
            hints.append(HybridHint(kind: .regionGap, weekday: nil,
                                    message: "\(names) not trained in 2+ weeks."))
        }
        return hints
    }

    /// Major regions with no lift recorded in the last 14 days — only once
    /// the athlete has some strength history, so a new athlete isn't nagged.
    static func untouchedRegions(records: [StrengthRecord], lifts: [StrengthLift], now: Date) -> [BodyRegion] {
        guard !records.isEmpty else { return [] }
        let since = Calendar.current.date(byAdding: .day, value: -regionGapDays, to: now) ?? now
        var trained = Set<BodyRegion>()
        for record in records where record.date >= since && record.date <= now {
            trained.formUnion(regions(forLiftKey: record.liftKey, lifts: lifts))
        }
        return BodyRegion.allCases.filter { !trained.contains($0) }
    }

    /// A lift's regions: its library pattern, else its muscle group.
    static func regions(forLiftKey key: String, lifts: [StrengthLift]) -> Set<BodyRegion> {
        if let pattern = MuscleBalance.bundledLibraryByID[key]?.pattern {
            return MuscleBalance.regions(for: pattern)
        }
        let muscle = StrengthLiftRegistry.lift(forKey: key, in: lifts)?.muscleGroup ?? .other
        return MuscleBalance.regions(for: muscle)
    }
}

// MARK: - Dismissals

/// "Dismiss for this week" on a hint: "weekStart#hintID" tokens that lapse
/// when the week rolls over.
enum HintDismissals {

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static func week(_ now: Date, _ firstWeekday: Int) -> String {
        formatter.string(from: now.startOfWeek(firstWeekday: firstWeekday))
    }

    /// The hints not dismissed this week.
    static func visible(_ hints: [HybridHint], in raw: String, now: Date, firstWeekday: Int) -> [HybridHint] {
        let tokens = Set(raw.split(separator: ",").map(String.init))
        let prefix = week(now, firstWeekday) + "#"
        return hints.filter { !tokens.contains(prefix + $0.id) }
    }

    /// Adds a dismissal, dropping other weeks' tokens.
    static func dismiss(_ hint: HybridHint, in raw: String, now: Date, firstWeekday: Int) -> String {
        let prefix = week(now, firstWeekday) + "#"
        var tokens = raw.split(separator: ",").map(String.init).filter { $0.hasPrefix(prefix) }
        let token = prefix + hint.id
        if !tokens.contains(token) { tokens.append(token) }
        return tokens.joined(separator: ",")
    }
}
