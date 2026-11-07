import SceneKit
import UIKit

extension GameWorld {

    // MARK: firing

    /// Fires the actor's current weapon along `dir`. Returns true if a shot was fired.
    @discardableResult
    func fire(_ a: Actor, dir: V3, aimError: Float = 0) -> Bool {
        guard a.state == .ground, let w = a.weapon, !a.reloading, a.healing == nil, !a.inWater else { return false }
        let st = w.stats
        if now - a.lastShot < st.interval { return false }
        if w.mag <= 0 {
            startReload(a)
            return false
        }
        a.lastShot = now
        w.mag -= 1
        var spread = a.aiming ? st.spreadAim : st.spreadHip
        spread *= 1 + min(1, a.moveSpeed / 5) * (a.aiming ? 1.5 : 0.8)
        if a.stance == .crouch { spread *= 0.8 }
        if a.stance == .prone { spread *= 0.6 }
        if !a.onGround { spread += 0.08 }
        spread += aimError
        let up = abs(dir.y) > 0.95 ? V3(1, 0, 0) : V3(0, 1, 0)
        let rx = vnorm(vcross(dir, up)), ry = vcross(rx, dir)
        let origin = a.eye + dir * 0.4
        var muzzle: V3 = origin + dir * 0.4
        if a.isPlayer && !fpp {
            let shoulder: V3 = a.pos + V3(0, a.eyeHeight - 0.15, 0)
            let side: V3 = flatRight(a.yaw) * 0.25
            muzzle = shoulder + side + dir * 0.8
        }
        for k in 0..<st.pellets {
            let ang = rng.r(0, kTwoPi)
            let rr = (st.pellets > 1 ? sqrt(rng.f()) : rng.f()) * spread
            let d = vnorm(dir + (rx * cos(ang) + ry * sin(ang)) * rr)
            let tracer = a.isPlayer ? (k == 0) : (k == 0 && rng.chance(0.5))
            bullets.append(Bullet(pos: origin, vel: d * st.speed, owner: a.id, damage: st.damage, weapon: w.type, age: 0,
                                  tracer: tracer, falloff: st.falloffStart))
        }
        let near = vlen(a.pos - cameraNode.simdPosition) < 220
        if near || a.isPlayer {
            fx.muzzle(at: muzzle, light: vlen(a.pos - cameraNode.simdPosition) < 80)
        }
        let soundNames = ["m416", "akm", "uzi", "kar98k", "s12k", "p92"]
        audio?.play(soundNames[st.sound], at: a.eye, volume: a.isPlayer ? 0.75 : 1.0, rate: Float.random(in: 0.95...1.05))
        if st.sound == 3 { audio?.play("bolt", at: a.eye, volume: 0.5) }
        shots.append((pos: a.pos, time: now, owner: a.id))
        if a.isPlayer {
            // recoil
            let kickMul: Float = (a.stance == .prone ? 0.5 : (a.stance == .crouch ? 0.75 : 1.0)) * (a.aiming ? 0.8 : 1.1)
            a.pitch = min(1.25, a.pitch + st.recoilUp * kickMul * rng.r(0.8, 1.2))
            a.yaw += st.recoilSide * kickMul * rng.r(-1, 1)
            recoilKick = min(0.06, recoilKick + st.recoilUp * 0.6)
            viewKick = 1
            camShake = max(camShake, st.sound == 3 || st.sound == 4 ? 0.5 : 0.15)
            hud.haptic += 1
        }
        if w.mag == 0 && a.inv.ammo[st.ammo.rawValue] > 0 {
            // auto reload when empty
            a.lastShot = now
            startReloadLater(a)
        }
        return true
    }

    func startReloadLater(_ a: Actor) {
        if a.isPlayer || a.bot != nil { startReload(a) }
    }

    func melee(_ a: Actor) {
        if now - a.lastShot < 0.55 { return }
        a.lastShot = now
        a.throwAnimUntil = now + 0.25
        let f = flatForward(a.yaw)
        for b in actors where b.alive && b.id != a.id && b.state == .ground {
            let d = b.pos - a.pos
            if vlen(d) < 1.8 && vdot(vnorm(V3(d.x, 0, d.z)), f) > 0.5 {
                applyDamage(to: b, amount: 14, part: 0, from: a, weaponName: "拳头", dir: f)
                break
            }
        }
    }

    // MARK: bullets

