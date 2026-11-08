import UIKit
import SceneKit
import simd

/// Drives the simulation from SceneKit's render loop.
final class GameLoop: NSObject, SCNSceneRendererDelegate {
    let world: GameWorld
    private var last: TimeInterval = 0
    var paused = false

    init(world: GameWorld) {
        self.world = world
    }

    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        let dt = last == 0 ? 1.0 / 60.0 : time - last
        last = time
        if paused { return }
        world.update(dt: Float(dt))
    }
}

/// Look area: every touch that isn't on a control rotates the camera.
final class HUDRootView: UIView {
    var onLook: ((CGPoint) -> Void)?
    private var lookTouches: [UITouch: CGPoint] = [:]

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        backgroundColor = .clear
    }
    required init?(coder: NSCoder) { fatalError() }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches { lookTouches[t] = t.location(in: self) }
    }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches {
            guard let last = lookTouches[t] else { continue }
            let p = t.location(in: self)
            onLook?(CGPoint(x: p.x - last.x, y: p.y - last.y))
            lookTouches[t] = p
        }
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches { lookTouches[t] = nil }
    }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches { lookTouches[t] = nil }
    }
}

final class GameViewController: UIViewController {
    let settings: GameSettings
    var onExit: (() -> Void)?
    private var scnView: SCNView!
    private var world: GameWorld?
    private var loop: GameLoop?
    private var link: CADisplayLink?
    private let loading = LoadingView()
    private let hudRoot = HUDRootView()

    // controls
    private let joystick = JoystickView()
    private let fireBtn = RoundButton(symbol: nil, text: " ", size: 84)
    private let fireLeft = RoundButton(symbol: nil, text: " ", size: 58)
    private let aimBtn = RoundButton(symbol: "scope", text: nil, size: 58)
    private let jumpBtn = RoundButton(symbol: "arrow.up.to.line", text: "跳", size: 50)
    private let crouchBtn = RoundButton(symbol: "figure.stand", text: "蹲", size: 50)
    private let proneBtn = RoundButton(symbol: "figure.fall", text: "趴", size: 50)
    private let reloadBtn = RoundButton(symbol: "arrow.triangle.2.circlepath", text: "换弹", size: 48)
    private let leanL = RoundButton(symbol: nil, text: "左探", size: 44)
    private let leanR = RoundButton(symbol: nil, text: "右探", size: 44)
    private let bagBtn = RoundButton(symbol: "bag.fill", text: "背包", size: 48)
    private let viewBtn = RoundButton(symbol: nil, text: "第三人称", size: 46)
    private let medBtn = RoundButton(symbol: "cross.case.fill", text: "0", size: 46)
    private let throwBtn = RoundButton(symbol: "circle.circle.fill", text: "0", size: 46)
    private let vehicleBtn = RoundButton(symbol: "car.fill", text: "驾驶", size: 56)
    private let bigBtn = RoundButton(symbol: nil, text: "跳伞", size: 92)
    private let pauseBtn = RoundButton(symbol: "gearshape.fill", text: nil, size: 36)
    private let fireMode = UIButton(type: .custom)
    private var slots: [SlotView] = []
    private let healthBack = UIView()
    private let healthFill = UIView()
    private let boostFill = UIView()
    private let armorLabel = UILabel()
    private let compass = CompassView()
    private let minimap = MinimapView()
    private let zoneLabel = UILabel()
    private let aliveLabel = UILabel()
    private let killsLabel = UILabel()
    private let feedStack = UIStackView()
    private let messageLabel = UILabel()
    private let crosshair = CrosshairView()
    private let scopeOverlay = ScopeOverlay()
    private let damage = DamageOverlay()
    private let pickupStack = UIStackView()
    private let progressLabel = UILabel()
    private let infoLabel = UILabel()
    private let medMenu = UIStackView()
    private var lastPickupIds: [Int] = []
    private var lastFeedCount = -1
    private var lastFeedTime: Float = -1
    private var hapticSeen = 0
    private var hapticHeavySeen = 0
    private let lightHaptic = UIImpactFeedbackGenerator(style: .light)
    private let heavyHaptic = UIImpactFeedbackGenerator(style: .heavy)
    private var aimOn = false
    private var lastHUD = HUDState()
    private var minimapT: CFTimeInterval = 0
    private var overlay: UIView?
    private var resultShown = false
    private var lastThrowSymbol = ""

