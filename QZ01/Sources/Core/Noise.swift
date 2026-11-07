import Foundation

/// Gradient (Perlin) noise with optional periodic tiling (period up to 1024).
final class Noise {
    private var perm: [Int32]

    init(seed: UInt64) {
        var p = [Int32](0..<1024)
        var rng = RNG(seed)
        var i = 1023
        while i > 0 {
            let j = rng.i(i + 1)
            p.swapAt(i, j)
            i -= 1
        }
        perm = p + p
    }

    @inline(__always) private func fade(_ t: Float) -> Float {
        return t * t * t * (t * (t * 6 - 15) + 10)
    }

    @inline(__always) private func grad(_ h: Int32, _ x: Float, _ y: Float) -> Float {
        switch h & 7 {
        case 0: return x + y
        case 1: return -x + y
        case 2: return x - y
        case 3: return -x - y
        case 4: return x * 1.41
        case 5: return -x * 1.41
        case 6: return y * 1.41
        default: return -y * 1.41
        }
    }

    /// Single octave, range roughly -1...1. `period` makes it tile (in lattice units).
    func n2(_ x: Float, _ y: Float, period: Int = 1024) -> Float {
        let xf = x.rounded(.down), yf = y.rounded(.down)
        let pr = max(1, min(period, 1024))
        var xi = Int(xf) % pr
        if xi < 0 { xi += pr }
        var yi = Int(yf) % pr
        if yi < 0 { yi += pr }
        let xi1 = (xi + 1) % pr
        let yi1 = (yi + 1) % pr
        let fx = x - xf, fy = y - yf
        let u = fade(fx), v = fade(fy)
        let a0 = Int(perm[xi]), a1 = Int(perm[xi1])
        let h00 = perm[a0 + yi], h01 = perm[a0 + yi1]
        let h10 = perm[a1 + yi], h11 = perm[a1 + yi1]
        let x1 = lerpf(grad(h00, fx, fy), grad(h10, fx - 1, fy), u)
        let x2 = lerpf(grad(h01, fx, fy - 1), grad(h11, fx - 1, fy - 1), u)
        return lerpf(x1, x2, v) * 0.7
    }

    /// Fractal brownian motion, result roughly -1...1
    func fbm(_ x: Float, _ y: Float, oct: Int, period: Int = 1024, gain: Float = 0.5) -> Float {
        var amp: Float = 1, freq: Float = 1, sum: Float = 0, norm: Float = 0
        var p = period
        for _ in 0..<oct {
            sum += amp * n2(x * freq, y * freq, period: p)
            norm += amp
            amp *= gain
            freq *= 2
            p = min(p * 2, 1024)
        }
        return sum / norm
    }

    /// Ridged noise 0...1 (sharp crests)
    func ridged(_ x: Float, _ y: Float, oct: Int, period: Int = 1024) -> Float {
        var amp: Float = 0.5, freq: Float = 1, sum: Float = 0, norm: Float = 0
        var p = period
        for _ in 0..<oct {
            let n = 1 - abs(n2(x * freq, y * freq, period: p) * 1.4)
            sum += amp * n * n
            norm += amp
            amp *= 0.5
            freq *= 2
            p = min(p * 2, 1024)
        }
        return sum / norm
    }

    /// Cheap cellular-ish value: distance to nearest jittered point (tileable with period)
    func cell(_ x: Float, _ y: Float, period: Int) -> Float {
        let xi = Int(x.rounded(.down)), yi = Int(y.rounded(.down))
        var best: Float = 9
        for dy in -1...1 {
            for dx in -1...1 {
                var cx = (xi + dx) % period; if cx < 0 { cx += period }
                var cy = (yi + dy) % period; if cy < 0 { cy += period }
                let h = Int(perm[Int(perm[cx & 1023]) + (cy & 1023)])
                let jx = Float(h & 255) / 255.0
                let jy = Float((h >> 2) & 255) / 255.0
                let px = Float(xi + dx) + jx, py = Float(yi + dy) + jy
                let d = (px - x) * (px - x) + (py - y) * (py - y)
                if d < best { best = d }
            }
        }
        return sqrt(best)
    }
}
