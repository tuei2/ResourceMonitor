import SwiftUI
import AppKit

extension Notification.Name {
    static let closePopoverForDetail = Notification.Name("closePopoverForDetail")
    static let detailWindowClosed    = Notification.Name("detailWindowClosed")
}

// MARK: - Window manager

final class DetailWindowManager {
    static let shared = DetailWindowManager()
    private var windows: [String: NSPanel] = [:]

    var hasOpenWindows: Bool { !windows.isEmpty }

    func open<V: View>(id: String, title: String,
                       size: NSSize = NSSize(width: 420, height: 500),
                       @ViewBuilder content: () -> V) {
        // Close the popover first so the panel comes to the front
        NotificationCenter.default.post(name: .closePopoverForDetail, object: nil)

        if let existing = windows[id] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                existing.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
            }
            return
        }
        let vc = NSHostingController(rootView: content())
        let panel = NSPanel(contentViewController: vc)
        panel.title = title
        panel.styleMask = [.titled, .closable, .utilityWindow]
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = false
        panel.isReleasedWhenClosed = false
        panel.contentMinSize = NSSize(width: 380, height: 320)
        panel.setContentSize(size)
        panel.center()
        windows[id] = panel

        // Restore full rate now that a detail window is open
        AppState.shared.startAll()

        // Remove from dict when closed; throttle if nothing else is open
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: panel, queue: .main) { [weak self] _ in
            self?.windows.removeValue(forKey: id)
            NotificationCenter.default.post(name: .detailWindowClosed, object: nil)
        }

        // Show after popover has had time to dismiss
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            panel.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

// MARK: - Shared components

struct DetailHeader: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let color: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 16, weight: .bold))
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct DetailSparkline: View {
    let values: [Double]
    let color: Color
    var maxValue: Double = 100
    var label: String = ""
    var secondaryValues: [Double] = []
    var secondaryColor: Color = .clear

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if !label.isEmpty {
                Text(label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            ZStack {
                if !secondaryValues.isEmpty {
                    SparklineView(values: secondaryValues, color: secondaryColor,
                                  maxValue: maxValue)
                }
                SparklineView(values: values, color: color, maxValue: maxValue)
            }
            .frame(height: 80)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }
}

struct StatGrid: View {
    let items: [(label: String, value: String, color: Color?)]
    var columns: Int = 3

    private var gridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible()), count: columns)
    }

    var body: some View {
        LazyVGrid(columns: gridColumns, spacing: 8) {
            ForEach(items, id: \.label) { item in
                VStack(spacing: 2) {
                    Text(item.value)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(item.color.map { AnyShapeStyle($0) }
                                         ?? AnyShapeStyle(.primary))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(item.label)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }
}

// MARK: - CPU detail

struct CPUDetailView: View {
    @ObservedObject var cpu: CPUMonitor
    @ObservedObject var processes: ProcessMonitor
    @State private var timeRange: HistoryTimeRange = .fiveMin

    var body: some View {
        VStack(spacing: 0) {
            // ── Time range toggle ──────────────────────────────────
            Picker("Time range", selection: $timeRange) {
                ForEach(HistoryTimeRange.allCases) { r in
                    Text(r.rawValue).tag(r)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 12)

            Divider().opacity(0.3)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {

                    // ── Header stats ───────────────────────────────
                    HStack(alignment: .center, spacing: 0) {
                        DetailHeader(
                            title: "CPU",
                            subtitle: String(format: "%.1f%% · %d cores",
                                             cpu.usage, cpu.coreUsages.count),
                            systemImage: "cpu",
                            color: .blue)
                        Spacer()
                        StatPill(label: "Peak",
                                 value: String(format: "%.0f%%", totalHistory.max() ?? 0))
                        StatPill(label: "Avg",
                                 value: String(format: "%.0f%%", average(totalHistory)))
                    }

                    // ── Overall sparkline ──────────────────────────
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Total usage")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                        SparklineView(values: totalHistory, color: .blue)
                            .frame(height: 64)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        TimeAxisLabels(range: timeRange)
                    }

                    // ── Per-core sparklines ────────────────────────
                    if !cpu.coreUsages.isEmpty {
                        Text("Per core")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)

                        CoreHistoryGrid(
                            coreHistories: coreHistories,
                            coreUsages: cpu.coreUsages)
                    }

                    // ── Top processes ──────────────────────────────
                    if !processes.topCPU.isEmpty {
                        Text("Active processes")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                        ProcessDetailTable(
                            processes: processes.topCPU,
                            valueLabel: { String(format: "%.1f%%", $0.cpuPercent) },
                            barValue: { $0.cpuPercent },
                            maxValue: processes.topCPU.first?.cpuPercent ?? 1,
                            color: .blue)
                    }
                }
                .padding(20)
            }
        }
        .frame(minWidth: 480)
    }

    // ── History selection ──────────────────────────────────────────
    private var totalHistory: [Double] {
        switch timeRange {
        case .fiveMin: return cpu.coreHistoryShort.first ?? cpu.history
        case .hour:    return cpu.coreHistoryHour.first  ?? []
        case .day:     return cpu.coreHistoryDay.first   ?? []
        case .week:    return cpu.coreHistoryWeek.first  ?? []
        }
    }

    // Per-core histories (indices 1..) — returns [[Double]] of core count
    private var coreHistories: [[Double]] {
        let buf: [[Double]]
        switch timeRange {
        case .fiveMin: buf = cpu.coreHistoryShort
        case .hour:    buf = cpu.coreHistoryHour
        case .day:     buf = cpu.coreHistoryDay
        case .week:    buf = cpu.coreHistoryWeek
        }
        guard buf.count > 1 else { return [] }
        return Array(buf.dropFirst())   // drop slot 0 (total)
    }
}

