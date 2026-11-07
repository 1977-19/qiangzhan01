import SceneKit
import UIKit

/// Merged static meshes per 160 m chunk, with a low-detail LOD.
final class StaticChunks {
    let n = 10
    let size: Float = 160
    var hi: [MeshBuilder]
    var lo: [MeshBuilder]

    init() {
        hi = (0..<100).map { _ in MeshBuilder() }
        lo = (0..<100).map { _ in MeshBuilder() }
    }

    func index(_ x: Float, _ z: Float) -> Int {
        let i = min(max(Int((x + 800) / size), 0), n - 1)
        let j = min(max(Int((z + 800) / size), 0), n - 1)
        return j * n + i
    }

    func buildNode(assets: Assets, terrain: Terrain) -> SCNNode {
        let root = SCNNode()
        root.name = "static"
        for j in 0..<n {
            for i in 0..<n {
                let k = j * n + i
                let cx = (Float(i) + 0.5) * size - 800, cz = (Float(j) + 0.5) * size - 800
                let center = V3(cx, terrain.height(cx, cz), cz)
                guard let g = hi[k].build(materials: { assets.mat($0) }, offset: center) else { continue }
                let gl = lo[k].build(materials: { assets.mat($0) }, offset: center)
                g.levelsOfDetail = [SCNLevelOfDetail(geometry: gl, worldSpaceDistance: 280),
                                    SCNLevelOfDetail(geometry: nil, worldSpaceDistance: 1150)]
                let node = SCNNode(geometry: g)
                node.simdPosition = center
                node.castsShadow = true
                root.addChildNode(node)
            }
        }
        hi.removeAll()
        lo.removeAll()
        return root
    }
}

struct PlaceName {
    var name: String
    var p: V2
}

/// Everything produced by the world generator.
final class WorldData {
    let kind: MapKind
    let assets: Assets
    let terrain: Terrain
    let col: CollisionWorld
    var terrainNode = SCNNode()
    var staticNode = SCNNode()
    var waterNode = SCNNode()
    var loot: [LootSpot] = []
    var doors: [DoorWay] = []
    var vehicleSpawns: [(p: V3, yaw: Float)] = []
    var places: [PlaceName] = []
    var footprints: [(V2, V2)] = []
    var minimap = UIImage()
    var grass: GrassField!
    var roads: [[V2]] = []

    init(kind: MapKind, assets: Assets, terrain: Terrain, col: CollisionWorld) {
        self.kind = kind
        self.assets = assets
        self.terrain = terrain
        self.col = col
    }
}

enum MapGen {
    struct Placed {
        var type: BType
        var c: V3
        var rot: Int
        var tier: Int
        var style: Buildings.Style
    }

    struct Town {
        var name: String
        var p: V2
        var radius: Float
        var count: Int
        var types: [BType]
        var tier: Int
    }

    static func catmull(_ pts: [V2], step: Float) -> [V2] {
        if pts.count < 2 { return pts }
        var out: [V2] = []
        for i in 0..<(pts.count - 1) {
            let p0 = pts[max(i - 1, 0)], p1 = pts[i], p2 = pts[i + 1], p3 = pts[min(i + 2, pts.count - 1)]
            let segLen = simd_length(p2 - p1)
            let n = max(2, Int(segLen / step))
            for k in 0..<n {
                let t = Float(k) / Float(n)
                let t2 = t * t, t3 = t2 * t
                let a: V2 = p1 * 2
                let b: V2 = (p2 - p0) * t
                let c: V2 = (p0 * 2 - p1 * 5 + p2 * 4 - p3) * t2
                let d: V2 = (p1 * 3 - p0 - p2 * 3 + p3) * t3
                out.append((a + b + c + d) * 0.5)
            }
        }
        out.append(pts[pts.count - 1])
        return out
    }

