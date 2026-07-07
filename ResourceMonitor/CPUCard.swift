import SwiftUI

struct CPUCard: View {
    @ObservedObject var cpu: CPUMonitor
    @ObservedObject var processes: ProcessMonitor
    @EnvironmentObject var settings: AppSettings
    var timeRange: HistoryTimeRange = .fiveMin
    var onExpand: (() -> Void)? = nil
    private var cfg: CardConfig { settings.config(for: .cpu) }
    private var baseAccent: Color {
        guard let h = settings.config(for: .cpu).accentHex,
              let rgb = UInt64(h.hasPrefix("#") ? String(h.dropFirst()) : h, radix: 16)
        else { return .blue }
        return Color(red: Double((rgb >> 16) & 0xFF) / 255,
                     green: Double((rgb >> 8) & 0xFF) / 255,
                     blue: Double(rgb & 0xFF) / 255)
    }
    private var accent: Color {
        settings.thresholdColor(value: cpu.usage, threshold: settings.cpuAlertThreshold, accent: baseAccent)
    }

    var body: some View {
        HoverCard {
            GlassCard {
                switch cfg.layoutMode {
                case .ring:    ringLayout
                case .compact: compactLayout
                default:       standardLayout
                }
            }
        } detail: {
            CPUDetailPanelView(cpu: cpu, processes: processes, accent: accent)
        }
    }

    // MARK: - Standard layout

    private var standardLayout: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Label("CPU", systemImage: "cpu")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                        if let onExpand { CardExpandButton(action: onExpand) }
                    }
                    Text(String(format: "%.1f%%", cpu.usage))
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(accent)
                        .contentTransition(.numericText())
                }
                Spacer()
                RingGauge(value: cpu.usage, color: accent)
                    .frame(width: 44, height: 44)
            }

            if cfg.shows("sparkline") {
                SparklineView(values: overallHistory, color: accent)
                    .frame(height: 36)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            if cfg.shows("loadavg") {
                HStack(spacing: 0) {
                    CPUInfoItem(label: "Uptime", value: cpu.uptime)
                    CPUInfoItem(label: "Load 1m",  value: String(format: "%.2f", cpu.loadAvg1))
                    CPUInfoItem(label: "Load 5m",  value: String(format: "%.2f", cpu.loadAvg5))
                    CPUInfoItem(label: "Load 15m", value: String(format: "%.2f", cpu.loadAvg15))
                }
            }

            if cfg.shows("clusters") && cpu.pCoreCount > 0 && cpu.eCoreCount > 0 {
                ClusterRow(pUsage: cpu.pCoreUsage, eUsage: cpu.eCoreUsage, accent: accent)
            }

            if cfg.shows("userload") {
                UserLoadRow(user: cpu.userPercent, system: cpu.systemPercent,
                            idle: cpu.idlePercent, accent: accent)
            }

            if cfg.shows("percore") && !cpu.coreUsages.isEmpty {
                PopoverCoreGrid(coreHistories: coreHistories, coreUsages: cpu.coreUsages,
                                accentColor: accent)
            }
        }
    }

    // MARK: - Compact layout

    private var compactLayout: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Label("CPU", systemImage: "cpu")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(String(format: "%.1f%%", cpu.usage))
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(accent)
                    .contentTransition(.numericText())
            }
            Spacer()
            RingGauge(value: cpu.usage, color: accent)
                .frame(width: 34, height: 34)
            if let onExpand { CardExpandButton(action: onExpand) }
        }
    }

    // MARK: - Ring layout

    private var ringLayout: some View {
        VStack(spacing: 8) {
            HStack {
                Label("CPU", systemImage: "cpu")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                if let onExpand { CardExpandButton(action: onExpand) }
            }
            ZStack {
                RingGauge(value: cpu.usage, color: accent, label: "")
                    .frame(width: 90, height: 90)
                Text(String(format: "%.0f%%", cpu.usage))
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(accent)
            }
            if cfg.shows("loadavg") {
                HStack(spacing: 0) {
                    CPUInfoItem(label: "1m",  value: String(format: "%.2f", cpu.loadAvg1))
                    CPUInfoItem(label: "5m",  value: String(format: "%.2f", cpu.loadAvg5))
                    CPUInfoItem(label: "15m", value: String(format: "%.2f", cpu.loadAvg15))
                }
            }
        }
    }

    // MARK: - History helpers

    private var overallHistory: [Double] {
        switch timeRange {
        case .fiveMin: return cpu.coreHistoryShort.first ?? cpu.history
        case .hour:    return cpu.coreHistoryHour.first  ?? []
        case .day:     return cpu.coreHistoryDay.first   ?? []
        case .week:    return cpu.coreHistoryWeek.first  ?? []
        }
    }

    private var coreHistories: [[Double]] {
        let buf: [[Double]]
        switch timeRange {
        case .fiveMin: buf = cpu.coreHistoryShort
        case .hour:    buf = cpu.coreHistoryHour
        case .day:     buf = cpu.coreHistoryDay
        case .week:    buf = cpu.coreHistoryWeek
        }
        guard buf.count > 1 else { return [] }
        return Array(buf.dropFirst())
    }
}

// MARK: - Sub-views

