import UIKit
import simd

enum Theme {
    static let yellow = UIColor(red: 0.98, green: 0.80, blue: 0.25, alpha: 1)
    static let panel = UIColor(white: 0.0, alpha: 0.38)
    static let border = UIColor(white: 1.0, alpha: 0.45)
    static let text = UIColor(white: 1.0, alpha: 0.95)
    static func font(_ s: CGFloat, _ w: UIFont.Weight = .semibold) -> UIFont { return UIFont.systemFont(ofSize: s, weight: w) }
    static func mono(_ s: CGFloat) -> UIFont { return UIFont.monospacedDigitSystemFont(ofSize: s, weight: .bold) }
}

/// Floating virtual joystick: appears where the thumb lands inside its area.
final class JoystickView: UIView {
    private let base = UIView()
    private let knob = UIView()
    private let sprintMark = UILabel()
    private var touch: UITouch?
    private var origin = CGPoint.zero
    var homeCenter = CGPoint.zero { didSet { if touch == nil { placeHome() } } }
    let radius: CGFloat = 62
    private(set) var value = CGPoint.zero
    var onChange: ((CGPoint) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = false
        backgroundColor = .clear
        base.frame = CGRect(x: 0, y: 0, width: radius * 2, height: radius * 2)
        base.layer.cornerRadius = radius
        base.backgroundColor = UIColor(white: 0, alpha: 0.22)
        base.layer.borderColor = Theme.border.cgColor
        base.layer.borderWidth = 1.5
        base.isUserInteractionEnabled = false
        addSubview(base)
        knob.frame = CGRect(x: 0, y: 0, width: 54, height: 54)
        knob.layer.cornerRadius = 27
        knob.backgroundColor = UIColor(white: 1, alpha: 0.35)
        knob.layer.borderColor = UIColor(white: 1, alpha: 0.7).cgColor
        knob.layer.borderWidth = 1.5
        knob.isUserInteractionEnabled = false
        addSubview(knob)
        sprintMark.text = "冲刺"
        sprintMark.font = Theme.font(11)
        sprintMark.textColor = Theme.yellow
        sprintMark.textAlignment = .center
        sprintMark.frame = CGRect(x: 0, y: 0, width: 50, height: 16)
        sprintMark.isHidden = true
        addSubview(sprintMark)
    }
    required init?(coder: NSCoder) { fatalError() }

    private func placeHome() {
        base.center = homeCenter
        knob.center = homeCenter
        sprintMark.center = CGPoint(x: homeCenter.x, y: homeCenter.y - radius - 14)
        base.alpha = 0.6
        knob.alpha = 0.6
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard touch == nil, let t = touches.first else { return }
        touch = t
        origin = t.location(in: self)
        base.center = origin
        knob.center = origin
        sprintMark.center = CGPoint(x: origin.x, y: origin.y - radius - 14)
        base.alpha = 1
        knob.alpha = 1
        update(t)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = touch, touches.contains(t) else { return }
        update(t)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = touch, touches.contains(t) else { return }
        touch = nil
        value = .zero
        onChange?(value)
        sprintMark.isHidden = true
        placeHome()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        touchesEnded(touches, with: event)
    }

    private func update(_ t: UITouch) {
        let p = t.location(in: self)
        var dx = p.x - origin.x, dy = p.y - origin.y
        let d = sqrt(dx * dx + dy * dy)
        let sprint = dy < -radius * 1.25 && abs(dx) < radius * 0.8
        if d > radius {
            dx = dx / d * radius
            dy = dy / d * radius
        }
        knob.center = CGPoint(x: origin.x + dx, y: origin.y + dy)
        var v = CGPoint(x: dx / radius, y: -dy / radius)
        if sprint { v = CGPoint(x: 0, y: 1) }
        sprintMark.isHidden = !sprint
        value = v
        onChange?(v)
    }
}

/// Round translucent button with an SF Symbol or text.
final class RoundButton: UIView {
    let label = UILabel()
    let icon = UIImageView()
    var onTap: (() -> Void)?
    var onPress: ((Bool) -> Void)?
    var onDrag: ((CGPoint) -> Void)?
    private var touch: UITouch?
    private var lastPoint = CGPoint.zero
    var highlighted = false { didSet { refresh() } }
    var active = false { didSet { refresh() } }

