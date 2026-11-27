//
//  FavoriteMenuSection.swift
//  Train
//
//  The "Start from Favorite" form section shared by the cardio record (quick
//  add) and schedule sheets. Picking a favorite hands it back to the sheet,
//  which fills its own fields. This section is also where favorites are
//  managed: they are cardio presets, so they live only where a cardio session
//  is recorded or scheduled. Favorites arrive as a `let` from the presenting
//  top-level view — sheets don't own queries.
//

import SwiftUI

/// A form section with a menu of favorite cardio sessions to pre-fill from,
/// plus the entry point into managing them.
struct FavoriteMenuSection: View {
    @Environment(\.useMetricUnits) private var useMetricUnits

    /// Favorites in their manual order.
    let favorites: [FavoriteWorkout]
    /// Called with the picked favorite.
    let onSelect: (FavoriteWorkout) -> Void

    /// Whether the favorites manager is showing.
    @State private var isManaging = false

    var body: some View {
        Section {
            if favorites.isEmpty {
                Button {
                    isManaging = true
                } label: {
                    Label("Save sessions you repeat as favorites", systemImage: "star")
                        .font(.subheadline)
                }
                .accessibilityIdentifier("favoriteMenu.empty")
            } else {
                Menu {
                    ForEach(favorites) { favorite in
                        Button {
                            onSelect(favorite)
                        } label: {
                            Label(favorite.name, systemImage: favorite.type.systemImage)
                            let summary = favorite.targetSummary(metric: useMetricUnits)
                            if !summary.isEmpty {
                                Text(summary)
                            }
                        }
                        .accessibilityIdentifier("favoriteMenu.item.\(favorite.name)")
                    }
                    Divider()
                    Button {
                        isManaging = true
                    } label: {
                        Label("Manage Favorites…", systemImage: "slider.horizontal.3")
                    }
                    .accessibilityIdentifier("favoriteMenu.manage")
                } label: {
                    Label("Start from Favorite", systemImage: "star")
                }
                .accessibilityIdentifier("favoriteMenu.button")
            }
        }
        .sheet(isPresented: $isManaging) {
            ManageFavoritesSheet(favorites: favorites)
        }
    }
}

#Preview {
    Form {
        FavoriteMenuSection(
            favorites: [FavoriteWorkout(name: "Easy Loop", type: .easyRun, distanceMiles: 5)],
            onSelect: { _ in }
        )
        FavoriteMenuSection(favorites: [], onSelect: { _ in })
    }
}
