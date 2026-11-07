import UIKit
import SceneKit

enum MapKind: Int {
    case island = 0
    case snow = 1

    var title: String {
        switch self {
        case .island: return "翠屿"
        case .snow: return "冰河峡谷"
        }
    }
    var subtitle: String {
        switch self {
        case .island: return "海岛 · 草原 · 小镇 · 军事基地"
        case .snow: return "雪山 · 冰河 · 大坝 · 林场"
        }
    }
}

/// Material ids used by MeshBuilder groups.
enum Mt: Int {
    case bark = 1, needles, leaves, rock, concrete, concreteDark, plasterA, plasterB, plasterC, brick
    case wood, woodDark, roofRed, roofGray, roofSnow, metalGray, metalRust, contRed, contBlue, contGreen, contYellow
    case floorTile, crate, sandbag, darkGlass, asphalt, soldier0, soldier1, soldier2, soldier3, soldier4
    case gun, vehicleA, vehicleB, vehicleC, chute, planeBody, black, white, lootAmmo, lootMed, lootArmor, lootScope, lootBag
}

/// Generates every texture and material for a given map (runs on a background thread while loading).
final class Assets {
    let kind: MapKind
    let noise: Noise
    var mats: [Int: SCNMaterial] = [:]

    // terrain textures
    var grass: TexSet!
    var rock: TexSet!
    var snowTex: TexSet!
    var sandTex: TexSet!
    var road: TexSet!
    var grassCard: CGImage!
    var waterNormal: CGImage!
    var smoke: CGImage!
    var dust: CGImage!
    var spark: CGImage!
    var flash: CGImage!
    var fire: CGImage!
    var sunGlow: CGImage!
    var zoneWall: CGImage!
    var skyFaces: [CGImage] = []

    var sunDir: V3
    var sunColor: UIColor
    var fogColor: UIColor
    var horizon: V3
    var zenith: V3

    init(kind: MapKind) {
        self.kind = kind
        noise = Noise(seed: 1234 + UInt64(kind.rawValue) * 77)
        switch kind {
        case .island:
            sunDir = vnorm(V3(-0.55, 0.62, 0.45))
            sunColor = UIColor(red: 1.0, green: 0.94, blue: 0.84, alpha: 1)
            horizon = V3(0.72, 0.80, 0.88)
            zenith = V3(0.22, 0.42, 0.75)
        case .snow:
            sunDir = vnorm(V3(0.6, 0.42, -0.55))
            sunColor = UIColor(red: 1.0, green: 0.93, blue: 0.86, alpha: 1)
            horizon = V3(0.78, 0.82, 0.88)
            zenith = V3(0.34, 0.48, 0.70)
        }
        fogColor = UIColor(red: CGFloat(horizon.x), green: CGFloat(horizon.y), blue: CGFloat(horizon.z), alpha: 1)
    }

    func m(_ id: Mt) -> SCNMaterial { return mats[id.rawValue] ?? mats[Mt.concrete.rawValue]! }
    func mat(_ id: Int) -> SCNMaterial { return mats[id] ?? mats[Mt.concrete.rawValue]! }

