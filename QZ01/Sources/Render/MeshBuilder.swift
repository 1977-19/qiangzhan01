import SceneKit
import simd

/// Accumulates triangles grouped by material id and builds a single SCNGeometry
/// (one geometry element per material). Used to merge many objects into few draw calls.
final class MeshBuilder {
    var pos: [Float] = []
    var nrm: [Float] = []
    var tex: [Float] = []
    private var groupOrder: [Int] = []
    private var groups: [Int: [UInt32]] = [:]

    var vertexCount: Int { return pos.count / 3 }
    var isEmpty: Bool { return groups.isEmpty }

    init() {
        pos.reserveCapacity(4096)
        nrm.reserveCapacity(4096)
        tex.reserveCapacity(4096)
    }

    @inline(__always) func vertex(_ p: V3, _ n: V3, _ t: V2) -> UInt32 {
        let i = UInt32(pos.count / 3)
        pos.append(p.x); pos.append(p.y); pos.append(p.z)
        nrm.append(n.x); nrm.append(n.y); nrm.append(n.z)
        tex.append(t.x); tex.append(t.y)
        return i
    }

    @inline(__always) func index(_ mat: Int, _ a: UInt32, _ b: UInt32, _ c: UInt32) {
        if groups[mat] == nil {
            groups[mat] = []
            groupOrder.append(mat)
        }
        groups[mat]!.append(a)
        groups[mat]!.append(b)
        groups[mat]!.append(c)
    }

    /// Quad with corners in counter-clockwise order seen from the front.
    func quad(_ mat: Int, _ p0: V3, _ p1: V3, _ p2: V3, _ p3: V3, _ n: V3,
              _ t0: V2, _ t1: V2, _ t2: V2, _ t3: V2) {
        let a = vertex(p0, n, t0), b = vertex(p1, n, t1), c = vertex(p2, n, t2), d = vertex(p3, n, t3)
        index(mat, a, b, c)
        index(mat, a, c, d)
    }

    func tri(_ mat: Int, _ p0: V3, _ p1: V3, _ p2: V3, _ t0: V2, _ t1: V2, _ t2: V2, smoothN: V3? = nil) {
        let n = smoothN ?? vnorm(vcross(p1 - p0, p2 - p0))
        let a = vertex(p0, n, t0), b = vertex(p1, n, t1), c = vertex(p2, n, t2)
        index(mat, a, b, c)
    }

    // MARK: Box

    static let faceDefs: [(n: V3, u: V3, v: V3)] = [
        (V3(1, 0, 0), V3(0, 0, -1), V3(0, 1, 0)),
        (V3(-1, 0, 0), V3(0, 0, 1), V3(0, 1, 0)),
        (V3(0, 0, 1), V3(1, 0, 0), V3(0, 1, 0)),
        (V3(0, 0, -1), V3(-1, 0, 0), V3(0, 1, 0)),
        (V3(0, 1, 0), V3(1, 0, 0), V3(0, 0, -1)),
        (V3(0, -1, 0), V3(1, 0, 0), V3(0, 0, 1)),
    ]

    /// Axis aligned box (in local space) transformed by `m`.
    /// - uv: nil => world-space UVs in metres (u along face u axis, v downwards); otherwise the rect is stretched on every face.
    /// - skipFaces: bit mask of face indices (0:+x 1:-x 2:+z 3:-z 4:+y 5:-y) not to emit.
    func box(_ mat: Int, min mn: V3, max mx: V3, m: M4 = matrix_identity_float4x4, uv: UVRect? = nil,
             skipFaces: Int = 0, uvScale: Float = 1) {
        let c = (mn + mx) * 0.5
        let e = (mx - mn) * 0.5
        let nm = normalMatrix(m)
        for (fi, f) in MeshBuilder.faceDefs.enumerated() {
            if (skipFaces >> fi) & 1 == 1 { continue }
            let eu = abs(vdot(f.u, e)), ev = abs(vdot(f.v, e)), en = abs(vdot(f.n, e))
            let fc = c + f.n * en
            let du = f.u * eu, dv = f.v * ev
            let c0: V3 = fc - du - dv
            let c1: V3 = fc + du - dv
            let c2: V3 = fc + du + dv
            let c3: V3 = fc - du + dv
            let lp: [V3] = [c0, c1, c2, c3]
            var t: [V2]
            if let r = uv {
                t = [V2(r.u0, r.v1), V2(r.u1, r.v1), V2(r.u1, r.v0), V2(r.u0, r.v0)]
            } else {
                t = lp.map { V2(vdot($0, f.u) * uvScale, -vdot($0, f.v) * uvScale) }
            }
            let wn = vnorm(nm * f.n)
            quad(mat, transformPoint(m, lp[0]), transformPoint(m, lp[1]), transformPoint(m, lp[2]), transformPoint(m, lp[3]),
                 wn, t[0], t[1], t[2], t[3])
        }
    }

