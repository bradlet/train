//
//  MovementGroup.swift
//  Train
//
//  Movement groups (#24): plan a *movement* (Chest Press) instead of one lift
//  (Barbell Bench Press), and the board rotates which member comes up. A
//  group is a value type merged from the bundled catalog
//  (`StrengthMovementGroups.json`) and the athlete's own `UserMovementGroup`
//  rows, which also hold every edit to a built-in (copy-on-write). Each member
//  is an ordinary lift with its own history, so machine press and barbell
//  bench numbers never mix. Rotation is computed by `GroupRotation`.
//

import Foundation

/// What makes lifts interchangeable in a group: the movement, not the
/// muscle, so flys never end up in a press rotation.
enum MovementPattern: String, Codable, CaseIterable, Identifiable, Sendable {
    case horizontalPush = "horizontal push"
    case verticalPush = "vertical push"
    case horizontalPull = "horizontal pull"
    case verticalPull = "vertical pull"
    case squat
    case hinge
    case singleLeg = "single leg"
    case core
    case calves
    case power

    var id: String { rawValue }

    /// Display name, e.g. "Horizontal push".
    var displayName: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }

    /// Whether the pattern loads the legs (for run-aware placement later).
    var isLowerBody: Bool {
        switch self {
        case .squat, .hinge, .singleLeg, .calves, .power: return true
        case .horizontalPush, .verticalPush, .horizontalPull, .verticalPull, .core: return false
        }
    }
}

/// How a group picks its member.
enum GroupRotationMode: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Smart rotation every workout: the least-recently-done member.
    case shuffleWithinBlock
    /// Hold one member for a whole block so it can progress, then rotate.
    case onePerBlock

    var id: String { rawValue }

    /// Display name for the rotation toggle.
    var displayName: String {
        switch self {
        case .shuffleWithinBlock: return "Shuffle within a block"
        case .onePerBlock: return "One member per block"
        }
    }
}

/// One lift in a group, denormalised so a card can show and record it
/// without loading the library.
struct GroupMember: Codable, Hashable, Identifiable, Sendable {
    /// Library entry id (bundled slug or "user-…").
    let libraryID: String
    /// Display name.
    let name: String
    /// Primary muscle group.
    let muscleGroup: MuscleGroup
    /// The lift's metric, for creating its `StrengthLift`.
    let primaryMetric: LiftMetric

    var id: String { liftKey }

    /// The member's lift key — its library id.
    var liftKey: String { StrengthLiftKey.make(libraryID: libraryID, name: name) }

    /// A member from a library entry.
    init(_ entry: LibraryExercise) {
        self.init(libraryID: entry.id, name: entry.name, muscleGroup: entry.muscleGroup, primaryMetric: entry.primaryMetric)
    }

    /// Creates a member.
    init(libraryID: String, name: String, muscleGroup: MuscleGroup, primaryMetric: LiftMetric) {
        self.libraryID = libraryID
        self.name = name
        self.muscleGroup = muscleGroup
        self.primaryMetric = primaryMetric
    }

    /// Tolerant decoding: unknown muscle groups read as `.other` (via
    /// `MuscleGroup`) and unknown metrics as weight.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        libraryID = try container.decode(String.self, forKey: .libraryID)
        name = try container.decode(String.self, forKey: .name)
        muscleGroup = (try? container.decode(MuscleGroup.self, forKey: .muscleGroup)) ?? .other
        let metricRaw = try container.decodeIfPresent(String.self, forKey: .primaryMetric)
        primaryMetric = metricRaw.flatMap(LiftMetric.init(rawValue:)) ?? .weight
    }
}

