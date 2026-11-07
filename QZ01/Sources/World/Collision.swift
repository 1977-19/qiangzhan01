import Foundation
import simd

enum SurfaceKind: Int8 {
    case concrete = 0, wood = 1, metal = 2, rock = 3, ground = 4, water = 5, flesh = 6, vehicle = 7
}

struct ABox {
    var mn: V3
    var mx: V3
    var kind: SurfaceKind
}

struct VCyl {
    var x: Float
    var z: Float
    var r: Float
    var y0: Float
    var y1: Float
    var kind: SurfaceKind
}

struct RayHit {
    var t: Float
    var p: V3
    var n: V3
    var kind: SurfaceKind
}

/// Static collision: axis-aligned boxes (buildings, props), vertical cylinders (trees, rocks) and the terrain.
final class CollisionWorld {
    let terrain: Terrain
    private(set) var boxes: [ABox] = []
    private(set) var cyls: [VCyl] = []
    let cell: Float = 16
    let gn = 100
    let half: Float = 800
    private var bCells: [[Int32]]
    private var cCells: [[Int32]]
    private var stampB: [UInt32] = []
    private var stampC: [UInt32] = []
    private var stamp: UInt32 = 1
    var smokes: [(c: V3, r: Float, until: Float)] = []

    init(terrain: Terrain) {
        self.terrain = terrain
        bCells = [[Int32]](repeating: [], count: 100 * 100)
        cCells = [[Int32]](repeating: [], count: 100 * 100)
    }

    @inline(__always) private func ci(_ x: Float) -> Int { return Int(((x + half) / cell).rounded(.down)) }

    @inline(__always) private func cellId(_ i: Int, _ j: Int) -> Int? {
        if i < 0 || j < 0 || i >= gn || j >= gn { return nil }
        return j * gn + i
    }

    func addBox(_ mn: V3, _ mx: V3, kind: SurfaceKind = .concrete) {
        let b = ABox(mn: simd_min(mn, mx), mx: simd_max(mn, mx), kind: kind)
        let idx = Int32(boxes.count)
        boxes.append(b)
        stampB.append(0)
        for j in ci(b.mn.z)...ci(b.mx.z) {
            for i in ci(b.mn.x)...ci(b.mx.x) {
                if let c = cellId(i, j) { bCells[c].append(idx) }
            }
        }
    }

    func addCyl(x: Float, z: Float, r: Float, y0: Float, y1: Float, kind: SurfaceKind) {
        let idx = Int32(cyls.count)
        cyls.append(VCyl(x: x, z: z, r: r, y0: y0, y1: y1, kind: kind))
        stampC.append(0)
        for j in ci(z - r)...ci(z + r) {
            for i in ci(x - r)...ci(x + r) {
                if let c = cellId(i, j) { cCells[c].append(idx) }
            }
        }
    }

    // MARK: character support

    /// Highest walkable surface under (x,z) that is not higher than feetY + step.
    func ground(_ x: Float, _ z: Float, feetY: Float, step: Float) -> Float {
        var g = terrain.height(x, z)
        guard let c = cellId(ci(x), ci(z)) else { return g }
        for bi in bCells[c] {
            let b = boxes[Int(bi)]
            if x >= b.mn.x && x <= b.mx.x && z >= b.mn.z && z <= b.mx.z {
                if b.mx.y <= feetY + step && b.mx.y > g { g = b.mx.y }
            }
        }
        for k in cCells[c] {
            let cy = cyls[Int(k)]
            let dx = x - cy.x, dz = z - cy.z
            if dx * dx + dz * dz < cy.r * cy.r * 0.5 {
                if cy.y1 <= feetY + step && cy.y1 > g { g = cy.y1 }
            }
        }
        return g
    }

    /// Lowest ceiling above `headY` at (x,z) (or +inf)
    func ceiling(_ x: Float, _ z: Float, fromY: Float) -> Float {
        var c: Float = 1e9
        guard let cid = cellId(ci(x), ci(z)) else { return c }
        for bi in bCells[cid] {
            let b = boxes[Int(bi)]
            if x >= b.mn.x && x <= b.mx.x && z >= b.mn.z && z <= b.mx.z && b.mn.y >= fromY {
                c = min(c, b.mn.y)
            }
        }
        return c
    }

