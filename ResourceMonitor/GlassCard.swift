import SwiftUI

struct GlassCard<Content: View>: View {
    let content: Content
    init(@ViewBuilder _ content: () -> Content) { self.content = content() }

    var body: some View {
        content
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [.white.opacity(0.25), .white.opacity(0.05)],
                                    startPoint: .topLeading, endPoint: .bottomTrailing),
                                lineWidth: 0.8)
                    }
            }
            .shadow(color: .black.opacity(0.08), radius: 6, y: 3)
    }
}

// MARK: - Hover card

/// NSViewRepresentable that reads its own screen frame via AppKit and reports the top Y.
private struct CardScreenFrameReader: NSViewRepresentable {
    let onScreenTopY: (CGFloat) -> Void

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            guard let window = nsView.window else { return }
            // Convert the view's bounds to window coordinates, then to screen coordinates.
            let windowRect = nsView.convert(nsView.bounds, to: nil)
            let screenRect = window.convertToScreen(windowRect)
            self.onScreenTopY(screenRect.maxY)   // maxY = top in screen coords (Y↑)
        }
    }
}

/// Wraps a card with hover → side-panel behavior.
/// `summary` shows in the popover grid; `detail` appears in the floating panel on hover.
/// Uses AppKit coordinate conversion to get the card's exact screen top Y.
struct HoverCard<Summary: View, Detail: View>: View {
    @ViewBuilder let summary: () -> Summary
    @ViewBuilder let detail: () -> Detail
    @State private var cardScreenTopY: CGFloat = 0

    var body: some View {
        summary()
            .contentShape(Rectangle())
            .background(CardScreenFrameReader { topY in
                cardScreenTopY = topY
            })
            .onHover { inside in
                if inside {
                    HoverDetailPanel.shared.show(SidePanelShell { detail() },
                                                 cardScreenTopY: cardScreenTopY)
                } else {
                    HoverDetailPanel.shared.scheduleHide()
                }
            }
    }
}

/// Visual chrome of the floating side panel.
/// Uses natural content height — no forced expansion — so the panel can size-to-fit.
struct SidePanelShell<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(
                        LinearGradient(colors: [.white.opacity(0.2), .white.opacity(0.04)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: 0.8)
            }
            .shadow(color: .black.opacity(0.22), radius: 18, y: 6)
    }
}

// MARK: - Expand button

struct CardExpandButton: View {
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
    }
}
