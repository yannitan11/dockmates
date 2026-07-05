import AppKit
import QuartzCore

enum HatKind { case beanie, bucket }

struct BuddyStyle {
    let name: String
    let skin: NSColor
    let outfit: NSColor
    let pants: NSColor
    let shoes: NSColor
    let hat: NSColor
    let hatKind: HatKind
    let glasses: Bool
    let scarf: NSColor?
    let hasTote: Bool
    let strollSpeed: CGFloat

    static let juno = BuddyStyle(
        name: "Juno",
        skin: Theme.skinWarm,
        outfit: Theme.accent,
        pants: Theme.offBlack,
        shoes: Theme.cream,
        hat: Theme.offBlack,
        hatKind: .beanie,
        glasses: true,
        scarf: nil,
        hasTote: false,
        strollSpeed: 44
    )

    static let bo = BuddyStyle(
        name: "Bo",
        skin: Theme.skinTan,
        outfit: Theme.sage,
        pants: Theme.cream,
        shoes: Theme.offBlack,
        hat: Theme.lilac,
        hatKind: .bucket,
        glasses: false,
        scarf: Theme.mustard,
        hasTote: true,
        strollSpeed: 36
    )
}

final class Buddy {
    enum Mode { case idle, think, celebrate }

    let style: BuddyStyle
    let root = CALayer()
    let bubble: SpeechBubble
    let feetY: CGFloat

    private let figure = CALayer()
    private var legL = CAShapeLayer()
    private var legR = CAShapeLayer()
    private var armL = CAShapeLayer()
    private var armR = CAShapeLayer()
    private let headGroup = CALayer()
    private var eyes: [CAShapeLayer] = []

    // Motion state
    var x: CGFloat = 0 {
        didSet { root.position = CGPoint(x: x, y: feetY) }
    }
    var facing: CGFloat = 1
    var bounds: ClosedRange<CGFloat> = 60...600
    var wanderEnabled = true
    private(set) var busy = false
    private(set) var mode: Mode = .idle

    var walkPhase: Double = .random(in: 0...6)
    var walkAmount: Double = 0
    private var targetX: CGFloat?
    private var nextWanderAt: TimeInterval = 0
    private var thinkOrigin: CGFloat = 0
    private var thinkStart: TimeInterval = 0
    private var nextPaceAt: TimeInterval = 0
    private var celebrateUntil: TimeInterval = 0
    private var hopStart: TimeInterval?
    private let hopDuration: TimeInterval = 0.5
    private var nextBlinkAt: TimeInterval = 0
    private var blinkUntil: TimeInterval = 0
    private var lastNow: TimeInterval = 0

    var thinkElapsed: TimeInterval { lastNow - thinkStart }

    init(style: BuddyStyle, scale: CGFloat, feetY: CGFloat) {
        self.style = style
        self.feetY = feetY
        self.bubble = SpeechBubble(scale: scale)
        buildLayers()
        applyContentsScale(root, scale)
        root.position = CGPoint(x: x, y: feetY)
    }

    // MARK: - Art

