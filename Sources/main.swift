import AppKit

// Design-review mode: render the buddies to a PNG and exit.
// Usage: Dockmates --snapshot /path/to/out.png
if let index = CommandLine.arguments.firstIndex(of: "--snapshot"),
   CommandLine.arguments.count > index + 1 {
    SnapshotRenderer.write(to: CommandLine.arguments[index + 1])
    exit(0)
}
if let index = CommandLine.arguments.firstIndex(of: "--snapshot-dressing-room"),
   CommandLine.arguments.count > index + 1 {
    let juno = Buddy(style: .juno, scale: 2, feetY: 8)
    let bo = Buddy(style: .bo, scale: 2, feetY: 8)
    let panel = StylePanel()
    panel.snapshotFullContent(buddies: [juno, bo], to: CommandLine.arguments[index + 1])
    exit(0)
}
// Debug: fetch and print the live weather summary, to confirm the real
// fetch + parse works from the compiled app before relying on it.
if CommandLine.arguments.contains("--test-weather") {
    WeatherService.shared.start()
    let deadline = Date().addingTimeInterval(15)
    let timer = Timer(timeInterval: 0.5, repeats: true) { _ in
        if let s = WeatherService.shared.summary {
            print("weather summary: \(s)")
            exit(0)
        }
        if Date() > deadline {
            print("weather summary: (nil - fetch failed or timed out)")
            exit(1)
        }
    }
    RunLoop.main.add(timer, forMode: .common)
    RunLoop.main.run(until: deadline.addingTimeInterval(1))
    exit(1)
}

// Debug: force two buddies into a greeting exchange repeatedly and log their
// bubble text over a few seconds, to confirm the question/answer sequencing
// actually fires (not just compiles) before shipping.
if CommandLine.arguments.contains("--test-conversation") {
    let overlay = OverlayController()
    overlay.start()
    // lastGreetAt already defaults to 0, which trivially satisfies the 90s
    // cooldown for a freshly-created buddy, so simply starting them close
    // together is enough to trigger exactly one exchange without needing to
    // force anything mid-run.
    overlay.buddies[0].x = 200
    overlay.buddies[1].x = 210
    var lastLine: [String: String] = [:]
    let timer = Timer(timeInterval: 0.1, repeats: true) { _ in
        for buddy in overlay.buddies where buddy.bubble.visible {
            if lastLine[buddy.style.name] != buddy.bubble.text {
                lastLine[buddy.style.name] = buddy.bubble.text
                print(String(format: "%.2fs  %@: %@", Date().timeIntervalSince1970, buddy.style.name, buddy.bubble.text))
            }
        }
    }
    RunLoop.main.add(timer, forMode: .common)
    RunLoop.main.run(until: Date().addingTimeInterval(5))
    exit(0)
}

if let index = CommandLine.arguments.firstIndex(of: "--snapshot-rain"),
   CommandLine.arguments.count > index + 1 {
    SnapshotRenderer.writeRain(to: CommandLine.arguments[index + 1])
    exit(0)
}
if let index = CommandLine.arguments.firstIndex(of: "--snapshot-walk"),
   CommandLine.arguments.count > index + 1 {
    SnapshotRenderer.writeWalk(to: CommandLine.arguments[index + 1])
    exit(0)
}
if let index = CommandLine.arguments.firstIndex(of: "--snapshot-shoulder"),
   CommandLine.arguments.count > index + 1 {
    SnapshotRenderer.writeShoulderZoom(to: CommandLine.arguments[index + 1])
    exit(0)
}
if let index = CommandLine.arguments.firstIndex(of: "--snapshot-wave"),
   CommandLine.arguments.count > index + 1 {
    SnapshotRenderer.writeWave(to: CommandLine.arguments[index + 1])
    exit(0)
}
if let index = CommandLine.arguments.firstIndex(of: "--snapshot-hats"),
   CommandLine.arguments.count > index + 1 {
    SnapshotRenderer.writeHats(to: CommandLine.arguments[index + 1])
    exit(0)
}
if let index = CommandLine.arguments.firstIndex(of: "--snapshot-closeup"),
   CommandLine.arguments.count > index + 1 {
    SnapshotRenderer.writeCloseup(to: CommandLine.arguments[index + 1])
    exit(0)
}
if let index = CommandLine.arguments.firstIndex(of: "--snapshot-routines"),
   CommandLine.arguments.count > index + 1 {
    SnapshotRenderer.writeRoutinePanel(to: CommandLine.arguments[index + 1])
    exit(0)
}

// Debug: check how free text parses into a reminder.
// Usage: Dockmates --parse "remind me to drink water every 30 mins"
if let index = CommandLine.arguments.firstIndex(of: "--parse"),
   CommandLine.arguments.count > index + 1 {
    let input = CommandLine.arguments[index + 1]
    if let r = ReminderParser.parse(input) {
        print("REMINDER  message=\"\(r.message)\"  schedule=\(r.scheduleText)")
    } else {
        print("NOT A REMINDER (would go to Claude): \"\(input)\"")
    }
    exit(0)
}

let app = NSApplication.shared
let controller = AppController()
app.delegate = controller
app.setActivationPolicy(.accessory)
app.run()
