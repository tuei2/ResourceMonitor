import Foundation

struct ProcessStat: Identifiable, Equatable {
    let id: Int32   // pid
    let name: String
    let cpuPercent: Double
    let ramMB: Double
    var diskReadMBps: Double = 0
    var diskWriteMBps: Double = 0
    var netDLMBps: Double = 0
    var netULMBps: Double = 0
    var energyImpact: Double = 0
    var gpuPercent: Double = 0
}
