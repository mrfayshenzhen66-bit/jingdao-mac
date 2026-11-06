//  WorkflowGuide.swift — the beginner's path through the editor (景到 20.8).
//
//  The rails are arranged by *what a thing is* (materials on the left,
//  parameters on the right), which is right for someone who knows film and
//  silent for someone who does not: nothing on screen says which section comes
//  first. This file adds the order without moving anything:
//
//  - `WorkflowStepBar`, a row under the tool bar: ① 选胶片 › ② 选相纸 › ③ 放大机 ›
//    ④ 微调 › ⑤ 导出. Clicking a step opens the rail that owns it, unfolds the
//    section, scrolls it to the top and outlines it for a moment while the other
//    sections dim. It is presentation only: no step changes a parameter.
//  - `CanvasEmptyGuide`, what the canvas says before there is a photograph.
//
//  The bar can be hidden (its ×, or View ▸ Show Beginner Steps); the rails
//  behave exactly as before either way.

import SwiftUI

enum WorkflowRail: Equatable { case left, preDev, postDev }

enum WorkflowStep: Int, CaseIterable, Identifiable {
    case film, print, enlarger, finish, export
    var id: Int { rawValue }

    @MainActor var title: String {
        switch self {
        case .film: L("Film", zh: "选胶片")
        case .print: L("Paper", zh: "选相纸")
        case .enlarger: L("Enlarger", zh: "放大机")
        case .finish: L("Fine-tune", zh: "微调")
        case .export: L("Export", zh: "导出")
        }
    }

    /// One sentence: what this step decides, in the beginner's words.
    @MainActor var hint: String {
        switch self {
        case .film: L("The film sets the colour and the grain.", zh: "胶片决定色彩倾向和颗粒")
        case .print: L("The paper sets contrast and skin tones.", zh: "相纸决定反差和肤色")
        case .enlarger: L("Press Process at the top first, then fine-tune brightness and filters.", zh: "先点顶部「配光」自动定曝光和滤色，再微调亮度、黄、品红")
        case .finish: L("White balance, curve and colour, after the print.", zh: "冲印后再调白平衡、曲线和色彩")
        case .export: L("Choose a format and save the picture.", zh: "选好格式，保存成片")
        }
    }

    /// Where the step lives. `nil` for Export, which opens its own window.
    var target: (rail: WorkflowRail, key: String)? {
        switch self {
        case .film: (.left, "film")
        case .print: (.left, "print")
        case .enlarger: (.left, "enlarger")
        case .finish: (.postDev, "wb2")
        case .export: nil
        }
    }
}

/// Which section the bar last pointed at, for the two rails to act on.
@MainActor
@Observable
final class WorkflowGuide {
    static let shared = WorkflowGuide()
    static let visibleKey = Session.uiKey + "workflowBar.visible"

    /// The step the person is on (the last one they clicked).
    var current: WorkflowStep?
    /// The section to bring into view; `token` changes on every request so
    /// clicking the same step twice still scrolls.
    private(set) var focus: (rail: WorkflowRail, key: String)?
    private(set) var token = 0
    /// The outlined section, cleared after a moment.
    private(set) var highlighted: String?
    @ObservationIgnored private var clearTask: Task<Void, Never>?

    var visible: Bool = UserDefaults.standard.object(forKey: WorkflowGuide.visibleKey) as? Bool ?? true {
        didSet { UserDefaults.standard.set(visible, forKey: Self.visibleKey) }
    }

    func go(_ step: WorkflowStep, session: Session) {
        current = step
        guard let target = step.target else {
            if session.selection != nil { session.showExport = true }
            return
        }
        reveal(target.rail, target.key, session: session)
    }

    /// Open the rail, the tab and the section, then ask the rail to scroll.
    func reveal(_ rail: WorkflowRail, _ key: String, session: Session) {
        switch rail {
        case .left:
            if session.leftCollapsed { withAnimation(.easeOut(duration: 0.18)) { session.leftCollapsed = false } }
        case .preDev, .postDev:
            if session.rightCollapsed { withAnimation(.easeOut(duration: 0.18)) { session.rightCollapsed = false } }
            let tab = rail == .preDev ? ParametersTab.preDev : ParametersTab.postDev
            UserDefaults.standard.set(tab.rawValue, forKey: Session.uiKey + "parametersTab")
        }
        // `PanelSection` keeps its open state in this key (`SectionHeader.swift`).
        UserDefaults.standard.set(true, forKey: Session.uiKey + "section.\(key)")
        focus = (rail, key)
        token &+= 1
        highlighted = key
        clearTask?.cancel()
        clearTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1.8))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.35)) { self?.highlighted = nil }
        }
    }
}

// MARK: - The rails' half

/// Scrolls a rail to the requested section and outlines it; dims the rest.
struct WorkflowFocus: ViewModifier {
    let rail: WorkflowRail
    let proxy: ScrollViewProxy
    @State private var guide = WorkflowGuide.shared

    func body(content: Content) -> some View {
        content.onChange(of: guide.token) { _, _ in
            guard let focus = guide.focus, focus.rail == rail else { return }
            // One runloop later: the tab switch and the unfolded section have
            // to be laid out before there is anything to scroll to.
            DispatchQueue.main.async {
                withAnimation(.easeInOut(duration: 0.3)) { proxy.scrollTo(focus.key, anchor: .top) }
            }
        }
    }
}

/// One rail entry: its scroll identity, plus the outline and dimming.
struct WorkflowEntry: ViewModifier {
    let key: String
    @State private var guide = WorkflowGuide.shared

