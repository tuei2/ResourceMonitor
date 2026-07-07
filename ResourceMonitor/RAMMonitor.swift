import Foundation
import Darwin

final class RAMMonitor: ObservableObject, Monitor {
    @Published var usedGB: Double = 0
    @Published var totalGB: Double = 0
    @Published var percent: Double = 0
    @Published var history: [Double] = Array(repeating: 0, count: 120)
    @Published var historyShort: [Double] = Array(repeating: 0, count: 150)
    @Published var historyHour:  [Double] = Array(repeating: 0, count: 360)
    @Published var historyDay:   [Double] = Array(repeating: 0, count: 288)
    @Published var historyWeek:  [Double] = Array(repeating: 0, count: 336)
    private var _hist = TimedHistory()

    // Memory breakdown
    @Published var wiredGB: Double = 0
    @Published var activeGB: Double = 0
    @Published var compressedGB: Double = 0
    // 0 = normal, 1 = warning (yellow), 2 = critical (red)
    @Published var pressureLevel: Int = 0
    @Published var swapUsedGB: Double = 0
    @Published var swapTotalGB: Double = 0

    private let queue = DispatchQueue(label: "com.resourcemonitor.ram", qos: .utility)
    private var timer: DispatchSourceTimer?

    func start(interval: Double = 2.0) {
        queue.async { self._hist.load(key: "ram") }
        stop()
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now(), repeating: interval)
        t.setEventHandler { [weak self] in self?.update() }
        t.resume()
        timer = t
    }

    func stop() {
        timer?.cancel(); timer = nil
        queue.async { self._hist.save(key: "ram") }
    }

    private func update() {
        let r = readRAM()
        pushHistory(r.pct)
        let h = _hist
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.usedGB        = r.used
            self.totalGB       = r.total
            self.percent       = r.pct
            self.wiredGB       = r.wired
            self.activeGB      = r.active
            self.compressedGB  = r.compressed
            self.pressureLevel = r.pressure
            self.swapUsedGB    = r.swapUsed
            self.swapTotalGB   = r.swapTotal
            self.history.append(r.pct); self.history.removeFirst()
            self.historyShort  = h.short
            self.historyHour   = h.hour
            self.historyDay    = h.day
            self.historyWeek   = h.week
        }
    }

    private struct RAMStats {
        var used, total, pct, wired, active, compressed: Double
        var pressure: Int
        var swapUsed: Double = 0
        var swapTotal: Double = 0
    }

    private func pushHistory(_ pct: Double) {
        _hist.push(pct)
    }

    private func readRAM() -> RAMStats {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)

        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return RAMStats(used:0,total:0,pct:0,wired:0,active:0,compressed:0,pressure:0) }

        let pageSize = Double(vm_kernel_page_size)
        let total    = Double(ProcessInfo.processInfo.physicalMemory)
        let wired    = Double(stats.wire_count) * pageSize
        // internal_page_count = anonymous (app-owned) pages only — matches Activity Monitor's
        // "App Memory". active_count also includes file-backed cache pages, which is why it
        // reads ~1 GB higher than Activity Monitor shows.
        let active   = Double(stats.internal_page_count) * pageSize
        let compressed = Double(stats.compressor_page_count) * pageSize
        let used     = wired + active + compressed
        let pct      = total > 0 ? used / total * 100 : 0

        // Pressure thresholds come from user settings (same slider as alert notifications)
        let warnAt = AppSettings.shared.ramAlertThreshold
        let critAt = min(99, warnAt + 15)
        let pressure = pct >= critAt ? 2 : pct >= warnAt ? 1 : 0

        // Swap usage
        var swapUsed: Double = 0
        var swapTotal: Double = 0
        var xsw = xsw_usage()
        var xswSize = MemoryLayout<xsw_usage>.size
        if sysctlbyname("vm.swapusage", &xsw, &xswSize, nil, 0) == 0 {
            swapUsed  = Double(xsw.xsu_used)  / 1_073_741_824
            swapTotal = Double(xsw.xsu_total) / 1_073_741_824
        }

        return RAMStats(
            used:       used / 1_073_741_824,
            total:      total / 1_073_741_824,
            pct:        pct,
            wired:      wired / 1_073_741_824,
            active:     active / 1_073_741_824,
            compressed: compressed / 1_073_741_824,
            pressure:   pressure,
            swapUsed:   swapUsed,
            swapTotal:  swapTotal
        )
    }
}
