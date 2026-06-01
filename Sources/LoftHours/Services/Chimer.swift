import AVFoundation

/// The three audio cues, matching the note sequences from the original timer's
/// WebAudio chime (C5/E5 at halfway, E5/G5 in the last minute, C5/E5/G5 on
/// complete).
enum ChimeKind {
    case halfway, lastMinute, complete

    var frequencies: [Double] {
        switch self {
        case .halfway:    return [523.25, 659.25]
        case .lastMinute: return [659.25, 783.99]
        case .complete:   return [523.25, 659.25, 783.99]
        }
    }
}

/// Plays soft synthesized chimes through AVAudioEngine. Tones are generated as
/// staggered sine bursts with a gentle attack/decay envelope, so no audio files
/// need to ship. Synced cues (fired from the controller's tick) replace the
/// browser chime from the skill's HTML timer.
@MainActor
final class Chimer {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)!
    private var started = false

    init() {
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
    }

    func play(_ kind: ChimeKind) {
        ensureRunning()
        guard let buffer = makeBuffer(frequencies: kind.frequencies) else { return }
        player.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
        if !player.isPlaying { player.play() }
    }

    private func ensureRunning() {
        guard !started else { return }
        do {
            try engine.start()
            started = true
        } catch {
            // Audio unavailable; cues just won't sound.
        }
    }

    /// Build one buffer holding the full staggered sequence.
    private func makeBuffer(frequencies: [Double]) -> AVAudioPCMBuffer? {
        let sampleRate = format.sampleRate
        let stagger = 0.16      // seconds between note onsets
        let noteDur = 0.5       // seconds per note
        let peak: Float = 0.18

        let totalDur = stagger * Double(max(0, frequencies.count - 1)) + noteDur
        let frameCount = AVAudioFrameCount(totalDur * sampleRate)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return nil }
        buffer.frameLength = frameCount

        guard let channels = buffer.floatChannelData else { return nil }
        let left = channels[0]
        let right = channels[1]

        // Zero-fill.
        for i in 0..<Int(frameCount) { left[i] = 0; right[i] = 0 }

        for (idx, freq) in frequencies.enumerated() {
            let startFrame = Int(Double(idx) * stagger * sampleRate)
            let noteFrames = Int(noteDur * sampleRate)
            let attackFrames = Int(0.03 * sampleRate)
            for n in 0..<noteFrames {
                let frame = startFrame + n
                if frame >= Int(frameCount) { break }
                let t = Double(n) / sampleRate
                // Attack then exponential decay.
                let env: Double
                if n < attackFrames {
                    env = Double(n) / Double(attackFrames)
                } else {
                    env = exp(-3.5 * (t - 0.03))
                }
                let sample = Float(sin(2.0 * .pi * freq * t) * env) * peak
                left[frame] += sample
                right[frame] += sample
            }
        }
        return buffer
    }
}
