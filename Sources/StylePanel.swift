import AppKit

/// NSButton that runs a closure, so rows of swatches don't need selector plumbing.
final class ActionButton: NSButton {
    var onClick: (() -> Void)?

    convenience init(size: NSSize) {
        self.init(frame: NSRect(origin: .zero, size: size))
        title = ""
        isBordered = false
        target = self
        action = #selector(fire)
    }

    @objc private func fire() { onClick?() }
}

/// The dressing room: live preview on top, swatch and chip rows below.
/// Edits apply immediately to the buddy on the dock and are reported
/// through onStyleChanged for persistence.
final class StylePanel: KeyPanel {
    var onStyleChanged: (() -> Void)?

    private var buddies: [Buddy] = []
    private var currentIndex = 0
    private var previewBuddy: Buddy?
    private let previewHost = NSView()
    private var controls: [NSView] = []
    private var nextY: CGFloat = 0

    private static let panelSize = NSSize(width: 430, height: 660)
    private let content = NSView(frame: NSRect(origin: .zero, size: panelSize))

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

        content.wantsLayer = true
        content.layer?.backgroundColor = Theme.paper.cgColor
        content.layer?.cornerRadius = 20
        content.layer?.borderWidth = 1.5
        content.layer?.borderColor = Theme.accent.withAlphaComponent(0.9).cgColor
        content.layer?.masksToBounds = true
        contentView = content

        let size = Self.panelSize
        let title = NSTextField(labelWithString: "Dressing room")
        title.frame = NSRect(x: 22, y: size.height - 34, width: 200, height: 18)
        title.font = Theme.rounded(13, .bold)
        title.textColor = Theme.ink
        content.addSubview(title)

        let closeButton = ActionButton(size: NSSize(width: 52, height: 24))
        closeButton.frame.origin = NSPoint(x: size.width - 66, y: size.height - 37)
        closeButton.attributedTitle = NSAttributedString(string: "Close", attributes: [
            .font: Theme.rounded(12, .semibold),
            .foregroundColor: Theme.inkSoft,
        ])
        closeButton.onClick = { [weak self] in self?.orderOut(nil) }
        content.addSubview(closeButton)

        let rule = NSView(frame: NSRect(x: 0, y: size.height - 46, width: size.width, height: 1))
        rule.wantsLayer = true
        rule.layer?.backgroundColor = Theme.hairline.cgColor
        content.addSubview(rule)

