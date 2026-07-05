import AppKit
import QuartzCore

final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class StageView: NSView {
    var onMouseDown: ((NSPoint) -> Void)?
    var onMouseDragged: ((NSPoint) -> Void)?
    var onMouseUp: ((NSPoint) -> Void)?
    var onRightClick: ((NSPoint) -> Void)?

    override func mouseDown(with event: NSEvent) {
        onMouseDown?(convert(event.locationInWindow, from: nil))
    }

    override func mouseDragged(with event: NSEvent) {
        onMouseDragged?(convert(event.locationInWindow, from: nil))
    }

    override func mouseUp(with event: NSEvent) {
        onMouseUp?(convert(event.locationInWindow, from: nil))
    }

    override func rightMouseDown(with event: NSEvent) {
        onRightClick?(convert(event.locationInWindow, from: nil))
    }
}

/// Owns the transparent full-width window that floats just above the dock,
/// the two buddies, and the 30fps animation loop.
final class OverlayController {
    let window: OverlayWindow
    let stageView = StageView()
    let stageLayer = CALayer()
    private(set) var buddies: [Buddy] = []
    var onBuddyClicked: ((Buddy) -> Void)?
    var onBuddyRightClicked: ((Buddy) -> Void)?

    private var timer: Timer?
    private var lastTick = CACurrentMediaTime()
    private var nextChatterAt = CACurrentMediaTime() + .random(in: 14...26)

    // Drag state
    private var pressedBuddy: Buddy?
    private var grabOffset: CGFloat = 0
    private var pressStartX: CGFloat = 0
    private var didDrag = false
    private var interacting = false
    private let dragThreshold: CGFloat = 4
    private let feetY: CGFloat = 18
    private let stageHeight: CGFloat = 250

    private let chatter = [
        "la la la",
        "nice dock you got",
        "coffee break?",
        "just strolling",
        "click me if you need me",
        "beep boop",
    ]

    init() {
        window = OverlayWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: stageHeight),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .statusBar
        // No .fullScreenAuxiliary: the buddies stay off fullscreen spaces
        // (videos, presentations) and only live where the dock lives.
        window.collectionBehavior = [.canJoinAllSpaces, .stationary]
        window.ignoresMouseEvents = true

        stageView.layer = stageLayer
        stageView.wantsLayer = true
        window.contentView = stageView

