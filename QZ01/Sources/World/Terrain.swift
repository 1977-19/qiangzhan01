import SceneKit
import UIKit

/// Height field covering the whole map (centered on the origin), plus splat data.
final class Terrain {
    let size: Float = 1600
    let half: Float = 800
    let res = 641
    let spacing: Float = 2.5
    var h: [Float]
    var waterLevel: Float = 0
    let kind: MapKind

    // splat data on CPU (for grass placement / gameplay)
    let sres = 512
    var grassW: [Float] = []
    var roadW: [Float] = []
    var roadDist: [Float]           // same grid as height (res x res)

    init(kind: MapKind) {
        self.kind = kind
        h = [Float](repeating: 0, count: res * res)
        roadDist = [Float](repeating: 999, count: res * res)
    }

    // MARK: sampling

    @inline(__always) func gridH(_ i: Int, _ j: Int) -> Float {
        let ii = min(max(i, 0), res - 1), jj = min(max(j, 0), res - 1)
        return h[jj * res + ii]
    }

    func height(_ x: Float, _ z: Float) -> Float {
        let gx = (x + half) / spacing, gz = (z + half) / spacing
        let fx = gx.rounded(.down), fz = gz.rounded(.down)
        let i = Int(fx), j = Int(fz)
        let tx = gx - fx, tz = gz - fz
        let h00 = gridH(i, j), h10 = gridH(i + 1, j), h01 = gridH(i, j + 1), h11 = gridH(i + 1, j + 1)
        // triangle-consistent interpolation matching the mesh split (BL,BR,TR)/(BL,TR,TL)
        let a = h00 + (h10 - h00) * tx
        let b = h01 + (h11 - h01) * tx
        return a + (b - a) * tz
    }

    func normal(_ x: Float, _ z: Float) -> V3 {
        let e: Float = spacing
        let hl = height(x - e, z), hr = height(x + e, z)
        let hu = height(x, z - e), hd = height(x, z + e)
        return vnorm(V3(hl - hr, 2 * e, hu - hd))
    }

    @inline(__always) func gridNormal(_ i: Int, _ j: Int) -> V3 {
        let hl = gridH(i - 1, j), hr = gridH(i + 1, j), hu = gridH(i, j - 1), hd = gridH(i, j + 1)
        return vnorm(V3(hl - hr, 2 * spacing, hu - hd))
    }

    func inside(_ x: Float, _ z: Float, margin: Float = 0) -> Bool {
        return x > -half + margin && x < half - margin && z > -half + margin && z < half - margin
    }

    func isWater(_ x: Float, _ z: Float) -> Bool {
        return height(x, z) < waterLevel - 0.4
    }

    func roadDistance(_ x: Float, _ z: Float) -> Float {
        let i = Int(((x + half) / spacing).rounded()), j = Int(((z + half) / spacing).rounded())
        if i < 0 || j < 0 || i >= res || j >= res { return 999 }
        return roadDist[j * res + i]
    }

    func grassWeight(_ x: Float, _ z: Float) -> Float {
        if grassW.isEmpty { return 0 }
        let i = Int((x + half) / size * Float(sres)), j = Int((z + half) / size * Float(sres))
        if i < 0 || j < 0 || i >= sres || j >= sres { return 0 }
        return grassW[j * sres + i]
    }

    // MARK: generation

    func riverX(_ z: Float) -> Float {
        return 70 * sin(z * 0.0042 + 0.6) + 35 * sin(z * 0.011 + 1.3) - 20
    }