        previewHost.frame = NSRect(x: 20, y: size.height - 46 - 152, width: size.width - 40, height: 144)
        previewHost.layer = CALayer()
        previewHost.wantsLayer = true
        previewHost.layer?.backgroundColor = NSColor(hex: 0xF2EBDE).cgColor
        previewHost.layer?.cornerRadius = 14
        previewHost.layer?.masksToBounds = true
        content.addSubview(previewHost)
    }

    func present(buddies: [Buddy], selected: Int, near point: NSPoint) {
        self.buddies = buddies
        currentIndex = min(selected, buddies.count - 1)

        if previewBuddy == nil, !buddies.isEmpty {
            let preview = Buddy(style: buddies[currentIndex].style, scale: 2, feetY: 8)
            preview.x = previewHost.bounds.midX
            previewHost.layer?.addSublayer(preview.root)
            previewBuddy = preview
        }
        syncPreview()
        rebuild()

        var origin = NSPoint(x: point.x - Self.panelSize.width / 2, y: point.y + 10)
        if let screen = NSScreen.screens.first {
            let vf = screen.visibleFrame
            origin.x = max(vf.minX + 12, min(origin.x, vf.maxX - Self.panelSize.width - 12))
            origin.y = min(origin.y, vf.maxY - Self.panelSize.height - 12)
            origin.y = max(origin.y, vf.minY + 12)
        }
        setFrameOrigin(origin)
        makeKeyAndOrderFront(nil)
    }

    override func cancelOperation(_ sender: Any?) {
        orderOut(nil)
    }

    // MARK: - Editing

    private var style: BuddyStyle { buddies[currentIndex].style }

    private func apply(_ mutate: (inout BuddyStyle) -> Void) {
        var s = buddies[currentIndex].style
        mutate(&s)
        buddies[currentIndex].applyStyle(s)
        onStyleChanged?()
        syncPreview()
        rebuild()
    }

    private func syncPreview() {
        guard let preview = previewBuddy, !buddies.isEmpty else { return }
        preview.applyStyle(buddies[currentIndex].style)
        preview.forcePose(phase: 0, walk: 0)
        preview.x = previewHost.bounds.midX
    }

    // MARK: - Rows

    private func rebuild() {
        controls.forEach { $0.removeFromSuperview() }
        controls = []
        guard !buddies.isEmpty else { return }
        nextY = Self.panelSize.height - 46 - 152 - 36

        let s = style

        addRow("Buddy", buddies.enumerated().map { index, buddy in
            chip(buddy.style.name, selected: index == currentIndex) { [weak self] in
                self?.currentIndex = index
                self?.syncPreview()
                self?.rebuild()
            }
        } + [chip("Reset", selected: false) { [weak self] in
            guard let self else { return }
            let defaults = BuddyStyle.defaults
            if self.currentIndex < defaults.count {
                self.apply { $0 = defaults[self.currentIndex] }
            }
        }])

        addRow("Skin", Theme.skinTones.map { hex in
            swatch(hex, selected: s.skin == hex) { [weak self] in
                self?.apply { $0.skin = hex }
            }
        })

        addRow("Hair", HairKind.allCases.map { kind in
            chip(kind.rawValue, selected: s.hairKind == kind) { [weak self] in
                self?.apply { $0.hairKind = kind }
            }
        })

        addRow("Hair color", Theme.hairShades.map { hex in
            swatch(hex, selected: s.hair == hex) { [weak self] in
                self?.apply { $0.hair = hex }
            }
        })

        addRow("Hat", HatKind.allCases.map { kind in
            chip(kind.rawValue, selected: s.hatKind == kind) { [weak self] in
                self?.apply { $0.hatKind = kind }
            }
        })

        addRow("Hat color", Theme.clothing.map { hex in
            swatch(hex, selected: s.hat == hex) { [weak self] in
                self?.apply { $0.hat = hex }
            }
        })

        addRow("Top", Theme.clothing.map { hex in
            swatch(hex, selected: s.outfit == hex) { [weak self] in
                self?.apply { $0.outfit = hex }
            }
        })

        addRow("Bottom", BottomKind.allCases.map { kind in
            chip(kind.rawValue, selected: s.bottomKind == kind) { [weak self] in
                self?.apply { $0.bottomKind = kind }
            }
        })

        addRow("Bottom color", Theme.clothing.map { hex in
            swatch(hex, selected: s.pants == hex) { [weak self] in
                self?.apply { $0.pants = hex }
            }
        })

        addRow("Shoes", Theme.clothing.map { hex in
            swatch(hex, selected: s.shoes == hex) { [weak self] in
                self?.apply { $0.shoes = hex }
            }
        })

        addRow("Extras", [
            chip("glasses", selected: s.glasses) { [weak self] in
                self?.apply { $0.glasses.toggle() }
            },
            chip("scarf", selected: s.scarfOn) { [weak self] in
                self?.apply { $0.scarfOn.toggle() }
            },
            chip("tote", selected: s.hasTote) { [weak self] in
                self?.apply { $0.hasTote.toggle() }
            },
        ])

        if s.scarfOn {
            addRow("Scarf color", Theme.clothing.map { hex in
                swatch(hex, selected: s.scarf == hex) { [weak self] in
                    self?.apply { $0.scarf = hex }
                }
            })
        }
    }

    private func addRow(_ label: String, _ items: [NSView]) {
        let labelField = NSTextField(labelWithString: label)
        labelField.font = Theme.rounded(11, .semibold)
        labelField.textColor = Theme.inkSoft
        labelField.frame = NSRect(x: 22, y: nextY + 3, width: 76, height: 16)
        content.addSubview(labelField)
        controls.append(labelField)

        var x: CGFloat = 102
        for item in items {
            var frame = item.frame
            frame.origin = NSPoint(x: x, y: nextY)
            item.frame = frame
            content.addSubview(item)
            controls.append(item)
            x += frame.width + 6
        }
        nextY -= 34
    }

    private func swatch(_ hex: UInt32, selected: Bool, action: @escaping () -> Void) -> ActionButton {
        let button = ActionButton(size: NSSize(width: 22, height: 22))
        button.wantsLayer = true
        button.layer?.backgroundColor = NSColor(hex: hex).cgColor
        button.layer?.cornerRadius = 11
        button.layer?.borderWidth = selected ? 2.5 : 1
        button.layer?.borderColor = selected
            ? Theme.accent.cgColor
            : Theme.ink.withAlphaComponent(0.15).cgColor
        button.onClick = action
        return button
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> ActionButton {
        let font = Theme.rounded(11, .semibold)
        let width = ceil((title as NSString).size(withAttributes: [.font: font]).width) + 20
        let button = ActionButton(size: NSSize(width: width, height: 22))
        button.wantsLayer = true
        button.layer?.cornerRadius = 11
        button.layer?.backgroundColor = selected ? Theme.accent.cgColor : NSColor.clear.cgColor
        button.layer?.borderWidth = selected ? 0 : 1
        button.layer?.borderColor = Theme.ink.withAlphaComponent(0.2).cgColor
        button.attributedTitle = NSAttributedString(string: title, attributes: [
            .font: font,
            .foregroundColor: selected ? Theme.paper : Theme.ink,
        ])
        button.onClick = action
        return button
    }
}
