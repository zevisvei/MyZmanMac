import AppKit
import CryptoKit
import Security
import os

/// Updates from the project's GitHub releases: checks once a day (and on demand), and installs a newer release
/// in place of the running app, then relaunches it.
///
/// The download is checked against the release's SHA256SUMS.txt and must be signed by the same certificate as
/// the running app (the project's release certificate), so a tampered download is never installed.
@MainActor
final class Updater: ObservableObject {
    static let shared = Updater()

    struct Release: Equatable {
        let version: String
        let zip: URL
        let sums: URL?
        let page: URL
    }

    enum State: Equatable {
        case idle, checking, upToDate, installing
        case available(Release)
        case failed(String)
        /// Installing the release failed; it can be downloaded by hand.
        case installFailed(Release, String)

        var error: String? {
            switch self {
            case .failed(let m), .installFailed(_, let m): return m
            default: return nil
            }
        }
    }

    @Published private(set) var state: State = .idle


    static let autoCheckKey = "autoCheckUpdates"
    private static let lastCheckKey = "lastUpdateCheck"
    private static let skippedKey = "skippedUpdateVersion"
    private static let api = URL(string: "https://api.github.com/repos/zevisvei/MyZmanMac/releases/latest")!
    static let releasesPage = URL(string: "https://github.com/zevisvei/MyZmanMac/releases/latest")!
    /// Releases are signed with this certificate (see scripts/setup-release-signing.sh). Used when the running
    /// app isn't itself signed with a certificate (an ad-hoc local build).
    private static let releaseRequirement = #"identifier "com.myzman.mac" and certificate leaf = H"2890bf4f5dc691450324a7beb7b39a11aefe54c9""#

    static let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"

    private let log = Logger(subsystem: "com.myzman.mac", category: "update")
    private var timer: Timer?

    /// The version offered in the popover: an available one the user didn't dismiss.
    var offered: Release? {
        guard case .available(let r) = state, r.version != UserDefaults.standard.string(forKey: Self.skippedKey) else { return nil }
        return r
    }

    func skip(_ release: Release) {
        UserDefaults.standard.set(release.version, forKey: Self.skippedKey)
        objectWillChange.send()
    }

    /// Hides a failed install's message (the update stays available in Settings).
    func dismissFailure() {
        if case .installFailed(let r, _) = state { state = .available(r) }
    }

    /// Only an installed app updates itself: not a bare `swift run` / debug binary, whose "bundle" is the build
    /// folder.
    static var canUpdate: Bool { Bundle.main.bundleURL.pathExtension == "app" }