    init(symbol: String?, text: String?, size: CGFloat) {
        super.init(frame: CGRect(x: 0, y: 0, width: size, height: size))
        layer.cornerRadius = size / 2
        layer.borderWidth = 1.5
        isMultipleTouchEnabled = false
        if let s = symbol, let img = UIImage(systemName: s, withConfiguration: UIImage.SymbolConfiguration(pointSize: size * 0.36, weight: .bold)) {
            icon.image = img
            icon.tintColor = Theme.text
            icon.contentMode = .center
            icon.frame = bounds
            icon.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            addSubview(icon)
            if let t = text {
                label.text = t
                label.font = Theme.font(max(9, size * 0.17))
                label.textColor = Theme.text
                label.textAlignment = .center
                label.frame = CGRect(x: 0, y: size * 0.66, width: size, height: size * 0.26)
                icon.frame = CGRect(x: 0, y: -size * 0.08, width: size, height: size)
                addSubview(label)
            }
        } else {
            label.text = text ?? symbol
            label.font = Theme.font(size * 0.28, .bold)
            label.textColor = Theme.text
            label.textAlignment = .center
            label.adjustsFontSizeToFitWidth = true
            label.minimumScaleFactor = 0.5
            label.frame = bounds.insetBy(dx: 4, dy: 4)
            label.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            addSubview(label)
        }
        refresh()
    }
    required init?(coder: NSCoder) { fatalError() }

    func setSymbol(_ s: String) {
        icon.image = UIImage(systemName: s, withConfiguration: UIImage.SymbolConfiguration(pointSize: bounds.width * 0.36, weight: .bold))
    }

    private func refresh() {
        let on = highlighted || active
        backgroundColor = on ? UIColor(white: 1, alpha: 0.35) : Theme.panel
        layer.borderColor = (active ? Theme.yellow : Theme.border).cgColor
        icon.tintColor = active ? Theme.yellow : Theme.text
        label.textColor = active ? Theme.yellow : Theme.text
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard touch == nil, let t = touches.first else { return }
        touch = t
        lastPoint = t.location(in: superview)
        highlighted = true
        onPress?(true)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = touch, touches.contains(t) else { return }
        let p = t.location(in: superview)
        onDrag?(CGPoint(x: p.x - lastPoint.x, y: p.y - lastPoint.y))
        lastPoint = p
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = touch, touches.contains(t) else { return }
        touch = nil
        highlighted = false
        onPress?(false)
        if bounds.insetBy(dx: -20, dy: -20).contains(t.location(in: self)) { onTap?() }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = touch, touches.contains(t) else { return }
        touch = nil
        highlighted = false
        onPress?(false)
    }
}

/// Big fire button with a bullet glyph (drag on it to aim).
final class FireButtonGlyph: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isUserInteractionEnabled = false
    }
    required init?(coder: NSCoder) { fatalError() }
    override func draw(_ rect: CGRect) {
        guard let g = UIGraphicsGetCurrentContext() else { return }
        let w = rect.width, h = rect.height
        g.translateBy(x: w / 2, y: h / 2)
        g.rotate(by: -.pi / 4)
        let L = w * 0.42, R = w * 0.075
        let body = UIBezierPath(roundedRect: CGRect(x: -R, y: -L * 0.2, width: R * 2, height: L * 0.75), cornerRadius: 2)
        UIColor(red: 0.85, green: 0.62, blue: 0.25, alpha: 1).setFill()
        body.fill()
        let tip = UIBezierPath()
        tip.move(to: CGPoint(x: -R, y: -L * 0.2))
        tip.addQuadCurve(to: CGPoint(x: 0, y: -L * 0.62), controlPoint: CGPoint(x: -R, y: -L * 0.5))
        tip.addQuadCurve(to: CGPoint(x: R, y: -L * 0.2), controlPoint: CGPoint(x: R, y: -L * 0.5))
        tip.close()
        UIColor(white: 0.85, alpha: 1).setFill()
        tip.fill()
        UIColor(red: 0.6, green: 0.42, blue: 0.15, alpha: 1).setFill()
        UIBezierPath(rect: CGRect(x: -R * 1.1, y: L * 0.5, width: R * 2.2, height: L * 0.08)).fill()
    }
}

