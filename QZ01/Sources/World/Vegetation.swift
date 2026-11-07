import SceneKit
import simd

enum Vegetation {
    /// Pine tree: tapered trunk + drooping star-shaped branch layers (real geometry so shadows are right).
    static func pine(_ mb: MeshBuilder, at p: V3, scale s: Float, yaw: Float, lod: Int, rng: inout RNG) {
        let m = mTranslate(p) * mRotY(yaw)
        let h: Float = 11 * s
        let trunkSeg = lod == 0 ? 7 : 4
        mb.cylinder(Mt.bark.rawValue, r0: 0.28 * s, r1: 0.06 * s, y0: -0.5, y1: h, seg: trunkSeg, m: m,
                    caps: false, uRepeat: 2, vScale: 0.5)
        let layers = lod == 0 ? 7 : 3
        let spikes = lod == 0 ? 9 : 5
        let baseR: Float = 3.0 * s
        for k in 0..<layers {
            let f = Float(k) / Float(layers)
            let y = h * (0.22 + 0.74 * f)
            let r = baseR * pow(1 - f, 0.85) + 0.35 * s
            let droop = 0.35 * s + r * 0.38
            let tw = rng.r(0, kTwoPi)
            let top = transformPoint(m, V3(0, y + 0.5 * s, 0))
            let under = transformPoint(m, V3(0, y - droop * 0.35, 0))
            var ring: [V3] = []
            for i in 0..<(spikes * 2) {
                let a = tw + Float(i) / Float(spikes * 2) * kTwoPi
                let outer = i % 2 == 0
                let rr = outer ? r * rng.r(0.85, 1.1) : r * 0.5
                let dy = outer ? -droop : -droop * 0.45
                ring.append(transformPoint(m, V3(cos(a) * rr, y + dy, -sin(a) * rr)))
            }
            for i in 0..<ring.count {
                let a = ring[i], b = ring[(i + 1) % ring.count]
                let ta = V2(a.x * 0.4, a.z * 0.4), tb = V2(b.x * 0.4, b.z * 0.4), tt = V2(top.x * 0.4, top.z * 0.4)
                // top surface (CCW from above): top, a, b with a->b counter-clockwise
                let nTop = vnorm(vcross(a - top, b - top))
                let upN = nTop.y < 0 ? -nTop : nTop
                let smooth = vnorm(upN + vnorm(V3(a.x - top.x, 0, a.z - top.z)) * 0.6)
                if nTop.y >= 0 {
                    mb.tri(Mt.needles.rawValue, top, a, b, tt, ta, tb, smoothN: smooth)
                } else {
                    mb.tri(Mt.needles.rawValue, top, b, a, tt, tb, ta, smoothN: smooth)
                }
                if lod == 0 {
                    let nU = vnorm(vcross(b - under, a - under))
                    let tu = V2(under.x * 0.4, under.z * 0.4)
                    if nU.y <= 0 {
                        mb.tri(Mt.needles.rawValue, under, b, a, tu, tb, ta, smoothN: V3(0, -1, 0))
                    } else {
                        mb.tri(Mt.needles.rawValue, under, a, b, tu, ta, tb, smoothN: V3(0, -1, 0))
                    }
                }
            }
        }
    }

