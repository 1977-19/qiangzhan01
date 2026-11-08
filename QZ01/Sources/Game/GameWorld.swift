import SceneKit
import UIKit

enum UICommand {
    case pick(Int)
    case slot(Int)
    case med(MedType)
    case throwSelect(ThrowType)
    case dropItem(ItemKind)
    case dropWeapon(Int)
    case fireMode
    case vehicle
    case jump
    case chute
    case crouch
    case prone
    case reload
    case toggleView
    case cancel
    case mapMarker(V2?)
}

struct InputState {
    var move = V2(0, 0)
    var look = V2(0, 0)
    var fire = false
    var aim = false
    var leanL = false
    var leanR = false
    var commands: [UICommand] = []
}

struct SlotInfo {
    var name: String = ""
    var mag: Int = 0
    var reserve: Int = 0
    var scope: String = ""
    var present = false
}

struct PickupInfo {
    var id: Int
    var name: String
    var count: Int
    var tint: UIColor
    var symbol: String
}

struct FeedLine {
    var text: String
    var time: Float
    var mine: Bool
}

enum GamePhase {
    case plane, freefall, chute, ground, vehicle, dead, won
}

struct HUDState {
    var phase: GamePhase = .plane
    var health: Float = 100
    var boost: Float = 0
    var alive = 50
    var kills = 0
    var heading: Float = 0
    var pos = V2(0, 0)
    var yaw: Float = 0
    var zoneCenter = V2(0, 0)
    var zoneRadius: Float = 1200
    var nextCenter = V2(0, 0)
    var nextRadius: Float = 500
    var zoneText = ""
    var outsideZone = false
    var slots: [SlotInfo] = [SlotInfo(), SlotInfo(), SlotInfo()]
    var activeSlot = -1
    var throwCount = 0
    var throwName = ""
    var fireAuto = true
    var canAuto = false
    var aiming = false
    var scope: ScopeType = .iron
    var scoped = false
    var reloadProgress: Float = -1
    var healProgress: Float = -1
    var healName = ""
    var pickups: [PickupInfo] = []
    var canEnterVehicle = false
    var vehicleSpeed: Float = 0
    var canJump = false
    var altitude: Float = 0
    var feed: [FeedLine] = []
    var hitMarker: Float = -10
    var killMarker: Float = -10
    var damageTime: Float = -10
    var damageDir: Float = 0
    var message = ""
    var messageTime: Float = -10
    var helmet = 0
    var vest = 0
    var bag = 0
    var helmetDur: Float = 0
    var vestDur: Float = 0
    var meds = [0, 0, 0, 0]
    var throws = [0, 0]
    var ammo = [0, 0, 0, 0]
    var scopes = [0, 0, 0, 0, 0]
    var spread: Float = 0
    var time: Float = 0
    var rank = 0
    var killedBy = ""
    var planeStart = V2(0, 0)
    var planeEnd = V2(0, 0)
    var planePos = V2(0, 0)
    var stance: Stance = .stand
    var fpp = false
    var marker: V2?
    var haptic = 0
    var hapticHeavy = 0
    var inWater = false
}

/// The whole simulation. Runs on the SceneKit render thread.
final class GameWorld {
    let settings: GameSettings
    let data: WorldData
    let assets: Assets
    let terrain: Terrain
    let col: CollisionWorld
    let scene = SCNScene()
    let cameraNode = SCNNode()
    let camera = SCNCamera()
    let sun = SCNNode()
    let actorsRoot = SCNNode()
    let lootRoot = SCNNode()
    let vehicleRoot = SCNNode()
    let viewModel = SCNNode()
    let viewGun = SCNNode()
    var viewGunKey = -1
    let fx: Effects
    let audio: AudioSys?
    var actors: [Actor] = []
    var player: Actor!
    var vehicles: [Vehicle] = []
    var plan: FlightPlan
    var zone: Zone
    var rng = RNG(UInt64(Date().timeIntervalSince1970 * 1000) & 0xFFFFFFF)
    var now: Float = 0
    var aliveCount = 0
    var gameOver = false
    var won = false

