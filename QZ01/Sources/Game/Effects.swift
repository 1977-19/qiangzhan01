import SceneKit
import UIKit

/// Visual effects: tracers, muzzle flashes, impacts, explosions, smoke.
final class Effects {
    let root = SCNNode()
    let assets: Assets
    private var tracers: [SCNNode] = []
    private var tracerLife: [Float] = []
    private var nextTracer = 0
    private var flashes: [SCNNode] = []
    private var flashLife: [Float] = []
    private var nextFlash = 0
    let flashLight = SCNNode()
    private var flashLightLife: Float = 0
    private var flashLightPeak: CGFloat = 0
    private var timed: [(node: SCNNode, until: Float)] = []
    private var now: Float = 0
    private var dustT: SCNParticleSystem!
    private var sparkT: SCNParticleSystem!
    private var chipT: SCNParticleSystem!
    private var splashT: SCNParticleSystem!
    private var hitT: SCNParticleSystem!
    private var fireT: SCNParticleSystem!
    private var bigSmokeT: SCNParticleSystem!
    private var smokeGrenT: SCNParticleSystem!

    init(assets: Assets) {
        self.assets = assets
        root.name = "fx"
        let tm = SCNMaterial()
        tm.lightingModel = .constant
        tm.diffuse.contents = UIColor(red: 1.0, green: 0.78, blue: 0.4, alpha: 1)
        tm.emission.contents = UIColor(red: 1.0, green: 0.7, blue: 0.3, alpha: 1)
        tm.emission.intensity = 4
        tm.writesToDepthBuffer = false
        let tg = SCNBox(width: 0.03, height: 0.03, length: 1, chamferRadius: 0)
        tg.materials = [tm]
        for _ in 0..<48 {
            let n = SCNNode(geometry: tg)
            n.isHidden = true
            n.castsShadow = false
            root.addChildNode(n)
            tracers.append(n)
            tracerLife.append(0)
        }
        let fm = SCNMaterial()
        fm.lightingModel = .constant
        fm.diffuse.contents = assets.flash
        fm.emission.contents = assets.flash
        fm.emission.intensity = 3
        fm.blendMode = .add
        fm.writesToDepthBuffer = false
        fm.isDoubleSided = true
        let fp = SCNPlane(width: 0.5, height: 0.5)
        fp.materials = [fm]
        for _ in 0..<10 {
            let n = SCNNode(geometry: fp)
            n.isHidden = true
            n.castsShadow = false
            n.constraints = [SCNBillboardConstraint()]
            root.addChildNode(n)
            flashes.append(n)
            flashLife.append(0)
        }
        let l = SCNLight()
        l.type = .omni
        l.color = UIColor(red: 1.0, green: 0.75, blue: 0.4, alpha: 1)
        l.intensity = 0
        l.attenuationStartDistance = 1
        l.attenuationEndDistance = 18
        l.castsShadow = false
        flashLight.light = l
        root.addChildNode(flashLight)
        buildTemplates()
    }

    private func fade() -> SCNParticlePropertyController {
        let a = CAKeyframeAnimation()
        a.values = [0.0, 1.0, 0.8, 0.0]
        a.keyTimes = [0, 0.08, 0.5, 1]
        return SCNParticlePropertyController(animation: a)
    }

    private func grow(_ from: CGFloat, _ to: CGFloat) -> SCNParticlePropertyController {
        let a = CAKeyframeAnimation()
        a.values = [from, to]
        a.keyTimes = [0, 1]
        return SCNParticlePropertyController(animation: a)
    }

