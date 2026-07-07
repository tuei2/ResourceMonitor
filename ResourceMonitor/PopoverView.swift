import SwiftUI
import AppKit

struct PopoverView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var settings: AppSettings
    @State private var timeRange: HistoryTimeRange = .fiveMin

    var body: some View {
        VStack(spacing: 0) {
            header
            // ── Global time-range toggle ──────────────────────────
            Picker("", selection: $timeRange) {
                ForEach(HistoryTimeRange.allCases) { r in
                    Text(r.rawValue).tag(r)
                }
            }   
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)
            .overlay(alignment: .bottom) { Divider().opacity(0.3) }

            ScrollView {
                if settings.popoverColumns == 2 {
                    HStack(alignment: .top, spacing: 8) {
                        VStack(spacing: 8) {
                            ForEach(settings.cards(inColumn: 0)) { card in
                                cardView(for: card)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        VStack(spacing: 8) {
                            ForEach(settings.cards(inColumn: 1)) { card in
                                cardView(for: card)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 14)
                } else {
                    VStack(spacing: 10) {
                        ForEach(settings.visibleCards) { card in
                            cardView(for: card)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 14)
                }
            }
        }
        .frame(width: settings.popoverColumns == 2 ? 580 : 320)
        .background(.ultraThinMaterial)
        .preferredColorScheme(colorScheme)
    }

    private var colorScheme: ColorScheme? {
        switch settings.theme {
        case .light:  return .light
        case .dark:   return .dark
        case .system: return nil
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "waveform.path.ecg")
                .foregroundStyle(.secondary)
                .font(.system(size: 13, weight: .medium))
            Text("Resource Monitor")
                .font(.system(size: 13, weight: .semibold))
            Spacer()
            Button {
                openSettingsWindow()
            } label: {
                Image(systemName: "gearshape.fill")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
                    .font(.system(size: 14))
            }
            .buttonStyle(.plain)
            Button {
                NSApp.terminate(nil)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
                    .font(.system(size: 15))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) { Divider().opacity(0.4) }
    }

    private func expand(_ card: PopoverCard) -> (() -> Void)? {
        settings.popoutsEnabled ? { openDetail(card) } : nil
    }

    @ViewBuilder
    private func cardView(for card: PopoverCard) -> some View {
        switch card {
        case .cpu:
            CPUCard(cpu: appState.cpu, processes: appState.processes,
                    timeRange: timeRange, onExpand: expand(.cpu))
        case .ram:
            RAMCard(ram: appState.ram, processes: appState.processes,
                    timeRange: timeRange, onExpand: expand(.ram))
        case .battery:
            BatteryCard(battery: appState.battery,
                        onExpand: expand(.battery))
        case .disk:
            DiskCard(disk: appState.disk, processes: appState.processes,
                     timeRange: timeRange, onExpand: expand(.disk))
        case .network:
            NetworkCard(network: appState.network, processes: appState.processes,
                        timeRange: timeRange, onExpand: expand(.network))
        case .gpu:
            GPUCard(gpu: appState.gpu,
                    timeRange: timeRange, onExpand: expand(.gpu))
        case .thermal:
            ThermalCard(thermal: appState.thermal,
                        onExpand: expand(.thermal))
        case .bluetooth:
            BluetoothCard(bluetooth: appState.bluetooth)
        }
    }
}

// MARK: - Detail windows

private func openDetail(_ card: PopoverCard) {
    let mgr = DetailWindowManager.shared
    let state = AppState.shared
    let settings = AppSettings.shared
    switch card {
    case .cpu:
        mgr.open(id: "cpu", title: "CPU", size: NSSize(width: 560, height: 620)) {
            CPUDetailView(cpu: state.cpu, processes: state.processes)
                .environmentObject(settings)
        }
    case .ram:
        mgr.open(id: "ram", title: "Memory") {
            RAMDetailView(ram: state.ram, processes: state.processes)
                .environmentObject(settings)
        }
    case .battery:
        mgr.open(id: "battery", title: "Battery") {
            BatteryDetailView(bat: state.battery)
                .environmentObject(settings)
        }
    case .network:
        mgr.open(id: "network", title: "Network") {
            NetworkDetailView(net: state.network)
                .environmentObject(settings)
        }
    case .gpu:
        mgr.open(id: "gpu", title: "GPU") {
            GPUDetailView(gpu: state.gpu)
                .environmentObject(settings)
        }
    case .thermal:
        mgr.open(id: "thermal", title: "Thermal & Fans") {
            ThermalDetailView(thermal: state.thermal)
                .environmentObject(settings)
        }
    case .disk:
        mgr.open(id: "disk", title: "Disk") {
            DiskDetailView(disk: state.disk)
                .environmentObject(settings)
        }
    case .bluetooth:
        break
    }
}

// MARK: - Settings window (singleton NSWindow)

private var settingsWindow: NSWindow?

func openSettingsWindow() {
    if let win = settingsWindow, win.isVisible {
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        return
    }

    let view = SettingsView()
        .environmentObject(AppSettings.shared)
        .environmentObject(AppState.shared)
        .localized()

    let vc = NSHostingController(rootView: view)
    let win = NSWindow(contentViewController: vc)
    win.title = "Resource Monitor — Settings"
    win.styleMask = [.titled, .closable, .miniaturizable]
    win.isReleasedWhenClosed = false
    win.center()
    win.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
    settingsWindow = win
}
