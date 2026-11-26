//
//  LogStrengthDaySheet.swift
//  Train
//
//  Log a whole day's lifts at once (#14, roadmap R3): one row per active
//  card, each prefilled from that lift's last session with − / + nudges.
//  Tick what you did and Save records every ticked row against its card.
//  Rows start unticked — ticking is the action, so nothing is logged by
//  accident ("Log lifts as planned", #26, is the one-tap version).
//

import SwiftUI
import SwiftData

/// One lift in the whole-day sheet.
struct StrengthDayLogRow: Identifiable, Equatable {
    /// The card (`StrengthExercise.id`) the record is logged from.
    let slotID: UUID
    /// The lift the record belongs to.
    let liftKey: String
    /// Display name.
    let name: String
    /// Primary muscle group, for the row's tint.
    let muscleGroup: MuscleGroup
    /// The value being recorded, prefilled from the lift's last session.
    var draft: StrengthRecordDraft
    /// Whether this lift is ticked as done.
    var isDone: Bool = false

    var id: UUID { slotID }
}

/// Pure rules for the whole-day sheet: building rows, when Save is allowed,
/// and which records Save writes.
enum StrengthDayLog {

    /// One prefilled, unticked row per card, in the given order.
    /// - Parameters:
    ///   - slots: The lane's active cards, in board order.
    ///   - context: The context to resolve lifts and records from.
    ///   - useMetricUnits: Whether values show in metric units.
    ///   - date: The day being logged.
    static func rows(
        for slots: [StrengthExercise],
        in context: ModelContext,
        useMetricUnits: Bool,
        date: Date
    ) -> [StrengthDayLogRow] {
        slots.map { slot in
            let resolved = StrengthPrefill.resolve(for: slot, in: context)
            return StrengthDayLogRow(
                slotID: slot.id,
                liftKey: slot.liftKey,
                name: slot.name,
                muscleGroup: slot.muscleGroup,
                draft: StrengthRecordDraft(
                    metric: resolved.metric,
                    prefill: resolved.prefill,
                    useMetricUnits: useMetricUnits,
                    date: date
                )
            )
        }
    }

    /// Save needs at least one ticked row, and every ticked row valid
    /// (blank is valid: it logs "done").
    static func canSave(_ rows: [StrengthDayLogRow], useMetricUnits: Bool) -> Bool {
        let ticked = rows.filter(\.isDone)
        return !ticked.isEmpty && ticked.allSatisfy { $0.draft.canSave(useMetricUnits: useMetricUnits) }
    }

    /// The records Save writes: one per ticked row, dated `date`, carrying
    /// its card's `slotID`. Unticked rows write nothing.
    /// - Parameters:
    ///   - rows: The sheet's rows.
    ///   - date: The day being logged.
    ///   - useMetricUnits: Whether values were entered in metric units.
    static func makeRecords(_ rows: [StrengthDayLogRow], date: Date, useMetricUnits: Bool) -> [StrengthRecord] {
        rows.filter(\.isDone).compactMap { row in
            var draft = row.draft
            draft.date = date
            return draft.makeRecord(liftKey: row.liftKey, slotID: row.slotID, useMetricUnits: useMetricUnits)
        }
    }
}

/// Sheet for logging several lifts from one day at once.
struct LogStrengthDaySheet: View {
    /// The lane's active cards, in board order.
    let slots: [StrengthExercise]
    /// Called with the names of lifts that set a new best on save.
    let onNewBest: ([String]) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.useMetricUnits) private var useMetricUnits

    @State private var date: Date
    @State private var rows: [StrengthDayLogRow] = []
    @State private var didLoad = false

    /// Creates the sheet.
    /// - Parameters:
    ///   - slots: The lane's active cards, in board order.
    ///   - date: The day being logged (defaults to today).
    ///   - onNewBest: Called with the names of lifts whose saved record is a
    ///     new best (only when there is at least one).
    init(slots: [StrengthExercise], date: Date = Date(), onNewBest: @escaping ([String]) -> Void = { _ in }) {
        self.slots = slots
        self.onNewBest = onNewBest
        self._date = State(initialValue: date)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Date", selection: $date, in: ...Date(), displayedComponents: .date)
                        .accessibilityIdentifier("logDay.date")
                }
                Section {
                    ForEach(Array($rows.enumerated()), id: \.element.id) { index, $row in
                        rowView($row, index: index)
                    }
                } header: {
                    Text("Lifts")
                } footer: {
                    Text("Tick what you did. Values start from your last session; leave one blank to log it as done.")
                }
            }
            .navigationTitle("Log \(date.weekdayName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!StrengthDayLog.canSave(rows, useMetricUnits: useMetricUnits))
                        .accessibilityIdentifier("logDay.save")
                }
            }
            .onAppear {
                guard !didLoad else { return }
                didLoad = true
                rows = StrengthDayLog.rows(for: slots, in: modelContext, useMetricUnits: useMetricUnits, date: date)
            }
        }
    }

    /// One lift: a tick, the name and measurement, and the value editor.
    private func rowView(_ row: Binding<StrengthDayLogRow>, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                row.wrappedValue.isDone.toggle()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: row.wrappedValue.isDone ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(row.wrappedValue.isDone ? Color.green : Color.secondary)
                    Text(row.wrappedValue.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Spacer()
                    if row.wrappedValue.draft.metric.usesMeasurement {
                        Text(row.wrappedValue.draft.measurement.shortLabel)
                            .font(.caption2.bold())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(row.wrappedValue.muscleGroup.color.opacity(0.15))
                            .foregroundStyle(row.wrappedValue.muscleGroup.color)
                            .clipShape(Capsule())
                    }
                }
            }
            // Borderless so the tick and the value editor's − / + stay
            // separate tap targets in one form row; tinted primary because
            // borderless otherwise paints the name in the accent colour.
            .buttonStyle(.borderless)
            .tint(.primary)
            .accessibilityIdentifier("logDay.tick.\(index)")
            StrengthValueEditor(draft: row.draft, identifierPrefix: "logDay.\(index)")
                .opacity(row.wrappedValue.isDone ? 1 : 0.5)
        }
        .padding(.vertical, 4)
    }

    /// Records every ticked row against its card's lift, remembers each
    /// lift's measurement, reports new bests, and dismisses.
    private func save() {
        let records = StrengthDayLog.makeRecords(rows, date: date, useMetricUnits: useMetricUnits)
        var bests: [String] = []
        for record in records {
            let slot = slots.first(where: { $0.id == record.slotID })
            if let slot {
                StrengthLiftRegistry.findOrCreate(for: slot, metric: record.metric, in: modelContext)
            }
            let previous = StrengthLiftRegistry.records(forKey: record.liftKey, in: modelContext)
            if StrengthPersonalBest.isNewBest(record, previous: previous), let name = slot?.name {
                bests.append(name)
            }
            modelContext.insert(record)
            StrengthLiftRegistry.rememberDefaults(after: record, in: modelContext)
        }
        if !bests.isEmpty { onNewBest(bests) }
        dismiss()
    }
}

#Preview {
    LogStrengthDaySheet(slots: [
        StrengthExercise(name: "Back Squat", muscleGroup: .quads),
        StrengthExercise(name: "Plank", muscleGroup: .core),
    ])
    .modelContainer(ModelContainerFactory.makePreviewContainer())
}
