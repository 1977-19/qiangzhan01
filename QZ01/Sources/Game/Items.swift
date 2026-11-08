import Foundation
import UIKit

enum AmmoType: Int, CaseIterable {
    case a556 = 0, a762, a9, a12
    var name: String {
        switch self {
        case .a556: return "5.56mm"
        case .a762: return "7.62mm"
        case .a9: return "9mm"
        case .a12: return "12号霰弹"
        }
    }
    var pickupAmount: Int {
        switch self {
        case .a12: return 10
        default: return 30
        }
    }
}

enum WeaponType: Int, CaseIterable {
    case m416 = 0, akm, uzi, kar98k, s12k, p92
}

enum ScopeType: Int, CaseIterable {
    case iron = 0, redDot, x2, x4, x8
    var name: String {
        switch self {
        case .iron: return "机瞄"
        case .redDot: return "红点瞄准镜"
        case .x2: return "2倍镜"
        case .x4: return "4倍镜"
        case .x8: return "8倍镜"
        }
    }
    /// Vertical field of view (degrees) when aiming
    var aimFov: Float {
        switch self {
        case .iron: return 40
        case .redDot: return 38
        case .x2: return 23
        case .x4: return 11.5
        case .x8: return 5.8
        }
    }
    var magnified: Bool { return rawValue >= ScopeType.x2.rawValue }
}

enum MedType: Int, CaseIterable {
    case bandage = 0, firstAid, medkit, drink
    var name: String {
        switch self {
        case .bandage: return "绷带"
        case .firstAid: return "急救包"
        case .medkit: return "医疗箱"
        case .drink: return "能量饮料"
        }
    }
    var useTime: Float {
        switch self {
        case .bandage: return 3
        case .firstAid: return 6
        case .medkit: return 8
        case .drink: return 4
        }
    }
}

enum ThrowType: Int, CaseIterable {
    case frag = 0, smoke
    var name: String { return self == .frag ? "破片手榴弹" : "烟雾弹" }
}

struct WeaponStats {
    let name: String
    let ammo: AmmoType
    let damage: Float
    let interval: Float
    let mag: Int
    let speed: Float
    let autoCapable: Bool
    let pellets: Int
    let spreadHip: Float
    let spreadAim: Float
    let recoilUp: Float
    let recoilSide: Float
    let reload: Float
    let isPistol: Bool
    let sound: Int
    let falloffStart: Float
    let muzzleZ: Float

    static let all: [WeaponStats] = [
        WeaponStats(name: "M416", ammo: .a556, damage: 41, interval: 0.086, mag: 30, speed: 880, autoCapable: true, pellets: 1,
                    spreadHip: 0.045, spreadAim: 0.004, recoilUp: 0.009, recoilSide: 0.004, reload: 2.2, isPistol: false, sound: 0,
                    falloffStart: 150, muzzleZ: -0.78),
        WeaponStats(name: "AKM", ammo: .a762, damage: 47, interval: 0.1, mag: 30, speed: 715, autoCapable: true, pellets: 1,
                    spreadHip: 0.05, spreadAim: 0.006, recoilUp: 0.014, recoilSide: 0.007, reload: 2.5, isPistol: false, sound: 1,
                    falloffStart: 140, muzzleZ: -0.82),
        WeaponStats(name: "UZI", ammo: .a9, damage: 26, interval: 0.048, mag: 25, speed: 350, autoCapable: true, pellets: 1,
                    spreadHip: 0.04, spreadAim: 0.01, recoilUp: 0.005, recoilSide: 0.004, reload: 2.0, isPistol: false, sound: 2,
                    falloffStart: 40, muzzleZ: -0.36),
        WeaponStats(name: "Kar98k", ammo: .a762, damage: 79, interval: 1.6, mag: 5, speed: 760, autoCapable: false, pellets: 1,
                    spreadHip: 0.06, spreadAim: 0.0005, recoilUp: 0.04, recoilSide: 0.002, reload: 3.6, isPistol: false, sound: 3,
                    falloffStart: 400, muzzleZ: -0.98),
        WeaponStats(name: "S12K", ammo: .a12, damage: 22, interval: 0.25, mag: 5, speed: 360, autoCapable: false, pellets: 9,
                    spreadHip: 0.07, spreadAim: 0.05, recoilUp: 0.03, recoilSide: 0.01, reload: 3.0, isPistol: false, sound: 4,
                    falloffStart: 15, muzzleZ: -0.8),
        WeaponStats(name: "P92", ammo: .a9, damage: 35, interval: 0.14, mag: 15, speed: 380, autoCapable: false, pellets: 1,
                    spreadHip: 0.035, spreadAim: 0.008, recoilUp: 0.012, recoilSide: 0.005, reload: 1.6, isPistol: true, sound: 5,
                    falloffStart: 30, muzzleZ: -0.17),
    ]