// MARK: - Supporting sub-views

private struct StatPill: View {
    let label: String
    let value: String
    var body: some View {
        VStack(spacing: 1) {
            Text(value)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.tertiary)
        }
        .frame(width: 52)
        .padding(.vertical, 6)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct TimeAxisLabels: View {
    let range: HistoryTimeRange
    var body: some View {
        HStack {
            Text(leftLabel)
            Spacer()
            Text("now")
        }
        .font(.system(size: 9))
        .foregroundStyle(.tertiary)
    }
    private var leftLabel: String {
        switch range {
        case .fiveMin: return "−5 min"
        case .hour:    return "−1 uur"
        case .day:     return "−24 uur"
        case .week:    return "−7 dagen"
        }
    }
}

private struct CoreHistoryGrid: View {
    let coreHistories: [[Double]]
    let coreUsages: [Double]

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 2)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(Array(coreHistories.enumerated()), id: \.offset) { idx, hist in
                CoreHistoryCell(
                    coreIndex: idx,
                    history: hist,
                    currentUsage: idx < coreUsages.count ? coreUsages[idx] : 0)
            }
        }
    }
}

private struct CoreHistoryCell: View {
    let coreIndex: Int
    let history: [Double]
    let currentUsage: Double

    private var coreColor: Color { coreIndex < 6 ? .blue : .teal }
    private var coreLabel: String {
        coreIndex < 6
            ? "P-Core \(coreIndex + 1)"
            : "E-Core \(coreIndex - 5)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text(coreLabel)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(String(format: "%.0f%%", currentUsage))
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(coreColor)
                    .contentTransition(.numericText())
            }
            SparklineView(values: history, color: coreColor, maxValue: 100)
                .frame(height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .padding(10)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - RAM detail

struct RAMDetailView: View {
    @ObservedObject var ram: RAMMonitor
    @ObservedObject var processes: ProcessMonitor

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                DetailHeader(title: "Memory",
                             subtitle: String(format: "%.1f GB used of %.0f GB",
                                              ram.usedGB, ram.totalGB),
                             systemImage: "memorychip",
                             color: .purple)

                DetailSparkline(values: ram.history, color: .purple,
                                label: "Last \(historyMinutes) minutes")

                StatGrid(items: [
                    ("Used", String(format: "%.1f GB", ram.usedGB), .purple),
                    ("Wired", String(format: "%.1f GB", ram.wiredGB), .red),
                    ("Compressed", String(format: "%.1f GB", ram.compressedGB), .orange),
                    ("Active", String(format: "%.1f GB", ram.activeGB), .purple),
                    ("Free", String(format: "%.1f GB",
                                   max(0, ram.totalGB - ram.wiredGB - ram.activeGB - ram.compressedGB)), .green),
                    ("Pressure", pressureLabel, pressureColor),
                ])

                if !processes.topRAM.isEmpty {
                    Text("Top Processes")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    ProcessDetailTable(processes: processes.topRAM,
                                       valueLabel: { formatMB($0.ramMB) },
                                       barValue: { $0.ramMB },
                                       maxValue: processes.topRAM.first?.ramMB ?? 1,
                                       color: .purple)
                }
            }
            .padding(20)
        }
    }

    private var pressureLabel: String {
        switch ram.pressureLevel {
        case 2: return "Critical"
        case 1: return "Warning"
        default: return "Normal"
        }
    }
    private var pressureColor: Color {
        switch ram.pressureLevel {
        case 2: return .red
        case 1: return .orange
        default: return .green
        }
    }
    private func formatMB(_ mb: Double) -> String {
        mb >= 1024 ? String(format: "%.1f GB", mb / 1024) : String(format: "%.0f MB", mb)
    }
}

