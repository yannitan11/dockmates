import Foundation

enum ClaudeEvent {
    /// A session finished a turn. `project` is the basename of the session's
    /// working directory when the Stop hook logged it (older hook formats
    /// didn't, so it can be nil).
    case done(project: String?)
    case needsPermission
    case waiting
}

/// Tails `~/.dockmates/events.log`, which Claude Code's Stop and Notification
/// hooks append to, and reports new events. Pre-existing lines are ignored so
/// only things that happen after launch trigger a nudge.
final class ClaudeWatcher {
    private let path: String
    private var offset: UInt64 = 0
    private var timer: Timer?
    var onEvent: ((ClaudeEvent) -> Void)?

    init() {
        path = "\(NSHomeDirectory())/.dockmates/events.log"
    }

    func start() {
        offset = currentSize()
        let timer = Timer(timeInterval: 1.5, repeats: true) { [weak self] _ in
            self?.poll()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func currentSize() -> UInt64 {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let size = attrs[.size] as? NSNumber else { return 0 }
        return size.uint64Value
    }

    private func poll() {
        let size = currentSize()
        if size == offset { return }
        if size < offset { offset = size; return }  // file was rotated/truncated
        guard let handle = FileHandle(forReadingAtPath: path) else { return }
        defer { try? handle.close() }
        do {
            try handle.seek(toOffset: offset)
            let data = handle.readDataToEndOfFile()
            offset = size
            guard let text = String(data: data, encoding: .utf8) else { return }
            for line in text.split(separator: "\n") {
                parse(String(line))
            }
        } catch {
            offset = size
        }
    }

    private func parse(_ line: String) {
        let parts = line.components(separatedBy: "\t")
        guard let type = parts.first else { return }
        switch type {
        case "stop":
            let project = parts.count > 2
                ? parts[2].trimmingCharacters(in: .whitespaces)
                : ""
            onEvent?(.done(project: project.isEmpty ? nil : project))
        case "notify":
            let rest = parts.dropFirst(2).joined(separator: " ").lowercased()
            onEvent?(rest.contains("permission") ? .needsPermission : .waiting)
        default:
            break
        }
    }
}
