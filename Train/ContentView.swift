//
//  ContentView.swift
//  Train
//
//  Root view: Home · Cardio (Plan | Progress) · Strength (Plan | Progress).
//  Reads the unit configuration and injects it into the environment.
//

import SwiftUI
import SwiftData

/// The root view that provides tab-based navigation across the app's main sections.
struct ContentView: View {
    @Query private var configurations: [AppConfiguration]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.coachLauncher) private var coachLauncher

    /// The selected tab. Switches to Home when the widget or Siri opens the
    /// coach, since Home owns the navigation into the chat.
    @State private var selectedTab: AppTab = .home

    /// Reactively reads the metric preference without fetching in body.
    private var useMetric: Bool { configurations.first?.useMetricUnits ?? false }

    /// Reactively reads the week-start preference, clamped to a valid
    /// Calendar weekday (1=Sunday ... 7=Saturday) in case a bad value
    /// arrives via CloudKit sync.
    private var weekStartDay: Int { min(max(configurations.first?.weekStartDay ?? AppConfiguration.defaultWeekStartDay, 1), 7) }

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView()
                .tabItem { Label("Home", systemImage: "house") }
                .tag(AppTab.home)
            CardioView()
                .tabItem { Label("Cardio", systemImage: "figure.run") }
                .tag(AppTab.cardio)
            StrengthView()
                .tabItem { Label("Strength", systemImage: "dumbbell") }
                .tag(AppTab.strength)
        }
        .onChange(of: coachLauncher.pending, initial: true) { _, pending in
            if pending != nil { selectedTab = .home }
        }
        .environment(\.useMetricUnits, useMetric)
        .environment(\.weekStartDay, weekStartDay)
        .environment(\.trainingExcludedTypes, configurations.first?.trainingExcludedTypes ?? TrainingInclusion.defaultExcluded)
        .environment(\.keyWorkoutTypes, configurations.first?.keyWorkoutTypes ?? [])
        .environment(\.keyDayStrategy, configurations.first?.keyDayStrategy ?? .stack)
        .onAppear { ensureConfigurationExists() }
    }

    /// Creates the singleton AppConfiguration if it doesn't exist yet.
    private func ensureConfigurationExists() {
        if configurations.isEmpty {
            modelContext.insert(AppConfiguration())
        }
    }
}

/// The app's top-level tabs.
enum AppTab: Hashable {
    case home, cardio, strength
}

#Preview {
    ContentView()
        .modelContainer(ModelContainerFactory.makePreviewContainer())
}
