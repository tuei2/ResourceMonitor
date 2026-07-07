import Foundation
import Darwin
import CoreWLAN

enum NetConnectionType: String {
    case wifi, ethernet, other

    var systemImage: String {
        switch self {
        case .wifi:     return "wifi"
        case .ethernet: return "cable.connector"
        case .other:    return "network"
        }
    }
}

final class NetworkMonitor: ObservableObject, Monitor {
    @Published var downloadMBps: Double = 0
    @Published var uploadMBps:   Double = 0
    @Published var downloadHistory: [Double] = Array(repeating: 0, count: 120)
    @Published var uploadHistory:   [Double] = Array(repeating: 0, count: 120)
    @Published var dlHistoryShort: [Double] = Array(repeating: 0, count: 150)
    @Published var dlHistoryHour:  [Double] = Array(repeating: 0, count: 360)
    @Published var dlHistoryDay:   [Double] = Array(repeating: 0, count: 288)
    @Published var dlHistoryWeek:  [Double] = Array(repeating: 0, count: 336)
    @Published var ulHistoryShort: [Double] = Array(repeating: 0, count: 150)
    @Published var ulHistoryHour:  [Double] = Array(repeating: 0, count: 360)
    @Published var ulHistoryDay:   [Double] = Array(repeating: 0, count: 288)
    @Published var ulHistoryWeek:  [Double] = Array(repeating: 0, count: 336)
    private var _dlHist = TimedHistory()
    private var _ulHist = TimedHistory()
    @Published var todayDownloadGB:    Double = 0
    @Published var todayUploadGB:      Double = 0
    @Published var sevenDayDownloadGB: Double = 0
    @Published var sevenDayUploadGB:   Double = 0
    @Published var thirtyDayDownloadGB: Double = 0
    @Published var thirtyDayUploadGB:   Double = 0
    @Published var activeInterface: String = ""
    @Published var localIP: String = ""
    @Published var externalIP: String = ""
    @Published var wifiSSID: String = ""
    @Published var wifiRSSI: Int = 0
    @Published var wifiChannel: Int = 0
    @Published var wifiTxMbps: Double = 0
    @Published var vpnActive: Bool = false
    @Published var connectionType: NetConnectionType = .other

    private let queue = DispatchQueue(label: "com.resourcemonitor.network", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var lastExternalIPFetch: Date = .distantPast
    private var prevIn:   UInt64 = 0
    private var prevOut:  UInt64 = 0
    private var prevTime: Date   = .now

    // Daily totals persistence
    private struct DailyEntry: Codable {
        var date: Date
        var downloadBytes: UInt64
        var uploadBytes: UInt64
    }

    private var dayStartIn:    UInt64 = 0
    private var dayStartOut:   UInt64 = 0
    private var dayStartDate:  Date   = .distantPast
    private var history: [DailyEntry] = []

    func start(interval: Double = 2.0) {
        loadHistory()
        queue.async { self._dlHist.load(key: "net_dl"); self._ulHist.load(key: "net_ul") }
        stop()
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now(), repeating: interval)
        t.setEventHandler { [weak self] in self?.update() }
        t.resume()
        timer = t
    }

    func stop() {
        timer?.cancel(); timer = nil
        queue.async { self._dlHist.save(key: "net_dl"); self._ulHist.save(key: "net_ul") }
    }

