import UIKit
import CoreGraphics

/// Simple RGBA8 pixel buffer used to synthesise textures.
final class Img {
    let w: Int
    let h: Int
    var px: [UInt8]

    init(_ w: Int, _ h: Int, fill: V3 = V3(0, 0, 0), alpha: Float = 1) {
        self.w = w
        self.h = h
        px = [UInt8](repeating: 0, count: w * h * 4)
        let r = UInt8(saturate(fill.x * alpha) * 255), g = UInt8(saturate(fill.y * alpha) * 255)
        let b = UInt8(saturate(fill.z * alpha) * 255), a = UInt8(saturate(alpha) * 255)
        var i = 0
        while i < px.count {
            px[i] = r; px[i + 1] = g; px[i + 2] = b; px[i + 3] = a
            i += 4
        }
    }

    @inline(__always) func set(_ x: Int, _ y: Int, _ c: V3, _ a: Float = 1) {
        let i = (y * w + x) * 4
        px[i] = UInt8(saturate(c.x * a) * 255)
        px[i + 1] = UInt8(saturate(c.y * a) * 255)
        px[i + 2] = UInt8(saturate(c.z * a) * 255)
        px[i + 3] = UInt8(saturate(a) * 255)
    }

    @inline(__always) func get(_ x: Int, _ y: Int) -> V3 {
        let i = (y * w + x) * 4
        return V3(Float(px[i]), Float(px[i + 1]), Float(px[i + 2])) / 255
    }

    @inline(__always) func alphaAt(_ x: Int, _ y: Int) -> Float {
        return Float(px[(y * w + x) * 4 + 3]) / 255
    }

    /// Blend colour over pixel with wrap-around coordinates (opaque images).
    @inline(__always) func blend(_ x: Int, _ y: Int, _ c: V3, _ a: Float) {
        var xx = x % w; if xx < 0 { xx += w }
        var yy = y % h; if yy < 0 { yy += h }
        let o = get(xx, yy)
        let n = o + (c - o) * a
        let i = (yy * w + xx) * 4
        px[i] = UInt8(saturate(n.x) * 255)
        px[i + 1] = UInt8(saturate(n.y) * 255)
        px[i + 2] = UInt8(saturate(n.z) * 255)
    }

    func stroke(_ x0: Float, _ y0: Float, _ x1: Float, _ y1: Float, _ c: V3, _ a: Float) {
        let dx = x1 - x0, dy = y1 - y0
        let n = max(1, Int(max(abs(dx), abs(dy))))
        for s in 0...n {
            let t = Float(s) / Float(n)
            blend(Int(x0 + dx * t), Int(y0 + dy * t), c, a)
        }
    }

    func disc(_ cx: Float, _ cy: Float, _ r: Float, _ c: V3, _ a: Float) {
        let ri = Int(r.rounded(.up))
        for yy in -ri...ri {
            for xx in -ri...ri {
                let d = sqrt(Float(xx * xx + yy * yy))
                if d <= r {
                    let k = a * saturate((r - d) / max(1, r * 0.35))
                    blend(Int(cx) + xx, Int(cy) + yy, c, k)
                }
            }
        }
    }

    func cg(alpha: Bool = false, linear: Bool = false) -> CGImage {
        let cs: CGColorSpace
        if linear {
            cs = CGColorSpace(name: CGColorSpace.linearSRGB) ?? CGColorSpaceCreateDeviceRGB()
        } else {
            cs = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        }
        let info = CGBitmapInfo(rawValue: alpha ? CGImageAlphaInfo.premultipliedLast.rawValue : CGImageAlphaInfo.noneSkipLast.rawValue)
        let data = Data(px) as CFData
        let provider = CGDataProvider(data: data)!
        return CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4,
                       space: cs, bitmapInfo: info, provider: provider, decode: nil,
                       shouldInterpolate: true, intent: .defaultIntent)!
    }

    func average() -> V3 {
        var s = V3(0, 0, 0)
        var n: Float = 0
        var y = 0
        while y < h {
            var x = 0
            while x < w {
                s += get(x, y)
                n += 1
                x += 7
            }
            y += 7
        }
        return s / max(n, 1)
    }

    /// Draw with CoreGraphics directly into this buffer (premultiplied RGBA).
    func draw(_ body: (CGContext) -> Void) {
        let cs = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let bw = w, bh = h
        px.withUnsafeMutableBytes { raw in
            guard let ctx = CGContext(data: raw.baseAddress, width: bw, height: bh, bitsPerComponent: 8,
                                      bytesPerRow: bw * 4, space: cs,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
            body(ctx)
        }
    }
}

struct TexSet {
    let albedo: CGImage
    let normal: CGImage?
    let avg: V3
}

/// Rects inside atlases (u0, v0, u1, v1), v measured from top.
struct UVRect {
    var u0: Float, v0: Float, u1: Float, v1: Float
    static let full = UVRect(u0: 0, v0: 0, u1: 1, v1: 1)
}

