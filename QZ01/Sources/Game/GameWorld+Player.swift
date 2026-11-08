import SceneKit
import UIKit

extension GameWorld {

    // MARK: player

    func updatePlayerControl(dt: Float) {
        let p = player!
        // look
        let fov = Float(camera.fieldOfView)
        let k = 0.0042 * settings.sensitivity * (fov / 50)
        if p.alive {
            p.yaw = wrapAngle(p.yaw - input.look.x * k)
            p.pitch = clampf(p.pitch - input.look.y * k, -1.35, 1.25)
        }
        switch p.state {
        case .plane:
            p.pos = plan.position
        case .freefall, .chute:
            updateAirborne(p, dt: dt, steer: input.move)
        case .ground:
            p.aiming = input.aim && p.weapon != nil && p.healing == nil && !p.inWater
            let targetLean: Float = input.leanL ? -1 : (input.leanR ? 1 : 0)
            p.lean = approachf(p.lean, p.stance == .prone ? 0 : targetLean, dt * 5)
            let sprint = input.move.y > 0.92 && !p.aiming && p.stance == .stand && p.healing == nil
            moveActor(p, dt: dt, move: input.move, sprint: sprint)
            if input.fire {
                if p.slot == 3 {
                    if now - p.lastThrow > 1.0 { throwGrenade(p, dir: aimDirection()) }
                } else if p.weapon == nil {
                    melee(p)
                } else {
                    playerFire(p)
                }
            }
            if !input.fire { p.lastBolt = -10 }
        case .vehicle:
            if let v = p.vehicle {
                let impact = v.update(dt: dt, throttle: input.move.y, steerIn: input.move.x, col: col, terrain: terrain)
                if impact > 9 {
                    applyDamage(to: p, amount: (impact - 9) * 3, part: -1, from: nil, weaponName: "撞击", dir: V3(0, 0, 0))
                    v.hp -= impact * 8
                    hud.hapticHeavy += 1
                }
                p.pos = v.seatPos()
                p.moveSpeed = 0
                if v.hp <= 0 { destroyVehicle(v) }
            }
        case .dead:
            break
        }
    }

    func playerFire(_ p: Actor) {
        guard let w = p.weapon else { return }
        let st = w.stats
        let auto = w.auto && st.autoCapable
        if !auto {
            // semi-auto: one shot per press (allow hold for bolt rifles after interval)
            if p.lastBolt > 0 { return }
        }
        let fired = fire(p, dir: aimDirection())
        if fired && !auto { p.lastBolt = now }
    }

    /// Direction from the player's eye to whatever is under the crosshair.
    func aimDirection() -> V3 {
        let p = player!
        let d = dirFrom(yaw: p.yaw, pitch: p.pitch)
        let camP = cameraNode.simdPosition
        let far = camP + d * 900
        var target = far
        if let h = col.raycast(camP + d * 0.5, far) { target = h.p }
        // actors
        var best: Float = vlen(target - camP)
        for a in actors where a.alive && !a.isPlayer && vlen(a.pos - camP) < best + 2 {
            for s in a.hitSpheres() {
                if let t = raySphere(camP, d, s.0, s.1), t < best { best = t; target = camP + d * t }
            }
        }
        let origin = p.eye
        let dir = target - origin
        if vlen(dir) < 1.5 { return d }
        return vnorm(dir)
    }

    func raySphere(_ o: V3, _ d: V3, _ c: V3, _ r: Float) -> Float? {
        let oc = o - c
        let b = vdot(oc, d)
        let cc = vdot(oc, oc) - r * r
        let disc = b * b - cc
        if disc < 0 { return nil }
        let t = -b - sqrt(disc)
        return t > 0 ? t : nil
    }

    // MARK: generic movement for ground actors

