import SceneKit
import simd

/// Loot spot inside the world.
struct LootSpot {
    var p: V3
    var tier: Int
}

/// Entrance waypoints used by AI to walk into buildings.
struct DoorWay {
    var outside: V3
    var inside: V3
}

enum BType: Int {
    case house1, house2, warehouse, cabin, barracks, tower, container, radar, shed

    /// half extents of footprint (local x, local z) incl. margin
    var halfSize: V2 {
        switch self {
        case .house1: return V2(5.0, 4.0)
        case .house2: return V2(5.5, 4.5)
        case .warehouse: return V2(11.5, 7.5)
        case .cabin: return V2(3.6, 3.2)
        case .barracks: return V2(8.5, 3.6)
        case .tower: return V2(2.0, 2.0)
        case .container: return V2(3.2, 1.4)
        case .radar: return V2(5.0, 5.0)
        case .shed: return V2(3.2, 2.6)
        }
    }
}

/// Helper that maps local building coordinates (x right, z towards the front door, y up)
/// into world space with a quarter-turn rotation and records meshes, colliders and loot.
final class BuildCtx {
    let hi: MeshBuilder
    let lo: MeshBuilder
    let col: CollisionWorld
    let o: V3
    let rot: Int
    let tier: Int
    var loot: [LootSpot] = []
    var doors: [DoorWay] = []

    init(hi: MeshBuilder, lo: MeshBuilder, col: CollisionWorld, origin: V3, rot: Int, tier: Int) {
        self.hi = hi
        self.lo = lo
        self.col = col
        self.o = origin
        self.rot = rot
        self.tier = tier
    }

    @inline(__always) func w(_ x: Float, _ y: Float, _ z: Float) -> V3 {
        let r = rotQ(x, z, rot)
        return V3(o.x + r.0, o.y + y, o.z + r.1)
    }

    func box(_ x0: Float, _ y0: Float, _ z0: Float, _ x1: Float, _ y1: Float, _ z1: Float, _ mat: Mt,
             collide: Bool = true, kind: SurfaceKind = .concrete, lod: Bool = true) {
        let a = w(x0, y0, z0), b = w(x1, y1, z1)
        let mn = simd_min(a, b), mx = simd_max(a, b)
        hi.box(mat.rawValue, min: mn, max: mx)
        if lod { lo.box(mat.rawValue, min: mn, max: mx) }
        if collide { col.addBox(mn, mx, kind: kind) }
    }

    /// Wall along local X at local z (centre of thickness). openings: (xa, xb, ya, yb) relative to wall base.
    func wallX(_ x0: Float, _ x1: Float, z: Float, t: Float, y0: Float, h: Float,
               openings: [(Float, Float, Float, Float)], _ mat: Mt, kind: SurfaceKind = .concrete) {
        let ops = openings.sorted { $0.0 < $1.0 }
        var cur = x0
        for op in ops {
            let a = max(op.0, x0), b = min(op.1, x1)
            if a > cur { box(cur, y0, z - t / 2, a, y0 + h, z + t / 2, mat, kind: kind) }
            if op.2 > 0.01 { box(a, y0, z - t / 2, b, y0 + op.2, z + t / 2, mat, kind: kind) }
            if op.3 < h - 0.01 { box(a, y0 + op.3, z - t / 2, b, y0 + h, z + t / 2, mat, kind: kind) }
            cur = b
        }
        if cur < x1 { box(cur, y0, z - t / 2, x1, y0 + h, z + t / 2, mat, kind: kind) }
    }

    /// Wall along local Z at local x.
    func wallZ(_ z0: Float, _ z1: Float, x: Float, t: Float, y0: Float, h: Float,
               openings: [(Float, Float, Float, Float)], _ mat: Mt, kind: SurfaceKind = .concrete) {
        let ops = openings.sorted { $0.0 < $1.0 }
        var cur = z0
        for op in ops {
            let a = max(op.0, z0), b = min(op.1, z1)
            if a > cur { box(x - t / 2, y0, cur, x + t / 2, y0 + h, a, mat, kind: kind) }
            if op.2 > 0.01 { box(x - t / 2, y0, a, x + t / 2, y0 + op.2, b, mat, kind: kind) }
            if op.3 < h - 0.01 { box(x - t / 2, y0 + op.3, a, x + t / 2, y0 + h, b, mat, kind: kind) }
            cur = b
        }
        if cur < z1 { box(x - t / 2, y0, cur, x + t / 2, y0 + h, z1, mat, kind: kind) }
    }

