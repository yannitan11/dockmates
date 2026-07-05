import AppKit
import QuartzCore

enum HatKind: String, Codable, CaseIterable { case none, beanie, bucket }
enum HairKind: String, Codable, CaseIterable { case none, crop, bob, long, bun }
enum BottomKind: String, Codable, CaseIterable { case pants, skirt }
enum OutfitDetail: String, Codable { case pockets, buttons }

/// Everything editable about a buddy. Colors are stored as hex so the whole
/// style round-trips through JSON for persistence.
struct BuddyStyle: Codable {
    var name: String
    var skin: UInt32
    var outfit: UInt32
    var pants: UInt32
    var shoes: UInt32
    var hatKind: HatKind
    var hat: UInt32
    var hairKind: HairKind
    var hair: UInt32
    var bottomKind: BottomKind = .pants
    var glasses: Bool
    var scarfOn: Bool
    var scarf: UInt32
    var hasTote: Bool
    var outfitDetail: OutfitDetail
    var strollSpeed: CGFloat

    // Custom decoding so styles saved by older builds (without newer fields
    // like bottomKind) still load instead of silently resetting to defaults.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        skin = try c.decode(UInt32.self, forKey: .skin)
        outfit = try c.decode(UInt32.self, forKey: .outfit)
        pants = try c.decode(UInt32.self, forKey: .pants)
        shoes = try c.decode(UInt32.self, forKey: .shoes)
        hatKind = try c.decode(HatKind.self, forKey: .hatKind)
        hat = try c.decode(UInt32.self, forKey: .hat)
        hairKind = try c.decode(HairKind.self, forKey: .hairKind)
        hair = try c.decode(UInt32.self, forKey: .hair)
        bottomKind = try c.decodeIfPresent(BottomKind.self, forKey: .bottomKind) ?? .pants
        glasses = try c.decode(Bool.self, forKey: .glasses)
        scarfOn = try c.decode(Bool.self, forKey: .scarfOn)
        scarf = try c.decode(UInt32.self, forKey: .scarf)
        hasTote = try c.decode(Bool.self, forKey: .hasTote)
        outfitDetail = try c.decode(OutfitDetail.self, forKey: .outfitDetail)
        strollSpeed = try c.decode(CGFloat.self, forKey: .strollSpeed)
    }

    init(name: String, skin: UInt32, outfit: UInt32, pants: UInt32, shoes: UInt32,
         hatKind: HatKind, hat: UInt32, hairKind: HairKind, hair: UInt32,
         bottomKind: BottomKind = .pants, glasses: Bool, scarfOn: Bool, scarf: UInt32,
         hasTote: Bool, outfitDetail: OutfitDetail, strollSpeed: CGFloat) {
        self.name = name
        self.skin = skin
        self.outfit = outfit
        self.pants = pants
        self.shoes = shoes
        self.hatKind = hatKind
        self.hat = hat
        self.hairKind = hairKind
        self.hair = hair
        self.bottomKind = bottomKind
        self.glasses = glasses
        self.scarfOn = scarfOn
        self.scarf = scarf
        self.hasTote = hasTote
        self.outfitDetail = outfitDetail
        self.strollSpeed = strollSpeed
    }

    var skinColor: NSColor { NSColor(hex: skin) }
    var outfitColor: NSColor { NSColor(hex: outfit) }
    var pantsColor: NSColor { NSColor(hex: pants) }
    var shoesColor: NSColor { NSColor(hex: shoes) }
    var hatColor: NSColor { NSColor(hex: hat) }
    var hairColor: NSColor { NSColor(hex: hair) }
    var scarfColor: NSColor { NSColor(hex: scarf) }

    static let juno = BuddyStyle(
        name: "Juno",
        skin: 0xF3C9A6, outfit: 0xFF6B2C, pants: 0x2E2A26, shoes: 0xF5F1E8,
        hatKind: .beanie, hat: 0x2E2A26,
        hairKind: .none, hair: 0x2E2A26,
        glasses: true, scarfOn: false, scarf: 0xF2C14E, hasTote: false,
        outfitDetail: .pockets, strollSpeed: 44
    )

    static let bo = BuddyStyle(
        name: "Bo",
        skin: 0xC98D5E, outfit: 0x9DBE8D, pants: 0xF5F1E8, shoes: 0x2E2A26,
        hatKind: .bucket, hat: 0xC9B8F0,
        hairKind: .none, hair: 0x2E2A26,
        glasses: false, scarfOn: true, scarf: 0xF2C14E, hasTote: true,
        outfitDetail: .buttons, strollSpeed: 36
    )

    static var defaults: [BuddyStyle] { [.juno, .bo] }
}

