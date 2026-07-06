import Foundation

enum ClaudeError: LocalizedError {
    case failed(String)

    var errorDescription: String? {
        if case .failed(let message) = self { return message }
        return nil
    }
}

/// A single reply from the `claude` CLI, plus the session id needed to
/// continue the same conversation on a follow-up call via `--resume`.
struct ClaudeReply {
    let text: String
    let sessionId: String
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

    /// Runs `prompt`, optionally continuing a prior conversation via
    /// `--resume`. If a `sessionId` is given but the CLI reports it can't
    /// find that session (e.g. it expired), retries once as a fresh
    /// conversation instead of surfacing that as an error.
    static func run(prompt: String, resuming sessionId: String? = nil,
                     completion: @escaping (Result<ClaudeReply, Error>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            guard let binary = locateBinary() else {
                DispatchQueue.main.async { completion(.failure(ClaudeError.failed(notAvailableMessage))) }
                return
            }

            let (stdout, stderr, status) = invoke(binary: binary, prompt: prompt, resuming: sessionId)
            let combined = (stdout + " " + stderr).lowercased()

            if sessionId != nil && combined.contains("no conversation found") {
                let (stdout2, stderr2, status2) = invoke(binary: binary, prompt: prompt, resuming: nil)
                finish(stdout: stdout2, stderr: stderr2, status: status2, completion: completion)
                return
            }

            finish(stdout: stdout, stderr: stderr, status: status, completion: completion)
        }
    }

    private static func invoke(binary: String, prompt: String, resuming sessionId: String?)
        -> (stdout: String, stderr: String, status: Int32) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        var args = ["-p", prompt, "--output-format", "json"]
        if let sessionId { args += ["--resume", sessionId] }
        process.arguments = args
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
            return ("", "", -1)
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
        return (stdout, stderr, process.terminationStatus)
    }

    private static func finish(stdout: String, stderr: String, status: Int32,
                                completion: @escaping (Result<ClaudeReply, Error>) -> Void) {
        let combined = (stdout + " " + stderr).lowercased()

        DispatchQueue.main.async {
            if combined.contains("not logged in") || combined.contains("please run /login") {
                completion(.failure(ClaudeError.failed(notAvailableMessage)))
                return
            }

            if let data = stdout.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let result = json["result"] as? String,
               let sessionId = json["session_id"] as? String {
                let isError = json["is_error"] as? Bool ?? false
                if isError {
                    completion(.failure(ClaudeError.failed(result)))
                } else {
                    completion(.success(ClaudeReply(text: result, sessionId: sessionId)))
                }
                return
            }

            if status == 0 && !stdout.isEmpty {
                completion(.failure(ClaudeError.failed(stdout)))
            } else if !stderr.isEmpty {
                completion(.failure(ClaudeError.failed(stderr)))
            } else {
                completion(.failure(ClaudeError.failed(notAvailableMessage)))
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
