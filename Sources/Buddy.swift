import AppKit
import QuartzCore

enum HatKind: String, Codable, CaseIterable { case none, beanie, bucket, cap, beret, headband, flowers }
enum HairKind: String, Codable, CaseIterable { case none, crop, bob, long, ponytail, pigtails, bun }
enum BottomKind: String, Codable, CaseIterable { case pants, skirt }
enum TopKind: String, Codable, CaseIterable { case singlet, tshirt, cardigan, jacket }
enum NeckKind: String, Codable, CaseIterable { case none, scarf, tie, bow }
enum Species: String, Codable { case person, cat, dog }
enum PetAccessory: String, Codable, CaseIterable { case none, bow, bandana, hat }

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
    var topKind: TopKind = .cardigan
    var glasses: Bool
    var neckKind: NeckKind = .none
    var neckColor: UInt32 = 0xF2C14E
    var hasTote: Bool
    var strollSpeed: CGFloat
    var species: Species = .person
    var petAccessory: PetAccessory = .none

    // For a pet, `outfit` = fur color, `neckColor` = collar color, and the
    // otherwise-unused `hat` = accessory color.
    var accessoryColor: NSColor { NSColor(hex: hat) }

    // Explicit keys so decoding can also read fields older builds used
    // (outfitDetail, scarfOn, scarf) that no longer have matching properties.
    private enum CodingKeys: String, CodingKey {
        case name, skin, outfit, pants, shoes, hatKind, hat, hairKind, hair
        case bottomKind, topKind, glasses, neckKind, neckColor, hasTote, strollSpeed
        case species, petAccessory
        case outfitDetail, scarfOn, scarf
    }

    // Custom decoding so styles saved by older builds (without newer fields
    // like bottomKind/topKind/neckKind) still load instead of silently
    // resetting to defaults. Older saves used outfitDetail (pockets/buttons)
    // and a scarfOn bool + scarf color, which map onto topKind/neckKind here.
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
        hasTote = try c.decode(Bool.self, forKey: .hasTote)
        strollSpeed = try c.decode(CGFloat.self, forKey: .strollSpeed)
        species = try c.decodeIfPresent(Species.self, forKey: .species) ?? .person
        petAccessory = try c.decodeIfPresent(PetAccessory.self, forKey: .petAccessory) ?? .none

        if let top = try c.decodeIfPresent(TopKind.self, forKey: .topKind) {
            topKind = top
        } else if let legacyDetail = try c.decodeIfPresent(String.self, forKey: .outfitDetail) {
            topKind = legacyDetail == "pockets" ? .jacket : .cardigan
        } else {
            topKind = .cardigan
        }

        if let neck = try c.decodeIfPresent(NeckKind.self, forKey: .neckKind) {
            neckKind = neck
        } else if let scarfOn = try c.decodeIfPresent(Bool.self, forKey: .scarfOn) {
            neckKind = scarfOn ? .scarf : .none
        } else {
            neckKind = .none
        }
        neckColor = try c.decodeIfPresent(UInt32.self, forKey: .neckColor)
            ?? c.decodeIfPresent(UInt32.self, forKey: .scarf)
            ?? 0xF2C14E
    }

    init(name: String, skin: UInt32, outfit: UInt32, pants: UInt32, shoes: UInt32,
         hatKind: HatKind, hat: UInt32, hairKind: HairKind, hair: UInt32,
         bottomKind: BottomKind = .pants, topKind: TopKind = .cardigan, glasses: Bool,
         neckKind: NeckKind = .none, neckColor: UInt32 = 0xF2C14E,
         hasTote: Bool, strollSpeed: CGFloat, species: Species = .person,
         petAccessory: PetAccessory = .none) {
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
        self.topKind = topKind
        self.glasses = glasses
        self.neckKind = neckKind
        self.neckColor = neckColor
        self.hasTote = hasTote
        self.strollSpeed = strollSpeed
        self.species = species
        self.petAccessory = petAccessory
    }

    // Encode only the current fields; the legacy CodingKeys cases above
    // exist purely so init(from:) can migrate old saves.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .name)
        try c.encode(skin, forKey: .skin)
        try c.encode(outfit, forKey: .outfit)
        try c.encode(pants, forKey: .pants)
        try c.encode(shoes, forKey: .shoes)
        try c.encode(hatKind, forKey: .hatKind)
        try c.encode(hat, forKey: .hat)
        try c.encode(hairKind, forKey: .hairKind)
        try c.encode(hair, forKey: .hair)
        try c.encode(bottomKind, forKey: .bottomKind)
        try c.encode(topKind, forKey: .topKind)
        try c.encode(glasses, forKey: .glasses)
        try c.encode(neckKind, forKey: .neckKind)
        try c.encode(neckColor, forKey: .neckColor)
        try c.encode(hasTote, forKey: .hasTote)
        try c.encode(strollSpeed, forKey: .strollSpeed)
        try c.encode(species, forKey: .species)
        try c.encode(petAccessory, forKey: .petAccessory)
    }

    var skinColor: NSColor { NSColor(hex: skin) }
    var outfitColor: NSColor { NSColor(hex: outfit) }
    var pantsColor: NSColor { NSColor(hex: pants) }
    var shoesColor: NSColor { NSColor(hex: shoes) }
    var hatColor: NSColor { NSColor(hex: hat) }
    var hairColor: NSColor { NSColor(hex: hair) }
    var neckColorValue: NSColor { NSColor(hex: neckColor) }

    static let juno = BuddyStyle(
        name: "Juno",
        skin: 0xF3C9A6, outfit: 0xFF6B2C, pants: 0x2E2A26, shoes: 0xF5F1E8,
        hatKind: .beanie, hat: 0x2E2A26,
        hairKind: .none, hair: 0x2E2A26,
        topKind: .jacket, glasses: true, neckKind: .none, hasTote: false, strollSpeed: 44
    )

    static let bo = BuddyStyle(
        name: "Bo",
        skin: 0xC98D5E, outfit: 0x9DBE8D, pants: 0xF5F1E8, shoes: 0x2E2A26,
        hatKind: .bucket, hat: 0xC9B8F0,
        hairKind: .none, hair: 0x2E2A26,
        topKind: .cardigan, glasses: false, neckKind: .scarf, neckColor: 0xF2C14E,
        hasTote: true, strollSpeed: 36
    )

    // Mochi the cat. Reuses `outfit` as the fur/body color and `neckColor`
    // as the collar; the human-only fields (hat, hair, top...) are ignored
    // for a cat.
    static let mochi = BuddyStyle(
        name: "Mochi",
        skin: 0xF3C9A6, outfit: 0xE7A867, pants: 0x2E2A26, shoes: 0x2E2A26,
        hatKind: .none, hat: 0xE0574E,  // accessory color
        hairKind: .none, hair: 0x2E2A26,
        topKind: .cardigan, glasses: false, neckKind: .none, neckColor: 0xE0574E,
        hasTote: false, strollSpeed: 52, species: .cat
    )

    // Tofu the white dog. Like the cat, `outfit` is the fur color and
    // `neckColor` the collar; human-only fields are ignored.
    static let tofu = BuddyStyle(
        name: "Tofu",
        skin: 0xF3C9A6, outfit: 0xF5F1E8, pants: 0x2E2A26, shoes: 0x2E2A26,
        hatKind: .none, hat: 0x3B5BDB,  // accessory color
        hairKind: .none, hair: 0x2E2A26,
        topKind: .cardigan, glasses: false, neckKind: .none, neckColor: 0x3B5BDB,
        hasTote: false, strollSpeed: 58, species: .dog
    )

    static var defaults: [BuddyStyle] { [.juno, .bo] }
    /// Every dockmate that can appear on the dock.
    static var roster: [BuddyStyle] { [.juno, .bo, .mochi, .tofu] }
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
    private var umbrella: CALayer?
    private var raining = false
    private var catLegs: [CAShapeLayer] = []
    private var catTail: CAShapeLayer?

    var isCat: Bool { style.species == .cat }
    var isPet: Bool { style.species != .person }
    /// Where the speech bubble should sit above this dockmate (a pet is
    /// shorter, so its bubble hangs lower than a person's).
    var bubbleY: CGFloat { feetY + (isPet ? 84 : 130) }

    // Motion state
    var x: CGFloat = 0 {
        didSet { root.position = CGPoint(x: x, y: feetY) }
    }
    var facing: CGFloat = 1
    var bounds: ClosedRange<CGFloat> = 60...600
    var wanderEnabled = true
    private(set) var beingDragged = false
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
    private var waveStart: TimeInterval?
    private let waveDuration: TimeInterval = 0.9

    /// Cooldown bookkeeping for ambient cute moments (hover waves, buddy
    /// greetings), owned and read by OverlayController.
    var lastWaveAt: TimeInterval = 0
    var lastGreetAt: TimeInterval = 0

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
        catLegs = []
        catTail = nil
        umbrella = nil
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

        switch style.species {
        case .cat:
            buildCat()
            return
        case .dog:
            buildDog()
            return
        case .person:
            break
        }

        // Legs (pivot at the hip). The left-side limbs are shaded as the
        // far side so the walk cycle reads with depth. With a skirt the
        // legs are bare skin; the "Bottom" color goes to the skirt itself.
        let wearsSkirt = style.bottomKind == .skirt
        let legColor = wearsSkirt ? style.skinColor : style.pantsColor
        let legWidth: CGFloat = wearsSkirt ? 10 : 13
        let farLeg = legColor.blended(withFraction: 0.16, of: .black) ?? legColor
        let farShoes = style.shoesColor.blended(withFraction: 0.16, of: .black) ?? style.shoesColor
        // Left = near side (full color), right = far side (shaded), so the
        // whole left side reads as nearer to match the in-front left arm.
        legL = rounded(CGRect(x: wearsSkirt ? 22 : 20, y: 0, width: legWidth, height: 32), 6, legColor)
        legR = rounded(CGRect(x: wearsSkirt ? 38 : 37, y: 0, width: legWidth, height: 32), 6, farLeg)
        for (leg, shoeColor) in [(legL, style.shoesColor), (legR, farShoes)] {
            let shoe = rounded(CGRect(x: -2, y: -2, width: 19, height: 9), 4.5, shoeColor)
            leg.addSublayer(shoe)
            setAnchor(leg, CGPoint(x: 0.5, y: 0.95))
            figure.addSublayer(leg)
        }

        // Arms (pivot at the shoulder), tucked behind the torso. Sleeve
        // length depends on the top: sleeveless singlet, capped tee sleeve,
        // or a full sleeve for a cardigan/jacket.
        let farOutfit = style.outfitColor.blended(withFraction: 0.14, of: .black) ?? style.outfitColor
        let farSkin = style.skinColor.blended(withFraction: 0.14, of: .black) ?? style.skinColor
        let sleeveLength: CGFloat
        switch style.topKind {
        case .singlet: sleeveLength = 0
        case .tshirt: sleeveLength = 12
        case .cardigan, .jacket: sleeveLength = 30
        }

        func buildArm(x: CGFloat, sleeveColor: NSColor, skinTone: NSColor) -> CAShapeLayer {
            let arm = rounded(CGRect(x: x, y: 36, width: 12, height: 30), 6, skinTone)
            if sleeveLength > 0 {
                arm.addSublayer(rounded(CGRect(x: 0, y: 30 - sleeveLength, width: 12, height: sleeveLength),
                                        6, sleeveColor))
            }
            let hand = ellipse(CGRect(x: 1.5, y: -2, width: 9, height: 9), skinTone)
            arm.addSublayer(hand)
            setAnchor(arm, CGPoint(x: 0.5, y: 0.94))
            return arm
        }

        // The left arm is the NEAR arm: full-strength color, and it's added
        // to the figure later (after the torso) so it renders in FRONT of the
        // body and visibly swings across it for depth. The right arm is the
        // FAR arm: shaded and tucked behind the torso. When the character
        // flips to walk the other way, the whole figure mirrors but layer
        // z-order doesn't, so the in-front arm correctly appears on the other
        // side (e.g. right hand in front when walking left).
        armL = buildArm(x: 6, sleeveColor: style.outfitColor, skinTone: style.skinColor)
        armR = buildArm(x: 52, sleeveColor: farOutfit, skinTone: farSkin)
        figure.addSublayer(armR)  // far arm, behind the torso

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

        // Torso: slimmer than before (was 54/70 = 77% of the character's
        // width, reading as an overinflated blob) and a touch shorter so
        // the head sits into it rather than floating disconnected above.
        let torso = rounded(CGRect(x: 11, y: 26, width: 48, height: 48), 15, style.outfitColor)
        figure.addSublayer(torso)

        // Outfit details, distinct per top style
        let detailColor = style.outfitColor.blended(withFraction: 0.22, of: .black) ?? style.outfitColor
        switch style.topKind {
        case .jacket:
            torso.addSublayer(rounded(CGRect(x: 26, y: 4, width: 2, height: 42), 1, detailColor))
            torso.addSublayer(rounded(CGRect(x: 8, y: 10, width: 13, height: 4), 2, detailColor))
            torso.addSublayer(rounded(CGRect(x: 33, y: 10, width: 13, height: 4), 2, detailColor))
        case .cardigan:
            torso.addSublayer(rounded(CGRect(x: 26, y: 4, width: 2, height: 42), 1, detailColor))
            for i in 0..<3 {
                torso.addSublayer(ellipse(CGRect(x: 22, y: 10 + CGFloat(i) * 11, width: 3, height: 3),
                                          Theme.ink.withAlphaComponent(0.3)))
            }
        case .tshirt:
            torso.addSublayer(rounded(CGRect(x: 19, y: 42, width: 16, height: 4), 2, detailColor))
        case .singlet:
            torso.addSublayer(rounded(CGRect(x: 15, y: 38, width: 6, height: 16), 3, style.outfitColor))
            torso.addSublayer(rounded(CGRect(x: 33, y: 38, width: 6, height: 16), 3, style.outfitColor))
        }

        // Near (left) arm renders in front of the torso, so its forward swing
        // crosses the body instead of hiding behind it.
        figure.addSublayer(armL)

        // Neck accessory sits on the torso, behind the head
        switch style.neckKind {
        case .none:
            break
        case .scarf:
            figure.addSublayer(rounded(CGRect(x: 18, y: 66, width: 34, height: 9), 4.5, style.neckColorValue))
            figure.addSublayer(rounded(CGRect(x: 38, y: 48, width: 11, height: 20), 5, style.neckColorValue))
        case .tie:
            figure.addSublayer(rounded(CGRect(x: 31, y: 62, width: 8, height: 8), 2, style.neckColorValue))
            let knot = CAShapeLayer()
            knot.frame = figure.bounds
            let path = CGMutablePath()
            path.move(to: CGPoint(x: 31, y: 63))
            path.addLine(to: CGPoint(x: 39, y: 63))
            path.addLine(to: CGPoint(x: 37, y: 36))
            path.addLine(to: CGPoint(x: 35, y: 31))
            path.addLine(to: CGPoint(x: 33, y: 36))
            path.closeSubpath()
            knot.path = path
            knot.fillColor = style.neckColorValue.cgColor
            figure.addSublayer(knot)
        case .bow:
            let bowColor = style.neckColorValue
            func wing(flip: CGFloat) -> CAShapeLayer {
                let wing = CAShapeLayer()
                wing.frame = figure.bounds
                let path = CGMutablePath()
                path.move(to: CGPoint(x: 35, y: 65))
                path.addLine(to: CGPoint(x: 35 + 11 * flip, y: 70))
                path.addLine(to: CGPoint(x: 35 + 11 * flip, y: 59))
                path.closeSubpath()
                wing.path = path
                wing.fillColor = bowColor.cgColor
                return wing
            }
            figure.addSublayer(wing(flip: -1))
            figure.addSublayer(wing(flip: 1))
            figure.addSublayer(ellipse(CGRect(x: 32, y: 62, width: 6, height: 6), bowColor))
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
            headGroup.addSublayer(bangs(CGRect(x: 4, y: 25, width: 38, height: 15), style.hairColor))
        case .bob:
            let back = rounded(CGRect(x: 1, y: 4, width: 44, height: 36), 15, style.hairColor)
            headGroup.insertSublayer(back, below: head)
            headGroup.addSublayer(bangs(CGRect(x: 4, y: 25, width: 38, height: 15), style.hairColor))
        case .long:
            // Bob-style back plus two strands falling over the shoulders,
            // keeping the chin area clear so it doesn't read as a beard
            let back = rounded(CGRect(x: 1, y: 4, width: 44, height: 36), 15, style.hairColor)
            headGroup.insertSublayer(back, below: head)
            let strandL = rounded(CGRect(x: 0, y: -14, width: 12, height: 36), 6, style.hairColor)
            let strandR = rounded(CGRect(x: 34, y: -14, width: 12, height: 36), 6, style.hairColor)
            headGroup.insertSublayer(strandL, below: head)
            headGroup.insertSublayer(strandR, below: head)
            headGroup.addSublayer(bangs(CGRect(x: 4, y: 25, width: 38, height: 15), style.hairColor))
        case .bun:
            headGroup.addSublayer(bangs(CGRect(x: 4, y: 25, width: 38, height: 15), style.hairColor))
            headGroup.addSublayer(ellipse(CGRect(x: 16, y: 37, width: 14, height: 11), style.hairColor))
        case .ponytail:
            // A high pony: hair gathered in a poof at the crown, with a
            // single tapering tail sweeping off to one side. Reads as
            // "gathered at the top" from either walking direction, rather
            // than a strand dangling loose by the cheek.
            headGroup.addSublayer(bangs(CGRect(x: 4, y: 25, width: 38, height: 15), style.hairColor))
            let gather = rounded(CGRect(x: 23, y: 30, width: 15, height: 15), 7, style.hairColor)
            headGroup.insertSublayer(gather, below: head)
            let tail = rounded(CGRect(x: 29, y: -18, width: 11, height: 40), 5, style.hairColor)
            headGroup.insertSublayer(tail, below: head)
            // Drawn on top (not tucked below head) since the crown piece
            // above would otherwise fully cover a tie this close to center.
            headGroup.addSublayer(rounded(CGRect(x: 24, y: 30, width: 13, height: 5), 2, Theme.accent))
        case .pigtails:
            // Crown, plus two tails sticking out clearly past both sides of
            // the head, each gathered with a bright hair tie and a couple of
            // darker wrap bands for a braided-rope texture.
            headGroup.addSublayer(bangs(CGRect(x: 4, y: 25, width: 38, height: 15), style.hairColor))
            let wrap = style.hairColor.blended(withFraction: 0.28, of: .black) ?? style.hairColor
            for side: CGFloat in [-4, 39] {
                let tail = rounded(CGRect(x: side, y: -10, width: 10, height: 32), 5, style.hairColor)
                headGroup.insertSublayer(tail, below: head)
                headGroup.insertSublayer(rounded(CGRect(x: side, y: 4, width: 10, height: 3), 1.5, wrap),
                                         below: head)
                headGroup.insertSublayer(rounded(CGRect(x: side, y: -4, width: 10, height: 3), 1.5, wrap),
                                         below: head)
                let tie = rounded(CGRect(x: side - 1, y: 16, width: 12, height: 5), 2, Theme.accent)
                headGroup.insertSublayer(tie, below: head)
            }
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
            // An ellipse (not a rect) for the dome, so its curve actually
            // matches the head's curve instead of leaving a straight-edged
            // seam at the temples; the folded brim strip stays a flat rect.
            let band = style.hatColor.blended(withFraction: 0.18, of: .white) ?? style.hatColor
            headGroup.addSublayer(ellipse(CGRect(x: 1, y: 21, width: 44, height: 26), style.hatColor))
            headGroup.addSublayer(rounded(CGRect(x: 3, y: 25, width: 40, height: 6), 3, band))
        case .bucket:
            headGroup.addSublayer(rounded(CGRect(x: 7, y: 29, width: 32, height: 13), 8, style.hatColor))
            let brim = style.hatColor.blended(withFraction: 0.12, of: .black) ?? style.hatColor
            headGroup.addSublayer(ellipse(CGRect(x: 1, y: 25, width: 44, height: 8), brim))
        case .cap:
            // Rounded dome plus a wide, flat brim, like a baseball cap
            let brimColor = style.hatColor.blended(withFraction: 0.15, of: .black) ?? style.hatColor
            headGroup.addSublayer(rounded(CGRect(x: 0, y: 19, width: 24, height: 6), 3, brimColor))
            headGroup.addSublayer(rounded(CGRect(x: 5, y: 24, width: 36, height: 18), 11, style.hatColor))
            headGroup.addSublayer(ellipse(CGRect(x: 21, y: 40, width: 4, height: 4), brimColor))
        case .beret:
            // Soft rounded poof with a base trim and a little stem on top
            headGroup.addSublayer(ellipse(CGRect(x: 2, y: 21, width: 42, height: 23), style.hatColor))
            let trim = style.hatColor.blended(withFraction: 0.15, of: .black) ?? style.hatColor
            headGroup.addSublayer(rounded(CGRect(x: 5, y: 23, width: 36, height: 6), 3, trim))
            headGroup.addSublayer(ellipse(CGRect(x: 20, y: 42, width: 6, height: 6), style.hatColor))
        case .headband:
            // A thin band across the crown, leaving hair visible around it
            headGroup.addSublayer(rounded(CGRect(x: 5, y: 30, width: 36, height: 6), 3, style.hatColor))
        case .flowers:
            // A little row of flowers across the crown, ties, or bare head
            let petals = [Theme.blush, Theme.lilac, Theme.sky, Theme.blush]
            for (i, cx) in [CGFloat(8), 17, 26, 35].enumerated() {
                headGroup.addSublayer(ellipse(CGRect(x: cx, y: 32, width: 8, height: 8), petals[i]))
                headGroup.addSublayer(ellipse(CGRect(x: cx + 2.5, y: 34.5, width: 3, height: 3), Theme.mustard))
            }
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

        // Rain umbrella, held up and to the side, hidden unless it's raining.
        // Added last so it renders over everything else.
        let umb = buildUmbrella()
        umb.isHidden = !raining
        figure.addSublayer(umb)
        umbrella = umb
    }

    // MARK: - Cat art

    /// A chunky side-profile cat (facing right by default; the whole root
    /// flips for direction). Body + tail + 4 legs + a big round head with
    /// ears and a little face. Populates `catLegs`, `catTail`, and `eyes` so
    /// the walk, tail sway, and blink animate in applyPose.
    private func buildCat() {
        let fur = style.outfitColor
        let shade = fur.blended(withFraction: 0.16, of: .black) ?? fur
        let bellyLight = fur.blended(withFraction: 0.30, of: .white) ?? fur

        // Tail behind the body, sways from its base
        let tail = CAShapeLayer()
        tail.frame = root.bounds
        let tp = CGMutablePath()
        tp.move(to: CGPoint(x: 12, y: 20))
        tp.addCurve(to: CGPoint(x: 6, y: 44),
                    control1: CGPoint(x: 0, y: 22), control2: CGPoint(x: 1, y: 40))
        tail.path = tp
        tail.strokeColor = fur.cgColor
        tail.fillColor = nil
        tail.lineWidth = 8
        tail.lineCap = .round
        setAnchor(tail, CGPoint(x: 12.0 / 70, y: 20.0 / 122))
        figure.addSublayer(tail)
        catTail = tail

        // Far legs (behind the body), shaded. Order in catLegs: [back-far,
        // front-far, back-near, front-near] — used for a diagonal gait.
        for lx in [CGFloat(15), 39] {
            let leg = rounded(CGRect(x: lx, y: 0, width: 8, height: 16), 4, shade)
            setAnchor(leg, CGPoint(x: 0.5, y: 0.9))
            figure.addSublayer(leg)
            catLegs.append(leg)
        }

        // Body
        let body = rounded(CGRect(x: 9, y: 11, width: 44, height: 25), 12, fur)
        body.addSublayer(rounded(CGRect(x: 8, y: 2, width: 22, height: 12), 6, bellyLight)) // light belly
        figure.addSublayer(body)

        // Collar (a little band at the neck)
        figure.addSublayer(rounded(CGRect(x: 36, y: 24, width: 16, height: 4), 2, style.neckColorValue))

        // Near legs (in front of the body), full color, with little paws
        for lx in [CGFloat(18), 42] {
            let leg = rounded(CGRect(x: lx, y: 0, width: 8, height: 16), 4, fur)
            leg.addSublayer(ellipse(CGRect(x: 0.5, y: -1, width: 7, height: 5), shade))
            setAnchor(leg, CGPoint(x: 0.5, y: 0.9))
            figure.addSublayer(leg)
            catLegs.append(leg)
        }

        // Head group (so a subtle think-tilt can pivot at the neck)
        headGroup.frame = CGRect(x: 32, y: 24, width: 34, height: 40)
        setAnchor(headGroup, CGPoint(x: 0.4, y: 0.1))
        figure.addSublayer(headGroup)

        // Ears (in headGroup-local coords)
        for ex in [CGFloat(5), 20] {
            let ear = CAShapeLayer()
            ear.frame = headGroup.bounds
            let ep = CGMutablePath()
            ep.move(to: CGPoint(x: ex, y: 24))
            ep.addLine(to: CGPoint(x: ex + 4, y: 36))
            ep.addLine(to: CGPoint(x: ex + 11, y: 26))
            ep.closeSubpath()
            ear.path = ep
            ear.fillColor = fur.cgColor
            headGroup.addSublayer(ear)
            let inner = CAShapeLayer()
            let ip = CGMutablePath()
            ip.move(to: CGPoint(x: ex + 3, y: 26))
            ip.addLine(to: CGPoint(x: ex + 5, y: 32))
            ip.addLine(to: CGPoint(x: ex + 8.5, y: 27))
            ip.closeSubpath()
            inner.path = ip
            inner.fillColor = (Theme.blush.blended(withFraction: 0.2, of: fur) ?? Theme.blush).cgColor
            headGroup.addSublayer(inner)
        }

        // Head
        let head = ellipse(CGRect(x: 2, y: 2, width: 30, height: 28), fur)
        headGroup.addSublayer(head)

        // Eyes (blinkable)
        let eyeA = ellipse(CGRect(x: 11, y: 14, width: 4.5, height: 5), Theme.ink)
        let eyeB = ellipse(CGRect(x: 21, y: 14, width: 4.5, height: 5), Theme.ink)
        eyes = [eyeA, eyeB]
        head.addSublayer(eyeA)
        head.addSublayer(eyeB)

        // Cheeks
        head.addSublayer(ellipse(CGRect(x: 6, y: 9, width: 5, height: 3.5), Theme.blush.withAlphaComponent(0.55)))
        head.addSublayer(ellipse(CGRect(x: 22, y: 9, width: 5, height: 3.5), Theme.blush.withAlphaComponent(0.55)))

        // Nose
        let nose = CAShapeLayer()
        let np = CGMutablePath()
        np.move(to: CGPoint(x: 14.5, y: 11))
        np.addLine(to: CGPoint(x: 18.5, y: 11))
        np.addLine(to: CGPoint(x: 16.5, y: 8.5))
        np.closeSubpath()
        nose.path = np
        nose.fillColor = Theme.blush.cgColor
        head.addSublayer(nose)

        // Mouth: the classic kawaii cat "\u{03C9}" — two soft smile dips ("\u{203F}\u{203F}")
        // sharing a high centre point right under the nose, each dipping
        // downward. Bezier curves make the downward direction unambiguous
        // (the previous arc version bulged upward and read like a mustache).
        head.addSublayer(catMouth(cx: 16.5, top: 7.4, halfW: 3.4, dip: 2.4))

        // Whiskers
        for (wy, side) in [(CGFloat(11), CGFloat(-1)), (CGFloat(8), CGFloat(-1)),
                           (CGFloat(11), CGFloat(1)), (CGFloat(8), CGFloat(1))] {
            let w = CAShapeLayer()
            let wp = CGMutablePath()
            let baseX: CGFloat = side < 0 ? 12 : 21
            wp.move(to: CGPoint(x: baseX, y: 10))
            wp.addLine(to: CGPoint(x: baseX + side * 9, y: wy))
            w.path = wp
            w.strokeColor = Theme.ink.withAlphaComponent(0.5).cgColor
            w.lineWidth = 0.9
            w.lineCap = .round
            head.addSublayer(w)
        }

        // Cat ears meet the crown around headGroup-y 26; perch hats/bows above.
        addPetAccessory(headTopY: 27)
    }

    /// A cute double-dip "\u{203F}\u{203F}" pet mouth: two smile bumps that dip downward
    /// from a shared high centre point, in head-local coords (y-up).
    private func petMouth(cx: CGFloat, top: CGFloat, halfW: CGFloat, dip: CGFloat) -> CAShapeLayer {
        let mouth = CAShapeLayer()
        let p = CGMutablePath()
        p.move(to: CGPoint(x: cx - halfW, y: top))
        p.addQuadCurve(to: CGPoint(x: cx, y: top), control: CGPoint(x: cx - halfW / 2, y: top - dip))
        p.addQuadCurve(to: CGPoint(x: cx + halfW, y: top), control: CGPoint(x: cx + halfW / 2, y: top - dip))
        mouth.path = p
        mouth.strokeColor = Theme.ink.cgColor
        mouth.fillColor = nil
        mouth.lineWidth = 1.3
        mouth.lineCap = .round
        mouth.lineJoin = .round
        return mouth
    }

    private func catMouth(cx: CGFloat, top: CGFloat, halfW: CGFloat, dip: CGFloat) -> CAShapeLayer {
        petMouth(cx: cx, top: top, halfW: halfW, dip: dip)
    }

    /// Draws the chosen dress-up accessory onto the head group (bow/hat) or
    /// figure (bandana), in the coordinate spaces those layers use. Shared by
    /// cat and dog. `earTopY` is the head-local y where the ears meet the
    /// crown, so a hat/bow can perch just above it.
    private func addPetAccessory(headTopY: CGFloat) {
        let color = style.accessoryColor
        switch style.petAccessory {
        case .none:
            break

        case .bow:
            // A ribbon bow perched near the top-right of the head (headGroup
            // coords). Two triangular loops + a knot.
            let bx: CGFloat = 22, by = headTopY
            func loop(_ dir: CGFloat) -> CAShapeLayer {
                let l = CAShapeLayer()
                let p = CGMutablePath()
                p.move(to: CGPoint(x: bx, y: by))
                p.addLine(to: CGPoint(x: bx + dir * 8, y: by + 5))
                p.addLine(to: CGPoint(x: bx + dir * 8, y: by - 5))
                p.closeSubpath()
                l.path = p
                l.fillColor = color.cgColor
                return l
            }
            headGroup.addSublayer(loop(-1))
            headGroup.addSublayer(loop(1))
            headGroup.addSublayer(ellipse(CGRect(x: bx - 2.5, y: by - 2.5, width: 5, height: 5), color))

        case .hat:
            // A little party cone hat sitting just above the crown.
            let hx: CGFloat = 17
            let base = headTopY + 1
            let hat = CAShapeLayer()
            let p = CGMutablePath()
            p.move(to: CGPoint(x: hx - 8, y: base))
            p.addLine(to: CGPoint(x: hx + 8, y: base))
            p.addLine(to: CGPoint(x: hx, y: base + 15))
            p.closeSubpath()
            hat.path = p
            hat.fillColor = color.cgColor
            headGroup.addSublayer(hat)
            // brim + pom-pom
            headGroup.addSublayer(rounded(CGRect(x: hx - 9, y: base - 1.5, width: 18, height: 3.5), 1.75,
                                          color.blended(withFraction: 0.25, of: .white) ?? color))
            headGroup.addSublayer(ellipse(CGRect(x: hx - 2.5, y: base + 13, width: 5, height: 5),
                                          color.blended(withFraction: 0.3, of: .white) ?? color))

        case .bandana:
            // A triangular neckerchief (figure coords): a point draping down
            // the chest, finished with a tied band across the top at the
            // collar line so it reads as knotted at the neck.
            let bandana = CAShapeLayer()
            bandana.frame = root.bounds
            let p = CGMutablePath()
            p.move(to: CGPoint(x: 36, y: 31))
            p.addLine(to: CGPoint(x: 52, y: 31))
            p.addLine(to: CGPoint(x: 45, y: 19))
            p.closeSubpath()
            bandana.path = p
            bandana.fillColor = color.cgColor
            figure.addSublayer(bandana)
            // the tied top band
            figure.addSublayer(rounded(CGRect(x: 35, y: 30, width: 18, height: 4), 2,
                                       color.blended(withFraction: 0.18, of: .black) ?? color))
        }
    }

    // MARK: - Dog art

    /// Same chunky body plan as the cat, dog-flavored: floppy ears hanging
    /// beside the head instead of pointy ones on top, an up-curled wagging
    /// tail, a muzzle with a big oval nose and a little tongue, no whiskers.
    /// Shares catLegs/catTail/eyes so applyPetLimbs animates both species.
    private func buildDog() {
        let fur = style.outfitColor
        let shade = fur.blended(withFraction: 0.14, of: .black) ?? fur

        // Up-curled tail behind the body, wags from its base
        let tail = CAShapeLayer()
        tail.frame = root.bounds
        let tp = CGMutablePath()
        tp.move(to: CGPoint(x: 13, y: 22))
        tp.addCurve(to: CGPoint(x: 5, y: 40),
                    control1: CGPoint(x: 4, y: 26), control2: CGPoint(x: 10, y: 38))
        tail.path = tp
        tail.strokeColor = fur.cgColor
        tail.fillColor = nil
        tail.lineWidth = 7
        tail.lineCap = .round
        setAnchor(tail, CGPoint(x: 13.0 / 70, y: 22.0 / 122))
        figure.addSublayer(tail)
        catTail = tail

        // Far legs (behind the body), shaded
        for lx in [CGFloat(15), 39] {
            let leg = rounded(CGRect(x: lx, y: 0, width: 8, height: 16), 4, shade)
            setAnchor(leg, CGPoint(x: 0.5, y: 0.9))
            figure.addSublayer(leg)
            catLegs.append(leg)
        }

        // Body
        let body = rounded(CGRect(x: 9, y: 11, width: 44, height: 25), 12, fur)
        body.addSublayer(rounded(CGRect(x: 8, y: 2, width: 22, height: 12), 6, shade.withAlphaComponent(0.25)))
        figure.addSublayer(body)

        // Collar
        figure.addSublayer(rounded(CGRect(x: 36, y: 24, width: 16, height: 4), 2, style.neckColorValue))

        // Near legs (in front), full color with paw shading
        for lx in [CGFloat(18), 42] {
            let leg = rounded(CGRect(x: lx, y: 0, width: 8, height: 16), 4, fur)
            leg.addSublayer(ellipse(CGRect(x: 0.5, y: -1, width: 7, height: 5), shade))
            setAnchor(leg, CGPoint(x: 0.5, y: 0.9))
            figure.addSublayer(leg)
            catLegs.append(leg)
        }

        // Head group
        headGroup.frame = CGRect(x: 32, y: 24, width: 34, height: 40)
        setAnchor(headGroup, CGPoint(x: 0.4, y: 0.1))
        figure.addSublayer(headGroup)

        // Head first, then floppy ears hanging over its top corners
        let head = ellipse(CGRect(x: 2, y: 2, width: 30, height: 28), fur)
        headGroup.addSublayer(head)

        // Floppy ears hang DOWN from the top corners of the head (slight
        // inward tilt at the bottom), not splayed up like earmuffs.
        for (ex, tilt) in [(CGFloat(0), CGFloat(-0.12)), (CGFloat(26), CGFloat(0.12))] {
            let ear = rounded(CGRect(x: ex, y: 9, width: 8, height: 17), 4, shade)
            setAnchor(ear, CGPoint(x: 0.5, y: 0.9))
            ear.transform = CATransform3DMakeRotation(tilt, 0, 0, 1)
            headGroup.addSublayer(ear)
        }

        // Eyes (blinkable)
        let eyeA = ellipse(CGRect(x: 10, y: 15, width: 4.5, height: 5), Theme.ink)
        let eyeB = ellipse(CGRect(x: 20, y: 15, width: 4.5, height: 5), Theme.ink)
        eyes = [eyeA, eyeB]
        head.addSublayer(eyeA)
        head.addSublayer(eyeB)

        // Muzzle + big oval nose
        head.addSublayer(ellipse(CGRect(x: 9, y: 2, width: 17, height: 11),
                                 fur.blended(withFraction: 0.5, of: .white) ?? fur))
        head.addSublayer(ellipse(CGRect(x: 14, y: 9, width: 7, height: 5), NSColor(hex: 0x3A332C)))

        // Mouth: same cute double-dip smile as the cat, centered under the
        // nose, with a little tongue peeking from the middle (drawn first so
        // the mouth line sits over its top edge).
        let tongue = rounded(CGRect(x: 15.9, y: 3.4, width: 3.2, height: 4), 1.6, Theme.blush)
        head.addSublayer(tongue)
        head.addSublayer(petMouth(cx: 17.5, top: 7.4, halfW: 3.6, dip: 2.4))

        // Cheeks
        head.addSublayer(ellipse(CGRect(x: 4, y: 10, width: 5, height: 3.5), Theme.blush.withAlphaComponent(0.5)))
        head.addSublayer(ellipse(CGRect(x: 25, y: 10, width: 5, height: 3.5), Theme.blush.withAlphaComponent(0.5)))

        // Dog crown is around headGroup-y 26; perch hats/bows above it.
        addPetAccessory(headTopY: 26)
    }

    /// A small umbrella held up and to the right (canopy over the head, stick
    /// down to the right hand), so it shelters the head without the stick
    /// crossing the face.
    private func buildUmbrella() -> CALayer {
        let group = CALayer()
        group.frame = root.bounds

        let canopyColor = NSColor(hex: 0xE0574E)
        let panelColor = canopyColor.blended(withFraction: 0.16, of: .white) ?? canopyColor
        let cx: CGFloat = 39
        let baseY: CGFloat = 118
        let halfW: CGFloat = 28
        let topY: CGFloat = 133

        // Canopy: a shallow dome with a scalloped lower edge for an umbrella feel
        let canopy = CAShapeLayer()
        canopy.frame = root.bounds
        let path = CGMutablePath()
        path.move(to: CGPoint(x: cx - halfW, y: baseY))
        path.addQuadCurve(to: CGPoint(x: cx + halfW, y: baseY),
                          control: CGPoint(x: cx, y: topY + 10))
        let scallops = 4
        for i in stride(from: scallops - 1, through: 0, by: -1) {
            let x0 = cx - halfW + CGFloat(i) * (halfW * 2 / CGFloat(scallops))
            let x1 = x0 + (halfW * 2 / CGFloat(scallops))
            path.addQuadCurve(to: CGPoint(x: x0, y: baseY),
                              control: CGPoint(x: (x0 + x1) / 2, y: baseY - 4))
        }
        path.closeSubpath()
        canopy.path = path
        canopy.fillColor = canopyColor.cgColor
        group.addSublayer(canopy)

        // A couple of lighter panel seams for depth
        for dx in [-halfW * 0.5, halfW * 0.5] {
            let seam = CAShapeLayer()
            let sp = CGMutablePath()
            sp.move(to: CGPoint(x: cx + dx, y: baseY))
            sp.addLine(to: CGPoint(x: cx + dx * 0.35, y: topY + 4))
            seam.path = sp
            seam.strokeColor = panelColor.cgColor
            seam.lineWidth = 1.4
            group.addSublayer(seam)
        }

        // Ferrule nub on top
        group.addSublayer(rounded(CGRect(x: cx - 1.2, y: topY - 1, width: 2.4, height: 6), 1.2,
                                  NSColor(hex: 0x6B5B4E)))

        // Stick runs straight down the RIGHT side to the right hand, staying
        // clear of the head (which reaches x~53) so it never crosses the face,
        // ending in a little J-hook handle. It attaches to the canopy's right
        // underside rather than dead center.
        let stick = CAShapeLayer()
        let stickPath = CGMutablePath()
        stickPath.move(to: CGPoint(x: 55, y: baseY - 3))
        stickPath.addLine(to: CGPoint(x: 55, y: 40))
        stickPath.addQuadCurve(to: CGPoint(x: 50, y: 37), control: CGPoint(x: 55, y: 35))
        stick.path = stickPath
        stick.strokeColor = NSColor(hex: 0x6B5B4E).cgColor
        stick.fillColor = nil
        stick.lineWidth = 2.4
        stick.lineCap = .round
        stick.lineJoin = .round
        group.addSublayer(stick)

        return group
    }

    /// Show or hide the umbrella when the weather starts or stops raining.
    func setRaining(_ value: Bool) {
        guard value != raining else { return }
        raining = value
        umbrella?.isHidden = !value
        if value, let umbrella {
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0
            fade.toValue = 1
            fade.duration = 0.25
            umbrella.add(fade, forKey: "fade")
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

    /// A dome shape for a hair fringe: curved on top to hug the head's
    /// curvature (like the ellipse it replaces), but with a flat-ish bottom
    /// edge instead of curving back up at the sides, so it reads as bangs
    /// cut across the forehead rather than a helmet dome.
    private func bangs(_ frame: CGRect, _ color: NSColor) -> CAShapeLayer {
        let layer = CAShapeLayer()
        layer.frame = frame
        let w = frame.width
        let h = frame.height
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: 0))
        path.addCurve(to: CGPoint(x: w, y: 0),
                     control1: CGPoint(x: 0, y: h * 1.34),
                     control2: CGPoint(x: w, y: h * 1.34))
        path.addQuadCurve(to: CGPoint(x: 0, y: 0), control: CGPoint(x: w / 2, y: -h * 0.1))
        path.closeSubpath()
        layer.path = path
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
        targetX = nil  // stop mid-stride rather than drifting while hopping
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

    /// A little hello wave, triggered when the cursor first lands on the
    /// buddy without clicking. Purely cosmetic; safe to call any time the
    /// buddy isn't busy or being dragged.
    func wave() {
        waveStart = lastNow
    }

    func beginDrag() {
        beingDragged = true
        targetX = nil
    }

    func endDrag() {
        beingDragged = false
        targetX = nil
        nextWanderAt = lastNow + 2.5  // settle a moment before wandering off
    }

    func tick(dt: TimeInterval, now: TimeInterval) {
        lastNow = now

        // While held by the cursor the buddy stays put; the drag handler owns x.
        if beingDragged {
            targetX = nil
            walkAmount += (0 - walkAmount) * min(1, dt * 8)
            applyPose(now: now)
            return
        }

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
        if isPet {
            applyPetLimbs(now: now, swing: swing)
        } else {
            applyPersonLimbs(now: now, swing: swing)
        }

        var lift = abs(CGFloat(sin(walkPhase))) * (isPet ? 1.6 : 2.4) * CGFloat(walkAmount)
        if let hs = hopStart {
            let t = now - hs
            if t < hopDuration {
                lift += CGFloat(sin(.pi * t / hopDuration)) * 15
            } else if mode != .celebrate {
                hopStart = nil
            }
        }
        if beingDragged { lift += 7 }

        let breathe = (1 - walkAmount) * 0.015 * sin(now * 2.2)
        let held: CGFloat = beingDragged ? 1.07 : 1
        var tf = CATransform3DMakeTranslation(0, lift, 0)
        if beingDragged {
            tf = CATransform3DRotate(tf, CGFloat(sin(now * 5)) * 0.04, 0, 0, 1)  // gentle sway
        }
        tf = CATransform3DScale(tf, held, held + CGFloat(breathe), 1)
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

    private func applyPersonLimbs(now: TimeInterval, swing: CGFloat) {
        legL.transform = CATransform3DMakeRotation(swing * 0.38, 0, 0, 1)
        legR.transform = CATransform3DMakeRotation(-swing * 0.38, 0, 0, 1)
        if beingDragged {
            // Arms up and outward, legs dangling straight, like being picked up.
            // Each arm's rest pose hangs straight down from a shoulder-top pivot,
            // so a positive rotation swings the right arm outward (+x) and a
            // negative rotation swings the left arm outward (-x); matching signs
            // on both arms would instead cross them in toward the chest.
            armL.transform = CATransform3DMakeRotation(-0.65, 0, 0, 1)
            armR.transform = CATransform3DMakeRotation(0.65, 0, 0, 1)
            legL.transform = CATransform3DMakeRotation(0.12, 0, 0, 1)
            legR.transform = CATransform3DMakeRotation(-0.12, 0, 0, 1)
        } else if let ws = waveStart, now - ws < waveDuration {
            // Right arm raises outward and up beside the head (not across the
            // face) and wiggles, like a little hello wave. See the sign note
            // above: positive rotation is what swings this arm outward.
            let t = now - ws
            let raise = min(1, t / 0.18)
            let wiggle = sin(t * 16) * 0.22 * CGFloat(min(1, (waveDuration - t) / 0.2 + 0.3))
            armR.transform = CATransform3DMakeRotation(2.5 * CGFloat(raise) + wiggle, 0, 0, 1)
            armL.transform = CATransform3DMakeRotation(swing * 0.3, 0, 0, 1)
        } else {
            if waveStart != nil { waveStart = nil }
            // The two arms swing out one after another, not in lockstep: the
            // far (right) arm's swing trails the near (left) arm's by a large
            // armLag (roughly a half-cycle), so when the near arm is fully
            // forward the far arm is only starting out, giving a clear
            // cascading "1... 2..." rhythm. The bigger swing amplitude makes
            // that offset legible at dock size.
            let armLag = 1.7
            let nearSwing = CGFloat(sin(walkPhase)) * CGFloat(walkAmount)
            let farSwing = CGFloat(sin(walkPhase - armLag)) * CGFloat(walkAmount)
            armL.transform = CATransform3DMakeRotation(nearSwing * 0.42, 0, 0, 1)
            armR.transform = CATransform3DMakeRotation(farSwing * 0.42, 0, 0, 1)
        }
    }

    private func applyPetLimbs(now: TimeInterval, swing: CGFloat) {
        if beingDragged {
            // Legs dangle straight, tail swishes a little while held.
            for leg in catLegs { leg.transform = CATransform3DIdentity }
            catTail?.transform = CATransform3DMakeRotation(CGFloat(sin(now * 6)) * 0.12, 0, 0, 1)
            return
        }
        // Diagonal gait: catLegs order is [back-far, front-far, back-near,
        // front-near]; the two diagonals move opposite each other.
        let phases: [CGFloat] = [swing, -swing, -swing, swing]
        for (i, leg) in catLegs.enumerated() where i < phases.count {
            leg.transform = CATransform3DMakeRotation(phases[i] * 0.5, 0, 0, 1)
        }
        // Tail motion: a cat sways slowly and gently; a dog wags fast and
        // eagerly, more so while walking.
        let sway: CGFloat
        if style.species == .dog {
            sway = CGFloat(sin(now * 8.5)) * (0.22 + 0.12 * CGFloat(walkAmount))
        } else {
            sway = CGFloat(sin(now * 3.2)) * (0.16 + 0.14 * CGFloat(walkAmount))
        }
        catTail?.transform = CATransform3DMakeRotation(sway, 0, 0, 1)
    }

    func hitRect() -> CGRect {
        if isPet {
            return CGRect(x: x - 38, y: feetY - 8, width: 76, height: 84)
        }
        return CGRect(x: x - 42, y: feetY - 8, width: 84, height: 140)
    }
}
