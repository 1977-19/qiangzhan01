import UIKit

/// Lobby: choose map, graphics quality, view and sensitivity.
final class MenuViewController: UIViewController {
    var onStart: ((GameSettings) -> Void)?
    private var settings = GameSettings()
    private let bg = UIImageView()
    private let shade = UIView()
    private let titleLabel = UILabel()
    private let subtitle = UILabel()
    private var mapCards: [UIButton] = []
    private let quality = UISegmentedControl(items: ["流畅", "高清", "极致"])
    private let viewMode = UISegmentedControl(items: ["第三人称", "第一人称"])
    private let sens = UISlider()
    private let sensLabel = UILabel()
    private let botsLabel = UILabel()
    private let bots = UIStepper()
    private let start = UIButton(type: .custom)
    private let qLabel = UILabel()
    private let vLabel = UILabel()
    private let note = UILabel()

    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }

    override func viewDidLoad() {
        super.viewDidLoad()
        let d = UserDefaults.standard
        if d.object(forKey: "quality") != nil { settings.quality = d.integer(forKey: "quality") }
        if d.object(forKey: "sens") != nil { settings.sensitivity = d.float(forKey: "sens") }
        if d.object(forKey: "map") != nil { settings.map = MapKind(rawValue: d.integer(forKey: "map")) ?? .island }
        if d.object(forKey: "fpp") != nil { settings.fpp = d.bool(forKey: "fpp") }
        if d.object(forKey: "bots") != nil { settings.bots = max(9, min(59, d.integer(forKey: "bots"))) }

        view.backgroundColor = .black
        bg.image = MenuViewController.backdrop()
        bg.contentMode = .scaleAspectFill
        bg.clipsToBounds = true
        view.addSubview(bg)
        shade.backgroundColor = UIColor(white: 0, alpha: 0.35)
        view.addSubview(shade)

        titleLabel.text = "枪战01"
        titleLabel.font = UIFont.systemFont(ofSize: 52, weight: .black)
        titleLabel.textColor = Theme.yellow
        titleLabel.shadowColor = .black
        titleLabel.shadowOffset = CGSize(width: 2, height: 2)
        view.addSubview(titleLabel)
        subtitle.text = "战术竞技 · 单人吃鸡"
        subtitle.font = Theme.font(16, .bold)
        subtitle.textColor = .white
        view.addSubview(subtitle)

        for k in [MapKind.island, MapKind.snow] {
            let b = UIButton(type: .custom)
            b.tag = k.rawValue
            b.layer.cornerRadius = 12
            b.clipsToBounds = true
            b.layer.borderWidth = 3
            b.setBackgroundImage(MenuViewController.cardImage(k), for: .normal)
            b.titleLabel?.numberOfLines = 2
            b.contentVerticalAlignment = .bottom
            b.contentHorizontalAlignment = .left
            b.titleEdgeInsets = UIEdgeInsets(top: 0, left: 14, bottom: 10, right: 8)
            let t = NSMutableAttributedString(string: k.title + "\n", attributes: [.font: Theme.font(22, .heavy), .foregroundColor: UIColor.white])
            t.append(NSAttributedString(string: k.subtitle, attributes: [.font: Theme.font(12, .semibold), .foregroundColor: UIColor(white: 1, alpha: 0.85)]))
            b.setAttributedTitle(t, for: .normal)
            b.addTarget(self, action: #selector(mapTap(_:)), for: .touchUpInside)
            view.addSubview(b)
            mapCards.append(b)
        }

        for (l, t) in [(qLabel, "画质"), (vLabel, "视角"), (sensLabel, ""), (botsLabel, "")] {
            l.text = t
            l.font = Theme.font(14, .bold)
            l.textColor = .white
            view.addSubview(l)
        }
        quality.selectedSegmentIndex = settings.quality
        viewMode.selectedSegmentIndex = settings.fpp ? 1 : 0
        for s in [quality, viewMode] {
            s.selectedSegmentTintColor = Theme.yellow
            s.backgroundColor = UIColor(white: 0, alpha: 0.4)
            s.setTitleTextAttributes([.foregroundColor: UIColor.white, .font: Theme.font(13, .bold)], for: .normal)
            s.setTitleTextAttributes([.foregroundColor: UIColor.black, .font: Theme.font(13, .heavy)], for: .selected)
            s.addTarget(self, action: #selector(changed), for: .valueChanged)
            view.addSubview(s)
        }
        sens.minimumValue = 0.4
        sens.maximumValue = 2.5
        sens.value = settings.sensitivity
        sens.minimumTrackTintColor = Theme.yellow
        sens.addTarget(self, action: #selector(changed), for: .valueChanged)
        view.addSubview(sens)
        bots.minimumValue = 9
        bots.maximumValue = 59
        bots.stepValue = 10
        bots.value = Double(settings.bots)
        bots.addTarget(self, action: #selector(changed), for: .valueChanged)
        bots.backgroundColor = UIColor(white: 1, alpha: 0.8)
        bots.layer.cornerRadius = 8
        view.addSubview(bots)

        start.setTitle("开始游戏", for: .normal)
        start.setTitleColor(.black, for: .normal)
        start.titleLabel?.font = UIFont.systemFont(ofSize: 24, weight: .black)
        start.backgroundColor = Theme.yellow
        start.layer.cornerRadius = 12
        start.layer.shadowColor = UIColor.black.cgColor
        start.layer.shadowOpacity = 0.5
        start.layer.shadowRadius = 8
        start.addTarget(self, action: #selector(startTap), for: .touchUpInside)
        view.addSubview(start)

        note.text = "极致画质最吃性能，如果卡顿请改为高清或流畅"
        note.font = Theme.font(11)
        note.textColor = UIColor(white: 1, alpha: 0.7)
        view.addSubview(note)
        refresh()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let W = view.bounds.width, H = view.bounds.height
        let ins = view.safeAreaInsets
        let L = max(ins.left, 24), R = max(ins.right, 24)
        bg.frame = view.bounds
        shade.frame = view.bounds
        titleLabel.frame = CGRect(x: L, y: 18, width: 400, height: 60)
        subtitle.frame = CGRect(x: L + 4, y: 74, width: 400, height: 22)
        let cardW = min(240, (W - L - R) * 0.3), cardH = H * 0.5
        for (i, b) in mapCards.enumerated() {
            b.frame = CGRect(x: L + CGFloat(i) * (cardW + 14), y: 110, width: cardW, height: cardH)
        }
        let px = L + 2 * (cardW + 14) + 10
        let pw = W - R - px
        qLabel.frame = CGRect(x: px, y: 110, width: 60, height: 30)
        quality.frame = CGRect(x: px + 56, y: 110, width: pw - 56, height: 32)
        vLabel.frame = CGRect(x: px, y: 152, width: 60, height: 30)
        viewMode.frame = CGRect(x: px + 56, y: 152, width: pw - 56, height: 32)
        sensLabel.frame = CGRect(x: px, y: 194, width: pw, height: 22)
        sens.frame = CGRect(x: px, y: 216, width: pw, height: 30)
        botsLabel.frame = CGRect(x: px, y: 254, width: pw - 100, height: 30)
        bots.frame = CGRect(x: px + pw - 94, y: 254, width: 94, height: 32)
        start.frame = CGRect(x: W - R - 240, y: H - 84, width: 240, height: 60)
        note.frame = CGRect(x: L, y: H - 40, width: W - L - R - 260, height: 18)
    }

    private func refresh() {
        for b in mapCards {
            let sel = b.tag == settings.map.rawValue
            b.layer.borderColor = (sel ? Theme.yellow : UIColor(white: 1, alpha: 0.3)).cgColor
            b.alpha = sel ? 1 : 0.8
        }
        sensLabel.text = "灵敏度  \(String(format: "%.1f", settings.sensitivity))"
        botsLabel.text = "对手数量  \(settings.bots) 个AI（共 \(settings.bots + 1) 人）"
    }

    @objc private func mapTap(_ b: UIButton) {
        settings.map = MapKind(rawValue: b.tag) ?? .island
        refresh()
    }

    @objc private func changed() {
        settings.quality = quality.selectedSegmentIndex
        settings.fpp = viewMode.selectedSegmentIndex == 1
        settings.sensitivity = (sens.value * 10).rounded() / 10
        settings.bots = Int(bots.value)
        refresh()
    }

    @objc private func startTap() {
        let d = UserDefaults.standard
        d.set(settings.quality, forKey: "quality")
        d.set(settings.sensitivity, forKey: "sens")
        d.set(settings.map.rawValue, forKey: "map")
        d.set(settings.fpp, forKey: "fpp")
        d.set(settings.bots, forKey: "bots")
        onStart?(settings)
    }

    // MARK: procedural art

    static func backdrop() -> UIImage {
        let size = CGSize(width: 900, height: 420)
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = 1
        return UIGraphicsImageRenderer(size: size, format: fmt).image { ctx in
            let g = ctx.cgContext
            let cs = CGColorSpaceCreateDeviceRGB()
            let sky = [UIColor(red: 0.15, green: 0.25, blue: 0.45, alpha: 1).cgColor,
                       UIColor(red: 0.95, green: 0.6, blue: 0.3, alpha: 1).cgColor] as CFArray
            if let gr = CGGradient(colorsSpace: cs, colors: sky, locations: [0, 1]) {
                g.drawLinearGradient(gr, start: .zero, end: CGPoint(x: 0, y: size.height * 0.75), options: [.drawsAfterEndLocation])
            }
            UIColor(red: 1, green: 0.85, blue: 0.6, alpha: 0.9).setFill()
            g.fillEllipse(in: CGRect(x: 600, y: 170, width: 70, height: 70))
            var rng = RNG(5)
            for layer in 0..<3 {
                let base = size.height * (0.55 + CGFloat(layer) * 0.12)
                let c = CGFloat(0.12 - Double(layer) * 0.035)
                UIColor(red: c, green: c + 0.03, blue: c + 0.05, alpha: 1).setFill()
                let p = UIBezierPath()
                p.move(to: CGPoint(x: 0, y: size.height))
                var x: CGFloat = 0
                while x <= size.width + 30 {
                    let y = base - CGFloat(rng.r(0, 60)) * CGFloat(1 - Double(layer) * 0.25)
                    p.addLine(to: CGPoint(x: x, y: y))
                    x += CGFloat(rng.r(25, 60))
                }
                p.addLine(to: CGPoint(x: size.width, y: size.height))
                p.close()
                p.fill()
            }
            // pine silhouettes
            UIColor(red: 0.03, green: 0.05, blue: 0.05, alpha: 1).setFill()
            for _ in 0..<26 {
                let x = CGFloat(rng.r(0, Float(size.width)))
                let h = CGFloat(rng.r(60, 140))
                let base = size.height - CGFloat(rng.r(0, 30))
                for k in 0..<4 {
                    let w = h * 0.32 * (1 - CGFloat(k) / 5)
                    let y = base - CGFloat(k) * h / 5
                    let t = UIBezierPath()
                    t.move(to: CGPoint(x: x - w, y: y))
                    t.addLine(to: CGPoint(x: x + w, y: y))
                    t.addLine(to: CGPoint(x: x, y: y - h / 2.4))
                    t.close()
                    t.fill()
                }
            }
            // soldier silhouette
            let s = UIBezierPath()
            let bx: CGFloat = 690, by: CGFloat = 420
            s.move(to: CGPoint(x: bx - 30, y: by))
            s.addLine(to: CGPoint(x: bx - 22, y: by - 120))
            s.addLine(to: CGPoint(x: bx - 34, y: by - 200))
            s.addQuadCurve(to: CGPoint(x: bx + 20, y: by - 205), controlPoint: CGPoint(x: bx - 5, y: by - 225))
            s.addLine(to: CGPoint(x: bx + 32, y: by - 120))
            s.addLine(to: CGPoint(x: bx + 26, y: by))
            s.close()
            s.fill()
            g.fillEllipse(in: CGRect(x: bx - 20, y: by - 252, width: 38, height: 42))
            g.fill(CGRect(x: bx - 120, y: by - 190, width: 150, height: 12))
        }
    }

    static func cardImage(_ k: MapKind) -> UIImage {
        let size = CGSize(width: 260, height: 220)
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = 2
        return UIGraphicsImageRenderer(size: size, format: fmt).image { ctx in
            let g = ctx.cgContext
            let cs = CGColorSpaceCreateDeviceRGB()
            let colors: CFArray
            if k == .island {
                colors = [UIColor(red: 0.35, green: 0.62, blue: 0.85, alpha: 1).cgColor, UIColor(red: 0.20, green: 0.45, blue: 0.25, alpha: 1).cgColor] as CFArray
            } else {
                colors = [UIColor(red: 0.62, green: 0.72, blue: 0.85, alpha: 1).cgColor, UIColor(red: 0.85, green: 0.88, blue: 0.92, alpha: 1).cgColor] as CFArray
            }
            if let gr = CGGradient(colorsSpace: cs, colors: colors, locations: [0, 1]) {
                g.drawLinearGradient(gr, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
            }
            var rng = RNG(UInt64(k.rawValue + 3))
            if k == .island {
                UIColor(red: 0.12, green: 0.38, blue: 0.55, alpha: 1).setFill()
                g.fill(CGRect(x: 0, y: 120, width: size.width, height: 100))
                UIColor(red: 0.30, green: 0.52, blue: 0.22, alpha: 1).setFill()
                g.fillEllipse(in: CGRect(x: 20, y: 95, width: 220, height: 70))
                UIColor(red: 0.85, green: 0.78, blue: 0.55, alpha: 1).setStroke()
                g.setLineWidth(3)
                g.strokeEllipse(in: CGRect(x: 20, y: 95, width: 220, height: 70))
            } else {
                UIColor(red: 0.45, green: 0.5, blue: 0.58, alpha: 1).setFill()
                let m = UIBezierPath()
                m.move(to: CGPoint(x: 0, y: 150))
                m.addLine(to: CGPoint(x: 60, y: 60)); m.addLine(to: CGPoint(x: 110, y: 120))
                m.addLine(to: CGPoint(x: 170, y: 40)); m.addLine(to: CGPoint(x: 260, y: 140))
                m.addLine(to: CGPoint(x: 260, y: 220)); m.addLine(to: CGPoint(x: 0, y: 220))
                m.close()
                m.fill()
                UIColor.white.setFill()
                for (x, y) in [(60, 60), (170, 40)] as [(CGFloat, CGFloat)] {
                    let c = UIBezierPath()
                    c.move(to: CGPoint(x: x, y: y)); c.addLine(to: CGPoint(x: x - 18, y: y + 26)); c.addLine(to: CGPoint(x: x + 22, y: y + 28))
                    c.close()
                    c.fill()
                }
                UIColor(red: 0.3, green: 0.45, blue: 0.55, alpha: 1).setFill()
                g.fill(CGRect(x: 0, y: 165, width: size.width, height: 14))
            }
            UIColor(red: 0.05, green: 0.15, blue: 0.08, alpha: 1).setFill()
            for _ in 0..<12 {
                let x = CGFloat(rng.r(10, 250)), base = CGFloat(rng.r(140, 175)), h = CGFloat(rng.r(20, 40))
                let t = UIBezierPath()
                t.move(to: CGPoint(x: x - h * 0.3, y: base)); t.addLine(to: CGPoint(x: x + h * 0.3, y: base)); t.addLine(to: CGPoint(x: x, y: base - h))
                t.close()
                t.fill()
            }
            let shadow = [UIColor(white: 0, alpha: 0).cgColor, UIColor(white: 0, alpha: 0.7).cgColor] as CFArray
            if let gr = CGGradient(colorsSpace: cs, colors: shadow, locations: [0.4, 1]) {
                g.drawLinearGradient(gr, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
            }
        }
    }
}