    static func generate(kind: MapKind, grassRadius: Float, grassDensity: Float, progress: @escaping (Float, String) -> Void) -> WorldData {
        let assets = Assets(kind: kind)
        assets.generate { p in progress(p * 0.55, "生成材质与天空…") }
        let noise = assets.noise
        let terrain = Terrain(kind: kind)
        progress(0.56, "生成地形…")
        terrain.generate(noise: noise)
        let col = CollisionWorld(terrain: terrain)
        let world = WorldData(kind: kind, assets: assets, terrain: terrain, col: col)
        var rng = RNG(777 + UInt64(kind.rawValue))
        let chunks = StaticChunks()
        var placed: [Placed] = []
        var rects: [(V2, V2)] = []

        func ensureLand(_ p: V2) -> V2 {
            var q = p
            for _ in 0..<40 {
                if terrain.height(q.x, q.y) > terrain.waterLevel + 2.0 && terrain.inside(q.x, q.y, margin: 60) { return q }
                q = q * 0.95
            }
            return q
        }

        func rectFree(_ mn: V2, _ mx: V2) -> Bool {
            for r in rects {
                if mn.x < r.1.x && mx.x > r.0.x && mn.y < r.1.y && mx.y > r.0.y { return false }
            }
            return true
        }

        func halfExt(_ t: BType, _ rot: Int) -> V2 {
            let h = t.halfSize
            return rot % 2 == 0 ? h : V2(h.y, h.x)
        }

        @discardableResult
        func place(_ t: BType, at p: V2, rot: Int, tier: Int, style: Buildings.Style, force: Bool = false, yOverride: Float? = nil, flatten: Bool = true) -> Bool {
            let he = halfExt(t, rot)
            let mn = p - he - V2(2.5, 2.5), mx = p + he + V2(2.5, 2.5)
            if !force {
                if !rectFree(mn, mx) { return false }
                if !terrain.inside(p.x, p.y, margin: 40) { return false }
                let st = terrain.averageHeight(cx: p.x, cz: p.y, hx: he.x, hz: he.y)
                if st.maxH - st.minH > 7 { return false }
                if st.minH < terrain.waterLevel + 0.8 { return false }
                // keep off roads
                let rd = min(terrain.roadDistance(p.x, p.y), min(terrain.roadDistance(p.x + he.x, p.y + he.y), terrain.roadDistance(p.x - he.x, p.y - he.y)))
                if rd < 5 && terrain.roadDistance(p.x, p.y) < max(he.x, he.y) + 4 { return false }
            }
            var y: Float
            if let yo = yOverride {
                y = yo
            } else {
                y = terrain.averageHeight(cx: p.x, cz: p.y, hx: he.x, hz: he.y).avg
            }
            if flatten {
                terrain.flattenRect(cx: p.x, cz: p.y, hx: he.x + 0.5, hz: he.y + 0.5, y: y, falloff: 7)
            }
            rects.append((mn, mx))
            placed.append(Placed(type: t, c: V3(p.x, y, p.y), rot: rot, tier: tier, style: style))
            return true
        }

        func styleFor(_ rng: inout RNG) -> Buildings.Style {
            if kind == .snow {
                let walls: [Mt] = [.woodDark, .wood, .plasterA, .plasterC, .brick]
                return Buildings.Style(wall: rng.pick(walls), roof: .roofSnow, flatRoof: false)
            }
            let walls: [Mt] = [.plasterA, .plasterB, .plasterC, .brick, .plasterA]
            let roofs: [Mt] = [.roofRed, .roofGray, .roofRed]
            return Buildings.Style(wall: rng.pick(walls), roof: rng.pick(roofs), flatRoof: rng.chance(0.3))
        }

        // ---------- layout ----------
        progress(0.60, "规划城镇与道路…")
        var towns: [Town] = []
        var roadDefs: [[V2]] = []
        var compound: (V2, Int)? = nil
        if kind == .island {
            let base = ensureLand(V2(0, -470))
            let center = ensureLand(V2(20, 40))
            let port = ensureLand(V2(420, 300))
            let fish = ensureLand(V2(-470, -120))
            let farm = ensureLand(V2(-350, 350))
            let plant = ensureLand(V2(-80, 430))
            let hill = ensureLand(V2(370, -260))
            compound = (base, 3)
            towns = [
                Town(name: "中心镇", p: center, radius: 115, count: 17, types: [.house1, .house2, .house1, .barracks, .house2, .shed], tier: 2),
                Town(name: "港口", p: port, radius: 85, count: 11, types: [.warehouse, .container, .house1, .container, .house2, .container], tier: 2),
                Town(name: "渔村", p: fish, radius: 60, count: 8, types: [.house1, .shed, .house1, .cabin], tier: 1),
                Town(name: "农场", p: farm, radius: 70, count: 7, types: [.house1, .warehouse, .shed, .house2], tier: 1),
                Town(name: "电厂", p: plant, radius: 75, count: 9, types: [.warehouse, .container, .container, .barracks], tier: 2),
                Town(name: "山顶哨站", p: hill, radius: 45, count: 4, types: [.barracks, .tower, .container], tier: 2),
            ]
            world.places = [PlaceName(name: "军事基地", p: base)] + towns.map { PlaceName(name: $0.name, p: $0.p) }
            func mid(_ a: V2, _ b: V2, _ ox: Float, _ oy: Float) -> V2 {
                let m: V2 = (a + b) * 0.5
                return m + V2(ox, oy)
            }
            let baseGate: V2 = base + V2(0, 50)
            let baseEast: V2 = base + V2(70, 0)
            var r1: [V2] = [fish, mid(fish, center, 0, 60), center]
            r1.append(mid(center, port, -20, -40))
            r1.append(port)
            var r2: [V2] = [baseGate, mid(base, center, -40, 0), center]
            r2.append(mid(center, plant, 30, 0))
            r2.append(plant)
            var r3: [V2] = [farm, mid(farm, plant, 0, 30), plant]
            r3.append(mid(plant, port, 0, 60))
            r3.append(port)
            let r4: [V2] = [hill, mid(hill, center, 10, -30), center]
            let r5: [V2] = [baseEast, mid(base, hill, 0, -50), hill]
            let r6: [V2] = [fish, mid(fish, farm, -40, 0), farm]
            roadDefs = [r1, r2, r3, r4, r5, r6]
        } else {
            let zDam: Float = -200
            let damX = terrain.riverX(zDam)
            let town = V2(230, 170)
            let lumber = V2(-330, -330)
            let base = V2(-310, 250)
            let resort = V2(380, -380)
            let radar = V2(-470, -40)
            let station = V2(damX + 120, -140)
            compound = (base, 3)
            towns = [
                Town(name: "冰河镇", p: town, radius: 105, count: 16, types: [.house1, .house2, .cabin, .house1, .barracks, .shed], tier: 2),
                Town(name: "林场", p: lumber, radius: 70, count: 9, types: [.cabin, .cabin, .shed, .warehouse], tier: 1),
                Town(name: "滑雪度假村", p: resort, radius: 70, count: 9, types: [.house2, .cabin, .house2, .shed], tier: 2),
                Town(name: "雷达站", p: radar, radius: 40, count: 4, types: [.barracks, .tower, .shed], tier: 2),
                Town(name: "水电站", p: station, radius: 55, count: 7, types: [.warehouse, .barracks, .container, .container], tier: 2),
            ]
            world.places = [PlaceName(name: "兵营", p: base), PlaceName(name: "大坝", p: V2(damX, zDam))] + towns.map { PlaceName(name: $0.name, p: $0.p) }
            let bridgeZ: Float = 330
            let bx = terrain.riverX(bridgeZ)
            roadDefs = [
                [lumber, V2(-250, -240), V2(damX - 110, zDam)],
                [V2(damX + 110, zDam), station, V2(300, -260), resort],
                [V2(base.x + 70, base.y), V2(-150, 300), V2(bx - 95, bridgeZ), V2(bx - 70, bridgeZ)],
                [V2(bx + 70, bridgeZ), V2(bx + 95, bridgeZ), V2(150, 280), town],
                [town, V2(220, 20), station],
                [radar, V2(-420, 100), V2(base.x, base.y - 55)],
                [radar, V2(-420, -200), lumber],
                [town, V2(360, 0), V2(420, -200), resort],
            ]
        }

        // roads
        for rd in roadDefs {
            let pts = catmull(rd, step: 8)
            world.roads.append(pts)
            if kind == .snow {
                // don't fill the river under bridges/dam approaches
                let saved = terrain.h
                terrain.applyRoad(pts, width: 7)
                for k in 0..<terrain.h.count where saved[k] < terrain.waterLevel + 0.5 {
                    terrain.h[k] = saved[k]
                }
            } else {
                terrain.applyRoad(pts, width: 7)
            }
        }

        // ---------- compounds ----------
        progress(0.63, "建造建筑…")
        if let comp = compound {
            let cp = comp.0
            let tier = comp.1
            let y = terrain.averageHeight(cx: cp.x, cz: cp.y, hx: 60, hz: 45).avg
            terrain.flattenRect(cx: cp.x, cz: cp.y, hx: 64, hz: 49, y: y, falloff: 20)
            rects.append((cp - V2(66, 51), cp + V2(66, 51)))
            let st = Buildings.Style(wall: .concrete, roof: .roofGray, flatRoof: true)
            let inner: [(BType, Float, Float, Int)] = [
                (.warehouse, -30, -22, 0), (.warehouse, 30, -22, 0),
                (.barracks, -36, 20, 2), (.barracks, 0, 28, 2), (.barracks, 36, 20, 2),
                (.container, -6, -2, 1), (.container, 4, -6, 0), (.container, 10, 6, 1), (.container, -14, 8, 0),
                (.tower, -55, -40, 0), (.tower, 55, -40, 0), (.tower, -55, 40, 0), (.tower, 55, 40, 0),
            ]
            for e in inner {
                place(e.0, at: cp + V2(e.1, e.2), rot: e.3, tier: tier, style: st, force: true, yOverride: y, flatten: false)
            }
            // perimeter wall with gates
            let wallCtx = BuildCtx(hi: chunks.hi[chunks.index(cp.x, cp.y)], lo: chunks.lo[chunks.index(cp.x, cp.y)], col: col,
                                   origin: V3(cp.x, y, cp.y), rot: 0, tier: tier)
            wallCtx.wallX(-60, 60, z: 45, t: 0.6, y0: -0.5, h: 3.2, openings: [(-6, 6, 0, 3.2)], .concrete)
            wallCtx.wallX(-60, 60, z: -45, t: 0.6, y0: -0.5, h: 3.2, openings: [(-6, 6, 0, 3.2)], .concrete)
            wallCtx.wallZ(-45, 45, x: -60, t: 0.6, y0: -0.5, h: 3.2, openings: [(-5, 5, 0, 3.2)], .concrete)
            wallCtx.wallZ(-45, 45, x: 60, t: 0.6, y0: -0.5, h: 3.2, openings: [(-5, 5, 0, 3.2)], .concrete)
            // sandbag nests
            for (sx, sz) in [(-20, 0), (20, 0), (0, -30)] as [(Float, Float)] {
                wallCtx.box(sx - 2, 0, sz - 0.4, sx + 2, 1.1, sz + 0.4, .sandbag, kind: .ground)
                wallCtx.box(sx - 2.4, 0, sz - 2, sx - 1.6, 1.1, sz + 0.4, .sandbag, kind: .ground)
            }
            world.loot.append(contentsOf: wallCtx.loot)
        }

        // special snow structures: dam and bridge
        if kind == .snow {
            let zDam: Float = -200
            let dx = terrain.riverX(zDam)
            let top: Float = 20
            terrain.flattenRect(cx: dx - 112, cz: zDam, hx: 14, hz: 14, y: top, falloff: 28)
            terrain.flattenRect(cx: dx + 112, cz: zDam, hx: 14, hz: 14, y: top, falloff: 28)
            rects.append((V2(dx - 130, zDam - 20), V2(dx + 130, zDam + 20)))
            let k = chunks.index(dx, zDam)
            let c = BuildCtx(hi: chunks.hi[k], lo: chunks.lo[k], col: col, origin: V3(dx, 0, zDam), rot: 0, tier: 2)
            c.box(-100, -4, -10, 100, 8, 10, .concrete)
            c.box(-100, 8, -6.5, 100, top, 6.5, .concrete)
            c.wallX(-100, 100, z: 6.0, t: 0.3, y0: top, h: 1.1, openings: [], .concreteDark)
            c.wallX(-100, 100, z: -6.0, t: 0.3, y0: top, h: 1.1, openings: [], .concreteDark)
            for gx in stride(from: -60, through: 60, by: 20) {
                c.box(Float(gx) - 3, 4, 6.5, Float(gx) + 3, top - 2, 7.4, .concreteDark, collide: false)
            }
            // control houses on top
            for hx in [-35, 35] as [Float] {
                c.box(hx - 4, top, -3.5, hx + 4, top + 0.1, 3.5, .concreteDark)
                c.wallX(hx - 4, hx + 4, z: 3.3, t: 0.25, y0: top, h: 3, openings: [(-1 + hx, 1 + hx, 0, 2.2)], .plasterC)
                c.wallX(hx - 4, hx + 4, z: -3.3, t: 0.25, y0: top, h: 3, openings: [(-1 + hx, 1 + hx, 0, 2.2)], .plasterC)
                c.wallZ(-3.2, 3.2, x: hx - 3.9, t: 0.25, y0: top, h: 3, openings: [(-1, 1, 1, 2)], .plasterC)
                c.wallZ(-3.2, 3.2, x: hx + 3.9, t: 0.25, y0: top, h: 3, openings: [(-1, 1, 1, 2)], .plasterC)
                c.box(hx - 4.3, top + 3, -3.6, hx + 4.3, top + 3.3, 3.6, .concreteDark)
                c.lootAt(hx - 2, top, -1.5)
                c.lootAt(hx + 2, top, 1.5)
            }
            c.lootAt(-70, top, 0)
            c.lootAt(70, top, 0)
            world.loot.append(contentsOf: c.loot)

            // bridge
            let zB: Float = 330
            let bx = terrain.riverX(zB)
            let deck = terrain.waterLevel + 5
            terrain.flattenRect(cx: bx - 92, cz: zB, hx: 10, hz: 6, y: deck, falloff: 22)
            terrain.flattenRect(cx: bx + 92, cz: zB, hx: 10, hz: 6, y: deck, falloff: 22)
            let kb = chunks.index(bx, zB)
            let b = BuildCtx(hi: chunks.hi[kb], lo: chunks.lo[kb], col: col, origin: V3(bx, deck, zB), rot: 0, tier: 1)
            b.box(-90, -0.7, -4.5, 90, 0, 4.5, .concrete)
            b.wallX(-90, 90, z: 4.3, t: 0.3, y0: 0, h: 1.0, openings: [], .concreteDark)
            b.wallX(-90, 90, z: -4.3, t: 0.3, y0: 0, h: 1.0, openings: [], .concreteDark)
            for px in stride(from: -60, through: 60, by: 30) {
                b.box(Float(px) - 1.2, -14, -3.5, Float(px) + 1.2, -0.7, 3.5, .concreteDark)
            }
            // abandoned cars as cover on the bridge
            b.box(-30, 0, -3.5, -25.5, 1.5, -1.6, .metalRust, kind: .metal)
            b.box(18, 0, 0.8, 22.5, 1.5, 2.8, .contBlue, kind: .metal)
            b.lootAt(-27, 0, 1)
            b.lootAt(20, 0, -1.5)
            world.loot.append(contentsOf: b.loot)
            rects.append((V2(bx - 100, zB - 8), V2(bx + 100, zB + 8)))
        }

        // ---------- towns ----------
        for t in towns {
            var n = 0
            var tries = 0
            while n < t.count && tries < t.count * 25 {
                tries += 1
                let off = rng.inDisc(t.radius)
                let p = t.p + off
                let type = rng.pick(t.types)
                let st = styleFor(&rng)
                if place(type, at: p, rot: rng.i(4), tier: t.tier, style: st) { n += 1 }
            }
        }
        // scattered buildings
        var scattered = 0
        var stries = 0
        while scattered < 26 && stries < 1500 {
            stries += 1
            let p = V2(rng.r(-620, 620), rng.r(-620, 620))
            let type: BType = kind == .snow ? (rng.chance(0.6) ? .cabin : .shed) : (rng.chance(0.5) ? .house1 : (rng.chance(0.5) ? .shed : .house2))
            let st = styleFor(&rng)
            if place(type, at: p, rot: rng.i(4), tier: 1, style: st) { scattered += 1 }
        }

        // ---------- splat & terrain ----------
        progress(0.68, "绘制地表…")
        let splat = terrain.buildSplat(noise: noise, assets: assets)
        progress(0.76, "构建地形网格…")
        let tmat = terrain.makeMaterial(assets: assets, splat: splat)
        world.terrainNode = terrain.buildNodes(material: tmat)
        world.waterNode = terrain.waterNode(assets: assets)

        // ---------- building meshes ----------
        progress(0.80, "构建建筑网格…")
        for pl in placed {
            let k = chunks.index(pl.c.x, pl.c.z)
            let ctx = BuildCtx(hi: chunks.hi[k], lo: chunks.lo[k], col: col, origin: pl.c, rot: pl.rot, tier: pl.tier)
            Buildings.build(pl.type, ctx: ctx, style: pl.style, rng: &rng)
            world.loot.append(contentsOf: ctx.loot)
            world.doors.append(contentsOf: ctx.doors)
            let he = halfExt(pl.type, pl.rot)
            world.footprints.append((V2(pl.c.x, pl.c.z) - he, V2(pl.c.x, pl.c.z) + he))
        }

        // ---------- props: power poles along roads, fences ----------
        for (ri, road) in world.roads.enumerated() {
            var acc: Float = 0
            for i in 1..<road.count {
                acc += simd_length(road[i] - road[i - 1])
                if acc > 45 {
                    acc = 0
                    let d = vnorm2(road[i] - road[i - 1])
                    let side = V2(-d.y, d.x) * (ri % 2 == 0 ? 6.5 : -6.5)
                    let p2 = road[i] + side
                    let y = terrain.height(p2.x, p2.y)
                    if y < terrain.waterLevel + 0.5 { continue }
                    var blockedPole = false
                    for r in rects where p2.x > r.0.x && p2.x < r.1.x && p2.y > r.0.y && p2.y < r.1.y { blockedPole = true; break }
                    if blockedPole { continue }
                    let k = chunks.index(p2.x, p2.y)
                    let base = V3(p2.x, y - 0.5, p2.y)
                    let m = mTranslate(base)
                    chunks.hi[k].cylinder(Mt.woodDark.rawValue, r0: 0.14, r1: 0.11, y0: 0, y1: 8.5, seg: 6, m: m, caps: false)
                    chunks.lo[k].cylinder(Mt.woodDark.rawValue, r0: 0.14, r1: 0.11, y0: 0, y1: 8.5, seg: 3, m: m, caps: false)
                    let ang = atan2(d.y, d.x)
                    let mb = mTranslate(base + V3(0, 7.8, 0)) * mRotY(-ang + kPi / 2)
                    chunks.hi[k].box(Mt.woodDark.rawValue, min: V3(-1.1, 0, -0.06), max: V3(1.1, 0.12, 0.06), m: mb)
                    col.addCyl(x: p2.x, z: p2.y, r: 0.18, y0: y - 1, y1: y + 8.5, kind: .wood)
                }
            }
        }

        // ---------- vegetation ----------
        progress(0.84, "种植森林…")
        func nearRect(_ x: Float, _ z: Float, _ m: Float) -> Bool {
            for r in rects where x > r.0.x - m && x < r.1.x + m && z > r.0.y - m && z < r.1.y + m { return true }
            return false
        }
        let treeTarget = kind == .snow ? 2700 : 2300
        var trees = 0
        var tt = 0
        while trees < treeTarget && tt < 40000 {
            tt += 1
            let x = rng.r(-790, 790), z = rng.r(-790, 790)
            let forest = noise.fbm(x * 0.0055 + 13, z * 0.0055 + 2, oct: 4) * 0.5 + 0.5
            let thresh: Float = kind == .snow ? 0.47 : 0.52
            if forest < thresh && !rng.chance(0.06) { continue }
            let y = terrain.height(x, z)
            if y < terrain.waterLevel + 1.0 { continue }
            if terrain.roadDistance(x, z) < 6 { continue }
            if nearRect(x, z, 3) { continue }
            let nn = terrain.normal(x, z)
            if nn.y < 0.72 { continue }
            let k = chunks.index(x, z)
            let s = rng.r(0.75, 1.35)
            let yaw = rng.r(0, kTwoPi)
            let p = V3(x, y, z)
            let pine = kind == .snow ? !rng.chance(0.08) : rng.chance(0.55)
            var r1 = RNG(rng.next())
            var r2 = r1
            if pine {
                Vegetation.pine(chunks.hi[k], at: p, scale: s, yaw: yaw, lod: 0, rng: &r1)
                Vegetation.pine(chunks.lo[k], at: p, scale: s, yaw: yaw, lod: 1, rng: &r2)
                col.addCyl(x: x, z: z, r: 0.3 * s, y0: y - 1, y1: y + 11 * s, kind: .wood)
            } else {
                Vegetation.broadleaf(chunks.hi[k], at: p, scale: s, yaw: yaw, lod: 0, rng: &r1, noise: noise)
                Vegetation.broadleaf(chunks.lo[k], at: p, scale: s, yaw: yaw, lod: 1, rng: &r2, noise: noise)
                col.addCyl(x: x, z: z, r: 0.32 * s, y0: y - 1, y1: y + 6.5 * s, kind: .wood)
            }
            trees += 1
        }
        progress(0.88, "摆放岩石…")
        var rocks = 0
        var rt = 0
        while rocks < 520 && rt < 10000 {
            rt += 1
            let x = rng.r(-780, 780), z = rng.r(-780, 780)
            let y = terrain.height(x, z)
            if y < terrain.waterLevel - 1 { continue }
            if terrain.roadDistance(x, z) < 5 || nearRect(x, z, 2) { continue }
            let big = rng.chance(0.25)
            let sx = big ? rng.r(2.5, 5.5) : rng.r(0.7, 1.8)
            let size = V3(sx, sx * rng.r(0.45, 0.8), sx * rng.r(0.7, 1.1))
            let k = chunks.index(x, z)
            let p = V3(x, y - size.y * 0.25, z)
            let yaw = rng.r(0, kTwoPi)
            let seed = rng.r(0, 100)
            let res = Vegetation.rock(chunks.hi[k], at: p, size: size, yaw: yaw, lod: 0, noise: noise, seed: seed)
            Vegetation.rock(chunks.lo[k], at: p, size: size, yaw: yaw, lod: 1, noise: noise, seed: seed)
            col.addCyl(x: x, z: z, r: res.r * 0.8, y0: y - 2, y1: res.top, kind: .rock)
            rocks += 1
        }
        var bushes = 0
        var bt = 0
        let bushTarget = kind == .snow ? 500 : 1100
        while bushes < bushTarget && bt < 12000 {
            bt += 1
            let x = rng.r(-780, 780), z = rng.r(-780, 780)
            let y = terrain.height(x, z)
            if y < terrain.waterLevel + 0.5 { continue }
            if terrain.roadDistance(x, z) < 4 || nearRect(x, z, 1) { continue }
            let k = chunks.index(x, z)
            Vegetation.bush(chunks.hi[k], at: V3(x, y, z), scale: rng.r(0.7, 1.4), rng: &rng, noise: noise, dead: kind == .snow)
            bushes += 1
        }
        // flavour props
        if kind == .snow {
            for _ in 0..<14 {
                let p = towns[1].p + rng.inDisc(60)
                let y = terrain.height(p.x, p.y)
                if nearRect(p.x, p.y, 1) || terrain.roadDistance(p.x, p.y) < 5 { continue }
                let k = chunks.index(p.x, p.y)
                Vegetation.logPile(chunks.hi[k], at: V3(p.x, y, p.y), yaw: rng.r(0, kPi))
                col.addBox(V3(p.x - 2.6, y - 1, p.y - 2.6), V3(p.x + 2.6, y + 1.2, p.y + 2.6), kind: .wood)
            }
        } else {
            for _ in 0..<16 {
                let p = towns[3].p + rng.inDisc(80)
                let y = terrain.height(p.x, p.y)
                if nearRect(p.x, p.y, 1) || terrain.roadDistance(p.x, p.y) < 5 { continue }
                let k = chunks.index(p.x, p.y)
                Vegetation.haystack(chunks.hi[k], at: V3(p.x, y, p.y))
                Vegetation.haystack(chunks.lo[k], at: V3(p.x, y, p.y))
                col.addCyl(x: p.x, z: p.y, r: 1.25, y0: y - 1, y1: y + 2.4, kind: .ground)
            }
        }
        // wrecked cars along roads as cover
        for _ in 0..<30 {
            let road = rng.pick(world.roads)
            let i = rng.i(max(1, road.count - 1))
            if i + 1 >= road.count { continue }
            let d = vnorm2(road[i + 1] - road[i])
            let side = V2(-d.y, d.x) * rng.r(4, 7) * rng.sign()
            let p = road[i] + side
            let y = terrain.height(p.x, p.y)
            if y < terrain.waterLevel + 0.5 || nearRect(p.x, p.y, 1) { continue }
            let k = chunks.index(p.x, p.y)
            let c = BuildCtx(hi: chunks.hi[k], lo: chunks.lo[k], col: col, origin: V3(p.x, y, p.y), rot: rng.i(4), tier: 1)
            let mat: Mt = rng.pick([.metalRust, .contBlue, .contRed, .metalGray])
            c.box(-2.2, 0, -0.95, 2.2, 0.9, 0.95, mat, kind: .metal)
            c.box(-1.0, 0.9, -0.85, 1.2, 1.5, 0.85, mat, kind: .metal)
            c.box(-1.6, 0.0, -1.0, -1.0, 0.6, 1.0, .black, collide: false)
            c.box(1.0, 0.0, -1.0, 1.6, 0.6, 1.0, .black, collide: false)
        }

        // ---------- vehicles ----------
        var vs = 0
        var vt = 0
        while vs < 16 && vt < 500 {
            vt += 1
            let road = rng.pick(world.roads)
            if road.count < 3 { continue }
            let i = 1 + rng.i(road.count - 2)
            let d = vnorm2(road[i + 1] - road[i])
            let p = road[i] + V2(-d.y, d.x) * 2.0
            let y = terrain.height(p.x, p.y)
            if y < terrain.waterLevel + 0.5 { continue }
            var tooClose = false
            for v in world.vehicleSpawns where distXZ(v.p, V3(p.x, 0, p.y)) < 120 { tooClose = true; break }
            if tooClose { continue }
            world.vehicleSpawns.append((p: V3(p.x, y, p.y), yaw: yawOf(V3(d.x, 0, d.y))))
            vs += 1
        }

        progress(0.92, "合并网格…")
        world.staticNode = chunks.buildNode(assets: assets, terrain: terrain)

        let grass = GrassField(terrain: terrain, col: col, card: assets.grassCard, radius: grassRadius, density: grassDensity)
        grass.blockers = rects.map { ($0.0 + V2(1.5, 1.5), $0.1 - V2(1.5, 1.5)) }
        world.grass = grass

        // ---------- minimap ----------
        progress(0.96, "绘制地图…")
        world.minimap = drawMinimap(base: splat.minimap, world: world)
        progress(1.0, "完成")
        return world
    }

