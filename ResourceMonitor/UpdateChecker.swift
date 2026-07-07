import AppKit
import Foundation

/// Checks the GitHub Releases API for a newer version and offers to open the
/// release page. No auto-download — the user reviews and installs manually.
final class UpdateChecker {
    static let shared = UpdateChecker()
    private init() {}

    /// GitHub repository that hosts the releases.
    private let owner = "tuei2"
    private let repo  = "ResourceMonitor"

    private let lastCheckKey = "lastUpdateCheck"
    private let skippedVersionKey = "skippedUpdateVersion"

    private var latestURL: URL {
        URL(string: "https://api.github.com/repos/\(owner)/\(repo)/releases/latest")!
    }

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    // MARK: - Public API

    /// Called on launch. Checks at most once every 24h and stays silent unless a
    /// newer, non-skipped version exists.
    func checkInBackgroundIfDue() {
        let last = UserDefaults.standard.object(forKey: lastCheckKey) as? Date ?? .distantPast
        guard Date().timeIntervalSince(last) > 86_400 else { return }
        check(userInitiated: false)
    }

    /// Called from the "Check for updates" button. Always reports the result.
    func checkNow() {
        check(userInitiated: true)
    }

    // MARK: - Core

    private func check(userInitiated: Bool) {
        UserDefaults.standard.set(Date(), forKey: lastCheckKey)

        var request = URLRequest(url: latestURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self else { return }

            guard let data,
                  let http = response as? HTTPURLResponse,
                  http.statusCode == 200,
                  let release = try? JSONDecoder().decode(GitHubRelease.self, from: data) else {
                if userInitiated {
                    DispatchQueue.main.async {
                        self.presentInfo(title: "Update check failed",
                                         message: "Could not reach GitHub. Please try again later.")
                    }
                }
                return
            }

            let latest = release.tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
            let isNewer = Self.compareVersions(latest, self.currentVersion) == .orderedDescending

            DispatchQueue.main.async {
                if isNewer {
                    if !userInitiated,
                       UserDefaults.standard.string(forKey: self.skippedVersionKey) == latest {
                        return  // user chose to skip this version
                    }
                    self.presentUpdate(version: latest, release: release)
                } else if userInitiated {
                    self.presentInfo(title: "You're up to date",
                                     message: "ResourceMonitor \(self.currentVersion) is the latest version.")
                }
            }
        }.resume()
    }

    // MARK: - UI

    private func presentUpdate(version: String, release: GitHubRelease) {
        let alert = NSAlert()
        alert.messageText = "ResourceMonitor \(version) is available"
        alert.informativeText = release.body?.isEmpty == false
            ? release.body! : "You have \(currentVersion). Version \(version) is now available on GitHub."
        alert.addButton(withTitle: "Download")
        alert.addButton(withTitle: "Skip This Version")
        alert.addButton(withTitle: "Later")

        NSApp.activate(ignoringOtherApps: true)
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            if let url = URL(string: release.htmlURL) { NSWorkspace.shared.open(url) }
        case .alertSecondButtonReturn:
            UserDefaults.standard.set(version, forKey: skippedVersionKey)
        default:
            break
        }
    }

    private func presentInfo(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    // MARK: - Version comparison

    /// Compares dotted numeric versions ("1.2.0" vs "1.10"). Missing components
    /// count as zero, so "1.2" == "1.2.0".
    static func compareVersions(_ a: String, _ b: String) -> ComparisonResult {
        let ac = a.split(separator: ".").map { Int($0) ?? 0 }
        let bc = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(ac.count, bc.count) {
            let av = i < ac.count ? ac[i] : 0
            let bv = i < bc.count ? bc[i] : 0
            if av != bv { return av < bv ? .orderedAscending : .orderedDescending }
        }
        return .orderedSame
    }
}

// MARK: - GitHub API model

private struct GitHubRelease: Decodable {
    let tagName: String
    let htmlURL: String
    let body: String?

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case body
    }
}
