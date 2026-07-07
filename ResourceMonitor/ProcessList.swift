import SwiftUI
import AppKit

// MARK: - Process icon cache

// Global cache keyed by pid so repeated renders don't call NSRunningApplication each time.
// Evicted lazily when the process list changes — cache entries for dead pids just sit until
// a new process with the same pid overwrites them (pids recycle, so icons stay accurate).
private var iconCache: [Int32: NSImage] = [:]

private func cachedIcon(for proc: ProcessStat) -> NSImage? {
    if let cached = iconCache[proc.id] { return cached }
    guard let app = NSRunningApplication(processIdentifier: proc.id),
          let icon = app.icon else { return nil }
    iconCache[proc.id] = icon
    return icon
}

// MARK: - Process icon view

private struct ProcessIconView: View {
    let proc: ProcessStat
    @State private var icon: NSImage? = nil

    var body: some View {
        Group {
            if let icon {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 14, height: 14)
            } else {
                // Daemon / CLI tool — no NSApplication, use generic chip icon
                Image(systemName: "app.dashed")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(width: 14, height: 14)
            }
        }
        .onAppear {
            // Lookup is fast but do it once; NSRunningApplication returns nil for daemons
            icon = cachedIcon(for: proc)
        }
    }
}

// MARK: - Process list

struct ProcessList: View {
    let processes: [ProcessStat]
    let valueLabel: (ProcessStat) -> String
    let maxValue: Double
    let barValue: (ProcessStat) -> Double
    let color: Color
    var secondaryLabel: ((ProcessStat) -> String)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Top Processes")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)
                .padding(.bottom, 2)

            ForEach(processes) { proc in
                HStack(spacing: 6) {
                    ProcessIconView(proc: proc)

                    Text(proc.name)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .frame(width: secondaryLabel != nil ? 70 : 90, alignment: .leading)

                    let ratio = barValue(proc) / max(maxValue, 0.01)
                    Canvas { ctx, size in
                        ctx.fill(
                            Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 2),
                            with: .color(color.opacity(0.1)))
                        let barW = size.width * ratio
                        if barW > 0 {
                            ctx.fill(
                                Path(roundedRect: CGRect(x: 0, y: 0, width: barW, height: size.height), cornerRadius: 2),
                                with: .color(color.opacity(0.55)))
                        }
                    }
                    .frame(height: 4)

                    Text(valueLabel(proc))
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(color)
                        .frame(width: 54, alignment: .trailing)

                    if let sec = secondaryLabel {
                        Text(sec(proc))
                            .font(.system(size: 11, design: .rounded))
                            .foregroundStyle(.secondary)
                            .frame(width: 30, alignment: .trailing)
                    }
                }
            }
        }
        .padding(10)
        .background(color.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(color.opacity(0.12), lineWidth: 0.5)
        }
    }
}
