//
//  ExerciseLibrarySheet.swift
//  Train
//
//  Browsable strength exercise library. Entries load asynchronously through
//  the `ExerciseLibraryProvider` abstraction (bundled JSON today, mergeable
//  with a server-based catalog later). Searchable, filterable by muscle group
//  via the chip row at the top, and grouped by muscle group; tapping an entry
//  shows details with a sets × reps plan and an Add button.
//

import SwiftUI
import SwiftData

// MARK: - Filtering

/// Pure filtering/grouping helpers for the exercise library list. Kept out of
/// the view so the search + muscle-group filter math is unit-testable (same
/// pattern as `StrengthBoardPlanner`).
enum ExerciseLibraryFilter {

    /// Whether an entry survives the current search text and group filter.
    /// - Parameters:
    ///   - entry: The library entry to test.
    ///   - searchText: Free-text search; empty matches everything. Matched
    ///     against name, muscle group, and equipment.
    ///   - group: Primary muscle group to restrict to, or `nil` for all.
    static func matches(_ entry: LibraryExercise, searchText: String, group: MuscleGroup?) -> Bool {
        if let group, entry.muscleGroup != group { return false }
        guard !searchText.isEmpty else { return true }
        return entry.name.localizedCaseInsensitiveContains(searchText)
            || entry.muscleGroup.rawValue.localizedCaseInsensitiveContains(searchText)
            || entry.equipment.localizedCaseInsensitiveContains(searchText)
    }

    /// Filters entries and groups the survivors by primary muscle group,
    /// dropping empty groups. Groups follow `MuscleGroup.allCases` order;
    /// entries within a group are sorted by name.
    /// - Parameters:
    ///   - entries: All library entries.
    ///   - searchText: Free-text search; empty matches everything.
    ///   - group: Primary muscle group to restrict to, or `nil` for all.
    static func grouped(
        _ entries: [LibraryExercise],
        searchText: String,
        group: MuscleGroup?
    ) -> [(group: MuscleGroup, entries: [LibraryExercise])] {
        let filtered = entries.filter { matches($0, searchText: searchText, group: group) }
        return MuscleGroup.allCases.compactMap { candidate in
            let members = filtered
                .filter { $0.muscleGroup == candidate }
                .sorted { $0.name < $1.name }
            return members.isEmpty ? nil : (candidate, members)
        }
    }

    /// The muscle groups actually represented in the library, in
    /// `MuscleGroup.allCases` order. Drives the filter chip row, so chips stay
    /// stable while the user types in the search field.
    /// - Parameter entries: All library entries.
    static func availableGroups(_ entries: [LibraryExercise]) -> [MuscleGroup] {
        let present = Set(entries.map(\.muscleGroup))
        return MuscleGroup.allCases.filter { present.contains($0) }
    }
}

// MARK: - Sheet

