import AppKit

/// Lets a user enable the widgets from Settings: macOS lists widgets only for apps signed with a
/// developer certificate, so this re-signs the installed app with the user's own free
/// "Apple Development" certificate (via the bundled enable-widget.sh) and relaunches it.
enum WidgetSigner {
    enum Status {
        case enabled(String)        // signed with a developer certificate
        case certificateAvailable   // not yet, but a certificate exists – one click away
        case noCertificate          // the user needs Xcode + Apple ID first
    }

    static let xcodeURL = URL(string: "macappstore://apps.apple.com/app/id497799835")!

    private static func run(_ tool: String, _ args: [String]) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        guard (try? p.run()) != nil else { return "" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }

    /// The signing authority of the running app, if it has one (ad-hoc signatures have none).
    static func currentAuthority() -> String? {
        run("/usr/bin/codesign", ["-dv", "--verbose=2", Bundle.main.bundlePath])
            .split(separator: "\n")
            .first { $0.hasPrefix("Authority=") }
            .map { String($0.dropFirst("Authority=".count)) }
    }

    static func developerIdentity() -> String? {
        let out = run("/usr/bin/security", ["find-identity", "-v", "-p", "codesigning"])
        guard let r = out.range(of: #""Apple Development: [^"]+""#, options: .regularExpression) else { return nil }
        return String(out[r]).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
    }

    static func status() -> Status {
        if let a = currentAuthority() { return .enabled(a) }
        return developerIdentity() == nil ? .noCertificate : .certificateAvailable
    }

    /// Runs enable-widget.sh detached: it quits this app, re-signs it and opens it again.
    static func enable() throws {
        guard let script = Bundle.main.path(forResource: "enable-widget", ofType: "sh") else {
            throw NSError(domain: "MyZman", code: 1, userInfo: [NSLocalizedDescriptionKey: "הסקריפט חסר באפליקציה."])
        }
        let log = FileManager.default.temporaryDirectory.appendingPathComponent("myzman-enable-widget.log").path
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = ["-c", "nohup /bin/zsh \"$0\" \"$1\" > \"$2\" 2>&1 &", script, Bundle.main.bundlePath, log]
        try p.run()
    }
}