// P-core / E-core cluster average usage side by side
private struct ClusterRow: View {
    let pUsage: Double
    let eUsage: Double
    let accent: Color

    var body: some View {
        HStack(spacing: 8) {
            ClusterStat(label: "P-Cores", value: pUsage, color: accent)
            Divider().frame(height: 28)
            ClusterStat(label: "E-Cores", value: eUsage, color: .teal)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct ClusterStat: View {
    let label: String
    let value: Double
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            HStack(alignment: .lastTextBaseline, spacing: 3) {
                Text(String(format: "%.0f", value))
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(color)
                    .contentTransition(.numericText())
                Text("%")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(color)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// User / System / Idle breakdown bar + labels
private struct UserLoadRow: View {
    let user: Double
    let system: Double
    let idle: Double
    let accent: Color

    var body: some View {
        VStack(spacing: 5) {
            // Segmented bar
            GeometryReader { geo in
                HStack(spacing: 1) {
                    let w = geo.size.width
                    RoundedRectangle(cornerRadius: 2)
                        .fill(accent.opacity(0.8))
                        .frame(width: max(0, w * user / 100))
                    RoundedRectangle(cornerRadius: 2)
                        .fill(accent.opacity(0.35))
                        .frame(width: max(0, w * system / 100))
                    Spacer(minLength: 0)
                }
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 2))
            }
            .frame(height: 5)
            // Labels
            HStack(spacing: 0) {
                UserLoadLabel(dot: accent.opacity(0.8),        label: "User",   value: user)
                UserLoadLabel(dot: accent.opacity(0.35),       label: "System", value: system)
                UserLoadLabel(dot: Color.secondary.opacity(0.3), label: "Idle",   value: idle)
            }
        }
    }
}

private struct UserLoadLabel: View {
    let dot: Color
    let label: String
    let value: Double

    var body: some View {
        HStack(spacing: 3) {
            Circle().fill(dot).frame(width: 6, height: 6)
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .fixedSize()
            Text(String(format: "%.1f%%", value))
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
                .contentTransition(.numericText())
                .fixedSize()
        }
        .frame(maxWidth: .infinity)
        .lineLimit(1)
    }
}

private struct CPUInfoItem: View {
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 1) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity)
    }
}

private struct PopoverCoreGrid: View {
    let coreHistories: [[Double]]
    let coreUsages: [Double]
    var accentColor: Color = .blue

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 2)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(Array(coreHistories.enumerated()), id: \.offset) { idx, hist in
                PopoverCoreCell(
                    coreIndex: idx,
                    history: hist,
                    currentUsage: idx < coreUsages.count ? coreUsages[idx] : 0,
                    totalCores: coreUsages.count,
                    overrideAccent: accentColor)
            }
        }
    }
}

// MARK: - Live-updating panel view

/// Holds @ObservedObject references so the side panel rerenders when monitors publish.
struct CPUDetailPanelView: View {
    @ObservedObject var cpu: CPUMonitor
    @ObservedObject var processes: ProcessMonitor
    let accent: Color

    private var settings: AppSettings { AppSettings.shared }
    private var cfg: CardConfig { settings.config(for: .cpu) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("CPU — Top Processes", systemImage: "cpu")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)

            if cfg.shows("processes") && !processes.topCPU.isEmpty {
                let procs = Array(processes.topCPU.prefix(settings.topProcessesCount))
                ProcessList(
                    processes: procs,
                    valueLabel: { String(format: "%.1f%%", $0.cpuPercent) },
                    maxValue: procs.first?.cpuPercent ?? 1,
                    barValue: { $0.cpuPercent },
                    color: accent,
                    secondaryLabel: { p in
                        p.energyImpact > 0 ? String(format: "E%.0f", p.energyImpact) : ""
                    }
                )
            }

            if cfg.shows("clusters") && cpu.pCoreCount > 0 && cpu.eCoreCount > 0 {
                Divider().opacity(0.4)
                ClusterRow(pUsage: cpu.pCoreUsage, eUsage: cpu.eCoreUsage, accent: accent)
            }

            if cfg.shows("userload") {
                UserLoadRow(user: cpu.userPercent, system: cpu.systemPercent,
                            idle: cpu.idlePercent, accent: accent)
            }
        }
    }
}

private struct PopoverCoreCell: View {
    let coreIndex: Int
    let history: [Double]
    let currentUsage: Double
    let totalCores: Int
    var overrideAccent: Color = .blue

    private var isEfficiency: Bool {
        guard totalCores > 4 else { return false }
        let pCount = Int((Double(totalCores) * 2 / 3).rounded())
        return coreIndex >= pCount
    }
    private var color: Color { isEfficiency ? .teal : overrideAccent }
    private var label: String {
        if totalCores <= 4 { return "Core \(coreIndex + 1)" }
        let pCount = Int((Double(totalCores) * 2 / 3).rounded())
        return isEfficiency
            ? "E-Core \(coreIndex - pCount + 1)"
            : "P-Core \(coreIndex + 1)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 2)
                Text(String(format: "%.0f%%", currentUsage))
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(color)
                    .contentTransition(.numericText())
            }
            SparklineView(values: history, color: color, maxValue: 100)
                .frame(height: 28)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 6)
        .background(color.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
    }
}