    /// Quad whose facing is chosen so its normal points along `hint` (world space).
    func quadFacing(_ mat: Mt, _ a: V3, _ b: V3, _ c: V3, _ d: V3, hint: V3, uvScale: Float = 1, both: Bool = false, lodToo: Bool = true) {
        var p = [a, b, c, d]
        var n = vnorm(vcross(b - a, c - a))
        if vdot(n, hint) < 0 {
            p = [a, d, c, b]
            n = -n
        }
        // planar UVs
        let up = abs(n.y) > 0.9 ? V3(0, 0, -1) : V3(0, 1, 0)
        let ua = vnorm(vcross(up, n)), va = vcross(n, ua)
        let t = p.map { V2(vdot($0, ua) * uvScale, -vdot($0, va) * uvScale) }
        hi.quad(mat.rawValue, p[0], p[1], p[2], p[3], n, t[0], t[1], t[2], t[3])
        if lodToo { lo.quad(mat.rawValue, p[0], p[1], p[2], p[3], n, t[0], t[1], t[2], t[3]) }
        if both {
            hi.quad(mat.rawValue, p[0], p[3], p[2], p[1], -n, t[0], t[3], t[2], t[1])
        }
    }

    func triFacing(_ mat: Mt, _ a: V3, _ b: V3, _ c: V3, hint: V3) {
        var p = [a, b, c]
        var n = vnorm(vcross(b - a, c - a))
        if vdot(n, hint) < 0 { p = [a, c, b]; n = -n }
        let up = V3(0, 1, 0)
        let ua = vnorm(vcross(up, n)), va = vcross(n, ua)
        let t = p.map { V2(vdot($0, ua), -vdot($0, va)) }
        hi.tri(mat.rawValue, p[0], p[1], p[2], t[0], t[1], t[2], smoothN: n)
        lo.tri(mat.rawValue, p[0], p[1], p[2], t[0], t[1], t[2], smoothN: n)
    }

    /// Gable roof with ridge along local X. Includes gable-end triangles and an underside.
    func gable(_ x0: Float, _ x1: Float, _ z0: Float, _ z1: Float, base: Float, rise: Float, _ mat: Mt, endMat: Mt) {
        let zm = (z0 + z1) * 0.5
        let rA = w(x0, base + rise, zm), rB = w(x1, base + rise, zm)
        let f0 = w(x0, base, z1), f1 = w(x1, base, z1)
        let b0 = w(x0, base, z0), b1 = w(x1, base, z0)
        let up = V3(0, 1, 0)
        let frontOut = w(0, 0, 1) - w(0, 0, 0)
        let backOut = w(0, 0, -1) - w(0, 0, 0)
        quadFacing(mat, f0, f1, rB, rA, hint: up + frontOut * 0.5, uvScale: 1)
        quadFacing(mat, b0, b1, rB, rA, hint: up + backOut * 0.5, uvScale: 1)
        // underside (visible from inside)
        quadFacing(.plasterA, f0, f1, rB, rA, hint: -(up + frontOut * 0.5), lodToo: false)
        quadFacing(.plasterA, b0, b1, rB, rA, hint: -(up + backOut * 0.5), lodToo: false)
        // gable ends (slightly inset)
        let leftOut = w(-1, 0, 0) - w(0, 0, 0)
        let rightOut = w(1, 0, 0) - w(0, 0, 0)
        let i0 = x0 + 0.4, i1 = x1 - 0.4
        triFacing(endMat, w(i0, base, z0 + 0.4), w(i0, base, z1 - 0.4), w(i0, base + rise - 0.25, zm), hint: leftOut)
        triFacing(endMat, w(i1, base, z0 + 0.4), w(i1, base, z1 - 0.4), w(i1, base + rise - 0.25, zm), hint: rightOut)
        triFacing(.plasterA, w(i0, base, z0 + 0.4), w(i0, base, z1 - 0.4), w(i0, base + rise - 0.25, zm), hint: rightOut)
        triFacing(.plasterA, w(i1, base, z0 + 0.4), w(i1, base, z1 - 0.4), w(i1, base + rise - 0.25, zm), hint: leftOut)
    }