    static func of(_ t: WeaponType) -> WeaponStats { return all[t.rawValue] }
}

final class WeaponInst {
    let type: WeaponType
    var mag: Int
    var scope: ScopeType
    var auto: Bool
    var stats: WeaponStats { return WeaponStats.of(type) }

    init(_ type: WeaponType, mag: Int? = nil, scope: ScopeType = .iron) {
        self.type = type
        let st = WeaponStats.of(type)
        self.mag = mag ?? 0
        self.scope = scope
        self.auto = st.autoCapable
    }
}

enum ItemKind: Equatable {
    case weapon(WeaponType)
    case ammo(AmmoType)
    case scope(ScopeType)
    case helmet(Int)
    case vest(Int)
    case bag(Int)
    case med(MedType)
    case throwable(ThrowType)

    var name: String {
        switch self {
        case .weapon(let w): return WeaponStats.of(w).name
        case .ammo(let a): return a.name
        case .scope(let s): return s.name
        case .helmet(let l): return "头盔(\(l)级)"
        case .vest(let l): return "防弹衣(\(l)级)"
        case .bag(let l): return "背包(\(l)级)"
        case .med(let m): return m.name
        case .throwable(let t): return t.name
        }
    }

    var symbol: String {
        switch self {
        case .weapon: return "scope"
        case .ammo: return "circle.grid.3x3.fill"
        case .scope: return "binoculars.fill"
        case .helmet: return "shield.lefthalf.filled"
        case .vest: return "shield.fill"
        case .bag: return "bag.fill"
        case .med: return "cross.case.fill"
        case .throwable: return "circle.circle.fill"
        }
    }

    var tint: UIColor {
        switch self {
        case .weapon: return UIColor(red: 1.0, green: 0.85, blue: 0.4, alpha: 1)
        case .ammo: return UIColor(red: 0.85, green: 0.8, blue: 0.5, alpha: 1)
        case .scope: return UIColor(red: 0.6, green: 0.85, blue: 1.0, alpha: 1)
        case .helmet(let l), .vest(let l), .bag(let l):
            return l >= 3 ? UIColor(red: 0.85, green: 0.5, blue: 1.0, alpha: 1) : (l == 2 ? UIColor(red: 0.45, green: 0.75, blue: 1.0, alpha: 1) : UIColor(white: 0.9, alpha: 1))
        case .med: return UIColor(red: 0.5, green: 1.0, blue: 0.6, alpha: 1)
        case .throwable: return UIColor(red: 1.0, green: 0.6, blue: 0.4, alpha: 1)
        }
    }
}

/// An item lying in the world.
final class LootItem {
    let id: Int
    var kind: ItemKind
    var count: Int
    var pos: V3
    var weapon: WeaponInst?
    var taken = false
    var crateId: Int = -1

    init(id: Int, kind: ItemKind, count: Int, pos: V3, weapon: WeaponInst? = nil) {
        self.id = id
        self.kind = kind
        self.count = count
        self.pos = pos
        self.weapon = weapon
    }
}

