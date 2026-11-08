import SceneKit
import simd

/// AI for computer controlled soldiers.
final class BotBrain {
    enum Task { case loot, roam, zone, fight, heal }

    let skill: Float
    var dropTarget = V2(0, 0)
    var jumpTime: Float = 0
    var task: Task = .loot
    var waypoints: [V3] = []
    var targetSpot = -1
    var target: Actor?
    var lastSeenPos = V3(0, 0, 0)
    var lastSeenTime: Float = -100
    var visibleNow = false
    var reactUntil: Float = 0
    var aimErr = V2(0, 0)
    var thinkT: Float = 0
    var strafe: Float = 1
    var strafeT: Float = 0
    var stuckT: Float = 0
    var stuckCount = 0
    var progressPos = V3(0, 0, 0)
    var sideStep: Float = 0
    var sideStepT: Float = 0
    var visited = Set<Int>()
    var lootsDone = 0
    var lootGoal: Int
    var investigate: V3?
    var investigateUntil: Float = 0
    var burstLeft = 0
    var pauseUntil: Float = 0
    var farAcc: Float = 0
    var crouchUntil: Float = 0
    var roamGoal: V3?
    var nextGrenade: Float = 0

    init(skill: Float) {
        self.skill = skill
        lootGoal = 4 + Int(skill * 8)
    }

    // MARK: drop

    func chooseDrop(world: GameWorld) {
        var r = RNG(UInt64(skill * 100000) &+ world.rng.next())
        // land just outside a doorway (never on a roof), so the bot can walk in and loot
        var spots: [V3] = world.data.doors.map { $0.outside }
        if spots.isEmpty { spots = world.data.loot.map { $0.p } }
        let plan = world.plan
        var best = V2(0, 0)
        for _ in 0..<12 {
            let s: V3 = spots.isEmpty ? V3(r.r(-500, 500), 0, r.r(-500, 500)) : spots[r.i(spots.count)]
            let p = V2(s.x, s.z)
            // prefer spots within ~600 m of the flight path
            let t = plan.closestTime(to: p)
            let onPath = plan.pos(at: t)
            if simd_length(V2(onPath.x, onPath.z) - p) < 600 || r.chance(0.15) {
                best = p + r.inDisc(2.5)
                break
            }
            best = p
        }
        dropTarget = best
        let t = plan.closestTime(to: best)
        let onPath = plan.pos(at: t)
        let lateral = simd_length(V2(onPath.x, onPath.z) - best)
        jumpTime = max(4, t - lateral / 40 + r.r(-3, 2))
    }

    // MARK: helpers

    static func chestHeight(_ c: Actor) -> Float {
        if c.state == .vehicle { return 1.0 }
        switch c.stance {
        case .prone: return 0.3
        case .crouch: return 0.88
        case .stand: return 1.28
        }
    }

    func effectiveRange(_ w: WeaponInst?) -> Float {
        guard let w = w else { return 2 }
        switch w.type {
        case .m416, .akm: return w.scope.magnified ? 320 : 180
        case .kar98k: return w.scope.magnified ? 520 : 220
        case .uzi: return 60
        case .s12k: return 30
        case .p92: return 50
        }
    }

    func bestSlot(_ a: Actor, distance: Float) -> Int {
        var best = -1
        var bestScore: Float = -1
        for s in 0..<3 {
            guard let w = a.inv.weapon(slot: s) else { continue }
            let ammo = w.mag + a.inv.ammo[w.stats.ammo.rawValue]
            if ammo == 0 { continue }
            var score: Float
            switch w.type {
            case .m416: score = 6
            case .akm: score = 6
            case .kar98k: score = distance > 90 ? 8 : 3
            case .s12k: score = distance < 25 ? 9 : 1
            case .uzi: score = distance < 40 ? 7 : 2
            case .p92: score = 1
            }
            if w.mag == 0 { score -= 0.5 }
            if score > bestScore { bestScore = score; best = s }
        }
        return best
    }