    func lootAt(_ x: Float, _ y: Float, _ z: Float) {
        loot.append(LootSpot(p: w(x, y + 0.02, z), tier: tier))
    }

    func door(outside: (Float, Float), inside: (Float, Float), y: Float) {
        doors.append(DoorWay(outside: w(outside.0, y, outside.1), inside: w(inside.0, y, inside.1)))
    }
}

enum Buildings {
    struct Style {
        var wall: Mt
        var roof: Mt
        var flatRoof: Bool
    }

    static func build(_ type: BType, ctx c: BuildCtx, style s: Style, rng: inout RNG) {
        switch type {
        case .house1: house1(c, s, &rng)
        case .house2: house2(c, s, &rng)
        case .warehouse: warehouse(c, &rng)
        case .cabin: cabin(c, s, &rng)
        case .barracks: barracks(c, s, &rng)
        case .tower: tower(c)
        case .container: container(c, &rng)
        case .radar: radar(c)
        case .shed: shed(c, s)
        }
    }

    static func foundation(_ c: BuildCtx, hx: Float, hz: Float, top: Float) {
        c.box(-hx, -2.2, -hz, hx, top, hz, .concreteDark, kind: .concrete)
    }

    static func furniture(_ c: BuildCtx, x: Float, z: Float, y: Float, rng: inout RNG) {
        // table or shelf: small cover objects
        if rng.chance(0.5) {
            c.box(x - 0.6, y, z - 0.4, x + 0.6, y + 0.75, z + 0.4, .wood, kind: .wood, lod: false)
        } else {
            c.box(x - 0.25, y, z - 0.6, x + 0.25, y + 1.8, z + 0.6, .woodDark, kind: .wood, lod: false)
        }
    }

    static func house1(_ c: BuildCtx, _ s: Style, _ rng: inout RNG) {
        let hx: Float = 4.5, hz: Float = 3.5, t: Float = 0.25, f: Float = 0.3, h: Float = 2.9
        foundation(c, hx: hx + 0.2, hz: hz + 0.2, top: f)
        c.box(-hx + t, f, -hz + t, hx - t, f + 0.02, hz - t, .floorTile, collide: false, lod: false)
        c.wallX(-hx, hx, z: hz - t / 2, t: t, y0: f, h: h, openings: [(-0.6, 0.6, 0, 2.2), (2.0, 3.3, 0.9, 2.0), (-3.4, -2.1, 0.9, 2.0)], s.wall)
        c.wallX(-hx, hx, z: -hz + t / 2, t: t, y0: f, h: h, openings: [(-2.6, -1.3, 0.9, 2.0), (1.3, 2.6, 0.9, 2.0)], s.wall)
        c.wallZ(-hz + t, hz - t, x: -hx + t / 2, t: t, y0: f, h: h, openings: [(-1.0, 0.5, 0.9, 2.0)], s.wall)
        c.wallZ(-hz + t, hz - t, x: hx - t / 2, t: t, y0: f, h: h, openings: [(-0.6, 0.9, 0.9, 2.0)], s.wall)
        // interior wall with door
        c.wallZ(-hz + t, hz - t, x: 1.2, t: 0.15, y0: f, h: h, openings: [(0.4, 1.4, 0, 2.15)], .plasterA)
        // ceiling slab
        c.box(-hx, f + h, -hz, hx, f + h + 0.2, hz, .concreteDark)
        let top = f + h + 0.2
        if s.flatRoof {
            c.wallX(-hx, hx, z: hz - 0.1, t: 0.2, y0: top, h: 0.6, openings: [], s.wall)
            c.wallX(-hx, hx, z: -hz + 0.1, t: 0.2, y0: top, h: 0.6, openings: [], s.wall)
            c.wallZ(-hz + 0.2, hz - 0.2, x: -hx + 0.1, t: 0.2, y0: top, h: 0.6, openings: [], s.wall)
            c.wallZ(-hz + 0.2, hz - 0.2, x: hx - 0.1, t: 0.2, y0: top, h: 0.6, openings: [], s.wall)
        } else {
            c.gable(-hx - 0.4, hx + 0.4, -hz - 0.5, hz + 0.5, base: top, rise: 1.8, s.roof, endMat: s.wall)
        }
        // door step
        c.box(-0.9, f - 0.15, hz, 0.9, f, hz + 0.8, .concrete, lod: false)
        furniture(c, x: -2.8, z: -2.4, y: f, rng: &rng)
        furniture(c, x: 3.0, z: 2.5, y: f, rng: &rng)
        c.lootAt(-2.2, f, 1.6)
        c.lootAt(2.8, f, -1.8)
        c.lootAt(-3.4, f, -0.4)
        c.lootAt(-0.5, f, -2.4)
        c.door(outside: (0, hz + 3.0), inside: (0, hz - 1.6), y: f)
    }

