//
//  HistoryView.swift
//  Train
//
//  Cardio → Progress (formerly the History tab, #12). Shows summary stats,
//  a monthly calendar, and a paginated list of all recorded workouts.
//  Hosted by `CardioView`, which owns the navigation bar; import/export
//  lives in Settings → Data.
//

import SwiftUI
import SwiftData

/// Cardio → Progress: summary statistics, a monthly calendar, and a workout log.
struct HistoryView: View {
    @Query private var allExercises: [Exercise]
    @State private var selectedMonth: Date = Date()

    /// Recorded exercises (those with a `workout`), most recent first.
    /// `workout != nil` cannot be expressed in a `#Predicate` over a Codable
    /// composite attribute, so the filter + sort run in memory here.
    private var completedExercises: [Exercise] {
        allExercises
            .filter(\.isCompleted)
            .sorted { $0.date > $1.date }
    }

    /// Drives `WorkoutListView` to jump to a specific workout's page and
    /// highlight it briefly. A new request (fresh `id`) is constructed on
    /// every calendar day tap so repeat taps still fire the observer.
    @State private var navigationRequest: WorkoutNavigationRequest?

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 20) {
                PerformanceHubView(exercises: completedExercises)
                MonthlyCalendarView(
                    selectedMonth: $selectedMonth,
                    items: completedExercises,
                    onDayTap: handleCalendarDayTap
                )
                workoutListSection
            }
            .padding(.vertical)
        }
    }

    /// Section header and workout list.
    private var workoutListSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent Workouts")
                .font(.headline)
                .padding(.horizontal)
            WorkoutListView(
                exercises: completedExercises,
                navigationRequest: navigationRequest
            )
        }
    }

    // MARK: Calendar navigation

    /// Translates a calendar day tap into a navigation request for the
    /// workout list. Since `allWorkouts` is sorted descending by date, the
    /// first match on a day is the most recent workout for that day.
    private func handleCalendarDayTap(_ day: Date) {
        guard let match = completedExercises.first(where: { $0.date.isSameDay(as: day) }) else {
            return
        }
        navigationRequest = WorkoutNavigationRequest(workoutID: match.id)
    }
}

#Preview {
    NavigationStack { HistoryView() }
        .modelContainer(ModelContainerFactory.makePreviewContainer())
}
