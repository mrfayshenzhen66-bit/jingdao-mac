// PanelOrderSheet.swift — arrows work with a mouse, keyboard and VoiceOver.
import SwiftUI

/// The same manager is presented from either rail's context menu or Settings.
struct PanelOrderManagerSheet: View {
    @State private var edits: PanelOrderEdits
    @State private var group: PanelOrderGroup
    @Environment(\.dismiss) private var dismiss
    private let store: PanelOrderStore

    init(initialGroup: PanelOrderGroup = .left, store: PanelOrderStore = .shared) {
        self.store = store
        _edits = State(initialValue: store.beginEditing())
        _group = State(initialValue: initialGroup)
    }

    private var draft: PanelOrderDraft { edits.draft(for: group) }

    private func groupTitle(_ group: PanelOrderGroup) -> String {
        switch group {
        case .left: L("Left · Film and Print", zh: "左栏 · 胶片与相纸")
        case .preDev: L("Right · Pre-Dev", zh: "右栏 · 显影前")
        case .postDev: L("Right · Post-Dev", zh: "右栏 · 显影后")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L("Edit Panels", zh: "显示编辑面板")).font(.headline)
            Picker(L("Panel", zh: "面板"), selection: $group) {
                ForEach(PanelOrderGroup.allCases, id: \.self) { group in
                    Text(groupTitle(group)).tag(group)
                }
            }
            .pickerStyle(.menu)
            Text(L("Use the arrows to move sections. Your order is remembered next time.",
                   zh: "用上下箭头移动栏目，下次打开仍保留此顺序。"))
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(L("Some sections appear only for the relevant photo or enabled feature.",
                   zh: "部分栏目仅在对应照片或功能可用时显示。"))
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(draft.visibleOrder, id: \.self) { id in
                        HStack(spacing: 10) {
                            Text(title(for: id)).frame(maxWidth: .infinity, alignment: .leading)
                            moveButton(id, offset: -1, symbol: "arrow.up")
                            moveButton(id, offset: 1, symbol: "arrow.down")
                        }
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        .background(Theme.well, in: RoundedRectangle(cornerRadius: 5))
                    }
                }
            }
            .frame(height: min(CGFloat(draft.visibleOrder.count) * 43, 420))
            HStack {
                Button(L("Restore Default", zh: "恢复默认")) { edits.reset(group) }
                    .help(L("Restore the selected panel's default order", zh: "恢复当前所选面板的默认顺序"))
                Spacer()
                Button(L("Cancel", zh: "取消")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(L("OK", zh: "确定")) { store.save(edits); dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 430)
        .background(Theme.ground)
    }

    private func moveButton(_ id: String, offset: Int, symbol: String) -> some View {
        Button { edits.move(id, in: group, by: offset) } label: {
            Image(systemName: symbol).frame(width: 14)
        }
        .buttonStyle(.bordered).controlSize(.small)
        .disabled(!draft.canMove(id, by: offset))
        .help(offset < 0 ? L("Move up", zh: "上移") : L("Move down", zh: "下移"))
        .accessibilityLabel(title(for: id) + " · " +
            (offset < 0 ? L("Move up", zh: "上移") : L("Move down", zh: "下移")))
    }

    private func title(for id: String) -> String {
        switch id {
        case "navigator": L(.sectionNavigator)
        case "pair": L("Half-Frame Pair", zh: "半格拼接")
        case "filmPaperPresets": L(.sectionFilmPaperPresets)
        case "clipboard": L(.sectionClipboard)
        case "film": L(.sectionFilm)
        case "filmEdge": L(.sectionFilmEdge)
        case "dateBack": L(.sectionDateBack)
        case "print": L(.sectionPrint)
        case "crop": L(.sectionCrop)
        case "enlarger": L(.sectionEnlarger)
        case "latitude": L(.sectionLatitude)
        case "camera": L(.sectionCamera)
        case "filmFormat": L(.filmFormat)
        case "scenePlacement": L(.sectionScenePlacement)
        case "toneMask": L(.sectionToneMask)
        case "wb2": L(.sectionWhiteBalance)
        case "exposure2": L(.sectionExposure)
        case "curve": L(.sectionCurve)
        case "colorbalance": L(.sectionColorBalance)
        case "hsl": "HSL"
        case "masks": L("Masks", zh: "蒙版")
        default: id
        }
    }
}