    private func buildLayers() {
        root.bounds = CGRect(x: 0, y: 0, width: 70, height: 122)
        root.anchorPoint = CGPoint(x: 0.5, y: 0)

        // Grounded shadow (does not bob with the figure)
        let shadow = ellipse(CGRect(x: 9, y: -3, width: 52, height: 7),
                             Theme.ink.withAlphaComponent(0.10))
        root.addSublayer(shadow)

        figure.frame = root.bounds
        root.addSublayer(figure)

        // Legs (pivot at the hip). The left-side limbs are shaded as the
        // far side so the walk cycle reads with depth.
        let farPants = style.pants.blended(withFraction: 0.16, of: .black) ?? style.pants
        let farShoes = style.shoes.blended(withFraction: 0.16, of: .black) ?? style.shoes
        legL = rounded(CGRect(x: 20, y: 0, width: 13, height: 32), 6, farPants)
        legR = rounded(CGRect(x: 37, y: 0, width: 13, height: 32), 6, style.pants)
        for (leg, shoeColor) in [(legL, farShoes), (legR, style.shoes)] {
            let shoe = rounded(CGRect(x: -2, y: -2, width: 19, height: 9), 4.5, shoeColor)
            leg.addSublayer(shoe)
            setAnchor(leg, CGPoint(x: 0.5, y: 0.95))
            figure.addSublayer(leg)
        }

        // Arms (pivot at the shoulder), tucked behind the torso
        let farOutfit = style.outfit.blended(withFraction: 0.14, of: .black) ?? style.outfit
        armL = rounded(CGRect(x: 3, y: 36, width: 12, height: 30), 6, farOutfit)
        armR = rounded(CGRect(x: 55, y: 36, width: 12, height: 30), 6, style.outfit)
        for arm in [armL, armR] {
            let hand = ellipse(CGRect(x: 1.5, y: -2, width: 9, height: 9), style.skin)
            arm.addSublayer(hand)
            setAnchor(arm, CGPoint(x: 0.5, y: 0.94))
            figure.addSublayer(arm)
        }

        // Torso
        let torso = rounded(CGRect(x: 8, y: 26, width: 54, height: 50), 16, style.outfit)
        figure.addSublayer(torso)

        // Outfit details
        let detailColor = style.outfit.blended(withFraction: 0.22, of: .black) ?? style.outfit
        if style.hatKind == .beanie {
            // Jacket pockets
            torso.addSublayer(rounded(CGRect(x: 8, y: 10, width: 13, height: 4), 2, detailColor))
            torso.addSublayer(rounded(CGRect(x: 33, y: 10, width: 13, height: 4), 2, detailColor))
        } else {
            // Cardigan buttons
            for i in 0..<3 {
                torso.addSublayer(ellipse(CGRect(x: 25.5, y: 12 + CGFloat(i) * 11, width: 3, height: 3),
                                          Theme.ink.withAlphaComponent(0.3)))
            }
        }

        // Scarf sits on the torso, behind the head
        if let scarfColor = style.scarf {
            figure.addSublayer(rounded(CGRect(x: 18, y: 66, width: 34, height: 9), 4.5, scarfColor))
            figure.addSublayer(rounded(CGRect(x: 38, y: 48, width: 11, height: 20), 5, scarfColor))
        }

        // Head group (tilts while thinking)
        headGroup.frame = CGRect(x: 12, y: 70, width: 46, height: 48)
        setAnchor(headGroup, CGPoint(x: 0.5, y: 0.15))
        figure.addSublayer(headGroup)

        let head = ellipse(CGRect(x: 5, y: 2, width: 36, height: 36), style.skin)
        headGroup.addSublayer(head)

        // Face (drawn facing right; the whole root flips for direction)
        let eyeA = ellipse(CGRect(x: 13, y: 15.5, width: 4, height: 4), Theme.ink)
        let eyeB = ellipse(CGRect(x: 24, y: 15.5, width: 4, height: 4), Theme.ink)
        eyes = [eyeA, eyeB]
        head.addSublayer(eyeA)
        head.addSublayer(eyeB)

        // In this y-up layer space, clockwise: false sweeps through the
        // bottom of the circle, which is what makes it a smile.
        let smile = CAShapeLayer()
        let smilePath = CGMutablePath()
        smilePath.addArc(center: CGPoint(x: 20.5, y: 11), radius: 3,
                         startAngle: .pi * 200 / 180, endAngle: .pi * 340 / 180,
                         clockwise: false)
        smile.path = smilePath
        smile.strokeColor = Theme.ink.cgColor
        smile.fillColor = nil
        smile.lineWidth = 1.6
        smile.lineCap = .round
        head.addSublayer(smile)

        head.addSublayer(rounded(CGRect(x: 6, y: 12, width: 5, height: 3), 1.5,
                                 Theme.blush.withAlphaComponent(0.5)))
        head.addSublayer(rounded(CGRect(x: 28, y: 12, width: 5, height: 3), 1.5,
                                 Theme.blush.withAlphaComponent(0.5)))

        if style.glasses {
            for cx in [15.0, 26.0] {
                let ring = CAShapeLayer()
                ring.path = CGPath(ellipseIn: CGRect(x: cx - 4.5, y: 13, width: 9, height: 9),
                                   transform: nil)
                ring.strokeColor = Theme.ink.cgColor
                ring.fillColor = nil
                ring.lineWidth = 1.4
                head.addSublayer(ring)
            }
            let bridge = CAShapeLayer()
            let bridgePath = CGMutablePath()
            bridgePath.move(to: CGPoint(x: 19.5, y: 18))
            bridgePath.addLine(to: CGPoint(x: 21.5, y: 18))
            bridge.path = bridgePath
            bridge.strokeColor = Theme.ink.cgColor
            bridge.lineWidth = 1.4
            bridge.lineCap = .round
            head.addSublayer(bridge)
        }

        // Hat
        switch style.hatKind {
        case .beanie:
            let band = style.hat.blended(withFraction: 0.18, of: .white) ?? style.hat
            headGroup.addSublayer(rounded(CGRect(x: 3, y: 27, width: 40, height: 15), 10, style.hat))
            headGroup.addSublayer(rounded(CGRect(x: 3, y: 25, width: 40, height: 6), 3, band))
        case .bucket:
            headGroup.addSublayer(rounded(CGRect(x: 7, y: 29, width: 32, height: 13), 8, style.hat))
            let brim = style.hat.blended(withFraction: 0.12, of: .black) ?? style.hat
            headGroup.addSublayer(ellipse(CGRect(x: 1, y: 25, width: 44, height: 8), brim))
        }

        // Tote bag in front
        if style.hasTote {
            let strap = CAShapeLayer()
            let strapPath = CGMutablePath()
            strapPath.move(to: CGPoint(x: 56, y: 68))
            strapPath.addLine(to: CGPoint(x: 62, y: 50))
            strap.path = strapPath
            strap.strokeColor = (Theme.sky.blended(withFraction: 0.35, of: .black) ?? Theme.sky).cgColor
            strap.lineWidth = 2.5
            strap.lineCap = .round
            figure.addSublayer(strap)

            let bag = rounded(CGRect(x: 52, y: 28, width: 20, height: 23), 4, Theme.sky)
            // Tiny smiley on the tote
            bag.addSublayer(ellipse(CGRect(x: 6, y: 13, width: 2.5, height: 2.5), Theme.ink))
            bag.addSublayer(ellipse(CGRect(x: 11.5, y: 13, width: 2.5, height: 2.5), Theme.ink))
            let bagSmile = CAShapeLayer()
            let bagSmilePath = CGMutablePath()
            bagSmilePath.addArc(center: CGPoint(x: 10, y: 11), radius: 2.5,
                                startAngle: .pi * 200 / 180, endAngle: .pi * 340 / 180,
                                clockwise: false)
            bagSmile.path = bagSmilePath
            bagSmile.strokeColor = Theme.ink.cgColor
            bagSmile.fillColor = nil
            bagSmile.lineWidth = 1.2
            bagSmile.lineCap = .round
            bag.addSublayer(bagSmile)
            figure.addSublayer(bag)
        }
    }

