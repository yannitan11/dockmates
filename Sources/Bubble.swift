import AppKit
import QuartzCore

/// A little rounded speech bubble with a tail, hosted as a CALayer on the stage.
final class SpeechBubble {
    let layer = CALayer()
    private let bg = CAShapeLayer()
    private let label = CATextLayer()
    private let font = Theme.rounded(12.5, .semibold)
    private(set) var text = ""
    private(set) var visible = false
    private var hideWork: DispatchWorkItem?

    init(scale: CGFloat) {
        layer.anchorPoint = CGPoint(x: 0.5, y: 0)
        layer.opacity = 0
        layer.isHidden = true
        layer.contentsScale = scale

        bg.fillColor = Theme.paper.cgColor
        bg.shadowColor = Theme.ink.cgColor
        bg.shadowOpacity = 0.16
        bg.shadowRadius = 3
        bg.shadowOffset = CGSize(width: 0, height: -1.5)
        bg.contentsScale = scale

        label.alignmentMode = .center
        label.font = font as CFTypeRef
        label.fontSize = 12.5
        label.foregroundColor = Theme.ink.cgColor
        label.contentsScale = scale
        label.truncationMode = .none
        label.isWrapped = false

        layer.addSublayer(bg)
        layer.addSublayer(label)
    }

    func setText(_ t: String) {
        guard t != text else { return }
        text = t
        label.string = t
        relayout()
    }

    /// Show the bubble; pass a duration to auto-hide, or nil to keep it up.
    func show(_ t: String, for duration: TimeInterval? = nil) {
        setText(t)
        hideWork?.cancel()
        hideWork = nil

        layer.isHidden = false
        layer.opacity = 1

        if !visible {
            visible = true
            let pop = CASpringAnimation(keyPath: "transform.scale")
            pop.fromValue = 0.5
            pop.toValue = 1
            pop.damping = 13
            pop.stiffness = 280
            pop.initialVelocity = 4
            pop.duration = pop.settlingDuration
            layer.add(pop, forKey: "pop")

            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0
            fade.toValue = 1
            fade.duration = 0.14
            layer.add(fade, forKey: "fade")
        }

        if let duration {
            let work = DispatchWorkItem { [weak self] in self?.hide() }
            hideWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
        }
    }

    func hide() {
        guard visible else { return }
        visible = false
        hideWork?.cancel()
        hideWork = nil

        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1
        fade.toValue = 0
        fade.duration = 0.18
        layer.add(fade, forKey: "fadeOut")
        layer.opacity = 0
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self, !self.visible else { return }
            self.layer.isHidden = true
        }
    }

    private func relayout() {
        let size = (text as NSString).size(withAttributes: [.font: font])
        let textW = ceil(size.width)
        let textH = ceil(size.height)
        let w = textW + 26
        let h: CGFloat = 27
        let tail: CGFloat = 7

        layer.bounds = CGRect(x: 0, y: 0, width: w, height: h + tail)
        bg.frame = layer.bounds

        let path = CGMutablePath()
        let body = CGRect(x: 0, y: tail, width: w, height: h)
        let r = min(12, body.height / 2)
        path.addRoundedRect(in: body, cornerWidth: r, cornerHeight: r)
        path.move(to: CGPoint(x: w / 2 - 6, y: tail + 2))
        path.addLine(to: CGPoint(x: w / 2, y: 0))
        path.addLine(to: CGPoint(x: w / 2 + 6, y: tail + 2))
        path.closeSubpath()
        bg.path = path

        label.frame = CGRect(x: 0, y: tail + (h - textH) / 2 - 0.5, width: w, height: textH + 1)
    }
}
