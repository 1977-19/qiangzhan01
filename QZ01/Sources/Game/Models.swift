import SceneKit
import simd

/// Procedural models for weapons, soldiers, vehicles, plane, parachute and loot.
enum Models {
    static var gunCache: [Int: SCNGeometry] = [:]
    static var lootCache: [String: SCNGeometry] = [:]
    static let cacheLock = Lock()

    // MARK: Guns

    static func addScope(_ mb: MeshBuilder, _ s: ScopeType, z: Float, y: Float) {
        let g = Mt.gun.rawValue
        let met = GunUV.metal
        switch s {
        case .none:
            break
        case .redDot:
            mb.box(g, min: V3(-0.015, y, z - 0.025), max: V3(0.015, y + 0.015, z + 0.025), uv: met)
            mb.box(g, min: V3(-0.02, y + 0.015, z - 0.03), max: V3(0.02, y + 0.055, z + 0.02), uv: met)
        case .x2:
            mb.box(g, min: V3(-0.012, y, z - 0.04), max: V3(0.012, y + 0.02, z + 0.04), uv: met)
            mb.tube(g, from: V3(0, y + 0.04, z + 0.07), to: V3(0, y + 0.04, z - 0.07), r0: 0.022, r1: 0.022, seg: 10, uv: met)
        case .x4:
            mb.box(g, min: V3(-0.012, y, z - 0.08), max: V3(0.012, y + 0.02, z - 0.05), uv: met)
            mb.box(g, min: V3(-0.012, y, z + 0.05), max: V3(0.012, y + 0.02, z + 0.08), uv: met)
            mb.tube(g, from: V3(0, y + 0.04, z + 0.12), to: V3(0, y + 0.04, z - 0.1), r0: 0.018, r1: 0.018, seg: 10, uv: met)
            mb.tube(g, from: V3(0, y + 0.04, z - 0.1), to: V3(0, y + 0.04, z - 0.16), r0: 0.018, r1: 0.027, seg: 10, uv: met)
            mb.tube(g, from: V3(0, y + 0.04, z + 0.16), to: V3(0, y + 0.04, z + 0.12), r0: 0.022, r1: 0.018, seg: 10, uv: met)
        case .x8:
            mb.box(g, min: V3(-0.012, y, z - 0.09), max: V3(0.012, y + 0.022, z - 0.06), uv: met)
            mb.box(g, min: V3(-0.012, y, z + 0.06), max: V3(0.012, y + 0.022, z + 0.09), uv: met)
            mb.tube(g, from: V3(0, y + 0.045, z + 0.14), to: V3(0, y + 0.045, z - 0.14), r0: 0.019, r1: 0.019, seg: 12, uv: met)
            mb.tube(g, from: V3(0, y + 0.045, z - 0.14), to: V3(0, y + 0.045, z - 0.22), r0: 0.019, r1: 0.033, seg: 12, uv: met)
            mb.tube(g, from: V3(0, y + 0.045, z + 0.2), to: V3(0, y + 0.045, z + 0.14), r0: 0.023, r1: 0.019, seg: 12, uv: met)
            mb.tube(g, from: V3(0.019, y + 0.045, z), to: V3(0.035, y + 0.045, z), r0: 0.01, r1: 0.01, seg: 8, uv: met)
        }
    }

