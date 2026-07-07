import AppKit
import SwiftUI
import Combine

// MARK: - Controller

final class MoodFaceController {
    static let shared = MoodFaceController()

    private var statusItem: NSStatusItem?
    private var popover:    NSPopover?
    private var timer:      Timer?
    private var cancellables = Set<AnyCancellable>()

    private init() {}

    func setup(appState: AppState, settings: AppSettings) {
        settings.$moodFaceEnabled
            .receive(on: DispatchQueue.main)
            .sink { [weak self] enabled in
                if enabled { self?.enable(appState: appState, settings: settings) }
                else       { self?.disable() }
            }
            .store(in: &cancellables)

        if settings.moodFaceEnabled {
            enable(appState: appState, settings: settings)
        }
    }

    private func enable(appState: AppState, settings: AppSettings) {
        guard statusItem == nil else { return }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let initRamPct = appState.ram.totalGB > 0 ? appState.ram.usedGB / appState.ram.totalGB * 100 : 0
        let initTemp   = appState.thermal.sensors.filter { $0.label.hasPrefix("CPU") }.map(\.celsius).max() ?? 0
        item.button?.title = MoodManager.shared.currentMood(cpu: appState.cpu.usage, ramPct: initRamPct,
                                                            battery: appState.battery, tempMax: initTemp,
                                                            settings: settings).emoji
        item.button?.font  = NSFont.systemFont(ofSize: 15)
        item.button?.action = #selector(togglePopover(_:))
        item.button?.target = self
        statusItem = item

        let pop = NSPopover()
        pop.contentSize   = CGSize(width: 300, height: 400)
        pop.behavior      = .transient
        pop.animates      = true
        pop.contentViewController = NSHostingController(
            rootView: MoodFaceCard(
                cpu:     appState.cpu,
                ram:     appState.ram,
                battery: appState.battery,
                thermal: appState.thermal
            )
            .localized()
        )
        popover = pop

        // Refresh emoji every 2 s
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self, weak appState] _ in
            guard let appState else { return }
            let settings = AppSettings.shared
            let ramPct = appState.ram.totalGB > 0 ? appState.ram.usedGB / appState.ram.totalGB * 100 : 0
            let tempMax = appState.thermal.sensors.filter { $0.label.hasPrefix("CPU") }.map(\.celsius).max() ?? 0
            let mood = MoodManager.shared.currentMood(cpu: appState.cpu.usage,
                                                      ramPct: ramPct,
                                                      battery: appState.battery,
                                                      tempMax: tempMax,
                                                      settings: settings)
            self?.statusItem?.button?.title = mood.emoji
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    private func disable() {
        timer?.invalidate(); timer = nil
        popover?.close(); popover = nil
        if let item = statusItem { NSStatusBar.system.removeStatusItem(item) }
        statusItem = nil
    }

    @objc private func togglePopover(_ sender: NSStatusBarButton) {
        guard let pop = popover, let button = statusItem?.button else { return }
        if pop.isShown {
            pop.performClose(nil)
        } else {
            pop.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

// MARK: - Card view

struct MoodFaceCard: View {
    @ObservedObject var cpu:     CPUMonitor
    @ObservedObject var ram:     RAMMonitor
    @ObservedObject var battery: BatteryMonitor
    @ObservedObject var thermal: ThermalMonitor

    private var settings: AppSettings { AppSettings.shared }

    private var mood: Mood {
        MoodManager.shared.currentMood(cpu: cpu.usage,
                                       ramPct: ram.totalGB > 0 ? ram.usedGB / ram.totalGB * 100 : 0,
                                       battery: battery,
                                       tempMax: tempMax,
                                       settings: settings)
    }
    private var ramPct: Double { ram.totalGB > 0 ? ram.usedGB / ram.totalGB * 100 : 0 }
    private var tempMax: Double {
        thermal.sensors.filter { $0.label.hasPrefix("CPU") }.map(\.celsius).max() ?? 0
    }

    var body: some View {
        VStack(spacing: 0) {
            // ── Header ──────────────────────────────────────────────────────
            VStack(spacing: 6) {
                Text(mood.emoji)
                    .font(.system(size: 52))
                    .shadow(color: .black.opacity(0.15), radius: 4, y: 2)

                Text(mood.title.uppercased())
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(2)
                    .foregroundStyle(.secondary)

                Text(mood.headline)
                    .font(.system(size: 14, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .padding(.horizontal, 16)
            .background(.ultraThinMaterial)

            Divider()

            // ── Diagnosis ───────────────────────────────────────────────────
            VStack(alignment: .leading, spacing: 12) {
                    Text(mood.diagnosis)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    // Relevant stats
                    HStack(spacing: 8) {
                        StatChip(label: "CPU",  value: String(format: "%.0f%%", cpu.usage))
                        StatChip(label: "RAM",  value: String(format: "%.0f%%", ramPct))
                        StatChip(label: "Batt", value: "\(battery.percent)%")
                        if tempMax > 0 {
                            StatChip(label: "Temp", value: String(format: "%.0f°", tempMax))
                        }
                    }

                    Divider().opacity(0.4)

                    // Prescription
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "pills.fill")
                            .foregroundStyle(.blue)
                            .font(.system(size: 12))
                        Text(mood.prescription)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
            }
            .padding(14)
        }
        .frame(width: 300)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct StatChip: View {
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 1) {
            Text(value)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 5)
        .background(.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 7))
    }
}