    func hasUsableWeapon(_ a: Actor) -> Bool {
        return bestSlot(a, distance: 50) >= 0
    }

    // MARK: update

    func update(actor a: Actor, world w: GameWorld, dt: Float) {
        switch a.state {
        case .plane:
            if w.plan.t >= jumpTime && w.plan.overMap { w.jumpFromPlane(a) }
            return
        case .freefall, .chute:
            let d = V2(dropTarget.x - a.pos.x, dropTarget.y - a.pos.z)
            let dist = simd_length(d)
            if dist > 2 { a.yaw = approachAngle(a.yaw, yawOf(V3(d.x, 0, d.y)), dt * 2.5) }
            let steer = V2(0, dist > 30 ? 1 : (dist > 6 ? 0.3 : -0.6))
            w.updateAirborne(a, dt: dt, steer: steer)
            return
        case .vehicle:
            if let v = a.vehicle {
                _ = v.update(dt: dt, throttle: 0, steerIn: 0, col: w.col, terrain: w.terrain)
                w.exitVehicle(a)
            }
            return
        case .dead:
            return
        case .ground:
            break
        }
        if a.far {
            farUpdate(a, w, dt)
            return
        }
        thinkT -= dt
        if thinkT <= 0 {
            thinkT = 0.18 + Float.random(in: 0...0.12)
            think(a, w)
        }
        act(a, w, dt)
    }

    // MARK: perception and decisions

