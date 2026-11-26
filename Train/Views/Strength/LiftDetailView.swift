//
//  LiftDetailView.swift
//  Train
//
//  One lift's history (#16, roadmap P2): latest / best / sessions, a chart
//  with one line per measurement (a "done" record is a gap, never 0; lines
//  step at each new entry, since a lift's number holds until the next
//  session), personal-best markers, and the record list. Tapping a record
//  edits it (`EditStrengthRecordSheet`); swipe to delete. Reachable from
//  Strength → Progress, a board card's "History" and the record sheet.
//
//  A pushed screen with its own `@Query` (filtered to the lift), so it stays
//  live after edits wherever it was pushed from.
//

import SwiftUI
import SwiftData
import Charts

/// One lift's chart and records.
struct LiftDetailView: View {
    let liftKey: String

    @Query private var records: [StrengthRecord]
    @Query private var lifts: [StrengthLift]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.useMetricUnits) private var useMetricUnits
    @State private var window: PerformanceTimeWindow = .allTime
    @State private var editing: StrengthRecord?

    /// Creates the screen for a lift.
    /// - Parameter liftKey: The lift to show.
    init(liftKey: String) {
        self.liftKey = liftKey
        _records = Query(filter: #Predicate<StrengthRecord> { $0.liftKey == liftKey }, sort: \.date, order: .reverse)
        _lifts = Query(filter: #Predicate<StrengthLift> { $0.liftKey == liftKey })
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE, MMM d, yyyy"
        return f
    }()

    var body: some View {
        let summary = StrengthProgress.summaries(lifts: lifts, records: records).first
        let metric = summary?.metric ?? .weight
        let bests = StrengthProgress.personalBests(records)
        List {
            if let summary {
                Section { header(summary) }
                Section {
                    chart(metric: metric)
                    Picker("Scale", selection: $window) {
                        ForEach(PerformanceTimeWindow.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("liftDetail.scale")
                }
            }
            if let lift = StrengthLiftRegistry.lift(forKey: liftKey, in: lifts) {
                Section {
                    Toggle("Counts toward training", isOn: Binding(
                        get: { lift.countsTowardTraining },
                        set: { lift.countsTowardTraining = $0 }
                    ))
                    .accessibilityIdentifier("liftDetail.countsTowardTraining")
                } footer: {
                    Text("Turn off for mobility or rehab work: it's still tracked, but left out of your weekly strength totals.")
                }
            }
            Section("Sessions") {
                ForEach(records) { record in
                    Button { editing = record } label: { recordRow(record, isBest: bests.contains(record.id)) }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("liftDetail.record.\(record.id.uuidString)")
                }
                .onDelete { offsets in
                    for index in offsets { StrengthRecordEditor.delete(records[index], in: modelContext) }
                }
            }
        }
        .navigationTitle(summary?.name ?? StrengthProgress.displayName(forKey: liftKey))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing) { record in
            EditStrengthRecordSheet(record: record)
        }
        .overlay {
            if records.isEmpty {
                ContentUnavailableView("No sessions", systemImage: "chart.line.uptrend.xyaxis")
            }
        }
    }

    // MARK: Header

    private func header(_ summary: LiftSummary) -> some View {
        HStack(alignment: .top) {
            stat("Latest", summary.metric.formatted(summary.latestValue, metric: useMetricUnits), id: "liftDetail.latest")
            Spacer()
            stat("Best", summary.metric.formatted(summary.bestValue, metric: useMetricUnits), id: "liftDetail.best")
            Spacer()
            stat("Sessions", "\(summary.recordCount)", id: "liftDetail.sessions")
        }
        .overlay(alignment: .bottomLeading) {
            if let measurement = summary.measurement {
                Text(measurement.displayName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .offset(y: 16)
            }
        }
        .padding(.bottom, summary.measurement == nil ? 0 : 12)
    }

    private func stat(_ title: String, _ value: String, id: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.weight(.semibold)).monospacedDigit()
                .accessibilityIdentifier(id)
        }
    }

    // MARK: Chart

    /// One line per measurement, stepping at each session, with a star on
    /// each personal best.
    @ViewBuilder
    private func chart(metric: LiftMetric) -> some View {
        let since = sinceDate
        let series = StrengthProgress.series(records, metric: metric, since: since)
        let dates = series.flatMap(\.points).map(\.date).sorted()
        if series.isEmpty {
            Text("No numbers in this range — sessions logged as done show in the list below.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            Chart {
                ForEach(series) { line in
                    ForEach(line.points) { point in
                        LineMark(
                            x: .value("Date", point.date),
                            y: .value("Value", metric.displayValue(fromStored: point.value, metric: useMetricUnits)),
                            series: .value("Measurement", line.label)
                        )
                        .interpolationMethod(.stepEnd)
                        .foregroundStyle(by: .value("Measurement", line.label))
                        .lineStyle(StrokeStyle(lineWidth: 2))
                    }
                    ForEach(line.points.filter(\.isPersonalBest)) { point in
                        PointMark(
                            x: .value("Date", point.date),
                            y: .value("Value", metric.displayValue(fromStored: point.value, metric: useMetricUnits))
                        )
                        .symbol(.asterisk)
                        .symbolSize(40)
                        .foregroundStyle(.orange)
                    }
                }
            }
            .chartLegend(series.count > 1 ? .visible : .hidden)
            // Strength numbers move a few percent at a time; a zero
            // baseline would flatten every trend.
            .chartYScale(domain: .automatic(includesZero: false))
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
                    AxisValueLabel()
                }
            }
            .chartXAxis {
                AxisMarks(values: ChartAxis.labelDates(dates, monthly: spansMonths(dates))) { _ in
                    AxisTick(stroke: StrokeStyle(lineWidth: 0.5))
                    if spansMonths(dates) {
                        AxisValueLabel(format: .dateTime.month(.abbreviated), collisionResolution: .greedy)
                    } else {
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day(), collisionResolution: .greedy)
                    }
                }
            }
            .frame(height: 180)
            .accessibilityIdentifier("liftDetail.chart")
        }
    }

    /// The start of the selected scale, or `nil` for all time.
    private var sinceDate: Date? {
        let now = Date()
        let weeks: Int
        switch window {
        case .oneMonth: weeks = 4
        case .threeMonth: weeks = 13
        case .sixMonth: weeks = 26
        case .oneYear: weeks = 52
        case .allTime: return nil
        }
        return Calendar.current.date(byAdding: .day, value: -weeks * 7, to: now)
    }

    /// Whether the dates cover more than about three months (month labels).
    private func spansMonths(_ dates: [Date]) -> Bool {
        guard let first = dates.first, let last = dates.last else { return false }
        return last.timeIntervalSince(first) > 95 * 86_400
    }

    // MARK: Records

    private func recordRow(_ record: StrengthRecord, isBest: Bool) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(Self.dateFormatter.string(from: record.date)).font(.subheadline)
                if !record.notes.isEmpty {
                    Text(record.notes).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer()
            if isBest {
                Label("Best", systemImage: "trophy.fill")
                    .font(.caption2.bold())
                    .foregroundStyle(.orange)
                    .labelStyle(.iconOnly)
                    .accessibilityLabel("Personal best")
            }
            Text(record.summary(useMetricUnits: useMetricUnits))
                .font(.subheadline.weight(.medium))
                .monospacedDigit()
        }
        .contentShape(Rectangle())
    }
}