    init(settings: GameSettings) {
        self.settings = settings
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }
    override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge { .all }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        scnView = SCNView(frame: view.bounds)
        scnView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        scnView.backgroundColor = .black
        scnView.isUserInteractionEnabled = false
        view.addSubview(scnView)
        hudRoot.frame = view.bounds
        hudRoot.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        hudRoot.isHidden = true
        view.addSubview(hudRoot)
        loading.frame = view.bounds
        loading.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        loading.mapName = settings.map.title
        view.addSubview(loading)
        buildHUD()
        startLoading()
    }

    // MARK: loading

    private func startLoading() {
        let s = settings
        let grassR: Float = s.quality == 2 ? 70 : (s.quality == 1 ? 55 : 38)
        let grassD: Float = s.quality == 2 ? 1.0 : (s.quality == 1 ? 0.8 : 0.55)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let data = MapGen.generate(kind: s.map, grassRadius: grassR, grassDensity: grassD) { p, text in
                DispatchQueue.main.async { self?.loading.set(progress: p, text: text) }
            }
            DispatchQueue.main.async { self?.loading.set(progress: 0.98, text: "部署玩家…") }
            let w = GameWorld(data: data, settings: s)
            DispatchQueue.main.async {
                self?.attach(world: w)
            }
        }
    }

    private func attach(world w: GameWorld) {
        world = w
        let ts = view.traitCollection.displayScale
        let screenScale: CGFloat = ts > 0 ? ts : 3.0
        let l = GameLoop(world: w)
        loop = l
        scnView.scene = w.scene
        scnView.pointOfView = w.cameraNode
        scnView.delegate = l
        switch settings.quality {
        case 2:
            scnView.antialiasingMode = .multisampling4X
            scnView.contentScaleFactor = min(screenScale, 3.0)
        case 1:
            scnView.antialiasingMode = .multisampling2X
            scnView.contentScaleFactor = min(screenScale, 2.0)
        default:
            scnView.antialiasingMode = .none
            scnView.contentScaleFactor = min(screenScale, 1.6)
        }
        scnView.preferredFramesPerSecond = 60
        scnView.rendersContinuously = true
        scnView.isJitteringEnabled = false
        scnView.isPlaying = true
        minimap.image = w.data.minimap
        hudRoot.isHidden = false
        UIView.animate(withDuration: 0.5, animations: { self.loading.alpha = 0 }, completion: { _ in self.loading.removeFromSuperview() })
        let dl = CADisplayLink(target: self, selector: #selector(tick))
        dl.preferredFramesPerSecond = 60
        dl.add(to: .main, forMode: .common)
        link = dl
        lightHaptic.prepare()
    }

    func exitGame() {
        link?.invalidate()
        link = nil
        loop?.paused = true
        world?.audio?.stop()
        scnView.isPlaying = false
        scnView.delegate = nil
        scnView.scene = nil
        world = nil
        onExit?()
    }

    // MARK: HUD build

    private func send(_ c: UICommand) {
        world?.submitInput { $0.commands.append(c) }
    }

    private func buildHUD() {
        joystick.onChange = { [weak self] v in
            self?.world?.submitInput { $0.move = V2(Float(v.x), Float(v.y)) }
        }
        hudRoot.addSubview(joystick)
        hudRoot.onLook = { [weak self] d in
            self?.world?.submitInput { $0.look += V2(Float(d.x), Float(d.y)) }
        }
        let glyph = FireButtonGlyph(frame: fireBtn.bounds.insetBy(dx: 12, dy: 12))
        fireBtn.addSubview(glyph)
        let glyph2 = FireButtonGlyph(frame: fireLeft.bounds.insetBy(dx: 9, dy: 9))
        fireLeft.addSubview(glyph2)
        for b in [fireBtn, fireLeft] {
            b.onPress = { [weak self] down in self?.world?.submitInput { $0.fire = down } }
            b.onDrag = { [weak self] d in self?.world?.submitInput { $0.look += V2(Float(d.x), Float(d.y)) } }
        }
        aimBtn.onTap = { [weak self] in
            guard let self = self else { return }
            self.aimOn.toggle()
            self.world?.submitInput { $0.aim = self.aimOn }
        }
        aimBtn.onDrag = { [weak self] d in self?.world?.submitInput { $0.look += V2(Float(d.x), Float(d.y)) } }
        jumpBtn.onTap = { [weak self] in self?.send(.jump) }
        crouchBtn.onTap = { [weak self] in self?.send(.crouch) }
        proneBtn.onTap = { [weak self] in self?.send(.prone) }
        reloadBtn.onTap = { [weak self] in self?.send(.reload) }
        leanL.onPress = { [weak self] down in self?.world?.submitInput { $0.leanL = down } }
        leanR.onPress = { [weak self] down in self?.world?.submitInput { $0.leanR = down } }
        bagBtn.onTap = { [weak self] in self?.showInventory() }
        viewBtn.onTap = { [weak self] in self?.send(.toggleView) }
        medBtn.onTap = { [weak self] in self?.toggleMedMenu() }
        throwBtn.onTap = { [weak self] in
            guard let self = self else { return }
            let h = self.lastHUD
            if h.activeSlot == 3 {
                let other: ThrowType = h.throwName == ThrowType.frag.name ? .smoke : .frag
                self.send(.throwSelect(other))
            } else {
                self.send(.slot(3))
            }
        }
        vehicleBtn.onTap = { [weak self] in self?.send(.vehicle) }
        bigBtn.onTap = { [weak self] in
            guard let self = self else { return }
            if self.lastHUD.phase == .plane { self.send(.jump) } else { self.send(.chute) }
        }
        pauseBtn.onTap = { [weak self] in self?.showPause() }
        bigBtn.label.font = Theme.font(22, .heavy)
        bigBtn.active = true
        fireMode.titleLabel?.font = Theme.font(11, .bold)
        fireMode.setTitleColor(.white, for: .normal)
        fireMode.backgroundColor = Theme.panel
        fireMode.layer.cornerRadius = 9
        fireMode.addTarget(self, action: #selector(fireModeTap), for: .touchUpInside)

        for b in [fireBtn, fireLeft, aimBtn, jumpBtn, crouchBtn, proneBtn, reloadBtn, leanL, leanR, bagBtn, viewBtn, medBtn, throwBtn, vehicleBtn, bigBtn, pauseBtn] {
            hudRoot.addSubview(b)
        }
        hudRoot.addSubview(fireMode)
        for i in 0..<3 {
            let s = SlotView()
            s.onTap = { [weak self] in self?.send(.slot(i)) }
            slots.append(s)
            hudRoot.addSubview(s)
        }
        healthBack.backgroundColor = UIColor(white: 0, alpha: 0.45)
        healthBack.layer.cornerRadius = 3
        healthBack.layer.borderWidth = 1
        healthBack.layer.borderColor = UIColor(white: 1, alpha: 0.3).cgColor
        healthFill.backgroundColor = .white
        healthFill.layer.cornerRadius = 2
        boostFill.backgroundColor = Theme.yellow
        hudRoot.addSubview(healthBack)
        healthBack.addSubview(healthFill)
        hudRoot.addSubview(boostFill)
        armorLabel.font = Theme.font(11, .bold)
        armorLabel.textColor = .white
        armorLabel.textAlignment = .right
        hudRoot.addSubview(armorLabel)
        hudRoot.addSubview(compass)
        let mapTap = UITapGestureRecognizer(target: self, action: #selector(openMap))
        minimap.addGestureRecognizer(mapTap)
        hudRoot.addSubview(minimap)
        for l in [zoneLabel, aliveLabel, killsLabel, messageLabel, progressLabel, infoLabel] {
            l.textColor = .white
            l.font = Theme.font(13, .bold)
            l.shadowColor = .black
            l.shadowOffset = CGSize(width: 0, height: 1)
            l.isUserInteractionEnabled = false
            hudRoot.addSubview(l)
        }
        aliveLabel.backgroundColor = Theme.panel
        killsLabel.backgroundColor = Theme.panel
        aliveLabel.textAlignment = .center
        killsLabel.textAlignment = .center
        aliveLabel.layer.cornerRadius = 4
        killsLabel.layer.cornerRadius = 4
        aliveLabel.clipsToBounds = true
        killsLabel.clipsToBounds = true
        zoneLabel.textAlignment = .right
        zoneLabel.font = Theme.font(12, .bold)
        messageLabel.textAlignment = .center
        messageLabel.font = Theme.font(17, .heavy)
        messageLabel.textColor = Theme.yellow
        progressLabel.textAlignment = .center
        infoLabel.textAlignment = .center
        infoLabel.font = Theme.font(15, .heavy)
        feedStack.axis = .vertical
        feedStack.spacing = 2
        feedStack.alignment = .leading
        feedStack.isUserInteractionEnabled = false
        hudRoot.addSubview(feedStack)
        pickupStack.axis = .vertical
        pickupStack.spacing = 3
        pickupStack.alignment = .fill
        hudRoot.addSubview(pickupStack)
        medMenu.axis = .horizontal
        medMenu.spacing = 6
        medMenu.isHidden = true
        hudRoot.addSubview(medMenu)
        crosshair.isUserInteractionEnabled = false
        scopeOverlay.isHidden = true
        hudRoot.insertSubview(scopeOverlay, at: 0)
        hudRoot.insertSubview(damage, at: 0)
        hudRoot.insertSubview(crosshair, at: 0)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        layoutHUD()
    }

    private func layoutHUD() {
        let b = hudRoot.bounds
        let W = b.width, H = b.height
        let ins = view.safeAreaInsets
        let L = max(ins.left, 16), R = max(ins.right, 16)
        let bottom = max(ins.bottom, 6)
        joystick.frame = CGRect(x: 0, y: H * 0.32, width: W * 0.42, height: H * 0.68)
        joystick.homeCenter = CGPoint(x: L + 105 - 0, y: joystick.bounds.height - 115 + 0)
        func place(_ v: UIView, _ x: CGFloat, _ y: CGFloat) { v.center = CGPoint(x: x, y: y) }
        place(fireBtn, W - R - 112, H - bottom - 118)
        place(fireLeft, L + 52, H * 0.46)
        place(aimBtn, W - R - 40, H * 0.43)
        place(jumpBtn, W - R - 34, H - bottom - 150)
        place(crouchBtn, W - R - 112, H - bottom - 32)
        place(proneBtn, W - R - 38, H - bottom - 62)
        place(reloadBtn, W - R - 200, H - bottom - 70)
        place(leanL, L + 130, H * 0.33)
        place(leanR, L + 186, H * 0.33)
        place(bagBtn, L + 30, H - bottom - 36)
        place(viewBtn, L + 84, H - bottom - 26)
        place(vehicleBtn, W - R - 190, H * 0.52)
        place(bigBtn, W - R - 140, H * 0.5)
        place(pauseBtn, W - R - 156, 26)
        let slotW: CGFloat = 112, slotH: CGFloat = 40
        let sy = H - bottom - 52
        for (i, s) in slots.enumerated() {
            s.frame = CGRect(x: W / 2 - slotW * 1.5 - 6 + CGFloat(i) * (slotW + 6), y: sy - slotH / 2, width: slotW, height: slotH)
        }
        place(medBtn, W / 2 - slotW * 1.5 - 40, sy)
        place(throwBtn, W / 2 + slotW * 1.5 + 40, sy)
        fireMode.frame = CGRect(x: W / 2 - 26, y: sy - slotH / 2 - 22, width: 52, height: 18)
        healthBack.frame = CGRect(x: W / 2 - 160, y: H - bottom - 20, width: 320, height: 9)
        boostFill.frame = CGRect(x: W / 2 - 160, y: H - bottom - 26, width: 0, height: 3)
        armorLabel.frame = CGRect(x: W / 2 - 330, y: H - bottom - 25, width: 160, height: 18)
        compass.frame = CGRect(x: W / 2 - 170, y: 4, width: 340, height: 36)
        minimap.frame = CGRect(x: W - R - 128, y: 6, width: 124, height: 124)
        zoneLabel.frame = CGRect(x: W - R - 300, y: 132, width: 296, height: 18)
        aliveLabel.frame = CGRect(x: L, y: 8, width: 76, height: 24)
        killsLabel.frame = CGRect(x: L + 82, y: 8, width: 76, height: 24)
        feedStack.frame = CGRect(x: L, y: 40, width: 320, height: 110)
        messageLabel.frame = CGRect(x: W / 2 - 250, y: H * 0.2, width: 500, height: 26)
        progressLabel.frame = CGRect(x: W / 2 - 150, y: H * 0.62, width: 300, height: 22)
        infoLabel.frame = CGRect(x: W / 2 - 200, y: H * 0.13, width: 400, height: 24)
        pickupStack.frame = CGRect(x: W - R - 340, y: H * 0.16, width: 180, height: 0)
        medMenu.frame = CGRect(x: W / 2 - slotW * 1.5 - 60, y: sy - 80, width: 260, height: 52)
        crosshair.frame = b
        scopeOverlay.frame = b
        damage.frame = b
        overlay?.frame = b
    }

    // MARK: per-frame HUD update

    @objc private func tick() {
        guard let w = world else { return }
        let h = w.readHUD()
        lastHUD = h
        apply(h)
    }

    private func apply(_ h: HUDState) {
        let ground = h.phase == .ground
        let air = h.phase == .plane || h.phase == .freefall || h.phase == .chute
        let inVeh = h.phase == .vehicle
        let dead = h.phase == .dead || h.phase == .won
        for v in [fireBtn, fireLeft, aimBtn, jumpBtn, crouchBtn, proneBtn, reloadBtn, leanL, leanR, medBtn, throwBtn] as [UIView] {
            v.isHidden = !ground
        }
        for s in slots { s.isHidden = air || dead }
        fireMode.isHidden = !ground || !h.canAuto
        bagBtn.isHidden = air || dead
        viewBtn.isHidden = !ground
        joystick.isHidden = dead
        vehicleBtn.isHidden = !(h.canEnterVehicle || inVeh)
        vehicleBtn.label.text = inVeh ? "下车" : "驾驶"
        bigBtn.isHidden = !(h.phase == .plane && h.canJump) && h.phase != .freefall
        bigBtn.label.text = h.phase == .plane ? "跳伞" : "开伞"
        crosshair.hideAll = !ground || h.scoped
        scopeOverlay.isHidden = !h.scoped
        scopeOverlay.scope = h.scope
        if aimOn && !h.aiming && h.phase == .ground && h.reloadProgress < 0 && h.healProgress < 0 && h.activeSlot < 0 {
            aimOn = false
            world?.submitInput { $0.aim = false }
        }
        aimBtn.active = h.aiming
        crouchBtn.active = h.stance == .crouch
        proneBtn.active = h.stance == .prone
        viewBtn.label.text = h.fpp ? "第一人称" : "第三人称"
        fireMode.setTitle(h.fireAuto ? "自动" : "单发", for: .normal)

        // health
        let hp = CGFloat(max(0, min(100, h.health)) / 100)
        healthFill.frame = CGRect(x: 1, y: 1, width: (healthBack.bounds.width - 2) * hp, height: healthBack.bounds.height - 2)
        healthFill.backgroundColor = h.health < 25 ? UIColor(red: 1, green: 0.25, blue: 0.2, alpha: 1) : (h.health < 50 ? UIColor(red: 1, green: 0.75, blue: 0.4, alpha: 1) : .white)
        var bf = boostFill.frame
        bf.size.width = 320 * CGFloat(h.boost / 100)
        boostFill.frame = bf
        var armor: [String] = []
        if h.helmet > 0 { armor.append("头\(h.helmet) \(Int(h.helmetDur * 100))%") }
        if h.vest > 0 { armor.append("甲\(h.vest) \(Int(h.vestDur * 100))%") }
        if h.bag > 0 { armor.append("包\(h.bag)") }
        armorLabel.text = armor.joined(separator: "  ")
        for i in 0..<3 {
            slots[i].set(h.slots[i], placeholder: i == 2 ? "手枪" : "主武器\(i + 1)")
            slots[i].isActive = h.activeSlot == i
        }
        medBtn.label.text = "\(h.meds.reduce(0, +))"
        throwBtn.label.text = "\(h.throwables.reduce(0, +))"
        throwBtn.active = h.activeSlot == 3
        let tsym = h.throwName == ThrowType.smoke.name ? "cloud.fill" : "circle.circle.fill"
        if tsym != lastThrowSymbol {
            lastThrowSymbol = tsym
            throwBtn.setSymbol(tsym)
        }

        compass.heading = CGFloat(h.heading)
        if let m = h.marker {
            let d = V3(m.x - h.pos.x, 0, m.y - h.pos.y)
            compass.markerBearing = CGFloat(headingDegrees(yaw: yawOf(d)))
        } else if compass.markerBearing != nil {
            compass.markerBearing = nil
        }
        let t = CACurrentMediaTime()
        if t - minimapT > 0.1 {
            minimapT = t
            minimap.state = h
            minimap.setNeedsDisplay()
        }
        aliveLabel.text = "存活 \(h.alive)"
        killsLabel.text = "击杀 \(h.kills)"
        if h.phase == .plane {
            zoneLabel.text = "飞机航线 · 选择时机跳伞"
        } else if h.outsideZone {
            let d = Int(simd_length(h.pos - h.nextCenter) - h.nextRadius)
            zoneLabel.text = "⚠︎ 安全区外 \(max(0, d))m · \(h.zoneText)"
            zoneLabel.textColor = UIColor(red: 0.5, green: 0.75, blue: 1, alpha: 1)
        } else {
            zoneLabel.text = h.zoneText
            zoneLabel.textColor = .white
        }
        // info
        switch h.phase {
        case .plane: infoLabel.text = h.canJump ? "点击「跳伞」离开飞机" : "飞机即将进入地图…"
        case .freefall: infoLabel.text = "高度 \(Int(h.altitude))m · 前推摇杆加速俯冲"
        case .chute: infoLabel.text = "降落伞 · 高度 \(Int(h.altitude))m"
        case .vehicle: infoLabel.text = "\(Int(h.vehicleSpeed)) km/h"
        default: infoLabel.text = h.inWater ? "游泳中" : ""
        }
        // message
        let msgAge = h.time - h.messageTime
        messageLabel.text = h.message
        messageLabel.alpha = msgAge < 3 ? 1 : max(0, 1 - CGFloat(msgAge - 3))
        // progress
        if h.reloadProgress >= 0 {
            progressLabel.text = "换弹中 \(Int(h.reloadProgress * 100))%"
        } else if h.healProgress >= 0 {
            progressLabel.text = "使用\(h.healName) \(Int(h.healProgress * 100))%"
        } else {
            progressLabel.text = ""
        }
        // crosshair
        let fovScale = CGFloat(50) / CGFloat(max(5, h.aiming ? 40 : 50))
        crosshair.spread = CGFloat(h.spread) * 320 * fovScale
        crosshair.aiming = h.aiming
        let hitAge = h.time - max(h.hitMarker, h.killMarker)
        crosshair.killHit = h.time - h.killMarker < 0.5
        crosshair.hitAlpha = hitAge < 0.35 ? CGFloat(1 - hitAge / 0.35) : 0
        // damage
        let dAge = h.time - h.damageTime
        damage.direction = CGFloat(h.damageDir)
        let lowHp: CGFloat = h.health < 30 && !dead ? 0.35 : 0
        damage.intensity = max(lowHp, dAge < 0.8 ? CGFloat(1 - dAge / 0.8) : 0)
        damage.outsideZone = h.outsideZone && !dead && !air
        // feed
        if h.feed.count != lastFeedCount || (h.feed.last?.time ?? -1) != lastFeedTime {
            lastFeedCount = h.feed.count
            lastFeedTime = h.feed.last?.time ?? -1
            for v in feedStack.arrangedSubviews { v.removeFromSuperview() }
            for f in h.feed.suffix(5) {
                let l = UILabel()
                l.text = " \(f.text) "
                l.font = Theme.font(12, .semibold)
                l.textColor = f.mine ? Theme.yellow : .white
                l.backgroundColor = UIColor(white: 0, alpha: 0.35)
                l.layer.cornerRadius = 3
                l.clipsToBounds = true
                feedStack.addArrangedSubview(l)
            }
        }
        // pickups
        let ids = h.pickups.map { $0.id }
        if ids != lastPickupIds || pickupStack.arrangedSubviews.count != ids.count {
            lastPickupIds = ids
            for v in pickupStack.arrangedSubviews { v.removeFromSuperview() }
            for p in h.pickups.prefix(6) {
                let b = UIButton(type: .custom)
                b.contentHorizontalAlignment = .left
                b.titleLabel?.font = Theme.font(13, .bold)
                b.setTitleColor(p.tint, for: .normal)
                b.setTitle("  " + p.name + (p.count > 1 ? " ×\(p.count)" : ""), for: .normal)
                b.setImage(UIImage(systemName: p.symbol), for: .normal)
                b.tintColor = p.tint
                b.backgroundColor = UIColor(white: 0, alpha: 0.5)
                b.layer.cornerRadius = 5
                b.layer.borderWidth = 1
                b.layer.borderColor = UIColor(white: 1, alpha: 0.2).cgColor
                b.tag = p.id
                b.addTarget(self, action: #selector(pickTap(_:)), for: .touchUpInside)
                b.heightAnchor.constraint(equalToConstant: 34).isActive = true
                pickupStack.addArrangedSubview(b)
            }
            var f = pickupStack.frame
            f.size.height = CGFloat(min(6, h.pickups.count)) * 37
            pickupStack.frame = f
        }
        pickupStack.isHidden = !ground
        // haptics
        if h.haptic != hapticSeen {
            hapticSeen = h.haptic
            lightHaptic.impactOccurred(intensity: 0.6)
        }
        if h.hapticHeavy != hapticHeavySeen {
            hapticHeavySeen = h.hapticHeavy
            heavyHaptic.impactOccurred()
        }
        if dead && !resultShown {
            resultShown = true
            DispatchQueue.main.asyncAfter(deadline: .now() + (h.phase == .won ? 1.0 : 2.2)) { [weak self] in
                self?.showResult()
            }
        }
    }

    @objc private func pickTap(_ b: UIButton) { send(.pick(b.tag)) }

    @objc private func fireModeTap() { send(.fireMode) }

    // MARK: med menu

    private func toggleMedMenu() {
        if !medMenu.isHidden { medMenu.isHidden = true; return }
        for v in medMenu.arrangedSubviews { v.removeFromSuperview() }
        let h = lastHUD
        for m in MedType.allCases {
            let b = UIButton(type: .custom)
            b.titleLabel?.numberOfLines = 2
            b.titleLabel?.textAlignment = .center
            b.titleLabel?.font = Theme.font(11, .bold)
            b.setTitle("\(m.name)\n×\(h.meds[m.rawValue])", for: .normal)
            b.setTitleColor(h.meds[m.rawValue] > 0 ? .white : .gray, for: .normal)
            b.backgroundColor = UIColor(white: 0, alpha: 0.6)
            b.layer.cornerRadius = 6
            b.tag = m.rawValue
            b.widthAnchor.constraint(equalToConstant: 60).isActive = true
            b.addTarget(self, action: #selector(medTap(_:)), for: .touchUpInside)
            medMenu.addArrangedSubview(b)
        }
        medMenu.isHidden = false
    }

    @objc private func medTap(_ b: UIButton) {
        if let m = MedType(rawValue: b.tag) { send(.med(m)) }
        medMenu.isHidden = true
    }

    // MARK: overlays

    private func present(_ v: UIView) {
        overlay?.removeFromSuperview()
        v.frame = view.bounds
        view.addSubview(v)
        overlay = v
    }

    private func dismissOverlay() {
        overlay?.removeFromSuperview()
        overlay = nil
    }

    @objc private func openMap() {
        guard let w = world else { return }
        let m = MapOverlay(image: w.data.minimap, state: lastHUD, places: w.data.places)
        m.onClose = { [weak self] in self?.dismissOverlay() }
        m.onMarker = { [weak self] p in self?.send(.mapMarker(p)) }
        present(m)
    }

    private func showInventory() {
        guard let w = world else { return }
        let inv = InventoryOverlay(world: w)
        inv.onClose = { [weak self] in self?.dismissOverlay() }
        inv.onCommand = { [weak self] c in self?.send(c) }
        present(inv)
    }

    private func showPause() {
        loop?.paused = true
        let p = PauseOverlay(sensitivity: settings.sensitivity)
        p.onResume = { [weak self] in
            self?.loop?.paused = false
            self?.dismissOverlay()
        }
        p.onQuit = { [weak self] in self?.exitGame() }
        present(p)
    }

    private func showResult() {
        let h = lastHUD
        let r = ResultOverlay(won: h.phase == .won, rank: h.rank, total: (world?.actors.count ?? 50), kills: h.kills, killedBy: h.killedBy)
        r.onExit = { [weak self] in self?.exitGame() }
        present(r)
    }
}

/// Loading screen.
final class LoadingView: UIView {
    private let title = UILabel()
    private let sub = UILabel()
    private let bar = UIView()
    private let fill = UIView()
    private let status = UILabel()
    private let tip = UILabel()
    var mapName = "" { didSet { sub.text = "地图：\(mapName)" } }
    private var progress: CGFloat = 0
    private let tips = [
        "提示：前推摇杆到顶可以自动冲刺",
        "提示：拖动开火键也可以转动视角",
        "提示：蹲下和趴下能减少后坐力与被发现的几率",
        "提示：注意蓝色毒圈，及时进入白圈",
        "提示：高倍镜适合搭配 Kar98k 远距离狙击",
        "提示：烟雾弹可以阻挡敌人视线",
    ]

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor(red: 0.05, green: 0.07, blue: 0.09, alpha: 1)
        title.text = "枪战01"
        title.font = UIFont.systemFont(ofSize: 44, weight: .black)
        title.textColor = Theme.yellow
        title.textAlignment = .center
        sub.font = Theme.font(16)
        sub.textColor = .white
        sub.textAlignment = .center
        bar.backgroundColor = UIColor(white: 1, alpha: 0.15)
        bar.layer.cornerRadius = 4
        fill.backgroundColor = Theme.yellow
        fill.layer.cornerRadius = 4
        status.font = Theme.font(13)
        status.textColor = UIColor(white: 1, alpha: 0.8)
        status.textAlignment = .center
        tip.font = Theme.font(13)
        tip.textColor = UIColor(white: 1, alpha: 0.6)
        tip.textAlignment = .center
        tip.text = tips.randomElement()
        for v in [title, sub, bar, status, tip] { addSubview(v) }
        bar.addSubview(fill)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        let W = bounds.width, H = bounds.height
        title.frame = CGRect(x: 0, y: H * 0.22, width: W, height: 56)
        sub.frame = CGRect(x: 0, y: H * 0.22 + 60, width: W, height: 24)
        bar.frame = CGRect(x: W * 0.2, y: H * 0.62, width: W * 0.6, height: 8)
        fill.frame = CGRect(x: 0, y: 0, width: bar.bounds.width * progress, height: 8)
        status.frame = CGRect(x: 0, y: H * 0.62 + 16, width: W, height: 20)
        tip.frame = CGRect(x: 0, y: H * 0.85, width: W, height: 20)
    }

    func set(progress p: Float, text: String) {
        progress = CGFloat(max(progress == 0 ? 0 : Float(progress), p))
        status.text = "\(text)  \(Int(p * 100))%"
        setNeedsLayout()
    }
}
