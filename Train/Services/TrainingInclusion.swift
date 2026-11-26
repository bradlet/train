//
//  TrainingInclusion.swift
//  Train
//
//  What counts as "my training" by default (#17). Each `ExerciseType` is
//  included or not (Settings → Training); a new exercise copies its type's
//  default into `Exercise.countsTowardTraining`, which stays overridable per
//  exercise. Walks and hikes start excluded; runs, bikes and swims count.
//  Changing a type's default asks once whether to rewrite past workouts.
//  Pure and unit-tested.
//

import SwiftUI
import SwiftData

/// Per-type "counts toward my training" defaults.
enum TrainingInclusion {

    /// Types excluded on a fresh install.
    static let defaultExcluded: Set<ExerciseType> = [.walk, .hike]

    /// Whether a new exercise of `type` counts toward training.
    /// - Parameters:
    ///   - type: The exercise type.
    ///   - excluded: The athlete's excluded types.
    static func counts(_ type: ExerciseType, excluded: Set<ExerciseType>) -> Bool {
        !excluded.contains(type)
    }

    /// The form's toggle after the type changes: it follows the new type's
    /// default unless the athlete had overridden the old one.
    /// - Parameters:
    ///   - current: The toggle's value before the change.
    ///   - old: The previous type.
    ///   - new: The new type.
    ///   - excluded: The athlete's excluded types.
    static func toggle(_ current: Bool, afterChangingFrom old: ExerciseType, to new: ExerciseType, excluded: Set<ExerciseType>) -> Bool {
        current == counts(old, excluded: excluded) ? counts(new, excluded: excluded) : current
    }

    /// Stored form: raw values joined by commas, in `allCases` order.
    static func encode(_ excluded: Set<ExerciseType>) -> String {
        ExerciseType.allCases.filter(excluded.contains).map(\.rawValue).joined(separator: ",")
    }

    /// Parses the stored form; unknown values are ignored.
    static func decode(_ raw: String) -> Set<ExerciseType> {
        Set(raw.split(separator: ",").compactMap { ExerciseType(rawValue: String($0)) })
    }

    /// The athlete's excluded types from the stored configuration, without
    /// creating one (services that make exercises outside a view).
    /// - Parameter context: The context to read `AppConfiguration` from.
    static func excludedTypes(in context: ModelContext) -> Set<ExerciseType> {
        (try? context.fetch(FetchDescriptor<AppConfiguration>()).first?.trainingExcludedTypes) ?? defaultExcluded
    }

    /// Applies a type's new default to existing exercises of that type
    /// ("apply to past workouts").
    /// - Parameters:
    ///   - type: The type whose default changed.
    ///   - counts: The new default.
    ///   - exercises: Exercises to update; other types are left alone.
    /// - Returns: How many exercises changed.
    @discardableResult
    static func applyToPast(_ type: ExerciseType, counts: Bool, exercises: [Exercise]) -> Int {
        var changed = 0
        for exercise in exercises where exercise.type == type && exercise.countsTowardTraining != counts {
            exercise.countsTowardTraining = counts
            changed += 1
        }
        return changed
    }
}

// MARK: - Environment

private struct TrainingExcludedTypesKey: EnvironmentKey {
    static let defaultValue: Set<ExerciseType> = TrainingInclusion.defaultExcluded
}

extension EnvironmentValues {
    /// Exercise types that don't count toward training by default, from
    /// `AppConfiguration`. New-exercise forms seed their toggle from this.
    var trainingExcludedTypes: Set<ExerciseType> {
        get { self[TrainingExcludedTypesKey.self] }
        set { self[TrainingExcludedTypesKey.self] = newValue }
    }
}
