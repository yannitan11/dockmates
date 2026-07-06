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

/// The dressing room: live preview on top, swatch and chip rows below in a
/// scrollable, wrapping list so growing option counts (more hats, more hair
/// styles, ...) never overflow the fixed-width panel. Edits apply immediately
/// to the buddy on the dock and are reported through onStyleChanged for
/// persistence.
final class StylePanel: KeyPanel {
    var onStyleChanged: (() -> Void)?

    private var buddies: [Buddy] = []
    private var currentIndex = 0
    private var previewBuddy: Buddy?
    private let previewHost = NSView()
    private let rowsContainer = FlippedView()
    private var rowViews: [NSView] = []
    private var cursorY: CGFloat = 0

    private static let panelSize = NSSize(width: 430, height: 620)
    private let rowsWidth = panelSize.width - 40
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

        let rule2Y = previewHost.frame.minY - 10
        let rule2 = NSView(frame: NSRect(x: 0, y: rule2Y, width: size.width, height: 1))
        rule2.wantsLayer = true
        rule2.layer?.backgroundColor = Theme.hairline.cgColor
        content.addSubview(rule2)

        let scrollTop = rule2Y - 8
        let scroll = NSScrollView(frame: NSRect(x: 20, y: 16, width: size.width - 40, height: scrollTop - 16))
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.autohidesScrollers = true
        rowsContainer.frame = NSRect(x: 0, y: 0, width: rowsWidth, height: 10)
        scroll.documentView = rowsContainer
        content.addSubview(scroll)
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
        enableOutsideClickDismiss()
    }

    override func cancelOperation(_ sender: Any?) {
        orderOut(nil)
    }

    /// Renders the whole scrollable rows area (not just the visible window
    /// frame) to a PNG, for design review of chip wrapping without needing
    /// to actually scroll the live panel. Loads buddies directly, bypassing
    /// present()'s window-ordering (no need for the panel to be on screen).
    func snapshotFullContent(buddies: [Buddy], to path: String) {
        self.buddies = buddies
        currentIndex = 0
        rebuild()
        let full = FlippedView(frame: NSRect(x: 0, y: 0, width: rowsWidth, height: rowsContainer.frame.height))
        full.wantsLayer = true
        full.layer?.backgroundColor = Theme.paper.cgColor
        for view in rowViews {
            view.removeFromSuperview()
            full.addSubview(view)
        }
        guard let rep = full.bitmapImageRepForCachingDisplay(in: full.bounds) else { return }
        full.cacheDisplay(in: full.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: URL(fileURLWithPath: path))
        print("style panel full content written to \(path)")
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
        rowViews.forEach { $0.removeFromSuperview() }
        rowViews = []
        guard !buddies.isEmpty else { return }
        cursorY = 4

        let s = style

        addRow("Buddy", buddies.enumerated().map { index, buddy in
            chip(buddy.style.name, selected: index == currentIndex) { [weak self] in
                self?.currentIndex = index
                self?.syncPreview()
                self?.rebuild()
            }
        } + [chip("Reset", selected: false) { [weak self] in
            self?.resetCurrent()
        }])

        // Pets get their own compact set of controls (fur, collar, accessory)
        // rather than the human hair/hat/top/... rows.
        if s.species != .person {
            addPetRows(s)
            rowsContainer.frame.size.height = cursorY + 8
            return
        }

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

        addRow("Top", TopKind.allCases.map { kind in
            chip(kind.rawValue, selected: s.topKind == kind) { [weak self] in
                self?.apply { $0.topKind = kind }
            }
        })

        addRow("Top color", Theme.clothing.map { hex in
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

        addRow("Neck", NeckKind.allCases.map { kind in
            chip(kind.rawValue, selected: s.neckKind == kind) { [weak self] in
                self?.apply { $0.neckKind = kind }
            }
        })

        if s.neckKind != .none {
            addRow("Neck color", Theme.clothing.map { hex in
                swatch(hex, selected: s.neckColor == hex) { [weak self] in
                    self?.apply { $0.neckColor = hex }
                }
            })
        }

        addRow("Extras", [
            chip("glasses", selected: s.glasses) { [weak self] in
                self?.apply { $0.glasses.toggle() }
            },
            chip("tote", selected: s.hasTote) { [weak self] in
                self?.apply { $0.hasTote.toggle() }
            },
        ])

        rowsContainer.frame.size.height = cursorY + 8
    }

    /// Reset the current dockmate to its roster default (works for people and
    /// pets, matched by name).
    private func resetCurrent() {
        let name = buddies[currentIndex].style.name
        if let def = BuddyStyle.roster.first(where: { $0.name == name }) {
            apply { $0 = def }
        }
    }

    /// Rows shown when the selected dockmate is a pet: fur color, collar
    /// color, and a dress-up accessory (with its own color).
    private func addPetRows(_ s: BuddyStyle) {
        addRow("Fur", Theme.furTones.map { hex in
            swatch(hex, selected: s.outfit == hex) { [weak self] in self?.apply { $0.outfit = hex } }
        })
        addRow("Collar", Theme.clothing.map { hex in
            swatch(hex, selected: s.neckColor == hex) { [weak self] in self?.apply { $0.neckColor = hex } }
        })
        addRow("Accessory", PetAccessory.allCases.map { kind in
            chip(kind.rawValue, selected: s.petAccessory == kind) { [weak self] in
                self?.apply { $0.petAccessory = kind }
            }
        })
        if s.petAccessory != .none {
            addRow("Accessory color", Theme.clothing.map { hex in
                swatch(hex, selected: s.hat == hex) { [weak self] in self?.apply { $0.hat = hex } }
            })
        }
    }

    /// Lays out a label plus a run of chips/swatches, wrapping onto
    /// additional lines within the row when they don't fit on one.
    private func addRow(_ label: String, _ items: [NSView]) {
        let labelField = NSTextField(labelWithString: label)
        labelField.font = Theme.rounded(11, .semibold)
        labelField.textColor = Theme.inkSoft
        labelField.frame = NSRect(x: 0, y: cursorY + 3, width: 76, height: 16)
        rowsContainer.addSubview(labelField)
        rowViews.append(labelField)

        let itemStartX: CGFloat = 80
        let lineHeight: CGFloat = 26
        var x = itemStartX
        var line: CGFloat = 0
        for item in items {
            let w = item.frame.width
            if x + w > rowsWidth, x > itemStartX {
                line += 1
                x = itemStartX
            }
            var frame = item.frame
            frame.origin = NSPoint(x: x, y: cursorY + line * lineHeight)
            item.frame = frame
            rowsContainer.addSubview(item)
            rowViews.append(item)
            x += w + 6
        }
        cursorY += 34 + line * lineHeight
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
