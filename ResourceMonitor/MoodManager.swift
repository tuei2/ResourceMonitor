import Foundation

// MARK: - Mood definition

enum Mood: String, CaseIterable {
    case dead
    case angry
    case hot
    case crying
    case stressed
    case inLove
    case sleepy
    case party
    case happy

    var emoji: String {
        switch self {
        case .dead:     return "💀"
        case .angry:    return "😡"
        case .hot:      return "🥵"
        case .crying:   return "😭"
        case .stressed: return "😤"
        case .inLove:   return "🥰"
        case .sleepy:   return "😴"
        case .party:    return "🥳"
        case .happy:    return "😊"
        }
    }

    var title: String {
        switch self {
        case .dead:     return "Deceased"
        case .angry:    return "Furious"
        case .hot:      return "Overheating"
        case .crying:   return "Desperate"
        case .stressed: return "Stressed"
        case .inLove:   return "In Love"
        case .sleepy:   return "Napping"
        case .party:    return "Partying"
        case .happy:    return "Vibing"
        }
    }

    var headline: String {
        switch self {
        case .dead:     return "Your Mac has left the building."
        case .angry:    return "One more process and someone's getting fired."
        case .hot:      return "Your Mac is sweating. Literally."
        case .crying:   return "The battery is writing its will."
        case .stressed: return "Fine. Everything is completely fine."
        case .inLove:   return "Charging and feeling cute."
        case .sleepy:   return "Shhh. Do not disturb."
        case .party:    return "Full battery. Zero stress. Let's go."
        case .happy:    return "All systems nominal. Don't ruin it."
        }
    }

    var diagnosis: String {
        switch self {
        case .dead:
            return "CPU and RAM are both at maximum occupancy. Your Mac is performing a dramatic one-act play called 'Too Much To Do, Too Little Silicon'."
        case .angry:
            return "Something is chewing through resources like it owns the place. Your fans are considering filing a formal complaint with HR."
        case .hot:
            return "The thermals are… ambitious. Your Mac is currently hotter than the inside of a car in August, and significantly less pleasant."
        case .crying:
            return "Battery critically low. Your Mac is not panicking. You should be panicking. Please plug something in before we have a situation."
        case .stressed:
            return "CPU and RAM are both giving it their all. They're managing. They'd appreciate if you'd stop opening new tabs, though."
        case .inLove:
            return "Plugged in and charging. The electrons are flowing. The fans are quiet. Your Mac is basically on a spa day."
        case .sleepy:
            return "CPU usage is so low it's practically philosophical. Your Mac is technically on, but emotionally somewhere far away."
        case .party:
            return "100% battery, low CPU, no drama. This is the dream. Screenshot this. Frame it. Remember what it felt like."
        case .happy:
            return "Everything is operating within acceptable parameters. CPU is calm, RAM has space, and no one is overheating. Enjoy it while it lasts."
        }
    }

    var prescription: String {
        switch self {
        case .dead:     return "Rx: Close literally everything. Immediately."
        case .angry:    return "Rx: Open Activity Monitor and start making cuts."
        case .hot:      return "Rx: Find a cool surface. Not a blanket. Never a blanket."
        case .crying:   return "Rx: Charger. Now. Run, don't walk."
        case .stressed: return "Rx: Maybe close that tab you opened three weeks ago."
        case .inLove:   return "Rx: Keep it plugged in. You're doing great."
        case .sleepy:   return "Rx: No action required. Let it rest."
        case .party:    return "Rx: Vibe responsibly."
        case .happy:    return "Rx: Continue current behavior. Don't jinx it."
        }
    }

    // What's driving this mood — short stat label
    var triggerLabel: String {
        switch self {
        case .dead:     return "CPU or RAM critical"
        case .angry:    return "CPU or RAM very high"
        case .hot:      return "Temperature exceeded"
        case .crying:   return "Battery critical"
        case .stressed: return "CPU or RAM elevated"
        case .inLove:   return "Charging"
        case .sleepy:   return "Very low activity"
        case .party:    return "100% charged, low load"
        case .happy:    return "Everything nominal"
        }
    }
}

// MARK: - MoodManager

final class MoodManager {
    static let shared = MoodManager()
    private init() {}

    func currentMood(cpu: Double, ramPct: Double, battery: BatteryMonitor,
                     tempMax: Double, settings: AppSettings) -> Mood {
        let tempWarn = settings.tempAlertThreshold

        if cpu > 95 || ramPct > 95                          { return .dead }
        if cpu > 80 || ramPct > 85                          { return .angry }
        if tempMax >= tempWarn                              { return .hot }
        if battery.percent < 15 && !battery.isPluggedIn    { return .crying }
        if cpu > 50 || ramPct > 70                         { return .stressed }
        if battery.isCharging && battery.percent < 100     { return .inLove }
        if battery.percent == 100 && !battery.isPluggedIn && cpu < 20 { return .party }
        if cpu < 10 && ramPct < 50                         { return .sleepy }
        return .happy
    }
}
