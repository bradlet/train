//
//  TodayTrainingSection.swift
//  Train
//
//  The "today" block on the Home tab: the day's aerobic sessions, the day's
//  active strength lane, and the strength cards from earlier this week that
//  are still to do (#15). Selection and ordering live in `TodayTraining`; this
//  file is presentation only.
//

import SwiftUI

/// Today's aerobic and strength work, with one-tap recording.
struct TodayTrainingSection: View {
    /// Today's aerobic exercises, already ordered by `TodayTraining.aerobic`.
    let aerobic: [Exercise]
    /// Today's active strength lane, already ordered by `TodayTraining.strength`.
    let strength: [StrengthExercise]
    /// The latest record per lift key, for each strength row's value.
    let latestStrengthRecords: [String: StrengthRecord]
    /// This week's latest record per card, for each strength row's ✓.
    var weekStrengthRecords: [UUID: StrengthRecord] = [:]
    /// Active cards from earlier days this week with no record yet
    /// (`StrengthWeek.carryover`).
    var carryover: [StrengthExercise] = []
    /// Called to record (or re-open) an aerobic exercise.
    let onRecordAerobic: (Exercise) -> Void
    /// Called to edit an aerobic exercise's plan or recorded data.
    let onEditAerobic: (Exercise) -> Void
    /// Called to record a session against a strength exercise.
    let onRecordStrength: (StrengthExercise) -> Void
    /// Logs today's unrecorded lifts as planned (#26); `nil` hides the
    /// button (nothing left to log today).
    var onLogAsPlanned: (() -> Void)? = nil
    /// Opens the whole-day sheet pre-ticked ("Log with changes…").
    var onLogWithChanges: () -> Void = {}

    /// Shared across the aerobic cards so only one shows its delete button.
    @State private var swipeDeleteActiveID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if TodayTraining.isEmpty(aerobic: aerobic, strength: strength, carryover: carryover) {
                emptyState
            } else {
                if !aerobic.isEmpty {
                    VStack(spacing: 8) {
                        ForEach(aerobic) { exercise in
                            ExerciseCardView(
                                exercise: exercise,
                                onRecord: { onRecordAerobic(exercise) },
                                onEdit: { onEditAerobic(exercise) },
                                hasRecordedWorkout: exercise.isCompleted,
                                swipeDeleteActiveID: $swipeDeleteActiveID
                            )
                        }
                    }
                }

                if !strength.isEmpty {
                    // The as-planned button always sits in this strength
                    // header — below the cardio cards, attached to the lift
                    // rows — so it can never read as completing a run.
                    if !aerobic.isEmpty || onLogAsPlanned != nil {
                        strengthHeader
                    }
                    VStack(spacing: 8) {
                        ForEach(strength) { exercise in
                            HomeStrengthRow(
                                exercise: exercise,
                                latestRecord: latestStrengthRecords[exercise.liftKey],
                                weekRecord: weekStrengthRecords[exercise.id]
                            ) {
                                onRecordStrength(exercise)
                            }
                        }
                    }
                }

                if !carryover.isEmpty {
                    carryoverSection
                }
            }
        }
    }

    // MARK: - Subviews

    /// "Strength", plus the one-tap "Log lifts as planned" button.
    private var strengthHeader: some View {
        HStack {
            Text("Strength")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
            if let onLogAsPlanned {
                Button(action: onLogAsPlanned) {
                    Label("Log lifts as planned", systemImage: "dumbbell.fill")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .controlSize(.small)
                .tint(.green)
                .contextMenu {
                    Button(action: onLogWithChanges) {
                        Label("Log with changes…", systemImage: "slider.horizontal.3")
                    }
                }
                .accessibilityIdentifier("home.logAsPlanned")
            }
        }
        .padding(.top, 4)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home.strengthSection")
    }

    /// "Still to do this week": earlier days' unrecorded lifts. Tapping one
    /// records it for today against its own card, which ticks that card.
    private var carryoverSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Still to do this week")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.top, 4)
                .accessibilityIdentifier("home.carryoverHeader")
            ForEach(carryover) { exercise in
                HomeStrengthRow(
                    exercise: exercise,
                    latestRecord: latestStrengthRecords[exercise.liftKey],
                    carryoverDay: Calendar.current.shortWeekdaySymbols[exercise.weekdayIndex]
                ) {
                    onRecordStrength(exercise)
                }
            }
        }
    }

    private var header: some View {
        HStack {
            Text("Today")
                .font(.headline)
            Spacer()
            Text(Self.dayFormatter.string(from: Date()))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .accessibilityIdentifier("home.todayHeader")
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Nothing scheduled today", systemImage: "calendar")
                .font(.subheadline.weight(.medium))
            Text("Log something below, or plan ahead from the Training tab.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .accessibilityIdentifier("home.todayEmpty")
    }

    /// Cached per project convention — never allocate in a computed property.
    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMM d"
        return f
    }()
}
