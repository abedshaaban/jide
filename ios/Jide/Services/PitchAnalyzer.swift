import AVFoundation
import Foundation

/// Pitch contour extraction (autocorrelation) for comparing the owner's tones with TTS.
enum PitchAnalyzer {
    struct Point: Identifiable {
        var time: Double      // 0...1 across the voiced part
        var semitones: Double // relative to the speaker's median pitch
        var id: Double { time }
    }

    static func monoFloats(_ buffer: AVAudioPCMBuffer) -> [Float] {
        let n = Int(buffer.frameLength)
        if let f = buffer.floatChannelData { return Array(UnsafeBufferPointer(start: f[0], count: n)) }
        if let i = buffer.int16ChannelData {
            return UnsafeBufferPointer(start: i[0], count: n).map { Float($0) / 32768 }
        }
        if let i = buffer.int32ChannelData {
            return UnsafeBufferPointer(start: i[0], count: n).map { Float($0) / 2_147_483_648 }
        }
        return []
    }

    static func load(_ url: URL) -> (samples: [Float], sampleRate: Double)? {
        guard let file = try? AVAudioFile(forReading: url),
              let buf = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)),
              (try? file.read(into: buf)) != nil else { return nil }
        return (monoFloats(buf), file.processingFormat.sampleRate)
    }

    /// Returns a contour with ~100 Hz frame rate. Unvoiced frames are dropped.
    static func contour(samples raw: [Float], sampleRate: Double) -> [Point] {
        guard sampleRate > 0, !raw.isEmpty else { return [] }
        // Downsample to ~11 kHz by averaging.
        let factor = max(1, Int(sampleRate / 11025))
        let sr = sampleRate / Double(factor)
        var x = [Float](repeating: 0, count: raw.count / factor)
        for i in 0..<x.count {
            var s: Float = 0
            for j in 0..<factor { s += raw[i * factor + j] }
            x[i] = s / Float(factor)
        }
        let frame = Int(sr * 0.04), hop = Int(sr * 0.01)
        let minLag = Int(sr / 450), maxLag = min(Int(sr / 70), frame - 1)
        guard x.count > frame, maxLag > minLag else { return [] }

        let peak = x.map { abs($0) }.max() ?? 0
        let gate = peak * 0.08
        var raws: [(Double, Double)] = []
        var start = 0
        x.withUnsafeBufferPointer { p in
            while start + frame < p.count {
                var energy: Float = 0
                var amp: Float = 0
                for i in start..<(start + frame) { energy += p[i] * p[i]; amp = max(amp, abs(p[i])) }
                if amp > gate && energy > 0 {
                    var bestLag = 0
                    var best: Float = 0
                    for lag in minLag...maxLag {
                        var s: Float = 0
                        for i in start..<(start + frame - lag) { s += p[i] * p[i + lag] }
                        if s > best { best = s; bestLag = lag }
                    }
                    if best / energy > 0.45 && bestLag > minLag && bestLag < maxLag {
                        raws.append((Double(start) / sr, sr / Double(bestLag)))
                    }
                }
                start += hop
            }
        }
        guard raws.count > 3 else { return [] }

        // Median filter to remove octave jumps, then convert to semitones around the median.
        let hz = raws.map(\.1)
        var smooth = hz
        for i in 0..<hz.count {
            let w = hz[max(0, i - 2)...min(hz.count - 1, i + 2)].sorted()
            smooth[i] = w[w.count / 2]
        }
        let median = smooth.sorted()[smooth.count / 2]
        let t0 = raws.first!.0, t1 = raws.last!.0
        let span = max(t1 - t0, 0.001)
        return zip(raws, smooth).compactMap { r, f in
            let st = 12 * log2(f / median)
            guard abs(st) < 12 else { return nil }
            return Point(time: (r.0 - t0) / span, semitones: st)
        }
    }
}
