import SwiftUI
import AppKit
import Combine

@main
struct ResourceMonitorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private let appState = AppState.shared
    private let settings = AppSettings.shared
    private var cancellables = Set<AnyCancellable>()
    private var globalKeyMonitor: Any?
    private var outsideClickMonitor: Any?
    private var menubarTimer: Timer?

    func applicationWillTerminate(_ notification: Notification) {
        appState.thermal.setAllFansAuto()
        NSApp.removeObserver(self, forKeyPath: "effectiveAppearance")
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        // Apply the saved language before any view is built.
        LocalizationManager.shared.apply(settings.language)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        popover = NSPopover()
        popover.contentSize = contentSize
        popover.behavior = .transient
        popover.animates = true
        // Set correct appearance immediately, then keep in sync via KVO.
        // Must happen after popover is created — .initial would fire observeValue
        // before the popover exists and crash on the implicit unwrap.
        popover.appearance = NSApp.effectiveAppearance
        NSApp.addObserver(self, forKeyPath: "effectiveAppearance",
                          options: [.new], context: nil)

        let root = PopoverView()
            .environmentObject(appState)
            .environmentObject(settings)
            .localized()
        let vc = NSHostingController(rootView: root)
        vc.view.wantsLayer = true
        popover.contentViewController = vc

        if let button = statusItem.button {
            button.action = #selector(togglePopover)
            button.target = self
        }

        appState.startAll()
        setupMenubarUpdates()
        AlertMonitor.shared.requestAuthorization()
        MoodFaceController.shared.setup(appState: appState, settings: settings)
        setupGlobalHotkey()

        if settings.autoUpdateCheck {
            UpdateChecker.shared.checkInBackgroundIfDue()
        }

        settings.$globalHotkeyEnabled
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.setupGlobalHotkey() }
            .store(in: &cancellables)

        // Width changes with column count; height is user-configured in Settings
        settings.$popoverColumns
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.applyContentSize() }
            .store(in: &cancellables)
        settings.$popoverHeight
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.applyContentSize() }
            .store(in: &cancellables)

        NotificationCenter.default.addObserver(self, selector: #selector(closePopoverForDetail),
                                               name: .closePopoverForDetail, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(onDetailWindowClosed),
                                               name: .detailWindowClosed, object: nil)

        statusItem.button?.image = NSImage(systemSymbolName: "waveform.path.ecg",
                                            accessibilityDescription: "Resource Monitor")
        statusItem.button?.image?.isTemplate = true
    }

    // MARK: - Appearance sync

    override func observeValue(forKeyPath keyPath: String?, of object: Any?,
                               change: [NSKeyValueChangeKey: Any]?,
                               context: UnsafeMutableRawPointer?) {
        if keyPath == "effectiveAppearance" {
            popover.appearance = NSApp.effectiveAppearance
        } else {
            super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
        }
    }

    // MARK: - Content size

    private var contentSize: NSSize {
        NSSize(width: settings.popoverColumns == 2 ? 580 : 320,
               height: settings.popoverHeight)
    }

    private func applyContentSize() {
        popover.contentSize = contentSize
    }

    // MARK: - Menubar

    private func setupMenubarUpdates() {
        menubarTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.updateMenuBar()
            AlertMonitor.shared.check(appState: self.appState)
        }
        RunLoop.main.add(menubarTimer!, forMode: .common)

        settings.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateMenuBar() }
            .store(in: &cancellables)
    }

    private func updateMenuBar() {
        let attrStr = MenubarRenderer.render(state: appState, settings: settings)
        guard let button = statusItem.button else { return }
        button.image = nil
        button.attributedTitle = attrStr
    }

    // MARK: - Popover

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            closePopover()
        } else {
            appState.startAll()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
            // Pass the popover's window to the side detail panel for positioning.
            DispatchQueue.main.async {
                HoverDetailPanel.shared.sourceWindow =
                    self.popover.contentViewController?.view.window
            }
            outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
                matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
            ) { [weak self] _ in
                self?.closePopover()
            }
        }
    }

    private func closePopover() {
        HoverDetailPanel.shared.hideNow()
        popover.performClose(nil)
        if let m = outsideClickMonitor { NSEvent.removeMonitor(m); outsideClickMonitor = nil }
        scheduleAdaptiveRate()
    }

    private func scheduleAdaptiveRate() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self else { return }
            guard !self.popover.isShown,
                  !DetailWindowManager.shared.hasOpenWindows else { return }
            self.appState.startAllBackground()
        }
    }

    @objc private func closePopoverForDetail() {
        if popover.isShown { popover.performClose(nil) }
    }

    @objc private func onDetailWindowClosed() {
        scheduleAdaptiveRate()
    }

    // MARK: - Global hotkey (⌥Space)

    private func setupGlobalHotkey() {
        if let existing = globalKeyMonitor {
            NSEvent.removeMonitor(existing)
            globalKeyMonitor = nil
        }
        guard settings.globalHotkeyEnabled else { return }
        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 49,
                  event.modifierFlags.intersection([.option, .command, .shift, .control]) == .option
            else { return }
            DispatchQueue.main.async { self?.togglePopover() }
        }
    }
}