    /// Broadleaf tree: trunk with a few branches and lumpy leaf blobs.
    static func broadleaf(_ mb: MeshBuilder, at p: V3, scale s: Float, yaw: Float, lod: Int, rng: inout RNG, noise: Noise) {
        let m = mTranslate(p) * mRotY(yaw)
        let h: Float = 6.5 * s
        mb.cylinder(Mt.bark.rawValue, r0: 0.3 * s, r1: 0.16 * s, y0: -0.5, y1: h, seg: lod == 0 ? 7 : 4, m: m, caps: false, uRepeat: 2, vScale: 0.5)
        let blobs = lod == 0 ? 5 : 2
        for k in 0..<blobs {
            let a = Float(k) / Float(blobs) * kTwoPi + rng.r(0, 1)
            let d: Float = k == 0 ? 0 : rng.r(1.0, 2.0) * s
            let c = V3(cos(a) * d, h + rng.r(-0.8, 1.2) * s, -sin(a) * d)
            let r = rng.r(1.8, 2.6) * s
            if lod == 0 && k > 0 {
                mb.tube(Mt.bark.rawValue, from: transformPoint(m, V3(0, h * 0.7, 0)), to: transformPoint(m, c), r0: 0.12 * s, r1: 0.06 * s, seg: 5, caps: false)
            }
            let bm = m * mTranslate(c)
            let seed = Float(k) * 3.1 + p.x * 0.1
            mb.sphere(Mt.leaves.rawValue, radius: V3(r, r * 0.8, r), m: bm, rings: lod == 0 ? 6 : 4, segs: lod == 0 ? 9 : 6,
                      uv: UVRect(u0: 0, v0: 0, u1: 3, v1: 2)) { dir in
                return 1 + noise.n2(dir.x * 2.2 + seed, dir.z * 2.2 + dir.y * 1.7) * 0.35
            }
        }
    }

    static func bush(_ mb: MeshBuilder, at p: V3, scale s: Float, rng: inout RNG, noise: Noise, dead: Bool) {
        let n = 2 + rng.i(2)
        for k in 0..<n {
            let off = V3(rng.r(-0.6, 0.6), 0, rng.r(-0.6, 0.6)) * s
            let r = rng.r(0.6, 1.0) * s
            let m = mTranslate(p + off + V3(0, r * 0.45, 0))
            let seed = Float(k) + p.z * 0.07
            mb.sphere(dead ? Mt.bark.rawValue : Mt.leaves.rawValue, radius: V3(r, r * 0.75, r), m: m, rings: 4, segs: 7,
                      uv: UVRect(u0: 0, v0: 0, u1: 1.5, v1: 1)) { dir in
                return 1 + noise.n2(dir.x * 3 + seed, dir.z * 3 + dir.y * 2) * 0.4
            }
        }
    }

    /// Displaced, flattened boulder. Returns collision radius / top.
    @discardableResult
    static func rock(_ mb: MeshBuilder, at p: V3, size: V3, yaw: Float, lod: Int, noise: Noise, seed: Float) -> (r: Float, top: Float) {
        let m = mTranslate(p) * mRotY(yaw)
        let startV = mb.vertexCount
        let startI = mb.indexCount(Mt.rock.rawValue)
        mb.sphere(Mt.rock.rawValue, radius: size, m: m, rings: lod == 0 ? 7 : 4, segs: lod == 0 ? 10 : 6,
                  uv: UVRect(u0: 0, v0: 0, u1: max(1, size.x * 0.7), v1: max(1, size.y * 0.7))) { dir in
            let n1 = noise.n2(dir.x * 1.6 + seed, dir.z * 1.6 + dir.y * 1.3 + seed)
            let n2 = noise.n2(dir.x * 4.1 + seed * 2, dir.z * 4.1 - dir.y * 3.7)
            var k = 1 + n1 * 0.35 + n2 * 0.12
            if dir.y < -0.2 { k *= 0.9 }
            return k
        }
        mb.recomputeNormals(fromVertex: startV, groupMat: Mt.rock.rawValue, fromIndex: startI)
        return (max(size.x, size.z) * 0.85, p.y + size.y * 0.9)
    }

    static func logPile(_ mb: MeshBuilder, at p: V3, yaw: Float) {
        let m0 = mTranslate(p) * mRotY(yaw)
        var k = 0
        for row in 0..<3 {
            let count = 4 - row
            for i in 0..<count {
                let x = (Float(i) - Float(count - 1) * 0.5) * 0.5
                let y = 0.25 + Float(row) * 0.42
                let m = m0 * mTranslate(V3(x, y, 0)) * mRotX(kPi / 2)
                mb.cylinder(Mt.bark.rawValue, r0: 0.22, r1: 0.22, y0: -2.5, y1: 2.5, seg: 7, m: m, caps: true)
                k += 1
            }
        }
    }

