import AppKit

final class AnswerPanel: KeyPanel {
    private let body: String

    private static let panelSize = NSSize(width: 460, height: 420)

    init(buddyName: String, body: String) {
        self.body = body
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

        let size = Self.panelSize
        let content = NSView(frame: NSRect(origin: .zero, size: size))
        content.wantsLayer = true
        content.layer?.backgroundColor = Theme.paper.cgColor
        content.layer?.cornerRadius = 20
        content.layer?.borderWidth = 1.5
        content.layer?.borderColor = Theme.accent.withAlphaComponent(0.9).cgColor
        content.layer?.masksToBounds = true
        contentView = content

        // Header
        let title = NSTextField(labelWithString: "")
        title.frame = NSRect(x: 22, y: size.height - 34, width: 260, height: 18)
        let t = NSMutableAttributedString()
        t.append(NSAttributedString(string: buddyName, attributes: [
            .font: Theme.rounded(13, .bold),
            .foregroundColor: Theme.ink,
        ]))
        t.append(NSAttributedString(string: "  found this for you", attributes: [
            .font: Theme.rounded(13, .regular),
            .foregroundColor: Theme.inkSoft,
        ]))
        title.attributedStringValue = t
        content.addSubview(title)

        let copyButton = NSButton(title: "Copy", target: self, action: #selector(copyBody))
        copyButton.frame = NSRect(x: size.width - 116, y: size.height - 37, width: 56, height: 24)
        copyButton.isBordered = false
        copyButton.attributedTitle = NSAttributedString(string: "Copy", attributes: [
            .font: Theme.rounded(12, .semibold),
            .foregroundColor: Theme.accent,
        ])
        content.addSubview(copyButton)

        let closeButton = NSButton(title: "Close", target: self, action: #selector(closePanel))
        closeButton.frame = NSRect(x: size.width - 66, y: size.height - 37, width: 52, height: 24)
        closeButton.isBordered = false
        closeButton.attributedTitle = NSAttributedString(string: "Close", attributes: [
            .font: Theme.rounded(12, .semibold),
            .foregroundColor: Theme.inkSoft,
        ])
        content.addSubview(closeButton)

        let rule = NSView(frame: NSRect(x: 0, y: size.height - 46, width: size.width, height: 1))
        rule.wantsLayer = true
        rule.layer?.backgroundColor = Theme.hairline.cgColor
        content.addSubview(rule)

        // Scrollable answer
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: size.width, height: size.height - 47))
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.autohidesScrollers = true

        let textView = NSTextView(frame: NSRect(origin: .zero, size: scroll.contentSize))
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 18, height: 16)
        textView.autoresizingMask = [.width]
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                  height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.textStorage?.setAttributedString(Self.render(body))
        scroll.documentView = textView
        content.addSubview(scroll)
    }

    func present(above point: NSPoint) {
        var origin = NSPoint(x: point.x - Self.panelSize.width / 2, y: point.y + 10)
        if let screen = NSScreen.screens.first {
            let vf = screen.visibleFrame
            origin.x = max(vf.minX + 12, min(origin.x, vf.maxX - Self.panelSize.width - 12))
            origin.y = min(origin.y, vf.maxY - Self.panelSize.height - 12)
            origin.y = max(origin.y, vf.minY + 12)
        }
        setFrameOrigin(origin)
        makeKeyAndOrderFront(nil)
        enableOutsideClickDismiss()
    }

    @objc private func copyBody() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(body, forType: .string)
    }

    @objc private func closePanel() {
        orderOut(nil)
    }

    override func cancelOperation(_ sender: Any?) {
        orderOut(nil)
    }

    // MARK: - Markdown-lite rendering

    static func render(_ source: String) -> NSAttributedString {
        let bodyFont = Theme.rounded(13.5, .regular)
        let boldFont = Theme.rounded(13.5, .bold)
        let headingFont = Theme.rounded(16, .bold)
        let monoFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 3
        paragraph.paragraphSpacing = 7

        let out = NSMutableAttributedString()
        var inCode = false

        for rawLine in source.components(separatedBy: "\n") {
            let line = rawLine
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                inCode.toggle()
                continue
            }

            if inCode {
                out.append(NSAttributedString(string: line + "\n", attributes: [
                    .font: monoFont,
                    .foregroundColor: Theme.ink,
                    .paragraphStyle: paragraph,
                ]))
                continue
            }

            if line.hasPrefix("#") {
                let text = line.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)
                out.append(NSAttributedString(string: text + "\n", attributes: [
                    .font: headingFont,
                    .foregroundColor: Theme.ink,
                    .paragraphStyle: paragraph,
                ]))
                continue
            }

            var text = line
            var prefix = ""
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                prefix = "•  "
                text = String(trimmed.dropFirst(2))
            }

            if !prefix.isEmpty {
                out.append(NSAttributedString(string: prefix, attributes: [
                    .font: bodyFont,
                    .foregroundColor: Theme.accent,
                    .paragraphStyle: paragraph,
                ]))
            }

            // Inline **bold** spans
            let parts = text.components(separatedBy: "**")
            for (i, part) in parts.enumerated() {
                let font = (i % 2 == 1 && parts.count > 2) ? boldFont : bodyFont
                out.append(NSAttributedString(string: part, attributes: [
                    .font: font,
                    .foregroundColor: Theme.ink,
                    .paragraphStyle: paragraph,
                ]))
            }
            out.append(NSAttributedString(string: "\n", attributes: [
                .font: bodyFont,
                .paragraphStyle: paragraph,
            ]))
        }
        return out
    }
}
