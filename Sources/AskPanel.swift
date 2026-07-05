import AppKit

/// Borderless panel that can still take keyboard focus without activating the app.
class KeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

final class AskPanel: KeyPanel, NSTextFieldDelegate {
    var onSubmit: ((String) -> Void)?

    private let field = NSTextField()
    private let caption = NSTextField(labelWithString: "")

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
            string: "Ask Claude anything",
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

        let hint = NSTextField(labelWithString: "return to send  ·  esc to close")
        hint.frame = NSRect(x: 22, y: 14, width: 356, height: 14)
        hint.font = Theme.rounded(10.5, .medium)
        hint.textColor = Theme.inkSoft.withAlphaComponent(0.8)
        hint.alignment = .right
        content.addSubview(hint)
    }

    func present(above point: NSPoint, listener: String) {
        caption.attributedStringValue = captionText(listener)
        field.stringValue = ""

        var origin = NSPoint(x: point.x - Self.panelSize.width / 2, y: point.y + 10)
        if let screen = NSScreen.screens.first {
            let vf = screen.visibleFrame
            origin.x = max(vf.minX + 12, min(origin.x, vf.maxX - Self.panelSize.width - 12))
            origin.y = min(origin.y, vf.maxY - Self.panelSize.height - 12)
        }
        setFrameOrigin(origin)
        makeKeyAndOrderFront(nil)
        makeFirstResponder(field)
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
        orderOut(nil)
        onSubmit?(prompt)
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
        return false
    }
}