    private func update() {
        let (ssid, rssi, channel, txMbps) = readWiFi()
        let (totalIn, totalOut, iface, ip) = readInterfaces()
        let vpnUp = detectVPN()
        // Wi-Fi if the primary interface is the CoreWLAN interface, else wired.
        let wifiIface = CWWiFiClient.shared().interface()?.interfaceName ?? ""
        let connType: NetConnectionType
        if iface.isEmpty                { connType = .other }
        else if iface == wifiIface      { connType = .wifi }
        else if iface.hasPrefix("en")   { connType = .ethernet }
        else                            { connType = .other }
        let now     = Date()
        let elapsed = now.timeIntervalSince(prevTime).clamped(to: 0.1...60)

        let dlBytes = totalIn  > prevIn  ? totalIn  - prevIn  : 0
        let ulBytes = totalOut > prevOut ? totalOut - prevOut : 0
        let dlMB    = prevIn > 0 ? Double(dlBytes) / 1_048_576 / elapsed : 0
        let ulMB    = prevIn > 0 ? Double(ulBytes) / 1_048_576 / elapsed : 0
        prevIn = totalIn;  prevOut = totalOut;  prevTime = now

        updateDailyTotals(dlBytes: dlBytes, ulBytes: ulBytes, totalIn: totalIn, totalOut: totalOut)

        let (todayDL, todayUL, d7DL, d7UL, d30DL, d30UL) = computeTotals()

        // Fetch external IP every 5 minutes
        if Date().timeIntervalSince(lastExternalIPFetch) > 300 {
            lastExternalIPFetch = Date()
            fetchExternalIP()
        }

        _dlHist.push(dlMB)
        _ulHist.push(ulMB)
        let dh = _dlHist, uh = _ulHist
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.downloadMBps = dlMB
            self.uploadMBps   = ulMB
            self.downloadHistory.append(dlMB); self.downloadHistory.removeFirst()
            self.uploadHistory.append(ulMB);   self.uploadHistory.removeFirst()
            self.dlHistoryShort = dh.short; self.dlHistoryHour = dh.hour
            self.dlHistoryDay   = dh.day;   self.dlHistoryWeek = dh.week
            self.ulHistoryShort = uh.short; self.ulHistoryHour = uh.hour
            self.ulHistoryDay   = uh.day;   self.ulHistoryWeek = uh.week
            self.activeInterface    = iface
            self.localIP            = ip
            self.wifiSSID           = ssid
            self.wifiRSSI           = rssi
            self.wifiChannel        = channel
            self.wifiTxMbps         = txMbps
            self.vpnActive          = vpnUp
            self.connectionType     = connType
            self.todayDownloadGB    = todayDL
            self.todayUploadGB      = todayUL
            self.sevenDayDownloadGB = d7DL
            self.sevenDayUploadGB   = d7UL
            self.thirtyDayDownloadGB = d30DL
            self.thirtyDayUploadGB   = d30UL
        }
    }

    // MARK: - External IP

    private func fetchExternalIP() {
        guard let url = URL(string: "https://api.ipify.org") else { return }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data, let ip = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !ip.isEmpty else { return }
            DispatchQueue.main.async { self?.externalIP = ip }
        }.resume()
    }

    // MARK: - Wi-Fi details

    private func readWiFi() -> (String, Int, Int, Double) {
        guard let iface = CWWiFiClient.shared().interface() else { return ("", 0, 0, 0) }
        let ssid    = iface.ssid() ?? ""
        let rssi    = iface.rssiValue()
        let channel = iface.wlanChannel()?.channelNumber ?? 0
        let txMbps  = iface.transmitRate()
        return (ssid, rssi, channel, txMbps)
    }

    // MARK: - VPN detection

    /// A VPN is considered active when a tunnel interface (utun/ipsec/tap/ppp)
    /// has an assigned IPv4 address. utun interfaces also exist for other system
    /// services, so requiring an IPv4 address filters most of those out.
    private func detectVPN() -> Bool {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return false }
        defer { freeifaddrs(ifaddr) }

        var ptr = ifaddr
        while let cur = ptr {
            defer { ptr = cur.pointee.ifa_next }
            let name = String(cString: cur.pointee.ifa_name)
            let isTunnel = name.hasPrefix("utun") || name.hasPrefix("ipsec")
                        || name.hasPrefix("tap")  || name.hasPrefix("ppp")
            guard isTunnel,
                  cur.pointee.ifa_addr.pointee.sa_family == UInt8(AF_INET) else { continue }
            // A tunnel interface carrying an IPv4 address and marked up is
            // treated as an active VPN. Not every client sets IFF_RUNNING.
            let flags = Int32(cur.pointee.ifa_flags)
            if (flags & IFF_UP) != 0 { return true }
        }
        return false
    }

    // MARK: - Interface reading

    private func readInterfaces() -> (UInt64, UInt64, String, String) {
        var totalIn:  UInt64 = 0
        var totalOut: UInt64 = 0
        var primaryIface = ""
        var primaryBytes: UInt64 = 0

        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return (0, 0, "", "") }
        defer { freeifaddrs(ifaddr) }

        var ptr = ifaddr
        while let cur = ptr {
            defer { ptr = cur.pointee.ifa_next }
            let name   = String(cString: cur.pointee.ifa_name)
            let family = cur.pointee.ifa_addr.pointee.sa_family
            guard family == UInt8(AF_LINK),
                  !name.hasPrefix("lo"),
                  !name.hasPrefix("utun"),
                  !name.hasPrefix("ipsec") else { continue }

            guard let ifData = cur.pointee.ifa_data else { continue }
            ifData.withMemoryRebound(to: if_data.self, capacity: 1) { data in
                let ibytes = UInt64(data.pointee.ifi_ibytes)
                let obytes = UInt64(data.pointee.ifi_obytes)
                totalIn  += ibytes
                totalOut += obytes
                if ibytes + obytes > primaryBytes {
                    primaryBytes = ibytes + obytes
                    primaryIface = name
                }
            }
        }

        // Find IPv4 address for the primary interface
        var localIP = ""
        if !primaryIface.isEmpty {
            ptr = ifaddr
            while let cur = ptr {
                defer { ptr = cur.pointee.ifa_next }
                let name = String(cString: cur.pointee.ifa_name)
                guard name == primaryIface,
                      cur.pointee.ifa_addr.pointee.sa_family == UInt8(AF_INET) else { continue }
                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(cur.pointee.ifa_addr, socklen_t(cur.pointee.ifa_addr.pointee.sa_len),
                               &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST) == 0 {
                    localIP = String(cString: hostname)
                }
                break
            }
        }

        return (totalIn, totalOut, primaryIface, localIP)
    }

    // MARK: - Daily history

    private func updateDailyTotals(dlBytes: UInt64, ulBytes: UInt64, totalIn: UInt64, totalOut: UInt64) {
        let cal = Calendar.current
        let now = Date()

        // Reset day tracking at midnight
        if !cal.isDate(dayStartDate, inSameDayAs: now) {
            if dayStartDate != .distantPast {
                let entry = DailyEntry(date: dayStartDate,
                                       downloadBytes: totalIn  - dayStartIn,
                                       uploadBytes:   totalOut - dayStartOut)
                history.append(entry)
                // Keep only 31 days
                history = history.filter {
                    cal.dateComponents([.day], from: $0.date, to: now).day ?? 99 <= 31
                }
                saveHistory()
            }
            dayStartIn   = totalIn
            dayStartOut  = totalOut
            dayStartDate = now
        }
    }

    private func computeTotals() -> (Double, Double, Double, Double, Double, Double) {
        let now = Date()
        let cal = Calendar.current
        func gb(_ bytes: UInt64) -> Double { Double(bytes) / 1_073_741_824 }

        // Today: from day start
        let todayDL = dayStartIn  > 0 ? gb(prevIn  - dayStartIn)  : 0
        let todayUL = dayStartOut > 0 ? gb(prevOut - dayStartOut) : 0

        // Historical days
        var d7DL: UInt64 = 0; var d7UL: UInt64 = 0
        var d30DL: UInt64 = 0; var d30UL: UInt64 = 0

        for entry in history {
            let days = cal.dateComponents([.day], from: entry.date, to: now).day ?? 99
            if days <= 7  { d7DL  += entry.downloadBytes; d7UL  += entry.uploadBytes }
            if days <= 30 { d30DL += entry.downloadBytes; d30UL += entry.uploadBytes }
        }
        // Add today to rolling totals
        let todayDLBytes = dayStartIn  > 0 ? prevIn  - dayStartIn  : 0
        let todayULBytes = dayStartOut > 0 ? prevOut - dayStartOut : 0
        d7DL  += todayDLBytes; d7UL  += todayULBytes
        d30DL += todayDLBytes; d30UL += todayULBytes

        return (todayDL, todayUL, gb(d7DL), gb(d7UL), gb(d30DL), gb(d30UL))
    }

    private func loadHistory() {
        guard let data = UserDefaults.standard.data(forKey: "networkHistory"),
              let entries = try? JSONDecoder().decode([DailyEntry].self, from: data) else { return }
        history = entries
    }

    private func saveHistory() {
        guard let data = try? JSONEncoder().encode(history) else { return }
        UserDefaults.standard.set(data, forKey: "networkHistory")
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
