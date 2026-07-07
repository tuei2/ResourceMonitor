import AppKit
import SwiftUI

/// Manages a floating side panel that appears when hovering over a dashboard card.
/// The panel positions itself to the right (or left) of the main popover window,
/// vertically aligned to the card being hovered.
final class HoverDetailPanel {
    static let shared = HoverDetailPanel()
    private init() {}

    private var panel: NSPanel?
    private var exitPollTimer: Timer?
    private var hideWorkItem: DispatchWorkItem?
    /// Screen Y of the hovered card's top edge (NSScreen coords: origin bottom-left, Y↑).
    private var cardScreenTopY: CGFloat = 0
    /// Set by AppDelegate each time the main popover opens.
    weak var sourceWindow: NSWindow?

    // MARK: - Public API

    /// `cardScreenTopY` is the card's top edge in screen coordinates (AppKit, Y increases upward).
    func show<V: View>(_ view: V, cardScreenTopY: CGFloat) {
        // Cancel any pending hide
        hideWorkItem?.cancel()
        hideWorkItem = nil
        exitPollTimer?.invalidate()
        exitPollTimer = nil

        self.cardScreenTopY = cardScreenTopY

        let p = panel ?? buildPanel()
        panel = p

        // Replace content with fresh hosting controller so SwiftUI update cycle starts clean.
        // Inject shared singletons so @EnvironmentObject lookups inside detail views succeed.
        let root = AnyView(view
            .environmentObject(AppSettings.shared)
            .environmentObject(AppState.shared)
            .localized())
        let vc = NSHostingController(rootView: root)
        vc.view.wantsLayer = true
        vc.sizingOptions = [.intrinsicContentSize]
        p.contentViewController = vc

        // Show at a generous height first so SwiftUI can do a real layout pass,
        // then resize to the actual content height on the next run-loop tick.
        positionAndSizePanel(p, measuredHeight: nil)
        if !p.isVisible { p.orderFront(nil) }

        // After SwiftUI has rendered once, shrink to fit.
        DispatchQueue.main.async { [weak self, weak p] in
            guard let self, let p else { return }
            self.positionAndSizePanel(p, measuredHeight: self.measureContentHeight(p))
        }
    }

    /// Called when the mouse leaves a card.
    /// Uses a longer delay (200ms) to avoid flicker when approaching from screen edges,
    /// then checks whether the mouse moved into the panel before hiding.
    func scheduleHide() {
        let item = DispatchWorkItem { [weak self] in
            guard let self, let p = self.panel, p.isVisible else { return }
            if p.frame.contains(NSEvent.mouseLocation) {
                self.startExitPoll()
            } else {
                p.orderOut(nil)
            }
        }
        hideWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.20, execute: item)
    }

    func hideNow() {
        hideWorkItem?.cancel()
        hideWorkItem = nil
        exitPollTimer?.invalidate()
        exitPollTimer = nil
        panel?.orderOut(nil)
    }

    // MARK: - Private helpers

    private func buildPanel() -> NSPanel {
        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 500),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.level = .popUpMenu
        p.isReleasedWhenClosed = false
        p.hasShadow = true
        p.collectionBehavior = [.canJoinAllSpaces, .ignoresCycle]
        return p
    }

    private func measureContentHeight(_ panel: NSPanel) -> CGFloat? {
        guard let vc = panel.contentViewController else { return nil }
        vc.view.layoutSubtreeIfNeeded()
        // With sizingOptions = .intrinsicContentSize the hosting view reports the
        // SwiftUI content's ideal height here once the first layout pass is done.
        let intrinsic = vc.view.intrinsicContentSize.height
        return intrinsic > 20 ? intrinsic : nil
    }

    private func positionAndSizePanel(_ panel: NSPanel, measuredHeight: CGFloat?) {
        guard let src = sourceWindow else { return }
        let sf = src.frame
        let w: CGFloat = 300
        let screen = NSScreen.screens.first { $0.frame.contains(sf.origin) } ?? NSScreen.main!
        let visibleFrame = screen.visibleFrame
        let maxAvailableH = visibleFrame.height - 20

        let h: CGFloat
        if let measured = measuredHeight {
            h = min(measured + 4, maxAvailableH)
        } else {
            // First pass: generous height so SwiftUI has room to lay out.
            h = min(600, maxAvailableH)
        }
        panel.setContentSize(NSSize(width: w, height: h))

        // Prefer right side of the popover; fall back to left if off-screen.
        let rightX = sf.maxX + 8
        let x = rightX + w <= visibleFrame.maxX ? rightX : sf.minX - w - 8

        let panelH = panel.frame.height
        let idealY = cardScreenTopY - panelH
        let y = max(visibleFrame.minY + 8, min(idealY, visibleFrame.maxY - panelH - 8))

        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    /// Poll at 80 ms intervals; close the panel when the mouse leaves its frame.
    private func startExitPoll() {
        exitPollTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] timer in
            guard let self, let p = self.panel, p.isVisible else { timer.invalidate(); return }
            if !p.frame.contains(NSEvent.mouseLocation) {
                timer.invalidate()
                p.orderOut(nil)
            }
        }
    }
}