// MARK: - Battery detail

struct BatteryDetailView: View {
    @ObservedObject var bat: BatteryMonitor

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                let color: Color = bat.isCharging ? .green : bat.percent < 20 ? .red : .teal
                DetailHeader(title: "Battery",
                             subtitle: bat.isCharging ? "Charging" : "On Battery",
                             systemImage: bat.isCharging ? "battery.100percent.bolt" : "battery.75percent",
                             color: color)

                StatGrid(items: [
                    ("Charge", "\(bat.percent)%", color),
                    ("Health", "\(bat.health)%", healthColor),
                    ("Condition", bat.condition, healthColor),
                    ("Power", String(format: "%.1f W", abs(bat.powerWatts)),
                     bat.isCharging ? .green : .orange),
                    ("Adapter", bat.adapterWatts > 0 ? "\(bat.adapterWatts) W" : "—", nil),
                    ("Time", timeString ?? "—", nil),
                ], columns: 3)

                if !bat.chargerName.isEmpty {
                    HStack {
                        Image(systemName: "powerplug.fill")
                            .foregroundStyle(.secondary)
                        Text(bat.chargerName)
                            .font(.system(size: 13))
                        Spacer()
                        if bat.adapterWatts > 0 {
                            Text("\(bat.adapterWatts) W")
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundStyle(.green)
                        }
                    }
                    .padding(12)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
                }
            }
            .padding(20)
        }
    }

    private var healthColor: Color {
        switch bat.health {
        case 85...: return .green
        case 70..<85: return .orange
        default: return .red
        }
    }

    private var timeString: String? {
        let min = bat.isCharging ? bat.timeToFullMin : bat.timeToEmptyMin
        guard min > 0 else { return nil }
        return min >= 60 ? "\(min/60)h \(min%60)m" : "\(min)m"
    }
}

// MARK: - Network detail

struct NetworkDetailView: View {
    @ObservedObject var net: NetworkMonitor

    private var maxScale: Double {
        max(net.downloadHistory.max() ?? 1, net.uploadHistory.max() ?? 1, 0.1)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                DetailHeader(title: "Network",
                             subtitle: net.activeInterface.isEmpty ? "All interfaces" : net.activeInterface,
                             systemImage: "network",
                             color: .cyan)

                DetailSparkline(values: net.downloadHistory, color: .cyan,
                                maxValue: maxScale,
                                label: "Download / Upload — last \(historyMinutes) min",
                                secondaryValues: net.uploadHistory,
                                secondaryColor: .indigo.opacity(0.7))

                StatGrid(items: [
                    ("Download", formatMBps(net.downloadMBps), .cyan),
                    ("Upload", formatMBps(net.uploadMBps), .indigo),
                    ("Interface", net.activeInterface.isEmpty ? "—" : net.activeInterface, nil),
                    ("Today ↓", formatGB(net.todayDownloadGB), nil),
                    ("Today ↑", formatGB(net.todayUploadGB), nil),
                    ("7d Total", formatGB(net.sevenDayDownloadGB + net.sevenDayUploadGB), nil),
                ])
            }
            .padding(20)
        }
    }

    private func formatMBps(_ mb: Double) -> String {
        if mb >= 1000 { return String(format: "%.2f GB/s", mb / 1024) }
        if mb >= 1    { return String(format: "%.1f MB/s", mb) }
        return String(format: "%.0f KB/s", mb * 1024)
    }
    private func formatGB(_ gb: Double) -> String {
        gb >= 1 ? String(format: "%.1f GB", gb) : String(format: "%.0f MB", gb * 1024)
    }
}

