//
//  GroupProgressView.swift
//  Train
//
//  A movement group in Strength → Progress (#16, with #24): one row per
//  member with its own sparkline, latest and best (each member is its own
//  lift, so numbers never mix), tapping through to that lift's detail; and a
//  rotation strip — how often each member was done in the last 8 weeks, with
//  never-reached members highlighted.
//

import SwiftUI
import SwiftData
import Charts

/// One movement group's members and rotation.
struct GroupProgressView: View {
    let groupID: String

    @Query private var records: [StrengthRecord]
    @Query private var lifts: [StrengthLift]
    @Query(sort: \UserMovementGroup.createdAt) private var userGroups: [UserMovementGroup]

    /// The group, built-in or the athlete's.
    private var group: MovementGroup? {
        StrengthSlotResolver.byID(MovementGroupCatalog.merged(
            builtIns: MovementGroupCatalog.bundled, user: userGroups.map(\.group)
        ))[groupID]
    }

    var body: some View {
        if let group {
            let summaries = Dictionary(
                StrengthProgress.summaries(lifts: lifts, records: records).map { ($0.liftKey, $0) },
                uniquingKeysWith: { first, _ in first }
            )
            let counts = StrengthProgress.rotationCounts(group, records: records, now: Date())
            List {
                Section {
                    rotationStrip(counts)
                } header: {
                    Text("Last 8 weeks")
                } footer: {
                    Text(group.rotationMode == .onePerBlock
                         ? "Holds one member per \(group.blockWeeks)-week block."
                         : "The least-recently-done member comes up next.")
                }
                Section("Members") {
                    ForEach(group.members) { member in
                        if let summary = summaries[member.liftKey] {
                            NavigationLink(value: StrengthProgressRoute.lift(member.liftKey)) {
                                LiftSummaryRow(summary: summary)
                            }
                            .accessibilityIdentifier("groupProgress.member.\(member.name)")
                        } else {
                            HStack {
                                Text(member.name)
                                Spacer()
                                Text(group.pausedLiftKeys.contains(member.liftKey) ? "Paused" : "Not done yet")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .accessibilityIdentifier("groupProgress.member.\(member.name)")
                        }
                    }
                }
            }
            .navigationTitle(group.name)
            .navigationBarTitleDisplayMode(.inline)
        } else {
            ContentUnavailableView("Group not found", systemImage: "arrow.triangle.2.circlepath")
        }
    }

    /// A bar per member; members never done in the window are orange.
    private func rotationStrip(_ counts: [(member: GroupMember, count: Int)]) -> some View {
        Chart(counts, id: \.member.liftKey) { item in
            BarMark(
                x: .value("Sessions", item.count),
                y: .value("Member", item.member.name)
            )
            .foregroundStyle(item.count == 0 ? Color.orange.opacity(0.6) : Color.accentColor)
            .annotation(position: .trailing) {
                Text(item.count == 0 ? "none" : "\(item.count)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .chartXAxis(.hidden)
        .chartXScale(domain: 0...max(Double(counts.map(\.count).max() ?? 1), 1) * 1.25)
        .frame(height: CGFloat(max(counts.count, 1)) * 28)
        .accessibilityIdentifier("groupProgress.rotation")
    }
}