    func think(_ a: Actor, _ w: GameWorld) {
        if let t = target, !t.alive { target = nil }
        let sight: Float = 110 + skill * 150
        let f = flatForward(a.yaw)
        var found: Actor?
        var checks = 0
        var cands: [Actor] = []
        for o in w.actors {
            if !o.alive || o.id == a.id { continue }
            if o.state != .ground && o.state != .vehicle { continue }
            if vlen(o.pos - a.pos) >= sight { continue }
            cands.append(o)
        }
        cands.sort { vlen($0.pos - a.pos) < vlen($1.pos - a.pos) }
        for c in cands {
            if checks >= 3 { break }
            let d = c.pos - a.pos
            let dist = vlen(d)
            let facing = vdot(vnorm(V3(d.x, 0, d.z)), f)
            let recentlyShot = w.shots.contains { $0.owner == c.id && w.now - $0.time < 1.0 }
            if facing < 0.25 && dist > 12 && !recentlyShot && c.id != a.lastHurtBy { continue }
            if c.stance == .prone && dist > 45 + skill * 60 && !recentlyShot { continue }
            if c.stance == .crouch && dist > 140 + skill * 80 && !recentlyShot { continue }
            checks += 1
            let aimPt: V3 = c.pos + V3(0, BotBrain.chestHeight(c), 0)
            if w.col.lineClear(a.eye, aimPt, now: w.now) {
                found = c
                break
            }
        }
        visibleNow = found != nil
        if let c = found {
            if target !== c {
                reactUntil = w.now + (0.95 - skill * 0.6) + Float.random(in: 0...0.35)
                let e = (1 - skill) * 0.14 + 0.025
                aimErr = V2(Float.random(in: -e...e), Float.random(in: -e...e) * 0.6)
            }
            target = c
            lastSeenPos = c.pos
            lastSeenTime = w.now
        } else if a.lastHurtTime > w.now - 2, a.lastHurtBy >= 0, target == nil {
            investigate = a.lastHurtFrom
            investigateUntil = w.now + 6
            if let att = w.actors.first(where: { $0.id == a.lastHurtBy }), att.alive {
                target = att
                lastSeenPos = att.pos
                lastSeenTime = w.now - 1.5
                reactUntil = w.now + 0.4
            }
        } else if target == nil {
            for s in w.shots where s.owner != a.id && w.now - s.time < 1.0 && vlen(s.pos - a.pos) < 130 {
                investigate = s.pos
                investigateUntil = w.now + 8
                break
            }
        }
        // choose task
        let hasMed = a.inv.meds[0] > 0 || a.inv.meds[1] > 0 || a.inv.meds[2] > 0
        let canFight = hasUsableWeapon(a)
        if let _ = target, w.now - lastSeenTime < 5, canFight {
            task = .fight
        } else if a.health < 60 && hasMed && w.now - a.lastHurtTime > 2.5 {
            task = .heal
        } else if w.zone.outside(a.pos) || (!w.zone.shrinking && w.zone.timer < 45 && w.zone.distanceToSafe(a.pos) > 0) || (w.zone.shrinking && w.zone.distanceToSafe(a.pos) > 0) {
            if task != .zone { waypoints.removeAll() }
            task = .zone
            target = nil
        } else if (!canFight || lootsDone < lootGoal) && w.zone.phase < 4 {
            if task != .loot { waypoints.removeAll() }
            task = .loot
            if w.now - lastSeenTime > 5 { target = nil }
        } else {
            if task != .roam { waypoints.removeAll(); roamGoal = nil }
            task = .roam
            if w.now - lastSeenTime > 5 { target = nil }
        }
        // weapon management
        let dist = target.map { vlen($0.pos - a.pos) } ?? 60
        let bs = bestSlot(a, distance: dist)
        if bs >= 0 && bs != a.slot && !a.reloading { a.slot = bs }
        if bs < 0 && a.slot != 3 { a.slot = -1 }
        if let wp = a.weapon, !a.reloading, a.healing == nil {
            let low = wp.mag == 0 || (task != .fight && Float(wp.mag) < Float(wp.stats.mag) * 0.5)
            if low && a.inv.ammo[wp.stats.ammo.rawValue] > 0 { w.startReload(a) }
        }
        // plan path
        if waypoints.isEmpty {
            switch task {
            case .loot:
                planLoot(a, w)
            case .zone:
                let c = w.zone.nextCenter
                let r = max(5, w.zone.nextRadius * 0.6)
                var p = c + V2(Float.random(in: -r...r), Float.random(in: -r...r)) * 0.7
                if simd_length(p - c) > r { p = c }
                waypoints = [V3(p.x, w.terrain.height(p.x, p.y), p.y)]
            case .roam:
                if let inv = investigate, w.now < investigateUntil {
                    waypoints = [inv]
                } else {
                    let c = w.zone.nextCenter
                    let r = max(5, w.zone.nextRadius * 0.7)
                    let p = c + V2(Float.random(in: -r...r), Float.random(in: -r...r)) * 0.7
                    let y = w.terrain.height(p.x, p.y)
                    if y > w.terrain.waterLevel + 0.5 { waypoints = [V3(p.x, y, p.y)] }
                }
            default:
                break
            }
        }
    }

    func planLoot(_ a: Actor, _ w: GameWorld) {
        let spots = w.data.loot
        var best = -1
        var bd: Float = 160
        for (i, s) in spots.enumerated() where !visited.contains(i) {
            let d = distXZ(s.p, a.pos)
            if d < bd && abs(s.p.y - a.pos.y) < 25 { bd = d; best = i }
        }
        if best < 0 {
            lootsDone = lootGoal
            return
        }
        targetSpot = best
        let sp = spots[best].p
        // route through the nearest door if the spot is inside a building
        var door: DoorWay?
        var dd: Float = 14
        for d in w.data.doors {
            let x = distXZ(d.inside, sp)
            if x < dd && abs(d.inside.y - sp.y) < 1.5 { dd = x; door = d }
        }
        if let d = door, distXZ(a.pos, d.inside) > 3 {
            waypoints = [d.outside, d.inside, sp]
        } else {
            waypoints = [sp]
        }
    }

    // MARK: acting