    static func gun(_ t: WeaponType, scope: ScopeType, assets: Assets) -> SCNGeometry {
        let key = t.rawValue * 10 + scope.rawValue
        if let c = cacheLock.run({ gunCache[key] }) { return c }
        let mb = MeshBuilder()
        let g = Mt.gun.rawValue
        let met = GunUV.metal, pol = GunUV.polymer, wood = GunUV.wood, tan = GunUV.tan
        switch t {
        case .m416:
            mb.box(g, min: V3(-0.028, 0.0, -0.20), max: V3(0.028, 0.07, 0.14), uv: met)
            mb.box(g, min: V3(-0.025, -0.045, -0.13), max: V3(0.025, 0.0, 0.07), uv: met)
            mb.box(g, min: V3(-0.034, -0.012, -0.52), max: V3(0.034, 0.066, -0.20), uv: tan)
            mb.tube(g, from: V3(0, 0.03, -0.52), to: V3(0, 0.03, -0.72), r0: 0.011, r1: 0.011, seg: 8, uv: met)
            mb.tube(g, from: V3(0, 0.03, -0.72), to: V3(0, 0.03, -0.78), r0: 0.017, r1: 0.017, seg: 8, uv: met)
            mb.box(g, min: V3(-0.016, -0.17, -0.035), max: V3(0.016, 0, 0.035), m: mTranslate(V3(0, -0.04, -0.07)) * mRotX(0.25), uv: met)
            mb.box(g, min: V3(-0.016, -0.1, -0.022), max: V3(0.016, 0, 0.022), m: mTranslate(V3(0, -0.04, 0.05)) * mRotX(-0.3), uv: pol)
            mb.box(g, min: V3(-0.022, -0.035, 0.14), max: V3(0.022, 0.055, 0.36), uv: pol)
            mb.box(g, min: V3(-0.014, 0.07, -0.48), max: V3(0.014, 0.085, 0.12), uv: met)
            if scope == .none {
                mb.box(g, min: V3(-0.004, 0.066, -0.47), max: V3(0.004, 0.115, -0.455), uv: met)
                mb.box(g, min: V3(-0.012, 0.085, 0.08), max: V3(0.012, 0.115, 0.1), uv: met)
            }
            addScope(mb, scope, z: -0.08, y: 0.085)
        case .akm:
            mb.box(g, min: V3(-0.03, -0.01, -0.2), max: V3(0.03, 0.065, 0.15), uv: met)
            mb.box(g, min: V3(-0.033, -0.015, -0.48), max: V3(0.033, 0.05, -0.2), uv: wood)
            mb.box(g, min: V3(-0.013, 0.05, -0.46), max: V3(0.013, 0.075, -0.2), uv: wood)
            mb.tube(g, from: V3(0, 0.02, -0.48), to: V3(0, 0.02, -0.76), r0: 0.012, r1: 0.012, seg: 8, uv: met)
            mb.tube(g, from: V3(0, 0.02, -0.76), to: V3(0, 0.02, -0.82), r0: 0.016, r1: 0.016, seg: 8, uv: met)
            let mm = mTranslate(V3(0, -0.01, -0.09))
            mb.box(g, min: V3(-0.017, -0.1, -0.035), max: V3(0.017, 0, 0.035), m: mm * mRotX(0.15), uv: met)
            mb.box(g, min: V3(-0.017, -0.1, -0.035), max: V3(0.017, 0, 0.035), m: mm * mTranslate(V3(0, -0.09, -0.02)) * mRotX(0.45), uv: met)
            mb.box(g, min: V3(-0.016, -0.1, -0.022), max: V3(0.016, 0, 0.022), m: mTranslate(V3(0, -0.01, 0.07)) * mRotX(-0.3), uv: wood)
            mb.box(g, min: V3(-0.022, -0.07, 0.0), max: V3(0.022, 0.04, 0.3), m: mTranslate(V3(0, 0.02, 0.14)) * mRotX(0.12), uv: wood)
            mb.box(g, min: V3(-0.014, 0.065, -0.12), max: V3(0.014, 0.08, 0.1), uv: met)
            if scope == .none {
                mb.box(g, min: V3(-0.004, 0.02, -0.75), max: V3(0.004, 0.075, -0.735), uv: met)
            }
            addScope(mb, scope, z: -0.0, y: 0.08)
        case .uzi:
            mb.box(g, min: V3(-0.032, -0.02, -0.2), max: V3(0.032, 0.07, 0.1), uv: met)
            mb.tube(g, from: V3(0, 0.03, -0.2), to: V3(0, 0.03, -0.36), r0: 0.012, r1: 0.012, seg: 8, uv: met)
            mb.box(g, min: V3(-0.018, -0.21, -0.03), max: V3(0.018, -0.02, 0.03), m: mRotX(-0.1), uv: pol)
            mb.box(g, min: V3(-0.006, 0.0, 0.1), max: V3(0.006, 0.015, 0.3), uv: met)
            mb.box(g, min: V3(-0.025, -0.06, 0.28), max: V3(0.025, 0.015, 0.3), uv: met)
            mb.box(g, min: V3(-0.012, 0.07, -0.14), max: V3(0.012, 0.082, 0.06), uv: met)
            addScope(mb, scope == .none ? .none : (scope.rawValue > 2 ? .x2 : scope), z: -0.04, y: 0.082)
        case .kar98k:
            mb.box(g, min: V3(-0.03, -0.04, -0.6), max: V3(0.03, 0.04, 0.0), uv: wood)
            mb.box(g, min: V3(-0.03, -0.12, 0.0), max: V3(0.03, 0.045, 0.42), m: mRotX(-0.08), uv: wood)
            mb.box(g, min: V3(-0.018, 0.04, -0.16), max: V3(0.018, 0.075, 0.08), uv: met)
            mb.tube(g, from: V3(0, 0.05, -0.16), to: V3(0, 0.05, -0.98), r0: 0.012, r1: 0.010, seg: 8, uv: met)
            mb.tube(g, from: V3(0.018, 0.065, 0.04), to: V3(0.07, 0.045, 0.05), r0: 0.006, r1: 0.006, seg: 6, uv: met)
            mb.sphere(g, radius: V3(0.012, 0.012, 0.012), m: mTranslate(V3(0.075, 0.044, 0.05)), rings: 4, segs: 6, uv: met)
            mb.box(g, min: V3(-0.012, -0.06, -0.02), max: V3(0.012, -0.03, 0.06), uv: met)
            if scope == .none {
                mb.box(g, min: V3(-0.004, 0.05, -0.96), max: V3(0.004, 0.08, -0.945), uv: met)
            }
            addScope(mb, scope, z: -0.05, y: 0.075)
        case .s12k:
            mb.box(g, min: V3(-0.032, -0.015, -0.22), max: V3(0.032, 0.07, 0.15), uv: met)
            mb.box(g, min: V3(-0.035, -0.02, -0.5), max: V3(0.035, 0.055, -0.22), uv: pol)
            mb.tube(g, from: V3(0, 0.025, -0.5), to: V3(0, 0.025, -0.8), r0: 0.016, r1: 0.016, seg: 8, uv: met)
            mb.box(g, min: V3(-0.024, -0.15, -0.14), max: V3(0.024, -0.015, -0.03), uv: pol)
            mb.box(g, min: V3(-0.016, -0.1, -0.022), max: V3(0.016, 0, 0.022), m: mTranslate(V3(0, -0.015, 0.07)) * mRotX(-0.3), uv: pol)
            mb.box(g, min: V3(-0.023, -0.07, 0.0), max: V3(0.023, 0.05, 0.28), m: mTranslate(V3(0, 0.02, 0.15)) * mRotX(0.1), uv: tan)
            mb.box(g, min: V3(-0.014, 0.07, -0.14), max: V3(0.014, 0.084, 0.1), uv: met)
            addScope(mb, scope == .none ? .none : (scope.rawValue > 2 ? .x2 : scope), z: -0.03, y: 0.084)
        case .p92:
            mb.box(g, min: V3(-0.014, 0.0, -0.17), max: V3(0.014, 0.034, 0.04), uv: met)
            mb.box(g, min: V3(-0.013, -0.02, -0.15), max: V3(0.013, 0.0, 0.03), uv: pol)
            mb.box(g, min: V3(-0.015, -0.12, -0.02), max: V3(0.015, 0, 0.035), m: mTranslate(V3(0, -0.01, 0.0)) * mRotX(-0.25), uv: pol)
            mb.box(g, min: V3(-0.004, -0.045, -0.06), max: V3(0.004, -0.02, -0.01), uv: met)
        }
        let geo = mb.build(materials: { assets.mat($0) }) ?? SCNBox(width: 0.05, height: 0.05, length: 0.6, chamferRadius: 0)
        cacheLock.run { gunCache[key] = geo }
        return geo
    }