    static func house2(_ c: BuildCtx, _ s: Style, _ rng: inout RNG) {
        let hx: Float = 5.0, hz: Float = 4.0, t: Float = 0.25, f: Float = 0.3, h: Float = 3.0
        let f2: Float = f + h + 0.2 // second floor top
        foundation(c, hx: hx + 0.2, hz: hz + 0.2, top: f)
        c.box(-hx + t, f, -hz + t, hx - t, f + 0.02, hz - t, .floorTile, collide: false, lod: false)
        // ground floor walls
        c.wallX(-hx, hx, z: hz - t / 2, t: t, y0: f, h: h, openings: [(0.6, 1.8, 0, 2.2), (-3.2, -1.8, 0.9, 2.1), (3.0, 4.2, 0.9, 2.1)], s.wall)
        c.wallX(-hx, hx, z: -hz + t / 2, t: t, y0: f, h: h, openings: [(-1.0, 0.4, 0.9, 2.1), (2.2, 3.6, 0.9, 2.1)], s.wall)
        c.wallZ(-hz + t, hz - t, x: -hx + t / 2, t: t, y0: f, h: h, openings: [(1.6, 2.8, 0.9, 2.1)], s.wall)
        c.wallZ(-hz + t, hz - t, x: hx - t / 2, t: t, y0: f, h: h, openings: [(-1.5, 1.5, 0, 2.2)], s.wall)
        // stairs along the left wall going towards -z
        let sx0: Float = -hx + t, sx1: Float = -hx + t + 1.1
        let steps = 10
        let rise = (f2 - f) / Float(steps)
        let run: Float = 0.45
        let zStart: Float = 1.2
        for k in 0..<steps {
            let zA = zStart - run * Float(k + 1), zB = zStart - run * Float(k)
            c.box(sx0, f, zA, sx1, f + rise * Float(k + 1), zB, .wood, kind: .wood, lod: false)
        }
        let holeZ0 = zStart - run * Float(steps)
        // second floor slab with stair hole
        c.box(sx1, f + h, -hz, hx, f2, hz, .concreteDark)
        c.box(-hx, f + h, zStart, sx1, f2, hz, .concreteDark)
        c.box(-hx, f + h, -hz, sx1, f2, holeZ0, .concreteDark)
        c.box(sx1 - 0.02, f2, holeZ0, sx1 + 0.06, f2 + 1.0, zStart, .metalGray, kind: .metal, lod: false) // railing
        c.box(-hx + t, f2, -hz + t, hx - t, f2 + 0.02, hz - t, .wood, collide: false, lod: false)
        // upper walls
        c.wallX(-hx, hx, z: hz - t / 2, t: t, y0: f2, h: h, openings: [(-3.0, -1.6, 0.9, 2.1), (1.0, 2.4, 0.9, 2.1)], s.wall)
        c.wallX(-hx, hx, z: -hz + t / 2, t: t, y0: f2, h: h, openings: [(1.5, 3.0, 0.9, 2.1)], s.wall)
        c.wallZ(-hz + t, hz - t, x: -hx + t / 2, t: t, y0: f2, h: h, openings: [(1.8, 3.0, 0.9, 2.1)], s.wall)
        c.wallZ(-hz + t, hz - t, x: hx - t / 2, t: t, y0: f2, h: h, openings: [(-1.0, 1.0, 0.9, 2.1)], s.wall)
        let top = f2 + h
        c.box(-hx, top, -hz, hx, top + 0.2, hz, .concreteDark)
        if s.flatRoof {
            c.wallX(-hx, hx, z: hz - 0.1, t: 0.2, y0: top + 0.2, h: 0.7, openings: [], s.wall)
            c.wallX(-hx, hx, z: -hz + 0.1, t: 0.2, y0: top + 0.2, h: 0.7, openings: [], s.wall)
            c.wallZ(-hz + 0.2, hz - 0.2, x: -hx + 0.1, t: 0.2, y0: top + 0.2, h: 0.7, openings: [], s.wall)
            c.wallZ(-hz + 0.2, hz - 0.2, x: hx - 0.1, t: 0.2, y0: top + 0.2, h: 0.7, openings: [], s.wall)
        } else {
            c.gable(-hx - 0.4, hx + 0.4, -hz - 0.5, hz + 0.5, base: top + 0.2, rise: 2.0, s.roof, endMat: s.wall)
        }
        c.box(0.3, f - 0.15, hz, 2.1, f, hz + 0.9, .concrete, lod: false)
        furniture(c, x: 3.4, z: -2.8, y: f, rng: &rng)
        furniture(c, x: 3.0, z: 2.6, y: f2, rng: &rng)
        c.lootAt(2.5, f, 1.5)
        c.lootAt(1.0, f, -2.5)
        c.lootAt(3.8, f, -0.5)
        c.lootAt(-1.5, f2, 2.5)
        c.lootAt(2.5, f2, -2.6)
        c.lootAt(0.5, f2, 0.0)
        c.door(outside: (1.2, hz + 3.0), inside: (1.2, hz - 1.5), y: f)
        c.door(outside: (hx + 3.0, 0), inside: (hx - 1.5, 0), y: f)
    }

