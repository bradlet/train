//
//  GroupRotation.swift
//  Train
//
//  Which member of a movement group each group card offers (#24). Nothing is
//  stored — the up-next member is computed from records, so there is no
//  rotation pointer to keep in sync across devices:
//
//  - A card recorded this week shows the member actually done.
//  - Shuffle within a block: the least-recently-done member (by the lift's
//    global history, so a standalone bench on Tuesday counts), skipping
//    members already assigned to or done on earlier cards of the same group
//    this week; ties go to member order.
//  - One member per block: every card shows the block's held member — the
//    least-recently-done as of the block's start, unless the athlete chose
//    "Hold this one instead" for this block.
//
//  Pure and unit-tested.
//

import Foundation

/// The member a group card offers, and why.
struct GroupAssignment: Equatable {
    /// The member to show and record.
    let member: GroupMember
    /// Whether this card was recorded this week (the member is what was done).
    let isRecorded: Bool
    /// The 1-based block number when the group holds one member per block.
    let heldBlock: Int?
}

/// Smart rotation for movement groups.
enum GroupRotation {

    /// The most recent record date per lift key.
    /// - Parameter records: All strength records.
    static func lastDone(_ records: [StrengthRecord]) -> [String: Date] {
        var last: [String: Date] = [:]
        for record in records where (last[record.liftKey] ?? .distantPast) < record.date {
            last[record.liftKey] = record.date
        }
        return last
    }

    /// The least-recently-done member among `candidates`: never done is
    /// oldest, ties go to the earlier member.
    /// - Parameters:
    ///   - candidates: Members to choose from, in group order (non-empty).
    ///   - lastDone: Last record date per lift key.
    static func leastRecentlyDone(_ candidates: [GroupMember], lastDone: [String: Date]) -> GroupMember? {
        var best: (member: GroupMember, date: Date)?
        for member in candidates {
            let date = lastDone[member.liftKey] ?? .distantPast
            if best == nil || date < best!.date { best = (member, date) }
        }
        return best?.member
    }

    // MARK: Blocks

    /// The 0-based block containing `now`: whole weeks since the anchor's
    /// week, divided by the block length. No anchor is block 0.
    /// - Parameters:
    ///   - group: The group.
    ///   - now: Any moment in the week.
    ///   - firstWeekday: Calendar weekday convention (1=Sunday ... 7=Saturday).
    static func blockIndex(for group: MovementGroup, now: Date, firstWeekday: Int) -> Int {
        guard let anchor = group.blockAnchor else { return 0 }
        let start = anchor.startOfWeek(firstWeekday: firstWeekday)
        let current = now.startOfWeek(firstWeekday: firstWeekday)
        let days = Calendar.current.dateComponents([.day], from: start, to: current).day ?? 0
        let weeks = max(0, Int((Double(days) / 7).rounded()))
        return weeks / max(group.blockWeeks, 1)
    }

    /// When block `index` starts.
    /// - Parameters:
    ///   - index: The 0-based block.
    ///   - group: The group.
    ///   - now: Used when the group has no anchor.
    ///   - firstWeekday: Calendar weekday convention (1=Sunday ... 7=Saturday).
    static func blockStart(_ index: Int, for group: MovementGroup, now: Date, firstWeekday: Int) -> Date {
        let anchorWeek = (group.blockAnchor ?? now).startOfWeek(firstWeekday: firstWeekday)
        return Calendar.current.date(byAdding: .day, value: index * max(group.blockWeeks, 1) * 7, to: anchorWeek) ?? anchorWeek
    }

    /// The member held for the block containing `now`: the athlete's
    /// override for this block if it is still an active member, otherwise
    /// the least-recently-done member as of the block's start (records from
    /// inside the block don't move it, so the hold is stable all block).
    /// - Parameters:
    ///   - group: The group (one member per block).
    ///   - records: All strength records.
    ///   - now: The current moment.
    ///   - firstWeekday: Calendar weekday convention (1=Sunday ... 7=Saturday).
    static func heldMember(
        for group: MovementGroup,
        records: [StrengthRecord],
        now: Date,
        firstWeekday: Int
    ) -> GroupMember? {
        let index = blockIndex(for: group, now: now, firstWeekday: firstWeekday)
        let active = group.activeMembers
        if let held = group.heldLiftKey, group.heldBlockIndex == index,
           let member = active.first(where: { $0.liftKey == held }) {
            return member
        }
        let start = blockStart(index, for: group, now: now, firstWeekday: firstWeekday)
        return leastRecentlyDone(active, lastDone: lastDone(records.filter { $0.date < start }))
    }

    // MARK: Assignments

    /// The member every group card offers this week.
    ///
    /// Active cards of one group are walked in week order (lane date, then
    /// board order), so earlier days claim members first. Offloaded cards
    /// get the plain least-recently-done member.
    /// - Parameters:
    ///   - slots: Every strength card (single-lift cards are ignored).
    ///   - groups: Groups by id; a card whose group is unknown is skipped.
    ///   - records: All strength records.
    ///   - now: The current moment.
    ///   - firstWeekday: Calendar weekday convention (1=Sunday ... 7=Saturday).
    /// - Returns: Assignments by card id.
    static func assignments(
        slots: [StrengthExercise],
        groups: [String: MovementGroup],
        records: [StrengthRecord],
        now: Date,
        firstWeekday: Int
    ) -> [UUID: GroupAssignment] {
        let last = lastDone(records)
        let thisWeek = StrengthWeek.recordsBySlot(records, now: now, firstWeekday: firstWeekday)
        var result: [UUID: GroupAssignment] = [:]

        let bySlotGroup = Dictionary(grouping: slots.filter { $0.groupID != nil }, by: { $0.groupID! })
        for (groupID, groupSlots) in bySlotGroup {
            guard let group = groups[groupID], !group.members.isEmpty else { continue }
            let ordered = groupSlots.sorted { lhs, rhs in
                let lhsDate = StrengthWeek.date(ofLane: lhs.weekdayIndex, now: now, firstWeekday: firstWeekday)
                let rhsDate = StrengthWeek.date(ofLane: rhs.weekdayIndex, now: now, firstWeekday: firstWeekday)
                if lhsDate != rhsDate { return lhsDate < rhsDate }
                return lhs.sortOrder < rhs.sortOrder
            }

            let held: GroupMember?
            let heldBlock: Int?
            if group.rotationMode == .onePerBlock {
                held = heldMember(for: group, records: records, now: now, firstWeekday: firstWeekday)
                heldBlock = blockIndex(for: group, now: now, firstWeekday: firstWeekday) + 1
            } else {
                held = nil
                heldBlock = nil
            }

            var taken = Set<String>()
            for slot in ordered {
                if let record = thisWeek[slot.id], let done = group.member(forLiftKey: record.liftKey) {
                    taken.insert(done.liftKey)
                    result[slot.id] = GroupAssignment(member: done, isRecorded: true, heldBlock: heldBlock)
                    continue
                }
                let member: GroupMember?
                if let held {
                    member = held
                } else if slot.isOffloaded {
                    member = leastRecentlyDone(group.activeMembers, lastDone: last)
                } else {
                    let open = group.activeMembers.filter { !taken.contains($0.liftKey) }
                    member = leastRecentlyDone(open.isEmpty ? group.activeMembers : open, lastDone: last)
                }
                guard let member else { continue }
                if !slot.isOffloaded { taken.insert(member.liftKey) }
                result[slot.id] = GroupAssignment(member: member, isRecorded: false, heldBlock: heldBlock)
            }
        }
        return result
    }
}