    // MARK: Soldier

    struct RigGeos {
        var pelvis: SCNGeometry
        var torso: SCNGeometry
        var head: SCNGeometry
        var upperArm: SCNGeometry
        var forearm: SCNGeometry
        var thigh: SCNGeometry
        var shin: SCNGeometry
    }

    static var rigCache: [Int: RigGeos] = [:]

    static func rigGeos(variant: Int, assets: Assets) -> RigGeos {
        if let r = cacheLock.run({ rigCache[variant] }) { return r }
        let mat = Mt.soldier0.rawValue + variant
        let mats: (Int) -> SCNMaterial = { assets.mat($0) }

        let pelvis = MeshBuilder()
        pelvis.box(mat, min: V3(-0.17, -0.13, -0.11), max: V3(0.17, 0.06, 0.11), uv: SoldierUV.pants)
        pelvis.box(mat, min: V3(-0.18, 0.02, -0.12), max: V3(0.18, 0.08, 0.12), uv: SoldierUV.black)
        pelvis.box(mat, min: V3(0.16, -0.08, -0.06), max: V3(0.21, 0.04, 0.06), uv: SoldierUV.vest)

        let torso = MeshBuilder()
        torso.box(mat, min: V3(-0.18, 0, -0.11), max: V3(0.18, 0.5, 0.12), uv: SoldierUV.camo)
        torso.box(mat, min: V3(-0.2, 0.1, -0.15), max: V3(0.2, 0.44, 0.14), uv: SoldierUV.vest)
        for k in 0..<3 {
            let x = Float(k - 1) * 0.11
            torso.box(mat, min: V3(x - 0.045, 0.12, -0.2), max: V3(x + 0.045, 0.27, -0.15), uv: SoldierUV.vest)
        }
        torso.box(mat, min: V3(-0.12, 0.3, -0.18), max: V3(0.12, 0.4, -0.15), uv: SoldierUV.black)
        torso.sphere(mat, radius: V3(0.085, 0.08, 0.09), m: mTranslate(V3(0.19, 0.45, 0)), rings: 5, segs: 8, uv: SoldierUV.camo)
        torso.sphere(mat, radius: V3(0.085, 0.08, 0.09), m: mTranslate(V3(-0.19, 0.45, 0)), rings: 5, segs: 8, uv: SoldierUV.camo)
        torso.box(mat, min: V3(-0.17, 0.08, 0.13), max: V3(0.17, 0.52, 0.34), uv: SoldierUV.pack)
        torso.box(mat, min: V3(-0.13, 0.12, 0.34), max: V3(0.13, 0.34, 0.4), uv: SoldierUV.pack)
        torso.tube(mat, from: V3(-0.16, 0.56, 0.24), to: V3(0.16, 0.56, 0.24), r0: 0.06, r1: 0.06, seg: 8, uv: SoldierUV.vest)

        let head = MeshBuilder()
        head.cylinder(mat, r0: 0.055, r1: 0.05, y0: 0, y1: 0.1, seg: 8, uv: SoldierUV.skin, caps: false)
        head.sphere(mat, radius: V3(0.095, 0.115, 0.105), m: mTranslate(V3(0, 0.16, 0)) * mRotY(-kPi / 2), rings: 8, segs: 12, uv: SoldierUV.skin)
        head.sphere(mat, radius: V3(0.125, 0.11, 0.135), m: mTranslate(V3(0, 0.185, 0.008)), rings: 5, segs: 14, uv: SoldierUV.helmet, hemisphere: true)
        head.cylinder(mat, r0: 0.135, r1: 0.128, y0: 0.17, y1: 0.195, seg: 14, m: mScale(V3(1, 1, 1.07)), uv: SoldierUV.helmet, caps: false)
        head.box(mat, min: V3(-0.115, 0.12, -0.03), max: V3(-0.09, 0.19, 0.04), uv: SoldierUV.black)
        head.box(mat, min: V3(0.09, 0.12, -0.03), max: V3(0.115, 0.19, 0.04), uv: SoldierUV.black)

        let ua = MeshBuilder()
        ua.tube(mat, from: V3(0, 0, 0), to: V3(0, -0.3, 0), r0: 0.062, r1: 0.052, seg: 8, uv: SoldierUV.camo)
        ua.sphere(mat, radius: V3(0.058, 0.058, 0.058), m: mTranslate(V3(0, -0.3, 0)), rings: 4, segs: 6, uv: SoldierUV.camo)
        let fa = MeshBuilder()
        fa.tube(mat, from: V3(0, 0, 0), to: V3(0, -0.26, 0), r0: 0.05, r1: 0.042, seg: 8, uv: SoldierUV.camo)
        fa.box(mat, min: V3(-0.035, -0.36, -0.045), max: V3(0.035, -0.26, 0.045), uv: SoldierUV.black)

        let th = MeshBuilder()
        th.tube(mat, from: V3(0, 0, 0), to: V3(0, -0.45, 0), r0: 0.088, r1: 0.066, seg: 8, uv: SoldierUV.pants)
        th.box(mat, min: V3(0.07, -0.3, -0.05), max: V3(0.1, -0.15, 0.05), uv: SoldierUV.pants)
        let sh = MeshBuilder()
        sh.tube(mat, from: V3(0, 0, 0), to: V3(0, -0.4, 0), r0: 0.064, r1: 0.05, seg: 8, uv: SoldierUV.pants)
        sh.box(mat, min: V3(-0.05, -0.08, -0.09), max: V3(0.05, 0.03, -0.04), uv: SoldierUV.black)
        sh.box(mat, min: V3(-0.058, -0.5, -0.16), max: V3(0.058, -0.37, 0.06), uv: SoldierUV.black)

        let r = RigGeos(pelvis: pelvis.build(materials: mats)!, torso: torso.build(materials: mats)!, head: head.build(materials: mats)!,
                        upperArm: ua.build(materials: mats)!, forearm: fa.build(materials: mats)!,
                        thigh: th.build(materials: mats)!, shin: sh.build(materials: mats)!)
        cacheLock.run { rigCache[variant] = r }
        return r
    }

