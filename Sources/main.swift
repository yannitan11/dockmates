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