    private func rounded(_ frame: CGRect, _ radius: CGFloat, _ color: NSColor) -> CAShapeLayer {
        let layer = CAShapeLayer()
        layer.frame = frame
        let r = min(radius, min(frame.width, frame.height) / 2)
        layer.path = CGPath(roundedRect: CGRect(origin: .zero, size: frame.size),
                            cornerWidth: r, cornerHeight: r, transform: nil)
        layer.fillColor = color.cgColor
        return layer
    }

    private func ellipse(_ frame: CGRect, _ color: NSColor) -> CAShapeLayer {
        let layer = CAShapeLayer()
        layer.frame = frame
        layer.path = CGPath(ellipseIn: CGRect(origin: .zero, size: frame.size), transform: nil)
        layer.fillColor = color.cgColor
        return layer
    }

    private func setAnchor(_ layer: CALayer, _ anchor: CGPoint) {
        let f = layer.frame
        layer.anchorPoint = anchor
        layer.position = CGPoint(x: f.minX + f.width * anchor.x,
                                 y: f.minY + f.height * anchor.y)
    }

    private func applyContentsScale(_ layer: CALayer, _ scale: CGFloat) {
        layer.contentsScale = scale
        layer.sublayers?.forEach { applyContentsScale($0, scale) }
    }

    // MARK: - Behavior

    func beginThinking() {
        busy = true
        mode = .think
        thinkOrigin = x
        thinkStart = lastNow
        targetX = nil
        nextPaceAt = lastNow + 1.2
    }

