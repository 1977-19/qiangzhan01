import SceneKit
import UIKit

extension GameWorld {

    @inline(__always) func lootKey(_ x: Float, _ z: Float) -> Int {
        let i = min(max(Int((x + 800) / 16), 0), 99)
        let j = min(max(Int((z + 800) / 16), 0), 99)
        return j * 100 + i
    }

    @discardableResult
    func addLoot(_ kind: ItemKind, _ count: Int, _ pos: V3, weapon: WeaponInst? = nil, crate: Int = -1) -> LootItem {
        let it = LootItem(id: nextLootId, kind: kind, count: count, pos: pos, weapon: weapon)
        it.crateId = crate
        nextLootId += 1
        loot[it.id] = it
        lootGrid[lootKey(pos.x, pos.z), default: []].append(it.id)
        return it
    }

    func removeLoot(_ it: LootItem) {
        it.taken = true
        loot[it.id] = nil
        let k = lootKey(it.pos.x, it.pos.z)
        lootGrid[k]?.removeAll { $0 == it.id }
        if let n = lootNodes[it.id] {
            n.removeFromParentNode()
            lootNodes[it.id] = nil
        }
        if it.crateId >= 0 {
            let cid = it.crateId
            let remaining = lootNear(it.pos, radius: 0.5).contains { $0.crateId == cid }
            if !remaining, let c = crates[cid] {
                c.node.removeFromParentNode()
                crates[cid] = nil
            }
        }
    }

    func lootNear(_ p: V3, radius: Float, dy: Float = 2.2) -> [LootItem] {
        var out: [LootItem] = []
        let i0 = max(0, Int(((p.x - radius + 800) / 16).rounded(.down)))
        let i1 = min(99, Int(((p.x + radius + 800) / 16).rounded(.down)))
        let j0 = max(0, Int(((p.z - radius + 800) / 16).rounded(.down)))
        let j1 = min(99, Int(((p.z + radius + 800) / 16).rounded(.down)))
        if i0 > i1 || j0 > j1 { return out }
        for j in j0...j1 {
            for i in i0...i1 {
                guard let ids = lootGrid[j * 100 + i] else { continue }
                for id in ids {
                    if let it = loot[id], !it.taken {
                        let d = distXZ(it.pos, p)
                        if d <= radius && abs(it.pos.y - p.y) < dy { out.append(it) }
                    }
                }
            }
        }
        return out
    }

    func spawnLoot() {
        var r = RNG(rng.next())
        for spot in data.loot {
            let chance: Float = spot.tier >= 3 ? 0.9 : (spot.tier == 2 ? 0.72 : 0.58)
            if !r.chance(chance) { continue }
            let rolls = spot.tier >= 3 ? 2 : 1
            var k = 0
            for _ in 0..<rolls {
                for (kind, count) in LootTable.roll(tier: spot.tier, rng: &r) {
                    let off = V3(r.r(-0.5, 0.5), 0, r.r(-0.5, 0.5)) + V3(Float(k) * 0.25, 0, 0)
                    addLoot(kind, count, spot.p + off)
                    k += 1
                }
            }
        }
        // a few loose items scattered near roads
        for _ in 0..<60 {
            let road = r.pick(data.roads)
            if road.isEmpty { continue }
            let q = road[r.i(road.count)] + V2(r.r(-6, 6), r.r(-6, 6))
            let y = terrain.height(q.x, q.y)
            if y < terrain.waterLevel + 0.3 { continue }
            for (kind, count) in LootTable.roll(tier: 1, rng: &r) {
                addLoot(kind, count, V3(q.x, y, q.y))
            }
        }
    }