        stageView.onMouseDown = { [weak self] point in
            self?.handleMouseDown(point)
        }
        stageView.onMouseDragged = { [weak self] point in
            self?.handleMouseDragged(point)
        }
        stageView.onMouseUp = { [weak self] point in
            self?.handleMouseUp(point)
        }
        stageView.onRightClick = { [weak self] point in
            guard let self, let buddy = self.buddyAt(point) else { return }
            self.onBuddyRightClicked?(buddy)
        }
    }

    func start() {
        let scale = NSScreen.screens.first?.backingScaleFactor ?? 2

        let juno = Buddy(style: .juno, scale: scale, feetY: feetY)
        let bo = Buddy(style: .bo, scale: scale, feetY: feetY)
        buddies = [juno, bo]

        // Restore saved outfits from the dressing room
        if let data = UserDefaults.standard.data(forKey: "buddyStyles"),
           let styles = try? JSONDecoder().decode([BuddyStyle].self, from: data) {
            for (buddy, style) in zip(buddies, styles) {
                buddy.applyStyle(style)
            }
        }
        for buddy in buddies {
            stageLayer.addSublayer(buddy.root)
            stageLayer.addSublayer(buddy.bubble.layer)
        }

        layout()

        if let width = NSScreen.screens.first?.frame.width {
            juno.x = width * 0.38
            bo.x = width * 0.55
            bo.facing = -1
        }

        window.orderFrontRegardless()

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.layout()
        }

        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func layout() {
        guard let screen = NSScreen.screens.first else { return }
        let sf = screen.frame
        let vf = screen.visibleFrame
        // Dock at the bottom: visibleFrame is lifted by the dock height.
        // Hidden or side dock: stand at the very bottom of the screen.
        let dockTop = vf.minY > sf.minY + 1 ? vf.minY : sf.minY + 4

        let frame = NSRect(x: sf.minX, y: dockTop - feetY, width: sf.width, height: stageHeight)
        window.setFrame(frame, display: true)
        stageLayer.frame = CGRect(origin: .zero, size: frame.size)

        let range: ClosedRange<CGFloat> = 90...max(91, sf.width - 90)
        for buddy in buddies {
            buddy.bounds = range
            if !range.contains(buddy.x) {
                buddy.x = .random(in: range)
            }
        }
    }

    var strolling = true {
        didSet {
            buddies.forEach { $0.wanderEnabled = strolling }
        }
    }

    private func tick() {
        let now = CACurrentMediaTime()
        let dt = min(0.1, now - lastTick)
        lastTick = now

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        for buddy in buddies {
            buddy.tick(dt: dt, now: now)
            buddy.bubble.layer.position = CGPoint(x: buddy.x, y: feetY + 130)

            if buddy.mode == .think {
                let elapsed = buddy.thinkElapsed
                let text: String
                if elapsed < 1.4 {
                    text = "on it!"
                } else {
                    let dots = Int(((elapsed - 1.4) / 0.5).truncatingRemainder(dividingBy: 4))
                    text = "thinking" + String(repeating: ".", count: dots)
                }
                if buddy.bubble.visible {
                    buddy.bubble.setText(text)
                } else {
                    buddy.bubble.show(text)
                }
            }
        }

        CATransaction.commit()

        // Idle chatter
        if now >= nextChatterAt {
            nextChatterAt = now + .random(in: 24...48)
            let idle = buddies.filter { !$0.busy && !$0.bubble.visible }
            if let buddy = idle.randomElement(), let line = chatter.randomElement() {
                buddy.bubble.show(line, for: 3.2)
            }
        }

        // Intercept the mouse while it hovers a buddy, or throughout a drag
        let mouse = NSEvent.mouseLocation
        let local = NSPoint(x: mouse.x - window.frame.minX, y: mouse.y - window.frame.minY)
        let over = interacting || buddyAt(local) != nil
        if window.ignoresMouseEvents == over {
            window.ignoresMouseEvents = !over
        }
    }

    private func buddyAt(_ point: NSPoint) -> Buddy? {
        buddies.first { $0.hitRect().contains(point) }
    }

    private func handleMouseDown(_ point: NSPoint) {
        guard let buddy = buddyAt(point) else { return }
        pressedBuddy = buddy
        grabOffset = point.x - buddy.x
        pressStartX = point.x
        didDrag = false
        interacting = true
    }

    private func handleMouseDragged(_ point: NSPoint) {
        guard let buddy = pressedBuddy else { return }
        if !didDrag && abs(point.x - pressStartX) > dragThreshold {
            didDrag = true
            buddy.beginDrag()
            NSCursor.closedHand.set()
        }
        guard didDrag else { return }
        let newX = min(max(point.x - grabOffset, buddy.bounds.lowerBound), buddy.bounds.upperBound)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if abs(newX - buddy.x) > 0.5 { buddy.facing = newX > buddy.x ? 1 : -1 }
        buddy.x = newX
        buddy.bubble.layer.position = CGPoint(x: newX, y: feetY + 130)
        CATransaction.commit()
    }

    private func handleMouseUp(_ point: NSPoint) {
        guard let buddy = pressedBuddy else { return }
        if didDrag {
            buddy.endDrag()
            NSCursor.arrow.set()
            if !buddy.busy { buddy.bubble.show("wheee!", for: 1.4) }
        } else if buddy.busy {
            buddy.bubble.show("still on it, one sec", for: 2)
        } else {
            buddy.hop()
            onBuddyClicked?(buddy)
        }
        pressedBuddy = nil
        interacting = false
    }

    /// Screen-space point just above a buddy's head, for anchoring panels.
    func screenPoint(above buddy: Buddy) -> NSPoint {
        NSPoint(x: window.frame.minX + buddy.x,
                y: window.frame.minY + feetY + 165)
    }

    func firstFreeBuddy() -> Buddy {
        buddies.first { !$0.busy } ?? buddies[0]
    }
}

// MARK: - Snapshot mode (renders the buddies to a PNG for design review)

