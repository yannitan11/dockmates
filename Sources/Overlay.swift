import AppKit
import QuartzCore

final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class StageView: NSView {
    var onClick: ((NSPoint) -> Void)?

    override func mouseDown(with event: NSEvent) {
        onClick?(convert(event.locationInWindow, from: nil))
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

    private var timer: Timer?
    private var lastTick = CACurrentMediaTime()
    private var nextChatterAt = CACurrentMediaTime() + .random(in: 14...26)
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

        stageView.onClick = { [weak self] point in
            self?.handleClick(at: point)
        }
    }

    func start() {
        let scale = NSScreen.screens.first?.backingScaleFactor ?? 2

        let juno = Buddy(style: .juno, scale: scale, feetY: feetY)
        let bo = Buddy(style: .bo, scale: scale, feetY: feetY)
        buddies = [juno, bo]
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

        // Only intercept the mouse while it hovers a buddy
        let mouse = NSEvent.mouseLocation
        let local = NSPoint(x: mouse.x - window.frame.minX, y: mouse.y - window.frame.minY)
        let over = buddyAt(local) != nil
        if window.ignoresMouseEvents == over {
            window.ignoresMouseEvents = !over
        }
    }

    private func buddyAt(_ point: NSPoint) -> Buddy? {
        buddies.first { $0.hitRect().contains(point) }
    }

    private func handleClick(at point: NSPoint) {
        guard let buddy = buddyAt(point) else { return }
        if buddy.busy {
            buddy.bubble.show("still on it, one sec", for: 2)
        } else {
            buddy.hop()
            onBuddyClicked?(buddy)
        }
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
    static func write(to path: String) {
        let width = 760
        let height = 320

        let stage = CALayer()
        stage.frame = CGRect(x: 0, y: 0, width: width, height: height)
        stage.backgroundColor = NSColor(hex: 0xE9E4DB).cgColor

        let dock = CALayer()
        dock.frame = CGRect(x: 0, y: 0, width: width, height: 22)
        dock.backgroundColor = NSColor(hex: 0xD5CFC4).cgColor
        stage.addSublayer(dock)

        let juno = Buddy(style: .juno, scale: 2, feetY: 22)
        juno.x = 240
        let bo = Buddy(style: .bo, scale: 2, feetY: 22)
        bo.x = 480
        bo.facing = -1

        stage.addSublayer(juno.root)
        stage.addSublayer(bo.root)
        stage.addSublayer(juno.bubble.layer)

        juno.forcePose(phase: 1.15, walk: 1)
        bo.forcePose(phase: 0, walk: 0)

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
