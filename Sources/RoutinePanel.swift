import AppKit

final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

/// The routines board: add nudges like "drink water every 1h" or
/// "exercise at 6:00 pm", toggle them, delete them. A free buddy hops
/// and says the message in a speech bubble when one fires.
final class RoutinePanel: KeyPanel, NSTextFieldDelegate {
    private var scheduler: ReminderScheduler?

    private let field = NSTextField()
    private let picker = NSDatePicker()
    private let listContainer = FlippedView()
    private var dynamicControls: [NSView] = []
    private var listRows: [NSView] = []

    private var draftIsInterval = true
    private var draftMinutes = 60
    private let intervalChoices = [15, 30, 60, 120, 180]

    private static let panelSize = NSSize(width: 430, height: 540)
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

        let title = NSTextField(labelWithString: "Routines")
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

        let prompt = NSTextField(labelWithString: "Remind me to")
        prompt.frame = NSRect(x: 22, y: size.height - 76, width: 200, height: 16)
        prompt.font = Theme.rounded(11, .semibold)
        prompt.textColor = Theme.inkSoft
        content.addSubview(prompt)

        field.frame = NSRect(x: 22, y: size.height - 106, width: 386, height: 26)
        field.isBezeled = false
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = Theme.rounded(14, .regular)
        field.textColor = Theme.ink
        field.placeholderAttributedString = NSAttributedString(
            string: "drink water",
            attributes: [
                .font: Theme.rounded(14, .regular),
                .foregroundColor: Theme.inkSoft.withAlphaComponent(0.7),
            ]
        )
        field.maximumNumberOfLines = 1
        field.cell?.usesSingleLineMode = true
        field.cell?.isScrollable = true
        field.delegate = self
        content.addSubview(field)

        let underline = NSView(frame: NSRect(x: 22, y: size.height - 110, width: 386, height: 1))
        underline.wantsLayer = true
        underline.layer?.backgroundColor = Theme.accent.withAlphaComponent(0.25).cgColor
        content.addSubview(underline)

        picker.datePickerStyle = .textFieldAndStepper
        picker.datePickerElements = .hourMinute
        picker.font = Theme.rounded(12, .regular)
        var comps = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        comps.hour = 18
        comps.minute = 0
        picker.dateValue = Calendar.current.date(from: comps) ?? Date()
        picker.isHidden = true
        content.addSubview(picker)

        let rule2 = NSView(frame: NSRect(x: 0, y: size.height - 162, width: size.width, height: 1))
        rule2.wantsLayer = true
        rule2.layer?.backgroundColor = Theme.hairline.cgColor
        content.addSubview(rule2)

        let listLabel = NSTextField(labelWithString: "Your reminders")
        listLabel.frame = NSRect(x: 22, y: size.height - 188, width: 200, height: 16)
        listLabel.font = Theme.rounded(11, .semibold)
        listLabel.textColor = Theme.inkSoft
        content.addSubview(listLabel)