    func updateBullets(dt: Float) {
        if bullets.isEmpty { return }
        let camP = cameraNode.simdPosition
        var keep: [Bullet] = []
        keep.reserveCapacity(bullets.count)
        for var b in bullets {
            b.age += dt
            let start = b.pos
            b.vel.y -= 9.8 * dt
            var end = start + b.vel * dt
            var hitT: Float = 2
            var hitP = end
            var hitN = V3(0, 1, 0)
            var hitKind: SurfaceKind = .ground
            var hitActor: Actor?
            var hitPart = 0
            var hitVehicle: Vehicle?
            if let h = col.raycast(start, end) {
                hitT = h.t; hitP = h.p; hitN = h.n; hitKind = h.kind
            }
            // water surface
            let wl = terrain.waterLevel
            if start.y > wl && end.y <= wl {
                let t = (start.y - wl) / max(1e-4, start.y - end.y)
                if t < hitT {
                    let p = start + (end - start) * t
                    if terrain.height(p.x, p.z) < wl {
                        hitT = t; hitP = p; hitN = V3(0, 1, 0); hitKind = .water
                    }
                }
            }
            let seg = end - start
            let segLen = vlen(seg)
            let dir = seg / max(segLen, 1e-5)
            for a in actors where a.alive && a.id != b.owner && a.state != .plane {
                // broad phase
                let mid = (start + end) * 0.5
                if vlen(a.pos - mid) > segLen * 0.5 + 2.5 { continue }
                for s in a.hitSpheres() {
                    if let t = raySphere(start, dir, s.0, s.1) {
                        let tn = t / max(segLen, 1e-5)
                        if tn <= 1 && tn < hitT {
                            hitT = tn; hitP = start + dir * t; hitN = -dir; hitKind = .flesh
                            hitActor = a; hitPart = s.2; hitVehicle = nil
                        }
                    }
                }
            }
            for v in vehicles where !v.destroyed {
                let c = v.pos + V3(0, 1.0, 0)
                if vlen(c - (start + end) * 0.5) > segLen * 0.5 + 3 { continue }
                let r: Float = v.isBike ? 0.8 : 1.5
                if let t = raySphere(start, dir, c, r) {
                    let tn = t / max(segLen, 1e-5)
                    if tn <= 1 && tn < hitT {
                        // drivers in jeeps are partly protected; bikes not
                        if let d = v.driver, v.isBike || rng.chance(0.5) {
                            hitT = tn; hitP = start + dir * t; hitN = -dir; hitKind = .flesh
                            hitActor = d; hitPart = 0; hitVehicle = nil
                        } else {
                            hitT = tn; hitP = start + dir * t; hitN = -dir; hitKind = .vehicle
                            hitVehicle = v; hitActor = nil
                        }
                    }
                }
            }
            if hitT <= 1 { end = hitP }
            if b.tracer && vlen(start - camP) < 400 {
                fx.tracer(from: start, to: end)
            }
            if hitT <= 1 {
                let traveled = b.age * vlen(b.vel)
                let fall: Float = traveled > b.falloff ? max(0.45, 1 - (traveled - b.falloff) / (b.falloff * 3)) : 1
                if let a = hitActor {
                    let owner = actors.first { $0.id == b.owner }
                    applyDamage(to: a, amount: b.damage * fall, part: hitPart, from: owner, weaponName: WeaponStats.of(b.weapon).name, dir: dir)
                    if vlen(hitP - camP) < 150 { fx.impact(at: hitP, normal: hitN, kind: .flesh) }
                } else if let v = hitVehicle {
                    v.hp -= b.damage * fall
                    if vlen(hitP - camP) < 200 { fx.impact(at: hitP, normal: hitN, kind: .metal) }
                    if v.hp <= 0 { destroyVehicle(v) }
                    if b.owner == player.id { hud.hitMarker = now }
                } else {
                    if vlen(hitP - camP) < 180 {
                        fx.impact(at: hitP, normal: hitN, kind: hitKind)
                        if vlen(hitP - camP) < 40 { audio?.play("impact", at: hitP, volume: 0.4) }
                    }
                }
                continue
            }
            b.pos = end
            if b.age < 2.5 && b.pos.y > -50 { keep.append(b) }
        }
        bullets = keep
    }

    // MARK: damage / death

    func applyDamage(to a: Actor, amount: Float, part: Int, from: Actor?, weaponName: String, dir: V3) {
        guard a.alive, amount > 0 else { return }
        var dmg = amount
        switch part {
        case 1:
            dmg *= 2.1
            if a.inv.helmet > 0 {
                dmg *= 1 - Armor.reduce[a.inv.helmet]
                a.inv.helmetHP -= amount
                if a.inv.helmetHP <= 0 { a.inv.helmet = 0; a.inv.helmetHP = 0 }
            }
        case 0:
            if a.inv.vest > 0 {
                dmg *= 1 - Armor.reduce[a.inv.vest]
                a.inv.vestHP -= amount
                if a.inv.vestHP <= 0 { a.inv.vest = 0; a.inv.vestHP = 0 }
            }
        case 2:
            dmg *= 0.8
        default:
            break
        }
        a.health -= dmg
        if let f = from {
            a.lastHurtBy = f.id
            a.lastHurtTime = now
            a.lastHurtFrom = f.pos
            if f.isPlayer && !a.isPlayer {
                hud.hitMarker = now
                audio?.playUI("hit", volume: 0.5)
            }
        }
        if a.isPlayer {
            hud.damageTime = now
            if let f = from {
                let d = f.pos - a.pos
                hud.damageDir = wrapAngle(yawOf(d) - a.yaw)
            } else {
                hud.damageDir = 99
            }
            camShake = max(camShake, 0.25)
            hud.hapticHeavy += 1
        }
        if a.healing != nil && part >= 0 { a.healing = nil }
        if a.health <= 0 {
            a.health = 0
            kill(a, by: from, weaponName: weaponName)
        }
    }