    /// Checks a little after launch and then every few hours, at most once a day.
    func start() {
        UserDefaults.standard.register(defaults: [Self.autoCheckKey: true])
        guard Self.canUpdate else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in self?.checkIfDue() }
        timer = Timer.scheduledTimer(withTimeInterval: 6 * 3600, repeats: true) { _ in
            MainActor.assumeIsolated { Updater.shared.checkIfDue() }
        }
        timer?.tolerance = 600
    }

    private func checkIfDue() {
        let d = UserDefaults.standard
        guard d.bool(forKey: Self.autoCheckKey) else { return }
        guard Date().timeIntervalSince1970 - d.double(forKey: Self.lastCheckKey) > 20 * 3600 else { return }
        Task { await check(userInitiated: false) }
    }

    func check(userInitiated: Bool = true) async {
        guard Self.canUpdate else { return }
        switch state {
        case .checking, .installing: return
        default: break
        }
        state = .checking
        do {
            var req = URLRequest(url: Self.api, timeoutInterval: 30)
            req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            let (data, response) = try await URLSession.shared.data(for: req)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw UpdateError.server }
            let json = try JSONDecoder().decode(GitHubRelease.self, from: data)
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.lastCheckKey)
            let version = json.tag_name.hasPrefix("v") ? String(json.tag_name.dropFirst()) : json.tag_name
            guard Self.isNewer(version, than: Self.currentVersion) else {
                state = .upToDate
                return
            }
            guard let zip = json.assets.first(where: { $0.name == "MyZman.zip" })?.browser_download_url else {
                throw UpdateError.noAsset
            }
            let sums = json.assets.first { $0.name == "SHA256SUMS.txt" }?.browser_download_url
            state = .available(Release(version: version, zip: zip, sums: sums, page: json.html_url))
            log.info("update available: \(version, privacy: .public)")
        } catch {
            log.error("update check failed: \(error.localizedDescription, privacy: .public)")
            // A background check that fails (offline) isn't worth a red message nobody asked for.
            state = userInitiated ? .failed(Self.message(error)) : .idle
        }
    }

    /// Downloads, verifies and installs the release, then relaunches.
    func install(_ release: Release) async {
        guard Self.canUpdate, state != .installing else { return }
        state = .installing
        do {
            let target = Bundle.main.bundleURL
            let fm = FileManager.default
            // Run straight from the downloaded DMG or from a quarantined copy that was never moved: the app's
            // folder is read-only (or a random translocation folder), so it can't be replaced there.
            guard !target.path.contains("/AppTranslocation/"), !target.path.hasPrefix("/Volumes/"),
                  fm.isWritableFile(atPath: target.deletingLastPathComponent().path) else { throw UpdateError.location }
            // On the app's volume, so the new app can be swapped in without copying.
            let work = try fm.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: target, create: true)
            defer { try? fm.removeItem(at: work) }

            let (downloaded, response) = try await URLSession.shared.download(from: release.zip)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw UpdateError.server }
            let zip = work.appendingPathComponent("MyZman.zip")
            try fm.moveItem(at: downloaded, to: zip)

            if let sums = release.sums {
                let (data, _) = try await URLSession.shared.data(from: sums)
                let expected = String(decoding: data, as: UTF8.self).split(separator: "\n")
                    .first { $0.hasSuffix(" MyZman.zip") }?.split(separator: " ").first.map(String.init)
                let actual = try await Task.detached {
                    SHA256.hash(data: try Data(contentsOf: zip, options: .mappedIfSafe)).map { String(format: "%02x", $0) }.joined()
                }.value
                guard expected?.lowercased() == actual else { throw UpdateError.checksum }
            }

            try await Self.run("/usr/bin/ditto", ["-x", "-k", zip.path, work.path])
            let app = work.appendingPathComponent("MyZman.app")
            try Self.verifySignature(of: app)
            let newVersion = Bundle(url: app)?.infoDictionary?["CFBundleShortVersionString"] as? String
            guard newVersion == release.version else { throw UpdateError.version }

            _ = try fm.replaceItemAt(target, withItemAt: app)
            log.info("installed \(release.version, privacy: .public), relaunching")
            relaunch(target)
        } catch {
            log.error("update failed: \(error.localizedDescription, privacy: .public)")
            state = .installFailed(release, Self.message(error))
        }
    }

    /// Opens the app again once this process has quit.
    private func relaunch(_ app: URL) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "while /bin/kill -0 \(getpid()) 2>/dev/null; do /bin/sleep 0.2; done; /usr/bin/open \"$0\"", app.path]
        try? p.run()
        NSApp.terminate(nil)
    }

    // MARK: - Helpers

    /// "1.10.0" is newer than "1.9.2".
    nonisolated static func isNewer(_ a: String, than b: String) -> Bool {
        let x = a.split(separator: ".").map { Int($0) ?? 0 }, y = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(x.count, y.count) {
            let l = i < x.count ? x[i] : 0, r = i < y.count ? y[i] : 0
            if l != r { return l > r }
        }
        return false
    }

    /// The new app must be signed like the running one (same identifier and certificate), or with the release
    /// certificate: a copy re-signed locally to enable widgets has its own certificate, and releases don't.
    private static func verifySignature(of app: URL) throws {
        var requirements: [SecRequirement] = []
        var me: SecCode?, meStatic: SecStaticCode?, mine: SecRequirement?
        if SecCodeCopySelf([], &me) == errSecSuccess, let me, SecCodeCopyStaticCode(me, [], &meStatic) == errSecSuccess,
           let meStatic, SecCodeCopyDesignatedRequirement(meStatic, [], &mine) == errSecSuccess, let mine {
            var text: CFString?
            SecRequirementCopyString(mine, [], &text)
            // An ad-hoc build's requirement is its own hash, which no other build satisfies.
            if (text as String?)?.contains("certificate") == true { requirements.append(mine) }
        }
        var release: SecRequirement?
        if SecRequirementCreateWithString(releaseRequirement as CFString, [], &release) == errSecSuccess, let release {
            requirements.append(release)
        }
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess, let code else { throw UpdateError.signature }
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate | kSecCSCheckNestedCode)
        guard requirements.contains(where: { SecStaticCodeCheckValidity(code, flags, $0) == errSecSuccess }) else {
            throw UpdateError.signature
        }
    }

    private static func run(_ tool: String, _ args: [String]) async throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            p.terminationHandler = { p in
                p.terminationStatus == 0 ? c.resume() : c.resume(throwing: UpdateError.unzip)
            }
            do { try p.run() } catch { c.resume(throwing: error) }
        }
    }

    private static func message(_ error: Error) -> String {
        if let e = error as? UpdateError { return e.text }
        if (error as NSError).domain == NSCocoaErrorDomain, [513, 642].contains((error as NSError).code) {
            return "אין הרשאה להחליף את האפליקציה בתיקייה שבה היא נמצאת. הורידו את הגרסה החדשה מהאתר."
        }
        return error.localizedDescription
    }

    private enum UpdateError: Error {
        case server, noAsset, checksum, signature, unzip, version, location
        var text: String {
            switch self {
            case .server: return "לא ניתן להתחבר לשרת העדכונים."
            case .noAsset: return "בגרסה החדשה אין קובץ להתקנה."
            case .checksum: return "הקובץ שהורד פגום (בדיקת SHA-256 נכשלה)."
            case .signature: return "החתימה של הגרסה שהורדה אינה תואמת – העדכון לא הותקן."
            case .unzip: return "פתיחת הקובץ שהורד נכשלה."
            case .version: return "הקובץ שהורד אינו הגרסה שפורסמה – העדכון לא הותקן."
            case .location: return "כדי לעדכן, העבירו את זמנים לתיקיית היישומים (Applications) ופתחו אותה משם."
            }
        }
    }

    private struct GitHubRelease: Decodable {
        let tag_name: String
        let html_url: URL
        let assets: [Asset]
        struct Asset: Decodable { let name: String; let browser_download_url: URL }
    }
}