/// A movement group as the app uses it: a built-in, a built-in the athlete
/// edited, or one of their own.
struct MovementGroup: Hashable, Identifiable, Sendable {
    /// Bundled ids start with "group-"; the athlete's own with "user-group-".
    let id: String
    var name: String
    var pattern: MovementPattern?
    /// Members in the athlete's order (ties in rotation go to the earlier).
    var members: [GroupMember]
    /// Lift keys out of rotation for now; they keep their history.
    var pausedLiftKeys: Set<String> = []
    var rotationMode: GroupRotationMode = .shuffleWithinBlock
    /// Block length in weeks for one-member-per-block in a steady plan.
    var blockWeeks: Int = 4
    /// The week blocks count from (when one-per-block was switched on).
    var blockAnchor: Date? = nil
    /// "Hold this one instead": the held member for block `heldBlockIndex`.
    var heldLiftKey: String? = nil
    var heldBlockIndex: Int? = nil
    /// Whether this group is (or was copied from) a bundled one.
    var isBuiltIn: Bool { id.hasPrefix(Self.builtInPrefix) }

    /// Prefix on bundled group ids.
    static let builtInPrefix = "group-"
    /// Prefix on athlete-created group ids.
    static let userPrefix = "user-group-"

    /// Members still in rotation, in order; every member when all are paused
    /// (a group never has nothing to offer).
    var activeMembers: [GroupMember] {
        let active = members.filter { !pausedLiftKeys.contains($0.liftKey) }
        return active.isEmpty ? members : active
    }

    /// The card tint: the first member's muscle group.
    var muscleGroup: MuscleGroup { members.first?.muscleGroup ?? .other }

    /// The member with a lift key, if it belongs to the group.
    func member(forLiftKey key: String) -> GroupMember? {
        members.first { $0.liftKey == key }
    }
}

// MARK: - Bundled catalog

/// One group as written in `StrengthMovementGroups.json`.
struct BundledMovementGroup: Codable, Equatable {
    let id: String
    let name: String
    let pattern: String
    let memberIDs: [String]
}

/// Loads the bundled groups, resolving member ids against the library.
enum MovementGroupCatalog {

    /// Builds groups from their JSON definitions and the library. Members
    /// the library doesn't know are dropped; a group left empty is dropped.
    /// - Parameters:
    ///   - definitions: The decoded catalog.
    ///   - library: Library entries to resolve member ids against.
    static func groups(from definitions: [BundledMovementGroup], library: [LibraryExercise]) -> [MovementGroup] {
        let byID = Dictionary(library.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return definitions.compactMap { definition in
            let members = definition.memberIDs.compactMap { byID[$0] }.map(GroupMember.init)
            guard !members.isEmpty else { return nil }
            return MovementGroup(
                id: definition.id,
                name: definition.name,
                pattern: MovementPattern(rawValue: definition.pattern),
                members: members
            )
        }
    }

    /// Merges the built-ins with the athlete's groups: a user row with a
    /// built-in's id replaces it (copy-on-write edits), the rest are added.
    /// Order: built-ins in catalog order, then the athlete's by name.
    /// - Parameters:
    ///   - builtIns: The bundled groups.
    ///   - user: The athlete's groups, including edited built-ins.
    static func merged(builtIns: [MovementGroup], user: [MovementGroup]) -> [MovementGroup] {
        var overrides: [String: MovementGroup] = [:]
        for group in user where overrides[group.id] == nil { overrides[group.id] = group }
        let builtInIDs = Set(builtIns.map(\.id))
        let edited = builtIns.map { overrides[$0.id] ?? $0 }
        let own = user.filter { !builtInIDs.contains($0.id) }
        var seen = Set<String>()
        let ownUnique = own.filter { seen.insert($0.id).inserted }.sorted { $0.name < $1.name }
        return edited + ownUnique
    }

    /// The bundled library, decoded once (synchronously — it ships in the
    /// app), for resolving built-in members and a card's library entry.
    static let bundledLibrary: [LibraryExercise] = {
        guard let url = Bundle.main.url(forResource: "StrengthExerciseLibrary", withExtension: "json"),
              let data = try? Data(contentsOf: url)
        else { return [] }
        return (try? JSONDecoder().decode([LibraryExercise].self, from: data)) ?? []
    }()

    /// The bundled groups resolved against the bundled library, loaded once.
    static let bundled: [MovementGroup] = {
        guard let url = Bundle.main.url(forResource: "StrengthMovementGroups", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let definitions = try? JSONDecoder().decode([BundledMovementGroup].self, from: data)
        else { return [] }
        return groups(from: definitions, library: bundledLibrary)
    }()
}