    func makeLootNode(_ it: LootItem) -> SCNNode {
        let n = SCNNode(geometry: Models.lootGeometry(it.kind, assets: assets))
        n.simdPosition = it.pos + V3(0, 0.02, 0)
        var h = RNG(UInt64(it.id) &* 7919)
        let yaw = h.r(0, kTwoPi)
        switch it.kind {
        case .weapon:
            n.simdOrientation = simd_quatf(angle: yaw, axis: V3(0, 1, 0)) * simd_quatf(angle: kPi / 2, axis: V3(0, 0, 1))
            n.simdPosition = it.pos + V3(0, 0.05, 0)
        default:
            n.simdOrientation = simd_quatf(angle: yaw, axis: V3(0, 1, 0))
        }
        n.castsShadow = true
        return n
    }

    func updateLootVisibility() {
        let c = cameraNode.simdPosition
        let near = lootNear(c, radius: 70, dy: 60)
        var want = Set<Int>()
        for it in near where it.crateId < 0 {
            want.insert(it.id)
            if lootNodes[it.id] == nil {
                let n = makeLootNode(it)
                lootRoot.addChildNode(n)
                lootNodes[it.id] = n
            }
        }
        for (id, n) in lootNodes where !want.contains(id) {
            n.removeFromParentNode()
            lootNodes[id] = nil
        }
        // auto pickup for the player
        let p = player!
        if p.state == .ground && p.alive {
            for it in lootNear(p.pos, radius: 1.9) where p.inv.wantsAuto(it.kind) {
                pick(p, it, explicit: false)
            }
        }
    }

    // MARK: inventory operations

    func pick(_ a: Actor, _ it: LootItem, explicit: Bool) {
        guard !it.taken else { return }
        let inv = a.inv
        var picked = true
        switch it.kind {
        case .weapon(let wt):
            let w = it.weapon ?? WeaponInst(wt, mag: 0)
            if w.stats.isPistol {
                if let old = inv.pistol {
                    if !explicit { return }
                    addLoot(.weapon(old.type), 1, a.pos + V3(0, 0.02, 0), weapon: old)
                }
                inv.pistol = w
                if a.slot == -1 { a.slot = 2 }
            } else {
                var s = inv.primary[0] == nil ? 0 : (inv.primary[1] == nil ? 1 : -1)
                if s == -1 {
                    if !explicit { return }
                    s = (a.slot == 0 || a.slot == 1) ? a.slot : 0
                    if let old = inv.primary[s] {
                        if old.scope != .iron {
                            inv.scopes[old.scope.rawValue] += 1
                            old.scope = .iron
                        }
                        addLoot(.weapon(old.type), 1, a.pos + V3(0, 0.02, 0), weapon: old)
                    }
                }
                inv.primary[s] = w
                if a.slot == -1 || a.slot == 2 || a.slot == 3 { a.slot = s }
            }
            inv.autoMountScopes()
            removeLoot(it)
        case .ammo(let t):
            let n = inv.room(for: it.kind, count: it.count)
            if n <= 0 { picked = false; break }
            inv.ammo[t.rawValue] += n
            it.count -= n
            if it.count <= 0 { removeLoot(it) }
        case .med(let m):
            let n = inv.room(for: it.kind, count: it.count)
            if n <= 0 { picked = false; break }
            inv.meds[m.rawValue] += n
            it.count -= n
            if it.count <= 0 { removeLoot(it) }
        case .throwable(let t):
            let n = inv.room(for: it.kind, count: it.count)
            if n <= 0 { picked = false; break }
            inv.throwables[t.rawValue] += n
            it.count -= n
            if it.count <= 0 { removeLoot(it) }
        case .scope(let s):
            inv.scopes[s.rawValue] += it.count
            inv.autoMountScopes()
            removeLoot(it)
        case .helmet(let l):
            if !explicit && l <= inv.helmet { return }
            if inv.helmet > 0 { addLoot(.helmet(inv.helmet), 1, a.pos + V3(0, 0.02, 0)) }
            inv.helmet = l
            inv.helmetHP = Armor.helmetDur[l]
            removeLoot(it)
        case .vest(let l):
            if !explicit && l <= inv.vest { return }
            if inv.vest > 0 { addLoot(.vest(inv.vest), 1, a.pos + V3(0, 0.02, 0)) }
            inv.vest = l
            inv.vestHP = Armor.vestDur[l]
            removeLoot(it)
        case .bag(let l):
            if !explicit && l <= inv.bag { return }
            if inv.bag > 0 { addLoot(.bag(inv.bag), 1, a.pos + V3(0, 0.02, 0)) }
            inv.bag = l
            removeLoot(it)
        }
        if a.isPlayer {
            if picked {
                audio?.playUI("pickup", volume: 0.35)
            } else if explicit {
                message("背包空间不足")
            }
        }
        if a.slot == -1, inv.hasAnyWeapon {
            a.slot = inv.primary[0] != nil ? 0 : (inv.primary[1] != nil ? 1 : 2)
        }
    }

