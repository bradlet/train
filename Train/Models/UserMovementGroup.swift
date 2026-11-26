//
//  UserMovementGroup.swift
//  Train
//
//  The athlete's own movement groups (#24), and every edit to a built-in:
//  editing a bundled group writes a row with the built-in's id
//  (copy-on-write), so app updates never overwrite the athlete's changes.
//  Read and written as a `MovementGroup` value through `group` / `update`.
//  CloudKit-safe: every field defaulted, arrays stored as JSON `Data`
//  (like `UserLibraryExercise.secondaryMuscleGroupsData`).
//

import Foundation
import SwiftData

@Model
final class UserMovementGroup {
    /// The group id: a built-in's "group-…" id when this row edits it,
    /// otherwise "user-group-<uuid>". Board cards reference it by
    /// `StrengthExercise.groupID`. Duplicates from sync resolve to the oldest.
    var groupID: String = MovementGroup.userPrefix + UUID().uuidString
    /// Display name, e.g. "Chest Press".
    var name: String = ""
    /// Raw `MovementPattern`, or `nil`. Access through `group`.
    private var patternRaw: String? = nil
    /// JSON `[GroupMember]`. Access through `group`.
    private var membersData: Data? = nil
    /// JSON `[String]` of paused lift keys. Access through `group`.
    private var pausedLiftKeysData: Data? = nil
    /// Raw `GroupRotationMode`. Access through `group`.
    private var rotationModeRaw: String = GroupRotationMode.shuffleWithinBlock.rawValue
    /// Block length in weeks for one-member-per-block.
    var blockWeeks: Int = 4
    /// The week blocks count from.
    var blockAnchor: Date? = nil
    /// "Hold this one instead" override and the block it applies to.
    var heldLiftKey: String? = nil
    var heldBlockIndex: Int? = nil
    /// Creation timestamp, for duplicate resolution and stable order.
    var createdAt: Date = Date()

    /// Creates a row holding `group`.
    /// - Parameter group: The group to store.
    init(_ group: MovementGroup) {
        self.groupID = group.id
        self.createdAt = Date()
        update(from: group)
    }

    /// This row as the value the app uses.
    var group: MovementGroup {
        let decoder = JSONDecoder()
        let members = membersData.flatMap { try? decoder.decode([GroupMember].self, from: $0) } ?? []
        let paused = pausedLiftKeysData.flatMap { try? decoder.decode([String].self, from: $0) } ?? []
        return MovementGroup(
            id: groupID,
            name: name,
            pattern: patternRaw.flatMap(MovementPattern.init(rawValue:)),
            members: members,
            pausedLiftKeys: Set(paused),
            rotationMode: GroupRotationMode(rawValue: rotationModeRaw) ?? .shuffleWithinBlock,
            blockWeeks: max(blockWeeks, 1),
            blockAnchor: blockAnchor,
            heldLiftKey: heldLiftKey,
            heldBlockIndex: heldBlockIndex
        )
    }

    /// Overwrites every field but the id from `group`.
    /// - Parameter group: The edited group.
    func update(from group: MovementGroup) {
        let encoder = JSONEncoder()
        name = group.name
        patternRaw = group.pattern?.rawValue
        membersData = try? encoder.encode(group.members)
        pausedLiftKeysData = group.pausedLiftKeys.isEmpty ? nil : try? encoder.encode(group.pausedLiftKeys.sorted())
        rotationModeRaw = group.rotationMode.rawValue
        blockWeeks = max(group.blockWeeks, 1)
        blockAnchor = group.blockAnchor
        heldLiftKey = group.heldLiftKey
        heldBlockIndex = group.heldBlockIndex
    }
}