    func generate(noise: Noise) {
        switch kind {
        case .island:
            waterLevel = 0
            for j in 0..<res {
                for i in 0..<res {
                    let x = Float(i) * spacing - half, z = Float(j) * spacing - half
                    let d = sqrt(x * x + z * z) / half
                    let coast = d + noise.fbm(x * 0.0022 + 3, z * 0.0022 + 7, oct: 4) * 0.22
                    let land = smoothstepf(0.97, 0.74, coast)
                    let hills = noise.fbm(x * 0.0028, z * 0.0028, oct: 6) * 0.5 + 0.5
                    let ridge = noise.ridged(x * 0.0018 + 11, z * 0.0018 + 5, oct: 5)
                    var hh = 2 + pow(hills, 1.7) * 48 + ridge * ridge * 30
                    let detail = noise.fbm(x * 0.02, z * 0.02, oct: 3) * 1.2
                    hh += detail
                    // gentle plateau in the middle for the central town
                    hh = lerpf(hh, 3 + hh * 0.35, smoothstepf(0.45, 0.0, d) * 0.4)
                    let y = land * hh + (1 - land) * (-14 + detail)
                    h[j * res + i] = y
                }
            }
        case .snow:
            waterLevel = 6
            for j in 0..<res {
                for i in 0..<res {
                    let x = Float(i) * spacing - half, z = Float(j) * spacing - half
                    let edge = max(abs(x), abs(z)) / half
                    let mountains = smoothstepf(0.62, 1.0, edge + noise.fbm(x * 0.003, z * 0.003, oct: 3) * 0.12)
                    let hills = noise.fbm(x * 0.0026 + 40, z * 0.0026 + 9, oct: 6) * 0.5 + 0.5
                    let ridge = noise.ridged(x * 0.002 + 3, z * 0.002 + 17, oct: 6)
                    var hh = 16 + pow(hills, 1.5) * 34 + ridge * ridge * 26 + mountains * (110 + ridge * 70)
                    hh += noise.fbm(x * 0.025, z * 0.025, oct: 3) * 1.0
                    let dr = abs(x - riverX(z))
                    let carve = smoothstepf(70, 20, dr)
                    let bed: Float = 1.5 + noise.fbm(x * 0.01, z * 0.01, oct: 2) * 1.0
                    hh = lerpf(hh, bed, carve)
                    // soften banks
                    let bank = smoothstepf(110, 60, dr) * (1 - carve)
                    hh = lerpf(hh, min(hh, 14 + (dr - 60) * 0.25), bank * 0.6)
                    h[j * res + i] = hh
                }
            }
        }
    }

    /// Flattens a rectangle (axis aligned after rotation) to height `y`, with smooth falloff.
    func flattenRect(cx: Float, cz: Float, hx: Float, hz: Float, y: Float, falloff: Float) {
        let i0 = max(0, Int((cx - hx - falloff + half) / spacing) - 1)
        let i1 = min(res - 1, Int((cx + hx + falloff + half) / spacing) + 1)
        let j0 = max(0, Int((cz - hz - falloff + half) / spacing) - 1)
        let j1 = min(res - 1, Int((cz + hz + falloff + half) / spacing) + 1)
        if i0 > i1 || j0 > j1 { return }
        for j in j0...j1 {
            for i in i0...i1 {
                let x = Float(i) * spacing - half, z = Float(j) * spacing - half
                let dx = max(0, abs(x - cx) - hx), dz = max(0, abs(z - cz) - hz)
                let d = sqrt(dx * dx + dz * dz)
                let w = smoothstepf(falloff, 0, d)
                if w > 0 {
                    let k = j * res + i
                    h[k] = lerpf(h[k], y, w)
                }
            }
        }
    }

    /// Average height over a rectangle.
    func averageHeight(cx: Float, cz: Float, hx: Float, hz: Float) -> (avg: Float, minH: Float, maxH: Float) {
        var s: Float = 0, n: Float = 0, mn: Float = 9999, mx: Float = -9999
        var z = cz - hz
        while z <= cz + hz + 0.01 {
            var x = cx - hx
            while x <= cx + hx + 0.01 {
                let y = height(x, z)
                s += y; n += 1
                mn = min(mn, y); mx = max(mx, y)
                x += max(1, hx / 3)
            }
            z += max(1, hz / 3)
        }
        return (s / max(n, 1), mn, mx)
    }

