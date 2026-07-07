import Foundation

// MARK: - Time range enum (used by toggle + all cards)

enum HistoryTimeRange: String, CaseIterable, Identifiable {
    case fiveMin = "5 min"
    case hour    = "1 uur"
    case day     = "1 dag"
    case week    = "1 week"
    var id: String { rawValue }
}

// MARK: - Per-metric accumulator (call push() on background thread)

private struct CodableHistory: Codable {
    var short: [Double]
    var hour:  [Double]
    var day:   [Double]
    var week:  [Double]
}

struct TimedHistory {
    private(set) var short: [Double] = Array(repeating: 0, count: 150)  // raw
    private(set) var hour:  [Double] = Array(repeating: 0, count: 360)  // 10s avg
    private(set) var day:   [Double] = Array(repeating: 0, count: 288)  // 5min avg
    private(set) var week:  [Double] = Array(repeating: 0, count: 336)  // 30min avg

    private var aH = 0.0, cH = 0; private var tH: Date = .now
    private var aD = 0.0, cD = 0; private var tD: Date = .now
    private var aW = 0.0, cW = 0; private var tW: Date = .now

    mutating func push(_ v: Double, now: Date = .now) {
        short.append(v); short.removeFirst()
        aH += v; cH += 1
        aD += v; cD += 1
        aW += v; cW += 1
        if now.timeIntervalSince(tH) >= 10,  cH > 0 { flush(&hour,  &aH, &cH, &tH, now) }
        if now.timeIntervalSince(tD) >= 300, cD > 0 { flush(&day,   &aD, &cD, &tD, now) }
        if now.timeIntervalSince(tW) >= 1800,cW > 0 { flush(&week,  &aW, &cW, &tW, now) }
    }

    private func flush(_ buf: inout [Double], _ acc: inout Double,
                       _ cnt: inout Int, _ last: inout Date, _ now: Date) {
        buf.append(acc / Double(cnt)); buf.removeFirst()
        acc = 0; cnt = 0; last = now
    }

    func values(for range: HistoryTimeRange) -> [Double] {
        switch range {
        case .fiveMin: return short
        case .hour:    return hour
        case .day:     return day
        case .week:    return week
        }
    }

    // Persist to UserDefaults. Only restores if saved within maxAge seconds.
    mutating func save(key: String) {
        let h = CodableHistory(short: short, hour: hour, day: day, week: week)
        guard let data = try? JSONEncoder().encode(h) else { return }
        UserDefaults.standard.set(data, forKey: "hist_\(key)")
        UserDefaults.standard.set(Date(), forKey: "hist_\(key)_date")
    }

    mutating func load(key: String, maxAge: TimeInterval = 3600) {
        guard let date = UserDefaults.standard.object(forKey: "hist_\(key)_date") as? Date,
              Date().timeIntervalSince(date) < maxAge,
              let data = UserDefaults.standard.data(forKey: "hist_\(key)"),
              let h = try? JSONDecoder().decode(CodableHistory.self, from: data) else { return }
        if h.short.count == short.count { short = h.short }
        if h.hour.count  == hour.count  { hour  = h.hour  }
        if h.day.count   == day.count   { day   = h.day   }
        if h.week.count  == week.count  { week  = h.week  }
    }
}

// MARK: - Convenience extensions on monitors

extension RAMMonitor {
    func historyValues(for range: HistoryTimeRange) -> [Double] {
        switch range {
        case .fiveMin: return historyShort
        case .hour:    return historyHour
        case .day:     return historyDay
        case .week:    return historyWeek
        }
    }
}

extension GPUMonitor {
    func historyValues(for range: HistoryTimeRange) -> [Double] {
        switch range {
        case .fiveMin: return historyShort
        case .hour:    return historyHour
        case .day:     return historyDay
        case .week:    return historyWeek
        }
    }
}

extension NetworkMonitor {
    func downloadValues(for range: HistoryTimeRange) -> [Double] {
        switch range {
        case .fiveMin: return dlHistoryShort
        case .hour:    return dlHistoryHour
        case .day:     return dlHistoryDay
        case .week:    return dlHistoryWeek
        }
    }
    func uploadValues(for range: HistoryTimeRange) -> [Double] {
        switch range {
        case .fiveMin: return ulHistoryShort
        case .hour:    return ulHistoryHour
        case .day:     return ulHistoryDay
        case .week:    return ulHistoryWeek
        }
    }
}

extension DiskMonitor {
    func readValues(for range: HistoryTimeRange) -> [Double] {
        switch range {
        case .fiveMin: return rdHistoryShort
        case .hour:    return rdHistoryHour
        case .day:     return rdHistoryDay
        case .week:    return rdHistoryWeek
        }
    }
    func writeValues(for range: HistoryTimeRange) -> [Double] {
        switch range {
        case .fiveMin: return wrHistoryShort
        case .hour:    return wrHistoryHour
        case .day:     return wrHistoryDay
        case .week:    return wrHistoryWeek
        }
    }
}