/// Sheet presenting the exercise library for adding an exercise to a day.
struct ExerciseLibrarySheet: View {
    /// Source of library entries. Defaults to the app's composite provider.
    var provider: any ExerciseLibraryProvider = .default
    /// Called with the chosen entry and its drafted plan; the caller creates
    /// the board exercise.
    let onSelect: (LibraryExercise, StrengthPlanDraft) -> Void
    /// Called with a chosen movement group (#24) and its plan; `nil` hides
    /// the Groups chip.
    var onSelectGroup: ((MovementGroup, StrengthPlanDraft) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var exercises: [LibraryExercise] = []
    @State private var searchText: String = ""
    @State private var selectedGroup: MuscleGroup?
    @State private var loadFailed = false
    @State private var showCreateForm = false
    /// Whether the Groups chip is selected (the list shows groups).
    @State private var showingGroups = false
    /// Built-in and athlete groups, loaded from the context.
    @State private var groups: [MovementGroup] = []
    /// The group being created or edited in the editor sheet.
    @State private var editingGroup: GroupEditRequest?

    /// Entries matching the current search and group filter, grouped by
    /// primary muscle group.
    private var groupedExercises: [(group: MuscleGroup, entries: [LibraryExercise])] {
        ExerciseLibraryFilter.grouped(exercises, searchText: searchText, group: selectedGroup)
    }

    /// Muscle groups represented in the loaded library.
    private var availableGroups: [MuscleGroup] {
        ExerciseLibraryFilter.availableGroups(exercises)
    }

    var body: some View {
        NavigationStack {
            Group {
                if loadFailed {
                    ContentUnavailableView(
                        "Library Unavailable",
                        systemImage: "exclamationmark.triangle",
                        description: Text("The exercise library could not be loaded.")
                    )
                } else if exercises.isEmpty {
                    ProgressView("Loading library…")
                } else {
                    VStack(spacing: 0) {
                        filterChips
                        Divider()
                        if showingGroups {
                            groupList
                        } else {
                            libraryList
                        }
                    }
                }
            }
            .navigationTitle("Exercise Library")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    if showingGroups {
                        Button {
                            editingGroup = GroupEditRequest(
                                group: MovementGroup(id: MovementGroup.userPrefix + UUID().uuidString, name: "", members: []),
                                title: "New Group"
                            )
                        } label: {
                            Label("New Group", systemImage: "plus")
                        }
                        .accessibilityIdentifier("exerciseLibrary.newGroup")
                    } else {
                        Button {
                            showCreateForm = true
                        } label: {
                            Label("New Exercise", systemImage: "plus")
                        }
                        .accessibilityIdentifier("exerciseLibrary.create")
                    }
                }
            }
            .sheet(isPresented: $showCreateForm, onDismiss: { Task { await load() } }) {
                UserExerciseFormSheet()
            }
            .sheet(item: $editingGroup) { request in
                MovementGroupEditorSheet(group: request.group, title: request.title, provider: provider) { edited in
                    MovementGroupStore.save(edited, in: modelContext)
                    loadGroups()
                }
            }
        }
        .task { await load() }
    }

    /// Loads (or reloads) the library entries from the provider.
    private func load() async {
        loadGroups()
        do {
            exercises = try await provider.loadExercises()
            loadFailed = exercises.isEmpty
        } catch {
            loadFailed = true
        }
    }

    /// Reloads the groups from the context (after an edit).
    private func loadGroups() {
        groups = Array(StrengthSlotResolver.groups(in: modelContext).values)
            .sorted { lhs, rhs in
                if lhs.isBuiltIn != rhs.isBuiltIn { return lhs.isBuiltIn }
                return lhs.name < rhs.name
            }
    }

    // MARK: - Muscle Group Filter

    /// Horizontally scrolling muscle-group chips pinned above the list, so a
    /// group can be targeted without scrolling the whole catalog.
    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                filterChip(nil, label: "All")
                if onSelectGroup != nil {
                    groupsChip
                }
                ForEach(availableGroups) { group in
                    filterChip(group, label: group.rawValue)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .accessibilityIdentifier("exerciseLibrary.filterChips")
    }

    /// One filter chip. Tapping the selected group chip clears the filter.
    /// - Parameters:
    ///   - group: The group the chip selects, or `nil` for the "All" chip.
    ///   - label: Chip text.
    private func filterChip(_ group: MuscleGroup?, label: String) -> some View {
        let isSelected = !showingGroups && selectedGroup == group
        let accent = group?.color ?? .blue
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                showingGroups = false
                selectedGroup = isSelected ? nil : group
            }
        } label: {
            Text(label)
                .font(.caption.bold())
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule().fill(isSelected ? accent : accent.opacity(0.12))
                )
                .foregroundStyle(isSelected ? .white : accent)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("exerciseLibrary.filter.\(group?.rawValue ?? "All")")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// The "Groups" chip: switches the list to movement groups.
    private var groupsChip: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) { showingGroups.toggle() }
        } label: {
            Label("Groups", systemImage: "arrow.triangle.2.circlepath")
                .font(.caption.bold())
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Capsule().fill(showingGroups ? Color.indigo : Color.indigo.opacity(0.12)))
                .foregroundStyle(showingGroups ? .white : .indigo)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("exerciseLibrary.filter.Groups")
        .accessibilityAddTraits(showingGroups ? .isSelected : [])
    }

    // MARK: - Groups

    /// Movement groups, searchable by name or member.
    private var groupList: some View {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        let shown = groups.filter { group in
            query.isEmpty || group.name.localizedCaseInsensitiveContains(query)
                || group.members.contains { $0.name.localizedCaseInsensitiveContains(query) }
        }
        return List(shown) { group in
            NavigationLink {
                MovementGroupDetailView(group: group) { plan in
                    onSelectGroup?(group, plan)
                    dismiss()
                } onEdit: {
                    editingGroup = GroupEditRequest(group: group, title: "Edit Group")
                }
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(group.name).font(.subheadline.bold())
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(group.members.map(\.name).joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .accessibilityIdentifier("exerciseLibrary.group.\(group.name)")
        }
        .searchable(text: $searchText, prompt: "Search groups")
        .accessibilityIdentifier("exerciseLibrary.groupList")
    }

    // MARK: - List

    /// The searchable, muscle-group-sectioned list of library entries.
    private var libraryList: some View {
        List {
            ForEach(groupedExercises, id: \.group) { section in
                Section {
                    ForEach(section.entries) { entry in
                        NavigationLink {
                            LibraryExerciseDetailView(entry: entry) { plan in
                                onSelect(entry, plan)
                                dismiss()
                            }
                        } label: {
                            libraryRow(entry)
                        }
                        .swipeActions(edge: .trailing) {
                            if entry.isUserCreated {
                                Button(role: .destructive) {
                                    deleteUserEntry(entry)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                } header: {
                    Label(section.group.rawValue, systemImage: "figure.strengthtraining.traditional")
                        .foregroundStyle(section.group.color)
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search exercises")
        .overlay {
            if groupedExercises.isEmpty {
                ContentUnavailableView(
                    "No Exercises",
                    systemImage: "magnifyingglass",
                    description: Text("No exercises match the current search and filter.")
                )
            }
        }
        .accessibilityIdentifier("exerciseLibrary.list")
    }

    /// Deletes a user-created entry from the store and reloads the list.
    private func deleteUserEntry(_ entry: LibraryExercise) {
        try? UserLibraryEditor.delete(entryID: entry.id, in: modelContext)
        Task { await load() }
    }

    /// A single library row: name, equipment, and difficulty, plus a
    /// "Custom" tag on user-created entries.
    private func libraryRow(_ entry: LibraryExercise) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(entry.name)
                    .font(.subheadline.bold())
                if entry.isUserCreated {
                    Text("Custom")
                        .font(.caption2.bold())
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(.tint.opacity(0.15))
                        .foregroundStyle(.tint)
                        .clipShape(Capsule())
                }
            }
            HStack(spacing: 6) {
                if !entry.equipment.isEmpty {
                    Text(entry.equipment)
                    Text("·")
                }
                Text(entry.difficulty)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Group detail

/// A request to open the group editor.
struct GroupEditRequest: Identifiable {
    let id = UUID()
    let group: MovementGroup
    let title: String
}

/// One movement group: its members and rotation, a sets × reps plan, and
/// Add — a group lands on a day exactly like a single lift.
struct MovementGroupDetailView: View {
    let group: MovementGroup
    /// Called with the drafted plan when the user adds the group.
    let onAdd: (StrengthPlanDraft) -> Void
    /// Opens the editor.
    let onEdit: () -> Void

    @State private var plan = StrengthPlanDraft()

    var body: some View {
        List {
            Section {
                ForEach(group.members) { member in
                    HStack {
                        Text(member.name)
                        Spacer()
                        if group.pausedLiftKeys.contains(member.liftKey) {
                            Text("Paused").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("Members")
            } footer: {
                Text("The board offers the least-recently-done member each session. Tap a card's member to swap on the day.")
            }
            Section("Rotation") {
                LabeledContent("Mode", value: group.rotationMode.displayName)
                if group.rotationMode == .onePerBlock {
                    LabeledContent("Block length", value: "\(group.blockWeeks) weeks")
                }
                if let pattern = group.pattern {
                    LabeledContent("Pattern", value: pattern.displayName)
                }
            }
            StrengthPlanFields(draft: $plan)
            Section {
                Button {
                    onAdd(plan)
                } label: {
                    Label("Add to This Day", systemImage: "plus.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .accessibilityIdentifier("exerciseLibrary.addGroup")
            }
        }
        .navigationTitle(group.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit", action: onEdit)
                    .accessibilityIdentifier("exerciseLibrary.editGroup")
            }
        }
    }
}

// MARK: - Detail

/// Detail view for one library entry with a sets × reps plan and an Add
/// button, so a new exercise lands on the board already planned.
struct LibraryExerciseDetailView: View {
    let entry: LibraryExercise
    /// Called with the drafted plan when the user adds this exercise.
    let onAdd: (StrengthPlanDraft) -> Void

    @State private var plan = StrengthPlanDraft()

    var body: some View {
        List {
            Section("Description") {
                Text(entry.details)
            }
            Section("Details") {
                LabeledContent("Muscle Group", value: entry.muscleGroup.rawValue)
                if !entry.secondaryMuscleGroups.isEmpty {
                    LabeledContent(
                        "Also Works",
                        value: entry.secondaryMuscleGroups.map(\.rawValue).joined(separator: ", ")
                    )
                }
                LabeledContent("Equipment", value: entry.equipment)
                LabeledContent("Difficulty", value: entry.difficulty)
            }
            StrengthPlanFields(draft: $plan)
            Section {
                Button {
                    onAdd(plan)
                } label: {
                    Label("Add to This Day", systemImage: "plus.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .accessibilityIdentifier("exerciseLibrary.add")
            }
        }
        .navigationTitle(entry.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    ExerciseLibrarySheet(onSelect: { _, _ in })
}