    func moveActor(_ a: Actor, dt: Float, move: V2, sprint: Bool) {
        let f = flatForward(a.yaw), r = flatRight(a.yaw)
        var speed: Float
        switch a.stance {
        case .stand: speed = sprint ? 6.6 : 4.9
        case .crouch: speed = 2.9
        case .prone: speed = 1.15
        }
        if a.aiming { speed *= 0.6 }
        if a.healing != nil { speed = min(speed, 1.6) }
        if a.inWater { speed = 2.6 }
        if a.boost > 60 { speed *= 1.06 }
        let mlen = min(1, vlen2(move))
        let dirv = move.x * r + move.y * f
        var desired = mlen > 0.05 ? vnorm(dirv) * (speed * mlen) : V3(0, 0, 0)
        if move.y < -0.1 { desired *= 0.85 }
        let accel: Float = a.onGround ? 28 : 6
        a.vel.x = approachf(a.vel.x, desired.x, accel * dt)
        a.vel.z = approachf(a.vel.z, desired.z, accel * dt)
        if sprint && a.healing != nil { a.healing = nil }

        let wl = terrain.waterLevel
        let tH = terrain.height(a.pos.x, a.pos.z)
        a.inWater = tH < wl - 1.15 && a.pos.y < wl - 0.6
        if a.inWater {
            a.stance = .stand
            a.vel.y = 0
            a.pos.y = approachf(a.pos.y, wl - 1.3, dt * 3)
        } else {
            a.vel.y -= 9.8 * dt
        }
        let prevY = a.pos.y
        a.pos += a.vel * dt
        a.pos.x = clampf(a.pos.x, -795, 795)
        a.pos.z = clampf(a.pos.z, -795, 795)
        col.pushOut(&a.pos, radius: a.stance == .prone ? 0.45 : 0.32, height: a.height, stepUp: 0.5)
        // ceiling
        let ceil = col.ceiling(a.pos.x, a.pos.z, fromY: prevY + 0.6)
        if a.pos.y + a.height > ceil && a.vel.y > 0 {
            a.pos.y = ceil - a.height
            a.vel.y = 0
        }
        if !a.inWater {
            let ground = col.ground(a.pos.x, a.pos.z, feetY: a.pos.y, step: 0.55)
            if a.pos.y <= ground + 0.02 || (a.onGround && a.vel.y <= 0 && a.pos.y - ground < 0.6) {
                if !a.onGround {
                    let fall = a.fallStartY - ground
                    if fall > 5 {
                        applyDamage(to: a, amount: (fall - 5) * 9, part: -1, from: nil, weaponName: "坠落", dir: V3(0, 0, 0))
                    }
                }
                a.pos.y = ground
                a.vel.y = 0
                a.onGround = true
            } else {
                if a.onGround { a.fallStartY = a.pos.y }
                a.fallStartY = max(a.fallStartY, a.pos.y)
                a.onGround = false
            }
        } else {
            a.onGround = true
        }
        let hv = V2(a.vel.x, a.vel.z)
        a.moveSpeed = vlen2(hv)
        a.forwardSpeed = simd_dot(hv, V2(f.x, f.z))
        // footsteps
        if a.onGround && a.moveSpeed > 1.5 && a.stance != .prone {
            a.stepAcc += a.moveSpeed * dt
            let stride: Float = a.moveSpeed > 6 ? 1.7 : 1.45
            if a.stepAcc > stride {
                a.stepAcc = 0
                if (a.isPlayer || vlen(a.pos - player.pos) < 45), let au = audio {
                    let vol: Float = a.isPlayer ? 0.35 : (a.stance == .crouch ? 0.25 : 0.7)
                    au.play(terrain.kind == .snow ? "stepSnow" : "step", at: a.pos + V3(0, 0.1, 0), volume: vol, rate: Float.random(in: 0.85...1.15))
                }
            }
        }
    }

    // MARK: camera