    static func warehouse(_ c: BuildCtx, _ rng: inout RNG) {
        let hx: Float = 11, hz: Float = 7, t: Float = 0.3, f: Float = 0.25, h: Float = 7
        let mat: Mt = rng.chance(0.5) ? .metalGray : .metalRust
        foundation(c, hx: hx + 0.3, hz: hz + 0.3, top: f)
        c.wallX(-hx, hx, z: hz - t / 2, t: t, y0: f, h: h, openings: [(-3.0, 3.0, 0, 5.0), (6.0, 8.0, 3.5, 4.8), (-8.0, -6.0, 3.5, 4.8)], mat, kind: .metal)
        c.wallX(-hx, hx, z: -hz + t / 2, t: t, y0: f, h: h, openings: [(-9.0, -7.8, 0, 2.3), (-4, 4, 3.5, 4.8)], mat, kind: .metal)
        c.wallZ(-hz + t, hz - t, x: -hx + t / 2, t: t, y0: f, h: h, openings: [(-1.0, 1.0, 3.5, 4.8)], mat, kind: .metal)
        c.wallZ(-hz + t, hz - t, x: hx - t / 2, t: t, y0: f, h: h, openings: [(-0.6, 0.6, 0, 2.3)], mat, kind: .metal)
        c.gable(-hx - 0.3, hx + 0.3, -hz - 0.3, hz + 0.3, base: f + h, rise: 1.6, .metalGray, endMat: mat)
        // roof beams
        for k in stride(from: -8, through: 8, by: 4) {
            c.box(Float(k) - 0.15, f + h - 0.4, -hz, Float(k) + 0.15, f + h, hz, .metalRust, collide: false, lod: false)
        }
        // crates / cover inside
        let spots: [(Float, Float)] = [(-7, -4), (-6.5, 3.5), (6, -4), (7, 3), (0, -3)]
        for sp in spots {
            let s: Float = rng.r(1.0, 1.4)
            c.box(sp.0 - s / 2, f, sp.1 - s / 2, sp.0 + s / 2, f + s, sp.1 + s / 2, .crate, kind: .wood, lod: false)
            if rng.chance(0.5) {
                c.box(sp.0 - s / 2 + 0.1, f + s, sp.1 - s / 2 + 0.1, sp.0 + s / 2 - 0.1, f + 2 * s - 0.2, sp.1 + s / 2 - 0.1, .crate, kind: .wood, lod: false)
            }
        }
        c.lootAt(-4, f, -1)
        c.lootAt(3.5, f, 1.5)
        c.lootAt(-8.5, f, 0.5)
        c.lootAt(8.5, f, -1)
        c.lootAt(0, f, 4)
        c.door(outside: (0, hz + 4), inside: (0, hz - 2), y: f)
        c.door(outside: (hx + 3, 0), inside: (hx - 2, 0), y: f)
    }