// MARK: - GPU detail

struct GPUDetailView: View {
    @ObservedObject var gpu: GPUMonitor

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                DetailHeader(title: "GPU",
                             subtitle: String(format: "%.0f%% utilization", gpu.utilizationPercent),
                             systemImage: "display",
                             color: .pink)

                DetailSparkline(values: gpu.history, color: .pink,
                                label: "Last \(historyMinutes) minutes")

                StatGrid(items: [
                    ("GPU", String(format: "%.0f%%", gpu.utilizationPercent), .pink),
                    ("Renderer", String(format: "%.0f%%", gpu.rendererPercent), nil),
                    ("Tiler", String(format: "%.0f%%", gpu.tilerPercent), nil),
                    ("VRAM Used", String(format: "%.0f MB", gpu.usedMemoryMB), nil),
                    ("VRAM Total", gpu.totalMemoryMB > 0
                        ? String(format: "%.0f MB", gpu.totalMemoryMB) : "Shared", nil),
                    ("Peak", String(format: "%.0f%%", gpu.history.max() ?? 0), nil),
                ])
            }
            .padding(20)
        }
    }
}

// MARK: - Thermal detail

struct ThermalDetailView: View {
    @ObservedObject var thermal: ThermalMonitor

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                let maxTemp = thermal.sensors.map(\.celsius).max() ?? 0
                let color: Color = maxTemp >= 80 ? .red : maxTemp >= 60 ? .orange : .mint
                DetailHeader(title: "Temperature & Fans",
                             subtitle: "Thermal state: \(thermal.thermalState)",
                             systemImage: "thermometer.medium",
                             color: color)

                if !thermal.sensors.isEmpty {
                    Text("Sensors")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)

                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2),
                              spacing: 6) {
                        ForEach(thermal.sensors) { sensor in
                            HStack {
                                Text(sensor.label)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                Spacer()
                                Text(String(format: "%.0f°C", sensor.celsius))
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                                    .foregroundStyle(tempColor(sensor.celsius))
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.quaternary.opacity(0.5),
                                        in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }

                if !thermal.fans.isEmpty {
                    HStack {
                        Text("Fans")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                        if !thermal.fanControlAvailable {
                            Text("read-only")
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                                .padding(.leading, 4)
                        }
                        Spacer()
                        if thermal.fanManualMask != 0 {
                            Button("Reset all to auto") { thermal.setAllFansAuto() }
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.orange)
                                .buttonStyle(.plain)
                        }
                    }

                    ForEach(thermal.fans) { fan in
                        DetailFanRow(fan: fan, thermal: thermal)
                    }
                }
            }
            .padding(20)
        }
    }

    private func tempColor(_ c: Double) -> Color {
        c >= 80 ? .red : c >= 60 ? .orange : .primary
    }
}

// MARK: - Shared sub-views

private struct ProcessDetailTable: View {
    let processes: [ProcessStat]
    let valueLabel: (ProcessStat) -> String
    let barValue: (ProcessStat) -> Double
    let maxValue: Double
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            ForEach(processes.prefix(10)) { proc in
                HStack(spacing: 8) {
                    Text(proc.name)
                        .font(.system(size: 12))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(color.opacity(0.1))
                            RoundedRectangle(cornerRadius: 3)
                                .fill(color.opacity(0.55))
                                .frame(width: geo.size.width * CGFloat(barValue(proc) / max(maxValue, 0.01)))
                        }
                    }
                    .frame(height: 5)

                    Text(valueLabel(proc))
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(color)
                        .frame(width: 56, alignment: .trailing)
                }
            }
        }
    }
}

// MARK: - Disk detail

struct DiskDetailView: View {
    @ObservedObject var disk: DiskMonitor

    private var primary: DiskVolume? { disk.volumes.first }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                DetailHeader(title: "Disk",
                             subtitle: primary.map { String(format: "%.0f%% used", $0.percent) } ?? "—",
                             systemImage: "internaldrive",
                             color: .brown)