    // loot
    var loot: [Int: LootItem] = [:]
    var lootGrid: [Int: [Int]] = [:]
    var lootNodes: [Int: SCNNode] = [:]
    var nextLootId = 1
    var crates: [Int: (pos: V3, node: SCNNode)] = [:]
    var lootScanT: Float = 0

    // combat
    struct Bullet {
        var pos: V3
        var vel: V3
        var owner: Int
        var damage: Float
        var weapon: WeaponType
        var age: Float
        var tracer: Bool
        var falloff: Float
    }
    struct Grenade {
        var pos: V3
        var vel: V3
        var type: ThrowType
        var fuse: Float
        var owner: Int
        var node: SCNNode
    }
    var bullets: [Bullet] = []
    var grenades: [Grenade] = []
    var shots: [(pos: V3, time: Float, owner: Int)] = []

    // input / hud
    let lock = Lock()
    private var pendingInput = InputState()
    var input = InputState()
    private var hudShared = HUDState()
    var hud = HUDState()
    var feed: [FeedLine] = []

    // player / camera state
    var fpp: Bool
    var aimBlend: Float = 0
    var camPos = V3(0, 0, 0)
    var camShake: Float = 0
    var recoilKick: Float = 0
    var viewKick: Float = 0
    var lastFootstep: Float = 0
    var zoneTickT: Float = 0
    var grassT: Float = 0
    var lodT: Float = 0
    var marker: V2?
    var autoPickT: Float = 0
    var spectate: Actor?
    var baseFov: Float = 50

    init(data: WorldData, settings: GameSettings) {
        self.data = data
        self.settings = settings
        assets = data.assets
        terrain = data.terrain
        col = data.col
        fpp = settings.fpp
        fx = Effects(assets: data.assets)
        let a = AudioSys()
        audio = a.running ? a : nil
        var r = RNG(UInt64(Date().timeIntervalSince1970) & 0xFFFFFF)
        plan = FlightPlan(rng: &r, assets: data.assets)
        zone = Zone(rng: &r, terrain: data.terrain, assets: data.assets)
        rng = r
        setupScene()
        spawnLoot()
        spawnVehicles()
        spawnActors()
    }

    // MARK: setup

