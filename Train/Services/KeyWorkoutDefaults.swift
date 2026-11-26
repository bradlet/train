//
//  KeyWorkoutDefaults.swift
//  Train
//
//  The athlete's own "key workouts by default" (#25): which exercise types
//  start marked ⚡ key. Nothing is ticked out of the box — the app never
//  decides what is hard. Mirrors `TrainingInclusion`'s form rule. Plus the
//  key-day strategy for lower-body strength. Pure and unit-tested.
//

import SwiftUI
import SwiftData

/// How lower-body strength relates to key days.
enum KeyDayStrategy: String, CaseIterable, Identifiable, Codable {
    /// "Hard days hard": lift on key days, after the key workout.
    case stack
    /// Keep key days free of lifting.
    case liftFree

    var id: String { rawValue }

    /// Display name for the setting.
    var displayName: String {
        switch self {
        case .stack: return "Stack strength with key days"
        case .liftFree: return "Keep key days lift-free"
        }
    }
}

/// Per-type key-workout defaults.
enum KeyWorkoutDefaults {

    /// Whether a new session of `type` starts marked key.
    static func isKey(_ type: ExerciseType, keyTypes: Set<ExerciseType>) -> Bool {
        keyTypes.contains(type)
    }

    /// The form's ⚡ toggle after the type changes: it follows the new
    /// type's default unless the athlete had overridden the old one.
    static func toggle(_ current: Bool, afterChangingFrom old: ExerciseType, to new: ExerciseType, keyTypes: Set<ExerciseType>) -> Bool {
        current == isKey(old, keyTypes: keyTypes) ? isKey(new, keyTypes: keyTypes) : current
    }

    /// The athlete's key types from the stored configuration, without
    /// creating one.
    static func keyTypes(in context: ModelContext) -> Set<ExerciseType> {
        (try? context.fetch(FetchDescriptor<AppConfiguration>()).first?.keyWorkoutTypes) ?? []
    }
}

private struct KeyWorkoutTypesKey: EnvironmentKey {
    static let defaultValue: Set<ExerciseType> = []
}

private struct KeyDayStrategyKey: EnvironmentKey {
    static let defaultValue: KeyDayStrategy = .stack
}

extension EnvironmentValues {
    /// Types whose new sessions start marked key (#25), from `AppConfiguration`.
    var keyWorkoutTypes: Set<ExerciseType> {
        get { self[KeyWorkoutTypesKey.self] }
        set { self[KeyWorkoutTypesKey.self] = newValue }
    }

    /// The athlete's key-day strategy (#25), from `AppConfiguration`.
    var keyDayStrategy: KeyDayStrategy {
        get { self[KeyDayStrategyKey.self] }
        set { self[KeyDayStrategyKey.self] = newValue }
    }
}
