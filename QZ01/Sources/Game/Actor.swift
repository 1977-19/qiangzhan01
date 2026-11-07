import SceneKit
import simd

enum ActorState {
    case plane, freefall, chute, ground, vehicle, dead
}

struct GameSettings {
    var map: MapKind = .island
    var quality: Int = 2          // 0 流畅, 1 高清, 2 极致
    var sensitivity: Float = 1.0
    var fpp = false
    var bots = 49
}

/// A soldier (player or bot).
final class Actor {
    let id: Int
    let name: String
    let isPlayer: Bool
    let rig: SoldierRig
    var pos: V3
    var vel = V3(0, 0, 0)
    var yaw: Float = 0
    var pitch: Float = 0
    var stance: Stance = .stand
    var state: ActorState = .plane
    var health: Float = 100
    var boost: Float = 0
    let inv = Inventory()
    var slot: Int = -1
    var throwType: ThrowType = .frag
    var onGround = false
    var vehicle: Vehicle?
    var kills = 0
    var lastShot: Float = -10
    var reloading = false
    var reloadEnd: Float = 0
    var reloadStart: Float = 0
    var healing: MedType?
    var healStart: Float = 0
    var healEnd: Float = 0
    var aiming = false
    var lean: Float = 0
    var moveSpeed: Float = 0
    var forwardSpeed: Float = 0
    var stepAcc: Float = 0
    var lastHurtBy = -1
    var lastHurtTime: Float = -100
    var lastHurtFrom = V3(0, 0, 0)
    var deathTime: Float = 0
    var rank = 0
    var bot: BotBrain?
    var nodeVisible = true
    var far = false
    var lastThrow: Float = -10
    var throwAnimUntil: Float = 0
    var lastBolt: Float = -10
    var fallStartY: Float = 0
    var inWater = false
    var killerName = ""
    var killerWeapon = ""

    var weapon: WeaponInst? { return inv.weapon(slot: slot) }
    var alive: Bool { return state != .dead }

    var eyeHeight: Float {
        switch stance {
        case .stand: return 1.62
        case .crouch: return 1.08
        case .prone: return 0.38
        }
    }
    var eye: V3 {
        let up: V3 = V3(0, eyeHeight, 0)
        let side: V3 = flatRight(yaw) * (lean * 0.35)
        return pos + up + side
    }
    var height: Float {
        switch stance {
        case .stand: return 1.8
        case .crouch: return 1.25
        case .prone: return 0.55
        }
    }

    init(id: Int, name: String, isPlayer: Bool, rig: SoldierRig, pos: V3) {
        self.id = id
        self.name = name
        self.isPlayer = isPlayer
        self.rig = rig
        self.pos = pos
    }

    /// Hit spheres in world space: (center, radius, part 0 body / 1 head / 2 legs)
    func hitSpheres() -> [(V3, Float, Int)] {
        if state == .vehicle {
            let p: V3 = pos
            let hd: V3 = p + V3(0, 1.35, 0)
            let bd: V3 = p + V3(0, 0.95, 0)
            return [(hd, 0.14, 1), (bd, 0.26, 0)]
        }
        var out: [(V3, Float, Int)] = []
        switch stance {
        case .prone:
            let f: V3 = flatForward(yaw)
            let h0: V3 = pos + f * 0.75
            let h1: V3 = pos + f * 0.3
            let h2: V3 = pos - f * 0.2
            let h3: V3 = pos - f * 0.75
            out.append((h0 + V3(0, 0.3, 0), 0.14, 1))
            out.append((h1 + V3(0, 0.22, 0), 0.24, 0))
            out.append((h2 + V3(0, 0.2, 0), 0.22, 0))
            out.append((h3 + V3(0, 0.15, 0), 0.2, 2))
        case .crouch:
            let e: V3 = eye
            out.append((e + V3(0, 0.02, 0), 0.14, 1))
            out.append((pos + V3(0, 0.82, 0), 0.27, 0))
            out.append((pos + V3(0, 0.4, 0), 0.26, 2))
        case .stand:
            let e: V3 = eye
            out.append((e + V3(0, 0.03, 0), 0.14, 1))
            out.append((pos + V3(0, 1.28, 0), 0.26, 0))
            out.append((pos + V3(0, 0.95, 0), 0.25, 0))
            out.append((pos + V3(0, 0.45, 0), 0.22, 2))
        }
        return out
    }

