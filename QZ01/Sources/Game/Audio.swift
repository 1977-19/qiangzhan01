import AVFoundation

/// Fully synthesised positional audio (no sound files needed).
final class AudioSys {
    let engine = AVAudioEngine()
    let env = AVAudioEnvironmentNode()
    let format: AVAudioFormat
    private var players: [AVAudioPlayerNode] = []
    private var nextPlayer = 0
    private var buffers: [String: AVAudioPCMBuffer] = [:]
    private var loops: [String: AVAudioPlayerNode] = [:]
    private(set) var running = false
    private let sr: Double = 44100
    var listener = V3(0, 0, 0)

    init() {
        format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
        engine.attach(env)
        engine.connect(env, to: engine.mainMixerNode, format: nil)
        env.distanceAttenuationParameters.distanceAttenuationModel = .inverse
        env.distanceAttenuationParameters.referenceDistance = 6
        env.distanceAttenuationParameters.maximumDistance = 900
        env.distanceAttenuationParameters.rolloffFactor = 0.9
        env.reverbParameters.enable = false
        for _ in 0..<24 {
            let p = AVAudioPlayerNode()
            engine.attach(p)
            engine.connect(p, to: env, format: format)
            p.renderingAlgorithm = .equalPowerPanning
            players.append(p)
        }
        synth()
        for name in ["wind", "engine", "plane"] {
            let p = AVAudioPlayerNode()
            engine.attach(p)
            engine.connect(p, to: env, format: format)
            p.renderingAlgorithm = .equalPowerPanning
            loops[name] = p
        }
        engine.mainMixerNode.outputVolume = 0.9
        do {
            try engine.start()
            running = true
            for (name, p) in loops {
                if let b = buffers[name] {
                    p.scheduleBuffer(b, at: nil, options: [.loops], completionHandler: nil)
                    p.volume = 0
                    p.play()
                }
            }
        } catch {
            running = false
        }
    }

    func stop() {
        for p in players { p.stop() }
        for (_, p) in loops { p.stop() }
        engine.stop()
        running = false
    }

    // MARK: synthesis