    func kill(_ a: Actor, by killer: Actor?, weaponName: String) {
        guard a.alive else { return }
        a.rank = aliveCount
        if let v = a.vehicle {
            v.driver = nil
            a.vehicle = nil
            a.pos = v.pos + flatRight(v.yaw) * 1.5
            a.pos.y = col.ground(a.pos.x, a.pos.z, feetY: a.pos.y + 2, step: 3)
        }
        a.state = .dead
        a.deathTime = now
        a.reloading = false
        a.healing = nil
        a.vel = V3(0, 0, 0)
        aliveCount -= 1
        if let k = killer {
            k.kills += 1
            a.killerName = k.name
            a.killerWeapon = weaponName
            addFeed("\(k.name) 使用 \(weaponName) 淘汰了 \(a.name)", mine: k.isPlayer || a.isPlayer)
            if k.isPlayer {
                hud.killMarker = now
                message("淘汰 \(a.name)！")
                hud.hapticHeavy += 1
            }
        } else {
            a.killerName = weaponName
            a.killerWeapon = ""
            addFeed("\(a.name) 死于\(weaponName)", mine: a.isPlayer)
        }
        if a.state == .dead {
            // ground fallback (in case dying in air)
            let g = col.ground(a.pos.x, a.pos.z, feetY: a.pos.y + 1, step: 2)
            if a.pos.y > g + 0.5 || a.pos.y < g - 1 { a.pos.y = max(g, terrain.waterLevel - 1.2) }
        }
        dropCrate(for: a)
        if a.isPlayer {
            gameOver = true
            a.rank = aliveCount + 1
            spectate = nil
        }
        if aliveCount <= 1 && player.alive {
            won = true
            gameOver = true
            player.rank = 1
            message("大吉大利，今晚吃鸡！")
        }
    }

    // MARK: grenades

    func throwGrenade(_ a: Actor, dir: V3) {
        let t = a.throwType
        guard a.inv.throws[t.rawValue] > 0 else { return }
        a.inv.throws[t.rawValue] -= 1
        a.lastThrow = now
        a.throwAnimUntil = now + 0.4
        let n = SCNNode(geometry: Models.lootGeometry(.throwable(t), assets: assets))
        let p = a.eye + dir * 0.5
        n.simdPosition = p
        fx.root.addChildNode(n)
        let v = dir * 19 + V3(0, 3.0, 0) + a.vel * 0.5
        grenades.append(Grenade(pos: p, vel: v, type: t, fuse: t == .frag ? 4.0 : 2.0, owner: a.id, node: n))
        if a.inv.throws[t.rawValue] == 0 {
            let other: ThrowType = t == .frag ? .smoke : .frag
            if a.inv.throws[other.rawValue] > 0 { a.throwType = other } else { a.slot = a.inv.primary[0] != nil ? 0 : (a.inv.primary[1] != nil ? 1 : (a.inv.pistol != nil ? 2 : -1)) }
        }
    }

    func updateGrenades(dt: Float) {
        if grenades.isEmpty { return }
        var keep: [Grenade] = []
        for var g in grenades {
            g.fuse -= dt
            g.vel.y -= 9.8 * dt
            let next = g.pos + g.vel * dt
            if let h = col.raycast(g.pos, next) {
                g.pos = h.p + h.n * 0.05
                let vn = vdot(g.vel, h.n)
                g.vel = (g.vel - h.n * (2 * vn)) * 0.45
                if vlen(g.vel) < 0.6 { g.vel = V3(0, 0, 0) }
            } else {
                g.pos = next
            }
            g.node.simdPosition = g.pos
            if g.fuse <= 0 {
                g.node.removeFromParentNode()
                if g.type == .frag {
                    explode(at: g.pos, owner: g.owner, radius: 8, maxDamage: 160, weaponName: "手榴弹")
                } else {
                    fx.smoke(at: g.pos)
                    col.smokes.append((c: g.pos + V3(0, 2.5, 0), r: 7.5, until: now + 25))
                }
                continue
            }
            keep.append(g)
        }
        grenades = keep
    }