enum SnapshotRenderer {
    static func writeRoutinePanel(to path: String) {
        let scheduler = ReminderScheduler()
        scheduler.useSampleData([
            Reminder(message: "drink water", isInterval: true, intervalMinutes: 60, hour: 9, minute: 0),
            Reminder(message: "stretch", isInterval: true, intervalMinutes: 120, hour: 9, minute: 0),
            Reminder(message: "exercise", isInterval: false, intervalMinutes: 60, hour: 18, minute: 0, enabled: false),
        ])
        let panel = RoutinePanel()
        panel.prepareForSnapshot(scheduler: scheduler)
        guard let view = panel.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            fputs("snapshot: could not render panel\n", stderr)
            return
        }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { return }
        do {
            try png.write(to: URL(fileURLWithPath: path))
            print("routines panel snapshot written to \(path)")
        } catch {
            fputs("snapshot: \(error.localizedDescription)\n", stderr)
        }
    }

    static func writeCloseup(to path: String) {
        let width = 700
        let height = 420
        let zoom: CGFloat = 2.6

        let stage = CALayer()
        stage.frame = CGRect(x: 0, y: 0, width: width, height: height)
        stage.backgroundColor = NSColor(hex: 0xE9E4DB).cgColor

        var pigtailsSinglet = BuddyStyle.juno
        pigtailsSinglet.hatKind = .none
        pigtailsSinglet.hairKind = .pigtails
        pigtailsSinglet.hair = 0x5C4330
        pigtailsSinglet.topKind = .singlet
        pigtailsSinglet.outfit = 0x3B5BDB
        pigtailsSinglet.neckKind = .tie
        pigtailsSinglet.neckColor = 0x2E2A26
        pigtailsSinglet.glasses = false
        let a = Buddy(style: pigtailsSinglet, scale: 3, feetY: 10)
        a.x = 190

        var ponytailTee = BuddyStyle.bo
        ponytailTee.hatKind = .none
        ponytailTee.hairKind = .ponytail
        ponytailTee.hair = 0xE8C97A
        ponytailTee.topKind = .tshirt
        ponytailTee.outfit = 0xF09A8B
        ponytailTee.neckKind = .bow
        ponytailTee.neckColor = 0xC9B8F0
        ponytailTee.hasTote = false
        let b = Buddy(style: ponytailTee, scale: 3, feetY: 10)
        b.x = 510
        b.facing = -1

        for buddy in [a, b] {
            stage.addSublayer(buddy.root)
            buddy.forcePose(phase: 0, walk: 0)
            // Geometric zoom for a real close-up (contentsScale above is
            // rasterization sharpness only, not physical size).
            buddy.root.transform = CATransform3DMakeScale(zoom * buddy.facing, zoom, 1)
        }

        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width * 2, pixelsHigh: height * 2,
            bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0
        ) else { return }
        rep.size = NSSize(width: width, height: height)
        guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return }
        stage.render(in: ctx.cgContext)
        guard let png = rep.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: URL(fileURLWithPath: path))
        print("closeup written to \(path)")
    }

    static func writeHats(to path: String) {
        let width = 900
        let height = 420
        let zoom: CGFloat = 2.2

        let stage = CALayer()
        stage.frame = CGRect(x: 0, y: 0, width: width, height: height)
        stage.backgroundColor = NSColor(hex: 0xE9E4DB).cgColor

        let hats: [(HatKind, HairKind, UInt32)] = [
            (.cap, .none, 0x5C4330),
            (.beret, .long, 0x5C4330),
            (.headband, .ponytail, 0xE8C97A),
            (.flowers, .pigtails, 0x9C6B3C),
        ]
        var x: CGFloat = 130
        for (hat, hair, hairColor) in hats {
            var s = BuddyStyle.juno
            s.hatKind = hat
            s.hairKind = hair
            s.hair = hairColor
            s.glasses = false
            let buddy = Buddy(style: s, scale: 3, feetY: 10)
            buddy.x = x
            stage.addSublayer(buddy.root)
            buddy.forcePose(phase: 0, walk: 0)
            buddy.root.transform = CATransform3DMakeScale(zoom, zoom, 1)
            x += 210
        }

        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width * 2, pixelsHigh: height * 2,
            bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0
        ) else { return }
        rep.size = NSSize(width: width, height: height)
        guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return }
        stage.render(in: ctx.cgContext)
        guard let png = rep.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: URL(fileURLWithPath: path))
        print("hats closeup written to \(path)")
    }

    static func write(to path: String) {
        let width = 900
        let height = 320

        let stage = CALayer()
        stage.frame = CGRect(x: 0, y: 0, width: width, height: height)
        stage.backgroundColor = NSColor(hex: 0xE9E4DB).cgColor

        let dock = CALayer()
        dock.frame = CGRect(x: 0, y: 0, width: width, height: 22)
        dock.backgroundColor = NSColor(hex: 0xD5CFC4).cgColor
        stage.addSublayer(dock)

        let juno = Buddy(style: .juno, scale: 2, feetY: 22)
        juno.x = 90
        let bo = Buddy(style: .bo, scale: 2, feetY: 22)
        bo.x = 220
        bo.facing = -1

        // Dressing-room variants, for reviewing new options
        var pigtailsSinglet = BuddyStyle.juno
        pigtailsSinglet.hatKind = .none
        pigtailsSinglet.hairKind = .pigtails
        pigtailsSinglet.hair = 0x5C4330
        pigtailsSinglet.topKind = .singlet
        pigtailsSinglet.outfit = 0x3B5BDB
        pigtailsSinglet.neckKind = .tie
        pigtailsSinglet.neckColor = 0x2E2A26
        pigtailsSinglet.glasses = false
        let withPigtails = Buddy(style: pigtailsSinglet, scale: 2, feetY: 22)
        withPigtails.x = 350

        var ponytailTee = BuddyStyle.bo
        ponytailTee.hatKind = .none
        ponytailTee.hairKind = .ponytail
        ponytailTee.hair = 0xE8C97A
        ponytailTee.topKind = .tshirt
        ponytailTee.outfit = 0xF09A8B
        ponytailTee.neckKind = .bow
        ponytailTee.neckColor = 0xC9B8F0
        ponytailTee.hasTote = false
        let withPonytail = Buddy(style: ponytailTee, scale: 2, feetY: 22)
        withPonytail.x = 480

        var longSkirt = BuddyStyle.bo
        longSkirt.hatKind = .none
        longSkirt.hairKind = .long
        longSkirt.hair = 0x5C4330
        longSkirt.neckKind = .none
        longSkirt.hasTote = false
        longSkirt.outfit = 0xF09A8B
        longSkirt.topKind = .jacket
        longSkirt.bottomKind = .skirt
        longSkirt.pants = 0x3B5BDB
        longSkirt.shoes = 0xF5F1E8
        let withLongSkirt = Buddy(style: longSkirt, scale: 2, feetY: 22)
        withLongSkirt.x = 610

        var bunSkirt = BuddyStyle.juno
        bunSkirt.hatKind = .none
        bunSkirt.hairKind = .bun
        bunSkirt.hair = 0xE8C97A
        bunSkirt.outfit = 0x4E6E52
        bunSkirt.topKind = .cardigan
        bunSkirt.bottomKind = .skirt
        bunSkirt.pants = 0xF2C14E
        let withBunSkirt = Buddy(style: bunSkirt, scale: 2, feetY: 22)
        withBunSkirt.x = 740

        var cropJacket = BuddyStyle.juno
        cropJacket.hairKind = .crop
        cropJacket.hair = 0x9C6B3C
        cropJacket.hatKind = .none
        cropJacket.topKind = .jacket
        cropJacket.outfit = 0x4E6E52
        let withCrop = Buddy(style: cropJacket, scale: 2, feetY: 22)
        withCrop.x = 870

        let variants = [withPigtails, withPonytail, withLongSkirt, withBunSkirt, withCrop]
        for buddy in [juno, bo] + variants {
            stage.addSublayer(buddy.root)
        }
        stage.addSublayer(juno.bubble.layer)

        juno.forcePose(phase: 1.15, walk: 1)
        for buddy in [bo] + variants {
            buddy.forcePose(phase: 0, walk: 0)
        }

        juno.bubble.layer.position = CGPoint(x: juno.x, y: 22 + 130)
        juno.bubble.show("on it!")

        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width * 2, pixelsHigh: height * 2,
            bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0
        ) else {
            fputs("snapshot: could not create bitmap\n", stderr)
            return
        }
        rep.size = NSSize(width: width, height: height)

        guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else {
            fputs("snapshot: could not create context\n", stderr)
            return
        }
        // rep.size is already set in points, so the context maps points to
        // the 2x pixel grid on its own; no extra scale needed.
        stage.render(in: ctx.cgContext)

        guard let png = rep.representation(using: .png, properties: [:]) else {
            fputs("snapshot: could not encode png\n", stderr)
            return
        }
        do {
            try png.write(to: URL(fileURLWithPath: path))
            print("snapshot written to \(path)")
        } catch {
            fputs("snapshot: \(error.localizedDescription)\n", stderr)
        }
    }
}