enum SoldierUV {
    static let camo = UVRect(u0: 0.01, v0: 0.01, u1: 0.49, v1: 0.49)
    static let skin = UVRect(u0: 0.51, v0: 0.01, u1: 0.74, v1: 0.24)
    static let helmet = UVRect(u0: 0.76, v0: 0.01, u1: 0.99, v1: 0.24)
    static let vest = UVRect(u0: 0.51, v0: 0.26, u1: 0.74, v1: 0.49)
    static let black = UVRect(u0: 0.76, v0: 0.26, u1: 0.99, v1: 0.49)
    static let pack = UVRect(u0: 0.01, v0: 0.51, u1: 0.49, v1: 0.99)
    static let pants = UVRect(u0: 0.51, v0: 0.51, u1: 0.99, v1: 0.99)
}

enum GunUV {
    static let metal = UVRect(u0: 0.02, v0: 0.02, u1: 0.48, v1: 0.48)
    static let polymer = UVRect(u0: 0.52, v0: 0.02, u1: 0.98, v1: 0.48)
    static let wood = UVRect(u0: 0.02, v0: 0.52, u1: 0.48, v1: 0.98)
    static let tan = UVRect(u0: 0.52, v0: 0.52, u1: 0.98, v1: 0.98)
}

enum VehUV {
    static let paint = UVRect(u0: 0.02, v0: 0.02, u1: 0.48, v1: 0.48)
    static let tire = UVRect(u0: 0.52, v0: 0.02, u1: 0.98, v1: 0.48)
    static let glass = UVRect(u0: 0.02, v0: 0.52, u1: 0.48, v1: 0.98)
    static let metal = UVRect(u0: 0.52, v0: 0.52, u1: 0.98, v1: 0.98)
}

enum TexGen {
    // MARK: helpers

    static func normalFromHeight(_ hgt: [Float], _ w: Int, _ h: Int, strength: Float) -> CGImage {
        let img = Img(w, h)
        for y in 0..<h {
            let ym = (y - 1 + h) % h, yp = (y + 1) % h
            for x in 0..<w {
                let xm = (x - 1 + w) % w, xp = (x + 1) % w
                let dx = (hgt[y * w + xp] - hgt[y * w + xm]) * strength
                let dy = (hgt[yp * w + x] - hgt[ym * w + x]) * strength
                let n = vnorm(V3(-dx, dy, 1))
                img.set(x, y, n * 0.5 + V3(0.5, 0.5, 0.5))
            }
        }
        return img.cg(linear: true)
    }

    static func flatNormal() -> CGImage {
        return Img(4, 4, fill: V3(0.5, 0.5, 1)).cg(linear: true)
    }

    // MARK: ground

    static func grassGround(_ noise: Noise, dry: Bool, seed: UInt64) -> TexSet {
        let n = 512
        let img = Img(n, n)
        var hgt = [Float](repeating: 0, count: n * n)
        let cA: V3 = dry ? V3(0.47, 0.40, 0.22) : V3(0.20, 0.31, 0.10)
        let cB: V3 = dry ? V3(0.62, 0.53, 0.31) : V3(0.33, 0.42, 0.15)
        let cC: V3 = dry ? V3(0.38, 0.35, 0.22) : V3(0.27, 0.30, 0.12)
        for y in 0..<n {
            for x in 0..<n {
                let fx = Float(x) / 64, fy = Float(y) / 64
                let a = noise.fbm(fx, fy, oct: 5, period: 8) * 0.5 + 0.5
                let b = noise.fbm(fx * 0.5 + 17, fy * 0.5 + 9, oct: 3, period: 4) * 0.5 + 0.5
                var c = lerp3(cA, cB, saturate(a * 1.3 - 0.15))
                c = lerp3(c, cC, smoothstepf(0.55, 0.8, b) * 0.6)
                img.set(x, y, c)
                hgt[y * n + x] = a * 0.4
            }
        }
        var rng = RNG(seed)
        let bladeLight: V3 = dry ? V3(0.80, 0.70, 0.45) : V3(0.45, 0.58, 0.22)
        let bladeDark: V3 = dry ? V3(0.30, 0.25, 0.14) : V3(0.10, 0.18, 0.06)
        for _ in 0..<14000 {
            let x = rng.r(0, Float(n)), y = rng.r(0, Float(n))
            let ang = rng.r(-0.6, 0.6) - kPi / 2
            let l = rng.r(3, 11)
            let light = rng.chance(0.55)
            let col = light ? bladeLight : bladeDark
            img.stroke(x, y, x + cos(ang) * l, y + sin(ang) * l, col, rng.r(0.25, 0.6))
            let xi = (Int(x) % n + n) % n, yi = (Int(y) % n + n) % n
            hgt[yi * n + xi] += light ? 0.6 : -0.3
        }
        // dirt specks
        for _ in 0..<500 {
            let x = rng.r(0, Float(n)), y = rng.r(0, Float(n))
            img.disc(x, y, rng.r(1, 3), V3(0.32, 0.26, 0.18), 0.6)
        }
        return TexSet(albedo: img.cg(), normal: normalFromHeight(hgt, n, n, strength: 2.0), avg: img.average())
    }