    func setupScene() {
        let q = settings.quality
        scene.background.contents = assets.skyFaces
        scene.background.intensity = 1.0
        scene.lightingEnvironment.contents = assets.skyFaces
        scene.lightingEnvironment.intensity = 1.35
        scene.fogColor = assets.fogColor
        scene.fogStartDistance = q == 0 ? 120 : 170
        scene.fogEndDistance = q == 0 ? 650 : (q == 1 ? 850 : 1050)
        scene.fogDensityExponent = 1.4

        let l = SCNLight()
        l.type = .directional
        l.intensity = 2100
        l.color = assets.sunColor
        l.castsShadow = true
        l.shadowMode = .forward
        l.shadowSampleCount = q == 2 ? 8 : 4
        l.shadowRadius = 2.0
        l.shadowMapSize = q == 2 ? CGSize(width: 4096, height: 4096) : (q == 1 ? CGSize(width: 3072, height: 3072) : CGSize(width: 2048, height: 2048))
        l.shadowCascadeCount = q == 2 ? 4 : (q == 1 ? 3 : 2)
        l.shadowCascadeSplittingFactor = 0.2
        l.maximumShadowDistance = q == 2 ? 240 : (q == 1 ? 170 : 110)
        l.automaticallyAdjustsShadowProjection = true
        l.shadowColor = UIColor(white: 0, alpha: 0.6)
        l.shadowBias = 1.2
        sun.light = l
        sun.simdOrientation = simd_quatf(from: V3(0, 0, -1), to: -assets.sunDir)
        scene.rootNode.addChildNode(sun)

        camera.zNear = 0.06
        camera.zFar = 2600
        camera.fieldOfView = 50
        camera.projectionDirection = .vertical
        camera.wantsHDR = true
        camera.wantsExposureAdaptation = true
        camera.exposureAdaptationBrighteningSpeedFactor = 0.5
        camera.exposureAdaptationDarkeningSpeedFactor = 0.5
        camera.averageGray = 0.2
        camera.minimumExposure = -1.5
        camera.maximumExposure = 1.5
        camera.exposureOffset = 0.1
        camera.bloomIntensity = q == 0 ? 0 : 0.55
        camera.bloomThreshold = 0.85
        camera.bloomBlurRadius = 8
        camera.vignettingIntensity = 0.35
        camera.vignettingPower = 0.6
        camera.saturation = 1.1
        camera.contrast = 0.08
        if q >= 1 {
            camera.screenSpaceAmbientOcclusionIntensity = q == 2 ? 1.1 : 0.8
            camera.screenSpaceAmbientOcclusionRadius = 1.3
            camera.screenSpaceAmbientOcclusionBias = 0.04
            camera.screenSpaceAmbientOcclusionDepthThreshold = 0.25
            camera.screenSpaceAmbientOcclusionNormalThreshold = 0.3
        }
        camera.motionBlurIntensity = 0
        cameraNode.camera = camera
        scene.rootNode.addChildNode(cameraNode)

        // first person view model
        viewModel.addChildNode(viewGun)
        cameraNode.addChildNode(viewModel)
        viewModel.isHidden = true
        let armMb = MeshBuilder()
        let m = Mt.soldier0.rawValue
        armMb.tube(m, from: V3(0.12, -0.25, 0.25), to: V3(0.03, -0.06, 0.02), r0: 0.05, r1: 0.045, seg: 8, uv: SoldierUV.camo)
        armMb.box(m, min: V3(-0.03, -0.12, -0.04), max: V3(0.04, -0.03, 0.06), uv: SoldierUV.black)
        armMb.tube(m, from: V3(-0.2, -0.28, 0.1), to: V3(-0.02, -0.05, -0.32), r0: 0.05, r1: 0.045, seg: 8, uv: SoldierUV.camo)
        armMb.box(m, min: V3(-0.05, -0.08, -0.4), max: V3(0.03, 0.0, -0.3), uv: SoldierUV.black)
        let arms = SCNNode(geometry: armMb.build(materials: { self.assets.mat($0) }))
        viewModel.addChildNode(arms)
        viewModel.castsShadow = false
        viewGun.castsShadow = false
        arms.castsShadow = false

        scene.rootNode.addChildNode(data.terrainNode)
        scene.rootNode.addChildNode(data.staticNode)
        scene.rootNode.addChildNode(data.waterNode)
        scene.rootNode.addChildNode(data.grass.root)
        scene.rootNode.addChildNode(actorsRoot)
        scene.rootNode.addChildNode(lootRoot)
        scene.rootNode.addChildNode(vehicleRoot)
        scene.rootNode.addChildNode(fx.root)
        scene.rootNode.addChildNode(zone.node)
        scene.rootNode.addChildNode(plan.node)
    }

    static let botNames: [String] = [
        "孤狼007", "Kaze_88", "夜行者", "老六本六", "ShadowFox", "雪豹突击", "黑桃A", "Rookie_Z", "一枪一个", "苟到决赛圈",
        "Viper", "北风", "沙漠之鹰", "BlueSky", "落地成盒", "Ghost_X", "铁血战士", "满级萌新", "Frost", "幽灵行动",
        "猎鹰", "Sniper_King", "冷锋", "Mr.Lucky", "暴走萝卜", "Night_Owl", "钢铁侠", "Maverick", "风之子", "老司机",
        "Ace_47", "神枪手", "Tango", "疾风", "ZeroCool", "无敌小可爱", "Raptor", "秋名山", "Echo", "刺客信条",
        "Bullseye", "龙卷风", "Phantom", "大漠孤烟", "Bravo", "天狼星", "Hunter", "雷霆", "Falcon", "影子",
        "Wolfpack", "红牛", "Delta", "江湖小虾", "Nova", "黑鹰坠落",
    ]

    func spawnActors() {
        var names = GameWorld.botNames
        for i in stride(from: names.count - 1, to: 0, by: -1) { names.swapAt(i, rng.i(i + 1)) }
        let total = 1 + settings.bots
        for i in 0..<total {
            let isPlayer = i == 0
            let variant = isPlayer ? (data.kind == .snow ? 2 : 0) : rng.i(5)
            let rig = SoldierRig(geos: Models.rigGeos(variant: variant, assets: assets), assets: assets)
            let name = isPlayer ? "我" : names[(i - 1) % names.count]
            let a = Actor(id: i, name: name, isPlayer: isPlayer, rig: rig, pos: plan.position)
            a.state = .plane
            a.rig.root.isHidden = true
            actorsRoot.addChildNode(rig.root)
            if !isPlayer {
                let b = BotBrain(skill: rng.r(0.25, 0.92))
                b.chooseDrop(world: self)
                a.bot = b
            }
            actors.append(a)
        }
        player = actors[0]
        aliveCount = actors.count
        hud.alive = aliveCount
    }

