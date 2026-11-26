//
//  TrainingScope.swift
//  Train
//
//  One value that drives every Cardio → Progress component (#17): stats,
//  charts, calendar and list. `All` is the training summary; a family
//  ("Running", "Bike") or a single type ("Tempo Run") narrows everything to
//  that scope. Inclusion still applies inside any scope — only workouts that
//  count toward training add to mileage — so a scope never changes what
//  "my training" means, only how much of it is shown. Pure and unit-tested.
//

import Foundation

/// A family of exercise types, for the scope chips.
enum ExerciseFamily: String, CaseIterable, Identifiable, Codable {
    case running = "Running"
    case bike = "Bike"
    case swim = "Swim"
    case walk = "Walk"
    case hike = "Hike"
    case elliptical = "Elliptical"
    case other = "Other"

    var id: String { rawValue }

    /// The family's types, in `ExerciseType` order.
    var types: [ExerciseType] { ExerciseType.allCases.filter { $0.family == self } }

    /// A representative symbol.
    var systemImage: String { types.first?.systemImage ?? "figure.mixed.cardio" }
}

extension ExerciseType {
    /// The family this type belongs to; every run variant and races are
    /// Running.
    var family: ExerciseFamily {
        switch self {
        case .run, .longRun, .tempoRun, .intervalRun, .easyRun, .recoveryRun, .race: return .running
        case .bike: return .bike
        case .swim: return .swim
        case .walk: return .walk
        case .hike: return .hike
        case .elliptical: return .elliptical
        case .other: return .other
        }
    }
}

/// What a Progress segment is showing.
enum TrainingScope: Hashable, Identifiable {
    /// Everything — the training summary.
    case all
    /// One family of types.
    case family(ExerciseFamily)
    /// One type.
    case type(ExerciseType)

    var id: String { rawValue }

    /// Chip label.
    var title: String {
        switch self {
        case .all: return "All"
        case .family(let family): return family.rawValue
        case .type(let type): return type.rawValue
        }
    }

    /// Whether an exercise is in scope.
    func contains(_ exercise: Exercise) -> Bool {
        switch self {
        case .all: return true
        case .family(let family): return exercise.type.family == family
        case .type(let type): return exercise.type == type
        }
    }

    /// The exercises in scope, order preserved.
    func filter(_ exercises: [Exercise]) -> [Exercise] {
        self == .all ? exercises : exercises.filter(contains)
    }

    /// The family a scope sits in, for highlighting its chip.
    var family: ExerciseFamily? {
        switch self {
        case .all: return nil
        case .family(let family): return family
        case .type(let type): return type.family
        }
    }

    /// The chips to offer: families present in the data, in family order.
    static func families(in exercises: [Exercise]) -> [ExerciseFamily] {
        let present = Set(exercises.map(\.type.family))
        return ExerciseFamily.allCases.filter(present.contains)
    }

    /// A family's types present in the data, for its drill-down menu.
    static func types(of family: ExerciseFamily, in exercises: [Exercise]) -> [ExerciseType] {
        let present = Set(exercises.map(\.type))
        return family.types.filter(present.contains)
    }
}

// MARK: - Storage

extension TrainingScope: RawRepresentable {
    /// "all", "family:Running" or "type:Tempo Run" — sticky in `@AppStorage`.
    var rawValue: String {
        switch self {
        case .all: return "all"
        case .family(let family): return "family:" + family.rawValue
        case .type(let type): return "type:" + type.rawValue
        }
    }

    /// Parses a stored scope; anything unknown reads as `nil`.
    init?(rawValue: String) {
        if rawValue == "all" { self = .all; return }
        if rawValue.hasPrefix("family:"), let family = ExerciseFamily(rawValue: String(rawValue.dropFirst(7))) {
            self = .family(family); return
        }
        if rawValue.hasPrefix("type:"), let type = ExerciseType(rawValue: String(rawValue.dropFirst(5))) {
            self = .type(type); return
        }
        return nil
    }
}