    static func rock(_ noise: Noise, tint: V3, seed: UInt64) -> TexSet {
        let n = 512
        let img = Img(n, n)
        var hgt = [Float](repeating: 0, count: n * n)
        for y in 0..<n {
            for x in 0..<n {
                let fx = Float(x) / 128, fy = Float(y) / 128
                let r = noise.ridged(fx, fy, oct: 6, period: 4)
                let f = noise.fbm(fx * 2 + 31, fy * 2 + 7, oct: 5, period: 8) * 0.5 + 0.5
                let cl = noise.cell(Float(x) / 48, Float(y) / 48, period: 10)
                let crack = smoothstepf(0.10, 0.0, abs(cl - 0.55)) * 0.6
                var hv = r * 0.6 + f * 0.4 - crack
                hv = max(hv, 0)
                let base = tint * (0.65 + 0.55 * f)
                var c = lerp3(base, base * V3(1.08, 1.0, 0.88), smoothstepf(0.4, 0.8, r))
                c *= (1 - crack * 0.7)
                let lichen = smoothstepf(0.62, 0.75, noise.fbm(fx * 3 + 50, fy * 3 + 3, oct: 3, period: 12) * 0.5 + 0.5)
                c = lerp3(c, V3(0.38, 0.40, 0.28), lichen * 0.35)
                img.set(x, y, c)
                hgt[y * n + x] = hv
            }
        }
        return TexSet(albedo: img.cg(), normal: normalFromHeight(hgt, n, n, strength: 6.0), avg: img.average())
    }

    static func snow(_ noise: Noise, seed: UInt64) -> TexSet {
        let n = 512
        let img = Img(n, n)
        var hgt = [Float](repeating: 0, count: n * n)
        var rng = RNG(seed)
        for y in 0..<n {
            for x in 0..<n {
                let fx = Float(x) / 128, fy = Float(y) / 128
                let a = noise.fbm(fx, fy, oct: 5, period: 4) * 0.5 + 0.5
                let ripN: Float = noise.fbm(fx * 2, fy * 2, oct: 2, period: 8)
                let ripA: Float = Float(y) * 0.09 + ripN * 6
                let rip: Float = sin(ripA) * 0.5 + 0.5
                let k1: Float = 0.94 + 0.08 * a
                let k2: Float = 0.02 * rip
                let c: V3 = V3(0.84, 0.87, 0.93) * k1 + V3(k2, k2, k2 * 1.5)
                img.set(x, y, c)
                hgt[y * n + x] = a * 0.8 + rip * 0.15
            }
        }
        for _ in 0..<900 {
            let x = rng.i(n), y = rng.i(n)
            img.set(x, y, V3(1, 1, 1))
        }
        return TexSet(albedo: img.cg(), normal: normalFromHeight(hgt, n, n, strength: 1.2), avg: img.average())
    }

    static func sand(_ noise: Noise, seed: UInt64) -> TexSet {
        let n = 512
        let img = Img(n, n)
        var hgt = [Float](repeating: 0, count: n * n)
        var rng = RNG(seed)
        for y in 0..<n {
            for x in 0..<n {
                let fx = Float(x) / 128, fy = Float(y) / 128
                let a = noise.fbm(fx, fy, oct: 5, period: 4) * 0.5 + 0.5
                let w = noise.fbm(fx * 0.5 + 3, fy * 0.5, oct: 2, period: 2)
                let rip = sin((Float(y) + w * 60) * 0.2) * 0.5 + 0.5
                let k1: Float = (0.88 + 0.18 * a) * (0.96 + 0.06 * rip)
                let c: V3 = V3(0.74, 0.66, 0.49) * k1
                img.set(x, y, c)
                hgt[y * n + x] = rip * 0.6 + a * 0.3
            }
        }
        for _ in 0..<5000 {
            img.blend(rng.i(n), rng.i(n), rng.chance(0.5) ? V3(0.5, 0.45, 0.35) : V3(0.9, 0.85, 0.7), 0.5)
        }
        return TexSet(albedo: img.cg(), normal: normalFromHeight(hgt, n, n, strength: 1.5), avg: img.average())
    }

    static func gravel(_ noise: Noise, seed: UInt64, base: V3) -> TexSet {
        let n = 512
        let img = Img(n, n)
        var hgt = [Float](repeating: 0, count: n * n)
        for y in 0..<n {
            for x in 0..<n {
                let fx = Float(x) / 128, fy = Float(y) / 128
                let a = noise.fbm(fx, fy, oct: 4, period: 4) * 0.5 + 0.5
                let pebble = noise.cell(Float(x) / 7, Float(y) / 7, period: 73)
                let p = smoothstepf(0.5, 0.15, pebble)
                let tone = noise.n2(Float(x) / 7 + 0.5, Float(y) / 7 + 0.5, period: 73) * 0.5 + 0.5
                let k1: Float = 0.85 + 0.3 * a
                var c: V3 = base * k1
                let k2: Float = 0.75 + 0.6 * tone
                c = lerp3(c, base * k2, p * 0.7)
                img.set(x, y, c)
                hgt[y * n + x] = p * 0.8 + a * 0.2
            }
        }
        return TexSet(albedo: img.cg(), normal: normalFromHeight(hgt, n, n, strength: 3), avg: img.average())
    }

    // MARK: vegetation

    static func bark(_ noise: Noise, base: V3) -> TexSet {
        let w = 256, h = 512
        let img = Img(w, h)
        var hgt = [Float](repeating: 0, count: w * h)
        for y in 0..<h {
            for x in 0..<w {
                let fx = Float(x) / 32, fy = Float(y) / 128
                let warp = noise.fbm(fx * 0.5, fy * 2, oct: 3, period: 8) * 1.5
                let furrow = abs(sin((fx + warp) * kPi * 1.0))
                let d = noise.fbm(fx * 2, fy * 4, oct: 4, period: 16) * 0.5 + 0.5
                let hv = furrow * 0.7 + d * 0.3
                let c = base * (0.45 + 0.75 * hv)
                img.set(x, y, c)
                hgt[y * w + x] = hv
            }
        }
        return TexSet(albedo: img.cg(), normal: normalFromHeight(hgt, w, h, strength: 5), avg: img.average())
    }