    func spawnVehicles() {
        for (i, s) in data.vehicleSpawns.enumerated() {
            let bike = rng.chance(0.3)
            let v = Vehicle(id: i, bike: bike, assets: assets, pos: s.p + V3(0, 0.3, 0), yaw: s.yaw, paint: bike ? 2 : rng.i(2))
            vehicles.append(v)
            vehicleRoot.addChildNode(v.node)
            _ = v.update(dt: 0.016, throttle: 0, steerIn: 0, col: col, terrain: terrain)
        }
    }

    // MARK: input / hud exchange (called from main thread)

    func submitInput(_ mutate: (inout InputState) -> Void) {
        lock.run { mutate(&pendingInput) }
    }

    func readHUD() -> HUDState {
        return lock.run { hudShared }
    }

    private func takeInput() {
        lock.run {
            input = pendingInput
            pendingInput.look = V2(0, 0)
            pendingInput.commands.removeAll()
        }
    }

    private func publishHUD() {
        let h = hud
        lock.run { hudShared = h }
    }

    func message(_ text: String) {
        hud.message = text
        hud.messageTime = now
    }

    func addFeed(_ text: String, mine: Bool) {
        feed.append(FeedLine(text: text, time: now, mine: mine))
        if feed.count > 6 { feed.removeFirst(feed.count - 6) }
    }

    // MARK: main loop

    func update(dt rawDt: Float) {
        let dt = min(max(rawDt, 0.001), 1.0 / 20.0)
        now += dt
        takeInput()

        // plane
        if !plan.done || actors.contains(where: { $0.state == .plane }) {
            plan.t += dt
            plan.node.simdPosition = plan.position
            plan.node.isHidden = plan.done
            if plan.done {
                for a in actors where a.state == .plane { jumpFromPlane(a) }
            }
        }

        for c in input.commands { handle(c) }

        updatePlayerControl(dt: dt)
        for a in actors where !a.isPlayer && a.alive {
            a.bot?.update(actor: a, world: self, dt: dt)
        }
        for a in actors where a.alive {
            updateActorTimers(a, dt: dt)
        }
        updateVehicles(dt: dt)
        updateBullets(dt: dt)
        updateGrenades(dt: dt)

        if let msg = zone.update(dt: dt, rng: &rng, terrain: terrain) { message(msg) }
        zoneTickT += dt
        if zoneTickT >= 1 {
            zoneTickT = 0
            for a in actors where a.alive && a.state != .plane && zone.outside(a.pos) {
                applyDamage(to: a, amount: zone.dps, part: -1, from: nil, weaponName: "毒圈", dir: V3(0, 0, 0))
            }
            col.pruneSmokes(now: now)
            shots.removeAll { now - $0.time > 1.5 }
            farCombat()
        }

        fx.update(dt: dt, time: now)
        lootScanT += dt
        if lootScanT > 0.25 {
            lootScanT = 0
            updateLootVisibility()
        }
        updateCamera(dt: dt)
        grassT += dt
        if grassT > 0.15 {
            grassT = 0
            data.grass.update(camera: cameraNode.simdPosition)
        }
        lodT += dt
        if lodT > 0.2 {
            lodT = 0
            updateActorLOD()
        }
        for a in actors { updateRig(a, dt: dt) }
        if let w = data.waterNode.geometry?.firstMaterial {
            let o = now * 0.012
            let rep = Float(terrain.kind == .island ? 9000 : 1700) / 28
            w.normal.contentsTransform = SCNMatrix4Mult(SCNMatrix4MakeScale(rep, rep, 1), SCNMatrix4MakeTranslation(o, o * 0.6, 0))
        }
        updateAudio()
        buildHUD()
        publishHUD()
    }