    static func drawMinimap(base: UIImage, world: WorldData) -> UIImage {
        let size = CGSize(width: 1024, height: 1024)
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = 1
        fmt.opaque = true
        let r = UIGraphicsImageRenderer(size: size, format: fmt)
        return r.image { ctx in
            base.draw(in: CGRect(origin: .zero, size: size))
            let g = ctx.cgContext
            func mp(_ p: V2) -> CGPoint {
                return CGPoint(x: CGFloat((p.x + 800) / 1600) * size.width, y: CGFloat((p.y + 800) / 1600) * size.height)
            }
            g.setFillColor(UIColor(white: 0.25, alpha: 0.9).cgColor)
            for f in world.footprints {
                let a = mp(f.0), b = mp(f.1)
                g.fill(CGRect(x: a.x, y: a.y, width: max(2, b.x - a.x), height: max(2, b.y - a.y)))
            }
            // grid
            g.setStrokeColor(UIColor(white: 1, alpha: 0.12).cgColor)
            g.setLineWidth(1)
            for k in 1..<8 {
                let v = CGFloat(k) * size.width / 8
                g.move(to: CGPoint(x: v, y: 0)); g.addLine(to: CGPoint(x: v, y: size.height))
                g.move(to: CGPoint(x: 0, y: v)); g.addLine(to: CGPoint(x: size.width, y: v))
            }
            g.strokePath()
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 22),
                .foregroundColor: UIColor.white,
                .strokeColor: UIColor.black,
                .strokeWidth: -3.0,
            ]
            for pl in world.places {
                let p = mp(pl.p)
                let s = NSAttributedString(string: pl.name, attributes: attrs)
                let sz = s.size()
                s.draw(at: CGPoint(x: p.x - sz.width / 2, y: p.y - sz.height / 2 - 26))
            }
        }
    }
}
