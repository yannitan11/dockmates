import AppKit

final class AppController: NSObject, NSApplicationDelegate {
    private var overlay: OverlayController!
    private var statusItem: NSStatusItem!
    private var askPanel: AskPanel?
    private var answerPanel: AnswerPanel?
    private var stylePanel: StylePanel?
    private var routinePanel: RoutinePanel?

    // Which buddy each open panel is anchored to, so it can be repositioned
    // as that buddy wanders or gets dragged instead of being left behind.
    private var askBuddy: Buddy?
    private var answerBuddy: Buddy?
    private var styleBuddy: Buddy?
    private let scheduler = ReminderScheduler()

    private let watcher = ClaudeWatcher()
    private let notifier = Notifier()
    private let claudeBundleID = "com.anthropic.claudefordesktop"
    private var watchClaude = UserDefaults.standard.object(forKey: "watchClaude") as? Bool ?? true
    private var lastNudgeAt: TimeInterval = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        // First run ever: turn on "launch at login" by default so Dockmates
        // shows up automatically next time the Mac starts. After that we
        // leave it alone and respect whatever the user sets in the menu.
        if !UserDefaults.standard.bool(forKey: "loginItemBootstrapped") {
            UserDefaults.standard.set(true, forKey: "loginItemBootstrapped")
            LoginItem.setEnabled(true)
        }

        overlay = OverlayController()
        overlay.onBuddyClicked = { [weak self] buddy in
            self?.openAsk(for: buddy)
        }
        overlay.onBuddyRightClicked = { [weak self] buddy in
            // The pet isn't dressable; right-clicking it just gets a reaction.
            if buddy.isCat {
                self?.overlay.petReaction(buddy)
            } else {
                self?.openDressingRoom(for: buddy)
            }
        }
        overlay.onTick = { [weak self] in
            self?.trackPanels()
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

        // Watch Claude Code: nudge when a session finishes or needs the user,
        // but only when they've tabbed away from the Claude app.
        notifier.requestAuthorization()
        watcher.onEvent = { [weak self] event in
            self?.handleClaudeEvent(event)
        }
        watcher.start()

        // Keep real local weather cached so buddy weather-chat is accurate.
        WeatherService.shared.start()
    }