    private func buildTemplates() {
        let snowy = assets.kind == .snow
        let d = SCNParticleSystem()
        d.particleImage = assets.dust
        d.birthRate = 400
        d.emissionDuration = 0.05
        d.loops = false
        d.particleLifeSpan = 0.9
        d.particleLifeSpanVariation = 0.4
        d.particleVelocity = 2.2
        d.particleVelocityVariation = 1.4
        d.spreadingAngle = 55
        d.emittingDirection = SCNVector3(0, 1, 0)
        d.particleSize = 0.14
        d.particleSizeVariation = 0.08
        d.particleColor = snowy ? UIColor(white: 0.95, alpha: 1) : UIColor(red: 0.62, green: 0.54, blue: 0.42, alpha: 1)
        d.blendMode = .alpha
        d.isAffectedByGravity = true
        d.dampingFactor = 2
        d.isLightingEnabled = true
        d.propertyControllers = [.opacity: fade(), .size: grow(1, 2.6)]
        dustT = d

        let s = SCNParticleSystem()
        s.particleImage = assets.spark
        s.birthRate = 900
        s.emissionDuration = 0.03
        s.loops = false
        s.particleLifeSpan = 0.25
        s.particleLifeSpanVariation = 0.1
        s.particleVelocity = 7
        s.particleVelocityVariation = 4
        s.spreadingAngle = 70
        s.emittingDirection = SCNVector3(0, 1, 0)
        s.particleSize = 0.03
        s.particleColor = UIColor(red: 1.0, green: 0.8, blue: 0.4, alpha: 1)
        s.blendMode = .additive
        s.isAffectedByGravity = true
        s.propertyControllers = [.opacity: fade()]
        sparkT = s

        let c = dustT.copy() as! SCNParticleSystem
        c.particleColor = UIColor(red: 0.45, green: 0.32, blue: 0.2, alpha: 1)
        c.particleSize = 0.06
        c.particleVelocity = 3.5
        chipT = c

        let w = dustT.copy() as! SCNParticleSystem
        w.particleColor = UIColor(white: 0.92, alpha: 1)
        w.particleVelocity = 4
        w.spreadingAngle = 25
        w.particleLifeSpan = 0.7
        splashT = w

        let h = dustT.copy() as! SCNParticleSystem
        h.particleColor = UIColor(red: 0.45, green: 0.08, blue: 0.06, alpha: 1)
        h.particleSize = 0.09
        h.particleVelocity = 1.2
        h.particleLifeSpan = 0.35
        h.isAffectedByGravity = false
        hitT = h

        let f = SCNParticleSystem()
        f.particleImage = assets.fire
        f.birthRate = 1500
        f.emissionDuration = 0.08
        f.loops = false
        f.particleLifeSpan = 0.55
        f.particleLifeSpanVariation = 0.2
        f.particleVelocity = 9
        f.particleVelocityVariation = 5
        f.spreadingAngle = 180
        f.particleSize = 0.9
        f.particleSizeVariation = 0.5
        f.particleColor = UIColor(red: 1.0, green: 0.6, blue: 0.25, alpha: 1)
        f.blendMode = .additive
        f.dampingFactor = 4
        f.propertyControllers = [.opacity: fade(), .size: grow(0.6, 2.2)]
        fireT = f

        let bs = SCNParticleSystem()
        bs.particleImage = assets.smoke
        bs.birthRate = 160
        bs.emissionDuration = 0.25
        bs.loops = false
        bs.particleLifeSpan = 3.5
        bs.particleLifeSpanVariation = 1.0
        bs.particleVelocity = 3.5
        bs.particleVelocityVariation = 2
        bs.spreadingAngle = 90
        bs.emittingDirection = SCNVector3(0, 1, 0)
        bs.particleSize = 1.4
        bs.particleSizeVariation = 0.6
        bs.particleColor = UIColor(white: 0.25, alpha: 1)
        bs.blendMode = .alpha
        bs.dampingFactor = 1.5
        bs.isLightingEnabled = true
        bs.acceleration = SCNVector3(0, 0.6, 0)
        bs.propertyControllers = [.opacity: fade(), .size: grow(0.8, 3.0)]
        bigSmokeT = bs

        let sg = SCNParticleSystem()
        sg.particleImage = assets.smoke
        sg.birthRate = 28
        sg.emissionDuration = 20
        sg.loops = false
        sg.particleLifeSpan = 9
        sg.particleLifeSpanVariation = 2
        sg.particleVelocity = 1.6
        sg.particleVelocityVariation = 0.8
        sg.spreadingAngle = 85
        sg.emittingDirection = SCNVector3(0, 1, 0)
        sg.particleSize = 2.6
        sg.particleSizeVariation = 0.8
        sg.particleColor = UIColor(white: 0.88, alpha: 1)
        sg.blendMode = .alpha
        sg.dampingFactor = 0.6
        sg.isLightingEnabled = true
        sg.propertyControllers = [.opacity: fade(), .size: grow(0.6, 2.4)]
        smokeGrenT = sg
    }