    func explode(at p: V3, owner: Int, radius: Float, maxDamage: Float, weaponName: String) {
        fx.explosion(at: p)
        audio?.play("explosion", at: p, volume: 1.0)
        let d = vlen(p - cameraNode.simdPosition)
        if d < 60 { camShake = max(camShake, (1 - d / 60) * 1.5); hud.hapticHeavy += 1 }
        let ownerA = actors.first { $0.id == owner }
        for a in actors where a.alive && a.state != .plane {
            let c = a.pos + V3(0, 0.8, 0)
            let dist = vlen(c - p)
            if dist > radius { continue }
            if !col.lineClear(p + V3(0, 0.4, 0), c, now: now, checkSmoke: false) { continue }
            let k = 1 - dist / radius
            applyDamage(to: a, amount: maxDamage * k * k + 10 * k, part: -1, from: ownerA, weaponName: weaponName, dir: vnorm(c - p))
        }
        for v in vehicles where !v.destroyed && vlen(v.pos - p) < radius {
            v.hp -= maxDamage * 3 * (1 - vlen(v.pos - p) / radius)
            if v.hp <= 0 { destroyVehicle(v) }
        }
    }

    // MARK: vehicles

    func nearestVehicle(_ a: Actor) -> Vehicle? {
        var best: Vehicle?
        var bd: Float = 3.6
        for v in vehicles where !v.destroyed && v.driver == nil {
            let d = distXZ(v.pos, a.pos)
            if d < bd && abs(v.pos.y - a.pos.y) < 2.5 { bd = d; best = v }
        }
        return best
    }

    func enterVehicle(_ a: Actor, _ v: Vehicle) {
        guard a.state == .ground, v.driver == nil, !v.destroyed else { return }
        a.cancelActions()
        a.aiming = false
        a.stance = .stand
        a.state = .vehicle
        a.vehicle = v
        v.driver = a
        a.pos = v.seatPos()
        if a.isPlayer { message(v.isBike ? "驾驶摩托车" : "驾驶吉普车") }
    }

    func exitVehicle(_ a: Actor) {
        guard let v = a.vehicle else { return }
        v.driver = nil
        a.vehicle = nil
        var p = v.pos + flatRight(v.yaw) * (v.halfW + 0.9) * (v.isBike ? 1 : -1)
        p.y = col.ground(p.x, p.z, feetY: v.pos.y + 1.5, step: 2.0)
        col.pushOut(&p, radius: 0.35, height: 1.8, stepUp: 0.5)
        a.pos = p
        a.state = .ground
        a.vel = flatForward(v.yaw) * v.speed * 0.3
        a.onGround = true
        if abs(v.speed) > 12 {
            applyDamage(to: a, amount: (abs(v.speed) - 12) * 4, part: -1, from: nil, weaponName: "跳车", dir: V3(0, 0, 0))
        }
    }

    func destroyVehicle(_ v: Vehicle) {
        guard !v.destroyed else { return }
        v.destroyed = true
        explode(at: v.pos + V3(0, 0.8, 0), owner: -1, radius: 7, maxDamage: 120, weaponName: "载具爆炸")
        if let d = v.driver {
            exitVehicle(d)
            applyDamage(to: d, amount: 80, part: -1, from: nil, weaponName: "载具爆炸", dir: V3(0, 1, 0))
        }
        v.speed = 0
        v.node.opacity = 0.45
        col.addBox(v.pos - V3(v.halfW, 0, v.halfW), v.pos + V3(v.halfW, 1.4, v.halfW), kind: .metal)
    }

    func updateVehicles(dt: Float) {
        for v in vehicles where !v.destroyed {
            if let d = v.driver, !d.isPlayer {
                // bots: handled inside BotBrain via drive()
                _ = d
            } else if v.driver == nil {
                if abs(v.speed) > 0.05 || v.vy != 0 {
                    _ = v.update(dt: dt, throttle: 0, steerIn: 0, col: col, terrain: terrain)
                }
            }
            // run over
            if abs(v.speed) > 5 {
                for a in actors where a.alive && a.state == .ground && a.vehicle == nil {
                    if distXZ(a.pos, v.pos) < v.halfW + 1.1 && abs(a.pos.y - v.pos.y) < 2 {
                        let f = flatForward(v.yaw)
                        let rel = a.pos - v.pos
                        if abs(vdot(rel, f)) < v.halfL + 0.5 {
                            applyDamage(to: a, amount: abs(v.speed) * 5, part: -1, from: v.driver, weaponName: "载具", dir: f)
                            a.vel = f * v.speed * 0.6 + V3(0, 3, 0)
                            a.pos += flatRight(v.yaw) * (vdot(rel, flatRight(v.yaw)) >= 0 ? 1 : -1) * 0.8
                            a.onGround = false
                        }
                    }
                }
            }
        }
    }
}