    /// Carves roads: records distance field and flattens the terrain along the polyline.
    func applyRoad(_ pts: [V2], width: Float) {
        if pts.count < 2 { return }
        // smooth target heights along the road
        var ys = pts.map { height($0.x, $0.y) }
        for _ in 0..<6 {
            var n = ys
            for k in 1..<(ys.count - 1) { n[k] = (ys[k - 1] + ys[k] * 2 + ys[k + 1]) / 4 }
            ys = n
        }
        if kind == .island { ys = ys.map { max($0, 1.2) } }
        if kind == .snow { ys = ys.map { max($0, waterLevel + 1.2) } }
        let reach = width * 0.5 + 9
        for s in 0..<(pts.count - 1) {
            let a = pts[s], b = pts[s + 1]
            let ya = ys[s], yb = ys[s + 1]
            let mnx = min(a.x, b.x) - reach, mxx = max(a.x, b.x) + reach
            let mnz = min(a.y, b.y) - reach, mxz = max(a.y, b.y) + reach
            let i0 = max(0, Int((mnx + half) / spacing)), i1 = min(res - 1, Int((mxx + half) / spacing) + 1)
            let j0 = max(0, Int((mnz + half) / spacing)), j1 = min(res - 1, Int((mxz + half) / spacing) + 1)
            if i0 > i1 || j0 > j1 { continue }
            let ab = b - a
            let l2 = max(simd_dot(ab, ab), 1e-4)
            for j in j0...j1 {
                for i in i0...i1 {
                    let p = V2(Float(i) * spacing - half, Float(j) * spacing - half)
                    let t = saturate(simd_dot(p - a, ab) / l2)
                    let q = a + ab * t
                    let d = simd_length(p - q)
                    let k = j * res + i
                    if d < roadDist[k] { roadDist[k] = d }
                    let w = smoothstepf(reach, width * 0.5 + 1, d)
                    if w > 0 {
                        let target = lerpf(ya, yb, t)
                        h[k] = lerpf(h[k], target, w * 0.92)
                    }
                }
            }
        }
    }

    // MARK: splat + colormap

    struct SplatOut {
        var splat: CGImage
        var variation: CGImage
        var colormap: CGImage
        var minimap: UIImage
    }

    func buildSplat(noise: Noise, assets: Assets) -> SplatOut {
        let n = 1024
        let splat = Img(n, n)
        let vari = Img(n, n)
        let cmap = Img(n, n)
        grassW = [Float](repeating: 0, count: sres * sres)
        roadW = [Float](repeating: 0, count: sres * sres)
        let avgA = assets.grass.avg, avgB = assets.rock.avg
        let avgC = kind == .snow ? assets.snowTex.avg : assets.sandTex.avg
        let avgD = assets.road.avg
        let waterC = kind == .snow ? V3(0.20, 0.30, 0.34) : V3(0.08, 0.26, 0.32)
        for y in 0..<n {
            for x in 0..<n {
                let wx = (Float(x) + 0.5) / Float(n) * size - half
                let wz = (Float(y) + 0.5) / Float(n) * size - half
                let hh = height(wx, wz)
                let nn = normal(wx, wz)
                let rd = roadDistance(wx, wz)
                var road = smoothstepf(4.6, 2.6, rd)
                let dirtN = noise.fbm(wx * 0.012 + 70, wz * 0.012 + 30, oct: 3) * 0.5 + 0.5
                road = max(road, smoothstepf(0.66, 0.78, dirtN) * 0.55)
                let rockW = smoothstepf(0.88, 0.70, nn.y)
                var cW: Float
                if kind == .snow {
                    let sn = noise.fbm(wx * 0.009 + 5, wz * 0.009 + 1, oct: 4) * 0.5 + 0.5
                    cW = smoothstepf(0.47, 0.60, sn + (hh - 25) * 0.006)
                    cW = max(cW, smoothstepf(45, 80, hh))
                    if hh < waterLevel + 0.6 { cW = max(cW, 0.7) }
                } else {
                    cW = smoothstepf(2.8, 1.0, hh)
                }
                let wr = road * (kind == .snow ? (1 - cW * 0.7) : 1)
                let rest = 1 - wr
                let wk = rockW * rest
                let wc = cW * rest * (1 - rockW * (kind == .snow ? 0.4 : 1))
                let wg = max(0, rest - wk - wc)
                splat.set(x, y, V3(wg, wk, wc))
                let v = noise.fbm(wx * 0.004 + 9, wz * 0.004 + 4, oct: 4) * 0.5 + 0.5
                vari.set(x, y, V3(v, v, v))
                let colA: V3 = avgA * wg + avgB * wk
                let colB: V3 = avgC * wc + avgD * wr
                var col: V3 = colA + colB
                let vk: Float = 0.8 + 0.4 * v
                col = col * vk
                if hh < waterLevel - 0.2 {
                    let depth = saturate((waterLevel - hh) / 8)
                    col = lerp3(col, waterC, 0.5 + 0.5 * depth)
                }
                cmap.set(x, y, col)
                if x % 2 == 0 && y % 2 == 0 {
                    let si = (y / 2) * sres + (x / 2)
                    grassW[si] = (hh < waterLevel + 0.3) ? 0 : wg * (1 - wr)
                    roadW[si] = wr
                }
            }
        }
        // minimap: colormap with relief shading
        let mm = Img(n, n)
        let L = vnorm(V3(-0.5, 0.8, -0.4))
        for y in 0..<n {
            for x in 0..<n {
                let wx = (Float(x) + 0.5) / Float(n) * size - half
                let wz = (Float(y) + 0.5) / Float(n) * size - half
                let nn = normal(wx, wz)
                let shade: Float = 0.65 + 0.5 * max(0, vdot(nn, L))
                var c = cmap.get(x, y) * shade
                if roadDistance(wx, wz) < 3.2 { c = V3(0.80, 0.74, 0.60) }
                mm.set(x, y, c)
            }
        }
        let mmImage = UIImage(cgImage: mm.cg())
        return SplatOut(splat: splat.cg(linear: true), variation: vari.cg(linear: true), colormap: cmap.cg(), minimap: mmImage)
    }

