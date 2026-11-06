import SwiftUI

/// Personal material combinations; exposure and other per-photo edits are
/// deliberately outside this section's scope.
struct FilmPaperPresetSection: View {
    static let key = "filmPaperPresets"
    @Bindable var session: Session
    @State private var selectedPresetID: UUID?
    @State private var nameDraft: CombinationNameDraft?
    @State private var deletionDraft: FilmPaperPreset?
    @State private var applyProblem: String?

    private var store: FilmPaperPresetStore { session.filmPaperPresets }
    private var currentCombination: FilmPaperCombination { FilmPaperCombination(session.params) }
    private var selectedPreset: FilmPaperPreset? {
        let matches = store.presets.filter { $0.combination == currentCombination }
        return matches.first { $0.id == selectedPresetID } ?? matches.first
    }

    var body: some View {
        PanelSection(L(.sectionFilmPaperPresets), key: Self.key, menu: sectionMenu {
            if store.presets.isEmpty {
                Button(L(.combinationEmpty)) {}.disabled(true)
            } else {
                ForEach(store.presets) { preset in
                    Menu(preset.name) {
                        Button(L(.combinationRename)) {
                            nameDraft = CombinationNameDraft(presetID: preset.id, name: preset.name,
                                                             combination: preset.combination)
                        }
                        Button(L(.combinationDelete)) { deletionDraft = preset }
                    }
                    .disabled(session.batchExporting)
                }
            }
        }) {
            RailRows {
                ToggleRow(label: L(.combinationRemember),
                          isOn: Binding(get: { store.rememberLastCombination },
                                        set: { store.rememberLastCombination = $0 }),
                          enabled: !session.batchExporting,
                          sublabel: L(.combinationRememberCaption))
                caption(L(.combinationScope))
                if session.selection == nil && store.rememberLastCombination {
                    caption(L(.combinationEmptyCanvas))
                }
                if store.presets.isEmpty {
                    caption(L(.combinationEmpty))
                } else {
                    presetMenu
                }
                HStack {
                    Button {
                        nameDraft = CombinationNameDraft(combination: currentCombination)
                    } label: {
                        Text(L(.combinationSave))
                            .font(Theme.Font.value)
                            .foregroundStyle(Theme.text)
                            .padding(.horizontal, 12)
                            .frame(height: Theme.Metric.controlHeight)
                            .background(Theme.pill, in: Capsule())
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .rowEnabled(session.canApplyFilmPaperCombination)
                    Spacer(minLength: 0)
                }
                if let applyProblem { caption(applyProblem) }
                if store.problem != nil { caption(L(.combinationStoreProblem)) }
            }
        }
        .sheet(item: $nameDraft) { draft in
            CombinationNameEditor(draft: draft) { name in
                guard !session.batchExporting else { throw CombinationNameError.unavailable }
                if let id = draft.presetID {
                    try store.renamePreset(id: id, name: name)
                } else {
                    guard let valid = draft.combination.validated(in: session.catalog) else {
                        throw CombinationNameError.unavailable
                    }
                    let saved = try store.savePreset(name: name, combination: valid)
                    selectedPresetID = saved.id
                }
            }
        }
        .alert(L(.combinationDeleteQuestion), isPresented: Binding(
            get: { deletionDraft != nil },
            set: { if !$0 { deletionDraft = nil } }
        )) {
            Button(L(.combinationCancel), role: .cancel) { deletionDraft = nil }
            Button(L(.combinationDelete), role: .destructive) {
                if !session.batchExporting, let preset = deletionDraft {
                    store.deletePreset(id: preset.id)
                    if selectedPresetID == preset.id { selectedPresetID = nil }
                }
                deletionDraft = nil
            }
        } message: {
            Text(String(format: L(.combinationDeleteCaption), deletionDraft?.name ?? ""))
        }
    }

    private var presetMenu: some View {
        Menu {
            ForEach(store.presets) { preset in
                Button {
                    if session.applyFilmPaperCombination(preset.combination) {
                        selectedPresetID = preset.id
                        applyProblem = nil
                    } else {
                        applyProblem = L(.combinationApplyFailed)
                    }
                } label: {
                    if selectedPreset?.id == preset.id {
                        Label(preset.name, systemImage: "checkmark")
                    } else {
                        Text(preset.name)
                    }
                }
            }
        } label: {
            Text(selectedPreset?.name ?? L(.combinationChoose))
                .font(Theme.Font.value)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .menuStyle(.borderlessButton)
        .rowEnabled(session.canApplyFilmPaperCombination)
        .help(L(.combinationApplyHelp))
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(Theme.Font.meta)
            .foregroundStyle(Theme.Ink.tertiary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func sectionMenu<Content: View>(@ViewBuilder _ content: @escaping () -> Content) -> () -> AnyView {
        { AnyView(content()) }
    }
}

private struct CombinationNameDraft: Identifiable {
    let id = UUID()
    var presetID: UUID? = nil
    var name = ""
    let combination: FilmPaperCombination
}

private enum CombinationNameError: Error {
    case unavailable
}

private struct CombinationNameEditor: View {
    let draft: CombinationNameDraft
    let save: (String) throws -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var problem: String?
    @FocusState private var nameFocused: Bool

    init(draft: CombinationNameDraft, save: @escaping (String) throws -> Void) {
        self.draft = draft
        self.save = save
        _name = State(initialValue: draft.name)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(draft.presetID == nil ? L(.combinationSave) : L(.combinationRename))
                .font(.headline)
            Text(L(.combinationScope)).font(.caption).foregroundStyle(.secondary)
            TextField(L(.combinationName), text: $name)
                .textFieldStyle(.roundedBorder)
                .focused($nameFocused)
                .onSubmit { submit() }
            if let problem {
                Text(problem).font(.caption).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                Button(L(.combinationCancel)) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(L(.combinationSaveAction)) { submit() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 360)
        .onAppear { nameFocused = true }
    }

    private func submit() {
        do {
            try save(name)
            dismiss()
        } catch let error as FilmPaperPresetError {
            problem = switch error {
            case .emptyName: L(.combinationEmptyName)
            case .duplicateName: L(.combinationDuplicateName)
            case .presetNotFound: L(.combinationMissing)
            }
        } catch is CombinationNameError {
            problem = L(.combinationApplyFailed)
        } catch {
            problem = L(.combinationSaveFailed)
        }
    }
}
