import UIKit
import simd

private func makeButton(_ title: String, color: UIColor = Theme.yellow, textColor: UIColor = .black, size: CGFloat = 15) -> UIButton {
    let b = UIButton(type: .custom)
    b.setTitle(title, for: .normal)
    b.setTitleColor(textColor, for: .normal)
    b.titleLabel?.font = Theme.font(size, .heavy)
    b.backgroundColor = color
    b.layer.cornerRadius = 8
    return b
}

// MARK: - Full map

final class FullMapView: UIView {
    let image: UIImage
    var state: HUDState
    var places: [PlaceName]
    var onTapWorld: ((V2) -> Void)?

    init(image: UIImage, state: HUDState, places: [PlaceName]) {
        self.image = image
        self.state = state
        self.places = places
        super.init(frame: .zero)
        backgroundColor = .black
        contentMode = .redraw
        let tap = UITapGestureRecognizer(target: self, action: #selector(tapped(_:)))
        addGestureRecognizer(tap)
    }
    required init?(coder: NSCoder) { fatalError() }

    private func toView(_ p: V2) -> CGPoint {
        let s = bounds.width
        return CGPoint(x: CGFloat((p.x + 800) / 1600) * s, y: CGFloat((p.y + 800) / 1600) * s)
    }

    @objc private func tapped(_ g: UITapGestureRecognizer) {
        let p = g.location(in: self)
        let s = bounds.width
        let w = V2(Float(p.x / s) * 1600 - 800, Float(p.y / s) * 1600 - 800)
        onTapWorld?(w)
    }

    override func draw(_ rect: CGRect) {
        guard let g = UIGraphicsGetCurrentContext() else { return }
        image.draw(in: bounds)
        let s = state
        let scale = bounds.width / 1600
        let zc = toView(s.zoneCenter), zr = CGFloat(s.zoneRadius) * scale
        g.setStrokeColor(UIColor(red: 0.25, green: 0.5, blue: 1.0, alpha: 1).cgColor)
        g.setLineWidth(3)
        g.strokeEllipse(in: CGRect(x: zc.x - zr, y: zc.y - zr, width: zr * 2, height: zr * 2))
        let nc = toView(s.nextCenter), nr = CGFloat(s.nextRadius) * scale
        g.setStrokeColor(UIColor.white.cgColor)
        g.setLineWidth(2)
        g.strokeEllipse(in: CGRect(x: nc.x - nr, y: nc.y - nr, width: nr * 2, height: nr * 2))
        if s.phase == .plane || s.phase == .freefall || s.phase == .chute {
            g.setStrokeColor(UIColor(white: 1, alpha: 0.85).cgColor)
            g.setLineWidth(2)
            g.setLineDash(phase: 0, lengths: [8, 6])
            g.move(to: toView(s.planeStart)); g.addLine(to: toView(s.planeEnd))
            g.strokePath()
            g.setLineDash(phase: 0, lengths: [])
            let pp = toView(s.planePos)
            UIColor.white.setFill()
            g.fillEllipse(in: CGRect(x: pp.x - 5, y: pp.y - 5, width: 10, height: 10))
        }
        if let m = s.marker {
            let p = toView(m)
            UIColor(red: 1, green: 0.4, blue: 0.2, alpha: 1).setFill()
            g.fillEllipse(in: CGRect(x: p.x - 6, y: p.y - 6, width: 12, height: 12))
        }
        let me = toView(s.phase == .plane ? s.planePos : s.pos)
        g.saveGState()
        g.translateBy(x: me.x, y: me.y)
        g.rotate(by: CGFloat(-s.yaw))
        let tri = UIBezierPath()
        tri.move(to: CGPoint(x: 0, y: -11))
        tri.addLine(to: CGPoint(x: 8, y: 8))
        tri.addLine(to: CGPoint(x: 0, y: 4))
        tri.addLine(to: CGPoint(x: -8, y: 8))
        tri.close()
        Theme.yellow.setFill()
        tri.fill()
        UIColor.black.setStroke()
        tri.stroke()
        g.restoreGState()
    }
}

final class MapOverlay: UIView {
    var onClose: (() -> Void)?
    var onMarker: ((V2?) -> Void)?
    private let map: FullMapView
    private let close = makeButton("关闭")
    private let clear = makeButton("清除标记", color: UIColor(white: 0.2, alpha: 0.9), textColor: .white, size: 13)
    private let legend = UILabel()

