//
//  RecordStrengthSheet.swift
//  Train
//
//  Form for recording one session of a lift from a board card: the date, the
//  lift's single number in its primary metric (weight, reps, time, distance)
//  and, for weight and reps, what that number represents. The number is
//  optional — leaving it blank logs the session as done. The record belongs
//  to the lift and remembers the card it was logged from. A group card
//  (#24) records its up-next member; picking another member is the swap
//  (nothing else is stored), and in a held block the athlete can make the
//  pick the block's held member instead.
//

import SwiftUI
import SwiftData

/// Sheet for recording a `StrengthRecord` against a board card's lift.
struct RecordStrengthSheet: View {
    /// The board card being recorded from.
    let slot: StrengthExercise
    /// Called with the lift's name when the saved record is a new best.
    var onNewBest: ([String]) -> Void = { _ in }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.useMetricUnits) private var useMetricUnits
    @Environment(\.weekStartDay) private var weekStartDay

    @State private var draft: StrengthRecordDraft
    /// The lift being recorded: the card's own, or a group member.
    @State private var target: LiftTarget?
    /// The card's group, when it plans one.
    @State private var group: MovementGroup?
    /// The member rotation offered, so a swap can be told apart.
    @State private var upNextKey: String?
    /// Whether "Hold this one instead" is chosen (one-per-block groups).
    @State private var holdInstead = false
    /// Last record date per lift key, for the member picker.
    @State private var lastDone: [String: Date] = [:]
    /// Whether the lift's metric and prefill have been applied (once).
    @State private var didPrefill = false

    /// Creates the sheet. The lift's metric and the prefill from its last
    /// session are resolved on appear.
    /// - Parameters:
    ///   - slot: The board card being recorded from.
    ///   - onNewBest: Called with the lift's name when the save is a new best.
    init(slot: StrengthExercise, onNewBest: @escaping ([String]) -> Void = { _ in }) {
        self.slot = slot
        self.onNewBest = onNewBest
        self._draft = State(initialValue: StrengthRecordDraft(metric: .weight))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if let group {
                        memberPicker(group)
                    } else {
                        LabeledContent("Exercise", value: slot.name)
                    }
                    DatePicker("Date", selection: $draft.date, displayedComponents: .date)
                    if let target {
                        NavigationLink {
                            LiftDetailView(liftKey: target.liftKey)
                        } label: {
                            Label("History", systemImage: "chart.line.uptrend.xyaxis")
                        }
                        .accessibilityIdentifier("recordStrength.history")
                    }
                } header: {
                    Text(group.map { "Session · \($0.name)" } ?? "Session")
                } footer: {
                    if let group, group.rotationMode == .onePerBlock, target?.liftKey != upNextKey {
                        Toggle("Hold this one for the rest of the block", isOn: $holdInstead)
                            .font(.footnote)
                            .accessibilityIdentifier("recordStrength.holdInstead")
                    }
                }
                Section {
                    StrengthValueEditor(draft: $draft, identifierPrefix: "recordStrength")
                    if draft.metric.usesMeasurement {
                        Picker("Measurement", selection: $draft.measurement) {
                            ForEach(LiftMeasurement.allCases) { measurement in
                                Text(measurement.displayName).tag(measurement)
                            }
                        }
                        .accessibilityIdentifier("recordStrength.measurementPicker")
                    }
                } header: {
                    Text(draft.metric.displayName)
                } footer: {
                    Text(footerText)
                }
                Section("Notes") {
                    TextField("Optional notes", text: $draft.notes, axis: .vertical)
                        .lineLimit(2...4)
                }
            }
            .onAppear {
                guard !didPrefill else { return }
                didPrefill = true
                let resolvedTarget = StrengthSlotResolver.target(for: slot, in: modelContext, firstWeekday: weekStartDay)
                if let groupID = slot.groupID {
                    group = StrengthSlotResolver.groups(in: modelContext)[groupID]
                    upNextKey = resolvedTarget.liftKey
                    lastDone = GroupRotation.lastDone((try? modelContext.fetch(FetchDescriptor<StrengthRecord>())) ?? [])
                }
                select(resolvedTarget)
            }
            .navigationTitle("Record Lift")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!draft.canSave(useMetricUnits: useMetricUnits))
                        .accessibilityIdentifier("recordStrength.save")
                }
            }
        }
    }

    /// Explains the optional number and, where relevant, the measurement.
    private var footerText: String {
        let done = "Starts from your last session; nudge it with − and +. Leave it blank to log the session as done without a number."
        guard draft.metric.usesMeasurement else { return done }
        return "Choose what the number represents so trends like a top set and an average can be tracked separately. " + done
    }

    /// The group's members, each with when it was last done; choosing one
    /// is the swap.
    private func memberPicker(_ group: MovementGroup) -> some View {
        Picker("Exercise", selection: Binding(
            get: { target?.liftKey ?? "" },
            set: { key in
                guard let member = group.member(forLiftKey: key) else { return }
                holdInstead = false
                select(LiftTarget(member: member))
            }
        )) {
            ForEach(group.members) { member in
                Text(memberLabel(member, in: group)).tag(member.liftKey)
            }
        }
        .accessibilityIdentifier("recordStrength.memberPicker")
    }

    /// "Incline Dumbbell Press · Nov 10", "… · Up next", "… · Paused".
    private func memberLabel(_ member: GroupMember, in group: MovementGroup) -> String {
        if member.liftKey == upNextKey { return "\(member.name) · Up next" }
        if group.pausedLiftKeys.contains(member.liftKey) { return "\(member.name) · Paused" }
        guard let date = lastDone[member.liftKey] else { return "\(member.name) · Never" }
        return "\(member.name) · \(Self.lastDoneFormatter.string(from: date))"
    }

    /// Cached formatter for member last-done dates, e.g. "Nov 10".
    private static let lastDoneFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()

    /// Switches the lift being recorded and re-prefills from its history,
    /// keeping the chosen date.
    private func select(_ newTarget: LiftTarget) {
        target = newTarget
        let resolved = StrengthPrefill.resolve(for: newTarget, in: modelContext)
        draft = StrengthRecordDraft(
            metric: resolved.metric,
            prefill: resolved.prefill,
            useMetricUnits: useMetricUnits,
            date: draft.date
        )
    }

    /// Resolves the lift, inserts the record, reports a new best, stores a
    /// "hold this one instead", and dismisses.
    private func save() {
        let recordTarget = target ?? LiftTarget(slot: slot)
        let lift = StrengthLiftRegistry.findOrCreate(for: recordTarget, metric: draft.metric, in: modelContext)
        guard let record = draft.makeRecord(
            liftKey: lift.liftKey,
            slotID: slot.id,
            useMetricUnits: useMetricUnits
        ) else { return }
        let previous = StrengthLiftRegistry.records(forKey: lift.liftKey, in: modelContext)
        if StrengthPersonalBest.isNewBest(record, previous: previous) {
            onNewBest([recordTarget.name])
        }
        if holdInstead, var held = group {
            held.heldLiftKey = recordTarget.liftKey
            held.heldBlockIndex = GroupRotation.blockIndex(for: held, now: Date(), firstWeekday: weekStartDay)
            MovementGroupStore.save(held, in: modelContext)
        }
        modelContext.insert(record)
        StrengthLiftRegistry.rememberDefaults(after: record, in: modelContext)
        dismiss()
    }
}