    static func cabin(_ c: BuildCtx, _ s: Style, _ rng: inout RNG) {
        let hx: Float = 3.2, hz: Float = 2.8, t: Float = 0.25, f: Float = 0.35, h: Float = 2.6
        foundation(c, hx: hx + 0.1, hz: hz + 0.1, top: f)
        c.box(-hx + t, f, -hz + t, hx - t, f + 0.02, hz - t, .wood, collide: false, lod: false)
        c.wallX(-hx, hx, z: hz - t / 2, t: t, y0: f, h: h, openings: [(-0.5, 0.5, 0, 2.1), (1.4, 2.4, 0.9, 1.8)], .woodDark, kind: .wood)
        c.wallX(-hx, hx, z: -hz + t / 2, t: t, y0: f, h: h, openings: [(-1.0, 0.0, 0.9, 1.8)], .woodDark, kind: .wood)
        c.wallZ(-hz + t, hz - t, x: -hx + t / 2, t: t, y0: f, h: h, openings: [(-0.5, 0.5, 0.9, 1.8)], .woodDark, kind: .wood)
        c.wallZ(-hz + t, hz - t, x: hx - t / 2, t: t, y0: f, h: h, openings: [], .woodDark, kind: .wood)
        c.box(-hx, f + h, -hz, hx, f + h + 0.15, hz, .woodDark, kind: .wood)
        c.gable(-hx - 0.5, hx + 0.5, -hz - 0.6, hz + 0.6, base: f + h + 0.15, rise: 1.7, s.roof, endMat: .woodDark)
        // porch
        c.box(-1.4, f - 0.1, hz, 1.4, f, hz + 1.4, .wood, kind: .wood, lod: false)
        furniture(c, x: 2.0, z: -1.8, y: f, rng: &rng)
        c.lootAt(-1.8, f, -1.4)
        c.lootAt(1.6, f, 1.2)
        c.door(outside: (0, hz + 3), inside: (0, hz - 1.4), y: f)
    }

