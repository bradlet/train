//
//  HybridWeekSection.swift
//  Train
//
//  Home's hybrid hub (#19), below Today: a two-track week strip — runs on
//  top, lifts beneath, done vs planned in the header — and the week's
//  hybrid hints, each dismissible for the week. Tapping a cell opens that
//  day in Cardio or Strength Plan (`PlanRouter`). Built from `HybridWeek`.
//

import SwiftUI

/// The week strip and hints.
struct HybridWeekSection: View {
    let days: [HybridDay]
    let hints: [HybridHint]
    let onOpenCardio: (Date) -> Void
    let onOpenStrength: (Int) -> Void
    let onDismissHint: (HybridHint) -> Void

    @Environment(\.useMetricUnits) private var useMetricUnits

    var body: some View {
        let progress = HybridWeek.progress(days)
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("This Week").font(.headline)
                Spacer()
                Text("\(progress.done) of \(progress.total) done")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("home.weekProgress")
            }
            Grid(horizontalSpacing: 4, verticalSpacing: 6) {
                GridRow {
                    Color.clear.frame(width: 30, height: 1)
                    ForEach(days) { day in
                        Text(Calendar.current.veryShortWeekdaySymbols[day.weekday])
                            .font(.caption2.bold())
                            .foregroundStyle(Calendar.current.isDateInToday(day.date) ? Color.accentColor : Color.secondary)
                            .frame(maxWidth: .infinity)
                    }
                }
                GridRow {
                    Image(systemName: "figure.run").font(.caption).foregroundStyle(.secondary)
                    ForEach(days) { day in
                        Button { onOpenCardio(day.date) } label: { runCell(day) }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("home.week.run.\(day.weekday)")
                    }
                }
                GridRow {
                    Image(systemName: "dumbbell.fill").font(.caption).foregroundStyle(.secondary)
                    ForEach(days) { day in
                        Button { onOpenStrength(day.weekday) } label: { liftCell(day) }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("home.week.lift.\(day.weekday)")
                    }
                }
            }
            if !hints.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(hints) { hint in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "lightbulb.fill").foregroundStyle(.yellow).font(.caption)
                            Text(hint.message).font(.caption).frame(maxWidth: .infinity, alignment: .leading)
                            Button {
                                onDismissHint(hint)
                            } label: {
                                Image(systemName: "xmark").font(.caption2.bold()).foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Dismiss for this week")
                            .accessibilityIdentifier("home.hint.dismiss.\(hint.kind.rawValue)")
                        }
                        .accessibilityIdentifier("home.hint.\(hint.kind.rawValue)")
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
        // No container identifier: on a plain stack it would replace every
        // child's own (the cells', the progress label's).
    }

    /// Miles (or a dash), ⚡ for key, green once all of the day's sessions
    /// are recorded.
    private func runCell(_ day: HybridDay) -> some View {
        let done = day.cardioCount > 0 && day.cardioDone == day.cardioCount
        let text: String
        if day.cardioCount == 0 {
            text = "–"
        } else if day.miles > 0 {
            let value = useMetricUnits ? day.miles * 1.60934 : day.miles
            text = value >= 10 ? String(format: "%.0f", value) : String(format: "%.1f", value)
        } else {
            text = "•"
        }
        return VStack(spacing: 0) {
            Text(text).font(.caption.weight(.semibold)).monospacedDigit()
            Text(day.hasKey ? "⚡" : " ").font(.system(size: 8))
        }
        .frame(maxWidth: .infinity, minHeight: 30)
        .background(RoundedRectangle(cornerRadius: 6).fill(done ? Color.green.opacity(0.18) : Color.secondary.opacity(day.cardioCount > 0 ? 0.1 : 0.04)))
        .foregroundStyle(done ? Color.green : Color.primary)
    }

    /// L / U for the lane's load, a ✓ once every card is recorded.
    private func liftCell(_ day: HybridDay) -> some View {
        let done = day.liftCount > 0 && day.liftDone == day.liftCount
        let text = day.liftLoad == .empty ? "–" : (day.liftLoad == .lower ? "L" : "U")
        return Text(done ? "✓" : text)
            .font(.caption.weight(.bold))
            .frame(maxWidth: .infinity, minHeight: 26)
            .background(RoundedRectangle(cornerRadius: 6).fill(done ? Color.green.opacity(0.18) : Color.secondary.opacity(day.liftCount > 0 ? 0.1 : 0.04)))
            .foregroundStyle(done ? Color.green : (day.liftLoad == .lower ? Color.purple : Color.primary))
    }
}