// MARK: - Draft

/// Form state for one strength record, and the parse from text fields to a
/// `StrengthRecord`. Kept free of SwiftUI so it can be unit-tested.
struct StrengthRecordDraft: Equatable {
    /// What the entered value parsed to.
    enum Entry: Equatable {
        /// Blank: logged as done with no number.
        case done
        /// A positive value in the metric's internal unit.
        case value(Double)
        /// Text that isn't a positive number for the metric.
        case invalid
    }

    /// The metric being recorded.
    var metric: LiftMetric
    /// The day the session was performed.
    var date: Date = Date()
    /// Value text for weight, reps and distance, in display units.
    var valueText: String = ""
    /// Minutes text, for time.
    var minutesText: String = ""
    /// Seconds text, for time.
    var secondsText: String = ""
    /// What the value represents (weight and reps only).
    var measurement: LiftMeasurement = .starting
    /// Optional notes.
    var notes: String = ""

    /// A blank draft for a metric.
    /// - Parameters:
    ///   - metric: The metric being recorded.
    ///   - date: The day the session was performed.
    init(metric: LiftMetric, date: Date = Date()) {
        self.metric = metric
        self.date = date
    }

    /// A draft seeded from the lift's last session.
    /// - Parameters:
    ///   - metric: The metric being recorded.
    ///   - prefill: The starting measurement and value.
    ///   - useMetricUnits: Whether to show the value in metric units.
    ///   - date: The day the session was performed.
    init(metric: LiftMetric, prefill: StrengthPrefill, useMetricUnits: Bool, date: Date = Date()) {
        self.init(metric: metric, date: date)
        self.measurement = prefill.measurement
        if let value = prefill.value {
            setValue(stored: value, useMetricUnits: useMetricUnits)
        }
    }

