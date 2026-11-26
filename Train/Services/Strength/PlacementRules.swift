//
//  PlacementRules.swift
//  Train
//
//  Run-aware strength placement (#25): one pure rule engine shared by the
//  board's day-chip markers, lane badges and "Arrange my week" (and later
//  the Home hybrid hints, #19).
//
//  - Cardio days are Key / Easy / Rest from `Exercise.isKeyWorkout` ONLY —
//    the app never infers hardness from type, distance, pace or RPE. With
//    nothing marked, there are no key days and the rules stay quiet.
//  - A lane is lower-heavy if it holds a squat, hinge, single-leg or power
//    card (by pattern; else quads, hamstrings, glutes or full body).
//  - Lower-heavy lanes stack on key days (or avoid them, if the athlete
//    keeps key days lift-free), avoid the day before a key day, and want
//    48 h between them. Upper/core lanes are fine anywhere.
//
//  The board is a weekly template, so "the day before" wraps (Saturday is
//  the day before Sunday).
//

import Foundation

/// A day's cardio, as the athlete marked it.
enum CardioDayClass: Equatable {
    /// At least one session marked ⚡ key.
    case key
    /// Cardio, none of it key.
    case easy
    /// No cardio.
    case rest

    /// The chip marker: ⚡, •, or nothing.
    var marker: String {
        switch self {
        case .key: return "⚡"
        case .easy: return "•"
        case .rest: return ""
        }
    }
}

/// What a strength lane loads.
enum LaneLoad: Equatable {
    /// No active cards.
    case empty
    /// Upper body or core only.
    case upper
    /// At least one lower-body card.
    case lower
}

/// The verdict for a lane on its day.
enum PlacementVerdict: Equatable {
    /// A good spot.
    case good
    /// Lower body on a key day, stacked after the key workout.
    case stack
    /// Allowed but not ideal (lower body on a rest day).
    case neutral
    /// A conflict, with the reason shown on the badge.
    case avoid(String)

    /// The conflict reason, if any.
    var conflict: String? {
        if case .avoid(let reason) = self { return reason }
        return nil
    }
}

/// The placement rules.
enum PlacementRules {

    /// Badge text for a lower-heavy lane on the day before a key day.
    static let dayBeforeKey = "Heavy legs the day before your key workout"
    /// Badge text for a lower-heavy lane on a key day under lift-free.
    static let keyDayLiftFree = "You keep key days lift-free"
    /// Badge text for lower-heavy lanes on consecutive days.
    static let tooClose = "Leg days less than 48 h apart"
    /// The same-day cue under the Stack strategy.
    static let stackCue = "Key workout first, lift later if you can"

    // MARK: Classification

    /// Each weekday lane's cardio class (index = weekdayIndex, Sunday=0) in
    /// the week containing `now`, from planned and recorded sessions.
    /// - Parameters:
    ///   - exercises: All cardio exercises.
    ///   - now: Any moment in the week.
    ///   - firstWeekday: Calendar weekday convention (1=Sunday ... 7=Saturday).
    static func cardioClasses(_ exercises: [Exercise], weekContaining now: Date, firstWeekday: Int) -> [CardioDayClass] {
        let week = StrengthWeek.interval(containing: now, firstWeekday: firstWeekday)
        var classes = Array(repeating: CardioDayClass.rest, count: 7)
        for exercise in exercises where exercise.date >= week.start && exercise.date < week.end {
            let day = exercise.date.weekdayIndex
            if exercise.isKeyWorkout {
                classes[day] = .key
            } else if classes[day] == .rest {
                classes[day] = .easy
            }
        }
        return classes
    }

    /// Whether a card loads the legs: its group's or library entry's
    /// pattern, else its muscle group.
    static func isLowerBody(_ card: StrengthExercise, groups: [String: MovementGroup], library: [String: LibraryExercise]) -> Bool {
        let pattern = card.groupID.flatMap { groups[$0]?.pattern }
            ?? card.libraryExerciseID.flatMap { library[$0]?.pattern }
        if let pattern {
            switch pattern {
            case .squat, .hinge, .singleLeg, .power: return true
            default: return false
            }
        }
        switch card.muscleGroup {
        case .quads, .hamstrings, .glutes, .fullBody: return true
        default: return false
        }
    }

