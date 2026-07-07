import Foundation
import Darwin

final class CPUMonitor: ObservableObject, Monitor {
    // Popover card (raw ticks, ~2 min at 2s)
    @Published var usage: Double = 0
    @Published var history: [Double] = Array(repeating: 0, count: 120)
    @Published var coreUsages: [Double] = []
    @Published var uptime: String = ""
    @Published var loadAvg1: Double = 0
    @Published var loadAvg5: Double = 0
    @Published var loadAvg15: Double = 0

    // User/System/Idle breakdown (percentage of total wall-clock CPU time)
    @Published var userPercent:   Double = 0
    @Published var systemPercent: Double = 0
    @Published var idlePercent:   Double = 0

    // P-core vs E-core cluster averages (both 0 on Intel or single-cluster chips)
    @Published var pCoreUsage: Double = 0
    @Published var eCoreUsage: Double = 0

    // Number of P-cores and E-cores detected at startup via sysctl
    let pCoreCount: Int = {
        var v = 0; var s = MemoryLayout<Int>.size
        sysctlbyname("hw.perflevel0.logicalcpu", &v, &s, nil, 0); return v
    }()
    let eCoreCount: Int = {
        var v = 0; var s = MemoryLayout<Int>.size
        sysctlbyname("hw.perflevel1.logicalcpu", &v, &s, nil, 0); return v
    }()

    // Multi-resolution per-core & total history
    // [core][time] — core index 0 = total, 1..N = individual cores
    @Published var coreHistoryShort: [[Double]] = []   // ~5 min  at raw rate (150 pts)
    @Published var coreHistoryHour:  [[Double]] = []   // 1 hour  at 10s/pt  (360 pts)
    @Published var coreHistoryDay:   [[Double]] = []   // 1 day   at 5min/pt (288 pts)
    @Published var coreHistoryWeek:  [[Double]] = []   // 1 week  at 30min/pt (336 pts)

    private let queue = DispatchQueue(label: "com.resourcemonitor.cpu", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var prevInfo: processor_info_array_t?
    private var prevInfoCount: mach_msg_type_number_t = 0

    // Accumulator state (indexed: 0 = total, 1..N = cores)
    private var accHour:  [Double] = []
    private var accDay:   [Double] = []
    private var accWeek:  [Double] = []
    private var accHourCount:  Int = 0
    private var accDayCount:   Int = 0
    private var accWeekCount:  Int = 0
    private var lastHourFlush: Date = .now
    private var lastDayFlush:  Date = .now
    private var lastWeekFlush: Date = .now

    private let hourInterval:  TimeInterval = 10      // 10s → 360 pts/hour
    private let dayInterval:   TimeInterval = 300     // 5min → 288 pts/day
    private let weekInterval:  TimeInterval = 1800    // 30min → 336 pts/week

    func start(interval: Double = 2.0) {
        stop()
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now(), repeating: interval)
        t.setEventHandler { [weak self] in self?.update() }
        t.resume()
        timer = t
    }

    func stop() {
        timer?.cancel(); timer = nil
        // Reset delta state so the first tick after restart doesn't use stale absolute counters
        if let prev = prevInfo {
            vm_deallocate(mach_task_self_,
                          vm_address_t(bitPattern: prev),
                          vm_size_t(prevInfoCount) * vm_size_t(MemoryLayout<integer_t>.size))
            prevInfo = nil
            prevInfoCount = 0
        }
    }