enum LootTable {
    static func roll(tier: Int, rng: inout RNG) -> [(ItemKind, Int)] {
        var out: [(ItemKind, Int)] = []
        let r = rng.f()
        let t = Float(tier)
        if r < 0.30 + t * 0.05 {
            // weapon + ammo
            let x = rng.f()
            let table: [(Float, WeaponType)]
            if tier >= 3 {
                table = [(0.35, .m416), (0.62, .akm), (0.85, .kar98k), (0.93, .s12k), (1.01, .uzi)]
            } else if tier == 2 {
                table = [(0.28, .m416), (0.50, .akm), (0.66, .uzi), (0.78, .s12k), (0.88, .kar98k), (1.01, .p92)]
            } else {
                table = [(0.18, .m416), (0.34, .akm), (0.56, .uzi), (0.72, .s12k), (0.78, .kar98k), (1.01, .p92)]
            }
            var w: WeaponType = .p92
            for e in table where x < e.0 {
                w = e.1
                break
            }
            out.append((.weapon(w), 1))
            let a = WeaponStats.of(w).ammo
            out.append((.ammo(a), a.pickupAmount))
        } else if r < 0.52 + t * 0.03 {
            let a = AmmoType(rawValue: rng.i(4)) ?? .a556
            out.append((.ammo(a), a.pickupAmount))
        } else if r < 0.68 {
            let lvl = rollLevel(tier, &rng)
            let k = rng.i(3)
            let item: ItemKind = k == 0 ? .helmet(lvl) : (k == 1 ? .vest(lvl) : .bag(lvl))
            out.append((item, 1))
        } else if r < 0.84 {
            let m = rng.f()
            if m < 0.5 { out.append((.med(.bandage), 5)) }
            else if m < 0.78 { out.append((.med(.firstAid), 1)) }
            else if m < 0.88 { out.append((.med(.medkit), 1)) }
            else { out.append((.med(.drink), 1)) }
        } else if r < 0.93 {
            let s = rng.f()
            var st: ScopeType = .x8
            if s < 0.35 { st = .redDot } else if s < 0.65 { st = .x2 } else if s < 0.9 { st = .x4 }
            out.append((.scope(st), 1))
        } else {
            let tt: ThrowType = rng.chance(0.65) ? .frag : .smoke
            out.append((ItemKind.throwable(tt), 1))
        }
        return out
    }

    static func rollLevel(_ tier: Int, _ rng: inout RNG) -> Int {
        let x = rng.f()
        switch tier {
        case 3: return x < 0.35 ? 1 : (x < 0.8 ? 2 : 3)
        case 2: return x < 0.55 ? 1 : (x < 0.92 ? 2 : 3)
        default: return x < 0.75 ? 1 : (x < 0.97 ? 2 : 3)
        }
    }
}

enum Armor {
    static let helmetDur: [Float] = [0, 80, 150, 230]
    static let vestDur: [Float] = [0, 200, 220, 250]
    static let reduce: [Float] = [0, 0.30, 0.40, 0.55]
}

final class Inventory {
    var primary: [WeaponInst?] = [nil, nil]
    var pistol: WeaponInst?
    var ammo = [Int](repeating: 0, count: 4)
    var meds = [Int](repeating: 0, count: 4)
    var throwables = [0, 0]
    var scopes = [Int](repeating: 0, count: 5)
    var helmet = 0
    var vest = 0
    var bag = 0
    var helmetHP: Float = 0
    var vestHP: Float = 0

    func maxAmmo(_ t: AmmoType) -> Int {
        let base: [Int] = [150, 120, 150, 30]
        let per: [Int] = [60, 50, 60, 15]
        return base[t.rawValue] + per[t.rawValue] * bag
    }
    func maxMed(_ m: MedType) -> Int {
        switch m {
        case .bandage: return 10 + bag * 5
        case .firstAid: return 3 + bag
        case .medkit: return 1 + bag / 2
        case .drink: return 3 + bag
        }
    }
    func maxThrow() -> Int { return 3 + bag }