    // MARK: Parachute / plane

    static var chuteGeo: SCNGeometry?

    static func parachute(assets: Assets) -> SCNNode {
        if chuteGeo == nil {
            let mb = MeshBuilder()
            let m = Mt.chute.rawValue
            mb.sphere(m, radius: V3(3.6, 1.4, 2.8), m: mTranslate(V3(0, 4.2, 0)), rings: 6, segs: 18, uv: .full, hemisphere: true)
            let blk = Mt.black.rawValue
            for k in 0..<8 {
                let a = Float(k) / 8 * kTwoPi
                let top = V3(cos(a) * 3.3, 4.25, -sin(a) * 2.55)
                mb.tube(blk, from: V3(cos(a) * 0.15, 1.45, -sin(a) * 0.1), to: top, r0: 0.008, r1: 0.008, seg: 3, caps: false)
            }
            chuteGeo = mb.build(materials: { assets.mat($0) })
        }
        let n = SCNNode(geometry: chuteGeo)
        n.castsShadow = true
        return n
    }

    static func plane(assets: Assets) -> SCNNode {
        let mb = MeshBuilder()
        let b = Mt.planeBody.rawValue
        let dk = Mt.black.rawValue
        mb.cylinder(b, r0: 2.3, r1: 2.3, y0: -14, y1: 12, seg: 16, m: mRotX(-kPi / 2), caps: false)
        mb.sphere(b, radius: V3(2.3, 2.3, 4.0), m: mTranslate(V3(0, 0, -12)) * mRotX(-kPi / 2), rings: 6, segs: 16, hemisphere: true)
        mb.cylinder(b, r0: 0.6, r1: 2.3, y0: -22, y1: -14, seg: 16, m: mRotX(-kPi / 2), caps: true)
        mb.box(b, min: V3(-19, 1.2, -3), max: V3(19, 1.6, 2))
        mb.box(b, min: V3(-0.25, 1.5, 15), max: V3(0.25, 7.5, 19.5))
        mb.box(b, min: V3(-6.5, 1.0, 16.5), max: V3(6.5, 1.3, 19.5))
        for x in [-11, -6, 6, 11] as [Float] {
            mb.cylinder(dk, r0: 0.75, r1: 0.65, y0: -5.2, y1: 0.8, seg: 10, m: mTranslate(V3(x, 0.9, 0)) * mRotX(-kPi / 2), caps: true)
        }
        mb.box(dk, min: V3(-1.6, 0.6, -15.4), max: V3(1.6, 1.4, -14.8))
        let n = SCNNode(geometry: mb.build(materials: { assets.mat($0) }))
        n.castsShadow = true
        return n
    }