    /// Writes a stored value into the text fields, in display units: whole
    /// numbers without decimals, otherwise one decimal; time as minutes and
    /// seconds.
    /// - Parameters:
    ///   - stored: The value in the metric's internal unit.
    ///   - useMetricUnits: Whether to show it in metric units.
    mutating func setValue(stored: Double, useMetricUnits: Bool) {
        switch metric {
        case .time:
            let total = Int(stored.rounded())
            minutesText = String(total / 60)
            secondsText = String(total % 60)
        case .reps:
            valueText = String(Int(stored.rounded()))
        case .weight, .distance:
            let display = (metric.displayValue(fromStored: stored, metric: useMetricUnits) * 10).rounded() / 10
            valueText = display.truncatingRemainder(dividingBy: 1) == 0
                ? String(format: "%.0f", display)
                : String(format: "%.1f", display)
        }
    }

    /// Steps the value by whole increments of `LiftMetric.stepIncrement`.
    /// A blank or invalid value counts as zero, and the result never drops
    /// below one step — the stepper is for numbers; blank is how "done" is
    /// logged.
    /// - Parameters:
    ///   - steps: Increments to add (negative to subtract).
    ///   - useMetricUnits: Whether the value is shown in metric units.
    mutating func nudge(by steps: Int, useMetricUnits: Bool) {
        let step = metric.stepIncrement(metric: useMetricUnits)
        let current: Double
        if case .value(let stored) = entry(useMetricUnits: useMetricUnits) {
            current = metric.displayValue(fromStored: stored, metric: useMetricUnits)
        } else {
            current = 0
        }
        let next = Swift.max(current + Double(steps) * step, step)
        setValue(stored: metric.storedValue(fromDisplay: next, metric: useMetricUnits), useMetricUnits: useMetricUnits)
    }

    /// Parses the entered value into the metric's internal unit.
    /// - Parameter useMetricUnits: Whether the value was entered in metric.
    func entry(useMetricUnits: Bool) -> Entry {
        switch metric {
        case .time:
            return timeEntry()
        case .reps:
            let text = valueText.trimmingCharacters(in: .whitespaces)
            if text.isEmpty { return .done }
            guard let reps = Int(text), reps > 0 else { return .invalid }
            return .value(Double(reps))
        case .weight, .distance:
            let text = valueText.trimmingCharacters(in: .whitespaces)
                .replacingOccurrences(of: ",", with: ".")
            if text.isEmpty { return .done }
            guard let display = Double(text), display > 0, display.isFinite else { return .invalid }
            return .value(metric.storedValue(fromDisplay: display, metric: useMetricUnits))
        }
    }

    /// Minutes and seconds to total seconds. Both blank is done; seconds
    /// alone may exceed 59 (e.g. "90"), but not alongside minutes.
    private func timeEntry() -> Entry {
        let minutesRaw = minutesText.trimmingCharacters(in: .whitespaces)
        let secondsRaw = secondsText.trimmingCharacters(in: .whitespaces)
        if minutesRaw.isEmpty && secondsRaw.isEmpty { return .done }
        guard let minutes = minutesRaw.isEmpty ? 0 : Int(minutesRaw),
              let seconds = secondsRaw.isEmpty ? 0 : Int(secondsRaw),
              minutes >= 0, seconds >= 0,
              minutesRaw.isEmpty || seconds < 60
        else { return .invalid }
        let total = minutes * 60 + seconds
        return total > 0 ? .value(Double(total)) : .invalid
    }

    /// Whether the form can be saved: blank or a valid positive value.
    /// - Parameter useMetricUnits: Whether the value was entered in metric.
    func canSave(useMetricUnits: Bool) -> Bool {
        entry(useMetricUnits: useMetricUnits) != .invalid
    }

    /// Builds the record, or `nil` when the entered value is invalid. A
    /// value-less record carries no measurement.
    /// - Parameters:
    ///   - liftKey: The lift the record belongs to.
    ///   - slotID: The card it was logged from.
    ///   - useMetricUnits: Whether the value was entered in metric.
    func makeRecord(liftKey: String, slotID: UUID?, useMetricUnits: Bool) -> StrengthRecord? {
        let value: Double?
        switch entry(useMetricUnits: useMetricUnits) {
        case .invalid: return nil
        case .done: value = nil
        case .value(let parsed): value = parsed
        }
        return StrengthRecord(
            liftKey: liftKey,
            slotID: slotID,
            date: date,
            value: value,
            metric: metric,
            measurement: value == nil ? nil : measurement,
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }
}

#Preview {
    RecordStrengthSheet(
        slot: StrengthExercise(name: "Plank", muscleGroup: .core)
    )
    .modelContainer(ModelContainerFactory.makePreviewContainer())
}
