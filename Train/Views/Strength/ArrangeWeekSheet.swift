//
//  ArrangeWeekSheet.swift
//  Train
//
//  "Arrange my week" (#25): a before/after grid of the cardio week and the
//  strength lanes, the moves `WeekArranger` proposes (whole lanes; pinned
//  days stay), and Apply. Suggestions only — nothing moves until Apply, and
//  the board offers Undo afterwards. The strategy can be switched here.
//

import SwiftUI

/// Proposes and applies a whole-lane rearrangement of the strength week.
struct ArrangeWeekSheet: View {
    /// Every strength card.
    let cards: [StrengthExercise]
    /// Every cardio exercise.
    let exercises: [Exercise]
    /// Movement groups by id, for lane loads.
    let groups: [String: MovementGroup]
    /// Pinned weekday lanes.
    let pinned: Set<Int>
    /// The athlete's strategy (written back through `onStrategyChange`).
    let strategy: KeyDayStrategy
    let onStrategyChange: (KeyDayStrategy) -> Void
    /// Applies the proposal; the host moves the cards and offers Undo.
    let onApply: (WeekArranger.Proposal) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.weekStartDay) private var weekStartDay
    @State private var nextWeek = false

    private var referenceDate: Date {
        Calendar.current.date(byAdding: .day, value: nextWeek ? 7 : 0, to: Date()) ?? Date()
    }

    var body: some View {
        let loads = PlacementRules.laneLoads(cards, groups: groups, library: MuscleBalance.bundledLibraryByID)
        let cardio = PlacementRules.cardioClasses(exercises, weekContaining: referenceDate, firstWeekday: weekStartDay)
        let proposal = WeekArranger.propose(loads: loads, cardio: cardio, pinned: pinned, strategy: strategy)
        NavigationStack {
            Form {
                Section {
                    Picker("Week", selection: $nextWeek) {
                        Text("This week").tag(false)
                        Text("Next week").tag(true)
                    }
                    .pickerStyle(.segmented)
                    Picker("Key days", selection: Binding(get: { strategy }, set: onStrategyChange)) {
                        ForEach(KeyDayStrategy.allCases) { Text($0.displayName).tag($0) }
                    }
                }
                Section("Before") {
                    grid(loads: loads, cardio: cardio)
                }
                if !cardio.contains(.key) {
                    Section {
                        Text("No workout is marked ⚡ key this week, so there's nothing to plan around. Mark key sessions on the workouts, or tick types under Settings → My Training → Key workouts by default.")
                            .font(.callout)
                            .accessibilityIdentifier("arrange.noKeyDays")
                    }
                } else if let proposal {
                    Section("After") {
                        grid(loads: arranged(loads, proposal), cardio: cardio)
                    }
                    Section {
                        ForEach(proposal.moves, id: \.from) { move in
                            Label(
                                "\(laneName(move.from)): \(dayName(move.from)) → \(dayName(move.to))",
                                systemImage: "arrow.right"
                            )
                            .font(.callout)
                        }
                    } footer: {
                        Text("Whole days move together. Pinned days stay put.")
                    }
                } else {
                    Section {
                        Label("Your week already works", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .accessibilityIdentifier("arrange.alreadyWorks")
                    }
                }
            }
            .navigationTitle("Arrange My Week")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        if let proposal { onApply(proposal) }
                        dismiss()
                    }
                    .disabled(proposal == nil || !cardio.contains(.key))
                    .accessibilityIdentifier("arrange.apply")
                }
            }
        }
    }

    // MARK: Grid

    /// Two rows: the cardio markers and the strength lanes (U / L).
    private func grid(loads: [LaneLoad], cardio: [CardioDayClass]) -> some View {
        Grid(horizontalSpacing: 4, verticalSpacing: 6) {
            GridRow {
                Text("")
                ForEach(orderedDays, id: \.self) { day in
                    Text(Calendar.current.veryShortWeekdaySymbols[day]).font(.caption2.bold())
                        .frame(width: 28)
                        .overlay(alignment: .topTrailing) {
                            if pinned.contains(day) {
                                Image(systemName: "pin.fill").font(.system(size: 7)).offset(x: 6, y: -4)
                            }
                        }
                }
            }
            GridRow {
                Text("Run").font(.caption2).foregroundStyle(.secondary)
                ForEach(orderedDays, id: \.self) { day in
                    Text(cardio[day] == .rest ? "–" : cardio[day].marker)
                        .font(.caption)
                        .foregroundStyle(cardio[day] == .key ? Color.orange : Color.secondary)
                        .frame(width: 28)
                }
            }
            GridRow {
                Text("Lift").font(.caption2).foregroundStyle(.secondary)
                ForEach(orderedDays, id: \.self) { day in
                    let conflict = PlacementRules.conflicts(loads, cardio: cardio, strategy: strategy)[day] != nil
                    Text(loads[day] == .empty ? "–" : loads[day] == .lower ? "L" : "U")
                        .font(.caption.bold())
                        .foregroundStyle(conflict ? Color.orange : (loads[day] == .lower ? Color.purple : Color.blue))
                        .frame(width: 28)
                        .overlay(alignment: .topTrailing) {
                            if conflict { Text("!").font(.system(size: 8, weight: .bold)).foregroundStyle(.orange).offset(x: 5, y: -3) }
                        }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// Weekdays in the athlete's week order.
    private var orderedDays: [Int] {
        (0..<7).map { (($0 + weekStartDay - 1) % 7) }
    }

    private func arranged(_ loads: [LaneLoad], _ proposal: WeekArranger.Proposal) -> [LaneLoad] {
        var result = Array(repeating: LaneLoad.empty, count: 7)
        for day in 0..<7 { result[proposal.destination[day]] = loads[day] }
        return result
    }

    /// "Back Squat +2" — the lane's first card and how many more.
    private func laneName(_ day: Int) -> String {
        let lane = StrengthBoardPlanner.lane(cards, day: day, offloaded: false)
        guard let first = lane.first else { return "Lane" }
        return lane.count > 1 ? "\(first.name) +\(lane.count - 1)" : first.name
    }

    private func dayName(_ day: Int) -> String {
        Calendar.current.shortWeekdaySymbols[day]
    }
}
