import Foundation
import IOKit

final class GPUMonitor: ObservableObject, Monitor {
    @Published var utilizationPercent: Double = 0
    @Published var rendererPercent:    Double = 0
    @Published var tilerPercent:       Double = 0
    @Published var encoderPercent:     Double = 0
    @Published var decoderPercent:     Double = 0
    @Published var usedMemoryMB:       Double = 0
    @Published var totalMemoryMB:      Double = 0
    @Published var history:      [Double] = Array(repeating: 0, count: 120)
    @Published var historyShort: [Double] = Array(repeating: 0, count: 150)
    @Published var historyHour:  [Double] = Array(repeating: 0, count: 360)
    @Published var historyDay:   [Double] = Array(repeating: 0, count: 288)
    @Published var historyWeek:  [Double] = Array(repeating: 0, count: 336)
    private var _hist = TimedHistory()

    private let queue = DispatchQueue(label: "com.resourcemonitor.gpu", qos: .utility)
    private var timer: DispatchSourceTimer?

    func start(interval: Double = 2.0) {
        queue.async { self._hist.load(key: "gpu") }
        stop()
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now(), repeating: interval)
        t.setEventHandler { [weak self] in self?.update() }
        t.resume()
        timer = t
    }

    func stop() {
        timer?.cancel(); timer = nil
        queue.async { self._hist.save(key: "gpu") }
    }

    private func update() {
        let snap = readGPU()
        _hist.push(snap.utilization)
        let h = _hist
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.utilizationPercent = snap.utilization
            self.rendererPercent    = snap.renderer
            self.tilerPercent       = snap.tiler
            self.encoderPercent     = snap.encoder
            self.decoderPercent     = snap.decoder
            self.usedMemoryMB       = snap.usedMB
            self.totalMemoryMB      = snap.totalMB
            self.history.append(snap.utilization); self.history.removeFirst()
            self.historyShort = h.short
            self.historyHour  = h.hour
            self.historyDay   = h.day
            self.historyWeek  = h.week
        }
    }

    private struct Snapshot {
        var utilization: Double = 0
        var renderer:    Double = 0
        var tiler:       Double = 0
        var encoder:     Double = 0
        var decoder:     Double = 0
        var usedMB:      Double = 0
        var totalMB:     Double = 0
    }

    private func readGPU() -> Snapshot {
        var snap = Snapshot()

        // Try AGXAccelerator (Apple Silicon GPU)
        var iter: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault,
              IOServiceMatching("AGXAccelerator"), &iter) == kIOReturnSuccess else {
            return snap
        }
        defer { IOObjectRelease(iter) }

        var service = IOIteratorNext(iter)
        defer { if service != 0 { IOObjectRelease(service) } }
        guard service != 0 else { return snap }

        if let stats = IORegistryEntryCreateCFProperty(
            service, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? [String: AnyObject] {

            snap.utilization = stats["Device Utilization %"] as? Double
                ?? Double(stats["Device Utilization %"] as? Int ?? 0)
            snap.renderer    = stats["Renderer Utilization %"] as? Double
                ?? Double(stats["Renderer Utilization %"] as? Int ?? 0)
            snap.tiler       = stats["Tiler Utilization %"] as? Double
                ?? Double(stats["Tiler Utilization %"] as? Int ?? 0)
            snap.encoder     = stats["Encode Utilization %"] as? Double
                ?? Double(stats["Encode Utilization %"] as? Int ?? 0)
            snap.decoder     = stats["Decode Utilization %"] as? Double
                ?? Double(stats["Decode Utilization %"] as? Int ?? 0)

            // On Apple Silicon memory is shared — report GPU-allocated bytes
            if let usedBytes = stats["In use system memory"] as? UInt64 {
                snap.usedMB = Double(usedBytes) / 1_048_576
            }
            if let allocBytes = stats["Allocated system memory"] as? UInt64 {
                snap.totalMB = Double(allocBytes) / 1_048_576
            }
        }

        // Fallback total from VRAM property if available (discrete GPU)
        if snap.totalMB == 0,
           let vram = IORegistryEntryCreateCFProperty(
            service, "VRAM,totalMB" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? UInt64 {
            snap.totalMB = Double(vram)
        }

        return snap
    }
}