/// Top compass strip.
final class CompassView: UIView {
    var heading: CGFloat = 0 { didSet { if abs(oldValue - heading) > 0.2 { setNeedsDisplay() } } }
    var markerBearing: CGFloat? { didSet { setNeedsDisplay() } }
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isUserInteractionEnabled = false
        contentMode = .redraw
    }
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ rect: CGRect) {
        let w = rect.width, h = rect.height
        let span: CGFloat = 150
        let pxPerDeg = w / span
        let names: [Int: String] = [0: "北", 45: "东北", 90: "东", 135: "东南", 180: "南", 225: "西南", 270: "西", 315: "西北"]
        let attrs: [NSAttributedString.Key: Any] = [.font: Theme.mono(13), .foregroundColor: UIColor.white,
                                                    .strokeColor: UIColor.black, .strokeWidth: -2.0]
        let small: [NSAttributedString.Key: Any] = [.font: Theme.mono(10), .foregroundColor: UIColor(white: 1, alpha: 0.8)]
        guard let g = UIGraphicsGetCurrentContext() else { return }
        g.setStrokeColor(UIColor(white: 1, alpha: 0.85).cgColor)
        g.setLineWidth(1.5)
        let start = Int((heading - span / 2).rounded(.down))
        let end = Int((heading + span / 2).rounded(.up))
        for d in start...end where d % 5 == 0 {
            let x = w / 2 + (CGFloat(d) - heading) * pxPerDeg
            var dd = d % 360
            if dd < 0 { dd += 360 }
            let major = dd % 15 == 0
            g.move(to: CGPoint(x: x, y: h * 0.62))
            g.addLine(to: CGPoint(x: x, y: major ? h * 0.36 : h * 0.5))
            g.strokePath()
            if dd % 15 == 0 {
                let s = names[dd] ?? "\(dd)"
                let a = NSAttributedString(string: s, attributes: names[dd] != nil ? attrs : small)
                let sz = a.size()
                a.draw(at: CGPoint(x: x - sz.width / 2, y: 0))
            }
        }
        // center pointer
        let tri = UIBezierPath()
        tri.move(to: CGPoint(x: w / 2 - 6, y: h))
        tri.addLine(to: CGPoint(x: w / 2 + 6, y: h))
        tri.addLine(to: CGPoint(x: w / 2, y: h - 8))
        tri.close()
        Theme.yellow.setFill()
        tri.fill()
        let hd = NSAttributedString(string: "\(Int(heading.rounded()) % 360)", attributes: [.font: Theme.mono(11), .foregroundColor: Theme.yellow])
        hd.draw(at: CGPoint(x: w / 2 + 9, y: h - 14))
        if let mb = markerBearing {
            var diff = mb - heading
            while diff > 180 { diff -= 360 }
            while diff < -180 { diff += 360 }
            if abs(diff) < span / 2 {
                let x = w / 2 + diff * pxPerDeg
                UIColor(red: 1, green: 0.4, blue: 0.2, alpha: 1).setFill()
                UIBezierPath(ovalIn: CGRect(x: x - 4, y: h * 0.66, width: 8, height: 8)).fill()
            }
        }
    }
}

