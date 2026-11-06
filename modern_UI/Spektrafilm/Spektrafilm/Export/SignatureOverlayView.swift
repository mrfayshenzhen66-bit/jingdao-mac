import SwiftUI

/// A cached, unsigned proof plus the recipe's final PNG layer. Both the
/// displayed pixels and the drag target use the export compositor's geometry.
struct SignatureOverlayView: View {
    let baseImage: CGImage
    let signatureImage: CGImage?
    let settings: SignatureSettings
    let displaySize: CGSize
    let alreadyComposited: Bool
    let editable: Bool
    let onEditingBegan: () -> Void
    let onCommit: (SignatureSettings) -> Void
    let onProblem: (String?) -> Void

    @State private var renderedImage: CGImage?
    @State private var renderedRequest: RenderRequest?
    @State private var dragDraft: SignatureSettings?
    @State private var dragStart: SignatureSettings?
    @State private var dragPhotoSize: CGSize?
    @State private var hovered = false
    @State private var coordinateSpaceID = UUID()

    private struct RenderRequest: Equatable {
        let base: CGImage
        let signature: CGImage?
        let settings: SignatureSettings
        let baked: Bool

        static func == (lhs: Self, rhs: Self) -> Bool {
            ObjectIdentifier(lhs.base) == ObjectIdentifier(rhs.base)
                && lhs.signature.map(ObjectIdentifier.init) == rhs.signature.map(ObjectIdentifier.init)
                && lhs.settings == rhs.settings && lhs.baked == rhs.baked
        }
    }

    private var activeSettings: SignatureSettings { dragDraft ?? settings }
    private var renderRequest: RenderRequest {
        RenderRequest(base: baseImage, signature: signatureImage,
                      settings: activeSettings, baked: alreadyComposited)
    }
    private var signatureSize: CGSize {
        signatureImage.map { CGSize(width: $0.width, height: $0.height) } ?? .zero
    }
    private var signatureRect: CGRect {
        SignatureCompositor.rect(settings: activeSettings, photoSize: displaySize,
                                 signatureSize: signatureSize)
    }
    private var canDrag: Bool {
        editable && settings.enabled && signatureImage != nil
            && displaySize.width > 0 && displaySize.height > 0
    }
    private var shownImage: CGImage {
        // Never show a signature painted for a different geometry than its
        // hit target. The synchronous change callback supplies one snapshot.
        guard activeSettings.enabled, renderedRequest == renderRequest else { return baseImage }
        return renderedImage ?? baseImage
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Image(decorative: shownImage, scale: 1)
                .resizable()
                .interpolation(.high)
                .frame(width: displaySize.width, height: displaySize.height)
            if canDrag {
                let rect = signatureRect
                Color.clear
                    .frame(width: max(24, rect.width), height: max(24, rect.height))
                    .contentShape(Rectangle())
                    .position(x: rect.midX, y: rect.midY)
                    .onHover { hovered = $0 }
                    .gesture(dragGesture)
                    .accessibilityLabel(L("Signature position", zh: "签名位置"))
                    .accessibilityHint(L("Drag the signature within the photo.", zh: "在照片范围内拖动签名。"))
                    .help(L("Drag to position the signature", zh: "拖动调整签名位置"))
                if hovered || dragDraft != nil {
                    Rectangle()
                        .stroke(.white, lineWidth: 1)
                        .shadow(color: .black.opacity(0.8), radius: 1)
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                        .allowsHitTesting(false)
                }
            }
        }
        .frame(width: displaySize.width, height: displaySize.height)
        .clipped()
        .coordinateSpace(name: coordinateSpaceID)
        .onChange(of: renderRequest, initial: true) { _, request in renderPreview(request) }
        .onChange(of: editable) { _, canEdit in
            if !canEdit { clearDrag() }
        }
        .onChange(of: settings.asset?.id) { _, _ in clearDrag() }
        .onDisappear { clearDrag() }
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .named(coordinateSpaceID))
            .onChanged { value in
                guard canDrag else { return }
                if dragStart == nil {
                    onEditingBegan()
                    // Start at the rendered centre, including edge clamping,
                    // so a signature against an edge never has a dead zone.
                    dragStart = clamped(settings, in: displaySize)
                    dragPhotoSize = displaySize
                }
                guard var next = dragStart, let size = dragPhotoSize else { return }
                next.centerX += value.translation.width / size.width
                next.centerY += value.translation.height / size.height
                dragDraft = clamped(next, in: size)
            }
            .onEnded { _ in
                if canDrag, let dragDraft { onCommit(dragDraft) }
                clearDrag()
            }
    }

    private func clamped(_ value: SignatureSettings, in size: CGSize) -> SignatureSettings {
        let rect = SignatureCompositor.rect(settings: value, photoSize: size,
                                            signatureSize: signatureSize)
        var result = value
        result.centerX = rect.midX / size.width
        result.centerY = rect.midY / size.height
        return result
    }

    private func clearDrag() {
        dragDraft = nil
        dragStart = nil
        dragPhotoSize = nil
    }

    private func renderPreview(_ request: RenderRequest) {
        do {
            if request.baked || !request.settings.enabled || request.signature == nil {
                renderedImage = request.base
            } else {
                // Only the display-sized CGImage is composited here. Moving a
                // signature neither reruns the engine nor writes the recipe.
                renderedImage = try SignatureCompositor.composite(request.base,
                    settings: request.settings, signature: request.signature)
            }
            renderedRequest = request
            onProblem(nil)
        } catch {
            renderedImage = request.base
            renderedRequest = request
            onProblem(L("Could not update the signature preview: \(error.localizedDescription)",
                        zh: "签名预览更新失败：\(error.localizedDescription)"))
        }
    }
}