        let scroll = NSScrollView(frame: NSRect(x: 22, y: 18, width: 386, height: size.height - 214))
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.autohidesScrollers = true
        listContainer.frame = NSRect(x: 0, y: 0, width: 386, height: 10)
        scroll.documentView = listContainer
        content.addSubview(scroll)
    }

    func present(scheduler: ReminderScheduler, near point: NSPoint) {
        self.scheduler = scheduler
        rebuildScheduleRow()
        rebuildList()

        var origin = NSPoint(x: point.x - Self.panelSize.width / 2, y: point.y + 10)
        if let screen = NSScreen.screens.first {
            let vf = screen.visibleFrame
            origin.x = max(vf.minX + 12, min(origin.x, vf.maxX - Self.panelSize.width - 12))
            origin.y = min(origin.y, vf.maxY - Self.panelSize.height - 12)
            origin.y = max(origin.y, vf.minY + 12)
        }
        setFrameOrigin(origin)
        makeKeyAndOrderFront(nil)
        makeFirstResponder(field)
        enableOutsideClickDismiss()
    }

    /// Layout without ordering the window in, for snapshot review.
    func prepareForSnapshot(scheduler: ReminderScheduler) {
        self.scheduler = scheduler
        rebuildScheduleRow()
        rebuildList()
    }

    /// Refresh the list if the panel is currently on screen (e.g. a reminder
    /// was just added from the ask box).
    func refresh() {
        guard isVisible else { return }
        rebuildList()
    }

    override func cancelOperation(_ sender: Any?) {
        orderOut(nil)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            addReminder()
            return true
        }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            orderOut(nil)
            return true
        }
        return false
    }

    // MARK: - Schedule row

    private func rebuildScheduleRow() {
        dynamicControls.forEach { $0.removeFromSuperview() }
        dynamicControls = []

        let y = Self.panelSize.height - 146
        var x: CGFloat = 22

        let everyChip = chip("every", selected: draftIsInterval) { [weak self] in
            self?.draftIsInterval = true
            self?.rebuildScheduleRow()
        }
        everyChip.frame.origin = NSPoint(x: x, y: y)
        content.addSubview(everyChip)
        dynamicControls.append(everyChip)
        x += everyChip.frame.width + 6

        let atChip = chip("at time", selected: !draftIsInterval) { [weak self] in
            self?.draftIsInterval = false
            self?.rebuildScheduleRow()
        }
        atChip.frame.origin = NSPoint(x: x, y: y)
        content.addSubview(atChip)
        dynamicControls.append(atChip)
        x += atChip.frame.width + 16

        if draftIsInterval {
            picker.isHidden = true
            for minutes in intervalChoices {
                let label = minutes < 60
                    ? "\(minutes)m"
                    : (minutes % 60 == 0 ? "\(minutes / 60)h" : "\(minutes / 60)h \(minutes % 60)m")
                let c = chip(label, selected: draftMinutes == minutes) { [weak self] in
                    self?.draftMinutes = minutes
                    self?.rebuildScheduleRow()
                }
                c.frame.origin = NSPoint(x: x, y: y)
                content.addSubview(c)
                dynamicControls.append(c)
                x += c.frame.width + 6
            }
        } else {
            picker.isHidden = false
            picker.frame = NSRect(x: x, y: y - 2, width: 96, height: 26)
        }

        let add = chip("Add", selected: true) { [weak self] in
            self?.addReminder()
        }
        add.frame.origin = NSPoint(x: Self.panelSize.width - 22 - add.frame.width, y: y)
        content.addSubview(add)
        dynamicControls.append(add)
    }

    private func addReminder() {
        guard let scheduler else { return }
        let message = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else { return }

        let comps = Calendar.current.dateComponents([.hour, .minute], from: picker.dateValue)
        let reminder = Reminder(
            message: message,
            isInterval: draftIsInterval,
            intervalMinutes: draftMinutes,
            hour: comps.hour ?? 18,
            minute: comps.minute ?? 0
        )
        scheduler.add(reminder)
        field.stringValue = ""
        rebuildList()
    }

    // MARK: - List

    private func rebuildList() {
        listRows.forEach { $0.removeFromSuperview() }
        listRows = []
        guard let scheduler else { return }

        let reminders = scheduler.reminders
        let rowHeight: CGFloat = 34
        listContainer.frame.size.height = max(10, CGFloat(reminders.count) * rowHeight)

        if reminders.isEmpty {
            let empty = NSTextField(wrappingLabelWithString:
                "Nothing yet. Add one above and Juno or Bo will hop over to nudge you.")
            empty.frame = NSRect(x: 2, y: 4, width: 360, height: 40)
            empty.font = Theme.rounded(12, .regular)
            empty.textColor = Theme.inkSoft
            listContainer.frame.size.height = 50
            listContainer.addSubview(empty)
            listRows.append(empty)
            return
        }

        for (index, reminder) in reminders.enumerated() {
            let y = CGFloat(index) * rowHeight

            let toggle = chip(reminder.enabled ? "on" : "off", selected: reminder.enabled) { [weak self] in
                guard let self, let scheduler = self.scheduler else { return }
                var updated = reminder
                updated.enabled.toggle()
                scheduler.update(updated)
                if updated.enabled { scheduler.touch(updated.id) }
                self.rebuildList()
            }
            toggle.frame.origin = NSPoint(x: 0, y: y + 5)
            listContainer.addSubview(toggle)
            listRows.append(toggle)

            let text = NSTextField(labelWithString: "")
            let line = NSMutableAttributedString()
            line.append(NSAttributedString(string: reminder.message, attributes: [
                .font: Theme.rounded(12.5, .semibold),
                .foregroundColor: reminder.enabled ? Theme.ink : Theme.inkSoft,
            ]))
            line.append(NSAttributedString(string: "   " + reminder.scheduleText, attributes: [
                .font: Theme.rounded(11.5, .regular),
                .foregroundColor: Theme.inkSoft,
            ]))
            text.attributedStringValue = line
            text.lineBreakMode = .byTruncatingTail
            text.frame = NSRect(x: 52, y: y + 8, width: 296, height: 18)
            listContainer.addSubview(text)
            listRows.append(text)

            let remove = ActionButton(size: NSSize(width: 24, height: 22))
            remove.attributedTitle = NSAttributedString(string: "✕", attributes: [
                .font: Theme.rounded(11, .semibold),
                .foregroundColor: Theme.inkSoft,
            ])
            remove.frame.origin = NSPoint(x: 358, y: y + 5)
            remove.onClick = { [weak self] in
                self?.scheduler?.remove(id: reminder.id)
                self?.rebuildList()
            }
            listContainer.addSubview(remove)
            listRows.append(remove)
        }
    }

    // MARK: - Controls

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
