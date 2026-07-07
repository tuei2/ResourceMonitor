import SwiftUI

struct GPUCard: View {
    @ObservedObject var gpu: GPUMonitor
    @EnvironmentObject var settings: AppSettings
    var timeRange: HistoryTimeRange = .fiveMin
    var onExpand: (() -> Void)? = nil

    private var cfg: CardConfig { settings.config(for: .gpu) }

    var body: some View {
        HoverCard {
            GlassCard {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .bottom) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 5) {
                                Label("GPU", systemImage: "display")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.secondary)
                                if let onExpand { CardExpandButton(action: onExpand) }
                            }
                            Text(String(format: "%.1f%%", gpu.utilizationPercent))
                                .font(.system(size: 28, weight: .bold, design: .rounded))
                                .foregroundStyle(.mint)
                                .contentTransition(.numericText())
                        }
                        Spacer()
                        RingGauge(value: gpu.utilizationPercent, color: .mint)
                            .frame(width: 44, height: 44)
                    }

                    if cfg.shows("sparkline") {
                        SparklineView(values: gpu.historyValues(for: timeRange), color: .mint)
                            .frame(height: 44)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }

                    if cfg.shows("displays") {
                        Divider().opacity(0.3)
                        DisplaysSection()
                    }
                }
            }
        } detail: {
            GPUDetailPanelView(gpu: gpu, processes: AppState.shared.processes)
        }
    }
}

// MARK: - Live-updating panel view

struct GPUDetailPanelView: View {
    @ObservedObject var gpu: GPUMonitor
    @ObservedObject var processes: ProcessMonitor

    private var cfg: CardConfig { AppSettings.shared.config(for: .gpu) }
    private var settings: AppSettings { AppSettings.shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("GPU Detail", systemImage: "display")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)

            if cfg.shows("encoder") {
                let hasSubStats = gpu.rendererPercent > 0 || gpu.tilerPercent > 0
                    || gpu.encoderPercent > 0 || gpu.decoderPercent > 0
                if hasSubStats {
                    HStack(spacing: 12) {
                        if gpu.rendererPercent > 0 {
                            GPUSubStat(label: "Renderer", value: gpu.rendererPercent, color: .mint)
                        }
                        if gpu.tilerPercent > 0 {
                            GPUSubStat(label: "Tiler", value: gpu.tilerPercent, color: .teal)
                        }
                        if gpu.encoderPercent > 0 {
                            GPUSubStat(label: "Encoder", value: gpu.encoderPercent, color: .cyan)
                        }
                        if gpu.decoderPercent > 0 {
                            GPUSubStat(label: "Decoder", value: gpu.decoderPercent, color: .indigo)
                        }
                    }
                }
            }

            if gpu.usedMemoryMB > 0 {
                Divider().opacity(0.4)
                GPUMemStat(used: gpu.usedMemoryMB, total: gpu.totalMemoryMB)
            }

            if cfg.shows("displays") {
                Divider().opacity(0.4)
                DisplaysSection()
            }

            let energyProcs = Array(processes.topEnergy.prefix(settings.topProcessesCount))
            if !energyProcs.isEmpty {
                Divider().opacity(0.4)
                VStack(alignment: .leading, spacing: 6) {
                    Label("Energy Impact", systemImage: "bolt.circle.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.mint)
                    ProcessList(
                        processes: energyProcs,
                        valueLabel: { String(format: "%.0f", $0.energyImpact) },
                        maxValue: energyProcs.first?.energyImpact ?? 1,
                        barValue: { $0.energyImpact },
                        color: .mint
                    )
                }
            }
        }
    }
}

/// Lists connected displays with their native (backing) resolution and refresh rate.
private struct DisplaysSection: View {
    private struct DisplayInfo: Identifiable {
        let id: Int
        let name: String
        let width: Int
        let height: Int
        let hz: Int
        let isMain: Bool
    }

    private var displays: [DisplayInfo] {
        NSScreen.screens.enumerated().map { idx, screen in
            let scale = screen.backingScaleFactor
            let w = Int((screen.frame.width * scale).rounded())
            let h = Int((screen.frame.height * scale).rounded())
            return DisplayInfo(
                id: idx,
                name: screen.localizedName,
                width: w,
                height: h,
                hz: screen.maximumFramesPerSecond,
                isMain: screen == NSScreen.main
            )
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Displays", systemImage: "rectangle.on.rectangle")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.mint)
            ForEach(displays) { d in
                HStack(spacing: 6) {
                    Image(systemName: d.isMain ? "menubar.dock.rectangle" : "display")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .frame(width: 14)
                    Text(d.name)
                        .font(.system(size: 11))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text("\(d.width)×\(d.height)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                    if d.hz > 0 {
                        Text("\(d.hz)Hz")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

private struct GPUSubStat: View {
    let label: String
    let value: Double
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(LocalizedStringKey(label))
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
            Text(String(format: "%.0f%%", value))
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(color)
        }
    }
}

private struct GPUMemStat: View {
    let used: Double
    let total: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("VRAM")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
            Text(formatMB(used))
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.mint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func formatMB(_ mb: Double) -> String {
        mb >= 1024 ? String(format: "%.1f GB", mb / 1024) : String(format: "%.0f MB", mb)
    }
}