    func act(_ a: Actor, _ w: GameWorld, _ dt: Float) {
        var move = V2(0, 0)
        var sprint = false
        a.aiming = false
        aimErr *= exp(-dt * (0.8 + skill * 2.2))

        switch task {
        case .fight:
            guard let t = target else { break }
            let tp: V3 = t.pos + V3(0, BotBrain.chestHeight(t), 0)
            let lead = t.vel * (vlen(tp - a.eye) / 600) * skill
            let aimAt = (visibleNow ? tp : lastSeenPos + V3(0, 1.2, 0)) + lead
            let dir = vnorm(aimAt - a.eye)
            let dy = yawOf(dir) + aimErr.x, dp = pitchOf(dir) + aimErr.y
            let turn = (2.5 + skill * 5) * dt
            a.yaw = approachAngle(a.yaw, dy, turn)
            a.pitch = approachf(a.pitch, dp, turn)
            let dist = vlen(t.pos - a.pos)
            let rng = effectiveRange(a.weapon)
            a.aiming = dist > 25 && a.weapon != nil
            // fire
            let angErr = abs(wrapAngle(a.yaw - yawOf(dir))) + abs(a.pitch - pitchOf(dir))
            if visibleNow && w.now > reactUntil && w.now > pauseUntil && angErr < 0.06 + (1 - skill) * 0.05 && dist < rng * 1.2 {
                if let wp = a.weapon {
                    let fireDir = dirFrom(yaw: a.yaw, pitch: a.pitch)
                    let extra = (1 - skill) * 0.012 * (1 + dist / 100)
                    if w.fire(a, dir: fireDir, aimError: extra) {
                        if wp.stats.autoCapable && wp.auto {
                            burstLeft -= 1
                            if burstLeft <= 0 {
                                burstLeft = dist < 25 ? 8 : (dist < 80 ? 4 : 2)
                                pauseUntil = w.now + (dist < 25 ? 0.15 : 0.35) + (1 - skill) * 0.35
                            }
                        } else {
                            pauseUntil = w.now + wp.stats.interval + 0.1 + (1 - skill) * 0.4
                        }
                    }
                } else if a.slot == 3 {
                    w.throwGrenade(a, dir: vnorm(dir + V3(0, 0.25, 0)))
                } else if dist < 2 {
                    w.melee(a)
                }
            }
            // grenade when target hides
            if !visibleNow && w.now - lastSeenTime < 3 && dist > 10 && dist < 32 && a.inv.throws[0] > 0 && w.now > nextGrenade && skill > 0.4 {
                nextGrenade = w.now + 12
                a.throwType = .frag
                let gd = vnorm(lastSeenPos - a.eye + V3(0, dist * 0.35, 0))
                w.throwGrenade(a, dir: gd)
            }
            // movement: strafe and keep distance
            strafeT -= dt
            if strafeT <= 0 {
                strafeT = Float.random(in: 0.6...1.8)
                strafe = Float.random(in: 0...1) < 0.5 ? -1 : 1
                if Float.random(in: 0...1) < 0.25 { strafe = 0 }
                if dist > 40 && Float.random(in: 0...1) < 0.35 * skill { crouchUntil = w.now + Float.random(in: 1...3) }
            }
            var fwd: Float = 0
            if !visibleNow { fwd = 1 } else if dist > rng * 0.8 { fwd = 1 } else if dist < 7 && a.weapon?.type != .s12k { fwd = -0.7 }
            if a.weapon == nil && visibleNow { fwd = dist > 2 ? 1 : 0 }
            move = V2(strafe * 0.8, fwd)
            a.stance = w.now < crouchUntil ? .crouch : .stand
            if !visibleNow && distXZ(a.pos, lastSeenPos) < 2 { lastSeenTime -= 10 }
        case .heal:
            a.stance = .crouch
            if a.healing == nil {
                if a.health < 75 && a.inv.meds[MedType.firstAid.rawValue] > 0 { w.startHeal(a, .firstAid) }
                else if a.inv.meds[MedType.medkit.rawValue] > 0 { w.startHeal(a, .medkit) }
                else if a.health < 75 && a.inv.meds[MedType.bandage.rawValue] > 0 { w.startHeal(a, .bandage) }
                else if a.inv.meds[MedType.drink.rawValue] > 0 && a.boost < 40 { w.startHeal(a, .drink) }
                else { task = .roam }
            }
        case .loot, .roam, .zone:
            a.stance = .stand
            if let wp = waypoints.first {
                let d = V3(wp.x - a.pos.x, 0, wp.z - a.pos.z)
                let dist = vlen(d)
                if dist < 1.1 {
                    waypoints.removeFirst()
                    if waypoints.isEmpty && task == .loot {
                        lootHere(a, w)
                        if targetSpot >= 0 { visited.insert(targetSpot) }
                        lootsDone += 1
                    }
                } else {
                    let want = yawOf(d)
                    a.yaw = approachAngle(a.yaw, want, dt * 4)
                    let aligned = abs(wrapAngle(a.yaw - want)) < 0.6
                    move = V2(0, aligned ? 1 : 0.3)
                    sprint = task != .loot || dist > 12
                    a.pitch = approachf(a.pitch, 0, dt)
                }
            } else if let inv = investigate, w.now < investigateUntil {
                let d = inv - a.pos
                a.yaw = approachAngle(a.yaw, yawOf(d), dt * 3)
            }
            // opportunistic pickup on the way
            if Int(w.now * 4) % 4 == 0 {
                for it in w.lootNear(a.pos, radius: 2.0) where a.inv.wantsAuto(it.kind) {
                    w.pick(a, it, explicit: false)
                }
            }
        }
        // stuck handling
        stuckT += dt
        if stuckT > 1.0 {
            let moved = distXZ(a.pos, progressPos)
            if vlen2(move) > 0.3 && moved < 0.6 {
                stuckCount += 1
                sideStep = Float.random(in: 0...1) < 0.5 ? -1 : 1
                sideStepT = 1.1
                if stuckCount >= 3 {
                    stuckCount = 0
                    if !waypoints.isEmpty { waypoints.removeFirst() }
                    if waypoints.isEmpty && task == .loot {
                        if targetSpot >= 0 { visited.insert(targetSpot) }
                    }
                }
            } else if moved > 1.5 {
                stuckCount = 0
            }
            progressPos = a.pos
            stuckT = 0
        }
        if sideStepT > 0 {
            sideStepT -= dt
            move = V2(sideStep, 0.2)
            sprint = false
        }
        w.moveActor(a, dt: dt, move: move, sprint: sprint)
    }