    private func update() {
        let (total, cores, userPct, sysPct, idlePct) = readCPU()
        let (uptimeStr, la1, la5, la15) = readSystemInfo()

        // P/E-core averages (only meaningful when both cluster counts are known)
        var pAvg = 0.0, eAvg = 0.0
        if pCoreCount > 0 && eCoreCount > 0 && cores.count >= pCoreCount + eCoreCount {
            let pSlice = cores[0..<pCoreCount]
            let eSlice = cores[pCoreCount..<(pCoreCount + eCoreCount)]
            pAvg = pSlice.reduce(0, +) / Double(pCoreCount)
            eAvg = eSlice.reduce(0, +) / Double(eCoreCount)
        }
        let now = Date()
        let n = cores.count + 1   // slot 0 = total

        // Ensure accumulator arrays are sized correctly
        if accHour.count != n  { accHour  = Array(repeating: 0, count: n) }
        if accDay.count  != n  { accDay   = Array(repeating: 0, count: n) }
        if accWeek.count != n  { accWeek  = Array(repeating: 0, count: n) }

        // Accumulate this tick
        accHour[0]  += total; accDay[0]  += total; accWeek[0]  += total
        for i in cores.indices {
            accHour[i+1]  += cores[i]
            accDay[i+1]   += cores[i]
            accWeek[i+1]  += cores[i]
        }
        accHourCount += 1; accDayCount += 1; accWeekCount += 1

        // Check flush conditions
        let flushHour = now.timeIntervalSince(lastHourFlush) >= hourInterval
        let flushDay  = now.timeIntervalSince(lastDayFlush)  >= dayInterval
        let flushWeek = now.timeIntervalSince(lastWeekFlush) >= weekInterval

        var avgHour: [Double]? = nil
        var avgDay:  [Double]? = nil
        var avgWeek: [Double]? = nil

        if flushHour, accHourCount > 0 {
            let cnt = Double(accHourCount)
            avgHour = accHour.map { $0 / cnt }
            accHour = Array(repeating: 0, count: n)
            accHourCount = 0
            lastHourFlush = now
        }
        if flushDay, accDayCount > 0 {
            let cnt = Double(accDayCount)
            avgDay = accDay.map { $0 / cnt }
            accDay = Array(repeating: 0, count: n)
            accDayCount = 0
            lastDayFlush = now
        }
        if flushWeek, accWeekCount > 0 {
            let cnt = Double(accWeekCount)
            avgWeek = accWeek.map { $0 / cnt }
            accWeek = Array(repeating: 0, count: n)
            accWeekCount = 0
            lastWeekFlush = now
        }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.usage          = total
            self.coreUsages     = cores
            self.uptime         = uptimeStr
            self.loadAvg1       = la1
            self.loadAvg5       = la5
            self.loadAvg15      = la15
            self.userPercent    = userPct
            self.systemPercent  = sysPct
            self.idlePercent    = idlePct
            self.pCoreUsage     = pAvg
            self.eCoreUsage     = eAvg
            self.history.append(total); self.history.removeFirst()

            // Ensure short-history arrays match core count
            if self.coreHistoryShort.count != n {
                self.coreHistoryShort = Array(repeating: Array(repeating: 0, count: 150), count: n)
                self.coreHistoryHour  = Array(repeating: Array(repeating: 0, count: 360), count: n)
                self.coreHistoryDay   = Array(repeating: Array(repeating: 0, count: 288), count: n)
                self.coreHistoryWeek  = Array(repeating: Array(repeating: 0, count: 336), count: n)
            }

            // Append raw tick to short history (slot 0 = total, 1..N = cores)
            self.coreHistoryShort[0].append(total); self.coreHistoryShort[0].removeFirst()
            for i in cores.indices {
                self.coreHistoryShort[i+1].append(cores[i])
                self.coreHistoryShort[i+1].removeFirst()
            }

            if let avg = avgHour {
                self.coreHistoryHour[0].append(avg[0]); self.coreHistoryHour[0].removeFirst()
                for i in cores.indices {
                    self.coreHistoryHour[i+1].append(avg[i+1])
                    self.coreHistoryHour[i+1].removeFirst()
                }
            }
            if let avg = avgDay {
                self.coreHistoryDay[0].append(avg[0]); self.coreHistoryDay[0].removeFirst()
                for i in cores.indices {
                    self.coreHistoryDay[i+1].append(avg[i+1])
                    self.coreHistoryDay[i+1].removeFirst()
                }
            }
            if let avg = avgWeek {
                self.coreHistoryWeek[0].append(avg[0]); self.coreHistoryWeek[0].removeFirst()
                for i in cores.indices {
                    self.coreHistoryWeek[i+1].append(avg[i+1])
                    self.coreHistoryWeek[i+1].removeFirst()
                }
            }
        }
    }

    // Returns (totalUsage%, perCore%, userPct%, systemPct%, idlePct%)
    private func readCPU() -> (Double, [Double], Double, Double, Double) {
        var cpuInfo: processor_info_array_t?
        var cpuInfoCount: mach_msg_type_number_t = 0
        var numCPUs: natural_t = 0

        let result = host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO,
                                         &numCPUs, &cpuInfo, &cpuInfoCount)
        guard result == KERN_SUCCESS, let info = cpuInfo else { return (0, [], 0, 0, 0) }

        var totalUsed:  Double = 0
        var totalUser:  Double = 0
        var totalSys:   Double = 0
        var totalIdle:  Double = 0
        var totalTicks: Double = 0
        var coreUsages: [Double] = []

        let prev = prevInfo

        for i in 0..<Int(numCPUs) {
            let base = Int(CPU_STATE_MAX) * i
            let user   = Double(info[base + Int(CPU_STATE_USER)])
            let system = Double(info[base + Int(CPU_STATE_SYSTEM)])
            let nice   = Double(info[base + Int(CPU_STATE_NICE)])
            let idle   = Double(info[base + Int(CPU_STATE_IDLE)])

            let dUser, dSys, dNice, dIdle: Double
            if let p = prev {
                dUser  = max(0, user   - Double(p[base + Int(CPU_STATE_USER)]))
                dSys   = max(0, system - Double(p[base + Int(CPU_STATE_SYSTEM)]))
                dNice  = max(0, nice   - Double(p[base + Int(CPU_STATE_NICE)]))
                dIdle  = max(0, idle   - Double(p[base + Int(CPU_STATE_IDLE)]))
            } else {
                // First tick after start(): no baseline yet, report 0
                dUser = 0; dSys = 0; dNice = 0; dIdle = 0
            }
            let coreTicks = dUser + dSys + dNice + dIdle
            let coreUsed  = dUser + dSys + dNice
            coreUsages.append(coreTicks > 0 ? coreUsed / coreTicks * 100 : 0)
            totalUsed  += coreUsed
            totalUser  += dUser + dNice   // nice is user-space
            totalSys   += dSys
            totalIdle  += dIdle
            totalTicks += coreTicks
        }

        if let p = prev {
            vm_deallocate(mach_task_self_,
                          vm_address_t(bitPattern: p),
                          vm_size_t(prevInfoCount) * vm_size_t(MemoryLayout<integer_t>.size))
        }
        prevInfo = info
        prevInfoCount = cpuInfoCount

        let total = totalTicks > 0 ? totalUsed / totalTicks * 100 : 0
        let user  = totalTicks > 0 ? totalUser  / totalTicks * 100 : 0
        let sys   = totalTicks > 0 ? totalSys   / totalTicks * 100 : 0
        let idle  = totalTicks > 0 ? totalIdle  / totalTicks * 100 : 0
        return (total, coreUsages, user, sys, idle)
    }

    private func readSystemInfo() -> (String, Double, Double, Double) {
        var avgs = [Double](repeating: 0, count: 3)
        getloadavg(&avgs, 3)

        let secs = Int(ProcessInfo.processInfo.systemUptime)
        let d = secs / 86400
        let h = (secs % 86400) / 3600
        let m = (secs % 3600) / 60
        let uptimeStr: String
        if d > 0      { uptimeStr = "\(d)d \(h)h" }
        else if h > 0 { uptimeStr = "\(h)h \(m)m" }
        else          { uptimeStr = "\(m)m" }

        return (uptimeStr, avgs[0], avgs[1], avgs[2])
    }
}
