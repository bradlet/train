//
//  StrengthSlotResolver.swift
//  Train
//
//  What a board card records (#24). A single-lift card records its own lift;
//  a group card records its group's up-next member (`GroupRotation`). Every
//  save path — the record sheet, the whole-day sheet, "Log lifts as
//  planned" — resolves a `LiftTarget` here instead of reading
//  `StrengthExercise.liftKey`, which is meaningless for a group card.
//  `MovementGroupStore` is the one write path for groups (copy-on-write).
//

import Foundation
import SwiftData

/// The lift a record is written against.
struct LiftTarget: Equatable, Hashable {
    /// The lift key the record gets.
    let liftKey: String
    /// The lift's display name.
    let name: String
    /// Library provenance, for creating the lift.
    let libraryExerciseID: String?
    /// Muscle group, for creating the lift and tinting rows.
    let muscleGroup: MuscleGroup
    /// The metric a newly created lift gets (an existing lift keeps its own).
    let defaultMetric: LiftMetric

    /// Creates a target.
    init(liftKey: String, name: String, libraryExerciseID: String?, muscleGroup: MuscleGroup, defaultMetric: LiftMetric) {
        self.liftKey = liftKey
        self.name = name
        self.libraryExerciseID = libraryExerciseID
        self.muscleGroup = muscleGroup
        self.defaultMetric = defaultMetric
    }

    /// A single-lift card's own lift.
    init(slot: StrengthExercise) {
        liftKey = slot.liftKey
        name = slot.name
        libraryExerciseID = slot.libraryExerciseID
        muscleGroup = slot.muscleGroup
        defaultMetric = .weight
    }

    /// A group member.
    init(member: GroupMember) {
        liftKey = member.liftKey
        name = member.name
        libraryExerciseID = member.libraryID
        muscleGroup = member.muscleGroup
        defaultMetric = member.primaryMetric
    }
}

/// Resolves cards to the lifts they record, reading from a context.
enum StrengthSlotResolver {

    /// Every group, built-in and the athlete's, by id.
    /// - Parameter context: The context to read `UserMovementGroup` rows from.
    static func groups(in context: ModelContext) -> [String: MovementGroup] {
        let rows = (try? context.fetch(FetchDescriptor<UserMovementGroup>(sortBy: [SortDescriptor(\.createdAt)]))) ?? []
        return byID(MovementGroupCatalog.merged(builtIns: MovementGroupCatalog.bundled, user: rows.map(\.group)))
    }

    /// Groups keyed by id.
    static func byID(_ groups: [MovementGroup]) -> [String: MovementGroup] {
        Dictionary(groups.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// The target for each card: its own lift, or its group's assignment.
    /// A group card whose group is gone falls back to its own name.
    /// - Parameters:
    ///   - slots: The cards to resolve.
    ///   - context: The context to read groups, cards and records from.
    ///   - now: The current moment.
    ///   - firstWeekday: Calendar weekday convention (1=Sunday ... 7=Saturday).
    static func targets(
        for slots: [StrengthExercise],
        in context: ModelContext,
        now: Date = Date(),
        firstWeekday: Int
    ) -> [UUID: LiftTarget] {
        guard slots.contains(where: \.isGroup) else {
            return Dictionary(slots.map { ($0.id, LiftTarget(slot: $0)) }, uniquingKeysWith: { first, _ in first })
        }
        let allSlots = (try? context.fetch(FetchDescriptor<StrengthExercise>())) ?? slots
        let records = (try? context.fetch(FetchDescriptor<StrengthRecord>())) ?? []
        let assignments = GroupRotation.assignments(
            slots: allSlots, groups: groups(in: context), records: records, now: now, firstWeekday: firstWeekday
        )
        var result: [UUID: LiftTarget] = [:]
        for slot in slots {
            result[slot.id] = assignments[slot.id].map { LiftTarget(member: $0.member) } ?? LiftTarget(slot: slot)
        }
        return result
    }

    /// One card's target.
    static func target(
        for slot: StrengthExercise,
        in context: ModelContext,
        now: Date = Date(),
        firstWeekday: Int
    ) -> LiftTarget {
        targets(for: [slot], in: context, now: now, firstWeekday: firstWeekday)[slot.id] ?? LiftTarget(slot: slot)
    }
}

/// The one write path for movement groups.
enum MovementGroupStore {

    /// Saves a group: updates the athlete's row for its id (the oldest, if
    /// sync made duplicates), or inserts one — which is how editing a
    /// built-in copies it. Cards planning the group take its name and tint.
    /// - Parameters:
    ///   - group: The edited group.
    ///   - context: The context to write to.
    static func save(_ group: MovementGroup, in context: ModelContext) {
        let id = group.id
        let descriptor = FetchDescriptor<UserMovementGroup>(
            predicate: #Predicate { $0.groupID == id },
            sortBy: [SortDescriptor(\.createdAt)]
        )
        if let existing = (try? context.fetch(descriptor))?.first {
            existing.update(from: group)
        } else {
            context.insert(UserMovementGroup(group))
        }
        let slots = (try? context.fetch(FetchDescriptor<StrengthExercise>(predicate: #Predicate { $0.groupID == id }))) ?? []
        for slot in slots {
            slot.name = group.name
            slot.muscleGroup = group.muscleGroup
        }
    }

    /// Saves a group and makes `slot` plan it ("Make This a Group").
    /// - Parameters:
    ///   - group: The new group.
    ///   - slot: The card that becomes a group card.
    ///   - context: The context to write to.
    static func assign(_ group: MovementGroup, to slot: StrengthExercise, in context: ModelContext) {
        slot.groupID = group.id
        slot.libraryExerciseID = nil
        save(group, in: context)
        slot.name = group.name
        slot.muscleGroup = group.muscleGroup
    }

    /// Restores a built-in to the bundled version by deleting the athlete's
    /// copy. Does nothing for the athlete's own groups.
    static func revert(_ groupID: String, in context: ModelContext) {
        guard groupID.hasPrefix(MovementGroup.builtInPrefix) else { return }
        let descriptor = FetchDescriptor<UserMovementGroup>(predicate: #Predicate { $0.groupID == groupID })
        for row in (try? context.fetch(descriptor)) ?? [] { context.delete(row) }
    }
}