    // MARK: meshes

    func makeMaterial(assets: Assets, splat: SplatOut) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = splat.colormap
        m.diffuse.wrapS = .clamp
        m.diffuse.wrapT = .clamp
        m.diffuse.mipFilter = .linear
        m.normal.contents = (kind == .snow ? assets.snowTex.normal : assets.grass.normal) ?? TexGen.flatNormal()
        m.normal.wrapS = .repeat
        m.normal.wrapT = .repeat
        m.normal.mipFilter = .linear
        m.normal.intensity = 0.7
        m.normal.contentsTransform = SCNMatrix4MakeScale(size / 4.5, size / 4.5, 1)
        m.roughness.contents = NSNumber(value: 0.95)
        m.metalness.contents = NSNumber(value: 0.0)

        func prop(_ img: CGImage, repeatWrap: Bool) -> SCNMaterialProperty {
            let p = SCNMaterialProperty(contents: img)
            p.wrapS = repeatWrap ? .repeat : .clamp
            p.wrapT = repeatWrap ? .repeat : .clamp
            p.mipFilter = .linear
            p.minificationFilter = .linear
            p.magnificationFilter = .linear
            return p
        }
        let texC = kind == .snow ? assets.snowTex.albedo : assets.sandTex.albedo
        m.setValue(prop(splat.splat, repeatWrap: false), forKey: "qzSplat")
        m.setValue(prop(splat.variation, repeatWrap: false), forKey: "qzVar")
        m.setValue(prop(assets.grass.albedo, repeatWrap: true), forKey: "qzTexA")
        m.setValue(prop(assets.rock.albedo, repeatWrap: true), forKey: "qzTexB")
        m.setValue(prop(texC, repeatWrap: true), forKey: "qzTexC")
        m.setValue(prop(assets.road.albedo, repeatWrap: true), forKey: "qzTexD")
        m.setValue(NSNumber(value: size / 4.0), forKey: "qzTile")

