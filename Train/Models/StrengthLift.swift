//
//  StrengthLift.swift
//  Train
//
//  A lift's identity: what history belongs to. Board cards (`StrengthExercise`)
//  are only slots that point at a lift through `liftKey`, so the same lift on
//  two days shares one history, and removing a card never removes a record.
//  Records (`StrengthRecord`) reference the lift by the same key rather than a
//  SwiftData relationship — CloudKit-friendly and never cascades.
//
//  CloudKit cannot enforce uniqueness, so two devices may each create a lift
//  for one key; `StrengthLiftRegistry` resolves duplicates to the oldest.
//

import Foundation
import SwiftData

@Model
final class StrengthLift {
    /// Identity shared with board slots and records; see `StrengthLiftKey`.
    var liftKey: String = ""
    /// Display name, e.g. "Barbell Bench Press".
    var name: String = ""
    /// Library entry this lift came from, or `nil` for an unlinked lift.
    var libraryExerciseID: String? = nil
    /// Raw primary muscle group (see `StrengthExercise.muscleGroupRaw` for
    /// why it is a String). Access through `muscleGroup`, never this.
    private var muscleGroupRaw: String = MuscleGroup.other.rawValue
    /// Raw primary metric. Access through `primaryMetric`, never this.
    private var primaryMetricRaw: String = LiftMetric.weight.rawValue
    /// Creation timestamp; the oldest lift wins when duplicates sync in.
    var createdAt: Date = Date()

    /// Primary muscle group. Unknown raw values read as `.other`.
    var muscleGroup: MuscleGroup {
        get { MuscleGroup(rawValue: muscleGroupRaw) ?? .other }
        set { muscleGroupRaw = newValue.rawValue }
    }

    /// The one number this lift is tracked by. Unknown raw values read as
    /// weight.
    var primaryMetric: LiftMetric {
        get { LiftMetric(rawValue: primaryMetricRaw) ?? .weight }
        set { primaryMetricRaw = newValue.rawValue }
    }

    /// Creates a lift.
    /// - Parameters:
    ///   - liftKey: Identity key (see `StrengthLiftKey.make`).
    ///   - name: Display name.
    ///   - libraryExerciseID: Library provenance, if any.
    ///   - muscleGroup: Primary muscle group.
    ///   - primaryMetric: The one number this lift is tracked by.
    ///   - createdAt: Creation timestamp.
    init(
        liftKey: String,
        name: String,
        libraryExerciseID: String? = nil,
        muscleGroup: MuscleGroup = .other,
        primaryMetric: LiftMetric = .weight,
        createdAt: Date = Date()
    ) {
        self.liftKey = liftKey
        self.name = name
        self.libraryExerciseID = libraryExerciseID
        self.muscleGroup = muscleGroup
        self.primaryMetric = primaryMetric
        self.createdAt = createdAt
    }
}

// MARK: - Lift Key

/// Builds the identity key that ties board slots, lifts and records together.
enum StrengthLiftKey {
    /// Prefix on keys built from a name, so they can never collide with a
    /// library slug.
    static let namePrefix = "name:"

    /// The lift key for a library id and name: the library id when there is
    /// one, otherwise `"name:"` plus the normalised name.
    /// - Parameters:
    ///   - libraryID: Library entry id, if any.
    ///   - name: Display name, used when there is no library id.
    static func make(libraryID: String?, name: String) -> String {
        if let libraryID, !libraryID.isEmpty { return libraryID }
        return namePrefix + normalizedName(name)
    }

    /// Lowercased, trimmed, with runs of whitespace collapsed to one space,
    /// so "Bench  Press " and "bench press" are one lift.
    static func normalizedName(_ name: String) -> String {
        name.lowercased()
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }
}
