import Foundation
import Darwin

final class ProcessMonitor: ObservableObject, Monitor {
    @Published var topCPU:     [ProcessStat] = []
    @Published var topRAM:     [ProcessStat] = []
    @Published var topDiskRd:  [ProcessStat] = []
    @Published var topDiskWr:  [ProcessStat] = []
    @Published var topNetDL:   [ProcessStat] = []
    @Published var topNetUL:   [ProcessStat] = []
    @Published var topEnergy:  [ProcessStat] = []

    private let queue    = DispatchQueue(label: "com.resourcemonitor.processes", qos: .utility)
    private let netQueue = DispatchQueue(label: "com.resourcemonitor.nettop",    qos: .background)
    private var timer:    DispatchSourceTimer?
    private var netTimer: DispatchSourceTimer?

    // Per-PID rusage snapshot for delta computation
    private struct RUsageSnap {
        var diskRead:  UInt64
        var diskWrite: UInt64
        var wakeups:   UInt64
        var gpuTimeNs: UInt64
        var time:      Date
    }
    private var prevRUsage: [Int32: RUsageSnap] = [:]

    // Latest nettop result, updated independently
    private struct NetBW { var dlMBps: Double; var ulMBps: Double }
    private var netSnapshot: [Int32: NetBW] = [:]

    func start(interval: Double = 2.0) {
        stop()

        // Process + disk IO timer — every max(interval*2, 4)s
        let procInterval = max(interval * 2, 4.0)
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now(), repeating: procInterval)
        t.setEventHandler { [weak self] in self?.update() }
        t.resume()
        timer = t