    func boxC(_ mat: Int, center: V3, size: V3, m: M4 = matrix_identity_float4x4, uv: UVRect? = nil, skipFaces: Int = 0) {
        box(mat, min: center - size * 0.5, max: center + size * 0.5, m: m, uv: uv, skipFaces: skipFaces)
    }

    // MARK: Cylinder / cone around local Y

    func cylinder(_ mat: Int, r0: Float, r1: Float, y0: Float, y1: Float, seg: Int, m: M4 = matrix_identity_float4x4,
                  uv: UVRect? = nil, caps: Bool = true, uRepeat: Float = 1, vScale: Float = 1) {
        let nm = normalMatrix(m)
        let h = y1 - y0
        var ring0: [UInt32] = []
        var ring1: [UInt32] = []
        let r = uv ?? UVRect(u0: 0, v0: 0, u1: uRepeat, v1: h * vScale)
        for i in 0...seg {
            let a = Float(i) / Float(seg) * kTwoPi
            let d = V3(cos(a), 0, -sin(a))
            let n = vnorm(d * h + V3(0, r0 - r1, 0))
            let wn = vnorm(nm * n)
            let u = r.u0 + (r.u1 - r.u0) * Float(i) / Float(seg)
            ring0.append(vertex(transformPoint(m, d * r0 + V3(0, y0, 0)), wn, V2(u, r.v1)))
            ring1.append(vertex(transformPoint(m, d * r1 + V3(0, y1, 0)), wn, V2(u, r.v0)))
        }
        for i in 0..<seg {
            index(mat, ring0[i], ring0[i + 1], ring1[i + 1])
            index(mat, ring0[i], ring1[i + 1], ring1[i])
        }
        if caps {
            let up = vnorm(nm * V3(0, 1, 0)), dn = vnorm(nm * V3(0, -1, 0))
            let cu = (r.u0 + r.u1) * 0.5, cv = (r.v0 + r.v1) * 0.5
            if r1 > 0.0001 {
                let ct = vertex(transformPoint(m, V3(0, y1, 0)), up, V2(cu, cv))
                var rt: [UInt32] = []
                for i in 0...seg {
                    let a = Float(i) / Float(seg) * kTwoPi
                    rt.append(vertex(transformPoint(m, V3(cos(a) * r1, y1, -sin(a) * r1)), up, V2(cu + cos(a) * 0.2, cv + sin(a) * 0.2)))
                }
                for i in 0..<seg { index(mat, ct, rt[i], rt[i + 1]) }
            }
            if r0 > 0.0001 {
                let cb = vertex(transformPoint(m, V3(0, y0, 0)), dn, V2(cu, cv))
                var rb: [UInt32] = []
                for i in 0...seg {
                    let a = Float(i) / Float(seg) * kTwoPi
                    rb.append(vertex(transformPoint(m, V3(cos(a) * r0, y0, -sin(a) * r0)), dn, V2(cu + cos(a) * 0.2, cv + sin(a) * 0.2)))
                }
                for i in 0..<seg { index(mat, cb, rb[i + 1], rb[i]) }
            }
        }
    }

    /// Cylinder between two arbitrary points.
    func tube(_ mat: Int, from a: V3, to b: V3, r0: Float, r1: Float, seg: Int, uv: UVRect? = nil, caps: Bool = true) {
        let d = b - a
        let l = vlen(d)
        if l < 1e-4 { return }
        let dir = d / l
        let q = simd_quatf(from: V3(0, 1, 0), to: dir)
        let m = mTranslate(a) * M4(q)
        cylinder(mat, r0: r0, r1: r1, y0: 0, y1: l, seg: seg, m: m, uv: uv, caps: caps)
    }

    // MARK: Sphere (lat/long)