    private func handleClaudeEvent(_ event: ClaudeEvent) {
        guard watchClaude else { return }

        // Stay quiet while the user is already looking at Claude.
        if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == claudeBundleID { return }

        let now = CACurrentMediaTime()
        if now - lastNudgeAt < 3 { return }  // debounce bursts
        lastNudgeAt = now

        let bubble: String
        let title: String
        let body: String
        switch event {
        case .done:
            bubble = "Claude's all done!"
            title = "Claude Code finished"
            body = "Your task wrapped up. Head back when you're ready."
        case .needsPermission:
            bubble = "Claude needs your OK"
            title = "Claude Code needs permission"
            body = "Claude is waiting for you to approve something."
        case .waiting:
            bubble = "Claude's waiting for you"
            title = "Claude Code is waiting"
            body = "Claude needs your input to keep going."
        }

        // A pet delivering the nudge is fine and cute, but always post the
        // system notification even if the dock is empty.
        if let buddy = overlay.firstFreeBuddy() {
            buddy.celebrate()
            buddy.bubble.show(bubble, for: 18)
        }
        notifier.post(title: title, body: body)
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

        // "On the dock" submenu: check on/off each possible dockmate.
        let dockmatesMenu = NSMenu()
        for style in overlay.rosterStyles {
            let label = style.species == .cat ? "\(style.name) (cat)" : style.name
            let item = NSMenuItem(title: label, action: #selector(toggleDockmate(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = style.name
            item.state = overlay.isVisible(style.name) ? .on : .off
            dockmatesMenu.addItem(item)
        }
        let dockmates = NSMenuItem(title: "On the dock", action: nil, keyEquivalent: "")
        dockmates.submenu = dockmatesMenu
        menu.addItem(dockmates)

        menu.addItem(.separator())
        let watch = NSMenuItem(title: "Notify me about Claude Code",
                               action: #selector(toggleWatchClaude), keyEquivalent: "")
        watch.target = self
        watch.state = watchClaude ? .on : .off
        menu.addItem(watch)

        let pause = NSMenuItem(title: "Pause strolling", action: #selector(togglePause), keyEquivalent: "")
        pause.target = self
        menu.addItem(pause)

        let login = NSMenuItem(title: "Start at Login", action: #selector(toggleLoginItem), keyEquivalent: "")
        login.target = self
        login.state = LoginItem.isEnabled ? .on : .off
        menu.addItem(login)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Dockmates", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
    }

    @objc private func askFromMenu() {
        guard let buddy = overlay.firstFreePerson() else { return }
        openAsk(for: buddy)
    }

    @objc private func toggleDockmate(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        let makeVisible = sender.state == .off
        overlay.setVisible(name, makeVisible)
        sender.state = makeVisible ? .on : .off
    }

    @objc private func dressingRoomFromMenu() {
        guard let person = overlay.buddies.first(where: { !$0.isCat }) else { return }
        openDressingRoom(for: person)
    }

    @objc private func routinesFromMenu() {
        let anchor = overlay.firstFreeBuddy().map { overlay.screenPoint(above: $0) }
            ?? NSPoint(x: (NSScreen.main?.frame.midX ?? 400), y: 120)
        let panel = routinePanel ?? RoutinePanel()
        routinePanel = panel
        panel.present(scheduler: scheduler, near: anchor)
    }

    private func openDressingRoom(for buddy: Buddy) {
        styleBuddy = buddy
        let panel = stylePanel ?? StylePanel()
        stylePanel = panel
        panel.onStyleChanged = { [weak self] in
            self?.saveStyles()
        }
        // The dressing room only edits people; the pet has a fixed look.
        let people = overlay.buddies.filter { !$0.isCat }
        let index = people.firstIndex { $0 === buddy } ?? 0
        panel.present(buddies: people, selected: index,
                      near: overlay.screenPoint(above: buddy))
    }

    /// Keeps any open, buddy-anchored panel glued above its buddy as that
    /// buddy wanders, gets dragged, or paces while thinking, instead of
    /// leaving the panel stranded at wherever it was first opened.
    private func trackPanels() {
        if let panel = askPanel, panel.isVisible, let buddy = askBuddy {
            reposition(panel, near: buddy)
        }
        if let panel = answerPanel, panel.isVisible, let buddy = answerBuddy {
            reposition(panel, near: buddy)
        }
        if let panel = stylePanel, panel.isVisible, let buddy = styleBuddy {
            reposition(panel, near: buddy)
        }
    }

    private func reposition(_ panel: NSPanel, near buddy: Buddy) {
        let point = overlay.screenPoint(above: buddy)
        var origin = NSPoint(x: point.x - panel.frame.width / 2, y: point.y + 10)
        if let screen = NSScreen.screens.first {
            let vf = screen.visibleFrame
            origin.x = max(vf.minX + 12, min(origin.x, vf.maxX - panel.frame.width - 12))
            origin.y = min(origin.y, vf.maxY - panel.frame.height - 12)
            origin.y = max(origin.y, vf.minY + 12)
        }
        panel.setFrameOrigin(origin)
    }

    private func saveStyles() {
        // Persist the whole roster (including hidden members' last-known
        // styles), pulling in live edits first.
        overlay.syncRosterFromBuddies()
        if let data = try? JSONEncoder().encode(overlay.rosterStyles) {
            UserDefaults.standard.set(data, forKey: "buddyStyles")
        }
    }

    @objc private func togglePause(_ sender: NSMenuItem) {
        overlay.strolling.toggle()
        sender.title = overlay.strolling ? "Pause strolling" : "Resume strolling"
    }

    @objc private func toggleWatchClaude(_ sender: NSMenuItem) {
        watchClaude.toggle()
        sender.state = watchClaude ? .on : .off
        UserDefaults.standard.set(watchClaude, forKey: "watchClaude")
    }

    @objc private func toggleLoginItem(_ sender: NSMenuItem) {
        let wantsEnabled = LoginItem.isEnabled == false
        if LoginItem.setEnabled(wantsEnabled) {
            sender.state = wantsEnabled ? .on : .off
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func openAsk(for buddy: Buddy) {
        askBuddy = buddy
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
                self.answerBuddy = buddy
            case .failure(let error):
                buddy.stopBusy()
                buddy.bubble.show("hmm, that didn't work", for: 3)
                let panel = AnswerPanel(
                    buddyName: buddy.style.name,
                    body: "Something went wrong:\n\n" + error.localizedDescription
                )
                panel.present(above: self.overlay.screenPoint(above: buddy))
                self.answerPanel = panel
                self.answerBuddy = buddy
            }
        }
    }
}