    static func haystack(_ mb: MeshBuilder, at p: V3) {
        let m = mTranslate(p)
        mb.cylinder(Mt.sandbag.rawValue, r0: 1.3, r1: 1.2, y0: -0.2, y1: 1.6, seg: 10, m: m, caps: false, uRepeat: 4)
        mb.cylinder(Mt.sandbag.rawValue, r0: 1.2, r1: 0.1, y0: 1.6, y1: 2.6, seg: 10, m: m, caps: false, uRepeat: 4)
    }
}

/// Dense alpha-tested grass cards generated around the camera in chunks.
final class GrassField {
    let terrain: Terrain
    let col: CollisionWorld
    let root = SCNNode()
    let material: SCNMaterial
    let chunk: Float = 20
    var radius: Float
    var density: Float
    private var active: [Int: SCNNode] = [:]
    private var queue: [(Int, Int)] = []
    var blockers: [(V2, V2)] = [] // building footprints (min,max) where no grass grows

    init(terrain: Terrain, col: CollisionWorld, card: CGImage, radius: Float, density: Float) {
        self.terrain = terrain
        self.col = col
        self.radius = radius
        self.density = density
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = card
        m.diffuse.wrapS = .clamp
        m.diffuse.wrapT = .clamp
        m.diffuse.mipFilter = .linear
        m.roughness.contents = NSNumber(value: 0.9)
        m.metalness.contents = NSNumber(value: 0.0)
        m.isDoubleSided = true
        m.blendMode = .replace
        m.writesToDepthBuffer = true
        m.readsFromDepthBuffer = true
        m.setValue(NSNumber(value: radius), forKey: "qzGrassR")
        let geo = """
        #pragma arguments
        float qzGrassR;
        #pragma body
        float4 qzWP = scn_node.modelTransform * _geometry.position;
        float3 qzCam = (scn_frame.inverseViewTransform * float4(0.0, 0.0, 0.0, 1.0)).xyz;
        float qzD = distance(qzWP.xyz, qzCam);
        float qzFade = clamp((qzGrassR - qzD) / 14.0, 0.0, 1.0);
        float qzW = 1.0 - _geometry.texcoords[0].y;
        float qzT = scn_frame.time;
        float qzPh = qzWP.x * 0.31 + qzWP.z * 0.23;
        _geometry.position.x += sin(qzT * 1.8 + qzPh) * 0.07 * qzW;
        _geometry.position.z += cos(qzT * 1.4 + qzPh * 1.3) * 0.05 * qzW;
        _geometry.position.y -= (1.0 - qzFade) * 1.2;
        """
        let surf = """
        #pragma body
        if (_surface.diffuse.a < 0.42) { discard_fragment(); }
        _surface.diffuse.a = 1.0;
        """
        m.shaderModifiers = [.geometry: geo, .surface: surf]
        material = m
        root.name = "grass"
    }

    private func key(_ i: Int, _ j: Int) -> Int { return (j + 1000) * 4000 + (i + 1000) }