    static func barracks(_ c: BuildCtx, _ s: Style, _ rng: inout RNG) {
        let hx: Float = 8, hz: Float = 3.2, t: Float = 0.3, f: Float = 0.3, h: Float = 3.0
        foundation(c, hx: hx + 0.2, hz: hz + 0.2, top: f)
        c.box(-hx + t, f, -hz + t, hx - t, f + 0.02, hz - t, .floorTile, collide: false, lod: false)
        c.wallX(-hx, hx, z: hz - t / 2, t: t, y0: f, h: h,
                openings: [(-5.2, -4.0, 0, 2.2), (4.0, 5.2, 0, 2.2), (-2.4, -1.0, 1.0, 2.1), (1.0, 2.4, 1.0, 2.1), (6.2, 7.4, 1.0, 2.1), (-7.4, -6.2, 1.0, 2.1)], .brick)
        c.wallX(-hx, hx, z: -hz + t / 2, t: t, y0: f, h: h,
                openings: [(-6.0, -4.6, 1.0, 2.1), (-1.4, 0.0, 1.0, 2.1), (3.0, 4.4, 1.0, 2.1)], .brick)
        c.wallZ(-hz + t, hz - t, x: -hx + t / 2, t: t, y0: f, h: h, openings: [(-0.6, 0.6, 0, 2.2)], .brick)
        c.wallZ(-hz + t, hz - t, x: hx - t / 2, t: t, y0: f, h: h, openings: [(-0.6, 0.6, 1.0, 2.1)], .brick)
        c.wallZ(-hz + t, hz - t, x: 0, t: 0.15, y0: f, h: h, openings: [(-0.5, 0.6, 0, 2.15)], .plasterA)
        c.box(-hx, f + h, -hz, hx, f + h + 0.25, hz, .concreteDark)
        c.wallX(-hx, hx, z: hz - 0.1, t: 0.2, y0: f + h + 0.25, h: 0.5, openings: [], .concrete)
        c.wallX(-hx, hx, z: -hz + 0.1, t: 0.2, y0: f + h + 0.25, h: 0.5, openings: [], .concrete)
        // bunk beds
        for k in [-6.5, -3.0, 3.0, 6.5] as [Float] {
            c.box(k - 0.5, f, -hz + 0.4, k + 0.5, f + 1.6, -hz + 2.3, .metalGray, kind: .metal, lod: false)
        }
        c.lootAt(-6, f, 1.6)
        c.lootAt(-2, f, 0.5)
        c.lootAt(2.5, f, 1.0)
        c.lootAt(6, f, 1.6)
        c.lootAt(-4.5, f, -0.5)
        c.door(outside: (-4.6, hz + 3), inside: (-4.6, hz - 1.4), y: f)
        c.door(outside: (4.6, hz + 3), inside: (4.6, hz - 1.4), y: f)
        _ = s
        _ = rng.f()
    }

    static func tower(_ c: BuildCtx) {
        let hs: Float = 1.5, h: Float = 7
        for (x, z) in [(-hs, -hs), (hs, -hs), (-hs, hs), (hs, hs)] as [(Float, Float)] {
            c.box(x - 0.15, -1, z - 0.15, x + 0.15, h, z + 0.15, .woodDark, kind: .wood)
        }
        c.box(-hs - 0.3, h, -hs - 0.3, hs + 0.3, h + 0.2, hs + 0.3, .woodDark, kind: .wood)
        c.wallX(-hs - 0.3, hs + 0.3, z: hs + 0.2, t: 0.1, y0: h + 0.2, h: 1.0, openings: [], .woodDark, kind: .wood)
        c.wallX(-hs - 0.3, hs + 0.3, z: -hs - 0.2, t: 0.1, y0: h + 0.2, h: 1.0, openings: [], .woodDark, kind: .wood)
        c.wallZ(-hs - 0.2, hs + 0.2, x: -hs - 0.2, t: 0.1, y0: h + 0.2, h: 1.0, openings: [], .woodDark, kind: .wood)
        c.wallZ(-hs - 0.2, hs + 0.2, x: hs + 0.2, t: 0.1, y0: h + 0.2, h: 1.0, openings: [], .woodDark, kind: .wood)
        c.gable(-hs - 0.6, hs + 0.6, -hs - 0.6, hs + 0.6, base: h + 2.4, rise: 1.0, .roofGray, endMat: .woodDark)
        for (x, z) in [(-hs, -hs), (hs, -hs), (-hs, hs), (hs, hs)] as [(Float, Float)] {
            c.box(x - 0.08, h + 0.2, z - 0.08, x + 0.08, h + 2.4, z + 0.08, .woodDark, collide: false)
        }
        // ladder
        for k in 0..<12 {
            let y = Float(k) * 0.6
            c.box(-0.4, y, hs + 0.15, 0.4, y + 0.06, hs + 0.25, .woodDark, collide: false, lod: false)
        }
        c.lootAt(0, 0.05, 0)
    }

