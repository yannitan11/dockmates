import AppKit

final class AppController: NSObject, NSApplicationDelegate {
    private var overlay: OverlayController!
    private var statusItem: NSStatusItem!
    private var askPanel: AskPanel?
    private var answerPanel: AnswerPanel?
    private var stylePanel: StylePanel?
    private var routinePanel: RoutinePanel?
    private let scheduler = ReminderScheduler()

    func applicationDidFinishLaunching(_ notification: Notification) {
        overlay = OverlayController()
        overlay.onBuddyClicked = { [weak self] buddy in
            self?.openAsk(for: buddy)
        }
        overlay.onBuddyRightClicked = { [weak self] buddy in
            self?.openDressingRoom(for: buddy)
        }
        overlay.start()
        setupStatusItem()

        // A free buddy hops over and delivers each reminder; if everyone is
        // busy the scheduler retries on its next tick.
        scheduler.deliver = { [weak self] reminder in
            guard let self,
                  let buddy = self.overlay.buddies.first(where: { !$0.busy }) else {
                return false
            }
            buddy.celebrate()
            buddy.bubble.show(reminder.message, for: 12)
            return true
        }
        scheduler.start()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "sparkles",
                                   accessibilityDescription: "Dockmates")
        }

        let menu = NSMenu()
        let ask = NSMenuItem(title: "Ask Claude", action: #selector(askFromMenu), keyEquivalent: "a")
        ask.target = self
        menu.addItem(ask)

        let dress = NSMenuItem(title: "Dressing room", action: #selector(dressingRoomFromMenu), keyEquivalent: "d")
        dress.target = self
        menu.addItem(dress)

        let routines = NSMenuItem(title: "Routines", action: #selector(routinesFromMenu), keyEquivalent: "r")
        routines.target = self
        menu.addItem(routines)

        let pause = NSMenuItem(title: "Pause strolling", action: #selector(togglePause), keyEquivalent: "")
        pause.target = self
        menu.addItem(pause)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Dockmates", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
    }

    @objc private func askFromMenu() {
        openAsk(for: overlay.firstFreeBuddy())
    }

    @objc private func dressingRoomFromMenu() {
        openDressingRoom(for: overlay.buddies[0])
    }

    @objc private func routinesFromMenu() {
        let panel = routinePanel ?? RoutinePanel()
        routinePanel = panel
        panel.present(scheduler: scheduler,
                      near: overlay.screenPoint(above: overlay.firstFreeBuddy()))
    }

    private func openDressingRoom(for buddy: Buddy) {
        let panel = stylePanel ?? StylePanel()
        stylePanel = panel
        panel.onStyleChanged = { [weak self] in
            self?.saveStyles()
        }
        let index = overlay.buddies.firstIndex { $0 === buddy } ?? 0
        panel.present(buddies: overlay.buddies, selected: index,
                      near: overlay.screenPoint(above: buddy))
    }

    private func saveStyles() {
        let styles = overlay.buddies.map { $0.style }
        if let data = try? JSONEncoder().encode(styles) {
            UserDefaults.standard.set(data, forKey: "buddyStyles")
        }
    }

    @objc private func togglePause(_ sender: NSMenuItem) {
        overlay.strolling.toggle()
        sender.title = overlay.strolling ? "Pause strolling" : "Resume strolling"
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func openAsk(for buddy: Buddy) {
        let panel = askPanel ?? AskPanel()
        askPanel = panel
        panel.onSubmit = { [weak self] prompt in
            self?.startTask(prompt, buddy: buddy)
        }
        panel.present(above: overlay.screenPoint(above: buddy), listener: buddy.style.name)
    }

    private func startTask(_ prompt: String, buddy: Buddy) {
        // A reminder request is handled locally, no Claude CLI needed.
        if let reminder = ReminderParser.parse(prompt) {
            scheduler.add(reminder)
            buddy.hop()
            buddy.bubble.show("on it! " + reminder.scheduleText, for: 4.5)
            routinePanel?.refresh()
            return
        }

        answerPanel?.orderOut(nil)
        buddy.beginThinking()

        ClaudeRunner.run(prompt: prompt) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let text):
                buddy.celebrate()
                buddy.bubble.show("ta-da!", for: 2.5)
                let panel = AnswerPanel(buddyName: buddy.style.name, body: text)
                panel.present(above: self.overlay.screenPoint(above: buddy))
                self.answerPanel = panel
            case .failure(let error):
                buddy.stopBusy()
                buddy.bubble.show("hmm, that didn't work", for: 3)
                let panel = AnswerPanel(
                    buddyName: buddy.style.name,
                    body: "Something went wrong:\n\n" + error.localizedDescription
                )
                panel.present(above: self.overlay.screenPoint(above: buddy))
                self.answerPanel = panel
            }
        }
    }
}