    func body(content: Content) -> some View {
        let lit = guide.highlighted
        content
            .id(key)
            .opacity(lit == nil || lit == key ? 1 : 0.4)
            .overlay {
                if lit == key {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Theme.accent, lineWidth: 2)
                        .padding(2)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.25), value: lit)
    }
}

extension View {
    func workflowFocus(_ rail: WorkflowRail, proxy: ScrollViewProxy) -> some View {
        modifier(WorkflowFocus(rail: rail, proxy: proxy))
    }
    func workflowEntry(_ key: String) -> some View { modifier(WorkflowEntry(key: key)) }
}

// MARK: - The bar

struct WorkflowStepBar: View {
    @Bindable var session: Session
    @State private var guide = WorkflowGuide.shared

    private var hasPhoto: Bool { session.selection != nil }

    var body: some View {
        HStack(spacing: 6) {
            Text(L("Steps", zh: "步骤"))
                .font(Theme.Font.small).foregroundStyle(Theme.secondaryText.opacity(0.7))
                .padding(.trailing, 2)
            ForEach(WorkflowStep.allCases) { step in
                if step.rawValue > 0 {
                    Image(systemName: "chevron.compact.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.secondaryText.opacity(0.45))
                }
                stepButton(step)
            }
            Spacer(minLength: 8)
            Text(hintText)
                .font(Theme.Font.small).foregroundStyle(Theme.secondaryText)
                .lineLimit(1).truncationMode(.tail)
                .layoutPriority(-1)
            if let next = nextStep {
                Button { guide.go(next, session: session) } label: {
                    Text(L("Next ›", zh: "下一步 ›"))
                        .font(Theme.Font.small).foregroundStyle(Theme.accent)
                }
                .buttonStyle(.plain)
                .disabled(!hasPhoto)
                .opacity(hasPhoto ? 1 : 0.4)
            }
            Button { withAnimation(.easeOut(duration: 0.18)) { guide.visible = false } } label: {
                Image(systemName: "xmark").font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.secondaryText.opacity(0.7))
                    .frame(width: 18, height: 18).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(L("Hide the steps (View ▸ Show Beginner Steps brings them back)",
                    zh: "隐藏步骤条（可在「视图 ▸ 显示新手步骤条」重新打开）"))
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity)
        .frame(height: 30)
        .background(Theme.card)
    }

    private var nextStep: WorkflowStep? {
        guard let c = guide.current else { return .film }
        return WorkflowStep(rawValue: c.rawValue + 1)
    }

    private var hintText: String {
        guard hasPhoto else { return L("Open a photograph to begin.", zh: "先打开一张照片") }
        return (guide.current ?? .film).hint
    }

    private func stepButton(_ step: WorkflowStep) -> some View {
        let current = guide.current
        let done = current.map { step.rawValue < $0.rawValue } ?? false
        let active = current == step
        return Button { guide.go(step, session: session) } label: {
            HStack(spacing: 4) {
                ZStack {
                    Circle().fill(active ? Theme.accent : (done ? Theme.accent.opacity(0.35) : Theme.ground))
                        .frame(width: 16, height: 16)
                    if done {
                        Image(systemName: "checkmark").font(.system(size: 8, weight: .bold)).foregroundStyle(Theme.text)
                    } else {
                        Text("\(step.rawValue + 1)").font(.system(size: 9, weight: .bold))
                            .foregroundStyle(active ? Color.black : Theme.text)
                    }
                }
                Text(step.title)
                    .font(Theme.Font.small)
                    .foregroundStyle(active ? Theme.accent : Theme.text)
            }
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(active ? Theme.accent.opacity(0.12) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!hasPhoto)
        .opacity(hasPhoto ? 1 : 0.5)
        .help(step.hint)
    }
}

// MARK: - The empty canvas

/// Before there is a photograph the canvas says how to start, and the order
/// of what follows. With a folder open and nothing picked, it points at the
/// filmstrip instead.
struct CanvasEmptyGuide: View {
    @Bindable var session: Session

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: session.frames.isEmpty ? "photo.on.rectangle.angled" : "hand.point.down")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Theme.accent)
            if session.frames.isEmpty {
                Text(L("Drop photographs here, or open them", zh: "把照片拖到这里，或点「打开照片」"))
                    .font(Theme.Font.action).foregroundStyle(Theme.text)
                Button { session.openPanel() } label: {
                    Text(L("Open Photos…", zh: "打开照片…"))
                        .font(Theme.Font.body).foregroundStyle(Color.black)
                        .padding(.horizontal, 16).padding(.vertical, 7)
                        .background(Theme.accent, in: Capsule())
                }
                .buttonStyle(.plain)
            } else {
                Text(L("Pick a photograph in the filmstrip below", zh: "在下方胶片条里点一张照片开始"))
                    .font(Theme.Font.action).foregroundStyle(Theme.text)
            }
            HStack(spacing: 8) {
                ForEach(Array(steps.enumerated()), id: \.offset) { i, s in
                    if i > 0 { Image(systemName: "arrow.right").font(.system(size: 9)).foregroundStyle(Theme.secondaryText.opacity(0.6)) }
                    Text(s).font(Theme.Font.small).foregroundStyle(Theme.secondaryText)
                }
            }
            .padding(.top, 6)
            Text(L("RAW files give the most faithful film rendering.", zh: "推荐使用 RAW 原片，胶片效果最接近真实"))
                .font(Theme.Font.small).foregroundStyle(Theme.secondaryText.opacity(0.7))
        }
        .padding(28)
        .background(Theme.card.opacity(0.92), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var steps: [String] {
        [L("① Open", zh: "① 打开照片"), L("② Film & paper", zh: "② 选胶片和相纸"),
         L("③ Process & brightness", zh: "③ 配光、调亮度"), L("④ Export", zh: "④ 导出")]
    }
}