    /// Pushes a vertical capsule (circle radius r, from feetY+stepUp to feetY+height) out of obstacles.
    /// Returns true if something was hit.
    @discardableResult
    func pushOut(_ p: inout V3, radius r: Float, height: Float, stepUp: Float) -> Bool {
        var hit = false
        for _ in 0..<2 {
            let i0 = ci(p.x - r), i1 = ci(p.x + r), j0 = ci(p.z - r), j1 = ci(p.z + r)
            for j in j0...j1 {
                for i in i0...i1 {
                    guard let c = cellId(i, j) else { continue }
                    for bi in bCells[c] {
                        let b = boxes[Int(bi)]
                        if b.mn.y >= p.y + height || b.mx.y <= p.y + stepUp { continue }
                        let qx = clampf(p.x, b.mn.x, b.mx.x), qz = clampf(p.z, b.mn.z, b.mx.z)
                        let dx = p.x - qx, dz = p.z - qz
                        let d2 = dx * dx + dz * dz
                        if d2 >= r * r { continue }
                        hit = true
                        if d2 > 1e-8 {
                            let d = sqrt(d2)
                            p.x += dx / d * (r - d)
                            p.z += dz / d * (r - d)
                        } else {
                            // inside: push to nearest side
                            let l = p.x - b.mn.x, rr = b.mx.x - p.x, f = p.z - b.mn.z, bk = b.mx.z - p.z
                            let m = min(min(l, rr), min(f, bk))
                            if m == l { p.x = b.mn.x - r } else if m == rr { p.x = b.mx.x + r } else if m == f { p.z = b.mn.z - r } else { p.z = b.mx.z + r }
                        }
                    }
                    for k in cCells[c] {
                        let cy = cyls[Int(k)]
                        if cy.y0 >= p.y + height || cy.y1 <= p.y + stepUp { continue }
                        let dx = p.x - cy.x, dz = p.z - cy.z
                        let rr = r + cy.r
                        let d2 = dx * dx + dz * dz
                        if d2 >= rr * rr { continue }
                        hit = true
                        let d = max(sqrt(d2), 1e-4)
                        p.x = cy.x + dx / d * rr
                        p.z = cy.z + dz / d * rr
                    }
                }
            }
        }
        return hit
    }

    // MARK: rays

    private func forCells(_ a: V3, _ b: V3, _ visit: (Int) -> Bool) {
        let ax = (a.x + half) / cell, az = (a.z + half) / cell
        let bx = (b.x + half) / cell, bz = (b.z + half) / cell
        var x = Int(ax.rounded(.down)), z = Int(az.rounded(.down))
        let ex = Int(bx.rounded(.down)), ez = Int(bz.rounded(.down))
        let dx = bx - ax, dz = bz - az
        let sx = dx > 0 ? 1 : -1, sz = dz > 0 ? 1 : -1
        var tMaxX: Float = abs(dx) < 1e-9 ? Float.infinity : ((Float(x) + (dx > 0 ? 1 : 0)) - ax) / dx
        var tMaxZ: Float = abs(dz) < 1e-9 ? Float.infinity : ((Float(z) + (dz > 0 ? 1 : 0)) - az) / dz
        let tdx: Float = abs(dx) < 1e-9 ? Float.infinity : 1 / abs(dx)
        let tdz: Float = abs(dz) < 1e-9 ? Float.infinity : 1 / abs(dz)
        var guardN = 0
        while guardN < 400 {
            guardN += 1
            if let c = cellId(x, z) {
                if !visit(c) { return }
            }
            if x == ex && z == ez { return }
            if tMaxX < tMaxZ {
                if tMaxX > 1 { return }
                tMaxX += tdx
                x += sx
            } else {
                if tMaxZ > 1 { return }
                tMaxZ += tdz
                z += sz
            }
        }
    }

    @inline(__always) private func rayBox(_ o: V3, _ d: V3, _ b: ABox) -> (Float, V3)? {
        var tmin: Float = 0, tmax: Float = 1
        var n = V3(0, 0, 0)
        for axis in 0..<3 {
            let oa = o[axis], da = d[axis]
            let mn = b.mn[axis], mx = b.mx[axis]
            if abs(da) < 1e-9 {
                if oa < mn || oa > mx { return nil }
            } else {
                let inv = 1 / da
                var t1 = (mn - oa) * inv
                var t2 = (mx - oa) * inv
                var sgn: Float = -1
                if t1 > t2 { swap(&t1, &t2); sgn = 1 }
                if t1 > tmin {
                    tmin = t1
                    n = V3(0, 0, 0)
                    n[axis] = sgn
                }
                tmax = min(tmax, t2)
                if tmin > tmax { return nil }
            }
        }
        return (tmin, n)
    }