    static func pbr(_ ts: TexSet?, color: UIColor? = nil, rough: CGFloat, metal: CGFloat = 0, tile: Float? = nil,
                    normalIntensity: CGFloat = 1, doubleSided: Bool = false) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        if let t = ts {
            m.diffuse.contents = t.albedo
            if let n = t.normal {
                m.normal.contents = n
                m.normal.intensity = normalIntensity
            }
        } else {
            m.diffuse.contents = color ?? UIColor.gray
        }
        m.roughness.contents = NSNumber(value: Double(rough))
        m.metalness.contents = NSNumber(value: Double(metal))
        for p in [m.diffuse, m.normal] {
            p.wrapS = .repeat
            p.wrapT = .repeat
            p.mipFilter = .linear
            p.minificationFilter = .linear
            p.magnificationFilter = .linear
            p.maxAnisotropy = 8
            if let t = tile {
                p.contentsTransform = SCNMatrix4MakeScale(1 / t, 1 / t, 1)
            }
        }
        m.isDoubleSided = doubleSided
        return m
    }

    func generate(progress: (Float) -> Void) {
        let nz = noise
        let snowy = kind == .snow
        progress(0.02)
        grass = TexGen.grassGround(nz, dry: snowy, seed: 11)
        rock = TexGen.rock(nz, tint: snowy ? V3(0.46, 0.47, 0.49) : V3(0.48, 0.46, 0.42), seed: 12)
        progress(0.06)
        snowTex = TexGen.snow(nz, seed: 13)
        sandTex = TexGen.sand(nz, seed: 14)
        road = TexGen.gravel(nz, seed: 15, base: snowy ? V3(0.40, 0.38, 0.36) : V3(0.46, 0.40, 0.31))
        progress(0.10)
        grassCard = TexGen.grassCard(seed: 16, dry: snowy)
        waterNormal = TexGen.waterNormal(nz)
        smoke = TexGen.radialSprite(size: 64, color: V3(0.85, 0.85, 0.85), hardness: 0.6, noise: nz)
        dust = TexGen.radialSprite(size: 64, color: snowy ? V3(0.9, 0.9, 0.92) : V3(0.6, 0.52, 0.40), hardness: 0.5, noise: nz)
        spark = TexGen.radialSprite(size: 32, color: V3(1.0, 0.8, 0.4), hardness: 2.5, noise: nil)
        fire = TexGen.radialSprite(size: 64, color: V3(1.0, 0.55, 0.15), hardness: 0.8, noise: nz)
        sunGlow = TexGen.radialSprite(size: 256, color: V3(1.0, 0.95, 0.82), hardness: 0.25, noise: nil)
        flash = TexGen.flashSprite()
        zoneWall = TexGen.zoneWall()
        progress(0.14)

        // static world materials
        let bark = TexGen.bark(nz, base: snowy ? V3(0.30, 0.26, 0.22) : V3(0.34, 0.26, 0.18))
        mats[Mt.bark.rawValue] = Assets.pbr(bark, rough: 0.95, tile: 1.2)
        let needles = TexGen.needles(nz, seed: 21, snowy: snowy)
        mats[Mt.needles.rawValue] = Assets.pbr(needles, rough: 0.9, tile: 2.5, doubleSided: true)
        let leaves = TexGen.leaves(nz, seed: 22, autumn: snowy)
        mats[Mt.leaves.rawValue] = Assets.pbr(leaves, rough: 0.85, tile: 2.0, doubleSided: true)
        mats[Mt.rock.rawValue] = Assets.pbr(rock, rough: 0.9, tile: 3.5, normalIntensity: 1.2)
        progress(0.20)
        let concrete = TexGen.concrete(nz, base: V3(0.56, 0.56, 0.54), seams: true)
        mats[Mt.concrete.rawValue] = Assets.pbr(concrete, rough: 0.9, tile: 4)
        let concreteDark = TexGen.concrete(nz, base: V3(0.40, 0.40, 0.39), seams: false)
        mats[Mt.concreteDark.rawValue] = Assets.pbr(concreteDark, rough: 0.92, tile: 3)
        let plasterA = TexGen.concrete(nz, base: V3(0.80, 0.77, 0.70), seams: false)
        mats[Mt.plasterA.rawValue] = Assets.pbr(plasterA, rough: 0.9, tile: 3)
        let plasterB = TexGen.concrete(nz, base: V3(0.78, 0.66, 0.45), seams: false)
        mats[Mt.plasterB.rawValue] = Assets.pbr(plasterB, rough: 0.9, tile: 3)
        let plasterC = TexGen.concrete(nz, base: V3(0.55, 0.64, 0.66), seams: false)
        mats[Mt.plasterC.rawValue] = Assets.pbr(plasterC, rough: 0.9, tile: 3)
        progress(0.28)
        let brick = TexGen.brick(nz, seed: 31, base: V3(0.55, 0.28, 0.20))
        mats[Mt.brick.rawValue] = Assets.pbr(brick, rough: 0.9, tile: 2.2)
        let wood = TexGen.planks(nz, seed: 32, base: V3(0.50, 0.36, 0.22))
        mats[Mt.wood.rawValue] = Assets.pbr(wood, rough: 0.85, tile: 2.0)
        let woodDark = TexGen.planks(nz, seed: 33, base: V3(0.30, 0.22, 0.15))
        mats[Mt.woodDark.rawValue] = Assets.pbr(woodDark, rough: 0.88, tile: 2.0)
        let roofRed = TexGen.roofTiles(nz, seed: 34, base: V3(0.55, 0.22, 0.15))
        mats[Mt.roofRed.rawValue] = Assets.pbr(roofRed, rough: 0.8, tile: 2.5)
        let roofGray = TexGen.roofTiles(nz, seed: 35, base: V3(0.28, 0.30, 0.32))
        mats[Mt.roofGray.rawValue] = Assets.pbr(roofGray, rough: 0.8, tile: 2.5)
        mats[Mt.roofSnow.rawValue] = Assets.pbr(snowTex, rough: 0.85, tile: 4)
        progress(0.36)
        let metalGray = TexGen.corrugated(nz, base: V3(0.50, 0.52, 0.53), rust: 0.3)
        mats[Mt.metalGray.rawValue] = Assets.pbr(metalGray, rough: 0.55, metal: 0.6, tile: 2)
        let metalRust = TexGen.corrugated(nz, base: V3(0.45, 0.40, 0.35), rust: 1.0)
        mats[Mt.metalRust.rawValue] = Assets.pbr(metalRust, rough: 0.7, metal: 0.4, tile: 2)
        let cRed = TexGen.corrugated(nz, base: V3(0.55, 0.15, 0.10), rust: 0.4)
        mats[Mt.contRed.rawValue] = Assets.pbr(cRed, rough: 0.6, metal: 0.4, tile: 2)
        let cBlue = TexGen.corrugated(nz, base: V3(0.12, 0.28, 0.50), rust: 0.4)
        mats[Mt.contBlue.rawValue] = Assets.pbr(cBlue, rough: 0.6, metal: 0.4, tile: 2)
        let cGreen = TexGen.corrugated(nz, base: V3(0.18, 0.35, 0.20), rust: 0.4)
        mats[Mt.contGreen.rawValue] = Assets.pbr(cGreen, rough: 0.6, metal: 0.4, tile: 2)
        let cYellow = TexGen.corrugated(nz, base: V3(0.70, 0.52, 0.12), rust: 0.4)
        mats[Mt.contYellow.rawValue] = Assets.pbr(cYellow, rough: 0.6, metal: 0.4, tile: 2)
        progress(0.44)
        let tiles = TexGen.floorTiles(nz, base: V3(0.62, 0.58, 0.52))
        mats[Mt.floorTile.rawValue] = Assets.pbr(tiles, rough: 0.6, tile: 2)
        let crate = TexGen.crate(nz)
        mats[Mt.crate.rawValue] = Assets.pbr(crate, rough: 0.85)
        let sandbag = TexGen.concrete(nz, base: V3(0.55, 0.50, 0.38), seams: false)
        mats[Mt.sandbag.rawValue] = Assets.pbr(sandbag, rough: 0.95, tile: 1)
        mats[Mt.darkGlass.rawValue] = Assets.pbr(nil, color: UIColor(white: 0.05, alpha: 1), rough: 0.1, metal: 0.2)
        mats[Mt.asphalt.rawValue] = Assets.pbr(road, rough: 0.95, tile: 4)
        mats[Mt.black.rawValue] = Assets.pbr(nil, color: UIColor(white: 0.06, alpha: 1), rough: 0.6)
        mats[Mt.white.rawValue] = Assets.pbr(nil, color: UIColor(white: 0.85, alpha: 1), rough: 0.6)
        progress(0.50)

        // characters
        let skinTones: [Float] = [0.15, 0.35, 0.25, 0.55, 0.2]
        for v in 0..<5 {
            let atlas = TexGen.soldierAtlas(nz, variant: v, skinTone: skinTones[v])
            let mm = Assets.pbr(atlas, rough: 0.85, normalIntensity: 0.6)
            for p in [mm.diffuse, mm.normal] { p.wrapS = .clamp; p.wrapT = .clamp; p.contentsTransform = SCNMatrix4Identity }
            mats[Mt.soldier0.rawValue + v] = mm
        }
        progress(0.60)
        let gun = TexGen.gunAtlas(nz)
        let gm = Assets.pbr(gun, rough: 0.45, metal: 0.5)
        for p in [gm.diffuse] { p.wrapS = .clamp; p.wrapT = .clamp }
        mats[Mt.gun.rawValue] = gm
        let paints: [V3] = [V3(0.28, 0.32, 0.20), V3(0.62, 0.55, 0.40), V3(0.55, 0.12, 0.10)]
        for (i, c) in paints.enumerated() {
            let atlas = TexGen.vehicleAtlas(nz, paint: c)
            let vm = Assets.pbr(atlas, rough: 0.5, metal: 0.3, normalIntensity: 0.4)
            for p in [vm.diffuse, vm.normal] { p.wrapS = .clamp; p.wrapT = .clamp }
            mats[Mt.vehicleA.rawValue + i] = vm
        }
        let chute = TexGen.parachute()
        mats[Mt.chute.rawValue] = Assets.pbr(chute, rough: 0.8, doubleSided: true)
        mats[Mt.planeBody.rawValue] = Assets.pbr(nil, color: UIColor(red: 0.42, green: 0.45, blue: 0.40, alpha: 1), rough: 0.5, metal: 0.6)
        mats[Mt.lootAmmo.rawValue] = Assets.pbr(nil, color: UIColor(red: 0.30, green: 0.36, blue: 0.20, alpha: 1), rough: 0.6, metal: 0.3)
        mats[Mt.lootMed.rawValue] = Assets.pbr(nil, color: UIColor(red: 0.85, green: 0.85, blue: 0.82, alpha: 1), rough: 0.5)
        mats[Mt.lootArmor.rawValue] = Assets.pbr(nil, color: UIColor(red: 0.22, green: 0.25, blue: 0.18, alpha: 1), rough: 0.8)
        mats[Mt.lootScope.rawValue] = Assets.pbr(nil, color: UIColor(white: 0.12, alpha: 1), rough: 0.35, metal: 0.7)
        mats[Mt.lootBag.rawValue] = Assets.pbr(nil, color: UIColor(red: 0.35, green: 0.32, blue: 0.22, alpha: 1), rough: 0.9)
        progress(0.66)

        skyFaces = SkyGen.cube(size: 512, sunDir: sunDir, zenith: zenith, horizon: horizon,
                               ground: kind == .snow ? V3(0.55, 0.57, 0.60) : V3(0.30, 0.32, 0.30),
                               cloud: kind == .snow ? 0.55 : 0.42, noise: nz)
        progress(0.72)
    }
}

