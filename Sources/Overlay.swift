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

    // The full roster (all possible dockmates) and which names are currently
    // shown. rosterStyles is the source of truth for customizations; `buddies`
    // holds live instances for the visible ones only.
    private(set) var rosterStyles: [BuddyStyle] = []
    private var visibleNames: Set<String> = []
    private let catReactions = ["meow!", "mrrp?", "purr", "mew", "prrp"]
    private let dogReactions = ["woof!", "arf arf!", "boof", "wruff?", "awoo"]

    private func petSound(_ buddy: Buddy) -> String {
        (buddy.style.species == .dog ? dogReactions : catReactions).randomElement()!
    }

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

    private let greetings = ["hey!", "oh hi!", "fancy seeing you here", "hiya"]
    private let hoverGreetings = ["hi!", "hello!", "hey there"]
    private let rainChatter = [
        "brr, so wet out",
        "good thing i packed a brolly",
        "rain rain go away",
        "staying dry over here",
        "splish splash",
    ]

    // A minority of greetings turn into a little back-and-forth instead of a
    // single word. One buddy asks, the other answers after a beat.
    private let conversations: [(String, String)] = [
        ("busy day?", "just the usual strolling"),
        ("seen any good downloads lately?", "nothing exciting, sadly"),
        ("you doing okay?", "yep, all good here"),
        ("what time is it anyway?", "no idea, lost track ages ago"),
        ("how's the wifi treating you?", "surprisingly solid today"),
        ("any plans for later?", "just gonna keep pacing around"),
        ("dock's looking calm today", "yeah, nice and quiet"),
    ]

    // Weather chat only happens when we have real, current weather to report,
    // so the answer is always accurate. The question is picked at random; the
    // answer is the live summary from WeatherService.
    private let weatherQuestions = [
        "how's the weather out there?",
        "what's it doing outside?",
        "nice out today?",
    ]

    /// Returns a (question, answer) pair for a buddy exchange. When real
    /// current weather is available, it's used about half the time so the
    /// weather report is genuine; otherwise a canned exchange is used.
    private func pickConversation() -> (String, String) {
        if let weather = WeatherService.shared.summary, Bool.random() {
            return (weatherQuestions.randomElement()!, weather)
        }
        return conversations.randomElement()!
    }

    /// Fires every animation tick (about 30fps), after buddies and bubbles
    /// update. Lets AppController keep buddy-anchored panels glued in place.
    var onTick: (() -> Void)?

    private var hoveredBuddy: Buddy?

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
        rosterStyles = loadRoster()
        visibleNames = loadVisible()
        rebuildBuddies()

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

    // MARK: - Roster & visibility

    /// Merge saved customizations (by name) onto the full default roster, so
    /// old 2-entry saves still load and unknown/new members fall to defaults.
    private func loadRoster() -> [BuddyStyle] {
        let defaults = BuddyStyle.roster
        guard let data = UserDefaults.standard.data(forKey: "buddyStyles"),
              let saved = try? JSONDecoder().decode([BuddyStyle].self, from: data) else {
            return defaults
        }
        return defaults.map { def in saved.first { $0.name == def.name } ?? def }
    }

    private func loadVisible() -> Set<String> {
        if let arr = UserDefaults.standard.stringArray(forKey: "dockmateVisible") {
            return Set(arr)
        }
        // First run of this version: show everyone (incl. the pets) so they're
        // discoverable; the menu lets the user hide whoever they want (e.g.
        // keep just one pet).
        return ["Juno", "Bo", "Mochi", "Tofu"]
    }

    private func saveVisible() {
        UserDefaults.standard.set(Array(visibleNames), forKey: "dockmateVisible")
    }

    func isVisible(_ name: String) -> Bool { visibleNames.contains(name) }

    /// Show or hide a dockmate by name, rebuilding the live set on the dock.
    func setVisible(_ name: String, _ visible: Bool) {
        if visible { visibleNames.insert(name) } else { visibleNames.remove(name) }
        saveVisible()
        rebuildBuddies()
    }

    /// Copy live buddies' styles back into the roster (called before saving so
    /// dressing-room edits to visible members persist).
    func syncRosterFromBuddies() {
        for buddy in buddies {
            if let i = rosterStyles.firstIndex(where: { $0.name == buddy.style.name }) {
                rosterStyles[i] = buddy.style
            }
        }
    }

    private func rebuildBuddies() {
        let scale = NSScreen.screens.first?.backingScaleFactor ?? 2
        for buddy in buddies {
            buddy.root.removeFromSuperlayer()
            buddy.bubble.layer.removeFromSuperlayer()
        }

        let visible = rosterStyles.filter { visibleNames.contains($0.name) }
        buddies = visible.map { Buddy(style: $0, scale: scale, feetY: feetY) }
        for buddy in buddies {
            buddy.wanderEnabled = strolling
            stageLayer.addSublayer(buddy.root)
            stageLayer.addSublayer(buddy.bubble.layer)
        }

        layout()

        // Spread them out across the dock so they don't overlap on spawn.
        if !buddies.isEmpty {
            let width = NSScreen.screens.first?.frame.width ?? 1200
            let lo = width * 0.32, hi = width * 0.62
            for (i, buddy) in buddies.enumerated() {
                let t = buddies.count == 1 ? 0.5 : CGFloat(i) / CGFloat(buddies.count - 1)
                buddy.x = lo + (hi - lo) * t
                if i % 2 == 1 { buddy.facing = -1 }
            }
        }
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

        let raining = WeatherService.shared.isRaining

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        for buddy in buddies {
            buddy.tick(dt: dt, now: now)
            buddy.bubble.layer.position = CGPoint(x: buddy.x, y: buddy.bubbleY)
            buddy.setRaining(raining)  // pops the umbrella when it's wet out

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

        // Idle chatter (rain-flavored when it's actually raining)
        if now >= nextChatterAt {
            nextChatterAt = now + .random(in: 24...48)
            let idle = buddies.filter { !$0.busy && !$0.bubble.visible }
            let pool = (raining && Bool.random()) ? rainChatter : chatter
            if let buddy = idle.randomElement(), let line = pool.randomElement() {
                buddy.bubble.show(line, for: 3.2)
            }
        }

        // Buddies say hi when they wander close to each other
        if buddies.count >= 2 {
            for i in 0..<buddies.count {
                for j in (i + 1)..<buddies.count {
                    let a = buddies[i]
                    let b = buddies[j]
                    guard !a.busy, !b.busy, !a.beingDragged, !b.beingDragged else { continue }
                    // Long cooldown: two buddies sharing a dock cross paths
                    // often, and this should read as an occasional charming
                    // moment, not a running conversation every time they meet.
                    guard now - a.lastGreetAt > 90, now - b.lastGreetAt > 90 else { continue }
                    guard abs(a.x - b.x) < 48 else { continue }
                    a.lastGreetAt = now
                    b.lastGreetAt = now
                    a.facing = b.x >= a.x ? 1 : -1
                    b.facing = a.x >= b.x ? 1 : -1
                    a.celebrate()
                    b.celebrate()

                    // A minority of the time, upgrade the plain "hey!" into
                    // a little question-and-answer exchange instead. The
                    // 90s cooldown above already keeps greetings rare; this
                    // only changes what a greeting looks like, not how
                    // often one happens.
                    if Double.random(in: 0...1) < 0.35 {
                        let pair = pickConversation()
                        let asker = Bool.random() ? a : b
                        let answerer = asker === a ? b : a
                        asker.bubble.show(pair.0, for: 2.6)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak answerer] in
                            // Skip the answer if they've since been picked up
                            // or given something else to do mid-exchange.
                            guard let answerer, !answerer.busy, !answerer.beingDragged else { return }
                            answerer.hop()
                            answerer.bubble.show(pair.1, for: 2.4)
                        }
                    } else {
                        (Bool.random() ? a : b).bubble.show(greetings.randomElement()!, for: 2.2)
                    }
                }
            }
        }

        // Intercept the mouse while it hovers a buddy, or throughout a drag
        let mouse = NSEvent.mouseLocation
        let local = NSPoint(x: mouse.x - window.frame.minX, y: mouse.y - window.frame.minY)
        let hovered = buddyAt(local)
        let over = interacting || hovered != nil
        if window.ignoresMouseEvents == over {
            window.ignoresMouseEvents = !over
        }

        // A little hello wave the first moment the cursor lands on a buddy
        if hovered !== hoveredBuddy {
            hoveredBuddy = hovered
            if let hovered, !hovered.busy, !hovered.beingDragged, now - hovered.lastWaveAt > 5 {
                hovered.lastWaveAt = now
                hovered.wave()
                if Bool.random(), !hovered.bubble.visible {
                    hovered.bubble.show(hoverGreetings.randomElement()!, for: 1.6)
                }
            }
        }

        onTick?()
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
        buddy.bubble.layer.position = CGPoint(x: newX, y: buddy.bubbleY)
        CATransaction.commit()
    }

    private func handleMouseUp(_ point: NSPoint) {
        guard let buddy = pressedBuddy else { return }
        if didDrag {
            buddy.endDrag()
            NSCursor.arrow.set()
            if !buddy.busy {
                buddy.bubble.show(buddy.isPet ? petSound(buddy) : "wheee!", for: 1.4)
            }
        } else if buddy.isPet {
            // A pet doesn't run Claude tasks; clicking it just gets a happy
            // little reaction.
            buddy.hop()
            buddy.bubble.show(petSound(buddy), for: 1.6)
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
                y: window.frame.minY + buddy.bubbleY + 35)
    }

    /// First free buddy of any kind (nil if the dock is empty).
    func firstFreeBuddy() -> Buddy? {
        buddies.first { !$0.busy } ?? buddies.first
    }

    /// First free person buddy, preferred for Claude asks (a cat doesn't run
    /// tasks). Falls back to any free buddy, then nil if the dock is empty.
    func firstFreePerson() -> Buddy? {
        buddies.first { !$0.busy && !$0.isPet }
            ?? buddies.first { !$0.isPet }
            ?? firstFreeBuddy()
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

    /// Renders one buddy across a full walk cycle (several swing phases) so
    /// the arm/leg motion can be reviewed as a filmstrip, not a single frame.
    static func writeRoster(to path: String) {
        let width = 760
        let height = 300

        let stage = CALayer()
        stage.frame = CGRect(x: 0, y: 0, width: width, height: height)
        stage.backgroundColor = NSColor(hex: 0xE9E4DB).cgColor
        let dock = CALayer()
        dock.frame = CGRect(x: 0, y: 0, width: width, height: 24)
        dock.backgroundColor = NSColor(hex: 0xD5CFC4).cgColor
        stage.addSublayer(dock)

        let scale: CGFloat = 2
        let juno = Buddy(style: .juno, scale: scale, feetY: 24); juno.x = 180
        let bo = Buddy(style: .bo, scale: scale, feetY: 24); bo.x = 380; bo.facing = -1
        let mochi = Buddy(style: .mochi, scale: scale, feetY: 24); mochi.x = 560

        for buddy in [juno, bo, mochi] {
            stage.addSublayer(buddy.root)
            buddy.forcePose(phase: 0, walk: 0)
        }
        stage.addSublayer(mochi.bubble.layer)
        mochi.bubble.show("meow!")
        mochi.bubble.layer.position = CGPoint(x: mochi.x, y: mochi.bubbleY)

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
        print("roster written to \(path)")
    }

    static func writeCat(to path: String) {
        let width = 1880
        let height = 340
        let zoom: CGFloat = 3.0

        let stage = CALayer()
        stage.frame = CGRect(x: 0, y: 0, width: width, height: height)
        stage.backgroundColor = NSColor(hex: 0xE9E4DB).cgColor

        // Each pet wearing each accessory, to review the dress-up options.
        let accessories: [PetAccessory] = [.none, .bow, .bandana, .hat]
        var x: CGFloat = 120
        for base in [BuddyStyle.mochi, BuddyStyle.tofu] {
            for acc in accessories {
                var s = base
                s.petAccessory = acc
                let pet = Buddy(style: s, scale: 3, feetY: 20)
                pet.x = x
                stage.addSublayer(pet.root)
                pet.forcePose(phase: 0, walk: 0)
                pet.root.transform = CATransform3DMakeScale(zoom, zoom, 1)
                x += 230
            }
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
        print("cat written to \(path)")
    }

    static func writeRain(to path: String) {
        let width = 700
        let height = 420
        let zoom: CGFloat = 2.6

        let stage = CALayer()
        stage.frame = CGRect(x: 0, y: 0, width: width, height: height)
        stage.backgroundColor = NSColor(hex: 0xE9E4DB).cgColor

        let juno = Buddy(style: .juno, scale: 3, feetY: 10)
        juno.x = 190
        stage.addSublayer(juno.root)
        juno.setRaining(true)
        juno.forcePose(phase: 1.15, walk: 1)  // mid-stride
        juno.root.transform = CATransform3DMakeScale(zoom, zoom, 1)

        let bo = Buddy(style: .bo, scale: 3, feetY: 10)
        bo.x = 510
        bo.facing = -1
        stage.addSublayer(bo.root)
        bo.setRaining(true)
        bo.forcePose(phase: 0, walk: 0)  // standing
        bo.root.transform = CATransform3DMakeScale(zoom * bo.facing, zoom, 1)

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
        print("rain umbrella written to \(path)")
    }

    static func writeWalk(to path: String) {
        let width = 1320
        let height = 300
        let zoom: CGFloat = 2.2

        let stage = CALayer()
        stage.frame = CGRect(x: 0, y: 0, width: width, height: height)
        stage.backgroundColor = NSColor(hex: 0xE9E4DB).cgColor

        // Six evenly-spaced steps across one full cycle, so a staggered
        // (one-after-another) arm swing is visible as a cascade.
        let phases: [Double] = (0..<6).map { Double($0) * (2 * .pi / 6) }
        var x: CGFloat = 120
        for phase in phases {
            var s = BuddyStyle.juno
            s.glasses = false
            let buddy = Buddy(style: s, scale: 3, feetY: 20)
            buddy.x = x
            stage.addSublayer(buddy.root)
            buddy.forcePose(phase: phase, walk: 1)
            buddy.root.transform = CATransform3DMakeScale(zoom, zoom, 1)
            x += 220
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
        print("walk cycle written to \(path)")
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

    static func writeShoulderZoom(to path: String) {
        let width = 500
        let height = 500
        let zoom: CGFloat = 5.5

        let stage = CALayer()
        stage.frame = CGRect(x: 0, y: 0, width: width, height: height)
        stage.backgroundColor = NSColor(hex: 0xE9E4DB).cgColor

        let buddy = Buddy(style: .bo, scale: 3, feetY: -60)
        buddy.x = CGFloat(width) / 2
        stage.addSublayer(buddy.root)
        buddy.forcePose(phase: 0, walk: 0)
        buddy.root.transform = CATransform3DMakeScale(zoom, zoom, 1)

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
        print("shoulder zoom written to \(path)")
    }

    static func writeWave(to path: String) {
        let width = 300
        let height = 320
        let zoom: CGFloat = 3

        let stage = CALayer()
        stage.frame = CGRect(x: 0, y: 0, width: width, height: height)
        stage.backgroundColor = NSColor(hex: 0xE9E4DB).cgColor

        let buddy = Buddy(style: .juno, scale: 3, feetY: 10)
        buddy.x = CGFloat(width) / 2
        stage.addSublayer(buddy.root)
        if CommandLine.arguments.contains("--held") {
            buddy.beginDrag()
            buddy.forcePose(phase: 0, walk: 0)
        } else {
            buddy.forcePose(phase: 0, walk: 0)
            buddy.wave()
            // wave() timestamps against lastNow (still 0, since forcePose only
            // feeds a local "now" into applyPose and never touches lastNow),
            // so a small explicit elapsed time here lands mid-wave.
            buddy.applyPose(now: 0.35)
        }
        buddy.root.transform = CATransform3DMakeScale(zoom, zoom, 1)

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
        print("wave pose written to \(path)")
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