    func lootHere(_ a: Actor, _ w: GameWorld) {
        for it in w.lootNear(a.pos, radius: 2.8) {
            switch it.kind {
            case .weapon(let wt):
                let st = WeaponStats.of(wt)
                if st.isPistol { if a.inv.pistol == nil { w.pick(a, it, explicit: true) } }
                else if a.inv.primary[0] == nil || a.inv.primary[1] == nil { w.pick(a, it, explicit: true) }
            default:
                if a.inv.wantsAuto(it.kind) { w.pick(a, it, explicit: false) }
            }
        }
        // also grab ammo for weapons we have
        for it in w.lootNear(a.pos, radius: 2.8) {
            if case .ammo = it.kind, a.inv.wantsAuto(it.kind) { w.pick(a, it, explicit: false) }
        }
    }

    // MARK: far simulation (cheap)

    func farUpdate(_ a: Actor, _ w: GameWorld, _ dt: Float) {
        farAcc += dt
        if farAcc < 0.25 { return }
        let step = farAcc
        farAcc = 0
        thinkT -= step
        if thinkT <= 0 || waypoints.isEmpty {
            thinkT = 1.5
            target = nil
            visibleNow = false
            // decide
            if w.zone.outside(a.pos) || w.zone.distanceToSafe(a.pos) > 0 && (w.zone.shrinking || w.zone.timer < 50) {
                task = .zone
            } else if (!hasUsableWeapon(a) || lootsDone < lootGoal) && w.zone.phase < 4 {
                task = .loot
            } else {
                task = .roam
            }
            if waypoints.isEmpty {
                switch task {
                case .loot: planLoot(a, w)
                case .zone:
                    let c = w.zone.nextCenter
                    let p = c + V2(Float.random(in: -1...1), Float.random(in: -1...1)) * w.zone.nextRadius * 0.5
                    waypoints = [V3(p.x, 0, p.y)]
                default:
                    let c = w.zone.nextCenter
                    let p = c + V2(Float.random(in: -1...1), Float.random(in: -1...1)) * w.zone.nextRadius * 0.6
                    waypoints = [V3(p.x, 0, p.y)]
                }
            }
            if a.health < 70 {
                if a.inv.meds[1] > 0 { a.inv.meds[1] -= 1; a.health = max(a.health, 75) }
                else if a.inv.meds[2] > 0 { a.inv.meds[2] -= 1; a.health = 100 }
                else if a.inv.meds[0] > 0 { a.inv.meds[0] -= 1; a.health = min(75, a.health + 12) }
            }
            let bs = bestSlot(a, distance: 60)
            a.slot = bs
            if let wp = a.weapon, wp.mag < wp.stats.mag {
                let take = min(wp.stats.mag - wp.mag, a.inv.ammo[wp.stats.ammo.rawValue])
                wp.mag += take
                a.inv.ammo[wp.stats.ammo.rawValue] -= take
            }
        }
        guard let wp = waypoints.first else { return }
        var d = V3(wp.x - a.pos.x, 0, wp.z - a.pos.z)
        let dist = vlen(d)
        let speed: Float = 5.6
        if dist < 2 {
            waypoints.removeFirst()
            if waypoints.isEmpty && task == .loot {
                // teleport onto the spot and loot it
                a.pos = wp
                lootHere(a, w)
                if targetSpot >= 0 { visited.insert(targetSpot) }
                lootsDone += 1
            }
            return
        }
        d /= dist
        let mv = min(dist, speed * step)
        var np = a.pos + d * mv
        let g = w.terrain.height(np.x, np.z)
        if g < w.terrain.waterLevel - 1.2 {
            // avoid deep water: skip waypoint
            waypoints.removeAll()
            return
        }
        np.y = w.col.ground(np.x, np.z, feetY: max(g, a.pos.y) + 0.3, step: 0.8)
        a.pos = np
        a.yaw = yawOf(d)
        a.moveSpeed = speed
        a.forwardSpeed = speed
        a.stance = .stand
        a.onGround = true
    }
}