    static func needles(_ noise: Noise, seed: UInt64, snowy: Bool) -> TexSet {
        let n = 512
        let img = Img(n, n, fill: V3(0.06, 0.12, 0.07))
        var hgt = [Float](repeating: 0, count: n * n)
        var rng = RNG(seed)
        for _ in 0..<26000 {
            let x = rng.r(0, Float(n)), y = rng.r(0, Float(n))
            let ang = rng.r(0, kTwoPi)
            let l = rng.r(4, 12)
            let t = rng.f()
            let col = lerp3(V3(0.07, 0.15, 0.08), V3(0.22, 0.34, 0.16), t)
            img.stroke(x, y, x + cos(ang) * l, y + sin(ang) * l, col, 0.8)
            let xi = (Int(x) % n + n) % n, yi = (Int(y) % n + n) % n
            hgt[yi * n + xi] += t
        }
        if snowy {
            for y in 0..<n {
                for x in 0..<n {
                    let s = noise.fbm(Float(x) / 64, Float(y) / 64, oct: 4, period: 8) * 0.5 + 0.5
                    let k = smoothstepf(0.52, 0.62, s)
                    if k > 0 {
                        img.blend(x, y, V3(0.86, 0.89, 0.93), k * 0.9)
                        hgt[y * n + x] += k * 2
                    }
                }
            }
        }
        return TexSet(albedo: img.cg(), normal: normalFromHeight(hgt, n, n, strength: 1.5), avg: img.average())
    }

    static func leaves(_ noise: Noise, seed: UInt64, autumn: Bool) -> TexSet {
        let n = 512
        let img = Img(n, n, fill: autumn ? V3(0.25, 0.20, 0.08) : V3(0.08, 0.16, 0.05))
        var hgt = [Float](repeating: 0, count: n * n)
        var rng = RNG(seed)
        for _ in 0..<9000 {
            let x = rng.r(0, Float(n)), y = rng.r(0, Float(n))
            let r = rng.r(2.5, 6)
            let t = rng.f()
            let col: V3 = autumn ? lerp3(V3(0.45, 0.35, 0.10), V3(0.70, 0.52, 0.18), t)
                                 : lerp3(V3(0.12, 0.26, 0.07), V3(0.32, 0.48, 0.14), t)
            img.disc(x, y, r, col, 0.9)
            let xi = (Int(x) % n + n) % n, yi = (Int(y) % n + n) % n
            hgt[yi * n + xi] += 1 + t
        }
        // smooth height a bit
        var h2 = hgt
        for y in 0..<n {
            for x in 0..<n {
                var s: Float = 0
                for dy in -2...2 { for dx in -2...2 { s += hgt[((y + dy + n) % n) * n + (x + dx + n) % n] } }
                h2[y * n + x] = s / 25
            }
        }
        return TexSet(albedo: img.cg(), normal: normalFromHeight(h2, n, n, strength: 3), avg: img.average())
    }

    /// Alpha-tested grass card texture: blades grow from the bottom row (v = 1) to the top (v = 0).
    static func grassCard(seed: UInt64, dry: Bool) -> CGImage {
        let w = 512, h = 256
        let img = Img(w, h, fill: V3(0, 0, 0), alpha: 0)
        var rng = RNG(seed)
        img.draw { ctx in
            // CoreGraphics origin is bottom-left: y = 0 is the bottom of the image.
            for _ in 0..<95 {
                let bx = CGFloat(rng.r(8, Float(w) - 8))
                let hgt = CGFloat(rng.r(0.45, 0.98)) * CGFloat(h)
                let lean = CGFloat(rng.r(-0.35, 0.35)) * hgt
                let width = CGFloat(rng.r(3, 7))
                let t = rng.f()
                let base: V3, tip: V3
                if dry {
                    base = lerp3(V3(0.30, 0.25, 0.12), V3(0.42, 0.34, 0.16), t)
                    tip = lerp3(V3(0.78, 0.66, 0.40), V3(0.92, 0.80, 0.52), t)
                } else {
                    base = lerp3(V3(0.10, 0.20, 0.05), V3(0.16, 0.27, 0.07), t)
                    tip = lerp3(V3(0.40, 0.55, 0.18), V3(0.55, 0.66, 0.25), t)
                }
                let path = CGMutablePath()
                path.move(to: CGPoint(x: bx - width, y: 0))
                path.addQuadCurve(to: CGPoint(x: bx + lean, y: hgt), control: CGPoint(x: bx - width * 0.3 + lean * 0.2, y: hgt * 0.55))
                path.addQuadCurve(to: CGPoint(x: bx + width, y: 0), control: CGPoint(x: bx + width * 0.3 + lean * 0.2, y: hgt * 0.5))
                path.closeSubpath()
                ctx.saveGState()
                ctx.addPath(path)
                ctx.clip()
                let cs = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
                let colors = [UIColor(red: CGFloat(base.x), green: CGFloat(base.y), blue: CGFloat(base.z), alpha: 1).cgColor,
                              UIColor(red: CGFloat(tip.x), green: CGFloat(tip.y), blue: CGFloat(tip.z), alpha: 1).cgColor] as CFArray
                if let grad = CGGradient(colorsSpace: cs, colors: colors, locations: [0, 1]) {
                    ctx.drawLinearGradient(grad, start: CGPoint(x: bx, y: 0), end: CGPoint(x: bx + lean, y: hgt), options: [])
                }
                ctx.restoreGState()
            }
        }
        return img.cg(alpha: true)
    }