    @inline(__always) private func rayCyl(_ o: V3, _ d: V3, _ c: VCyl) -> (Float, V3)? {
        let ox = o.x - c.x, oz = o.z - c.z
        let a = d.x * d.x + d.z * d.z
        if a < 1e-9 { return nil }
        let bq = 2 * (ox * d.x + oz * d.z)
        let cq = ox * ox + oz * oz - c.r * c.r
        let disc = bq * bq - 4 * a * cq
        if disc < 0 { return nil }
        let s = sqrt(disc)
        var t = (-bq - s) / (2 * a)
        if t < 0 { t = (-bq + s) / (2 * a); if cq > 0 { return nil } }
        if t < 0 || t > 1 { return nil }
        let y = o.y + d.y * t
        if y < c.y0 || y > c.y1 { return nil }
        let hx = ox + d.x * t, hz = oz + d.z * t
        return (t, vnorm(V3(hx, 0, hz)))
    }

    func terrainHit(_ a: V3, _ b: V3) -> Float? {
        let d = b - a
        let l = vlen(d)
        if l < 1e-4 { return nil }
        let steps = max(2, Int(l / 1.6))
        var prevT: Float = 0
        var prevAbove = a.y - terrain.height(a.x, a.z)
        if prevAbove < 0 { return 0 }
        for s in 1...steps {
            let t = Float(s) / Float(steps)
            let p = a + d * t
            let above = p.y - terrain.height(p.x, p.z)
            if above < 0 {
                // refine
                var lo = prevT, hi = t
                for _ in 0..<6 {
                    let mid = (lo + hi) * 0.5
                    let q = a + d * mid
                    if q.y - terrain.height(q.x, q.z) < 0 { hi = mid } else { lo = mid }
                }
                return hi
            }
            prevT = t
            prevAbove = above
        }
        return nil
    }

    /// Closest hit along segment a→b against terrain, boxes and cylinders.
    func raycast(_ a: V3, _ b: V3, terrainToo: Bool = true) -> RayHit? {
        let d = b - a
        var best: Float = 2
        var bn = V3(0, 1, 0)
        var bk: SurfaceKind = .ground
        stamp &+= 1
        if stamp == 0 { stamp = 1; for i in 0..<stampB.count { stampB[i] = 0 }; for i in 0..<stampC.count { stampC[i] = 0 } }
        let st = stamp
        forCells(a, b) { c in
            for bi in bCells[c] {
                let i = Int(bi)
                if stampB[i] == st { continue }
                stampB[i] = st
                if let hit = rayBox(a, d, boxes[i]), hit.0 < best {
                    best = hit.0; bn = hit.1; bk = boxes[i].kind
                }
            }
            for k in cCells[c] {
                let i = Int(k)
                if stampC[i] == st { continue }
                stampC[i] = st
                if let hit = rayCyl(a, d, cyls[i]), hit.0 < best {
                    best = hit.0; bn = hit.1; bk = cyls[i].kind
                }
            }
            return true
        }
        if terrainToo {
            let end = best < 1 ? a + d * best : b
            if let t = terrainHit(a, end) {
                let tt = (best < 1 ? best : 1) * t
                if tt < best {
                    best = tt
                    let p = a + d * tt
                    bn = terrain.normal(p.x, p.z)
                    bk = .ground
                }
            }
        }
        if best <= 1 {
            return RayHit(t: best, p: a + d * best, n: bn, kind: bk)
        }
        return nil
    }

    /// True if nothing blocks the line (including active smoke clouds).
    func lineClear(_ a: V3, _ b: V3, now: Float, checkSmoke: Bool = true) -> Bool {
        if checkSmoke {
            for s in smokes where s.until > now {
                if segmentSphere(a, b, s.c, s.r) { return false }
            }
        }
        return raycast(a, b) == nil
    }

    func segmentSphere(_ a: V3, _ b: V3, _ c: V3, _ r: Float) -> Bool {
        let d = b - a
        let l2 = max(vdot(d, d), 1e-6)
        let t = saturate(vdot(c - a, d) / l2)
        let q = a + d * t
        return vlen(q - c) < r
    }

    func pruneSmokes(now: Float) {
        smokes.removeAll { $0.until < now }
    }
}