    // MARK: Vehicles

    static func jeepBody(assets: Assets, paint: Int) -> SCNNode {
        let mb = MeshBuilder()
        let m = Mt.vehicleA.rawValue + paint
        mb.box(m, min: V3(-0.95, 0.45, -2.1), max: V3(0.95, 1.05, 2.1), uv: VehUV.paint)
        mb.box(m, min: V3(-0.9, 1.05, -2.05), max: V3(0.9, 1.22, -0.95), uv: VehUV.paint)
        mb.box(m, min: V3(-0.92, 1.05, 0.9), max: V3(0.92, 1.45, 2.1), uv: VehUV.paint)
        mb.box(m, min: V3(-0.9, 1.22, -0.98), max: V3(0.9, 1.85, -0.9), uv: VehUV.glass)
        mb.box(m, min: V3(-0.92, 1.85, -0.98), max: V3(0.92, 1.92, 1.0), uv: VehUV.metal)
        for x in [-0.88, 0.88] as [Float] {
            mb.box(m, min: V3(x - 0.04, 1.05, -0.95), max: V3(x + 0.04, 1.9, -0.88), uv: VehUV.metal)
            mb.box(m, min: V3(x - 0.04, 1.05, 0.92), max: V3(x + 0.04, 1.9, 1.0), uv: VehUV.metal)
        }
        mb.box(m, min: V3(-0.75, 1.05, -0.5), max: V3(-0.15, 1.5, 0.05), uv: VehUV.glass)
        mb.box(m, min: V3(0.15, 1.05, -0.5), max: V3(0.75, 1.5, 0.05), uv: VehUV.glass)
        mb.box(m, min: V3(-0.98, 0.35, -2.2), max: V3(0.98, 0.6, -2.05), uv: VehUV.metal)
        mb.box(m, min: V3(-0.8, 0.85, -2.12), max: V3(-0.55, 1.0, -2.08), uv: VehUV.metal)
        mb.box(m, min: V3(0.55, 0.85, -2.12), max: V3(0.8, 1.0, -2.08), uv: VehUV.metal)
        mb.cylinder(m, r0: 0.38, r1: 0.38, y0: 0, y1: 0.25, seg: 12, m: mTranslate(V3(0, 1.0, 2.1)) * mRotX(kPi / 2), uv: VehUV.tire)
        // wheel arches
        for (x, z) in [(-0.9, -1.35), (0.9, -1.35), (-0.9, 1.35), (0.9, 1.35)] as [(Float, Float)] {
            mb.box(m, min: V3(x - 0.17, 0.85, z - 0.55), max: V3(x + 0.17, 0.95, z + 0.55), uv: VehUV.paint)
        }
        let n = SCNNode(geometry: mb.build(materials: { assets.mat($0) }))
        n.castsShadow = true
        return n
    }

    static func bikeBody(assets: Assets, paint: Int) -> SCNNode {
        let mb = MeshBuilder()
        let m = Mt.vehicleA.rawValue + paint
        mb.box(m, min: V3(-0.14, 0.55, -0.55), max: V3(0.14, 0.85, 0.1), uv: VehUV.paint)
        mb.box(m, min: V3(-0.13, 0.8, 0.05), max: V3(0.13, 0.92, 0.6), uv: VehUV.glass)
        mb.box(m, min: V3(-0.12, 0.35, -0.35), max: V3(0.12, 0.6, 0.25), uv: VehUV.metal)
        mb.tube(m, from: V3(0, 0.36, -0.75), to: V3(0, 1.0, -0.55), r0: 0.03, r1: 0.03, seg: 6, uv: VehUV.metal)
        mb.tube(m, from: V3(-0.35, 1.02, -0.52), to: V3(0.35, 1.02, -0.52), r0: 0.018, r1: 0.018, seg: 6, uv: VehUV.metal)
        mb.tube(m, from: V3(0.12, 0.4, 0.2), to: V3(0.15, 0.45, 0.8), r0: 0.04, r1: 0.04, seg: 6, uv: VehUV.metal)
        mb.box(m, min: V3(-0.06, 0.9, -0.72), max: V3(0.06, 1.0, -0.62), uv: VehUV.metal)
        let n = SCNNode(geometry: mb.build(materials: { assets.mat($0) }))
        n.castsShadow = true
        return n
    }

    static func wheel(assets: Assets, radius: Float, width: Float, paint: Int) -> SCNNode {
        let mb = MeshBuilder()
        let m = Mt.vehicleA.rawValue + paint
        mb.cylinder(m, r0: radius, r1: radius, y0: -width / 2, y1: width / 2, seg: 14, m: mRotZ(kPi / 2), uv: VehUV.tire, caps: true)
        mb.cylinder(m, r0: radius * 0.55, r1: radius * 0.55, y0: -width / 2 - 0.01, y1: width / 2 + 0.01, seg: 8, m: mRotZ(kPi / 2), uv: VehUV.metal, caps: true)
        let n = SCNNode(geometry: mb.build(materials: { assets.mat($0) }))
        n.castsShadow = true
        return n
    }

