//
//  StrengthProgressView.swift
//  Train
//
//  Strength → Progress (#16): this week's headline, then every lift with
//  history — including lifts no longer on the board — grouped by muscle
//  group and searchable, each with a sparkline, latest, best and last-done
//  date. Movement groups with history get their own section. Rows push the
//  lift detail or the group view. The rules live in `StrengthProgress`.
//

import SwiftUI
import SwiftData
import Charts

/// Where Strength → Progress navigates.
enum StrengthProgressRoute: Hashable, Identifiable {
    /// One lift's detail, by lift key.
    case lift(String)
    /// A movement group's view, by group id.
    case group(String)

    var id: String {
        switch self {
        case .lift(let key): return "lift:" + key
        case .group(let id): return "group:" + id
        }
    }
}

/// Strength → Progress: the lift list.
struct StrengthProgressView: View {
    @Query private var records: [StrengthRecord]
    @Query private var lifts: [StrengthLift]
    @Query(sort: \UserMovementGroup.createdAt) private var userGroups: [UserMovementGroup]

    @Environment(\.weekStartDay) private var weekStartDay
    @Environment(\.useMetricUnits) private var useMetricUnits
    @State private var searchText = ""
    /// The muscle-group scope, sticky between visits (#17); "" is All.
    @AppStorage("strengthProgressScope") private var muscleFilterRaw = ""

    private var muscleFilter: MuscleGroup? {
        get { MuscleGroup(rawValue: muscleFilterRaw) }
        nonmutating set { muscleFilterRaw = newValue?.rawValue ?? "" }
    }

    var body: some View {
        let summaries = StrengthProgress.summaries(lifts: lifts, records: records)
        let sections = StrengthProgress.sections(summaries, searchText: searchText, muscleGroup: muscleFilter)
        let groups = StrengthProgress.groupsWithHistory(allGroups, records: records)
        List {
            Section {
                weekHeadline
            }
            if summaries.isEmpty {
                ContentUnavailableView {
                    Label("No lifts recorded yet", systemImage: "chart.line.uptrend.xyaxis")
                } description: {
                    Text("Record a lift from the Plan board and its history, best and trend appear here.")
                }
                .listRowBackground(Color.clear)
                .accessibilityIdentifier("strengthProgress.empty")
            } else {
                Section { muscleChips(summaries) }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                if muscleFilter == nil, searchText.isEmpty, !groups.isEmpty {
                    Section("Movement Groups") {
                        ForEach(groups) { group in
                            NavigationLink(value: StrengthProgressRoute.group(group.id)) {
                                Label(group.name, systemImage: "arrow.triangle.2.circlepath")
                            }
                            .accessibilityIdentifier("strengthProgress.group.\(group.name)")
                        }
                    }
                }
                ForEach(sections, id: \.group) { section in
                    Section {
                        ForEach(section.lifts) { summary in
                            NavigationLink(value: StrengthProgressRoute.lift(summary.liftKey)) {
                                LiftSummaryRow(summary: summary)
                            }
                            .accessibilityIdentifier("strengthProgress.lift.\(summary.name)")
                        }
                    } header: {
                        Text(section.group.rawValue).foregroundStyle(section.group.color)
                    }
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search lifts")
        .accessibilityIdentifier("strengthProgress.list")
        .progressCSVExport(.strength)
    }

    /// Built-in and athlete groups.
    private var allGroups: [MovementGroup] {
        MovementGroupCatalog.merged(builtIns: MovementGroupCatalog.bundled, user: userGroups.map(\.group))
    }

    /// "This week: 6 lifts · 2 days".
    private var weekHeadline: some View {
        let excluded = Set(lifts.filter { !$0.countsTowardTraining }.map(\.liftKey))
        let week = StrengthProgress.thisWeek(records, now: Date(), firstWeekday: weekStartDay, excludedLiftKeys: excluded)
        return HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("This week").font(.caption).foregroundStyle(.secondary)
                Text(week.lifts == 1 ? "1 lift" : "\(week.lifts) lifts")
                    .font(.title3.weight(.semibold))
                    .accessibilityIdentifier("strengthProgress.weekLifts")
            }
            Divider().frame(height: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text("Strength days").font(.caption).foregroundStyle(.secondary)
                Text("\(week.days)")
                    .font(.title3.weight(.semibold))
                    .accessibilityIdentifier("strengthProgress.weekDays")
            }
            Spacer()
        }
        .accessibilityElement(children: .combine)
    }

    /// Muscle-group filter chips for the groups present.
    private func muscleChips(_ summaries: [LiftSummary]) -> some View {
        let present = Set(summaries.map(\.muscleGroup))
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(nil, label: "All")
                ForEach(MuscleGroup.allCases.filter(present.contains)) { group in
                    chip(group, label: group.rawValue)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
        }
    }

    private func chip(_ group: MuscleGroup?, label: String) -> some View {
        let selected = muscleFilter == group
        let accent = group?.color ?? .blue
        return Button {
            muscleFilter = selected ? nil : group
        } label: {
            Text(label)
                .font(.caption.bold())
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Capsule().fill(selected ? accent : accent.opacity(0.12)))
                .foregroundStyle(selected ? .white : accent)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("strengthProgress.filter.\(label)")
    }
}

/// Resolves a Progress route to its screen. Shared by the Progress list,
/// the board's "History" menu item and the record sheet.
struct StrengthProgressDestination: View {
    let route: StrengthProgressRoute

    var body: some View {
        switch route {
        case .lift(let key): LiftDetailView(liftKey: key)
        case .group(let id): GroupProgressView(groupID: id)
        }
    }
}

// MARK: - Row

/// One lift in the list: name, last done, sparkline, latest and best.
struct LiftSummaryRow: View {
    let summary: LiftSummary
    @Environment(\.useMetricUnits) private var useMetricUnits

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(summary.name).font(.subheadline.weight(.semibold))
                    if !summary.countsTowardTraining {
                        Text("Not training")
                            .font(.caption2.bold())
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().strokeBorder(.secondary))
                            .foregroundStyle(.secondary)
                    }
                }
                Text("Last done \(Self.dateFormatter.string(from: summary.lastDone))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if summary.sparkline.count >= 2 {
                LiftSparkline(values: summary.sparkline, tint: summary.muscleGroup.color)
                    .frame(width: 56, height: 24)
            }
            VStack(alignment: .trailing, spacing: 3) {
                Text(summary.metric.formatted(summary.latestValue, metric: useMetricUnits))
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                if let best = summary.bestValue {
                    Text("Best \(summary.metric.formatted(best, metric: useMetricUnits))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
        .padding(.vertical, 2)
        .opacity(summary.countsTowardTraining ? 1 : 0.55)
    }
}

/// A tiny trend line.
struct LiftSparkline: View {
    let values: [Double]
    let tint: Color

    var body: some View {
        Chart(Array(values.enumerated()), id: \.offset) { item in
            LineMark(x: .value("Session", item.offset), y: .value("Value", item.element))
                .interpolationMethod(.monotone)
                .foregroundStyle(tint)
                .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round))
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: (values.min() ?? 0)...(max(values.max() ?? 1, (values.min() ?? 0) + 0.001)))
        .accessibilityHidden(true)
    }
}