    func weapon(slot: Int) -> WeaponInst? {
        switch slot {
        case 0, 1: return primary[slot]
        case 2: return pistol
        default: return nil
        }
    }

    var hasAnyWeapon: Bool { return primary[0] != nil || primary[1] != nil || pistol != nil }

    /// How many of `count` of this item can be added (0 = can't).
    func room(for kind: ItemKind, count: Int) -> Int {
        switch kind {
        case .ammo(let a): return max(0, min(count, maxAmmo(a) - ammo[a.rawValue]))
        case .med(let m): return max(0, min(count, maxMed(m) - meds[m.rawValue]))
        case .throwable(let t): return max(0, min(count, maxThrow() - throwables[t.rawValue]))
        case .scope: return 1
        case .helmet, .vest, .bag, .weapon: return 1
        }
    }

    /// Is this item an obvious upgrade worth auto-picking?
    func wantsAuto(_ kind: ItemKind) -> Bool {
        switch kind {
        case .ammo(let a):
            let usedBy = [primary[0], primary[1], pistol].compactMap { $0 }.contains { $0.stats.ammo == a }
            return usedBy && ammo[a.rawValue] < maxAmmo(a)
        case .med(let m): return meds[m.rawValue] < maxMed(m)
        case .throwable(let t): return throwables[t.rawValue] < maxThrow()
        case .helmet(let l): return l > helmet
        case .vest(let l): return l > vest
        case .bag(let l): return l > bag
        case .scope(let s):
            let ws = [primary[0], primary[1]].compactMap { $0 }
            return ws.contains { $0.scope.rawValue < s.rawValue } && scopes[s.rawValue] == 0
        case .weapon(let w):
            let st = WeaponStats.of(w)
            if st.isPistol { return pistol == nil }
            return primary[0] == nil || primary[1] == nil
        }
    }

    /// Fit best available scope on weapons that lack one.
    func autoMountScopes() {
        for i in 0..<2 {
            guard let w = primary[i] else { continue }
            var best = w.scope.rawValue
            var bestIdx = -1
            for s in stride(from: 4, through: 1, by: -1) where scopes[s] > 0 && s > best {
                // prefer 8x/4x for Kar98k, red dot/2x for close weapons
                if w.type == .uzi || w.type == .s12k {
                    if s > ScopeType.x2.rawValue { continue }
                }
                best = s
                bestIdx = s
                break
            }
            if bestIdx > 0 {
                if w.scope != .iron { scopes[w.scope.rawValue] += 1 }
                scopes[bestIdx] -= 1
                w.scope = ScopeType(rawValue: bestIdx) ?? .iron
            }
        }
    }

    func dumpAll() -> [(ItemKind, Int, WeaponInst?)] {
        var out: [(ItemKind, Int, WeaponInst?)] = []
        for w in [primary[0], primary[1], pistol].compactMap({ $0 }) {
            out.append((.weapon(w.type), 1, w))
        }
        for a in AmmoType.allCases where ammo[a.rawValue] > 0 { out.append((.ammo(a), ammo[a.rawValue], nil)) }
        for m in MedType.allCases where meds[m.rawValue] > 0 { out.append((.med(m), meds[m.rawValue], nil)) }
        for t in ThrowType.allCases where throwables[t.rawValue] > 0 { out.append((.throwable(t), throwables[t.rawValue], nil)) }
        for s in ScopeType.allCases where s != .iron && scopes[s.rawValue] > 0 { out.append((.scope(s), scopes[s.rawValue], nil)) }
        if helmet > 0 { out.append((.helmet(helmet), 1, nil)) }
        if vest > 0 { out.append((.vest(vest), 1, nil)) }
        if bag > 0 { out.append((.bag(bag), 1, nil)) }
        return out
    }
}
