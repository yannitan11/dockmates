import AppKit

/// Borderless panel that can still take keyboard focus without activating the app.
class KeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }

    private var outsideClickMonitors: [Any] = []

    /// Auto-dismiss the panel when the user clicks anywhere outside it
    /// (another app, the desktop, or a Dockmate on the dock). Call after
    /// presenting.
    func enableOutsideClickDismiss() {
        disableOutsideClickDismiss()
        let events: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]

        // Clicks in other apps / the desktop
        let global = NSEvent.addGlobalMonitorForEvents(matching: events, handler: { [weak self] _ in
            self?.dismissIfClickedOutside()
        })
        if let global { outsideClickMonitors.append(global) }

        // Clicks in our own other windows (e.g. the buddy overlay)
        let local = NSEvent.addLocalMonitorForEvents(matching: events, handler: { [weak self] event in
            self?.dismissIfClickedOutside()
            return event
        })
        if let local { outsideClickMonitors.append(local) }
    }

    func disableOutsideClickDismiss() {
        outsideClickMonitors.forEach { NSEvent.removeMonitor($0) }
        outsideClickMonitors = []
    }

    private func dismissIfClickedOutside() {
        guard isVisible else { return }
        if !frame.contains(NSEvent.mouseLocation) {
            orderOut(nil)
        }
    }

    override func orderOut(_ sender: Any?) {
        disableOutsideClickDismiss()
        super.orderOut(sender)
    }
}

final class AskPanel: KeyPanel, NSTextFieldDelegate {
    var onSubmit: ((String) -> Void)?

    private let field = NSTextField()
    private let caption = NSTextField(labelWithString: "")

    // Up/down-arrow prompt history, shared across panels via UserDefaults.
    // While browsing, `historyIndex` is the offset into `history` (0 = most
    // recent) and `draft` holds whatever was typed before browsing began.
    private var history: [String] = []
    private var historyIndex: Int?
    private var draft = ""

    private static let historyKey = "askHistory"
    private static let historyCap = 20

    static func recordPrompt(_ prompt: String) {
        var history = UserDefaults.standard.stringArray(forKey: historyKey) ?? []
        history.removeAll { $0 == prompt }  // resurface repeats at the top
        history.insert(prompt, at: 0)
        if history.count > historyCap { history.removeLast(history.count - historyCap) }
        UserDefaults.standard.set(history, forKey: historyKey)
    }

    private static let panelSize = NSSize(width: 400, height: 116)

    init() {
        super.init(
            contentRect: NSRect(origin: .zero, size: Self.panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .popUpMenu
        isMovableByWindowBackground = true
        collectionBehavior = [.canJoinAllSpaces]
        hidesOnDeactivate = false

        let content = NSView(frame: NSRect(origin: .zero, size: Self.panelSize))
        content.wantsLayer = true
        content.layer?.backgroundColor = Theme.paper.cgColor
        content.layer?.cornerRadius = 20
        content.layer?.borderWidth = 1.5
        content.layer?.borderColor = Theme.accent.withAlphaComponent(0.9).cgColor
        content.layer?.masksToBounds = true
        contentView = content

        caption.frame = NSRect(x: 22, y: 82, width: 356, height: 16)
        caption.font = Theme.rounded(11, .semibold)
        caption.textColor = Theme.inkSoft
        content.addSubview(caption)

        field.frame = NSRect(x: 20, y: 44, width: 360, height: 28)
        field.isBezeled = false
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = Theme.rounded(15, .regular)
        field.textColor = Theme.ink
        field.placeholderAttributedString = NSAttributedString(
            string: "Ask anything, or \u{201C}remind me to\u{2026}\u{201D}",
            attributes: [
                .font: Theme.rounded(15, .regular),
                .foregroundColor: Theme.inkSoft.withAlphaComponent(0.7),
            ]
        )
        field.maximumNumberOfLines = 1
        field.cell?.usesSingleLineMode = true
        field.cell?.isScrollable = true
        field.delegate = self
        content.addSubview(field)

        let rule = NSView(frame: NSRect(x: 22, y: 38, width: 356, height: 1))
        rule.wantsLayer = true
        rule.layer?.backgroundColor = Theme.accent.withAlphaComponent(0.25).cgColor
        content.addSubview(rule)

        let hint = NSTextField(labelWithString: "\u{2191} history  ·  return to send  ·  esc to close")
        hint.frame = NSRect(x: 22, y: 14, width: 356, height: 14)
        hint.font = Theme.rounded(10.5, .medium)
        hint.textColor = Theme.inkSoft.withAlphaComponent(0.8)
        hint.alignment = .right
        content.addSubview(hint)
    }

    func present(above point: NSPoint, listener: String) {
        caption.attributedStringValue = captionText(listener)
        field.stringValue = ""
        history = UserDefaults.standard.stringArray(forKey: Self.historyKey) ?? []
        historyIndex = nil
        draft = ""

        var origin = NSPoint(x: point.x - Self.panelSize.width / 2, y: point.y + 10)
        if let screen = NSScreen.screens.first {
            let vf = screen.visibleFrame
            origin.x = max(vf.minX + 12, min(origin.x, vf.maxX - Self.panelSize.width - 12))
            origin.y = min(origin.y, vf.maxY - Self.panelSize.height - 12)
        }
        setFrameOrigin(origin)
        makeKeyAndOrderFront(nil)
        makeFirstResponder(field)
        enableOutsideClickDismiss()
    }

    private func captionText(_ listener: String) -> NSAttributedString {
        let s = NSMutableAttributedString()
        s.append(NSAttributedString(string: "● ", attributes: [
            .font: Theme.rounded(11, .semibold),
            .foregroundColor: Theme.accent,
        ]))
        s.append(NSAttributedString(string: "\(listener) is listening", attributes: [
            .font: Theme.rounded(11, .semibold),
            .foregroundColor: Theme.inkSoft,
        ]))
        return s
    }

    private func submit() {
        let prompt = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }
        Self.recordPrompt(prompt)
        orderOut(nil)
        onSubmit?(prompt)
    }

    /// Steps through prompt history: up = older, down = newer, past the
    /// newest = back to whatever was being typed.
    private func browseHistory(_ step: Int) {
        guard !history.isEmpty else { return }
        var index = (historyIndex ?? -1) + step
        if index < -1 { index = -1 }
        if index >= history.count { index = history.count - 1 }

        if index == -1 {
            historyIndex = nil
            field.stringValue = draft
        } else {
            if historyIndex == nil { draft = field.stringValue }
            historyIndex = index
            field.stringValue = history[index]
        }
        // Park the caret at the end, like a shell.
        field.currentEditor()?.selectedRange = NSRange(location: field.stringValue.count, length: 0)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            submit()
            return true
        }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            orderOut(nil)
            return true
        }
        if commandSelector == #selector(NSResponder.moveUp(_:)) {
            browseHistory(1)
            return true
        }
        if commandSelector == #selector(NSResponder.moveDown(_:)) {
            browseHistory(-1)
            return true
        }
        return false
    }
}