/// Crosshair + hit marker.
final class CrosshairView: UIView {
    var spread: CGFloat = 10 { didSet { if abs(oldValue - spread) > 0.5 { setNeedsDisplay() } } }
    var aiming = false { didSet { if oldValue != aiming { setNeedsDisplay() } } }
    var hitAlpha: CGFloat = 0 { didSet { if abs(oldValue - hitAlpha) > 0.02 { setNeedsDisplay() } } }
    var killHit = false
    var hideAll = false { didSet { if oldValue != hideAll { setNeedsDisplay() } } }
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isUserInteractionEnabled = false
        contentMode = .redraw
    }
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ rect: CGRect) {
        guard let g = UIGraphicsGetCurrentContext(), !hideAll else { return }
        let c = CGPoint(x: rect.midX, y: rect.midY)
        g.setLineCap(.round)
        if aiming {
            UIColor(red: 1, green: 0.15, blue: 0.1, alpha: 1).setFill()
            g.fillEllipse(in: CGRect(x: c.x - 2.5, y: c.y - 2.5, width: 5, height: 5))
        } else {
            g.setStrokeColor(UIColor(white: 1, alpha: 0.9).cgColor)
            g.setShadow(offset: .zero, blur: 2, color: UIColor.black.cgColor)
            g.setLineWidth(2)
            let s = 4 + spread, l: CGFloat = 9
            for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] as [(CGFloat, CGFloat)] {
                g.move(to: CGPoint(x: c.x + dx * s, y: c.y + dy * s))
                g.addLine(to: CGPoint(x: c.x + dx * (s + l), y: c.y + dy * (s + l)))
            }
            g.strokePath()
            UIColor.white.setFill()
            g.fillEllipse(in: CGRect(x: c.x - 1.2, y: c.y - 1.2, width: 2.4, height: 2.4))
        }
        if hitAlpha > 0 {
            let col = killHit ? UIColor(red: 1, green: 0.2, blue: 0.15, alpha: hitAlpha) : UIColor(white: 1, alpha: hitAlpha)
            g.setStrokeColor(col.cgColor)
            g.setLineWidth(2.5)
            let a: CGFloat = 7, b: CGFloat = 15
            for (dx, dy) in [(1, 1), (-1, 1), (1, -1), (-1, -1)] as [(CGFloat, CGFloat)] {
                g.move(to: CGPoint(x: c.x + dx * a, y: c.y + dy * a))
                g.addLine(to: CGPoint(x: c.x + dx * b, y: c.y + dy * b))
            }
            g.strokePath()
        }
    }
}

/// Black scope mask with reticle.
final class ScopeOverlay: UIView {
    var scope: ScopeType = .x4 { didSet { if oldValue != scope { setNeedsDisplay() } } }
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isUserInteractionEnabled = false
        contentMode = .redraw
    }
    required init?(coder: NSCoder) { fatalError() }
    override func draw(_ rect: CGRect) {
        guard let g = UIGraphicsGetCurrentContext() else { return }
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let r = rect.height * 0.47
        let path = UIBezierPath(rect: rect)
        path.append(UIBezierPath(ovalIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)))
        path.usesEvenOddFillRule = true
        UIColor.black.setFill()
        path.fill()
        // lens edge vignette
        let cs = CGColorSpaceCreateDeviceRGB()
        if let grad = CGGradient(colorsSpace: cs, colors: [UIColor(white: 0, alpha: 0).cgColor, UIColor(white: 0, alpha: 0.75).cgColor] as CFArray, locations: [0.8, 1.0]) {
            g.saveGState()
            g.addEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
            g.clip()
            g.drawRadialGradient(grad, startCenter: c, startRadius: 0, endCenter: c, endRadius: r, options: [])
            g.restoreGState()
        }
        g.setStrokeColor(UIColor.black.cgColor)
        g.setLineWidth(1.4)
        g.move(to: CGPoint(x: c.x - r, y: c.y)); g.addLine(to: CGPoint(x: c.x - 8, y: c.y))
        g.move(to: CGPoint(x: c.x + 8, y: c.y)); g.addLine(to: CGPoint(x: c.x + r, y: c.y))
        g.move(to: CGPoint(x: c.x, y: c.y + 8)); g.addLine(to: CGPoint(x: c.x, y: c.y + r))
        g.strokePath()
        g.setLineWidth(3)
        g.move(to: CGPoint(x: c.x - r, y: c.y)); g.addLine(to: CGPoint(x: c.x - r * 0.45, y: c.y))
        g.move(to: CGPoint(x: c.x + r * 0.45, y: c.y)); g.addLine(to: CGPoint(x: c.x + r, y: c.y))
        g.move(to: CGPoint(x: c.x, y: c.y + r * 0.45)); g.addLine(to: CGPoint(x: c.x, y: c.y + r))
        g.strokePath()
        // drop marks
        g.setLineWidth(1.2)
        for k in 1...4 {
            let y = c.y + CGFloat(k) * r * 0.08
            let hw: CGFloat = k % 2 == 0 ? 10 : 6
            g.move(to: CGPoint(x: c.x - hw, y: y)); g.addLine(to: CGPoint(x: c.x + hw, y: y))
        }
        g.strokePath()
        UIColor(red: 1, green: 0.1, blue: 0.1, alpha: 0.95).setFill()
        g.fillEllipse(in: CGRect(x: c.x - 1.8, y: c.y - 1.8, width: 3.6, height: 3.6))
    }
}