extension GameWorld {
    /// Very cheap combat resolution between bots that are far from the player.
    func farCombat() {
        let fars = actors.filter { $0.alive && !$0.isPlayer && $0.far && $0.state == .ground }
        if fars.count < 2 { return }
        for i in 0..<fars.count {
            let a = fars[i]
            for j in (i + 1)..<fars.count {
                let b = fars[j]
                let d = distXZ(a.pos, b.pos)
                if d > 70 { continue }
                let aw = a.bot?.hasUsableWeapon(a) ?? false
                let bw = b.bot?.hasUsableWeapon(b) ?? false
                if !aw && !bw { continue }
                let pa: Float = aw ? (0.35 + (a.bot?.skill ?? 0.5) * 0.4) * (1 - d / 120) : 0
                let pb: Float = bw ? (0.35 + (b.bot?.skill ?? 0.5) * 0.4) * (1 - d / 120) : 0
                if rng.chance(pa) {
                    let wn = a.weapon?.stats.name ?? "拳头"
                    applyDamage(to: b, amount: rng.r(18, 42), part: rng.chance(0.15) ? 1 : 0, from: a, weaponName: wn, dir: vnorm(b.pos - a.pos))
                    if let wpn = a.weapon, wpn.mag > 0 { wpn.mag -= 1 }
                }
                if b.alive && a.alive && rng.chance(pb) {
                    let wn = b.weapon?.stats.name ?? "拳头"
                    applyDamage(to: a, amount: rng.r(18, 42), part: rng.chance(0.15) ? 1 : 0, from: b, weaponName: wn, dir: vnorm(a.pos - b.pos))
                    if let wpn = b.weapon, wpn.mag > 0 { wpn.mag -= 1 }
                }
            }
        }
    }
}