    private func makeBuffer(_ s: [Float]) -> AVAudioPCMBuffer? {
        guard let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(s.count)) else { return nil }
        buf.frameLength = AVAudioFrameCount(s.count)
        if let ch = buf.floatChannelData?[0] {
            for i in 0..<s.count { ch[i] = s[i] }
        }
        return buf
    }

    private func gunshot(seed: UInt64, crack: Float, crackDecay: Float, thumpHz: Float, thump: Float, tail: Float, tailDecay: Float, lp: Float) -> [Float] {
        var rng = RNG(seed)
        let n = Int(sr * 1.0)
        var out = [Float](repeating: 0, count: n)
        var lpS: Float = 0
        var tailLp: Float = 0
        for i in 0..<n {
            let t = Float(i) / Float(sr)
            let noise = rng.r(-1, 1)
            lpS += (noise - lpS) * lp
            let c = lpS * crack * exp(-t / crackDecay)
            let th = sin(2 * kPi * thumpHz * t * (1 - t * 0.8)) * thump * exp(-t / 0.07)
            tailLp += (noise - tailLp) * 0.05
            let tl = tailLp * tail * exp(-t / tailDecay) * min(1, t * 40)
            out[i] = c + th + tl
        }
        normalize(&out, 0.95)
        return out
    }

    private func normalize(_ a: inout [Float], _ peak: Float) {
        var m: Float = 1e-6
        for v in a { m = max(m, abs(v)) }
        let k = peak / m
        for i in 0..<a.count { a[i] *= k }
    }

    private func noiseBurst(seed: UInt64, dur: Float, decay: Float, lp: Float, amp: Float) -> [Float] {
        var rng = RNG(seed)
        let n = Int(Float(sr) * dur)
        var out = [Float](repeating: 0, count: n)
        var s: Float = 0
        for i in 0..<n {
            let t = Float(i) / Float(sr)
            s += (rng.r(-1, 1) - s) * lp
            out[i] = s * amp * exp(-t / decay) * min(1, t * 200)
        }
        return out
    }

    private func synth() {
        let defs: [(String, [Float])] = [
            ("m416", gunshot(seed: 1, crack: 1.0, crackDecay: 0.025, thumpHz: 90, thump: 0.8, tail: 0.6, tailDecay: 0.22, lp: 0.55)),
            ("akm", gunshot(seed: 2, crack: 1.0, crackDecay: 0.035, thumpHz: 70, thump: 1.0, tail: 0.7, tailDecay: 0.28, lp: 0.45)),
            ("uzi", gunshot(seed: 3, crack: 0.9, crackDecay: 0.018, thumpHz: 120, thump: 0.5, tail: 0.35, tailDecay: 0.12, lp: 0.6)),
            ("kar98k", gunshot(seed: 4, crack: 1.0, crackDecay: 0.05, thumpHz: 55, thump: 1.2, tail: 1.0, tailDecay: 0.55, lp: 0.4)),
            ("s12k", gunshot(seed: 5, crack: 1.0, crackDecay: 0.06, thumpHz: 50, thump: 1.3, tail: 0.8, tailDecay: 0.35, lp: 0.3)),
            ("p92", gunshot(seed: 6, crack: 0.9, crackDecay: 0.02, thumpHz: 110, thump: 0.5, tail: 0.3, tailDecay: 0.12, lp: 0.65)),
        ]
        for (k, s) in defs { buffers[k] = makeBuffer(s) }
        buffers["step"] = makeBuffer(noiseBurst(seed: 7, dur: 0.14, decay: 0.035, lp: 0.12, amp: 0.6))
        buffers["stepSnow"] = makeBuffer(noiseBurst(seed: 8, dur: 0.18, decay: 0.05, lp: 0.25, amp: 0.5))
        // reload: two clicks
        var rl = [Float](repeating: 0, count: Int(sr * 0.6))
        let c1 = noiseBurst(seed: 9, dur: 0.05, decay: 0.008, lp: 0.9, amp: 1)
        for i in 0..<c1.count { rl[i] += c1[i] }
        let off = Int(sr * 0.42)
        for i in 0..<c1.count where off + i < rl.count { rl[off + i] += c1[i] * 0.9 }
        buffers["reload"] = makeBuffer(rl)
        // hit marker tick
        var hit = [Float](repeating: 0, count: Int(sr * 0.08))
        for i in 0..<hit.count {
            let t = Float(i) / Float(sr)
            hit[i] = sin(2 * kPi * 2200 * t) * exp(-t / 0.015) * 0.6
        }
        buffers["hit"] = makeBuffer(hit)
        // explosion
        var ex = noiseBurst(seed: 10, dur: 2.2, decay: 0.5, lp: 0.06, amp: 1)
        for i in 0..<ex.count {
            let t = Float(i) / Float(sr)
            ex[i] += sin(2 * kPi * 38 * t) * exp(-t / 0.35) * 0.9
        }
        normalize(&ex, 0.95)
        buffers["explosion"] = makeBuffer(ex)
        // loops
        var wind = [Float](repeating: 0, count: Int(sr * 3))
        var rng = RNG(11)
        var s: Float = 0
        for i in 0..<wind.count {
            s += (rng.r(-1, 1) - s) * 0.03
            let t = Float(i) / Float(wind.count)
            wind[i] = s * (0.7 + 0.3 * sin(t * kTwoPi * 2))
        }
        normalize(&wind, 0.8)
        buffers["wind"] = makeBuffer(wind)
        var eng = [Float](repeating: 0, count: Int(sr * 1.0))
        for i in 0..<eng.count {
            let t = Float(i) / Float(sr)
            let f: Float = 46
            var v: Float = 0
            for h in 1...6 { v += sin(2 * kPi * f * Float(h) * t) / Float(h) }
            eng[i] = v * (0.8 + 0.2 * sin(2 * kPi * 8 * t))
        }
        normalize(&eng, 0.7)
        buffers["engine"] = makeBuffer(eng)
        var pl = [Float](repeating: 0, count: Int(sr * 2.0))
        s = 0
        for i in 0..<pl.count {
            let t = Float(i) / Float(sr)
            s += (rng.r(-1, 1) - s) * 0.05
            pl[i] = sin(2 * kPi * 82 * t) * 0.5 + sin(2 * kPi * 164 * t) * 0.2 + s * 0.6
        }
        normalize(&pl, 0.8)
        buffers["plane"] = makeBuffer(pl)
        var pick = [Float](repeating: 0, count: Int(sr * 0.12))
        for i in 0..<pick.count {
            let t = Float(i) / Float(sr)
            pick[i] = sin(2 * kPi * (600 + 900 * t * 8) * t) * exp(-t / 0.04) * 0.5
        }
        buffers["pickup"] = makeBuffer(pick)
        buffers["heal"] = makeBuffer(noiseBurst(seed: 12, dur: 0.6, decay: 0.25, lp: 0.2, amp: 0.4))
        buffers["bolt"] = makeBuffer(noiseBurst(seed: 13, dur: 0.12, decay: 0.03, lp: 0.7, amp: 0.8))
        buffers["impact"] = makeBuffer(noiseBurst(seed: 14, dur: 0.12, decay: 0.02, lp: 0.5, amp: 0.7))
    }

    // MARK: playback

    func play(_ name: String, at p: V3, volume: Float = 1, rate: Float = 1) {
        guard running, let b = buffers[name] else { return }
        let d = vlen(p - listener)
        if d > 1000 { return }
        let node = players[nextPlayer]
        nextPlayer = (nextPlayer + 1) % players.count
        node.stop()
        node.position = AVAudio3DPoint(x: p.x, y: p.y, z: p.z)
        node.volume = volume
        node.rate = rate
        node.scheduleBuffer(b, at: nil, options: [], completionHandler: nil)
        node.play()
    }

    func playUI(_ name: String, volume: Float = 1) {
        play(name, at: listener + V3(0, 0.1, 0), volume: volume)
    }

    func setListener(pos: V3, forward: V3) {
        guard running else { return }
        listener = pos
        env.listenerPosition = AVAudio3DPoint(x: pos.x, y: pos.y, z: pos.z)
        env.listenerVectorOrientation = AVAudio3DVectorOrientation(forward: AVAudio3DVector(x: forward.x, y: forward.y, z: forward.z),
                                                                   up: AVAudio3DVector(x: 0, y: 1, z: 0))
    }

    func setLoop(_ name: String, volume: Float, rate: Float = 1, at p: V3? = nil) {
        guard running, let n = loops[name] else { return }
        n.volume = volume
        n.rate = max(0.5, min(2.0, rate))
        let q = p ?? listener
        n.position = AVAudio3DPoint(x: q.x, y: q.y, z: q.z)
    }
}
