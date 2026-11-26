//
//  StrengthBoardCopier.swift
//  Train
//
//  Copy a whole day's plan to another day, or duplicate one card onto
//  another day (#18, roadmap A3). A copy is a new card for the same lift (or
//  movement group) with the same sets × reps; history belongs to the lift,
//  so copies share it. A card whose lift or group is already planned on the
//  target day is skipped, never doubled. Pure apart from `insert`.
//

import Foundation
import SwiftData

/// Duplicates board cards across days.
enum StrengthBoardCopier {

    /// What a copy did.
    struct Outcome: Equatable {
        /// Cards added to the target day.
        var copied: [String] = []
        /// Names skipped because the target day already plans them.
        var skipped: [String] = []
    }

    /// The identity two cards share when they plan the same thing: the group
    /// for a group card, otherwise the lift.
    static func planKey(_ card: StrengthExercise) -> String {
        card.groupID.map { "group:" + $0 } ?? "lift:" + card.liftKey
    }

    /// A new card copying `card` onto a day's active plan, at the end.
    /// - Parameters:
    ///   - card: The card to copy.
    ///   - day: The target lane (Sunday=0 ... Saturday=6).
    ///   - sortOrder: Its position in the target lane.
    static func copy(of card: StrengthExercise, toDay day: Int, sortOrder: Int) -> StrengthExercise {
        StrengthExercise(
            name: card.name,
            libraryExerciseID: card.libraryExerciseID,
            muscleGroup: card.muscleGroup,
            weekdayIndex: day,
            isOffloaded: false,
            sortOrder: sortOrder,
            notes: card.notes,
            plannedSets: card.plannedSets,
            plannedReps: card.plannedReps,
            groupID: card.groupID
        )
    }

    /// Copies cards onto a day's active plan, in order, skipping any whose
    /// lift or group the day already plans.
    /// - Parameters:
    ///   - cards: The cards to copy (a lane, or one card).
    ///   - day: The target lane.
    ///   - all: Every card, for the target lane's contents and order.
    ///   - context: The context to insert into.
    @discardableResult
    static func copy(
        _ cards: [StrengthExercise],
        toDay day: Int,
        all: [StrengthExercise],
        in context: ModelContext
    ) -> Outcome {
        var outcome = Outcome()
        var planned = Set(StrengthBoardPlanner.lane(all, day: day, offloaded: false).map(planKey))
        var order = StrengthBoardPlanner.nextSortOrder(all, day: day, offloaded: false)
        for card in cards {
            guard planned.insert(planKey(card)).inserted else {
                outcome.skipped.append(card.name)
                continue
            }
            context.insert(copy(of: card, toDay: day, sortOrder: order))
            order += 1
            outcome.copied.append(card.name)
        }
        return outcome
    }

    /// A short confirmation, e.g. "Copied 3 lifts to Thursday" or
    /// "Copied 1 lift to Friday · 2 already there".
    static func message(_ outcome: Outcome, dayName: String) -> String {
        let count = outcome.copied.count
        var text = count == 0 ? "Nothing new to copy to \(dayName)"
            : "Copied \(count == 1 ? "1 lift" : "\(count) lifts") to \(dayName)"
        if !outcome.skipped.isEmpty, count > 0 { text += " · \(outcome.skipped.count) already there" }
        return text
    }
}

// MARK: - Muscle balance

/// A training region for the board's balance glance (#18, roadmap A2).
enum BodyRegion: String, CaseIterable, Identifiable {
    case push = "Push"
    case pull = "Pull"
    case legsFront = "Quads"
    case legsBack = "Posterior"
    case core = "Core"

    var id: String { rawValue }

    /// A symbol for the chip.
    var systemImage: String {
        switch self {
        case .push: return "arrow.up.forward"
        case .pull: return "arrow.down.backward"
        case .legsFront: return "figure.step.training"
        case .legsBack: return "figure.strengthtraining.functional"
        case .core: return "figure.core.training"
        }
    }
}

/// Which regions the week's active plan covers.
enum MuscleBalance {

    /// The regions a movement pattern loads.
    static func regions(for pattern: MovementPattern) -> Set<BodyRegion> {
        switch pattern {
        case .horizontalPush, .verticalPush: return [.push]
        case .horizontalPull, .verticalPull: return [.pull]
        case .squat: return [.legsFront]
        case .hinge, .calves: return [.legsBack]
        case .singleLeg, .power: return [.legsFront, .legsBack]
        case .core: return [.core]
        }
    }

    /// The regions a muscle group loads, when there's no pattern.
    static func regions(for muscle: MuscleGroup) -> Set<BodyRegion> {
        switch muscle {
        case .chest, .shoulders, .triceps: return [.push]
        case .back, .biceps, .forearms: return [.pull]
        case .quads: return [.legsFront]
        case .hamstrings, .glutes, .calves: return [.legsBack]
        case .core: return [.core]
        case .fullBody: return [.push, .pull, .legsFront, .legsBack]
        case .other: return []
        }
    }

    /// The regions one card covers: its group's or library entry's pattern
    /// when known, else its muscle group.
    /// - Parameters:
    ///   - card: The card.
    ///   - groups: Movement groups by id.
    ///   - library: Library entries by id.
    static func regions(
        for card: StrengthExercise,
        groups: [String: MovementGroup],
        library: [String: LibraryExercise]
    ) -> Set<BodyRegion> {
        if let groupID = card.groupID, let pattern = groups[groupID]?.pattern {
            return regions(for: pattern)
        }
        if let id = card.libraryExerciseID, let pattern = library[id]?.pattern {
            return regions(for: pattern)
        }
        return regions(for: card.muscleGroup)
    }

    /// The regions the week's active plan covers (offloaded cards don't
    /// count — they're out of the week's plan).
    static func covered(
        _ cards: [StrengthExercise],
        groups: [String: MovementGroup],
        library: [String: LibraryExercise]
    ) -> Set<BodyRegion> {
        cards.filter { !$0.isOffloaded }
            .reduce(into: Set<BodyRegion>()) { $0.formUnion(regions(for: $1, groups: groups, library: library)) }
    }

    /// The bundled library by id, for pattern lookups.
    static let bundledLibraryByID: [String: LibraryExercise] = Dictionary(
        MovementGroupCatalog.bundledLibrary.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }
    )
}