    func cancelActions() {
        reloading = false
        healing = nil
    }
}

// MARK: - Vehicles

final class Vehicle {
    let id: Int
    let isBike: Bool
    let node: SCNNode
    let body: SCNNode
    var wheels: [SCNNode] = []
    var frontWheels: [SCNNode] = []
    var pos: V3
    var yaw: Float
    var speed: Float = 0
    var steer: Float = 0
    var pitch: Float = 0
    var roll: Float = 0
    var vy: Float = 0
    var driver: Actor?
    var hp: Float
    var spin: Float = 0
    var destroyed = false
    let halfL: Float
    let halfW: Float
    let wheelR: Float

    init(id: Int, bike: Bool, assets: Assets, pos: V3, yaw: Float, paint: Int) {
        self.id = id
        isBike = bike
        self.pos = pos
        self.yaw = yaw
        node = SCNNode()
        hp = bike ? 450 : 1000
        halfL = bike ? 0.95 : 2.15
        halfW = bike ? 0.35 : 1.0
        wheelR = bike ? 0.36 : 0.42
        if bike {
            body = Models.bikeBody(assets: assets, paint: paint)
            for z in [-0.75, 0.75] as [Float] {
                let w = Models.wheel(assets: assets, radius: 0.36, width: 0.12, paint: paint)
                let holder = SCNNode()
                holder.simdPosition = V3(0, 0.36, z)
                holder.addChildNode(w)
                node.addChildNode(holder)
                wheels.append(w)
                if z < 0 { frontWheels.append(holder) }
            }
        } else {
            body = Models.jeepBody(assets: assets, paint: paint)
            for (x, z) in [(-0.88, -1.35), (0.88, -1.35), (-0.88, 1.35), (0.88, 1.35)] as [(Float, Float)] {
                let w = Models.wheel(assets: assets, radius: 0.42, width: 0.3, paint: paint)
                let holder = SCNNode()
                holder.simdPosition = V3(x, 0.42, z)
                holder.addChildNode(w)
                node.addChildNode(holder)
                wheels.append(w)
                if z < 0 { frontWheels.append(holder) }
            }
        }
        node.addChildNode(body)
        syncNode()
    }

    var forward: V3 { return flatForward(yaw) }

    func seatPos() -> V3 {
        let q = orientation()
        let local = isBike ? V3(0, 0.55, 0.1) : V3(-0.45, 0.7, -0.15)
        return pos + q.act(local)
    }

    func orientation() -> Quat {
        return simd_quatf(angle: yaw, axis: V3(0, 1, 0)) * simd_quatf(angle: pitch, axis: V3(1, 0, 0)) * simd_quatf(angle: roll, axis: V3(0, 0, 1))
    }

    func syncNode() {
        node.simdPosition = pos
        node.simdOrientation = orientation()
        for w in wheels { w.simdEulerAngles = V3(spin, 0, 0) }
        for f in frontWheels { f.simdEulerAngles = V3(0, steer * 0.5, 0) }
    }

    func groundAt(_ p: V3, col: CollisionWorld) -> Float {
        return col.ground(p.x, p.z, feetY: pos.y + 0.6, step: 0.9)
    }

