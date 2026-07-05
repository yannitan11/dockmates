import AppKit

final class AppController: NSObject, NSApplicationDelegate {
    private var overlay: OverlayController!
    private var statusItem: NSStatusItem!
    private var askPanel: AskPanel?
    private var answerPanel: AnswerPanel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        overlay = OverlayController()
        overlay.onBuddyClicked = { [weak self] buddy in
            self?.openAsk(for: buddy)
        }
        overlay.start()
        setupStatusItem()
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