    // MARK: Loot visuals

    static func lootGeometry(_ kind: ItemKind, assets: Assets) -> SCNGeometry {
        let key: String
        switch kind {
        case .weapon(let w): key = "w\(w.rawValue)"
        case .ammo: key = "ammo"
        case .scope: key = "scope"
        case .helmet: key = "helmet"
        case .vest: key = "vest"
        case .bag: key = "bag"
        case .med(let m): key = "med\(m.rawValue)"
        case .throwable: key = "throw"
        }
        if let g = cacheLock.run({ lootCache[key] }) { return g }
        var geo: SCNGeometry
        switch kind {
        case .weapon(let w):
            geo = gun(w, scope: .none, assets: assets)
        default:
            let mb = MeshBuilder()
            switch kind {
            case .ammo:
                mb.box(Mt.lootAmmo.rawValue, min: V3(-0.15, 0, -0.09), max: V3(0.15, 0.16, 0.09))
                mb.box(Mt.black.rawValue, min: V3(-0.04, 0.16, -0.02), max: V3(0.04, 0.19, 0.02))
            case .scope:
                mb.tube(Mt.lootScope.rawValue, from: V3(0, 0.04, -0.14), to: V3(0, 0.04, 0.14), r0: 0.035, r1: 0.035, seg: 10)
            case .helmet:
                mb.sphere(Mt.lootArmor.rawValue, radius: V3(0.14, 0.13, 0.16), rings: 5, segs: 12, hemisphere: true)
            case .vest:
                mb.box(Mt.lootArmor.rawValue, min: V3(-0.22, 0, -0.3), max: V3(0.22, 0.08, 0.3))
                mb.box(Mt.black.rawValue, min: V3(-0.15, 0.08, -0.2), max: V3(0.15, 0.12, 0.0))
            case .bag:
                mb.box(Mt.lootBag.rawValue, min: V3(-0.2, 0, -0.14), max: V3(0.2, 0.42, 0.14))
                mb.box(Mt.lootBag.rawValue, min: V3(-0.15, 0.05, 0.14), max: V3(0.15, 0.25, 0.2))
            case .med(let md):
                if md == .drink {
                    mb.cylinder(Mt.contRed.rawValue, r0: 0.035, r1: 0.035, y0: 0, y1: 0.13, seg: 10)
                } else {
                    let s: Float = md == .medkit ? 0.22 : (md == .firstAid ? 0.15 : 0.08)
                    mb.box(Mt.lootMed.rawValue, min: V3(-s, 0, -s * 0.7), max: V3(s, s * 0.6, s * 0.7))
                    mb.box(Mt.contRed.rawValue, min: V3(-s * 0.15, s * 0.6, -s * 0.45), max: V3(s * 0.15, s * 0.62, s * 0.45))
                    mb.box(Mt.contRed.rawValue, min: V3(-s * 0.45, s * 0.6, -s * 0.15), max: V3(s * 0.45, s * 0.62, s * 0.15))
                }
            case .throwable:
                mb.sphere(Mt.lootArmor.rawValue, radius: V3(0.045, 0.06, 0.045), m: mTranslate(V3(0, 0.06, 0)), rings: 5, segs: 8)
            default:
                mb.box(Mt.crate.rawValue, min: V3(-0.1, 0, -0.1), max: V3(0.1, 0.2, 0.1))
            }
            geo = mb.build(materials: { assets.mat($0) }) ?? SCNBox(width: 0.2, height: 0.2, length: 0.2, chamferRadius: 0)
        }
        cacheLock.run { lootCache[key] = geo }
        return geo
    }

    static var crateGeo: SCNGeometry?
    static func crate(assets: Assets) -> SCNGeometry {
        if let g = crateGeo { return g }
        let mb = MeshBuilder()
        mb.box(Mt.crate.rawValue, min: V3(-0.45, 0, -0.35), max: V3(0.45, 0.6, 0.35), uv: .full)
        let g = mb.build(materials: { assets.mat($0) })!
        crateGeo = g
        return g
    }
}

// MARK: - Soldier rig

enum RigMode {
    case ground, freefall, chute, drive, dead, hidden
}

enum Stance: Int {
    case stand = 0, crouch, prone
}

struct PoseInput {
    var speed: Float = 0
    var forwardSpeed: Float = 0
    var stance: Stance = .stand
    var mode: RigMode = .ground
    var pitch: Float = 0
    var aiming = false
    var reloading = false
    var healing = false
    var lean: Float = 0
    var hasGun = false
    var pistol = false
    var throwing = false
}