    func updateCamera(dt: Float) {
        let p = spectate ?? player!
        let aimDir = dirFrom(yaw: p.yaw, pitch: p.pitch)
        var fov: Float = baseFov
        var scoped = false
        let wantAim = p.aiming && p.state == .ground
        aimBlend = approachf(aimBlend, wantAim ? 1 : 0, dt * 7)
        var showViewModel = false
        switch p.state {
        case .plane:
            let c = plan.position
            let back = dirFrom(yaw: p.yaw, pitch: min(p.pitch, 0.3) - 0.25)
            camPos = c - back * 48 + V3(0, 10, 0)
            cameraNode.simdPosition = camPos
            cameraNode.simdOrientation = simd_quatf(angle: p.yaw, axis: V3(0, 1, 0)) * simd_quatf(angle: min(p.pitch, 0.3) - 0.25, axis: V3(1, 0, 0))
            camera.fieldOfView = CGFloat(baseFov + 10)
            hud.scoped = false
            viewModel.isHidden = true
            return
        case .freefall, .chute:
            let piv = p.pos + V3(0, p.state == .chute ? 2.5 : 1.0, 0)
            let dist: Float = p.state == .chute ? 9 : 6
            var cp = piv - aimDir * dist + V3(0, 1.0, 0)
            let g = terrain.height(cp.x, cp.z)
            cp.y = max(cp.y, g + 0.5)
            camPos = cp
            fov = baseFov + (p.state == .freefall ? 8 : 4)
        case .vehicle:
            let piv = p.pos + V3(0, 1.6, 0)
            var cp = piv - aimDir * 6.5 + V3(0, 1.2, 0)
            if let h = col.raycast(piv, cp) { cp = piv + (cp - piv) * max(0.1, h.t - 0.05) }
            cp.y = max(cp.y, terrain.height(cp.x, cp.z) + 0.4)
            camPos = cp
            fov = baseFov + min(10, (p.vehicle?.speed ?? 0) * 0.3)
        case .ground, .dead:
            let scope = p.weapon?.scope ?? .iron
            let magnified = scope.magnified && aimBlend > 0.6 && p.state == .ground
            if magnified || fpp {
                camPos = p.eye + aimDir * 0.12
                if magnified {
                    scoped = true
                    fov = scope.aimFov
                } else {
                    fov = lerpf(baseFov + 5, scope.aimFov, aimBlend)
                    showViewModel = p.state == .ground && p.weapon != nil
                }
            } else {
                let right = flatRight(p.yaw)
                let shoulder: Float = 0.5 * (1 - aimBlend * 0.3) + p.lean * 0.4
                let piv = p.pos + V3(0, p.eyeHeight + 0.18, 0) + right * shoulder
                let dist: Float = lerpf(p.stance == .prone ? 2.4 : 2.9, 1.25, aimBlend)
                var cp = piv - aimDir * dist + V3(0, 0.15, 0)
                if let h = col.raycast(piv, cp) { cp = piv + (cp - piv) * max(0.05, h.t - 0.06) }
                cp.y = max(cp.y, terrain.height(cp.x, cp.z) + 0.25)
                if p.inWater { cp.y = max(cp.y, terrain.waterLevel + 0.3) }
                camPos = cp
                fov = lerpf(baseFov, scope == .iron ? 44 : scope.aimFov + 4, aimBlend)
            }
        }
        // shake & recoil
        camShake = max(0, camShake - dt * 2)
        recoilKick = approachf(recoilKick, 0, dt * 0.35)
        viewKick = approachf(viewKick, 0, dt * 6)
        var shake = V3(0, 0, 0)
        if camShake > 0 {
            shake = V3(Float.random(in: -1...1), Float.random(in: -1...1), 0) * camShake * 0.08
        }
        cameraNode.simdPosition = camPos + shake
        let roll: Float = -p.lean * 0.12
        cameraNode.simdOrientation = simd_quatf(angle: p.yaw, axis: V3(0, 1, 0)) * simd_quatf(angle: p.pitch, axis: V3(1, 0, 0)) * simd_quatf(angle: roll, axis: V3(0, 0, 1))
        camera.fieldOfView = CGFloat(fov)
        hud.scoped = scoped
        // view model
        viewModel.isHidden = !showViewModel
        if showViewModel, let w = p.weapon {
            let key = w.type.rawValue * 10 + w.scope.rawValue
            if key != viewGunKey {
                viewGunKey = key
                viewGun.geometry = Models.gun(w.type, scope: w.scope, assets: assets)
            }
            let hip = V3(0.17, -0.19, -0.42)
            let sightY: Float = w.scope == .iron ? -0.09 : (w.scope == .redDot ? -0.13 : -0.14)
            let ads = V3(0, sightY, -0.3)
            var vp = lerp3(hip, ads, aimBlend)
            vp.z += viewKick * 0.06
            vp.y += sin(now * 7) * 0.004 * min(1, p.moveSpeed / 4)
            viewModel.simdPosition = vp
            viewModel.simdEulerAngles = V3(viewKick * 0.15, 0, 0)
        }
    }

    // MARK: audio

    func updateAudio() {
        guard let au = audio else { return }
        let fwd = dirFrom(yaw: player.yaw, pitch: player.pitch)
        au.setListener(pos: cameraNode.simdPosition, forward: fwd)
        let st = player.state
        au.setLoop("wind", volume: st == .freefall ? 0.9 : (st == .chute ? 0.35 : 0.0))
        if let v = player.vehicle, st == .vehicle {
            au.setLoop("engine", volume: 0.35 + min(0.4, abs(v.speed) / 40), rate: 0.7 + abs(v.speed) / 30, at: v.pos)
        } else {
            au.setLoop("engine", volume: 0)
        }
        let planeD = vlen(plan.position - cameraNode.simdPosition)
        au.setLoop("plane", volume: plan.done ? 0 : (st == .plane ? 0.55 : max(0, 0.6 - planeD / 1200)), at: plan.position)
    }

    // MARK: HUD