    // MARK: building materials

    static func concrete(_ noise: Noise, base: V3, seams: Bool) -> TexSet {
        let n = 512
        let img = Img(n, n)
        var hgt = [Float](repeating: 0, count: n * n)
        for y in 0..<n {
            for x in 0..<n {
                let fx = Float(x) / 128, fy = Float(y) / 128
                let a = noise.fbm(fx, fy, oct: 5, period: 4) * 0.5 + 0.5
                let stain = smoothstepf(0.55, 0.8, noise.fbm(fx * 0.5 + 9, fy * 2 + 1, oct: 3, period: 2) * 0.5 + 0.5)
                let fine = noise.n2(Float(x) / 2, Float(y) / 2, period: 256) * 0.5 + 0.5
                let k1: Float = 0.86 + 0.18 * a + 0.06 * fine
                var c: V3 = base * k1
                c *= (1 - stain * 0.22)
                var hv = a * 0.3 + fine * 0.2
                if seams && (x % 256 < 2 || y % 256 < 2) {
                    c *= 0.6
                    hv -= 0.8
                }
                img.set(x, y, c)
                hgt[y * n + x] = hv
            }
        }
        return TexSet(albedo: img.cg(), normal: normalFromHeight(hgt, n, n, strength: 2), avg: img.average())
    }

    static func brick(_ noise: Noise, seed: UInt64, base: V3) -> TexSet {
        let n = 512
        let img = Img(n, n)
        var hgt = [Float](repeating: 0, count: n * n)
        let bw = 64, bh = 32
        for y in 0..<n {
            let row = y / bh
            let off = (row % 2) * (bw / 2)
            for x in 0..<n {
                let xx = (x + off) % n
                let col = xx / bw
                let lx = xx % bw, ly = y % bh
                let mortar = lx < 3 || ly < 3
                let rnd = Float(hash2(col, row, seed) % 1000) / 1000
                let a = noise.fbm(Float(x) / 32, Float(y) / 32, oct: 3, period: 16) * 0.5 + 0.5
                var c: V3
                var hv: Float
                if mortar {
                    let km: Float = 0.9 + 0.2 * a
                    c = V3(0.62, 0.60, 0.56) * km
                    hv = 0
                } else {
                    let kb: Float = (0.75 + 0.4 * rnd) * (0.9 + 0.2 * a)
                    c = base * kb
                    hv = 1 + a * 0.3
                }
                img.set(x, y, c)
                hgt[y * n + x] = hv
            }
        }
        return TexSet(albedo: img.cg(), normal: normalFromHeight(hgt, n, n, strength: 1.5), avg: img.average())
    }

    static func planks(_ noise: Noise, seed: UInt64, base: V3, plankPx: Int = 64) -> TexSet {
        let n = 512
        let img = Img(n, n)
        var hgt = [Float](repeating: 0, count: n * n)
        for y in 0..<n {
            for x in 0..<n {
                let p = x / plankPx
                let lx = x % plankPx
                let rnd = Float(hash2(p, 7, seed) % 1000) / 1000
                let gx: Float = Float(x) / 64
                let gy: Float = Float(y) / 16 + Float(p) * 3
                let gN: Float = noise.fbm(gx, gy, oct: 3, period: 32)
                let gA: Float = Float(x) * 0.6 + gN * 8
                let grain: Float = sin(gA) * 0.5 + 0.5
                let a = noise.fbm(Float(x) / 64, Float(y) / 64, oct: 3, period: 8) * 0.5 + 0.5
                let k1: Float = (0.75 + 0.35 * rnd) * (0.85 + 0.2 * grain)
                let k2: Float = 0.9 + 0.15 * a
                var c: V3 = base * (k1 * k2)
                var hv = grain * 0.2
                if lx < 2 {
                    c *= 0.45
                    hv = -1
                }
                img.set(x, y, c)
                hgt[y * n + x] = hv
            }
        }
        return TexSet(albedo: img.cg(), normal: normalFromHeight(hgt, n, n, strength: 2), avg: img.average())
    }

    static func roofTiles(_ noise: Noise, seed: UInt64, base: V3) -> TexSet {
        let n = 512
        let img = Img(n, n)
        var hgt = [Float](repeating: 0, count: n * n)
        let tw = 48, th = 40
        for y in 0..<n {
            let row = y / th
            let off = (row % 2) * (tw / 2)
            for x in 0..<n {
                let xx = (x + off) % n
                let col = xx / tw
                let ly = Float(y % th) / Float(th)
                let lx = Float(xx % tw) / Float(tw)
                let rnd = Float(hash2(col, row, seed) % 1000) / 1000
                let curve = sin(lx * kPi)
                let a = noise.fbm(Float(x) / 32, Float(y) / 32, oct: 3, period: 16) * 0.5 + 0.5
                let shade = 0.55 + 0.45 * ly
                let k1: Float = (0.8 + 0.3 * rnd) * shade
                let k2: Float = (0.8 + 0.25 * curve) * (0.9 + 0.15 * a)
                let c: V3 = base * (k1 * k2)
                img.set(x, y, c)
                hgt[y * n + x] = ly + curve * 0.3
            }
        }
        return TexSet(albedo: img.cg(), normal: normalFromHeight(hgt, n, n, strength: 2.5), avg: img.average())
    }

