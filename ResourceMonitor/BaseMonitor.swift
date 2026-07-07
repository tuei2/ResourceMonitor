import Foundation

protocol Monitor: AnyObject {
    func start(interval: Double)
    func stop()
}

extension Monitor {
    func start() { start(interval: 2.0) }
}

// Shared helper — runs a command and returns stdout as String.
// Kills the process and returns "" if it doesn't finish within `timeout` seconds,
// preventing a hung subprocess from blocking the dispatch queue indefinitely.
func shellOutput(_ path: String, _ args: [String], timeout: TimeInterval = 8.0) -> String {
    let task = Process()
    task.launchPath = path
    task.arguments  = args
    let outPipe = Pipe()
    task.standardOutput = outPipe
    task.standardError  = Pipe()

    do { try task.run() } catch { return "" }

    let done = DispatchSemaphore(value: 0)
    DispatchQueue.global(qos: .utility).async {
        task.waitUntilExit()
        done.signal()
    }

    guard done.wait(timeout: .now() + timeout) == .success else {
        task.terminate()
        return ""
    }

    return String(data: outPipe.fileHandleForReading.readDataToEndOfFile(),
                  encoding: .utf8) ?? ""
}