// MARK: - Edit

/// Edit or delete one recorded session (the `WorkoutDetailSheet` pattern):
/// the same value editor as recording, through `StrengthRecordEditor`.
struct EditStrengthRecordSheet: View {
    let record: StrengthRecord

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.useMetricUnits) private var useMetricUnits
    @State private var draft: StrengthRecordDraft
    @State private var confirmDelete = false

    /// Creates the sheet. The draft is filled on appear, once the unit
    /// preference is known.
    init(record: StrengthRecord) {
        self.record = record
        _draft = State(initialValue: StrengthRecordDraft(metric: record.metric, date: record.date))
    }

    @State private var didLoad = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Date", selection: $draft.date, in: ...Date(), displayedComponents: .date)
                }
                Section {
                    StrengthValueEditor(draft: $draft, identifierPrefix: "editRecord")
                    if draft.metric.usesMeasurement {
                        Picker("Measurement", selection: $draft.measurement) {
                            ForEach(LiftMeasurement.allCases) { Text($0.displayName).tag($0) }
                        }
                    }
                } header: {
                    Text(draft.metric.displayName)
                } footer: {
                    Text("Leave it blank to keep the session as done without a number.")
                }
                Section("Notes") {
                    TextField("Optional notes", text: $draft.notes, axis: .vertical)
                        .lineLimit(2...4)
                }
                Section {
                    Button("Delete Session", role: .destructive) { confirmDelete = true }
                        .accessibilityIdentifier("editRecord.delete")
                }
            }
            .navigationTitle("Edit Session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if StrengthRecordEditor.apply(draft, to: record, useMetricUnits: useMetricUnits) { dismiss() }
                    }
                    .disabled(!draft.canSave(useMetricUnits: useMetricUnits))
                    .accessibilityIdentifier("editRecord.save")
                }
            }
            .confirmationDialog("Delete this session?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    StrengthRecordEditor.delete(record, in: modelContext)
                    dismiss()
                }
            }
            .onAppear {
                guard !didLoad else { return }
                didLoad = true
                draft = StrengthRecordEditor.draft(for: record, useMetricUnits: useMetricUnits)
            }
        }
    }
}