    func drop(_ a: Actor, _ kind: ItemKind) {
        let inv = a.inv
        let p = a.pos + flatForward(a.yaw) * 0.6 + V3(rng.r(-0.3, 0.3), 0.02, rng.r(-0.3, 0.3))
        switch kind {
        case .ammo(let t):
            if inv.ammo[t.rawValue] > 0 { addLoot(kind, inv.ammo[t.rawValue], p); inv.ammo[t.rawValue] = 0 }
        case .med(let m):
            if inv.meds[m.rawValue] > 0 { addLoot(kind, inv.meds[m.rawValue], p); inv.meds[m.rawValue] = 0 }
        case .throwable(let t):
            if inv.throwables[t.rawValue] > 0 { addLoot(kind, inv.throwables[t.rawValue], p); inv.throwables[t.rawValue] = 0 }
        case .scope(let s):
            if inv.scopes[s.rawValue] > 0 { addLoot(kind, 1, p); inv.scopes[s.rawValue] -= 1 }
        case .helmet:
            if inv.helmet > 0 { addLoot(.helmet(inv.helmet), 1, p); inv.helmet = 0; inv.helmetHP = 0 }
        case .vest:
            if inv.vest > 0 { addLoot(.vest(inv.vest), 1, p); inv.vest = 0; inv.vestHP = 0 }
        case .bag:
            if inv.bag > 0 { addLoot(.bag(inv.bag), 1, p); inv.bag = 0 }
        case .weapon:
            break
        }
    }

    func dropWeapon(_ a: Actor, slot: Int) {
        let inv = a.inv
        let p = a.pos + flatForward(a.yaw) * 0.7 + V3(0, 0.02, 0)
        if slot == 2, let w = inv.pistol {
            addLoot(.weapon(w.type), 1, p, weapon: w)
            inv.pistol = nil
        } else if slot == 0 || slot == 1, let w = inv.primary[slot] {
            if w.scope != .iron { inv.scopes[w.scope.rawValue] += 1; w.scope = .iron }
            addLoot(.weapon(w.type), 1, p, weapon: w)
            inv.primary[slot] = nil
        }
        if a.slot == slot { a.slot = -1 }
        a.reloading = false
    }

    func dropCrate(for a: Actor) {
        let items = a.inv.dumpAll()
        if items.isEmpty { return }
        let cid = a.id + 10000
        let p = V3(a.pos.x, a.pos.y, a.pos.z)
        let n = SCNNode(geometry: Models.crate(assets: assets))
        n.simdPosition = p
        n.simdOrientation = simd_quatf(angle: a.yaw, axis: V3(0, 1, 0))
        n.castsShadow = true
        lootRoot.addChildNode(n)
        crates[cid] = (pos: p, node: n)
        for (k, c, w) in items {
            addLoot(k, c, p + V3(0, 0.3, 0), weapon: w, crate: cid)
        }
        let fresh = Inventory()
        a.inv.primary = fresh.primary
        a.inv.pistol = nil
        a.inv.ammo = fresh.ammo
        a.inv.meds = fresh.meds
        a.inv.throwables = fresh.throwables
        a.inv.scopes = fresh.scopes
        a.inv.helmet = 0
        a.inv.vest = 0
        a.inv.bag = 0
        a.slot = -1
        a.rig.setGun(nil, assets: assets)
    }
}