final class SoldierRig {
    let root = SCNNode()
    let body = SCNNode()
    let pelvis = SCNNode()
    let spine = SCNNode()
    let head = SCNNode()
    let shoulderL = SCNNode(), elbowL = SCNNode(), shoulderR = SCNNode(), elbowR = SCNNode()
    let hipL = SCNNode(), kneeL = SCNNode(), hipR = SCNNode(), kneeR = SCNNode()
    let gunMount = SCNNode()
    let gunNode = SCNNode()
    let chute: SCNNode
    var gunKey = -1
    var phase: Float = 0
    var pelvisY: Float = 0.95
    var bodyPitch: Float = 0
    var bodyRoll: Float = 0
    var deathT: Float = 0
    private var curHip: Float = 0
    private var curKnee: Float = 0

    init(geos: Models.RigGeos, assets: Assets) {
        chute = Models.parachute(assets: assets)
        root.addChildNode(body)
        body.addChildNode(pelvis)
        pelvis.simdPosition = V3(0, 0.95, 0)
        pelvis.geometry = geos.pelvis
        pelvis.addChildNode(spine)
        spine.simdPosition = V3(0, 0.06, 0)
        spine.geometry = geos.torso
        spine.addChildNode(head)
        head.simdPosition = V3(0, 0.52, 0)
        head.geometry = geos.head

        func arm(_ s: SCNNode, _ e: SCNNode, x: Float) {
            spine.addChildNode(s)
            s.simdPosition = V3(x, 0.44, 0)
            s.geometry = geos.upperArm
            s.addChildNode(e)
            e.simdPosition = V3(0, -0.3, 0)
            e.geometry = geos.forearm
        }
        arm(shoulderL, elbowL, x: -0.24)
        arm(shoulderR, elbowR, x: 0.24)

        func leg(_ h: SCNNode, _ k: SCNNode, x: Float) {
            pelvis.addChildNode(h)
            h.simdPosition = V3(x, -0.05, 0)
            h.geometry = geos.thigh
            h.addChildNode(k)
            k.simdPosition = V3(0, -0.45, 0)
            k.geometry = geos.shin
        }
        leg(hipL, kneeL, x: -0.1)
        leg(hipR, kneeR, x: 0.1)

        spine.addChildNode(gunMount)
        gunMount.simdPosition = V3(0.1, 0.34, -0.3)
        gunMount.addChildNode(gunNode)
        root.addChildNode(chute)
        chute.isHidden = true
        for n in [pelvis, spine, head, shoulderL, elbowL, shoulderR, elbowR, hipL, kneeL, hipR, kneeR] {
            n.castsShadow = true
        }
    }

    func setGun(_ w: WeaponInst?, assets: Assets) {
        let key = w.map { $0.type.rawValue * 10 + $0.scope.rawValue } ?? -1
        if key == gunKey { return }
        gunKey = key
        if let w = w {
            gunNode.geometry = Models.gun(w.type, scope: w.scope, assets: assets)
            gunNode.isHidden = false
        } else {
            gunNode.geometry = nil
            gunNode.isHidden = true
        }
    }

    @inline(__always) private func set(_ n: SCNNode, _ x: Float, _ y: Float, _ z: Float) {
        n.simdEulerAngles = V3(x, y, z)
    }