/// Red damage vignette with direction indicator.
final class DamageOverlay: UIView {
    var intensity: CGFloat = 0 { didSet { if abs(oldValue - intensity) > 0.02 { setNeedsDisplay() } } }
    var direction: CGFloat = 99
    var outsideZone = false { didSet { if oldValue != outsideZone { setNeedsDisplay() } } }
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isUserInteractionEnabled = false
        contentMode = .redraw
    }
    required init?(coder: NSCoder) { fatalError() }
    override func draw(_ rect: CGRect) {
        guard let g = UIGraphicsGetCurrentContext() else { return }
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let cs = CGColorSpaceCreateDeviceRGB()
        if outsideZone {
            UIColor(red: 0.15, green: 0.35, blue: 1.0, alpha: 0.13).setFill()
            g.fill(rect)
        }
        if intensity > 0.01 {
            let colors = [UIColor(red: 0.8, green: 0, blue: 0, alpha: 0).cgColor, UIColor(red: 0.8, green: 0, blue: 0, alpha: 0.55 * intensity).cgColor] as CFArray
            if let grad = CGGradient(colorsSpace: cs, colors: colors, locations: [0.55, 1.0]) {
                let r = max(rect.width, rect.height) * 0.6
                g.drawRadialGradient(grad, startCenter: c, startRadius: 0, endCenter: c, endRadius: r, options: [.drawsAfterEndLocation])
            }
            if direction < 50 {
                // screen angle: 0 = up; direction>0 means attacker to the left
                let ang = -direction - .pi / 2
                let rr: CGFloat = min(rect.width, rect.height) * 0.32
                g.setStrokeColor(UIColor(red: 1, green: 0.15, blue: 0.1, alpha: 0.85 * intensity).cgColor)
                g.setLineWidth(7)
                g.setLineCap(.round)
                g.addArc(center: c, radius: rr, startAngle: ang - 0.3, endAngle: ang + 0.3, clockwise: false)
                g.strokePath()
            }
        }
    }
}

/// Weapon slot tile at the bottom of the screen.
final class SlotView: UIView {
    let name = UILabel()
    let ammo = UILabel()
    let scope = UILabel()
    var onTap: (() -> Void)?
    var isActive = false { didSet { refresh() } }

    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.cornerRadius = 6
        layer.borderWidth = 1.5
        name.font = Theme.font(13, .bold)
        name.textColor = .white
        ammo.font = Theme.mono(14)
        ammo.textColor = .white
        scope.font = Theme.font(9)
        scope.textColor = UIColor(white: 1, alpha: 0.7)
        for l in [name, ammo, scope] { addSubview(l) }
        refresh()
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        let w = bounds.width, h = bounds.height
        name.frame = CGRect(x: 8, y: 2, width: w - 16, height: h * 0.5)
        ammo.frame = CGRect(x: 8, y: h * 0.48, width: w * 0.6, height: h * 0.5)
        scope.frame = CGRect(x: w * 0.5, y: h * 0.52, width: w * 0.5 - 6, height: h * 0.42)
        scope.textAlignment = .right
    }

    func set(_ s: SlotInfo, placeholder: String) {
        if s.present {
            name.text = s.name
            ammo.text = "\(s.mag)/\(s.reserve)"
            ammo.textColor = s.mag == 0 ? UIColor(red: 1, green: 0.35, blue: 0.3, alpha: 1) : .white
            scope.text = s.scope
            alpha = 1
        } else {
            name.text = placeholder
            ammo.text = ""
            scope.text = ""
            alpha = 0.55
        }
    }

    private func refresh() {
        backgroundColor = isActive ? UIColor(white: 0, alpha: 0.55) : Theme.panel
        layer.borderColor = (isActive ? Theme.yellow : UIColor(white: 1, alpha: 0.25)).cgColor
        name.textColor = isActive ? Theme.yellow : .white
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        onTap?()
    }
}