    func sphere(_ mat: Int, radius: V3, m: M4 = matrix_identity_float4x4, rings: Int = 8, segs: Int = 12, uv: UVRect = .full,
                displace: ((V3) -> Float)? = nil, hemisphere: Bool = false) {
        let nm = normalMatrix(m)
        var idx = [[UInt32]](repeating: [], count: rings + 1)
        let maxTheta: Float = hemisphere ? kPi * 0.5 : kPi
        for j in 0...rings {
            let th = Float(j) / Float(rings) * maxTheta
            for i in 0...segs {
                let ph = Float(i) / Float(segs) * kTwoPi
                let d = V3(sin(th) * cos(ph), cos(th), -sin(th) * sin(ph))
                var k: Float = 1
                if let f = displace { k = f(d) }
                let p = d * radius * k
                let n = vnorm(d / radius)
                let u = uv.u0 + (uv.u1 - uv.u0) * Float(i) / Float(segs)
                let v = uv.v0 + (uv.v1 - uv.v0) * Float(j) / Float(rings)
                idx[j].append(vertex(transformPoint(m, p), vnorm(nm * n), V2(u, v)))
            }
        }
        for j in 0..<rings {
            for i in 0..<segs {
                let bl = idx[j + 1][i], br = idx[j + 1][i + 1], tr = idx[j][i + 1], tl = idx[j][i]
                index(mat, bl, br, tr)
                index(mat, bl, tr, tl)
            }
        }
    }

    /// Recompute smooth normals for vertices of the last `fromVertex...` range (used for displaced rocks).
    func recomputeNormals(fromVertex start: Int, groupMat: Int, fromIndex idxStart: Int) {
        guard let g = groups[groupMat] else { return }
        let count = vertexCount
        var acc = [V3](repeating: V3(0, 0, 0), count: max(0, count - start))
        var i = idxStart
        while i + 2 < g.count {
            let a = Int(g[i]), b = Int(g[i + 1]), c = Int(g[i + 2])
            if a >= start && b >= start && c >= start {
                let pa = V3(pos[a * 3], pos[a * 3 + 1], pos[a * 3 + 2])
                let pb = V3(pos[b * 3], pos[b * 3 + 1], pos[b * 3 + 2])
                let pc = V3(pos[c * 3], pos[c * 3 + 1], pos[c * 3 + 2])
                let fn = vcross(pb - pa, pc - pa)
                acc[a - start] += fn; acc[b - start] += fn; acc[c - start] += fn
            }
            i += 3
        }
        for k in 0..<acc.count {
            let n = vnorm(acc[k])
            let vi = (start + k) * 3
            nrm[vi] = n.x; nrm[vi + 1] = n.y; nrm[vi + 2] = n.z
        }
    }

    func indexCount(_ mat: Int) -> Int { return groups[mat]?.count ?? 0 }

    // MARK: Build

    func build(materials: (Int) -> SCNMaterial, offset: V3 = V3(0, 0, 0)) -> SCNGeometry? {
        if groups.isEmpty || pos.isEmpty { return nil }
        var p = pos
        if offset != V3(0, 0, 0) {
            var i = 0
            while i < p.count {
                p[i] -= offset.x; p[i + 1] -= offset.y; p[i + 2] -= offset.z
                i += 3
            }
        }
        let vc = p.count / 3
        let pData = p.withUnsafeBufferPointer { Data(buffer: $0) }
        let nData = nrm.withUnsafeBufferPointer { Data(buffer: $0) }
        let tData = tex.withUnsafeBufferPointer { Data(buffer: $0) }
        let ps = SCNGeometrySource(data: pData, semantic: .vertex, vectorCount: vc, usesFloatComponents: true,
                                   componentsPerVector: 3, bytesPerComponent: 4, dataOffset: 0, dataStride: 12)
        let ns = SCNGeometrySource(data: nData, semantic: .normal, vectorCount: vc, usesFloatComponents: true,
                                   componentsPerVector: 3, bytesPerComponent: 4, dataOffset: 0, dataStride: 12)
        let ts = SCNGeometrySource(data: tData, semantic: .texcoord, vectorCount: vc, usesFloatComponents: true,
                                   componentsPerVector: 2, bytesPerComponent: 4, dataOffset: 0, dataStride: 8)
        var elements: [SCNGeometryElement] = []
        var mats: [SCNMaterial] = []
        for key in groupOrder {
            guard let ind = groups[key], !ind.isEmpty else { continue }
            let data = ind.withUnsafeBufferPointer { Data(buffer: $0) }
            let el = SCNGeometryElement(data: data, primitiveType: .triangles, primitiveCount: ind.count / 3, bytesPerIndex: 4)
            elements.append(el)
            mats.append(materials(key))
        }
        let g = SCNGeometry(sources: [ps, ns, ts], elements: elements)
        g.materials = mats
        return g
    }

    func node(materials: (Int) -> SCNMaterial, offset: V3 = V3(0, 0, 0)) -> SCNNode {
        let n = SCNNode()
        n.geometry = build(materials: materials, offset: offset)
        n.simdPosition = offset
        return n
    }
}
