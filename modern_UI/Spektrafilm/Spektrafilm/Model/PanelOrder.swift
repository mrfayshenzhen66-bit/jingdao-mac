// PanelOrder.swift — presentation order only; never a processing pipeline.
import Foundation
import Observation

enum PanelOrderGroup: String, CaseIterable, Sendable {
    case left, preDev, postDev

    var defaultIDs: [String] {
        switch self {
        case .left:
            ["navigator", "pair", "filmPaperPresets", "clipboard", "film", "filmEdge",
             "dateBack", "print", "crop", "enlarger"]
        case .preDev: ["latitude", "camera", "filmFormat", "scenePlacement", "toneMask"]
        case .postDev: ["wb2", "exposure2", "curve", "colorbalance", "hsl", "masks"]
        }
    }

    var storageKey: String { "ui2.panelOrder.\(rawValue).v1" }

    func normalized(_ saved: [String]) -> [String] {
        let known = Set(defaultIDs)
        var seen = Set<String>()
        // Missing/new sections are appended; damaged or obsolete ids cannot
        // hide a section or give ForEach duplicate identities.
        return (saved + defaultIDs).filter { known.contains($0) && seen.insert($0).inserted }
    }
}

/// A sheet edits its own value. Dismissal and Cancel cannot write preferences.
struct PanelOrderDraft {
    let group: PanelOrderGroup
    let availableIDs: Set<String>
    private(set) var order: [String]

    init(group: PanelOrderGroup, order: [String], availableIDs: [String]) {
        self.group = group
        self.order = group.normalized(order)
        self.availableIDs = Set(availableIDs)
    }

    var visibleOrder: [String] { order.filter { availableIDs.contains($0) } }

    func canMove(_ id: String, by offset: Int) -> Bool {
        guard offset == -1 || offset == 1,
              let index = visibleOrder.firstIndex(of: id) else { return false }
        return visibleOrder.indices.contains(index + offset)
    }

    mutating func move(_ id: String, by offset: Int) {
        guard canMove(id, by: offset), let index = visibleOrder.firstIndex(of: id) else { return }
        var visible = visibleOrder
        visible.swapAt(index, index + offset)
        var next = 0
        // Pair/Crop and feature-gated sections retain their slots while hidden.
        // Changing the visible list must not erase their remembered position.
        order = order.map { id in
            guard availableIDs.contains(id) else { return id }
            defer { next += 1 }
            return visible[next]
        }
    }

    mutating func reset() { order = group.defaultIDs }
}

/// One manager can edit all three groups before confirming. Save only groups
/// that this manager changed, so an untouched draft cannot undo another window.
struct PanelOrderEdits {
    private let originalOrders: [PanelOrderGroup: [String]]
    private var drafts: [PanelOrderGroup: PanelOrderDraft]

    init(drafts: [PanelOrderDraft]) {
        self.drafts = Dictionary(uniqueKeysWithValues: drafts.map { ($0.group, $0) })
        originalOrders = Dictionary(uniqueKeysWithValues: drafts.map { ($0.group, $0.order) })
    }

    func draft(for group: PanelOrderGroup) -> PanelOrderDraft {
        drafts[group] ?? PanelOrderDraft(group: group, order: group.defaultIDs,
                                         availableIDs: group.defaultIDs)
    }

    mutating func move(_ id: String, in group: PanelOrderGroup, by offset: Int) {
        drafts[group]?.move(id, by: offset)
    }

    mutating func reset(_ group: PanelOrderGroup) { drafts[group]?.reset() }

    var changedDrafts: [PanelOrderDraft] {
        PanelOrderGroup.allCases.compactMap { group in
            guard let draft = drafts[group], draft.order != originalOrders[group] else { return nil }
            return draft
        }
    }
}

@MainActor
@Observable
final class PanelOrderStore {
    /// All live panels and the Settings manager observe this same instance.
    /// Tests continue to own a separate store with an injected defaults suite.
    static let shared = PanelOrderStore()
    @ObservationIgnored private let defaults: UserDefaults
    private var orders: [PanelOrderGroup: [String]]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        orders = [:]
        reloadFromDefaults()
    }

    func reloadFromDefaults() {
        orders = Dictionary(uniqueKeysWithValues: PanelOrderGroup.allCases.map {
            ($0, $0.normalized(defaults.stringArray(forKey: $0.storageKey) ?? []))
        })
    }

    func beginEditing() -> PanelOrderEdits {
        PanelOrderEdits(drafts: PanelOrderGroup.allCases.map {
            draft(for: $0, availableIDs: $0.defaultIDs)
        })
    }

    func draft(for group: PanelOrderGroup, availableIDs: [String]) -> PanelOrderDraft {
        PanelOrderDraft(group: group, order: orders[group] ?? group.defaultIDs,
                        availableIDs: availableIDs)
    }

    func arranged<Value>(_ entries: [(String, Value)], in group: PanelOrderGroup) -> [(String, Value)] {
        let rank = Dictionary(uniqueKeysWithValues: (orders[group] ?? group.defaultIDs)
            .enumerated().map { ($0.element, $0.offset) })
        return entries.enumerated().sorted { a, b in
            let left = rank[a.element.0] ?? Int.max
            let right = rank[b.element.0] ?? Int.max
            return left == right ? a.offset < b.offset : left < right
        }.map(\.element)
    }

    func save(_ draft: PanelOrderDraft) {
        let normalized = draft.group.normalized(draft.order)
        orders[draft.group] = normalized
        defaults.set(normalized, forKey: draft.group.storageKey)
    }

    func save(_ edits: PanelOrderEdits) {
        for draft in edits.changedDrafts { save(draft) }
    }

    func reset(_ group: PanelOrderGroup) {
        orders[group] = group.defaultIDs
        defaults.removeObject(forKey: group.storageKey)
    }
}