                let readMax = max(disk.readHistory.max() ?? 1, disk.writeHistory.max() ?? 1, 0.1)
                DetailSparkline(values: disk.readHistory, color: .brown,
                                maxValue: readMax,
                                label: "Read / Write — last \(historyMinutes) min",
                                secondaryValues: disk.writeHistory,
                                secondaryColor: .orange.opacity(0.7))

                if let vol = primary {
                    StatGrid(items: [
                        ("Used", formatGB(vol.usedGB), .brown),
                        ("Free", formatGB(vol.freeGB), .green),
                        ("Total", formatGB(vol.totalGB), nil),
                        ("Read", formatMBps(disk.readMBps), .brown),
                        ("Write", formatMBps(disk.writeMBps), .orange),
                        ("Usage", String(format: "%.0f%%", vol.percent), nil),
                    ])
                }

                if disk.volumes.count > 1 {
                    Text("Volumes")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    ForEach(disk.volumes) { vol in
                        HStack {
                            Image(systemName: "internaldrive")
                                .foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(vol.name).font(.system(size: 12))
                                Text(vol.id).font(.system(size: 10)).foregroundStyle(.tertiary)
                            }
                            Spacer()
                            Text("\(formatGB(vol.usedGB)) / \(formatGB(vol.totalGB))")
                                .font(.system(size: 11, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
            .padding(20)
        }
    }

    private func formatGB(_ gb: Double) -> String {
        gb >= 1 ? String(format: "%.0f GB", gb) : String(format: "%.0f MB", gb * 1024)
    }
    private func formatMBps(_ mb: Double) -> String {
        mb >= 1 ? String(format: "%.1f MB/s", mb) : String(format: "%.0f KB/s", mb * 1024)
    }
}

// MARK: - Fan control row (used in ThermalDetailView)

private struct DetailFanRow: View {
    let fan: FanInfo
    @ObservedObject var thermal: ThermalMonitor

    private var isManual: Bool { thermal.fanManualMask & (1 << fan.id) != 0 }
    private var targetRPM: Double { thermal.fanTargetRPMs[fan.id] ?? fan.minRPM }

    @State private var sliderValue: Double = 0

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: "fan")
                    .foregroundStyle(isManual ? .orange : .secondary)
                    .font(.system(size: 14))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Fan \(fan.id + 1)")
                        .font(.system(size: 13))
                    Text(fan.rpm > 0 ? String(format: "%.0f RPM (%.0f%%)", fan.rpm, min(fan.percent, 100)) : "Off")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("Manual", isOn: Binding(
                    get: { isManual },
                    set: { manual in
                        if manual { thermal.setFanManual(fan.id, rpm: sliderValue) }
                        else       { thermal.setFanAuto(fan.id) }
                    }))
                .toggleStyle(.switch)
                .controlSize(.small)
                .font(.system(size: 11))
            }

            if !thermal.fanControlAvailable && isManual == false {
                Text("Fan control requires SIP to be disabled or a privileged helper.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            } else if isManual {
                VStack(spacing: 6) {
                    Slider(value: $sliderValue,
                           in: fan.minRPM...max(fan.maxRPM, fan.minRPM + 1),
                           step: 50) { _ in
                        thermal.setFanManual(fan.id, rpm: sliderValue)
                    }
                    .tint(.orange)
                    HStack {
                        Text(String(format: "%.0f RPM", fan.minRPM))
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                        Spacer()
                        Text(String(format: "Target: %.0f RPM", sliderValue))
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(.orange)
                        Spacer()
                        Text(String(format: "%.0f RPM", fan.maxRPM))
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.horizontal, 4)
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
        .onAppear { sliderValue = isManual ? targetRPM : fan.minRPM }
        .onChange(of: isManual) { manual in
            if !manual { sliderValue = fan.minRPM }
        }
    }
}

// MARK: - Helpers

private var historyMinutes: String {
    let rate = AppSettings.shared.refreshRate.rawValue
    let minutes = Int((120 * rate / 60).rounded())
    return "\(max(1, minutes))"
}

private func average(_ values: [Double]) -> Double {
    let nonZero = values.filter { $0 > 0 }
    guard !nonZero.isEmpty else { return 0 }
    return nonZero.reduce(0, +) / Double(nonZero.count)
}