final class Buddy {
    enum Mode { case idle, think, celebrate }

    private(set) var style: BuddyStyle
    let root = CALayer()
    let bubble: SpeechBubble
    let feetY: CGFloat
    private let scale: CGFloat

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
        self.scale = scale
        self.feetY = feetY
        self.bubble = SpeechBubble(scale: scale)
        buildLayers()
        applyContentsScale(root, scale)
        root.position = CGPoint(x: x, y: feetY)
    }

    /// Swap in a new look and redraw the character in place.
    func applyStyle(_ newStyle: BuddyStyle) {
        style = newStyle
        root.sublayers?.forEach { $0.removeFromSuperlayer() }
        figure.sublayers?.forEach { $0.removeFromSuperlayer() }
        headGroup.sublayers?.forEach { $0.removeFromSuperlayer() }
        eyes = []
        buildLayers()
        applyContentsScale(root, scale)
        root.position = CGPoint(x: x, y: feetY)
        nextBlinkAt = lastNow + 3  // don't restyle mid-blink
        blinkUntil = 0
        applyPose(now: lastNow)
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
        figure.transform = CATransform3DIdentity
        root.addSublayer(figure)

        // Legs (pivot at the hip). The left-side limbs are shaded as the
        // far side so the walk cycle reads with depth. With a skirt the
        // legs are bare skin; the "Bottom" color goes to the skirt itself.
        let wearsSkirt = style.bottomKind == .skirt
        let legColor = wearsSkirt ? style.skinColor : style.pantsColor
        let legWidth: CGFloat = wearsSkirt ? 10 : 13
        let farLeg = legColor.blended(withFraction: 0.16, of: .black) ?? legColor
        let farShoes = style.shoesColor.blended(withFraction: 0.16, of: .black) ?? style.shoesColor
        legL = rounded(CGRect(x: wearsSkirt ? 22 : 20, y: 0, width: legWidth, height: 32), 6, farLeg)
        legR = rounded(CGRect(x: wearsSkirt ? 38 : 37, y: 0, width: legWidth, height: 32), 6, legColor)
        for (leg, shoeColor) in [(legL, farShoes), (legR, style.shoesColor)] {
            let shoe = rounded(CGRect(x: -2, y: -2, width: 19, height: 9), 4.5, shoeColor)
            leg.addSublayer(shoe)
            setAnchor(leg, CGPoint(x: 0.5, y: 0.95))
            figure.addSublayer(leg)
        }

        // Arms (pivot at the shoulder), tucked behind the torso
        let farOutfit = style.outfitColor.blended(withFraction: 0.14, of: .black) ?? style.outfitColor
        armL = rounded(CGRect(x: 3, y: 36, width: 12, height: 30), 6, farOutfit)
        armR = rounded(CGRect(x: 55, y: 36, width: 12, height: 30), 6, style.outfitColor)
        for arm in [armL, armR] {
            let hand = ellipse(CGRect(x: 1.5, y: -2, width: 9, height: 9), style.skinColor)
            arm.addSublayer(hand)
            setAnchor(arm, CGPoint(x: 0.5, y: 0.94))
            figure.addSublayer(arm)
        }

        // A-line skirt over the legs, tucked under the torso
        if wearsSkirt {
            let skirt = CAShapeLayer()
            skirt.frame = root.bounds
            let path = CGMutablePath()
            path.move(to: CGPoint(x: 16, y: 32))
            path.addLine(to: CGPoint(x: 10, y: 16))
            path.addQuadCurve(to: CGPoint(x: 13, y: 13), control: CGPoint(x: 10, y: 13))
            path.addLine(to: CGPoint(x: 57, y: 13))
            path.addQuadCurve(to: CGPoint(x: 60, y: 16), control: CGPoint(x: 60, y: 13))
            path.addLine(to: CGPoint(x: 54, y: 32))
            path.closeSubpath()
            skirt.path = path
            skirt.fillColor = style.pantsColor.cgColor
            figure.addSublayer(skirt)
        }

        // Torso
        let torso = rounded(CGRect(x: 8, y: 26, width: 54, height: 50), 16, style.outfitColor)
        figure.addSublayer(torso)

        // Outfit details
        let detailColor = style.outfitColor.blended(withFraction: 0.22, of: .black) ?? style.outfitColor
        switch style.outfitDetail {
        case .pockets:
            torso.addSublayer(rounded(CGRect(x: 8, y: 10, width: 13, height: 4), 2, detailColor))
            torso.addSublayer(rounded(CGRect(x: 33, y: 10, width: 13, height: 4), 2, detailColor))
        case .buttons:
            for i in 0..<3 {
                torso.addSublayer(ellipse(CGRect(x: 25.5, y: 12 + CGFloat(i) * 11, width: 3, height: 3),
                                          Theme.ink.withAlphaComponent(0.3)))
            }
        }

        // Scarf sits on the torso, behind the head
        if style.scarfOn {
            figure.addSublayer(rounded(CGRect(x: 18, y: 66, width: 34, height: 9), 4.5, style.scarfColor))
            figure.addSublayer(rounded(CGRect(x: 38, y: 48, width: 11, height: 20), 5, style.scarfColor))
        }

        // Head group (tilts while thinking)
        headGroup.frame = CGRect(x: 12, y: 70, width: 46, height: 48)
        setAnchor(headGroup, CGPoint(x: 0.5, y: 0.15))
        figure.addSublayer(headGroup)

        let head = ellipse(CGRect(x: 5, y: 2, width: 36, height: 36), style.skinColor)
        headGroup.addSublayer(head)

        // Hair (behind and/or on top of the head, under any hat)
        switch style.hairKind {
        case .none:
            break
        case .crop:
            headGroup.addSublayer(rounded(CGRect(x: 6, y: 26, width: 34, height: 13), 9, style.hairColor))
        case .bob:
            let back = rounded(CGRect(x: 1, y: 4, width: 44, height: 36), 15, style.hairColor)
            headGroup.insertSublayer(back, below: head)
            headGroup.addSublayer(rounded(CGRect(x: 6, y: 27, width: 34, height: 11), 7, style.hairColor))
        case .long:
            // Bob-style back plus two strands falling over the shoulders,
            // keeping the chin area clear so it doesn't read as a beard
            let back = rounded(CGRect(x: 1, y: 4, width: 44, height: 36), 15, style.hairColor)
            headGroup.insertSublayer(back, below: head)
            let strandL = rounded(CGRect(x: 0, y: -14, width: 12, height: 36), 6, style.hairColor)
            let strandR = rounded(CGRect(x: 34, y: -14, width: 12, height: 36), 6, style.hairColor)
            headGroup.insertSublayer(strandL, below: head)
            headGroup.insertSublayer(strandR, below: head)
            headGroup.addSublayer(rounded(CGRect(x: 6, y: 27, width: 34, height: 11), 7, style.hairColor))
        case .bun:
            headGroup.addSublayer(rounded(CGRect(x: 6, y: 26, width: 34, height: 13), 9, style.hairColor))
            headGroup.addSublayer(ellipse(CGRect(x: 16, y: 37, width: 14, height: 11), style.hairColor))
        }

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
        case .none:
            break
        case .beanie:
            let band = style.hatColor.blended(withFraction: 0.18, of: .white) ?? style.hatColor
            headGroup.addSublayer(rounded(CGRect(x: 3, y: 27, width: 40, height: 15), 10, style.hatColor))
            headGroup.addSublayer(rounded(CGRect(x: 3, y: 25, width: 40, height: 6), 3, band))
        case .bucket:
            headGroup.addSublayer(rounded(CGRect(x: 7, y: 29, width: 32, height: 13), 8, style.hatColor))
            let brim = style.hatColor.blended(withFraction: 0.12, of: .black) ?? style.hatColor
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