    func updateActorLOD() {
        let c = cameraNode.simdPosition
        for a in actors {
            let d = vlen(a.pos - c)
            a.far = d > 380
            let visible = a.state != .plane && d < 650 && !(a.isPlayer && (fpp || hud.scoped) && a.state == .ground)
            a.nodeVisible = visible
            a.rig.root.isHidden = !visible
        }
    }

    func updateRig(_ a: Actor, dt: Float) {
        if !a.nodeVisible && a.alive { return }
        var p = PoseInput()
        p.speed = a.moveSpeed
        p.forwardSpeed = a.forwardSpeed
        p.stance = a.stance
        p.pitch = a.pitch
        p.aiming = a.aiming
        p.reloading = a.reloading
        p.healing = a.healing != nil
        p.lean = a.lean
        p.hasGun = a.weapon != nil
        p.pistol = a.slot == 2
        p.throwing = now < a.throwAnimUntil
        switch a.state {
        case .plane: p.mode = .hidden
        case .freefall: p.mode = .freefall
        case .chute: p.mode = .chute
        case .ground: p.mode = .ground
        case .vehicle: p.mode = .drive
        case .dead: p.mode = .dead
        }
        a.rig.setGun(a.weapon, assets: assets)
        a.rig.update(dt: dt, p)
        a.rig.root.simdPosition = a.pos
        if a.state == .vehicle, let v = a.vehicle {
            a.rig.root.simdOrientation = v.orientation()
        } else {
            a.rig.root.simdOrientation = simd_quatf(angle: a.yaw, axis: V3(0, 1, 0))
        }
    }

    func updateActorTimers(_ a: Actor, dt: Float) {
        if a.reloading && now >= a.reloadEnd {
            a.reloading = false
            if let w = a.weapon {
                let need = w.stats.mag - w.mag
                let have = a.inv.ammo[w.stats.ammo.rawValue]
                let take = min(need, have)
                w.mag += take
                a.inv.ammo[w.stats.ammo.rawValue] -= take
            }
        }
        if let m = a.healing, now >= a.healEnd {
            a.healing = nil
            if a.inv.meds[m.rawValue] > 0 {
                a.inv.meds[m.rawValue] -= 1
                switch m {
                case .bandage: a.health = min(75, a.health + 12)
                case .firstAid: a.health = max(a.health, 75)
                case .medkit: a.health = 100
                case .drink: a.boost = min(100, a.boost + 45)
                }
                if a.isPlayer { audio?.playUI("heal", volume: 0.6) }
            }
        }
        if a.boost > 0 {
            a.boost = max(0, a.boost - dt * 1.6)
            a.health = min(100, a.health + dt * 0.9)
        }
    }

    // MARK: commands

    func handle(_ c: UICommand) {
        let p = player!
        switch c {
        case .pick(let id):
            if let it = loot[id], !it.taken, distXZ(it.pos, p.pos) < 3.2 { pick(p, it, explicit: true) }
        case .slot(let s):
            switchSlot(p, s)
        case .med(let m):
            startHeal(p, m)
        case .throwSelect(let t):
            p.throwType = t
            if p.inv.throws[t.rawValue] > 0 { switchSlot(p, 3) }
        case .dropItem(let k):
            drop(p, k)
        case .dropWeapon(let s):
            dropWeapon(p, slot: s)
        case .fireMode:
            if let w = p.weapon, w.stats.autoCapable { w.auto.toggle(); message(w.auto ? "全自动" : "单发") }
        case .vehicle:
            if p.state == .vehicle { exitVehicle(p) } else if let v = nearestVehicle(p) { enterVehicle(p, v) }
        case .jump:
            if p.state == .plane { if plan.overMap { jumpFromPlane(p) } else { message("飞机还未进入地图") } }
            else if p.state == .ground && p.onGround {
                if p.stance != .stand { p.stance = .stand } else { p.vel.y = 4.6; p.onGround = false }
            }
        case .chute:
            if p.state == .freefall { openChute(p) }
        case .crouch:
            if p.state == .ground { p.stance = p.stance == .crouch ? .stand : .crouch }
        case .prone:
            if p.state == .ground && !p.inWater { p.stance = p.stance == .prone ? .stand : .prone }
        case .reload:
            startReload(p)
        case .toggleView:
            fpp.toggle()
        case .cancel:
            p.cancelActions()
        case .mapMarker(let m):
            marker = m
        }
    }