    /// Each weekday lane's load (index = weekdayIndex), from active cards.
    static func laneLoads(_ cards: [StrengthExercise], groups: [String: MovementGroup], library: [String: LibraryExercise]) -> [LaneLoad] {
        (0..<7).map { day in
            let lane = cards.filter { $0.weekdayIndex == day && !$0.isOffloaded }
            if lane.isEmpty { return .empty }
            return lane.contains { isLowerBody($0, groups: groups, library: library) } ? .lower : .upper
        }
    }

    // MARK: Verdicts

    /// A lane's verdict on its day (the doc's placement table).
    /// - Parameters:
    ///   - load: The lane's load.
    ///   - day: The weekday lane.
    ///   - cardio: Cardio classes by weekday.
    ///   - strategy: The athlete's key-day strategy.
    static func verdict(_ load: LaneLoad, day: Int, cardio: [CardioDayClass], strategy: KeyDayStrategy) -> PlacementVerdict {
        guard load == .lower else { return .good }
        if cardio[day] == .key {
            return strategy == .stack ? .stack : .avoid(keyDayLiftFree)
        }
        if cardio[(day + 1) % 7] == .key { return .avoid(dayBeforeKey) }
        return cardio[day] == .easy ? .good : .neutral
    }

    /// Lanes in a ⚠️ spot, with the reason: the placement table, plus a soft
    /// warning on the later of two lower-heavy lanes on consecutive days.
    static func conflicts(_ loads: [LaneLoad], cardio: [CardioDayClass], strategy: KeyDayStrategy) -> [Int: String] {
        var result: [Int: String] = [:]
        for day in 0..<7 {
            if let reason = verdict(loads[day], day: day, cardio: cardio, strategy: strategy).conflict {
                result[day] = reason
            } else if loads[day] == .lower, loads[(day + 6) % 7] == .lower {
                result[day] = tooClose
            }
        }
        return result
    }

    /// Whether Today should show the stack cue: a key session and a
    /// lower-heavy lane on the same day, under the Stack strategy.
    static func showsStackCue(load: LaneLoad, cardio: CardioDayClass, strategy: KeyDayStrategy) -> Bool {
        strategy == .stack && load == .lower && cardio == .key
    }
}

// MARK: - Arranger

/// "Arrange my week": the smallest whole-lane shuffle that fixes conflicts.
enum WeekArranger {

    /// A lane moving from one weekday to another.
    struct Move: Equatable {
        let from: Int
        let to: Int
    }

    /// A proposed arrangement.
    struct Proposal: Equatable {
        /// Where each weekday's lane goes (index = old day, value = new day).
        let destination: [Int]
        /// The non-empty lanes that move.
        let moves: [Move]
        /// Conflict cost before and after.
        let costBefore: Double
        let costAfter: Double
    }

    /// How bad an arrangement is: conflicts dominate, then lower body on a
    /// rest day, then upper body away from easy days (a mild preference).
    static func cost(_ loads: [LaneLoad], cardio: [CardioDayClass], strategy: KeyDayStrategy) -> Double {
        var total = 0.0
        for day in 0..<7 {
            switch PlacementRules.verdict(loads[day], day: day, cardio: cardio, strategy: strategy) {
            case .avoid: total += 10
            case .neutral: total += 1
            case .good, .stack: break
            }
            if loads[day] == .lower, loads[(day + 6) % 7] == .lower { total += 3 }
            if loads[day] == .upper, cardio[day] != .easy { total += 0.2 }
        }
        return total
    }