        let surface = """
        #pragma arguments
        texture2d<float, access::sample> qzSplat;
        texture2d<float, access::sample> qzVar;
        texture2d<float, access::sample> qzTexA;
        texture2d<float, access::sample> qzTexB;
        texture2d<float, access::sample> qzTexC;
        texture2d<float, access::sample> qzTexD;
        float qzTile;
        #pragma body
        constexpr sampler qzRep(coord::normalized, filter::linear, mip_filter::linear, address::repeat);
        constexpr sampler qzClp(coord::normalized, filter::linear, address::clamp_to_edge);
        float2 qzUV = _surface.diffuseTexcoord;
        float3 qzW = qzSplat.sample(qzClp, qzUV).rgb;
        float qzWd = max(0.0, 1.0 - qzW.r - qzW.g - qzW.b);
        float qzV = qzVar.sample(qzClp, qzUV).r;
        float2 qzT1 = qzUV * qzTile;
        float2 qzT2 = qzUV * (qzTile * 0.173);
        float3 qzA = mix(qzTexA.sample(qzRep, qzT1).rgb, qzTexA.sample(qzRep, qzT2).rgb, 0.4);
        float3 qzB = mix(qzTexB.sample(qzRep, qzT1 * 0.6).rgb, qzTexB.sample(qzRep, qzT2).rgb, 0.4);
        float3 qzC = mix(qzTexC.sample(qzRep, qzT1).rgb, qzTexC.sample(qzRep, qzT2).rgb, 0.3);
        float3 qzD = mix(qzTexD.sample(qzRep, qzT1).rgb, qzTexD.sample(qzRep, qzT2).rgb, 0.3);
        float3 qzDetail = qzA * qzW.r + qzB * qzW.g + qzC * qzW.b + qzD * qzWd;
        qzDetail *= (0.8 + 0.4 * qzV);
        float qzDist = length(_surface.position);
        float qzFar = smoothstep(140.0, 600.0, qzDist);
        _surface.diffuse = float4(mix(qzDetail, _surface.diffuse.rgb, qzFar), 1.0);
        """
        m.shaderModifiers = [.surface: surface]
        return m
    }

    /// Builds chunk geometry: `cells` cells per side, sampling every `step` grid points.
    private func chunkGeometry(ci: Int, cj: Int, cells: Int, step: Int, center: V3, material: SCNMaterial) -> SCNGeometry {
        let n = cells / step + 1
        var p: [Float] = []
        var nrm: [Float] = []
        var uv: [Float] = []
        var ind: [UInt32] = []
        p.reserveCapacity(n * n * 3 + n * 12)
        let gi0 = ci * cells, gj0 = cj * cells
        for b in 0..<n {
            for a in 0..<n {
                let gi = gi0 + a * step, gj = gj0 + b * step
                let x = Float(gi) * spacing - half, z = Float(gj) * spacing - half
                let y = gridH(gi, gj)
                p.append(x - center.x); p.append(y - center.y); p.append(z - center.z)
                let nn = gridNormal(gi, gj)
                nrm.append(nn.x); nrm.append(nn.y); nrm.append(nn.z)
                uv.append((x + half) / size); uv.append((z + half) / size)
            }
        }
        for b in 0..<(n - 1) {
            for a in 0..<(n - 1) {
                let tl = UInt32(b * n + a), tr = UInt32(b * n + a + 1)
                let bl = UInt32((b + 1) * n + a), br = UInt32((b + 1) * n + a + 1)
                ind.append(bl); ind.append(br); ind.append(tr)
                ind.append(bl); ind.append(tr); ind.append(tl)
            }
        }
        // skirts to hide LOD cracks
        func addSkirt(_ edge: [Int], outward: V3) {
            var top: [UInt32] = []
            var bot: [UInt32] = []
            for idx in edge {
                let px = p[idx * 3], py = p[idx * 3 + 1], pz = p[idx * 3 + 2]
                let base = UInt32(p.count / 3)
                p.append(px); p.append(py - 8); p.append(pz)
                nrm.append(nrm[idx * 3]); nrm.append(nrm[idx * 3 + 1]); nrm.append(nrm[idx * 3 + 2])
                uv.append(uv[idx * 2]); uv.append(uv[idx * 2 + 1])
                top.append(UInt32(idx))
                bot.append(base)
            }
            for k in 0..<(edge.count - 1) {
                let a0 = top[k], a1 = top[k + 1], b0 = bot[k], b1 = bot[k + 1]
                let pa0 = V3(p[Int(a0) * 3], p[Int(a0) * 3 + 1], p[Int(a0) * 3 + 2])
                let pa1 = V3(p[Int(a1) * 3], p[Int(a1) * 3 + 1], p[Int(a1) * 3 + 2])
                let pb0 = V3(p[Int(b0) * 3], p[Int(b0) * 3 + 1], p[Int(b0) * 3 + 2])
                let fn = vcross(pa1 - pb0, pa0 - pb0)
                if vdot(fn, outward) >= 0 {
                    ind.append(b0); ind.append(a1); ind.append(a0)
                    ind.append(b0); ind.append(b1); ind.append(a1)
                } else {
                    ind.append(b0); ind.append(a0); ind.append(a1)
                    ind.append(b0); ind.append(a1); ind.append(b1)
                }
            }
        }
        addSkirt((0..<n).map { $0 }, outward: V3(0, 0, -1))
        addSkirt((0..<n).map { (n - 1) * n + $0 }, outward: V3(0, 0, 1))
        addSkirt((0..<n).map { $0 * n }, outward: V3(-1, 0, 0))
        addSkirt((0..<n).map { $0 * n + n - 1 }, outward: V3(1, 0, 0))

        let vc = p.count / 3
        let ps = SCNGeometrySource(data: p.withUnsafeBufferPointer { Data(buffer: $0) }, semantic: .vertex, vectorCount: vc,
                                   usesFloatComponents: true, componentsPerVector: 3, bytesPerComponent: 4, dataOffset: 0, dataStride: 12)
        let ns = SCNGeometrySource(data: nrm.withUnsafeBufferPointer { Data(buffer: $0) }, semantic: .normal, vectorCount: vc,
                                   usesFloatComponents: true, componentsPerVector: 3, bytesPerComponent: 4, dataOffset: 0, dataStride: 12)
        let ts = SCNGeometrySource(data: uv.withUnsafeBufferPointer { Data(buffer: $0) }, semantic: .texcoord, vectorCount: vc,
                                   usesFloatComponents: true, componentsPerVector: 2, bytesPerComponent: 4, dataOffset: 0, dataStride: 8)
        let el = SCNGeometryElement(data: ind.withUnsafeBufferPointer { Data(buffer: $0) }, primitiveType: .triangles,
                                    primitiveCount: ind.count / 3, bytesPerIndex: 4)
        let g = SCNGeometry(sources: [ps, ns, ts], elements: [el])
        g.materials = [material]
        return g
    }

    func buildNodes(material: SCNMaterial) -> SCNNode {
        let root = SCNNode()
        root.name = "terrain"
        let chunks = 10
        let cells = (res - 1) / chunks // 64
        for cj in 0..<chunks {
            for ci in 0..<chunks {
                let cx = (Float(ci) + 0.5) * Float(cells) * spacing - half
                let cz = (Float(cj) + 0.5) * Float(cells) * spacing - half
                let cy = gridH(ci * cells + cells / 2, cj * cells + cells / 2)
                let center = V3(cx, cy, cz)
                let g0 = chunkGeometry(ci: ci, cj: cj, cells: cells, step: 1, center: center, material: material)
                let g1 = chunkGeometry(ci: ci, cj: cj, cells: cells, step: 2, center: center, material: material)
                let g2 = chunkGeometry(ci: ci, cj: cj, cells: cells, step: 4, center: center, material: material)
                g0.levelsOfDetail = [SCNLevelOfDetail(geometry: g1, worldSpaceDistance: 330),
                                     SCNLevelOfDetail(geometry: g2, worldSpaceDistance: 650)]
                let node = SCNNode(geometry: g0)
                node.simdPosition = center
                node.castsShadow = true
                root.addChildNode(node)
            }
        }
        return root
    }

    func waterNode(assets: Assets) -> SCNNode {
        let s: CGFloat = kind == .island ? 9000 : 1700
        let plane = SCNPlane(width: s, height: s)
        plane.widthSegmentCount = 1
        plane.heightSegmentCount = 1
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        let deep = kind == .snow ? UIColor(red: 0.06, green: 0.14, blue: 0.16, alpha: 1) : UIColor(red: 0.02, green: 0.12, blue: 0.15, alpha: 1)
        m.diffuse.contents = deep
        m.normal.contents = assets.waterNormal
        m.normal.wrapS = .repeat
        m.normal.wrapT = .repeat
        m.normal.mipFilter = .linear
        m.normal.intensity = 0.55
        let rep = Float(s) / 28
        m.normal.contentsTransform = SCNMatrix4MakeScale(rep, rep, 1)
        m.roughness.contents = NSNumber(value: 0.06)
        m.metalness.contents = NSNumber(value: 0.0)
        m.transparency = 0.86
        m.transparencyMode = .aOne
        m.isDoubleSided = false
        m.writesToDepthBuffer = true
        plane.materials = [m]
        let node = SCNNode(geometry: plane)
        node.simdEulerAngles = V3(-kPi / 2, 0, 0)
        node.simdPosition = V3(0, waterLevel, 0)
        node.castsShadow = false
        node.name = "water"
        return node
    }
}