    private func spawn(_ template: SCNParticleSystem, at p: V3, normal: V3, life: Float) {
        let ps = template.copy() as! SCNParticleSystem
        let n = SCNNode()
        n.simdPosition = p
        n.simdOrientation = simd_quatf(from: V3(0, 1, 0), to: vnorm(normal))
        n.addParticleSystem(ps)
        n.castsShadow = false
        root.addChildNode(n)
        timed.append((n, now + life))
    }

    func tracer(from a: V3, to b: V3) {
        let d = b - a
        let l = vlen(d)
        if l < 0.5 { return }
        let n = tracers[nextTracer]
        tracerLife[nextTracer] = 0.035
        nextTracer = (nextTracer + 1) % tracers.count
        n.isHidden = false
        n.simdPosition = (a + b) * 0.5
        n.simdOrientation = simd_quatf(from: V3(0, 0, 1), to: d / l)
        n.simdScale = V3(1, 1, l)
    }

    func muzzle(at p: V3, light: Bool) {
        let n = flashes[nextFlash]
        flashLife[nextFlash] = 0.05
        nextFlash = (nextFlash + 1) % flashes.count
        n.isHidden = false
        n.simdPosition = p
        n.simdScale = V3(repeating: Float.random(in: 0.7...1.2))
        if light {
            flashLight.simdPosition = p
            flashLight.light?.intensity = 900
            flashLightPeak = 900
            flashLightLife = 0.05
        }
    }

    func impact(at p: V3, normal: V3, kind: SurfaceKind) {
        switch kind {
        case .metal, .vehicle:
            spawn(sparkT, at: p, normal: normal, life: 1)
        case .wood:
            spawn(chipT, at: p, normal: normal, life: 1.5)
        case .water:
            spawn(splashT, at: p, normal: V3(0, 1, 0), life: 1.5)
        case .flesh:
            spawn(hitT, at: p, normal: normal, life: 1)
        case .concrete, .rock:
            spawn(dustT, at: p, normal: normal, life: 1.5)
            spawn(sparkT, at: p, normal: normal, life: 1)
        case .ground:
            spawn(dustT, at: p, normal: normal, life: 1.5)
        }
    }

    func explosion(at p: V3) {
        spawn(fireT, at: p, normal: V3(0, 1, 0), life: 1.5)
        spawn(bigSmokeT, at: p, normal: V3(0, 1, 0), life: 5)
        spawn(dustT, at: p, normal: V3(0, 1, 0), life: 2)
        flashLight.simdPosition = p + V3(0, 1, 0)
        flashLight.light?.intensity = 6000
        flashLightPeak = 6000
        flashLightLife = 0.35
    }

    func smoke(at p: V3) {
        spawn(smokeGrenT, at: p, normal: V3(0, 1, 0), life: 32)
    }

    func update(dt: Float, time: Float) {
        now = time
        for i in 0..<tracers.count where tracerLife[i] > 0 {
            tracerLife[i] -= dt
            if tracerLife[i] <= 0 { tracers[i].isHidden = true }
        }
        for i in 0..<flashes.count where flashLife[i] > 0 {
            flashLife[i] -= dt
            if flashLife[i] <= 0 { flashes[i].isHidden = true }
        }
        if flashLightLife > 0 {
            flashLightLife -= dt
            if flashLightLife <= 0 {
                flashLight.light?.intensity = 0
            } else {
                flashLight.light?.intensity = flashLightPeak * CGFloat(min(1, flashLightLife / 0.05))
            }
        }
        if !timed.isEmpty {
            var keep: [(node: SCNNode, until: Float)] = []
            for t in timed {
                if t.until < now { t.node.removeFromParentNode() } else { keep.append(t) }
            }
            timed = keep
        }
    }
}
