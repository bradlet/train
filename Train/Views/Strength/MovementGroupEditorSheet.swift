//
//  MovementGroupEditorSheet.swift
//  Train
//
//  Create or edit a movement group (#24): name, members (add from the
//  library with same-pattern lifts suggested first, reorder, pause, remove),
//  and the rotation toggle (shuffle within a block / one member per block,
//  with the block length in weeks). Editing a built-in saves the athlete's
//  own copy; the caller does the writing through `MovementGroupStore`.
//

import SwiftUI

/// Pure editing rules for the group form, kept out of the view for tests.
enum MovementGroupDraft {

    /// Whether the group can be saved: a name and at least one member.
    static func canSave(_ group: MovementGroup) -> Bool {
        !group.name.trimmingCharacters(in: .whitespaces).isEmpty && !group.members.isEmpty
    }

    /// Library entries to offer when adding members: not already in the
    /// group, same-pattern entries first (in name order), then the rest.
    /// - Parameters:
    ///   - library: All library entries.
    ///   - group: The group being edited.
    ///   - searchText: Optional name filter.
    static func candidates(_ library: [LibraryExercise], for group: MovementGroup, searchText: String = "") -> [LibraryExercise] {
        let existing = Set(group.members.map(\.libraryID))
        let query = searchText.trimmingCharacters(in: .whitespaces)
        var same: [LibraryExercise] = []
        var rest: [LibraryExercise] = []
        for entry in library where !existing.contains(entry.id) {
            if !query.isEmpty && !entry.name.localizedCaseInsensitiveContains(query) { continue }
            if let pattern = group.pattern, entry.pattern == pattern {
                same.append(entry)
            } else {
                rest.append(entry)
            }
        }
        let byName: (LibraryExercise, LibraryExercise) -> Bool = { $0.name < $1.name }
        return same.sorted(by: byName) + rest.sorted(by: byName)
    }

    /// Switches the rotation mode, anchoring blocks to now the first time
    /// one-member-per-block is chosen and dropping a stale override.
    static func setRotation(_ mode: GroupRotationMode, on group: inout MovementGroup, now: Date = Date()) {
        guard group.rotationMode != mode else { return }
        group.rotationMode = mode
        if mode == .onePerBlock {
            group.blockAnchor = now
            group.heldLiftKey = nil
            group.heldBlockIndex = nil
        }
    }

    /// Pauses or resumes a member.
    static func togglePaused(_ liftKey: String, in group: inout MovementGroup) {
        if group.pausedLiftKeys.contains(liftKey) {
            group.pausedLiftKeys.remove(liftKey)
        } else {
            group.pausedLiftKeys.insert(liftKey)
        }
    }

    /// A new group seeded from a single-lift card: its lift as the first
    /// member, named after the built-in for its pattern when there is one.
    /// - Parameters:
    ///   - slot: The card being turned into a group.
    ///   - entry: The card's library entry, if known.
    static func seed(from slot: StrengthExercise, entry: LibraryExercise?) -> MovementGroup {
        let member = entry.map(GroupMember.init) ?? GroupMember(
            libraryID: slot.libraryExerciseID ?? "",
            name: slot.name,
            muscleGroup: slot.muscleGroup,
            primaryMetric: .weight
        )
        let pattern = entry?.pattern
        let builtInName = MovementGroupCatalog.bundled.first { pattern != nil && $0.pattern == pattern }?.name
        return MovementGroup(
            id: MovementGroup.userPrefix + UUID().uuidString,
            name: builtInName ?? slot.name,
            pattern: pattern,
            members: [member]
        )
    }
}

/// Form for one movement group.
struct MovementGroupEditorSheet: View {
    /// Where library entries come from, for adding members.
    var provider: any ExerciseLibraryProvider = .default
    /// The title, e.g. "New Group" or "Edit Group".
    let title: String
    /// Called with the edited group on Save.
    let onSave: (MovementGroup) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var group: MovementGroup
    @State private var library: [LibraryExercise] = []
    @State private var isAddingMembers = false