    init(image: UIImage, state: HUDState, places: [PlaceName]) {
        map = FullMapView(image: image, state: state, places: places)
        super.init(frame: .zero)
        backgroundColor = UIColor(white: 0, alpha: 0.85)
        addSubview(map)
        addSubview(close)
        addSubview(clear)
        legend.numberOfLines = 0
        legend.font = Theme.font(12)
        legend.textColor = .white
        legend.text = "蓝圈：当前毒圈\n白圈：下一个安全区\n黄色箭头：你的位置\n点击地图：放置标记\n\n\(state.zoneText)"
        addSubview(legend)
        close.addTarget(self, action: #selector(closeTap), for: .touchUpInside)
        clear.addTarget(self, action: #selector(clearTap), for: .touchUpInside)
        map.onTapWorld = { [weak self] p in
            self?.map.state.marker = p
            self?.map.setNeedsDisplay()
            self?.onMarker?(p)
        }
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        let s = bounds.height - 20
        map.frame = CGRect(x: (bounds.width - s) / 2, y: 10, width: s, height: s)
        close.frame = CGRect(x: bounds.width - 130, y: 16, width: 100, height: 40)
        clear.frame = CGRect(x: bounds.width - 130, y: 64, width: 100, height: 34)
        legend.frame = CGRect(x: 30, y: 20, width: (bounds.width - s) / 2 - 40, height: 200)
    }

    @objc private func closeTap() { onClose?() }
    @objc private func clearTap() {
        map.state.marker = nil
        map.setNeedsDisplay()
        onMarker?(nil)
    }
}

// MARK: - Inventory

final class InventoryOverlay: UIView {
    var onClose: (() -> Void)?
    var onCommand: ((UICommand) -> Void)?
    private weak var world: GameWorld?
    private let titleLabel = UILabel()
    private let close = makeButton("关闭")
    private let cols: [UIStackView] = [UIStackView(), UIStackView(), UIStackView()]
    private let scrolls: [UIScrollView] = [UIScrollView(), UIScrollView(), UIScrollView()]
    private let headers: [UILabel] = [UILabel(), UILabel(), UILabel()]
    private var timer: Timer?
    private var signature = ""

    init(world: GameWorld) {
        self.world = world
        super.init(frame: .zero)
        backgroundColor = UIColor(white: 0, alpha: 0.78)
        titleLabel.text = "背包"
        titleLabel.font = Theme.font(22, .heavy)
        titleLabel.textColor = Theme.yellow
        addSubview(titleLabel)
        addSubview(close)
        close.addTarget(self, action: #selector(closeTap), for: .touchUpInside)
        let names = ["附近物资", "背包", "装备"]
        for i in 0..<3 {
            headers[i].text = names[i]
            headers[i].font = Theme.font(15, .bold)
            headers[i].textColor = .white
            addSubview(headers[i])
            scrolls[i].backgroundColor = UIColor(white: 1, alpha: 0.06)
            scrolls[i].layer.cornerRadius = 8
            addSubview(scrolls[i])
            cols[i].axis = .vertical
            cols[i].spacing = 6
            scrolls[i].addSubview(cols[i])
        }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in self?.refresh() }
    }
    required init?(coder: NSCoder) { fatalError() }

    override func removeFromSuperview() {
        timer?.invalidate()
        timer = nil
        super.removeFromSuperview()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let ins = safeAreaInsets
        let L = max(ins.left, 20), R = max(ins.right, 20)
        titleLabel.frame = CGRect(x: L, y: 12, width: 200, height: 30)
        close.frame = CGRect(x: bounds.width - R - 100, y: 10, width: 96, height: 36)
        let colW = (bounds.width - L - R - 24) / 3
        for i in 0..<3 {
            let x = L + CGFloat(i) * (colW + 12)
            headers[i].frame = CGRect(x: x + 4, y: 50, width: colW, height: 22)
            scrolls[i].frame = CGRect(x: x, y: 74, width: colW, height: bounds.height - 84)
            layoutColumn(i)
        }
    }

    private func layoutColumn(_ i: Int) {
        let w = scrolls[i].bounds.width - 12
        let size = cols[i].systemLayoutSizeFitting(CGSize(width: w, height: UIView.layoutFittingCompressedSize.height),
                                                   withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel)
        cols[i].frame = CGRect(x: 6, y: 6, width: w, height: max(size.height, 10))
        scrolls[i].contentSize = CGSize(width: w, height: size.height + 12)
    }

    private func row(_ title: String, color: UIColor, actions: [(String, UICommand)]) -> UIView {
        let v = UIView()
        v.backgroundColor = UIColor(white: 0, alpha: 0.45)
        v.layer.cornerRadius = 6
        let l = UILabel()
        l.text = title
        l.font = Theme.font(13, .bold)
        l.textColor = color
        l.adjustsFontSizeToFitWidth = true
        l.minimumScaleFactor = 0.6
        l.translatesAutoresizingMaskIntoConstraints = false
        v.addSubview(l)
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        for (t, c) in actions {
            let b = ActionButton(type: .custom)
            b.command = c
            b.setTitle(t, for: .normal)
            b.titleLabel?.font = Theme.font(12, .heavy)
            b.setTitleColor(.black, for: .normal)
            b.backgroundColor = t == "丢弃" ? UIColor(red: 0.9, green: 0.45, blue: 0.35, alpha: 1) : Theme.yellow
            b.layer.cornerRadius = 5
            b.contentEdgeInsets = UIEdgeInsets(top: 4, left: 10, bottom: 4, right: 10)
            b.addTarget(self, action: #selector(actionTap(_:)), for: .touchUpInside)
            stack.addArrangedSubview(b)
        }
        v.addSubview(stack)
        NSLayoutConstraint.activate([
            v.heightAnchor.constraint(equalToConstant: 40),
            l.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 10),
            l.centerYAnchor.constraint(equalTo: v.centerYAnchor),
            stack.trailingAnchor.constraint(equalTo: v.trailingAnchor, constant: -6),
            stack.centerYAnchor.constraint(equalTo: v.centerYAnchor),
            l.trailingAnchor.constraint(lessThanOrEqualTo: stack.leadingAnchor, constant: -6),
        ])
        return v
    }

    @objc private func actionTap(_ b: ActionButton) {
        if let c = b.command { onCommand?(c) }
        signature = ""
    }

    private func refresh() {
        guard let w = world else { return }
        let h = w.readHUD()
        var sig = ""
        for p in h.pickups { sig += "\(p.id):\(p.count)," }
        sig += "|\(h.ammo)|\(h.meds)|\(h.throwables)|\(h.scopes)|\(h.helmet)\(h.vest)\(h.bag)"
        for s in h.slots { sig += "|\(s.name)\(s.mag)\(s.scope)" }
        if sig == signature { return }
        signature = sig
        for c in cols { for v in c.arrangedSubviews { v.removeFromSuperview() } }
        // nearby
        if h.pickups.isEmpty {
            let l = UILabel()
            l.text = "  附近没有物资"
            l.textColor = .lightGray
            l.font = Theme.font(13)
            l.heightAnchor.constraint(equalToConstant: 30).isActive = true
            cols[0].addArrangedSubview(l)
        }
        for p in h.pickups {
            cols[0].addArrangedSubview(row(p.name + (p.count > 1 ? " ×\(p.count)" : ""), color: p.tint, actions: [("拾取", .pick(p.id))]))
        }
        // bag
        for a in AmmoType.allCases where h.ammo[a.rawValue] > 0 {
            cols[1].addArrangedSubview(row("\(a.name) ×\(h.ammo[a.rawValue])", color: ItemKind.ammo(a).tint, actions: [("丢弃", .dropItem(.ammo(a)))]))
        }
        for m in MedType.allCases where h.meds[m.rawValue] > 0 {
            cols[1].addArrangedSubview(row("\(m.name) ×\(h.meds[m.rawValue])", color: ItemKind.med(m).tint, actions: [("使用", .med(m)), ("丢弃", .dropItem(.med(m)))]))
        }
        for t in ThrowType.allCases where h.throwables[t.rawValue] > 0 {
            cols[1].addArrangedSubview(row("\(t.name) ×\(h.throwables[t.rawValue])", color: ItemKind.throwable(t).tint, actions: [("装备", .throwSelect(t)), ("丢弃", .dropItem(.throwable(t)))]))
        }
        for s in ScopeType.allCases where s != .iron && h.scopes[s.rawValue] > 0 {
            cols[1].addArrangedSubview(row("\(s.name) ×\(h.scopes[s.rawValue])", color: ItemKind.scope(s).tint, actions: [("丢弃", .dropItem(.scope(s)))]))
        }
        if cols[1].arrangedSubviews.isEmpty {
            let l = UILabel()
            l.text = "  背包是空的"
            l.textColor = .lightGray
            l.font = Theme.font(13)
            l.heightAnchor.constraint(equalToConstant: 30).isActive = true
            cols[1].addArrangedSubview(l)
        }
        // equipment
        let slotNames = ["主武器1", "主武器2", "手枪"]
        for i in 0..<3 {
            let s = h.slots[i]
            if s.present {
                let txt = "\(slotNames[i])：\(s.name)  \(s.mag)发" + (s.scope.isEmpty ? "" : " · \(s.scope)")
                cols[2].addArrangedSubview(row(txt, color: Theme.yellow, actions: [("装备", .slot(i)), ("丢弃", .dropWeapon(i))]))
            } else {
                cols[2].addArrangedSubview(row("\(slotNames[i])：空", color: .lightGray, actions: []))
            }
        }
        if h.helmet > 0 { cols[2].addArrangedSubview(row("头盔(\(h.helmet)级) \(Int(h.helmetDur * 100))%", color: ItemKind.helmet(h.helmet).tint, actions: [("丢弃", .dropItem(.helmet(h.helmet)))])) }
        if h.vest > 0 { cols[2].addArrangedSubview(row("防弹衣(\(h.vest)级) \(Int(h.vestDur * 100))%", color: ItemKind.vest(h.vest).tint, actions: [("丢弃", .dropItem(.vest(h.vest)))])) }
        if h.bag > 0 { cols[2].addArrangedSubview(row("背包(\(h.bag)级)", color: ItemKind.bag(h.bag).tint, actions: [("丢弃", .dropItem(.bag(h.bag)))])) }
        setNeedsLayout()
    }

    @objc private func closeTap() { onClose?() }
}

final class ActionButton: UIButton {
    var command: UICommand?
}

// MARK: - Pause

final class PauseOverlay: UIView {
    var onResume: (() -> Void)?
    var onQuit: (() -> Void)?
    private let title = UILabel()
    private let resume = makeButton("继续游戏")
    private let quit = makeButton("退出到大厅", color: UIColor(white: 0.25, alpha: 1), textColor: .white)
    private let info = UILabel()

    init(sensitivity: Float) {
        super.init(frame: .zero)
        backgroundColor = UIColor(white: 0, alpha: 0.75)
        title.text = "暂停"
        title.font = Theme.font(30, .heavy)
        title.textColor = .white
        title.textAlignment = .center
        info.text = "灵敏度 \(String(format: "%.1f", sensitivity)) · 可在大厅中调整画质与灵敏度"
        info.font = Theme.font(13)
        info.textColor = .lightGray
        info.textAlignment = .center
        for v in [title, resume, quit, info] as [UIView] { addSubview(v) }
        resume.addTarget(self, action: #selector(r), for: .touchUpInside)
        quit.addTarget(self, action: #selector(q), for: .touchUpInside)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        let W = bounds.width, H = bounds.height
        title.frame = CGRect(x: 0, y: H * 0.22, width: W, height: 40)
        resume.frame = CGRect(x: W / 2 - 110, y: H * 0.42, width: 220, height: 48)
        quit.frame = CGRect(x: W / 2 - 110, y: H * 0.42 + 60, width: 220, height: 44)
        info.frame = CGRect(x: 0, y: H * 0.42 + 120, width: W, height: 20)
    }

    @objc private func r() { onResume?() }
    @objc private func q() { onQuit?() }
}

// MARK: - Result

final class ResultOverlay: UIView {
    var onExit: (() -> Void)?
    private let title = UILabel()
    private let rank = UILabel()
    private let detail = UILabel()
    private let exit = makeButton("返回大厅")

    init(won: Bool, rank r: Int, total: Int, kills: Int, killedBy: String) {
        super.init(frame: .zero)
        backgroundColor = UIColor(white: 0, alpha: 0.72)
        title.text = won ? "大吉大利，今晚吃鸡！" : "再接再厉！"
        title.font = UIFont.systemFont(ofSize: 38, weight: .black)
        title.textColor = won ? Theme.yellow : .white
        title.textAlignment = .center
        rank.text = "#\(max(1, r)) / \(total)"
        rank.font = UIFont.monospacedDigitSystemFont(ofSize: 54, weight: .black)
        rank.textColor = won ? Theme.yellow : .white
        rank.textAlignment = .center
        var d = "击杀 \(kills)"
        if !won && !killedBy.isEmpty { d += "    被 \(killedBy) 淘汰" }
        detail.text = d
        detail.font = Theme.font(17, .bold)
        detail.textColor = .white
        detail.textAlignment = .center
        for v in [title, rank, detail, exit] as [UIView] { addSubview(v) }
        exit.addTarget(self, action: #selector(e), for: .touchUpInside)
        alpha = 0
        UIView.animate(withDuration: 0.6) { self.alpha = 1 }
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        let W = bounds.width, H = bounds.height
        title.frame = CGRect(x: 0, y: H * 0.18, width: W, height: 50)
        rank.frame = CGRect(x: 0, y: H * 0.18 + 60, width: W, height: 66)
        detail.frame = CGRect(x: 0, y: H * 0.18 + 136, width: W, height: 26)
        exit.frame = CGRect(x: W / 2 - 110, y: H * 0.72, width: 220, height: 48)
    }

    @objc private func e() { onExit?() }
}
