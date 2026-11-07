import Foundation
import simd
import SceneKit

typealias V2 = SIMD2<Float>
typealias V3 = SIMD3<Float>
typealias V4 = SIMD4<Float>
typealias M4 = simd_float4x4
typealias Quat = simd_quatf

let kPi: Float = Float.pi
let kTwoPi: Float = Float.pi * 2

@inline(__always) func clampf(_ x: Float, _ a: Float, _ b: Float) -> Float { return min(max(x, a), b) }
@inline(__always) func saturate(_ x: Float) -> Float { return min(max(x, 0), 1) }
@inline(__always) func lerpf(_ a: Float, _ b: Float, _ t: Float) -> Float { return a + (b - a) * t }
@inline(__always) func lerp3(_ a: V3, _ b: V3, _ t: Float) -> V3 { return a + (b - a) * t }
@inline(__always) func smoothstepf(_ e0: Float, _ e1: Float, _ x: Float) -> Float {
    let t = saturate((x - e0) / (e1 - e0))
    return t * t * (3 - 2 * t)
}

func wrapAngle(_ a: Float) -> Float {
    var x = a
    while x > kPi { x -= kTwoPi }
    while x < -kPi { x += kTwoPi }
    return x
}

/// Moves angle `a` towards `b` by at most `step` radians (shortest way).
func approachAngle(_ a: Float, _ b: Float, _ step: Float) -> Float {
    let d = wrapAngle(b - a)
    if abs(d) <= step { return b }
    return a + (d > 0 ? step : -step)
}

func approachf(_ a: Float, _ b: Float, _ step: Float) -> Float {
    if a < b { return min(a + step, b) }
    return max(a - step, b)
}

@inline(__always) func vlen(_ v: V3) -> Float { return simd_length(v) }
@inline(__always) func vlen2(_ v: V2) -> Float { return simd_length(v) }
@inline(__always) func vdot(_ a: V3, _ b: V3) -> Float { return simd_dot(a, b) }
@inline(__always) func vcross(_ a: V3, _ b: V3) -> V3 { return simd_cross(a, b) }

func vnorm(_ v: V3) -> V3 {
    let l = simd_length(v)
    return l > 1e-6 ? v / l : V3(0, 1, 0)
}

func vnorm2(_ v: V2) -> V2 {
    let l = simd_length(v)
    return l > 1e-6 ? v / l : V2(0, 0)
}

@inline(__always) func xz(_ v: V3) -> V2 { return V2(v.x, v.z) }

/// yaw = 0 looks towards -Z (north). Positive yaw turns left (towards -X).
func dirFrom(yaw: Float, pitch: Float) -> V3 {
    return V3(-sin(yaw) * cos(pitch), sin(pitch), -cos(yaw) * cos(pitch))
}
func flatForward(_ yaw: Float) -> V3 { return V3(-sin(yaw), 0, -cos(yaw)) }
func flatRight(_ yaw: Float) -> V3 { return V3(cos(yaw), 0, -sin(yaw)) }
func yawOf(_ d: V3) -> Float { return atan2(-d.x, -d.z) }
func pitchOf(_ d: V3) -> Float {
    let h = sqrt(d.x * d.x + d.z * d.z)
    return atan2(d.y, max(h, 1e-5))
}

/// Compass heading in degrees, 0 = north (-Z), 90 = east (+X)
func headingDegrees(yaw: Float) -> Float {
    var h = -yaw * 180 / kPi
    while h < 0 { h += 360 }
    while h >= 360 { h -= 360 }
    return h
}

func mTranslate(_ t: V3) -> M4 {
    var m = matrix_identity_float4x4
    m.columns.3 = V4(t.x, t.y, t.z, 1)
    return m
}
func mRotX(_ a: Float) -> M4 { return M4(simd_quatf(angle: a, axis: V3(1, 0, 0))) }
func mRotY(_ a: Float) -> M4 { return M4(simd_quatf(angle: a, axis: V3(0, 1, 0))) }
func mRotZ(_ a: Float) -> M4 { return M4(simd_quatf(angle: a, axis: V3(0, 0, 1))) }
func mScale(_ s: V3) -> M4 { return M4(diagonal: V4(s.x, s.y, s.z, 1)) }
func mScale(_ s: Float) -> M4 { return M4(diagonal: V4(s, s, s, 1)) }

@inline(__always) func transformPoint(_ m: M4, _ p: V3) -> V3 {
    let r = m * V4(p.x, p.y, p.z, 1)
    return V3(r.x, r.y, r.z)
}

func normalMatrix(_ m: M4) -> simd_float3x3 {
    let a = simd_float3x3(V3(m.columns.0.x, m.columns.0.y, m.columns.0.z),
                          V3(m.columns.1.x, m.columns.1.y, m.columns.1.z),
                          V3(m.columns.2.x, m.columns.2.y, m.columns.2.z))
    return a.inverse.transpose
}

func quatYaw(_ a: Float) -> Quat { return simd_quatf(angle: a, axis: V3(0, 1, 0)) }

/// Rotate a 2D (x,z) offset by a quarter-turn count (0..3)
func rotQ(_ x: Float, _ z: Float, _ k: Int) -> (Float, Float) {
    switch ((k % 4) + 4) % 4 {
    case 1: return (-z, x)
    case 2: return (-x, -z)
    case 3: return (z, -x)
    default: return (x, z)
    }
}

/// Deterministic random generator (SplitMix64)
struct RNG {
    var state: UInt64
    init(_ seed: UInt64) { state = seed &+ 0x9E3779B97F4A7C15 }
    mutating func next() -> UInt64 {
        state = state &+ 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
    mutating func f() -> Float { return Float(next() >> 40) / 16777216.0 }
    mutating func r(_ a: Float, _ b: Float) -> Float { return a + (b - a) * f() }
    mutating func i(_ n: Int) -> Int { return n <= 0 ? 0 : Int(next() % UInt64(n)) }
    mutating func chance(_ p: Float) -> Bool { return f() < p }
    mutating func sign() -> Float { return chance(0.5) ? 1 : -1 }
    mutating func pick<T>(_ a: [T]) -> T { return a[i(a.count)] }
    mutating func gauss() -> Float {
        let u1 = max(f(), 1e-6), u2 = f()
        return sqrt(-2 * log(u1)) * cos(kTwoPi * u2)
    }
    mutating func inDisc(_ radius: Float) -> V2 {
        let a = r(0, kTwoPi), d = sqrt(f()) * radius
        return V2(cos(a) * d, sin(a) * d)
    }
}

func hash2(_ x: Int, _ y: Int, _ seed: UInt64) -> UInt64 {
    var h = UInt64(bitPattern: Int64(x)) &* 0x9E3779B185EBCA87
    h ^= UInt64(bitPattern: Int64(y)) &* 0xC2B2AE3D27D4EB4F
    h ^= seed &* 0x165667B19E3779F9
    h ^= h >> 29
    h = h &* 0xBF58476D1CE4E5B9
    h ^= h >> 32
    return h
}

func distXZ(_ a: V3, _ b: V3) -> Float {
    let dx = a.x - b.x, dz = a.z - b.z
    return sqrt(dx * dx + dz * dz)
}

func fmtTime(_ s: Float) -> String {
    let t = max(0, Int(s.rounded(.up)))
    return String(format: "%d:%02d", t / 60, t % 60)
}

/// Thread-safe small lock wrapper
final class Lock {
    private let l = NSLock()
    @inline(__always) func run<T>(_ body: () -> T) -> T {
        l.lock()
        defer { l.unlock() }
        return body()
    }
}