    func celebrate() {
        mode = .celebrate
        celebrateUntil = lastNow + 1.8
        hopStart = nil
    }

    func stopBusy() {
        busy = false
        mode = .idle
        targetX = nil
        nextWanderAt = lastNow + 2
    }

    func hop() {
        hopStart = lastNow
    }

    func tick(dt: TimeInterval, now: TimeInterval) {
        lastNow = now

        switch mode {
        case .think:
            if targetX == nil && now >= nextPaceAt {
                let lo = max(bounds.lowerBound, thinkOrigin - 40)
                let hi = min(bounds.upperBound, thinkOrigin + 40)
                if lo < hi { targetX = .random(in: lo...hi) }
                nextPaceAt = now + .random(in: 1.4...2.8)
            }
        case .celebrate:
            if hopStart == nil {
                hopStart = now
            } else if now - hopStart! > hopDuration + 0.1 && now < celebrateUntil {
                hopStart = now
            }
            if now >= celebrateUntil {
                mode = .idle
                busy = false
                nextWanderAt = now + .random(in: 1.5...4)
            }
        case .idle:
            if !busy && wanderEnabled && targetX == nil && now >= nextWanderAt {
                let candidate = CGFloat.random(in: bounds)
                if abs(candidate - x) > 40 {
                    targetX = candidate
                } else {
                    nextWanderAt = now + 2
                }
            }
        }

        var moving = false
        if let t = targetX {
            let speed: CGFloat = mode == .think ? 26 : style.strollSpeed
            let dx = t - x
            let step = speed * CGFloat(dt)
            if abs(dx) <= step {
                x = t
                targetX = nil
                if mode != .think { nextWanderAt = now + .random(in: 2.5...8) }
            } else {
                x += dx > 0 ? step : -step
                facing = dx > 0 ? 1 : -1
                moving = true
            }
        }

        if moving { walkPhase += dt * 9.5 }
        let targetAmount: Double = moving ? 1 : 0
        walkAmount += (targetAmount - walkAmount) * min(1, dt * 7)

        applyPose(now: now)
    }

    func forcePose(phase: Double, walk: Double) {
        walkPhase = phase
        walkAmount = walk
        nextBlinkAt = 2000  // keep the eyes open for the still frame
        blinkUntil = 0
        applyPose(now: 1000)
    }

    func applyPose(now: TimeInterval) {
        let swing = CGFloat(sin(walkPhase)) * CGFloat(walkAmount)
        legL.transform = CATransform3DMakeRotation(swing * 0.38, 0, 0, 1)
        legR.transform = CATransform3DMakeRotation(-swing * 0.38, 0, 0, 1)
        armL.transform = CATransform3DMakeRotation(-swing * 0.3, 0, 0, 1)
        armR.transform = CATransform3DMakeRotation(swing * 0.3, 0, 0, 1)

        var lift = abs(CGFloat(sin(walkPhase))) * 2.4 * CGFloat(walkAmount)
        if let hs = hopStart {
            let t = now - hs
            if t < hopDuration {
                lift += CGFloat(sin(.pi * t / hopDuration)) * 15
            } else if mode != .celebrate {
                hopStart = nil
            }
        }

        let breathe = (1 - walkAmount) * 0.015 * sin(now * 2.2)
        var tf = CATransform3DMakeTranslation(0, lift, 0)
        tf = CATransform3DScale(tf, 1, 1 + CGFloat(breathe), 1)
        figure.transform = tf

        if mode == .think {
            headGroup.transform = CATransform3DMakeRotation(CGFloat(sin(now * 1.6)) * 0.07, 0, 0, 1)
        } else {
            headGroup.transform = CATransform3DIdentity
        }

        if now >= nextBlinkAt {
            blinkUntil = now + 0.12
            nextBlinkAt = now + .random(in: 2.5...5.5)
        }
        let eyeScale: CGFloat = now < blinkUntil ? 0.15 : 1
        for eye in eyes {
            eye.transform = CATransform3DMakeScale(1, eyeScale, 1)
        }

        root.transform = CATransform3DMakeScale(facing, 1, 1)
    }

    func hitRect() -> CGRect {
        CGRect(x: x - 42, y: feetY - 8, width: 84, height: 140)
    }
}