/// Square minimap (north up) drawn from the generated map image.
final class MinimapView: UIView {
    var image: UIImage?
    var state = HUDState()
    var range: Float = 340
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor(white: 0, alpha: 0.5)
        layer.borderWidth = 1.5
        layer.borderColor = UIColor(white: 1, alpha: 0.6).cgColor
        clipsToBounds = true
        contentMode = .redraw
    }
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ rect: CGRect) {
        guard let img = image, let g = UIGraphicsGetCurrentContext() else { return }
        let s = state
        let w = rect.width
        let scale = w / CGFloat(range)          // points per metre
        let center = s.phase == .plane ? s.planePos : s.pos
        func toView(_ p: V2) -> CGPoint {
            return CGPoint(x: w / 2 + CGFloat(p.x - center.x) * scale, y: rect.height / 2 + CGFloat(p.y - center.y) * scale)
        }
        // draw map image portion
        let mapPts = CGFloat(1600) * scale
        let origin = toView(V2(-800, -800))
        img.draw(in: CGRect(x: origin.x, y: origin.y, width: mapPts, height: mapPts))
        drawZones(g, s, toView, scale)
        if s.phase == .plane || s.phase == .freefall {
            g.setStrokeColor(UIColor(white: 1, alpha: 0.8).cgColor)
            g.setLineWidth(1.5)
            g.setLineDash(phase: 0, lengths: [5, 4])
            g.move(to: toView(s.planeStart)); g.addLine(to: toView(s.planeEnd))
            g.strokePath()
            g.setLineDash(phase: 0, lengths: [])
        }
        if let m = s.marker {
            let p = toView(m)
            UIColor(red: 1, green: 0.4, blue: 0.2, alpha: 1).setFill()
            g.fillEllipse(in: CGRect(x: p.x - 4, y: p.y - 4, width: 8, height: 8))
        }
        // player arrow
        let pp = toView(s.pos)
        g.saveGState()
        g.translateBy(x: pp.x, y: pp.y)
        g.rotate(by: CGFloat(-s.yaw))
        let tri = UIBezierPath()
        tri.move(to: CGPoint(x: 0, y: -8))
        tri.addLine(to: CGPoint(x: 5.5, y: 6))
        tri.addLine(to: CGPoint(x: 0, y: 3))
        tri.addLine(to: CGPoint(x: -5.5, y: 6))
        tri.close()
        Theme.yellow.setFill()
        tri.fill()
        UIColor.black.setStroke()
        tri.lineWidth = 1
        tri.stroke()
        g.restoreGState()
    }

    func drawZones(_ g: CGContext, _ s: HUDState, _ toView: (V2) -> CGPoint, _ scale: CGFloat) {
        let zc = toView(s.zoneCenter), zr = CGFloat(s.zoneRadius) * scale
        g.setStrokeColor(UIColor(red: 0.25, green: 0.5, blue: 1.0, alpha: 0.95).cgColor)
        g.setLineWidth(2)
        g.strokeEllipse(in: CGRect(x: zc.x - zr, y: zc.y - zr, width: zr * 2, height: zr * 2))
        let nc = toView(s.nextCenter), nr = CGFloat(s.nextRadius) * scale
        g.setStrokeColor(UIColor.white.cgColor)
        g.setLineWidth(1.6)
        g.strokeEllipse(in: CGRect(x: nc.x - nr, y: nc.y - nr, width: nr * 2, height: nr * 2))
        if s.phase != .plane {
            let d = simd_length(s.pos - s.nextCenter)
            if d > s.nextRadius {
                g.setStrokeColor(UIColor(white: 1, alpha: 0.6).cgColor)
                g.setLineWidth(1)
                g.setLineDash(phase: 0, lengths: [3, 3])
                let dir = (s.nextCenter - s.pos) / d
                let edge = s.nextCenter - dir * s.nextRadius
                g.move(to: toView(s.pos)); g.addLine(to: toView(edge))
                g.strokePath()
                g.setLineDash(phase: 0, lengths: [])
            }
        }
    }
}