    /// Creates the editor.
    /// - Parameters:
    ///   - group: The group to start from.
    ///   - title: The navigation title.
    ///   - provider: Library source for adding members.
    ///   - onSave: Called with the edited group.
    init(
        group: MovementGroup,
        title: String,
        provider: any ExerciseLibraryProvider = .default,
        onSave: @escaping (MovementGroup) -> Void
    ) {
        self._group = State(initialValue: group)
        self.title = title
        self.provider = provider
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("e.g. Chest Press", text: $group.name)
                        .accessibilityIdentifier("groupEditor.name")
                }
                membersSection
                rotationSection
                if group.isBuiltIn {
                    Section {
                        EmptyView()
                    } footer: {
                        Text("This is a built-in group. Your changes are saved as your own copy.")
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        group.name = group.name.trimmingCharacters(in: .whitespaces)
                        onSave(group)
                        dismiss()
                    }
                    .disabled(!MovementGroupDraft.canSave(group))
                    .accessibilityIdentifier("groupEditor.save")
                }
            }
            .sheet(isPresented: $isAddingMembers) {
                addMembersSheet
            }
            .task {
                library = (try? await provider.loadExercises()) ?? []
            }
        }
    }

    // MARK: Members

    private var membersSection: some View {
        Section {
            ForEach(Array(group.members.enumerated()), id: \.element.id) { index, member in
                let paused = group.pausedLiftKeys.contains(member.liftKey)
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(member.name)
                            .foregroundStyle(paused ? .secondary : .primary)
                        if paused {
                            Text("Paused — out of rotation, history kept")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Button {
                        MovementGroupDraft.togglePaused(member.liftKey, in: &group)
                    } label: {
                        Image(systemName: paused ? "play.circle" : "pause.circle")
                            .font(.title3)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(paused ? "Resume \(member.name)" : "Pause \(member.name)")
                    .accessibilityIdentifier("groupEditor.pause.\(index)")
                }
            }
            .onDelete { group.members.remove(atOffsets: $0) }
            .onMove { group.members.move(fromOffsets: $0, toOffset: $1) }
            Button {
                isAddingMembers = true
            } label: {
                Label("Add Exercises", systemImage: "plus.circle")
            }
            .accessibilityIdentifier("groupEditor.addMembers")
        } header: {
            Text("Members")
        } footer: {
            Text("The least-recently-done member comes up next, so the group cycles predictably. Ties go to the higher member.")
        }
    }

    /// The library list for adding members, same-pattern lifts first.
    private var addMembersSheet: some View {
        NavigationStack {
            AddGroupMembersList(library: library, group: $group)
                .navigationTitle("Add Exercises")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { isAddingMembers = false }
                            .accessibilityIdentifier("groupEditor.doneAdding")
                    }
                }
        }
    }

    // MARK: Rotation

    private var rotationSection: some View {
        Section {
            Picker("Rotation", selection: Binding(
                get: { group.rotationMode },
                set: { MovementGroupDraft.setRotation($0, on: &group) }
            )) {
                ForEach(GroupRotationMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .accessibilityIdentifier("groupEditor.rotation")
            if group.rotationMode == .onePerBlock {
                Stepper(value: $group.blockWeeks, in: 1...12) {
                    LabeledContent("Block length", value: group.blockWeeks == 1 ? "1 week" : "\(group.blockWeeks) weeks")
                }
                .accessibilityIdentifier("groupEditor.blockWeeks")
            }
        } header: {
            Text("Rotation")
        } footer: {
            Text(group.rotationMode == .onePerBlock
                 ? "Holds one member for the whole block so it can progress, then rotates to the least-recently-done member."
                 : "Rotates every workout. The same group on two days gets a different member each day.")
        }
    }
}

/// Searchable library list that adds tapped entries to a group.
private struct AddGroupMembersList: View {
    let library: [LibraryExercise]
    @Binding var group: MovementGroup
    @State private var searchText = ""

    var body: some View {
        let candidates = MovementGroupDraft.candidates(library, for: group, searchText: searchText)
        List(candidates) { entry in
            Button {
                group.members.append(GroupMember(entry))
                if group.pattern == nil { group.pattern = entry.pattern }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.name).foregroundStyle(.primary)
                        Text(entry.pattern?.displayName ?? entry.muscleGroup.rawValue)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if group.pattern != nil && entry.pattern == group.pattern {
                        Text("Suggested")
                            .font(.caption2.bold())
                            .foregroundStyle(.tint)
                    }
                }
            }
            .accessibilityIdentifier("groupEditor.candidate.\(entry.id)")
        }
        .searchable(text: $searchText, prompt: "Search exercises")
        .overlay {
            if library.isEmpty { ProgressView() }
        }
    }
}