    static func container(_ c: BuildCtx, _ rng: inout RNG) {
        let mats: [Mt] = [.contRed, .contBlue, .contGreen, .contYellow, .metalRust]
        let m = rng.pick(mats)
        let hx: Float = 3.05, hz: Float = 1.22, h: Float = 2.6
        if rng.chance(0.5) {
            // open container with loot inside
            c.box(-hx, -0.5, -hz, hx, 0.15, hz, m, kind: .metal)
            c.box(-hx, 0.15, -hz, hx, h, -hz + 0.08, m, kind: .metal)
            c.box(-hx, 0.15, hz - 0.08, hx, h, hz, m, kind: .metal)
            c.box(-hx, 0.15, -hz, -hx + 0.08, h, hz, m, kind: .metal)
            c.box(-hx, h, -hz, hx, h + 0.08, hz, m, kind: .metal)
            c.lootAt(0, 0.15, 0)
            c.door(outside: (hx + 3, 0), inside: (hx - 1, 0), y: 0.15)
        } else {
            c.box(-hx, -0.5, -hz, hx, h, hz, m, kind: .metal)
        }
    }

    static func radar(_ c: BuildCtx) {
        c.box(-4, -1.5, -4, 4, 0.3, 4, .concrete)
        // lattice tower
        let h: Float = 14
        for (x, z) in [(-1.6, -1.6), (1.6, -1.6), (-1.6, 1.6), (1.6, 1.6)] as [(Float, Float)] {
            c.hi.tube(Mt.metalGray.rawValue, from: c.w(x, 0.3, z), to: c.w(x * 0.4, h, z * 0.4), r0: 0.12, r1: 0.1, seg: 6)
            c.lo.tube(Mt.metalGray.rawValue, from: c.w(x, 0.3, z), to: c.w(x * 0.4, h, z * 0.4), r0: 0.12, r1: 0.1, seg: 4)
            c.col.addCyl(x: c.w(x, 0, z).x, z: c.w(x, 0, z).z, r: 0.2, y0: c.o.y, y1: c.o.y + 4, kind: .metal)
        }
        for k in 1..<5 {
            let y = Float(k) * h / 5
            let s: Float = 1.6 * (1 - 0.6 * Float(k) / 5)
            c.box(-s, y, -s - 0.05, s, y + 0.1, -s + 0.05, .metalGray, collide: false)
            c.box(-s, y, s - 0.05, s, y + 0.1, s + 0.05, .metalGray, collide: false)
            c.box(-s - 0.05, y, -s, -s + 0.05, y + 0.1, s, .metalGray, collide: false)
            c.box(s - 0.05, y, -s, s + 0.05, y + 0.1, s, .metalGray, collide: false)
        }
        // dish
        let m = mTranslate(c.w(0, h + 1.5, 0)) * mRotX(-0.9)
        c.hi.sphere(Mt.white.rawValue, radius: V3(3.2, 1.0, 3.2), m: m, rings: 4, segs: 16, hemisphere: true)
        c.lo.sphere(Mt.white.rawValue, radius: V3(3.2, 1.0, 3.2), m: m, rings: 2, segs: 8, hemisphere: true)
        // control hut
        c.box(1.5, 0.3, 1.5, 3.9, 2.8, 3.9, .plasterA)
        c.lootAt(-2.8, 0.3, -2.8)
        c.lootAt(-2.8, 0.3, 2.8)
    }

    static func shed(_ c: BuildCtx, _ s: Style) {
        let hx: Float = 2.8, hz: Float = 2.2, h: Float = 2.4, t: Float = 0.15
        c.box(-hx, -1, -hz, hx, 0.15, hz, .concreteDark)
        c.wallX(-hx, hx, z: -hz + t / 2, t: t, y0: 0.15, h: h, openings: [], .woodDark, kind: .wood)
        c.wallZ(-hz + t, hz, x: -hx + t / 2, t: t, y0: 0.15, h: h, openings: [], .woodDark, kind: .wood)
        c.wallZ(-hz + t, hz, x: hx - t / 2, t: t, y0: 0.15, h: h, openings: [], .woodDark, kind: .wood)
        c.box(-hx - 0.3, h + 0.15, -hz - 0.3, hx + 0.3, h + 0.3, hz + 0.6, s.roof == .roofSnow ? .roofSnow : .metalRust, kind: .metal)
        c.lootAt(0, 0.15, -0.5)
        c.door(outside: (0, hz + 2.5), inside: (0, 0), y: 0.15)
    }
}