    /// Returns collision impact speed (0 if none)
    func update(dt: Float, throttle: Float, steerIn: Float, col: CollisionWorld, terrain: Terrain) -> Float {
        let maxF: Float = isBike ? 31 : 27
        let accel: Float = isBike ? 10 : 8
        if throttle > 0.05 {
            if speed < -0.5 { speed += 18 * dt } else { speed += accel * throttle * dt * (1 - max(0, speed) / (maxF * 1.05)) }
        } else if throttle < -0.05 {
            if speed > 0.5 { speed -= 18 * dt * -throttle } else { speed -= 5 * dt * -throttle; speed = max(speed, -7) }
        } else {
            speed = approachf(speed, 0, dt * (abs(speed) * 0.25 + 1.2))
        }
        steer = approachf(steer, steerIn, dt * 3.5)
        let turnRate = steer * speed / ((isBike ? 2.2 : 3.0) + abs(speed) * 0.09)
        if vy > -1 { yaw -= turnRate * dt }
        let prev = pos
        let f = forward
        pos += f * speed * dt
        pos.x = clampf(pos.x, -790, 790)
        pos.z = clampf(pos.z, -790, 790)

        // collisions with world
        var impact: Float = 0
        var probe = pos + f * (halfL * 0.65) * (speed >= 0 ? 1 : -1)
        let before = probe
        col.pushOut(&probe, radius: halfW, height: 1.4, stepUp: 0.7)
        var center = pos
        col.pushOut(&center, radius: halfW, height: 1.4, stepUp: 0.7)
        if vlen(probe - before) > 0.001 || vlen(center - pos) > 0.001 {
            impact = abs(speed)
            pos = prev + (center - pos) * 0.5
            speed *= -0.25
        }
        // deep water blocks
        if terrain.height(pos.x, pos.z) < terrain.waterLevel - 1.1 {
            pos = prev
            impact = max(impact, abs(speed) * 0.5)
            speed = 0
        }
        // terrain following
        let r = flatRight(yaw)
        let fl: Float = isBike ? 0.75 : 1.35
        let hf = groundAt(pos + f * fl, col: col), hb = groundAt(pos - f * fl, col: col)
        let hl = groundAt(pos - r * halfW, col: col), hr = groundAt(pos + r * halfW, col: col)
        let target = (hf + hb + hl + hr) * 0.25
        let tp = atan2(hf - hb, fl * 2)
        let tr = isBike ? -steer * min(1, abs(speed) / 12) * 0.45 : atan2(hl - hr, halfW * 2)
        if pos.y > target + 0.25 {
            vy -= 9.8 * dt
            pos.y += vy * dt
            if pos.y < target { pos.y = target; vy = 0 }
        } else {
            if vy < -9 { impact = max(impact, -vy) }
            pos.y = target
            vy = 0
            pitch = lerpf(pitch, tp, min(1, dt * 8))
            roll = lerpf(roll, tr, min(1, dt * 8))
        }
        spin += speed / wheelR * dt
        syncNode()
        return impact
    }
}

// MARK: - Plane

final class FlightPlan {
    let start: V3
    let end: V3
    let speed: Float = 62
    let alt: Float = 420
    let node: SCNNode
    var t: Float = 0

    init(rng: inout RNG, assets: Assets) {
        let ang = rng.r(0, kTwoPi)
        let c = V2(rng.r(-220, 220), rng.r(-220, 220))
        let d = V2(cos(ang), sin(ang))
        start = V3(c.x - d.x * 1150, 420, c.y - d.y * 1150)
        end = V3(c.x + d.x * 1150, 420, c.y + d.y * 1150)
        node = Models.plane(assets: assets)
        node.simdOrientation = simd_quatf(angle: yawOf(end - start), axis: V3(0, 1, 0))
    }

    var length: Float { return vlen(end - start) }
    var dir: V3 { return vnorm(end - start) }
    func pos(at time: Float) -> V3 { return start + dir * min(time * speed, length) }
    var position: V3 { return pos(at: t) }
    var overMap: Bool {
        let p = position
        return abs(p.x) < 770 && abs(p.z) < 770
    }
    var done: Bool { return t * speed >= length }
    var hasEnteredMap: Bool {
        // time at which plane first enters the map square
        return t * speed > 300
    }

    /// Time when the plane passes closest to point p
    func closestTime(to p: V2) -> Float {
        let s = V2(start.x, start.z), dd = V2(dir.x, dir.z)
        let along = simd_dot(p - s, dd)
        return max(0, along / speed)
    }
}

// MARK: - Blue zone