    func buildHUD() {
        let p = player!
        var h = hud
        h.time = now
        h.health = p.health
        h.boost = p.boost
        h.alive = aliveCount
        h.kills = p.kills
        h.heading = headingDegrees(yaw: p.yaw)
        h.pos = V2(p.pos.x, p.pos.z)
        h.yaw = p.yaw
        h.zoneCenter = zone.center
        h.zoneRadius = zone.radius
        h.nextCenter = zone.nextCenter
        h.nextRadius = zone.nextRadius
        h.outsideZone = p.state != .plane && zone.outside(p.pos)
        if zone.finished {
            h.zoneText = "最终安全区"
        } else if zone.shrinking {
            h.zoneText = "安全区缩小中 \(fmtTime(zone.timer))"
        } else {
            h.zoneText = "安全区倒计时 \(fmtTime(zone.timer))"
        }
        switch p.state {
        case .plane: h.phase = .plane
        case .freefall: h.phase = .freefall
        case .chute: h.phase = .chute
        case .ground: h.phase = .ground
        case .vehicle: h.phase = .vehicle
        case .dead: h.phase = .dead
        }
        if won { h.phase = .won }
        for i in 0..<3 {
            var s = SlotInfo()
            if let w = p.inv.weapon(slot: i) {
                s.present = true
                s.name = w.stats.name
                s.mag = w.mag
                s.reserve = p.inv.ammo[w.stats.ammo.rawValue]
                s.scope = w.scope == .iron ? "" : w.scope.name
            }
            h.slots[i] = s
        }
        h.activeSlot = p.slot
        h.throwName = p.throwType.name
        h.throwCount = p.inv.throws[p.throwType.rawValue]
        if let w = p.weapon {
            h.fireAuto = w.auto && w.stats.autoCapable
            h.canAuto = w.stats.autoCapable
            h.scope = w.scope
        } else {
            h.canAuto = false
            h.scope = .iron
        }
        h.aiming = p.aiming
        if p.reloading, let w = p.weapon {
            h.reloadProgress = saturate((now - p.reloadStart) / max(0.1, p.reloadEnd - p.reloadStart))
            _ = w
        } else { h.reloadProgress = -1 }
        if let m = p.healing {
            h.healProgress = saturate((now - p.healStart) / m.useTime)
            h.healName = m.name
        } else { h.healProgress = -1 }
        // pickups nearby
        var ps: [PickupInfo] = []
        if p.state == .ground {
            let items = lootNear(p.pos, radius: 3.0).sorted { distXZ($0.pos, p.pos) < distXZ($1.pos, p.pos) }
            for it in items.prefix(8) {
                ps.append(PickupInfo(id: it.id, name: it.kind.name, count: it.count, tint: it.kind.tint, symbol: it.kind.symbol))
            }
        }
        h.pickups = ps
        h.canEnterVehicle = p.state == .ground && nearestVehicle(p) != nil
        h.vehicleSpeed = abs(p.vehicle?.speed ?? 0) * 3.6
        h.canJump = p.state == .plane && plan.overMap
        h.altitude = p.pos.y - terrain.height(p.pos.x, p.pos.z)
        h.feed = feed.filter { now - $0.time < 8 }
        h.helmet = p.inv.helmet
        h.vest = p.inv.vest
        h.bag = p.inv.bag
        h.helmetDur = p.inv.helmet > 0 ? p.inv.helmetHP / Armor.helmetDur[p.inv.helmet] : 0
        h.vestDur = p.inv.vest > 0 ? p.inv.vestHP / Armor.vestDur[p.inv.vest] : 0
        h.meds = p.inv.meds
        h.throws = p.inv.throws
        h.ammo = p.inv.ammo
        h.scopes = p.inv.scopes
        var spread: Float = 0
        if let w = p.weapon {
            spread = p.aiming ? w.stats.spreadAim : w.stats.spreadHip
            spread *= 1 + min(1, p.moveSpeed / 5)
            if p.stance == .crouch { spread *= 0.8 }
            if p.stance == .prone { spread *= 0.6 }
            spread += recoilKick * 0.5
        }
        h.spread = spread
        h.rank = p.rank
        h.killedBy = p.killerName.isEmpty ? "" : (p.killerWeapon.isEmpty ? p.killerName : "\(p.killerName) 使用 \(p.killerWeapon)")
        h.planeStart = V2(plan.start.x, plan.start.z)
        h.planeEnd = V2(plan.end.x, plan.end.z)
        h.planePos = V2(plan.position.x, plan.position.z)
        h.stance = p.stance
        h.fpp = fpp
        h.marker = marker
        h.inWater = p.inWater
        hud = h
    }
}
