import Foundation

enum ClaudeError: LocalizedError {
    case failed(String)

    var errorDescription: String? {
        if case .failed(let message) = self { return message }
        return nil
    }
}

/// Runs a prompt through the `claude` CLI (`claude -p`) off the main thread.
enum ClaudeRunner {
    static func run(prompt: String, completion: @escaping (Result<String, Error>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let quoted = "'" + prompt.replacingOccurrences(of: "'", with: "'\\''") + "'"
            let command = """
            export PATH="$PATH:/opt/homebrew/bin:/usr/local/bin:$HOME/.local/bin:$HOME/.claude/local"
            claude -p \(quoted)
            """

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-lc", command]
            process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser

            let out = Pipe()
            let err = Pipe()
            process.standardOutput = out
            process.standardError = err

            do {
                try process.run()
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }

            // Kill runaway tasks after 5 minutes
            let timeout = DispatchWorkItem {
                if process.isRunning { process.terminate() }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + 300, execute: timeout)

            // Drain both pipes concurrently to avoid buffer deadlock
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

            DispatchQueue.main.async {
                if process.terminationStatus == 0 && !stdout.isEmpty {
                    completion(.success(stdout))
                } else {
                    var message = stderr.isEmpty ? stdout : stderr
                    if message.isEmpty {
                        message = "Claude didn't answer. Is the claude CLI installed and signed in?"
                    }
                    completion(.failure(ClaudeError.failed(message)))
                }
            }
        }
    }
}