    func update(dt: Float, _ p: PoseInput) {
        chute.isHidden = p.mode != .chute
        let k = min(1, dt * 10)
        switch p.mode {
        case .hidden:
            return
        case .dead:
            deathT = min(1, deathT + dt * 2.2)
            let t = deathT
            pelvisY = lerpf(pelvisY, 0.2, k)
            pelvis.simdPosition = V3(0, pelvisY, 0)
            set(pelvis, -kPi / 2 * t, 0, 0.3 * t)
            set(spine, 0, 0, 0)
            set(head, 0.3 * t, 0.4 * t, 0)
            set(shoulderL, 2.6 * t, 0, -0.4 * t); set(elbowL, 0.3, 0, 0)
            set(shoulderR, 2.4 * t, 0, 0.5 * t); set(elbowR, 0.5, 0, 0)
            set(hipL, 0.2 * t, 0, -0.15); set(kneeL, -0.3 * t, 0, 0)
            set(hipR, -0.1 * t, 0, 0.2); set(kneeR, -0.6 * t, 0, 0)
            gunNode.isHidden = true
            return
        case .freefall:
            pelvis.simdPosition = V3(0, 0.95, 0)
            set(pelvis, -1.25, 0, 0)
            set(spine, -0.1, 0, 0)
            set(head, 0.9, 0, 0)
            set(shoulderL, 0.3, 0, -1.35); set(elbowL, 0.5, 0, 0)
            set(shoulderR, 0.3, 0, 1.35); set(elbowR, 0.5, 0, 0)
            set(hipL, -0.2, 0, -0.25); set(kneeL, -0.6, 0, 0)
            set(hipR, -0.2, 0, 0.25); set(kneeR, -0.6, 0, 0)
            gunNode.isHidden = true
            return
        case .chute:
            pelvis.simdPosition = V3(0, 0.95, 0)
            set(pelvis, 0, 0, 0)
            set(spine, 0, 0, 0)
            set(head, 0, 0, 0)
            set(shoulderL, 2.7, 0, -0.35); set(elbowL, 0.4, 0, 0)
            set(shoulderR, 2.7, 0, 0.35); set(elbowR, 0.4, 0, 0)
            set(hipL, 0.25, 0, 0); set(kneeL, -0.3, 0, 0)
            set(hipR, 0.05, 0, 0); set(kneeR, -0.2, 0, 0)
            gunNode.isHidden = true
            return
        case .drive:
            pelvis.simdPosition = V3(0, 0.55, 0)
            set(pelvis, 0, 0, 0)
            set(spine, -0.05, 0, 0)
            set(head, 0, 0, 0)
            set(shoulderL, 1.0, 0, 0.1); set(elbowL, 0.6, 0, 0)
            set(shoulderR, 1.0, 0, -0.1); set(elbowR, 0.6, 0, 0)
            set(hipL, 1.45, 0, -0.08); set(kneeL, -1.4, 0, 0)
            set(hipR, 1.45, 0, 0.08); set(kneeR, -1.4, 0, 0)
            gunNode.isHidden = true
            return
        case .ground:
            break
        }
        deathT = 0
        gunNode.isHidden = !p.hasGun
        // stance targets
        var targetY: Float = 0.95
        var targetPitch: Float = 0
        var hipBase: Float = 0, kneeBase: Float = 0
        switch p.stance {
        case .stand: break
        case .crouch:
            targetY = 0.62; hipBase = 1.25; kneeBase = -1.85; targetPitch = 0
        case .prone:
            targetY = 0.2; targetPitch = -kPi / 2 + 0.05
        }
        pelvisY = lerpf(pelvisY, targetY, k)
        bodyPitch = lerpf(bodyPitch, targetPitch, k)
        curHip = lerpf(curHip, hipBase, k)
        curKnee = lerpf(curKnee, kneeBase, k)
        pelvis.simdPosition = V3(0, pelvisY, 0)
        bodyRoll = lerpf(bodyRoll, p.lean * 0.35, k)
        set(pelvis, bodyPitch, 0, 0)

        // walk cycle
        let amp: Float = min(1, p.speed / 4.5) * (p.stance == .prone ? 0.35 : 0.6)
        phase += dt * (2.0 + p.speed * 1.55)
        let dir: Float = p.forwardSpeed < -0.2 ? -1 : 1
        let s1 = sin(phase) * amp * dir
        let kneeL0 = max(0, -sin(phase)) * amp * 1.4
        let kneeR0 = max(0, sin(phase)) * amp * 1.4
        if p.stance == .prone {
            set(hipL, s1 * 0.4, 0, -0.12); set(kneeL, -kneeL0 * 0.5, 0, 0)
            set(hipR, -s1 * 0.4, 0, 0.12); set(kneeR, -kneeR0 * 0.5, 0, 0)
        } else {
            set(hipL, curHip + s1, 0, -0.04); set(kneeL, curKnee - kneeL0, 0, 0)
            set(hipR, curHip - s1, 0, 0.04); set(kneeR, curKnee - kneeR0, 0, 0)
        }
        // upper body aim
        let aimPitch = clampf(p.pitch, -1.2, 1.2)
        if p.stance == .prone {
            set(spine, 0, 0, bodyRoll)
            set(head, 1.3 + aimPitch * 0.3, 0, 0)
            gunMount.simdEulerAngles = V3(kPi / 2 - 0.05 + aimPitch * 0.25, 0, 0)
        } else {
            set(spine, aimPitch * 0.5 - (p.stance == .crouch ? 0.12 : 0.04), 0, bodyRoll)
            set(head, aimPitch * 0.45, 0, 0)
            gunMount.simdEulerAngles = V3(aimPitch * 0.5, 0, 0)
        }
        // arms
        if p.healing {
            set(shoulderL, 0.9, -0.5, 0.2); set(elbowL, 1.4 + sin(phase * 3) * 0.1, 0, 0)
            set(shoulderR, 0.9, 0.5, -0.2); set(elbowR, 1.4, 0, 0)
            gunNode.isHidden = true
        } else if p.throwing {
            set(shoulderR, 2.8, 0, 0.2); set(elbowR, 0.8, 0, 0)
            set(shoulderL, 1.2, -0.3, 0); set(elbowL, 0.2, 0, 0)
        } else if !p.hasGun {
            let sw = sin(phase) * amp * 0.9
            set(shoulderL, -sw, 0, -0.12); set(elbowL, 0.35, 0, 0)
            set(shoulderR, sw, 0, 0.12); set(elbowR, 0.35, 0, 0)
        } else if p.pistol {
            set(shoulderR, 1.45, 0.25, 0); set(elbowR, 0.1, 0, 0)
            set(shoulderL, 1.4, -0.45, 0); set(elbowL, 0.25, 0, 0)
        } else {
            set(shoulderR, 1.0, 0.3, -0.25); set(elbowR, 1.1, 0, 0)
            if p.reloading {
                set(shoulderL, 0.6 + sin(phase * 2.5) * 0.15, -0.3, 0.15); set(elbowL, 1.5, 0, 0)
            } else {
                set(shoulderL, 1.35, -0.62, 0.3); set(elbowL, 0.3, 0, 0)
            }
        }
    }
}
