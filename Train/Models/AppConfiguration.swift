//
//  AppConfiguration.swift
//  Train
//
//  Singleton app-wide preferences stored in SwiftData.
//  Syncs via CloudKit alongside other model data.
//

import Foundation
import SwiftData

@Model
final class AppConfiguration {
    /// Whether to display distances in metric units (km). Default is false (miles).
    var useMetricUnits: Bool = false

    /// Whether the user has enabled the auto-export Google Sheets Sync feature.
    /// When `true`, every workout add/edit/delete schedules a debounced full
    /// overwrite of the spreadsheet identified by `googleSheetsSpreadsheetID`.
    /// Synced across devices via CloudKit; OAuth tokens are not synced and
    /// each device must sign in independently.
    var googleSheetsSyncEnabled: Bool = false

    /// The Google Sheets spreadsheet ID created for this user when they
    /// enabled sync. Empty when sync has never been enabled. The app creates
    /// this spreadsheet on first enable rather than asking the user to pick
    /// one.
    var googleSheetsSpreadsheetID: String = ""

    /// First day of the user's workout week, using the Calendar weekday
    /// convention (1=Sunday ... 7=Saturday). Affects weekly aggregation math
    /// only (weekly mileage buckets, "This Week" stats); calendar grids stay
    /// visually Sunday-first regardless. Default is 2 (Monday) — see
    /// `defaultWeekStartDay`.
    var weekStartDay: Int = AppConfiguration.defaultWeekStartDay

    /// The week start a fresh install gets: Monday (Calendar weekday 2),
    /// which matches how most athletes think of a training week. Shared by
    /// the model default, the environment fallback, and `ContentView`'s
    /// clamp so they can't drift apart.
    static let defaultWeekStartDay = 2

    /// Exercise types that don't count toward training by default (#17),
    /// as comma-joined raw values. Access through `trainingExcludedTypes`.
    var trainingExcludedTypesRaw: String = TrainingInclusion.encode(TrainingInclusion.defaultExcluded)

    /// Exercise types whose new sessions start marked as key workouts (#25),
    /// as comma-joined raw values. Empty out of the box: what's hard is the
    /// athlete's call. Access through `keyWorkoutTypes`.
    var keyWorkoutTypesRaw: String = ""

    /// Exercise types whose new sessions start marked as key workouts.
    var keyWorkoutTypes: Set<ExerciseType> {
        get { TrainingInclusion.decode(keyWorkoutTypesRaw) }
        set { keyWorkoutTypesRaw = TrainingInclusion.encode(newValue) }
    }

    /// Raw `KeyDayStrategy` (#25). Access through `keyDayStrategy`.
    var keyDayStrategyRaw: String = KeyDayStrategy.stack.rawValue

    /// Whether lower-body strength stacks on key days or keeps them lift-free.
    var keyDayStrategy: KeyDayStrategy {
        get { KeyDayStrategy(rawValue: keyDayStrategyRaw) ?? .stack }
        set { keyDayStrategyRaw = newValue.rawValue }
    }

    /// The start of a one-off light week (#20), or `nil`. Light only while
    /// it is the current week, so it reverts on its own.
    var lightWeekStart: Date? = nil

    /// Weekday lanes (Sunday=0 ... Saturday=6) whose strength plan "Arrange my
    /// week" never moves, comma-joined (#25). Access through `pinnedWeekdays`.
    var pinnedWeekdaysRaw: String = ""

    /// Weekday lanes the arranger leaves in place.
    var pinnedWeekdays: Set<Int> {
        get { Set(pinnedWeekdaysRaw.split(separator: ",").compactMap { Int($0) }.filter { (0...6).contains($0) }) }
        set { pinnedWeekdaysRaw = newValue.sorted().map(String.init).joined(separator: ",") }
    }

    /// Exercise types whose new workouts start out not counting toward
    /// training (walks and hikes by default).
    var trainingExcludedTypes: Set<ExerciseType> {
        get { TrainingInclusion.decode(trainingExcludedTypesRaw) }
        set { trainingExcludedTypesRaw = TrainingInclusion.encode(newValue) }
    }

    /// Creates a new configuration with default values.
    init(
        useMetricUnits: Bool = false,
        googleSheetsSyncEnabled: Bool = false,
        googleSheetsSpreadsheetID: String = "",
        weekStartDay: Int = AppConfiguration.defaultWeekStartDay
    ) {
        self.useMetricUnits = useMetricUnits
        self.googleSheetsSyncEnabled = googleSheetsSyncEnabled
        self.googleSheetsSpreadsheetID = googleSheetsSpreadsheetID
        self.weekStartDay = weekStartDay
    }

    /// Fetches the singleton configuration, creating one if it doesn't exist.
    /// - Parameter context: The model context to query.
    /// - Returns: The app configuration instance.
    static func current(in context: ModelContext) -> AppConfiguration {
        let descriptor = FetchDescriptor<AppConfiguration>()
        if let existing = try? context.fetch(descriptor).first {
            return existing
        }
        let config = AppConfiguration()
        context.insert(config)
        return config
    }
}
