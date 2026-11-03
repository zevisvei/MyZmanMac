import AppKit

/// macOS lists widgets only for apps with a certificate-based signature (official releases have one).
/// For an ad-hoc signed copy – e.g. built from source – this re-signs the installed app via the
/// bundled enable-widget.sh, which creates a local self-signed certificate if needed, and relaunches it.
enum WidgetSigner {
    enum Status {
        case enabled(String)  // signed with a certificate: widgets are available
        case adHoc            // one click away
    }

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

    static func status() -> Status {
        currentAuthority().map(Status.enabled) ?? .adHoc
    }

    /// Runs enable-widget.sh: first its checks and the certificate (an error shows in the window), then, detached,
    /// the part that quits this app, re-signs it and opens it again.
    static func enable() async throws {
        guard let script = Bundle.main.path(forResource: "enable-widget", ofType: "sh") else {
            throw NSError(domain: "MyZman", code: 1, userInfo: [NSLocalizedDescriptionKey: "הסקריפט חסר באפליקציה."])
        }
        let (ok, output) = await Task.detached {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/bin/zsh")
            p.arguments = [script, Bundle.main.bundlePath, "--prepare"]
            let pipe = Pipe()
            p.standardOutput = pipe
            p.standardError = pipe
            guard (try? p.run()) != nil else { return (false, "") }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            return (p.terminationStatus == 0, String(decoding: data, as: UTF8.self))
        }.value
        guard ok else {
            let message = output.split(separator: "\n").last { $0.hasPrefix("✗") }.map(String.init) ?? output
            throw NSError(domain: "MyZman", code: 2, userInfo: [NSLocalizedDescriptionKey: message.isEmpty ? "החתימה נכשלה." : message])
        }
        let log = FileManager.default.temporaryDirectory.appendingPathComponent("myzman-enable-widget.log").path
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = ["-c", "nohup /bin/zsh \"$0\" \"$1\" > \"$2\" 2>&1 &", script, Bundle.main.bundlePath, log]
        try p.run()
    }
}