    func update(camera: V3) {
        let ci = Int(((camera.x) / chunk).rounded(.down)), cj = Int(((camera.z) / chunk).rounded(.down))
        let rc = Int((radius / chunk).rounded(.up))
        var wanted = Set<Int>()
        for j in (cj - rc)...(cj + rc) {
            for i in (ci - rc)...(ci + rc) {
                let cx = (Float(i) + 0.5) * chunk, cz = (Float(j) + 0.5) * chunk
                let dx = cx - camera.x, dz = cz - camera.z
                if dx * dx + dz * dz > (radius + chunk) * (radius + chunk) { continue }
                let k = key(i, j)
                wanted.insert(k)
                if active[k] == nil && !queue.contains(where: { $0.0 == i && $0.1 == j }) {
                    queue.append((i, j))
                }
            }
        }
        for (k, node) in active where !wanted.contains(k) {
            node.removeFromParentNode()
            active[k] = nil
        }
        queue.removeAll { !wanted.contains(key($0.0, $0.1)) }
        // sort queue by distance, build a few per frame
        queue.sort { a, b in
            let da = pow((Float(a.0) + 0.5) * chunk - camera.x, 2) + pow((Float(a.1) + 0.5) * chunk - camera.z, 2)
            let db = pow((Float(b.0) + 0.5) * chunk - camera.x, 2) + pow((Float(b.1) + 0.5) * chunk - camera.z, 2)
            return da < db
        }
        var built = 0
        while built < 3 && !queue.isEmpty {
            let (i, j) = queue.removeFirst()
            let node = buildChunk(i, j)
            root.addChildNode(node)
            active[key(i, j)] = node
            built += 1
        }
    }

    private func blocked(_ x: Float, _ z: Float) -> Bool {
        for b in blockers {
            if x > b.0.x && x < b.1.x && z > b.0.y && z < b.1.y { return true }
        }
        return false
    }

    private func buildChunk(_ i: Int, _ j: Int) -> SCNNode {
        var rng = RNG(hash2(i, j, 991))
        let mb = MeshBuilder()
        let x0 = Float(i) * chunk, z0 = Float(j) * chunk
        let center = V3(x0 + chunk / 2, terrain.height(x0 + chunk / 2, z0 + chunk / 2), z0 + chunk / 2)
        let count = Int(Float(520) * density)
        let nearBlockers = blockers.filter { b in
            b.1.x > x0 - 2 && b.0.x < x0 + chunk + 2 && b.1.y > z0 - 2 && b.0.y < z0 + chunk + 2
        }
        for _ in 0..<count {
            let x = x0 + rng.f() * chunk, z = z0 + rng.f() * chunk
            let gw = terrain.grassWeight(x, z)
            if gw < 0.25 || rng.f() > gw * 1.15 { continue }
            if terrain.roadDistance(x, z) < 4.0 { continue }
            var skip = false
            for b in nearBlockers where x > b.0.x && x < b.1.x && z > b.0.y && z < b.1.y { skip = true; break }
            if skip { continue }
            let y = terrain.height(x, z)
            if y < terrain.waterLevel + 0.2 { continue }
            let hgt = rng.r(0.35, 0.85) * (0.6 + 0.6 * gw)
            let wid = rng.r(0.7, 1.3)
            let a = rng.r(0, kPi)
            let up = V3(0, 1, 0)
            for c in 0..<2 {
                let ang = a + Float(c) * kPi / 2
                let d = V3(cos(ang), 0, -sin(ang)) * (wid * 0.5)
                let bl = V3(x, y - 0.05, z) - d, br = V3(x, y - 0.05, z) + d
                let lean = V3(rng.r(-0.12, 0.12), 0, rng.r(-0.12, 0.12))
                let tr = br + V3(0, hgt, 0) + lean, tl = bl + V3(0, hgt, 0) + lean
                let u0: Float = rng.chance(0.5) ? 0 : 0.5
                mb.quad(1, bl, br, tr, tl, up, V2(u0, 1), V2(u0 + 0.5, 1), V2(u0 + 0.5, 0), V2(u0, 0))
            }
        }
        let node = SCNNode()
        if let g = mb.build(materials: { _ in self.material }, offset: center) {
            node.geometry = g
        }
        node.simdPosition = center
        node.castsShadow = false
        return node
    }

    func clear() {
        for (_, n) in active { n.removeFromParentNode() }
        active.removeAll()
        queue.removeAll()
    }
}