    static func corrugated(_ noise: Noise, base: V3, rust: Float) -> TexSet {
        let n = 256
        let img = Img(n, n)
        var hgt = [Float](repeating: 0, count: n * n)
        for y in 0..<n {
            for x in 0..<n {
                let ridge = sin(Float(x) / Float(n) * kTwoPi * 8) * 0.5 + 0.5
                let a = noise.fbm(Float(x) / 32, Float(y) / 32, oct: 4, period: 8) * 0.5 + 0.5
                let r = smoothstepf(0.55, 0.75, noise.fbm(Float(x) / 64 + 5, Float(y) / 24, oct: 4, period: 4) * 0.5 + 0.5) * rust
                let k1: Float = (0.82 + 0.25 * ridge) * (0.9 + 0.15 * a)
                var c: V3 = base * k1
                let k2: Float = 0.8 + 0.4 * a
                c = lerp3(c, V3(0.42, 0.24, 0.12) * k2, r)
                img.set(x, y, c)
                hgt[y * n + x] = ridge
            }
        }
        return TexSet(albedo: img.cg(), normal: normalFromHeight(hgt, n, n, strength: 3), avg: img.average())
    }

    static func floorTiles(_ noise: Noise, base: V3) -> TexSet {
        let n = 512
        let img = Img(n, n)
        var hgt = [Float](repeating: 0, count: n * n)
        for y in 0..<n {
            for x in 0..<n {
                let tx = x / 128, ty = y / 128
                let grout = x % 128 < 3 || y % 128 < 3
                let a = noise.fbm(Float(x) / 64, Float(y) / 64, oct: 4, period: 8) * 0.5 + 0.5
                let checker: Float = ((tx + ty) % 2 == 0) ? 1.0 : 0.88
                let k1: Float = checker * (0.92 + 0.12 * a)
                var c: V3 = base * k1
                if grout { c = V3(0.35, 0.34, 0.32) }
                img.set(x, y, c)
                hgt[y * n + x] = grout ? 0 : 1
            }
        }
        return TexSet(albedo: img.cg(), normal: normalFromHeight(hgt, n, n, strength: 1), avg: img.average())
    }

    static func crate(_ noise: Noise) -> TexSet {
        let n = 256
        let img = Img(n, n)
        var hgt = [Float](repeating: 0, count: n * n)
        for y in 0..<n {
            for x in 0..<n {
                let border = x < 20 || x > n - 21 || y < 20 || y > n - 21
                let diag = abs(x - y) < 12 && !border
                let gN: Float = noise.fbm(Float(x) / 16, Float(y) / 64, oct: 3, period: 16)
                let gA: Float = Float(y) * 0.5 + gN * 6
                let grain: Float = sin(gA) * 0.5 + 0.5
                let k1: Float = 0.8 + 0.25 * grain
                var c: V3 = V3(0.55, 0.42, 0.25) * k1
                if border || diag { c *= 0.78 }
                img.set(x, y, c)
                hgt[y * n + x] = (border || diag) ? 1 : 0.3 + grain * 0.1
            }
        }
        return TexSet(albedo: img.cg(), normal: normalFromHeight(hgt, n, n, strength: 2), avg: img.average())
    }

    // MARK: atlases

    static func camoColors(_ variant: Int) -> [V3] {
        switch variant {
        case 1: return [V3(0.62, 0.55, 0.40), V3(0.48, 0.40, 0.28), V3(0.70, 0.64, 0.50), V3(0.36, 0.30, 0.22)] // desert
        case 2: return [V3(0.82, 0.84, 0.86), V3(0.60, 0.62, 0.64), V3(0.92, 0.93, 0.95), V3(0.40, 0.42, 0.44)] // snow
        case 3: return [V3(0.30, 0.31, 0.33), V3(0.18, 0.18, 0.20), V3(0.42, 0.43, 0.45), V3(0.10, 0.10, 0.11)] // urban
        case 4: return [V3(0.18, 0.22, 0.30), V3(0.12, 0.14, 0.20), V3(0.26, 0.30, 0.38), V3(0.08, 0.09, 0.12)] // navy
        default: return [V3(0.30, 0.34, 0.20), V3(0.20, 0.24, 0.13), V3(0.40, 0.36, 0.24), V3(0.12, 0.12, 0.09)] // woodland
        }
    }

    static func fillRect(_ img: Img, _ r: UVRect, _ fn: (Float, Float, Int, Int) -> V3) {
        let x0 = Int(r.u0 * Float(img.w)), x1 = Int(r.u1 * Float(img.w))
        let y0 = Int(r.v0 * Float(img.h)), y1 = Int(r.v1 * Float(img.h))
        for y in max(0, y0 - 4)..<min(img.h, y1 + 4) {
            for x in max(0, x0 - 4)..<min(img.w, x1 + 4) {
                let u = Float(x - x0) / Float(max(1, x1 - x0))
                let v = Float(y - y0) / Float(max(1, y1 - y0))
                img.set(x, y, fn(u, v, x, y))
            }
        }
    }