    /// The best whole-lane arrangement, or `nil` when nothing beats the
    /// current week. Brute force over every permutation of the unpinned
    /// lanes (at most 7! = 5,040); each moved lane costs one point, so the
    /// smallest fix wins, and ties keep the first found (deterministic).
    /// - Parameters:
    ///   - loads: Lane loads by weekday.
    ///   - cardio: Cardio classes by weekday.
    ///   - pinned: Weekdays whose lane must stay.
    ///   - strategy: The athlete's key-day strategy.
    static func propose(
        loads: [LaneLoad],
        cardio: [CardioDayClass],
        pinned: Set<Int>,
        strategy: KeyDayStrategy
    ) -> Proposal? {
        let before = cost(loads, cardio: cardio, strategy: strategy)
        let free = (0..<7).filter { !pinned.contains($0) }
        var best: (destination: [Int], score: Double, conflictCost: Double)?

        func evaluate(_ destination: [Int]) {
            var arranged = Array(repeating: LaneLoad.empty, count: 7)
            var moved = 0
            for day in 0..<7 {
                arranged[destination[day]] = loads[day]
                if destination[day] != day && loads[day] != .empty { moved += 1 }
            }
            let conflictCost = cost(arranged, cardio: cardio, strategy: strategy)
            let score = conflictCost + Double(moved)
            if best == nil || score < best!.score - 1e-9 {
                best = (destination, score, conflictCost)
            }
        }

        var destination = Array(0..<7)
        func permute(_ index: Int, _ remaining: [Int]) {
            if index == free.count {
                evaluate(destination)
                return
            }
            for (i, day) in remaining.enumerated() {
                destination[free[index]] = day
                var rest = remaining
                rest.remove(at: i)
                permute(index + 1, rest)
            }
        }
        permute(0, free)

        guard let best, best.conflictCost < before - 1e-9 else { return nil }
        let moves = (0..<7)
            .filter { best.destination[$0] != $0 && loads[$0] != .empty }
            .map { Move(from: $0, to: best.destination[$0]) }
        guard !moves.isEmpty else { return nil }
        return Proposal(destination: best.destination, moves: moves, costBefore: before, costAfter: best.conflictCost)
    }

    /// Moves every card (active and offloaded) to its lane's new weekday.
    /// - Returns: Each moved card's previous weekday, for Undo.
    @discardableResult
    static func apply(_ proposal: Proposal, to cards: [StrengthExercise]) -> [UUID: Int] {
        var previous: [UUID: Int] = [:]
        for card in cards {
            let target = proposal.destination[card.weekdayIndex]
            if target != card.weekdayIndex {
                previous[card.id] = card.weekdayIndex
                card.weekdayIndex = target
            }
        }
        return previous
    }

    /// Puts cards back where `apply` found them.
    static func undo(_ previous: [UUID: Int], cards: [StrengthExercise]) {
        for card in cards {
            if let day = previous[card.id] { card.weekdayIndex = day }
        }
    }
}

// MARK: - Dismissals

/// "Dismiss for this week" on a lane badge: stored as "weekStart#day"
/// tokens, so a dismissal lapses when the week rolls over.
enum PlacementDismissals {

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// The token for a lane in the week containing `now`.
    static func token(day: Int, now: Date, firstWeekday: Int) -> String {
        formatter.string(from: now.startOfWeek(firstWeekday: firstWeekday)) + "#\(day)"
    }

    /// Whether a lane's badge is dismissed this week.
    static func isDismissed(day: Int, in raw: String, now: Date, firstWeekday: Int) -> Bool {
        raw.split(separator: ",").contains { String($0) == token(day: day, now: now, firstWeekday: firstWeekday) }
    }

    /// Adds a dismissal, dropping tokens from other weeks.
    static func dismiss(day: Int, in raw: String, now: Date, firstWeekday: Int) -> String {
        let week = formatter.string(from: now.startOfWeek(firstWeekday: firstWeekday))
        var tokens = raw.split(separator: ",").map(String.init).filter { $0.hasPrefix(week + "#") }
        let token = token(day: day, now: now, firstWeekday: firstWeekday)
        if !tokens.contains(token) { tokens.append(token) }
        return tokens.joined(separator: ",")
    }
}
