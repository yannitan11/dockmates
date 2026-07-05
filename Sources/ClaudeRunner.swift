import Foundation

enum ClaudeError: LocalizedError {
    case failed(String)

    var errorDescription: String? {
        if case .failed(let message) = self { return message }
        return nil
    }
}

/// Runs a prompt through a `claude` CLI off the main thread.
///
/// On Macs where Claude is used only through the desktop app there is no
/// logged-in command-line `claude`, so this can legitimately fail. When it
/// does we return a friendly explanation instead of a raw shell error.
enum ClaudeRunner {
    private static let notAvailableMessage = """
    I can't reach Claude from here.

    The "ask" feature shells out to the `claude` command-line tool, and it \
    isn't installed and logged in on this Mac (the Claude desktop app doesn't \
    count as a command-line login).

    Good news: reminders don't need it. Try typing something like:
      • drink water every 30 mins
      • stretch every 2 hours
      • exercise at 6pm

    To enable open-ended questions, install Claude Code as a CLI and run \
    `claude` once to log in, then reopen Dockmates.
    """

    static func run(prompt: String, completion: @escaping (Result<String, Error>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            guard let binary = locateBinary() else {
                DispatchQueue.main.async { completion(.failure(ClaudeError.failed(notAvailableMessage))) }
                return
            }

            let process = Process()
            process.executableURL = URL(fileURLWithPath: binary)
            process.arguments = ["-p", prompt]
            process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser

            var env = ProcessInfo.processInfo.environment
            env["PATH"] = (env["PATH"] ?? "") +
                ":/opt/homebrew/bin:/usr/local/bin:\(NSHomeDirectory())/.local/bin"
            process.environment = env

            let out = Pipe()
            let err = Pipe()
            process.standardOutput = out
            process.standardError = err

            do {
                try process.run()
            } catch {
                DispatchQueue.main.async { completion(.failure(ClaudeError.failed(notAvailableMessage))) }
                return
            }

            let timeout = DispatchWorkItem {
                if process.isRunning { process.terminate() }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + 300, execute: timeout)

            var outData = Data()
            var errData = Data()
            let group = DispatchGroup()
            group.enter()
            DispatchQueue.global().async {
                outData = out.fileHandleForReading.readDataToEndOfFile()
                group.leave()
            }
            group.enter()
            DispatchQueue.global().async {
                errData = err.fileHandleForReading.readDataToEndOfFile()
                group.leave()
            }
            group.wait()
            process.waitUntilExit()
            timeout.cancel()

            let stdout = String(data: outData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let stderr = String(data: errData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let combined = (stdout + " " + stderr).lowercased()

            DispatchQueue.main.async {
                if combined.contains("not logged in") || combined.contains("please run /login") {
                    completion(.failure(ClaudeError.failed(notAvailableMessage)))
                } else if process.terminationStatus == 0 && !stdout.isEmpty {
                    completion(.success(stdout))
                } else if !stderr.isEmpty {
                    completion(.failure(ClaudeError.failed(stderr)))
                } else {
                    completion(.failure(ClaudeError.failed(notAvailableMessage)))
                }
            }
        }
    }

    /// Find a usable `claude` executable: a real one on PATH first, then the
    /// binary bundled inside the Claude desktop app as a last resort.
    private static func locateBinary() -> String? {
        // 1. A login shell knows about PATH-installed CLIs (npm, homebrew, etc.)
        let probe = Process()
        probe.executableURL = URL(fileURLWithPath: "/bin/zsh")
        probe.arguments = ["-lc", "command -v claude"]
        let pipe = Pipe()
        probe.standardOutput = pipe
        probe.standardError = Pipe()
        if (try? probe.run()) != nil {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            probe.waitUntilExit()
            if let path = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !path.isEmpty, FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }

        // 2. The desktop app bundles claude-code under a versioned folder.
        let base = "\(NSHomeDirectory())/Library/Application Support/Claude/claude-code"
        if let versions = try? FileManager.default.contentsOfDirectory(atPath: base) {
            let sorted = versions.sorted { $0.compare($1, options: .numeric) == .orderedDescending }
            for version in sorted {
                let candidate = "\(base)/\(version)/claude.app/Contents/MacOS/claude"
                if FileManager.default.isExecutableFile(atPath: candidate) {
                    return candidate
                }
            }
        }

        return nil
    }
}