    static func soldierAtlas(_ noise: Noise, variant: Int, skinTone: Float) -> TexSet {
        let n = 512
        let img = Img(n, n)
        var hgt = [Float](repeating: 0.5, count: n * n)
        let cc = camoColors(variant)
        let off = Float(variant) * 13.7
        func camo(_ x: Int, _ y: Int, dark: Float) -> V3 {
            let fx = Float(x) / 40 + off, fy = Float(y) / 40
            let a = noise.fbm(fx, fy, oct: 3) * 0.5 + 0.5
            let b = noise.fbm(fx + 40, fy + 11, oct: 3) * 0.5 + 0.5
            let c2 = noise.fbm(fx * 1.6 + 7, fy * 1.6 + 70, oct: 2) * 0.5 + 0.5
            var c = cc[0]
            if a > 0.55 { c = cc[1] }
            if b > 0.6 { c = cc[2] }
            if c2 > 0.66 { c = cc[3] }
            let fabric = (sin(Float(x) * 1.7) * sin(Float(y) * 1.7)) * 0.03
            return c * (dark + fabric)
        }
        fillRect(img, SoldierUV.camo) { _, _, x, y in camo(x, y, dark: 1.0) }
        fillRect(img, SoldierUV.pants) { _, _, x, y in camo(x, y, dark: 0.85) }
        let skin = lerp3(V3(0.85, 0.66, 0.52), V3(0.45, 0.30, 0.22), skinTone)
        fillRect(img, SoldierUV.skin) { u, v, x, y in
            let a = noise.n2(Float(x) / 8, Float(y) / 8) * 0.04
            var c = skin * (0.97 + a)
            // simple face hint: eyes and brows on front band
            if v > 0.42 && v < 0.48 && ((u > 0.40 && u < 0.46) || (u > 0.54 && u < 0.60)) { c = V3(0.1, 0.08, 0.07) }
            if v > 0.62 && v < 0.65 && u > 0.45 && u < 0.55 { c = skin * 0.7 }
            return c
        }
        let helmetBase: V3 = variant == 2 ? V3(0.80, 0.82, 0.84) : (variant == 1 ? V3(0.55, 0.48, 0.35) : V3(0.27, 0.30, 0.20))
        fillRect(img, SoldierUV.helmet) { _, _, x, y in
            let a = noise.fbm(Float(x) / 16, Float(y) / 16, oct: 3) * 0.5 + 0.5
            return helmetBase * (0.85 + 0.25 * a)
        }
        fillRect(img, SoldierUV.vest) { u, v, x, y in
            let web = (Int(v * 16) % 3 == 0) ? Float(0.7) : Float(1.0)
            let a = noise.fbm(Float(x) / 16, Float(y) / 16, oct: 3) * 0.5 + 0.5
            var c = V3(0.22, 0.23, 0.18) * web * (0.85 + 0.25 * a)
            if u > 0.2 && u < 0.45 && v > 0.55 && v < 0.85 { c *= 0.75 }
            if u > 0.55 && u < 0.8 && v > 0.55 && v < 0.85 { c *= 0.75 }
            return c
        }
        fillRect(img, SoldierUV.black) { _, _, x, y in
            let a = noise.fbm(Float(x) / 8, Float(y) / 8, oct: 2) * 0.5 + 0.5
            return V3(0.08, 0.08, 0.08) * (0.8 + 0.4 * a)
        }
        fillRect(img, SoldierUV.pack) { u, v, x, y in
            let pocket = (u > 0.15 && u < 0.85 && v > 0.45 && v < 0.85) ? Float(0.82) : Float(1.0)
            let strap = (abs(u - 0.3) < 0.03 || abs(u - 0.7) < 0.03) ? Float(0.6) : Float(1.0)
            return camo(x + 77, y + 31, dark: 0.9) * pocket * strap
        }
        for y in 0..<n { for x in 0..<n { hgt[y * n + x] = img.get(x, y).x * 0.5 + noise.n2(Float(x) / 3, Float(y) / 3) * 0.2 } }
        return TexSet(albedo: img.cg(), normal: normalFromHeight(hgt, n, n, strength: 1.2), avg: img.average())
    }

    static func gunAtlas(_ noise: Noise) -> TexSet {
        let n = 256
        let img = Img(n, n)
        fillRect(img, GunUV.metal) { _, _, x, y in
            let a = noise.fbm(Float(x) / 16, Float(y) / 16, oct: 3) * 0.5 + 0.5
            return V3(0.10, 0.10, 0.11) * (0.8 + 0.4 * a)
        }
        fillRect(img, GunUV.polymer) { _, _, x, y in
            let a = noise.n2(Float(x) / 4, Float(y) / 4) * 0.5 + 0.5
            return V3(0.17, 0.17, 0.17) * (0.9 + 0.15 * a)
        }
        fillRect(img, GunUV.wood) { _, _, x, y in
            let gN: Float = noise.fbm(Float(x) / 32, Float(y) / 8, oct: 3)
            let gA: Float = Float(y) * 0.8 + gN * 5
            let g: Float = sin(gA) * 0.5 + 0.5
            return V3(0.42, 0.24, 0.12) * (0.75 + 0.35 * g)
        }
        fillRect(img, GunUV.tan) { _, _, x, y in
            let a = noise.n2(Float(x) / 6, Float(y) / 6) * 0.5 + 0.5
            return V3(0.55, 0.47, 0.33) * (0.9 + 0.15 * a)
        }
        return TexSet(albedo: img.cg(), normal: nil, avg: img.average())
    }