    func switchSlot(_ a: Actor, _ s: Int) {
        if a.state != .ground { return }
        if s == 3 {
            if a.inv.throws[a.throwType.rawValue] == 0 {
                if a.inv.throws[0] > 0 { a.throwType = .frag } else if a.inv.throws[1] > 0 { a.throwType = .smoke } else { return }
            }
            a.slot = a.slot == 3 ? -1 : 3
        } else if a.inv.weapon(slot: s) != nil {
            a.slot = a.slot == s ? -1 : s
        }
        a.reloading = false
        a.aiming = false
    }

    func startReload(_ a: Actor) {
        guard let w = a.weapon, !a.reloading, w.mag < w.stats.mag, a.inv.ammo[w.stats.ammo.rawValue] > 0 else { return }
        a.reloading = true
        a.reloadStart = now
        a.reloadEnd = now + w.stats.reload * (w.mag == 0 ? 1.15 : 1)
        a.healing = nil
        if a.nodeVisible || a.isPlayer { audio?.play("reload", at: a.eye, volume: a.isPlayer ? 0.7 : 0.5) }
    }

    func startHeal(_ a: Actor, _ m: MedType) {
        guard a.inv.meds[m.rawValue] > 0, a.healing == nil, a.state == .ground else { return }
        switch m {
        case .bandage, .firstAid:
            if a.health >= 75 { if a.isPlayer { message("生命值高于75，无法使用") }; return }
        case .medkit:
            if a.health >= 100 { if a.isPlayer { message("生命值已满") }; return }
        case .drink: break
        }
        a.healing = m
        a.healStart = now
        a.healEnd = now + m.useTime
        a.reloading = false
        a.aiming = false
    }

    // MARK: plane / parachute

    func jumpFromPlane(_ a: Actor) {
        guard a.state == .plane else { return }
        a.state = .freefall
        a.pos = plan.position + V3(0, -4, 0)
        a.vel = plan.dir * 30 + V3(0, -5, 0)
        a.yaw = yawOf(plan.dir)
        a.rig.root.isHidden = false
        if a.isPlayer { message("跳伞成功！滑动摇杆控制方向") }
    }

    func openChute(_ a: Actor) {
        if a.state == .freefall {
            a.state = .chute
            a.vel.y = max(a.vel.y, -12)
        }
    }

    func updateAirborne(_ a: Actor, dt: Float, steer: V2) {
        let g = terrain.height(a.pos.x, a.pos.z)
        let agl = a.pos.y - max(g, terrain.waterLevel)
        let f = flatForward(a.yaw), r = flatRight(a.yaw)
        if a.state == .freefall {
            let target = (f * steer.y + r * steer.x) * 24
            a.vel.x = approachf(a.vel.x, target.x, dt * 14)
            a.vel.z = approachf(a.vel.z, target.z, dt * 14)
            let dive = max(0, steer.y) * 12
            a.vel.y = approachf(a.vel.y, -(48 + dive), dt * 20)
            if agl < 110 { openChute(a) }
        } else {
            let target = (f * max(0.3, steer.y + 0.4) + r * steer.x * 0.8) * 11
            a.vel.x = approachf(a.vel.x, target.x, dt * 5)
            a.vel.z = approachf(a.vel.z, target.z, dt * 5)
            a.vel.y = approachf(a.vel.y, steer.y < -0.5 ? -4.2 : -7.2, dt * 6)
        }
        a.pos += a.vel * dt
        a.pos.x = clampf(a.pos.x, -790, 790)
        a.pos.z = clampf(a.pos.z, -790, 790)
        let ground = col.ground(a.pos.x, a.pos.z, feetY: a.pos.y, step: 0.5)
        let wl = terrain.waterLevel
        if a.pos.y <= max(ground, wl - 1.2) + 0.05 {
            a.pos.y = max(ground, wl - 1.25)
            a.state = .ground
            a.vel = V3(0, 0, 0)
            a.stance = .stand
            a.onGround = true
            if a.isPlayer { message("") }
        }
        a.moveSpeed = 0
    }
}
