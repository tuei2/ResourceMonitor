import Foundation
import IOKit

struct DiskVolume: Identifiable, Equatable {
    let id: String          // mount point path
    let name: String
    let totalGB: Double
    let usedGB: Double
    var freeGB: Double { totalGB - usedGB }
    var percent: Double { totalGB > 0 ? usedGB / totalGB * 100 : 0 }
}

final class DiskMonitor: ObservableObject, Monitor {
    @Published var volumes: [DiskVolume] = []
    @Published var readMBps: Double = 0
    @Published var writeMBps: Double = 0
    @Published var readHistory:  [Double] = Array(repeating: 0, count: 120)
    @Published var writeHistory: [Double] = Array(repeating: 0, count: 120)
    @Published var rdHistoryShort: [Double] = Array(repeating: 0, count: 150)
    @Published var rdHistoryHour:  [Double] = Array(repeating: 0, count: 360)
    @Published var rdHistoryDay:   [Double] = Array(repeating: 0, count: 288)
    @Published var rdHistoryWeek:  [Double] = Array(repeating: 0, count: 336)
    @Published var wrHistoryShort: [Double] = Array(repeating: 0, count: 150)
    @Published var wrHistoryHour:  [Double] = Array(repeating: 0, count: 360)
    @Published var wrHistoryDay:   [Double] = Array(repeating: 0, count: 288)
    @Published var wrHistoryWeek:  [Double] = Array(repeating: 0, count: 336)
    private var _rdHist = TimedHistory()
    private var _wrHist = TimedHistory()

    private let queue = DispatchQueue(label: "com.resourcemonitor.disk", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var prevRead:  UInt64 = 0
    private var prevWrite: UInt64 = 0
    private var prevTime:  Date   = .now

    func start(interval: Double = 2.0) {
        queue.async { self._rdHist.load(key: "disk_rd"); self._wrHist.load(key: "disk_wr") }
        stop()
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now(), repeating: interval)
        t.setEventHandler { [weak self] in self?.update(interval: interval) }
        t.resume()
        timer = t
    }

    func stop() {
        timer?.cancel(); timer = nil
        queue.async { self._rdHist.save(key: "disk_rd"); self._wrHist.save(key: "disk_wr") }
    }

    private func update(interval: Double) {
        let vols          = readVolumes()
        let (r, w)        = readDiskIO()
        let now           = Date()
        let elapsed       = now.timeIntervalSince(prevTime).clamped(to: 0.1...60)
        let readMB        = prevRead  > 0 ? Double(r > prevRead  ? r - prevRead  : 0) / 1_048_576 / elapsed : 0
        let writeMB       = prevWrite > 0 ? Double(w > prevWrite ? w - prevWrite : 0) / 1_048_576 / elapsed : 0
        prevRead  = r;  prevWrite = w;  prevTime = now

        _rdHist.push(readMB)
        _wrHist.push(writeMB)
        let rh = _rdHist, wh = _wrHist
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.volumes   = vols
            self.readMBps  = readMB
            self.writeMBps = writeMB
            self.readHistory.append(readMB);   self.readHistory.removeFirst()
            self.writeHistory.append(writeMB); self.writeHistory.removeFirst()
            self.rdHistoryShort = rh.short; self.rdHistoryHour = rh.hour
            self.rdHistoryDay   = rh.day;   self.rdHistoryWeek = rh.week
            self.wrHistoryShort = wh.short; self.wrHistoryHour = wh.hour
            self.wrHistoryDay   = wh.day;   self.wrHistoryWeek = wh.week
        }
    }

    // MARK: - Volumes

    private func readVolumes() -> [DiskVolume] {
        guard let urls = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: [
                .volumeNameKey, .volumeTotalCapacityKey,
                .volumeAvailableCapacityForImportantUsageKey, .volumeIsLocalKey,
                .volumeIsInternalKey
            ],
            options: [.skipHiddenVolumes]) else { return [] }

        return urls.compactMap { url -> DiskVolume? in
            guard let vals = try? url.resourceValues(forKeys: [
                .volumeNameKey, .volumeTotalCapacityKey,
                .volumeAvailableCapacityForImportantUsageKey,
                .volumeIsLocalKey, .volumeIsInternalKey
            ]) else { return nil }
            guard vals.volumeIsLocal == true else { return nil }
            let total = Double(vals.volumeTotalCapacity ?? 0) / 1_073_741_824
            guard total > 0.1 else { return nil }
            let free  = Double(vals.volumeAvailableCapacityForImportantUsage ?? 0) / 1_073_741_824
            let name  = vals.volumeName ?? url.lastPathComponent
            return DiskVolume(id: url.path, name: name, totalGB: total, usedGB: total - free)
        }
    }

    // MARK: - Disk I/O

    private func readDiskIO() -> (UInt64, UInt64) {
        var totalRead: UInt64  = 0
        var totalWrite: UInt64 = 0

        var iter: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault,
              IOServiceMatching("IOBlockStorageDriver"), &iter) == kIOReturnSuccess else {
            return (0, 0)
        }
        defer { IOObjectRelease(iter) }

        var service = IOIteratorNext(iter)
        while service != 0 {
            defer { IOObjectRelease(service); service = IOIteratorNext(iter) }
            guard let stats = IORegistryEntryCreateCFProperty(
                service, "Statistics" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? [String: Any] else { continue }
            totalRead  += stats["Bytes (Read)"]    as? UInt64 ?? 0
            totalWrite += stats["Bytes (Write)"]   as? UInt64 ?? 0
        }
        return (totalRead, totalWrite)
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