    static func vehicleAtlas(_ noise: Noise, paint: V3) -> TexSet {
        let n = 512
        let img = Img(n, n)
        var hgt = [Float](repeating: 0, count: n * n)
        fillRect(img, VehUV.paint) { _, _, x, y in
            let a = noise.fbm(Float(x) / 32, Float(y) / 32, oct: 4) * 0.5 + 0.5
            let dirt = smoothstepf(0.55, 0.75, noise.fbm(Float(x) / 48 + 3, Float(y) / 20, oct: 4) * 0.5 + 0.5)
            return lerp3(paint * (0.9 + 0.15 * a), V3(0.36, 0.30, 0.22), dirt * 0.6)
        }
        fillRect(img, VehUV.tire) { u, v, x, y in
            let tread = (Int(v * 40) % 2 == 0) ? Float(0.7) : Float(1.0)
            let hub = (abs(u - 0.5) < 0.18) ? Float(1.6) : Float(1.0)
            return V3(0.06, 0.06, 0.06) * tread * hub
        }
        fillRect(img, VehUV.glass) { _, v, _, _ in
            return V3(0.05, 0.07, 0.09) * (0.7 + 0.6 * (1 - v))
        }
        fillRect(img, VehUV.metal) { _, _, x, y in
            let a = noise.fbm(Float(x) / 16, Float(y) / 16, oct: 3) * 0.5 + 0.5
            return V3(0.35, 0.35, 0.36) * (0.8 + 0.35 * a)
        }
        for y in 0..<n { for x in 0..<n { hgt[y * n + x] = img.get(x, y).y } }
        return TexSet(albedo: img.cg(), normal: normalFromHeight(hgt, n, n, strength: 1), avg: img.average())
    }

    // MARK: water / fx

    static func waterNormal(_ noise: Noise) -> CGImage {
        let n = 512
        var hgt = [Float](repeating: 0, count: n * n)
        for y in 0..<n {
            for x in 0..<n {
                let fx = Float(x) / 64, fy = Float(y) / 64
                hgt[y * n + x] = noise.fbm(fx, fy, oct: 5, period: 8) + 0.3 * noise.ridged(fx * 2 + 4, fy * 2, oct: 3, period: 16)
            }
        }
        return normalFromHeight(hgt, n, n, strength: 3)
    }

    static func radialSprite(size: Int, color: V3, hardness: Float, noise: Noise?) -> CGImage {
        let img = Img(size, size, fill: V3(0, 0, 0), alpha: 0)
        let c = Float(size) / 2
        for y in 0..<size {
            for x in 0..<size {
                let dx = (Float(x) + 0.5 - c) / c, dy = (Float(y) + 0.5 - c) / c
                let d = sqrt(dx * dx + dy * dy)
                var a = saturate(1 - d)
                a = pow(a, 1.0 / max(0.05, hardness))
                if let nz = noise {
                    a *= 0.6 + 0.6 * (nz.fbm(Float(x) / 12, Float(y) / 12, oct: 3) * 0.5 + 0.5)
                }
                img.set(x, y, color, saturate(a))
            }
        }
        return img.cg(alpha: true)
    }

    static func flashSprite() -> CGImage {
        let size = 128
        let img = Img(size, size, fill: V3(0, 0, 0), alpha: 0)
        let c = Float(size) / 2
        for y in 0..<size {
            for x in 0..<size {
                let dx = (Float(x) + 0.5 - c) / c, dy = (Float(y) + 0.5 - c) / c
                let d = sqrt(dx * dx + dy * dy)
                let ang = atan2(dy, dx)
                let star = pow(abs(cos(ang * 3)), 8) * 0.8
                let a = saturate((1 - d / (0.35 + star)) * 1.4)
                let col = lerp3(V3(1.0, 0.55, 0.15), V3(1.0, 0.95, 0.7), saturate(1 - d * 2))
                img.set(x, y, col, a)
            }
        }
        return img.cg(alpha: true)
    }

    static func zoneWall() -> CGImage {
        let w = 256, h = 128
        let img = Img(w, h, fill: V3(0, 0, 0), alpha: 0)
        for y in 0..<h {
            for x in 0..<w {
                let v = Float(y) / Float(h)
                let stripe = (sin(Float(x) * 0.25 + Float(y) * 0.5) * 0.5 + 0.5) * 0.25
                let a = saturate(0.35 + stripe) * (0.4 + 0.6 * v)
                img.set(x, y, V3(0.25, 0.55, 1.0), a)
            }
        }
        return img.cg(alpha: true)
    }

    static func parachute() -> TexSet {
        let n = 256
        let img = Img(n, n)
        for y in 0..<n {
            for x in 0..<n {
                let seg = (x / 32) % 2
                let c: V3 = seg == 0 ? V3(0.85, 0.30, 0.12) : V3(0.92, 0.90, 0.85)
                img.set(x, y, c * (0.9 + 0.1 * Float(y) / Float(n)))
            }
        }
        return TexSet(albedo: img.cg(), normal: nil, avg: img.average())
    }
}
