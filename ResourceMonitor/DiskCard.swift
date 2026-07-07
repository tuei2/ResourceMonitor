import SwiftUI

struct DiskCard: View {
    @ObservedObject var disk: DiskMonitor
    @ObservedObject var processes: ProcessMonitor
    @EnvironmentObject var settings: AppSettings
    var timeRange: HistoryTimeRange = .fiveMin
    var onExpand: (() -> Void)? = nil
    private var cfg: CardConfig { settings.config(for: .disk) }
    private var accent: Color {
        guard let h = settings.config(for: .disk).accentHex,
              let rgb = UInt64(h.hasPrefix("#") ? String(h.dropFirst()) : h, radix: 16)
        else { return .orange }
        return Color(red: Double((rgb >> 16) & 0xFF) / 255,
                     green: Double((rgb >> 8) & 0xFF) / 255,
                     blue: Double(rgb & 0xFF) / 255)
    }

    var body: some View {
        HoverCard {
            diskSummary
        } detail: {
            DiskDetailPanelView(disk: disk, processes: processes, accent: accent)
        }
    }

    private var diskSummary: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 5) {
                    Label("Disk", systemImage: "internaldrive")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    if let onExpand { CardExpandButton(action: onExpand) }
                }

                // Volume list
                if cfg.shows("volumes") {
                    ForEach(disk.volumes) { vol in
                        VolumeRow(volume: vol, accentColor: accent)
                    }
                    Divider().opacity(0.3)
                }

                // Live read/write speeds
                if cfg.shows("sparkline") {
                    HStack(spacing: 12) {
                        IOSpeedView(label: "Read",  value: disk.readMBps,
                                    history: disk.readValues(for: timeRange),  color: accent)
                        Divider().frame(height: 40)
                        IOSpeedView(label: "Write", value: disk.writeMBps,
                                    history: disk.writeValues(for: timeRange), color: .pink)
                    }
                }
            }
        }
    }

}

// MARK: - Live-updating panel view

struct DiskDetailPanelView: View {
    @ObservedObject var disk: DiskMonitor
    @ObservedObject var processes: ProcessMonitor
    let accent: Color

    private var settings: AppSettings { AppSettings.shared }
    private var cfg: CardConfig { settings.config(for: .disk) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Disk — Process I/O", systemImage: "internaldrive")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)

            let rdProcs = Array(processes.topDiskRd.filter { $0.diskReadMBps > 0 }
                .prefix(settings.topProcessesCount))
            let wrProcs = Array(processes.topDiskWr.filter { $0.diskWriteMBps > 0 }
                .prefix(settings.topProcessesCount))

            if !rdProcs.isEmpty {
                DiskProcSection(title: "Read", icon: "arrow.down.circle.fill",
                                processes: rdProcs,
                                value: { formatMBps($0.diskReadMBps) },
                                barValue: { $0.diskReadMBps },
                                maxValue: rdProcs.first?.diskReadMBps ?? 1,
                                color: accent)
            }
            if !wrProcs.isEmpty {
                if !rdProcs.isEmpty { Divider().opacity(0.3) }
                DiskProcSection(title: "Write", icon: "arrow.up.circle.fill",
                                processes: wrProcs,
                                value: { formatMBps($0.diskWriteMBps) },
                                barValue: { $0.diskWriteMBps },
                                maxValue: wrProcs.first?.diskWriteMBps ?? 1,
                                color: .pink)
            }
            if rdProcs.isEmpty && wrProcs.isEmpty {
                Text("No active disk processes")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            if cfg.shows("volumes") && !disk.volumes.isEmpty {
                Divider().opacity(0.4)
                ForEach(disk.volumes) { vol in
                    VolumeRow(volume: vol, accentColor: accent)
                }
            }
        }
    }

    private func formatMBps(_ v: Double) -> String {
        v >= 1 ? String(format: "%.1f MB/s", v) : String(format: "%.0f KB/s", v * 1024)
    }
}

private struct DiskProcSection: View {
    let title: String; let icon: String
    let processes: [ProcessStat]
    let value: (ProcessStat) -> String
    let barValue: (ProcessStat) -> Double
    let maxValue: Double; let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(LocalizedStringKey(title), systemImage: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(color)
            ProcessList(processes: processes, valueLabel: value,
                        maxValue: maxValue, barValue: barValue, color: color)
        }
    }
}

private struct DiskProcessGrid: View {
    let rdProcs: [ProcessStat]
    let wrProcs: [ProcessStat]

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if !rdProcs.isEmpty {
                MiniProcList(title: "Read", processes: rdProcs,
                             value: { formatMBps($0.diskReadMBps) }, color: .orange)
            }
            if !wrProcs.isEmpty {
                MiniProcList(title: "Write", processes: wrProcs,
                             value: { formatMBps($0.diskWriteMBps) }, color: .pink)
            }
        }
    }

    private func formatMBps(_ v: Double) -> String {
        v >= 1 ? String(format: "%.1fM/s", v) : String(format: "%.0fK/s", v * 1024)
    }
}

private struct MiniProcList: View {
    let title: String
    let processes: [ProcessStat]
    let value: (ProcessStat) -> String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)
            ForEach(processes.prefix(5)) { p in
                HStack(spacing: 4) {
                    Text(p.name)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Spacer(minLength: 2)
                    Text(value(p))
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(color)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(color.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct VolumeRow: View {
    let volume: DiskVolume
    var accentColor: Color = .orange

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(volume.name)
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                Text(String(format: "%.0f / %.0f GB", volume.usedGB, volume.totalGB))
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3).fill(accentColor.opacity(0.12))
                    RoundedRectangle(cornerRadius: 3).fill(volumeColor)
                        .frame(width: geo.size.width * CGFloat(volume.percent / 100))
                        .animation(.easeInOut(duration: 0.4), value: volume.percent)
                }
            }
            .frame(height: 5)
        }
    }

    private var volumeColor: Color {
        switch volume.percent {
        case 0..<70:  return accentColor
        case 70..<90: return .orange
        default:      return .red
        }
    }
}

private struct IOSpeedView: View {
    let label: String
    let value: Double
    let history: [Double]
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            Text(formatSpeed(value))
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(color)
                .contentTransition(.numericText())
            SparklineView(values: history, color: color,
                          maxValue: max(history.max() ?? 1, 1))
                .frame(height: 28)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func formatSpeed(_ mb: Double) -> String {
        mb >= 1000 ? String(format: "%.1f GB/s", mb / 1024)
                   : String(format: "%.1f MB/s", mb)
    }
}