enum SkyGen {
    /// Six faces in SceneKit cube-map order: +X, -X, +Y, -Y, +Z, -Z
    static func cube(size: Int, sunDir: V3, zenith: V3, horizon: V3, ground: V3, cloud: Float, noise: Noise) -> [CGImage] {
        var faces: [CGImage] = []
        for f in 0..<6 {
            let img = Img(size, size)
            for y in 0..<size {
                let vv = (Float(y) + 0.5) / Float(size) * 2 - 1
                for x in 0..<size {
                    let uu = (Float(x) + 0.5) / Float(size) * 2 - 1
                    var d: V3
                    switch f {
                    case 0: d = V3(1, -vv, -uu)
                    case 1: d = V3(-1, -vv, uu)
                    case 2: d = V3(uu, 1, vv)
                    case 3: d = V3(uu, -1, -vv)
                    case 4: d = V3(uu, -vv, 1)
                    default: d = V3(-uu, -vv, -1)
                    }
                    d = vnorm(d)
                    img.set(x, y, skyColor(d, sunDir: sunDir, zenith: zenith, horizon: horizon, ground: ground, cloud: cloud, noise: noise))
                }
            }
            faces.append(img.cg())
        }
        return faces
    }

    static func skyColor(_ d: V3, sunDir: V3, zenith: V3, horizon: V3, ground: V3, cloud: Float, noise: Noise) -> V3 {
        let e = d.y
        let cosSun = max(0, vdot(d, sunDir))
        if e < 0 {
            let t = smoothstepf(0, 0.12, -e)
            return lerp3(horizon * 0.95, ground, t)
        }
        let t = pow(1 - e, 4)
        var c = lerp3(zenith, horizon, t)
        // warm halo around the sun
        let halo1: Float = pow(cosSun, 8) * 0.25
        let halo2: Float = pow(cosSun, 64) * 0.5
        c += V3(1.0, 0.85, 0.6) * (halo1 + halo2)
        // clouds on a virtual plane
        if e > 0.015 {
            let k = 1 / (e + 0.06)
            let px = d.x * k * 1.4, pz = d.z * k * 1.4
            let n1 = noise.fbm(px + 100, pz + 50, oct: 6) * 0.5 + 0.5
            let n2 = noise.fbm(px * 3 + 7, pz * 3 + 9, oct: 3) * 0.5 + 0.5
            let cov = smoothstepf(1 - cloud, 1 - cloud + 0.25, n1 * 0.85 + n2 * 0.15)
            let fade = smoothstepf(0.015, 0.25, e)
            let shade: Float = 0.78 + 0.22 * smoothstepf(0.4, 0.9, n2)
            let lit: Float = 1.0 + pow(cosSun, 6) * 0.4
            let cloudCol = V3(0.97, 0.97, 0.98) * (shade * lit)
            c = lerp3(c, cloudCol, cov * fade * 0.9)
        }
        return c
    }
}