final class Zone {
    struct Phase {
        var wait: Float
        var shrink: Float
        var radius: Float
        var dps: Float
    }
    let phases: [Phase] = [
        Phase(wait: 120, shrink: 60, radius: 560, dps: 1),
        Phase(wait: 60, shrink: 45, radius: 330, dps: 2),
        Phase(wait: 50, shrink: 40, radius: 190, dps: 4),
        Phase(wait: 40, shrink: 35, radius: 100, dps: 6),
        Phase(wait: 30, shrink: 30, radius: 50, dps: 8),
        Phase(wait: 25, shrink: 25, radius: 20, dps: 10),
        Phase(wait: 20, shrink: 25, radius: 0, dps: 14),
    ]
    var center = V2(0, 0)
    var radius: Float = 1200
    var nextCenter = V2(0, 0)
    var nextRadius: Float = 560
    var fromCenter = V2(0, 0)
    var fromRadius: Float = 1200
    var phase = 0
    var shrinking = false
    var timer: Float = 0
    var dps: Float = 0.6
    var finished = false
    let node: SCNNode
    let material: SCNMaterial
    var uvOffset: Float = 0

    init(rng: inout RNG, terrain: Terrain, assets: Assets) {
        center = V2(rng.r(-150, 150), rng.r(-150, 150))
        radius = 1250
        fromCenter = center
        fromRadius = radius
        // unit open cylinder
        let mb = MeshBuilder()
        mb.cylinder(1, r0: 1, r1: 1, y0: -120, y1: 600, seg: 128, uv: UVRect(u0: 0, v0: 0, u1: 90, v1: 6), caps: false)
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = assets.zoneWall
        m.diffuse.wrapS = .repeat
        m.diffuse.wrapT = .repeat
        m.isDoubleSided = true
        m.writesToDepthBuffer = false
        m.blendMode = .alpha
        m.transparencyMode = .aOne
        material = m
        let g = mb.build(materials: { _ in m })
        node = SCNNode(geometry: g)
        node.castsShadow = false
        node.renderingOrder = 50
        node.name = "zone"
        pickNext(rng: &rng, terrain: terrain)
        timer = phases[0].wait
        dps = 0.6
        syncNode()
    }

    func pickNext(rng: inout RNG, terrain: Terrain) {
        guard phase < phases.count else { return }
        let nr = phases[phase].radius
        var best = center
        for _ in 0..<30 {
            let maxOff = max(0, min(radius, 900) - nr)
            let c = center + rng.inDisc(maxOff)
            let inner = c
            if abs(inner.x) > 720 || abs(inner.y) > 720 { continue }
            if terrain.height(c.x, c.y) > terrain.waterLevel + 1 || nr > 150 {
                best = c
                break
            }
        }
        nextCenter = best
        nextRadius = nr
    }

    func update(dt: Float, rng: inout RNG, terrain: Terrain) -> String? {
        if finished { return nil }
        var msg: String?
        timer -= dt
        if !shrinking {
            if timer <= 0 {
                shrinking = true
                fromCenter = center
                fromRadius = radius
                timer = phases[phase].shrink
                msg = "安全区正在缩小！"
            }
        } else {
            let total = phases[phase].shrink
            let k = 1 - max(0, timer) / total
            center = fromCenter + (nextCenter - fromCenter) * k
            radius = fromRadius + (nextRadius - fromRadius) * k
            if timer <= 0 {
                center = nextCenter
                radius = nextRadius
                dps = phases[phase].dps
                shrinking = false
                phase += 1
                if phase >= phases.count {
                    finished = true
                } else {
                    pickNext(rng: &rng, terrain: terrain)
                    timer = phases[phase].wait
                    msg = "新的安全区已刷新，\(Int(phases[phase].wait))秒后开始缩小"
                }
            }
        }
        if shrinking { dps = phases[phase].dps }
        uvOffset += dt * 0.05
        syncNode()
        return msg
    }

    func syncNode() {
        let r = max(radius, 0.5)
        node.simdPosition = V3(center.x, 0, center.y)
        node.simdScale = V3(r, 1, r)
        material.diffuse.contentsTransform = SCNMatrix4MakeTranslation(uvOffset, uvOffset * 0.5, 0)
    }

    func outside(_ p: V3) -> Bool {
        let dx = p.x - center.x, dz = p.z - center.y
        return dx * dx + dz * dz > radius * radius
    }

    func distanceToSafe(_ p: V3) -> Float {
        let d = simd_length(V2(p.x, p.z) - nextCenter)
        return max(0, d - nextRadius)
    }
}
