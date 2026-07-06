import AppKit

/// One remembered ask: the question, Claude's answer, and the CLI session id
/// so reopening it from the menu can continue the same conversation.
struct RecentAnswer: Codable {
    let prompt: String
    let text: String
    let sessionId: String
}

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

    // The `claude` CLI session backing the current answer panel's
    // conversation, so follow-up replies continue it via `--resume`.
    private var answerSessionId: String?

    // Last few asks + answers, reopenable from the menu bar. Persisted so
    // they survive an app restart.
    private var recentAnswers: [RecentAnswer] = []
    private let recentAnswersKey = "recentAnswers"
    private let recentAnswersCap = 10
    private let recentAnswersMenu = NSMenu()

    private let watcher = ClaudeWatcher()
    private let notifier = Notifier()
    private let claudeBundleID = "com.anthropic.claudefordesktop"
    private var watchClaude = UserDefaults.standard.object(forKey: "watchClaude") as? Bool ?? true
    private var lastNudgeAt: TimeInterval = 0

    // How many sessions have finished since the user last checked in, shown
    // as a little badge on the buddy that delivered the latest nudge. Cleared
    // when the Claude app comes to the front or any buddy is clicked.
    private var unattendedCount = 0
    private weak var badgeBuddy: Buddy?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // First run ever: turn on "launch at login" by default so Dockmates
        // shows up automatically next time the Mac starts. After that we
        // leave it alone and respect whatever the user sets in the menu.
        if !UserDefaults.standard.bool(forKey: "loginItemBootstrapped") {
            UserDefaults.standard.set(true, forKey: "loginItemBootstrapped")
            LoginItem.setEnabled(true)
        }

        loadRecentAnswers()

        overlay = OverlayController()
        overlay.onBuddyClicked = { [weak self] buddy in
            self?.clearUnattended()
            self?.openAsk(for: buddy)
        }
        overlay.onBuddyRightClicked = { [weak self] buddy in
            // Everyone (people and pets) is dressable via right-click; a plain
            // left-click on a pet still just gets a happy reaction.
            self?.openDressingRoom(for: buddy)
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

        // Tabbing back to the Claude app means the finished sessions have
        // been seen; retire the badge.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] note in
            guard let self,
                  let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.bundleIdentifier == self.claudeBundleID else { return }
            self.clearUnattended()
        }
    }

    private func handleClaudeEvent(_ event: ClaudeEvent) {
        guard watchClaude else { return }

        // Stay quiet while the user is already looking at Claude.
        if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == claudeBundleID { return }

        // Every unattended finish bumps the badge, even inside the nudge
        // debounce window, so a burst of sessions still counts each one.
        if case .done = event {
            unattendedCount += 1
        }

        let now = CACurrentMediaTime()
        let debounced = now - lastNudgeAt < 3
        if !debounced { lastNudgeAt = now }

        let bubble: String
        let title: String
        let body: String
        switch event {
        case .done(let project):
            if let project {
                bubble = "\(project) is done!"
                title = "Claude Code finished"
                body = "Your \(project) session wrapped up. Head back when you're ready."
            } else {
                bubble = "Claude's all done!"
                title = "Claude Code finished"
                body = "Your task wrapped up. Head back when you're ready."
            }
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
            if !debounced {
                buddy.celebrate()
                buddy.bubble.show(bubble, for: 18)
            }
            // Move the badge onto whichever buddy nudged most recently.
            if unattendedCount > 0 {
                if badgeBuddy !== buddy { badgeBuddy?.setBadge(0) }
                badgeBuddy = buddy
                buddy.setBadge(unattendedCount)
            }
        }
        if !debounced {
            notifier.post(title: title, body: body)
        }
    }

    /// The user has seen what finished: drop the badge back to zero.
    private func clearUnattended() {
        guard unattendedCount > 0 else { return }
        unattendedCount = 0
        badgeBuddy?.setBadge(0)
        badgeBuddy = nil
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

        // Recent answers, rebuilt from `recentAnswers` every time it opens.
        recentAnswersMenu.delegate = self
        let recents = NSMenuItem(title: "Recent answers", action: nil, keyEquivalent: "")
        recents.submenu = recentAnswersMenu
        menu.addItem(recents)

        // "On the dock" submenu: check on/off each possible dockmate.
        let dockmatesMenu = NSMenu()
        for style in overlay.rosterStyles {
            let label = style.species == .person ? style.name : "\(style.name) (\(style.species.rawValue))"
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

    // MARK: - Recent answers

    private func loadRecentAnswers() {
        guard let data = UserDefaults.standard.data(forKey: recentAnswersKey),
              let saved = try? JSONDecoder().decode([RecentAnswer].self, from: data) else { return }
        recentAnswers = saved
    }

    private func recordRecentAnswer(prompt: String, text: String, sessionId: String) {
        recentAnswers.insert(RecentAnswer(prompt: prompt, text: text, sessionId: sessionId), at: 0)
        if recentAnswers.count > recentAnswersCap {
            recentAnswers.removeLast(recentAnswers.count - recentAnswersCap)
        }
        if let data = try? JSONEncoder().encode(recentAnswers) {
            UserDefaults.standard.set(data, forKey: recentAnswersKey)
        }
    }

    @objc private func openRecentAnswer(_ sender: NSMenuItem) {
        guard let index = sender.representedObject as? Int,
              recentAnswers.indices.contains(index),
              let buddy = overlay.firstFreePerson() else { return }
        let recent = recentAnswers[index]
        // Continue that conversation: follow-ups typed into the reopened
        // panel resume the same CLI session (or start fresh if it expired).
        answerSessionId = recent.sessionId
        let panel = AnswerPanel(buddyName: buddy.style.name, body: recent.text, prompt: recent.prompt)
        panel.onReply = { [weak self] reply in
            self?.startTask(reply, buddy: buddy, isFollowUp: true)
        }
        panel.present(above: overlay.screenPoint(above: buddy))
        answerPanel = panel
        answerBuddy = buddy
    }

    @objc private func toggleDockmate(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        let makeVisible = sender.state == .off
        overlay.setVisible(name, makeVisible)
        sender.state = makeVisible ? .on : .off
    }

    @objc private func dressingRoomFromMenu() {
        guard let first = overlay.buddies.first else { return }
        openDressingRoom(for: first)
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
        // Everyone is editable now; the panel shows person or pet controls
        // per the selected dockmate's species.
        let all = overlay.buddies
        let index = all.firstIndex { $0 === buddy } ?? 0
        panel.present(buddies: all, selected: index,
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
            self?.answerSessionId = nil
            self?.startTask(prompt, buddy: buddy, isFollowUp: false)
        }
        panel.present(above: overlay.screenPoint(above: buddy), listener: buddy.style.name)
    }

    private func startTask(_ prompt: String, buddy: Buddy, isFollowUp: Bool) {
        // A reminder request is handled locally, no Claude CLI needed.
        if let reminder = ReminderParser.parse(prompt) {
            scheduler.add(reminder)
            buddy.hop()
            buddy.bubble.show("on it! " + reminder.scheduleText, for: 4.5)
            routinePanel?.refresh()
            return
        }

        buddy.beginThinking()
        if isFollowUp {
            answerPanel?.appendUserMessage(prompt)
            answerPanel?.setBusy(true)
        } else {
            answerPanel?.orderOut(nil)
        }

        ClaudeRunner.run(prompt: prompt, resuming: answerSessionId) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let reply):
                self.answerSessionId = reply.sessionId
                buddy.celebrate()
                buddy.bubble.show("ta-da!", for: 2.5)
                if isFollowUp, let panel = self.answerPanel {
                    panel.setBusy(false)
                    panel.appendAssistantMessage(reply.text)
                } else {
                    self.recordRecentAnswer(prompt: prompt, text: reply.text, sessionId: reply.sessionId)
                    self.presentAnswer(reply.text, buddy: buddy)
                }
            case .failure(let error):
                buddy.stopBusy()
                buddy.bubble.show("hmm, that didn't work", for: 3)
                let message = "Something went wrong:\n\n" + error.localizedDescription
                if isFollowUp, let panel = self.answerPanel {
                    panel.setBusy(false)
                    panel.appendAssistantMessage(message)
                } else {
                    self.presentAnswer(message, buddy: buddy)
                }
            }
        }
    }

    private func presentAnswer(_ text: String, buddy: Buddy) {
        let panel = AnswerPanel(buddyName: buddy.style.name, body: text)
        panel.onReply = { [weak self] reply in
            self?.startTask(reply, buddy: buddy, isFollowUp: true)
        }
        panel.present(above: overlay.screenPoint(above: buddy))
        answerPanel = panel
        answerBuddy = buddy
    }
}

extension AppController: NSMenuDelegate {
    /// Rebuilds the "Recent answers" submenu each time it opens.
    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === recentAnswersMenu else { return }
        menu.removeAllItems()
        if recentAnswers.isEmpty {
            let empty = NSMenuItem(title: "Nothing asked yet", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
            return
        }
        for (index, recent) in recentAnswers.enumerated() {
            var title = recent.prompt
            if title.count > 44 {
                title = String(title.prefix(44)) + "\u{2026}"
            }
            let item = NSMenuItem(title: title, action: #selector(openRecentAnswer(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = index
            menu.addItem(item)
        }
    }
}