        // Network timer — every 10s (nettop takes ~1s to run)
        let nt = DispatchSource.makeTimerSource(queue: netQueue)
        nt.schedule(deadline: .now() + 2, repeating: 10.0)
        nt.setEventHandler { [weak self] in self?.updateNetwork() }
        nt.resume()
        netTimer = nt
    }

    func stop() {
        timer?.cancel();    timer = nil
        netTimer?.cancel(); netTimer = nil
    }

    // MARK: - Process + disk IO

    private func update() {
        let raw  = shellOutput("/bin/ps", ["-Aceo", "pid=,pcpu=,rss=,comm="])
        let now  = Date()
        var procs: [(pid: Int32, name: String, cpu: Double, ramMB: Double,
                     rdMBps: Double, wrMBps: Double, energy: Double, gpuPct: Double)] = []

        for line in raw.components(separatedBy: "\n") {
            let parts = line.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
            guard parts.count >= 4,
                  let pid = Int32(parts[0]),
                  let cpu = Double(parts[1]),
                  let rssKB = Double(parts[2]) else { continue }
            let name = String(parts[3]).trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { continue }

            let (rdMBps, wrMBps, wkps, gpuPct) = rusageDelta(pid: pid, now: now)
            let energy = cpu * 2.0 + wkps * 3.0

            procs.append((pid, name, cpu, rssKB / 1024.0, rdMBps, wrMBps, energy, gpuPct))
        }

        // Merge nettop data (read from main snapshot, no lock needed — queue serial)
        let net = netSnapshot
        let built: [ProcessStat] = procs.map { p in
            let bw = net[p.pid]
            return ProcessStat(id: p.pid, name: p.name,
                               cpuPercent: p.cpu, ramMB: p.ramMB,
                               diskReadMBps: p.rdMBps, diskWriteMBps: p.wrMBps,
                               netDLMBps: bw?.dlMBps ?? 0, netULMBps: bw?.ulMBps ?? 0,
                               energyImpact: p.energy, gpuPercent: p.gpuPct)
        }

        let topCPU    = Array(built.sorted { $0.cpuPercent    > $1.cpuPercent    }.prefix(10))
        let topRAM    = Array(built.sorted { $0.ramMB         > $1.ramMB         }.prefix(10))
        let topDiskRd = Array(built.sorted { $0.diskReadMBps  > $1.diskReadMBps  }.prefix(8))
        let topDiskWr = Array(built.sorted { $0.diskWriteMBps > $1.diskWriteMBps }.prefix(8))
        let topEnergy = Array(built.filter { $0.energyImpact > 0 }
                                   .sorted { $0.energyImpact > $1.energyImpact }.prefix(8))

        DispatchQueue.main.async { [weak self] in
            self?.topCPU    = topCPU
            self?.topRAM    = topRAM
            self?.topDiskRd = topDiskRd
            self?.topDiskWr = topDiskWr
            self?.topEnergy = topEnergy
        }
    }

    // MARK: - rusage (disk IO + wakeups)

    private func rusageDelta(pid: Int32, now: Date) -> (rdMBps: Double, wrMBps: Double, wkps: Double, gpuPct: Double) {
        var info = rusage_info_v4()
        let ret: Int32 = withUnsafeMutablePointer(to: &info) { ptr in
            ptr.withMemoryRebound(to: Optional<UnsafeMutableRawPointer>.self, capacity: 1) { rptr in
                proc_pid_rusage(pid, RUSAGE_INFO_V4, rptr)
            }
        }
        guard ret == 0 else { return (0, 0, 0, 0) }

        let rd = info.ri_diskio_bytesread
        let wr = info.ri_diskio_byteswritten
        let wk = info.ri_pkg_idle_wkups + info.ri_interrupt_wkups

        defer {
            prevRUsage[pid] = RUsageSnap(diskRead: rd, diskWrite: wr,
                                         wakeups: wk, gpuTimeNs: 0, time: now)
        }

        guard let prev = prevRUsage[pid] else { return (0, 0, 0, 0) }
        let elapsed = max(now.timeIntervalSince(prev.time), 0.1)

        let rdMBps = Double(rd > prev.diskRead  ? rd - prev.diskRead  : 0) / 1_048_576 / elapsed
        let wrMBps = Double(wr > prev.diskWrite ? wr - prev.diskWrite : 0) / 1_048_576 / elapsed
        let wkps   = Double(wk > prev.wakeups   ? wk - prev.wakeups  : 0) / elapsed

        return (rdMBps, wrMBps, wkps, 0)
    }

    // MARK: - Per-process network via nettop

    private func updateNetwork() {
        // -L: CSV mode (parseable), -s 1: 1-second sample interval, -2 samples: gives a delta.
        // Separate -t flags required — comma-joined value is not accepted.
        let raw = shellOutput("/usr/bin/nettop",
                              ["-P", "-n", "-L", "2", "-s", "1", "-t", "wifi", "-t", "wired"])
        let byPid = parseNettopCSV(raw)

        queue.async { [weak self] in
            self?.netSnapshot = byPid
            self?.publishNetTop(byPid)
        }
    }

    private func publishNetTop(_ byPid: [Int32: NetBW]) {
        let raw = shellOutput("/bin/ps", ["-Aceo", "pid=,comm="])
        var names: [Int32: String] = [:]
        for line in raw.components(separatedBy: "\n") {
            let p = line.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
            guard p.count == 2, let pid = Int32(p[0]) else { continue }
            names[pid] = String(p[1]).trimmingCharacters(in: .whitespaces)
        }

        let stats: [ProcessStat] = byPid.compactMap { pid, bw in
            guard bw.dlMBps > 0 || bw.ulMBps > 0 else { return nil }
            let name = names[pid] ?? "PID \(pid)"
            return ProcessStat(id: pid, name: name, cpuPercent: 0, ramMB: 0,
                               netDLMBps: bw.dlMBps, netULMBps: bw.ulMBps)
        }
        let topDL = Array(stats.sorted { $0.netDLMBps > $1.netDLMBps }.prefix(8))
        let topUL = Array(stats.sorted { $0.netULMBps > $1.netULMBps }.prefix(8))

        DispatchQueue.main.async { [weak self] in
            self?.topNetDL = topDL
            self?.topNetUL = topUL
        }
    }

    // MARK: - nettop CSV parser
    //
    // CSV header:  time,,interface,state,bytes_in,bytes_out,...
    // Data line:   12:01:43,name.pid,,,21153,6885,...
    //
    // With -L 2 -s 1 we get two samples one second apart.
    // Delta between last and first sample for each PID ≈ bytes/s rate.

    private func parseNettopCSV(_ output: String) -> [Int32: NetBW] {
        var first: [Int32: (dl: Double, ul: Double)] = [:]
        var last:  [Int32: (dl: Double, ul: Double)] = [:]

        for line in output.components(separatedBy: "\n") {
            let cols = line.components(separatedBy: ",")
            guard cols.count >= 6 else { continue }
            // Skip header row
            guard cols[0] != "time", !cols[0].isEmpty else { continue }
            // col[1] = "processname.pid" — PID is after the last "."
            guard let dotRange = cols[1].range(of: ".", options: .backwards),
                  let pid = Int32(cols[1][dotRange.upperBound...]) else { continue }
            guard let dl = Double(cols[4]), let ul = Double(cols[5]) else { continue }

            if first[pid] == nil { first[pid] = (dl, ul) }
            last[pid] = (dl, ul)
        }

        // delta bytes over 1 second = bytes/s; convert to MB/s
        var result: [Int32: NetBW] = [:]
        for (pid, l) in last {
            guard let f = first[pid] else { continue }
            let dlBytes = max(0, l.dl - f.dl)
            let ulBytes = max(0, l.ul - f.ul)
            guard dlBytes > 0 || ulBytes > 0 else { continue }
            result[pid] = NetBW(dlMBps: dlBytes / 1_048_576, ulMBps: ulBytes / 1_048_576)
        }
        return result
    }
}
