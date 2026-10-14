import AppKit

/// The moments Talkie makes a noise.
enum SoundCue: String, CaseIterable, Sendable {
    case recordingStarted, recordingStopped, capApproaching, pasted, failed
}

/// A set of sounds. All but `system` are synthesised in-app (see `ToneSynth`)
/// so they can be quieter and softer than the bundled macOS alert sounds.
enum SoundTheme: String, CaseIterable, Sendable {
    case chime, marimba, glass, minimal, system, off

    var title: String {
        switch self {
        case .chime: return "Soft Chime"
        case .marimba: return "Marimba"
        case .glass: return "Muted Glass"
        case .minimal: return "Minimal"
        case .system: return "macOS Sounds"
        case .off: return "Off"
        }
    }

    var subtitle: String {
        switch self {
        case .chime: return "Gentle two-note cues, soft bell when pasted"
        case .marimba: return "Warm wooden taps, rising arpeggio when pasted"
        case .glass: return "Like the macOS Glass sound, but quieter and rounder"
        case .minimal: return "Barely-there ticks, one soft note when pasted"
        case .system: return "Tink, Pop, Glass and Basso"
        case .off: return "No sounds"
        }
    }

    /// The bundled macOS sound for `system`, nil for synthesised themes.
    fileprivate func systemName(for cue: SoundCue) -> String? {
        guard self == .system else { return nil }
        switch cue {
        case .recordingStarted: return "Tink"
        case .recordingStopped: return "Pop"
        case .capApproaching: return "Purr"
        case .pasted: return "Glass"
        case .failed: return "Basso"
        }
    }

    /// The notes of a synthesised cue. Times in seconds, frequencies in Hz.
    func notes(for cue: SoundCue) -> [ToneSynth.Note] {
        switch self {
        case .system, .off:
            return []

        case .chime:
            // Pure sine with a whisper of octave: soft and round.
            let soft = ToneSynth.Timbre(partials: [(1, 1), (2, 0.12)])
            // Bell-like partials for the ringing tail.
            let bell = ToneSynth.Timbre(partials: [(1, 1), (2.0, 0.35), (2.76, 0.22), (5.4, 0.06)])
            switch cue {
            case .recordingStarted:
                return [.init(at: 0, hz: 659, decay: 0.12, amp: 0.30, timbre: soft),
                        .init(at: 0.11, hz: 880, decay: 0.18, amp: 0.30, timbre: soft)]
            case .recordingStopped:
                return [.init(at: 0, hz: 880, decay: 0.12, amp: 0.28, timbre: soft),
                        .init(at: 0.11, hz: 659, decay: 0.18, amp: 0.26, timbre: soft)]
            case .capApproaching:
                return [.init(at: 0, hz: 523, decay: 0.08, amp: 0.25, timbre: soft),
                        .init(at: 0.18, hz: 523, decay: 0.08, amp: 0.25, timbre: soft)]
            case .pasted:
                return [.init(at: 0, hz: 1047, decay: 0.55, amp: 0.26, timbre: bell)]
            case .failed:
                return [.init(at: 0, hz: 330, decay: 0.16, amp: 0.30, timbre: soft),
                        .init(at: 0.17, hz: 277, decay: 0.30, amp: 0.30, timbre: soft)]
            }

        case .marimba:
            // A marimba bar: fundamental, strong fourth partial, quick decay.
            let wood = ToneSynth.Timbre(partials: [(1, 1), (4, 0.30), (10, 0.06)])
            switch cue {
            case .recordingStarted:
                return [.init(at: 0, hz: 523, decay: 0.09, amp: 0.34, timbre: wood),
                        .init(at: 0.10, hz: 659, decay: 0.14, amp: 0.34, timbre: wood)]
            case .recordingStopped:
                return [.init(at: 0, hz: 659, decay: 0.09, amp: 0.32, timbre: wood),
                        .init(at: 0.10, hz: 523, decay: 0.14, amp: 0.30, timbre: wood)]
            case .capApproaching:
                return [.init(at: 0, hz: 440, decay: 0.07, amp: 0.30, timbre: wood),
                        .init(at: 0.16, hz: 440, decay: 0.07, amp: 0.30, timbre: wood)]
            case .pasted:
                return [.init(at: 0, hz: 523, decay: 0.10, amp: 0.30, timbre: wood),
                        .init(at: 0.09, hz: 659, decay: 0.10, amp: 0.30, timbre: wood),
                        .init(at: 0.18, hz: 784, decay: 0.45, amp: 0.30, timbre: wood)]
            case .failed:
                return [.init(at: 0, hz: 294, decay: 0.14, amp: 0.34, timbre: wood),
                        .init(at: 0.15, hz: 262, decay: 0.26, amp: 0.34, timbre: wood)]
            }

        case .glass:
            // Inharmonic partials give the glassy ring; low amplitudes keep it mellow.
            let glass = ToneSynth.Timbre(partials: [(1, 1), (1.5, 0.25), (2.0, 0.30), (3.0, 0.10), (4.2, 0.04)])
            let tap = ToneSynth.Timbre(partials: [(1, 1), (2.0, 0.20), (3.0, 0.05)])
            switch cue {
            case .recordingStarted:
                return [.init(at: 0, hz: 1175, decay: 0.14, amp: 0.22, timbre: tap)]
            case .recordingStopped:
                return [.init(at: 0, hz: 784, decay: 0.16, amp: 0.22, timbre: tap)]
            case .capApproaching:
                return [.init(at: 0, hz: 988, decay: 0.06, amp: 0.20, timbre: tap),
                        .init(at: 0.18, hz: 988, decay: 0.06, amp: 0.20, timbre: tap)]
            case .pasted:
                return [.init(at: 0, hz: 1319, decay: 0.70, amp: 0.20, timbre: glass)]
            case .failed:
                return [.init(at: 0, hz: 392, decay: 0.20, amp: 0.26, timbre: tap),
                        .init(at: 0.20, hz: 349, decay: 0.35, amp: 0.26, timbre: tap)]
            }

        case .minimal:
            let tick = ToneSynth.Timbre(partials: [(1, 1)])
            switch cue {
            case .recordingStarted:
                return [.init(at: 0, hz: 1500, decay: 0.025, amp: 0.30, timbre: tick)]
            case .recordingStopped:
                return [.init(at: 0, hz: 1000, decay: 0.03, amp: 0.30, timbre: tick)]
            case .capApproaching:
                return [.init(at: 0, hz: 1200, decay: 0.02, amp: 0.30, timbre: tick),
                        .init(at: 0.15, hz: 1200, decay: 0.02, amp: 0.30, timbre: tick)]
            case .pasted:
                return [.init(at: 0, hz: 880, decay: 0.35, amp: 0.22, timbre: tick)]
            case .failed:
                return [.init(at: 0, hz: 330, decay: 0.25, amp: 0.30, timbre: tick)]
            }
        }
    }
}

enum SoundVolume: String, CaseIterable, Sendable {
    case quiet, normal

    var title: String {
        switch self {
        case .quiet: return "Quiet"
        case .normal: return "Normal"
        }
    }

    var gain: Float {
        switch self {
        case .quiet: return 0.45
        case .normal: return 1
        }
    }
}

/// Renders short decaying tones to 16-bit mono WAV. Pure, so it is unit tested.
enum ToneSynth {
    static let sampleRate = 44_100.0
    /// Linear fade-in that stops the start of each note clicking.
    static let attackSeconds = 0.006
    /// A note is rendered until it has decayed by this many time constants.
    static let tailConstants = 6.0

    struct Timbre: Sendable {
        /// (frequency ratio to the fundamental, relative amplitude).
        var partials: [(Double, Double)]
    }

    struct Note: Sendable {
        var at: Double
        var hz: Double
        /// Exponential decay time constant in seconds: how long the ring lasts.
        var decay: Double
        var amp: Double
        var timbre: Timbre

        init(at: Double, hz: Double, decay: Double, amp: Double, timbre: Timbre) {
            self.at = at; self.hz = hz; self.decay = decay; self.amp = amp; self.timbre = timbre
        }

        var end: Double { at + attackSeconds + decay * tailConstants }
    }

    static func render(_ notes: [Note]) -> [Float] {
        guard let last = notes.map(\.end).max() else { return [] }
        var samples = [Float](repeating: 0, count: Int(last * sampleRate))
        for note in notes {
            let start = Int(note.at * sampleRate)
            let end = min(samples.count, Int(note.end * sampleRate))
            let norm = note.timbre.partials.map(\.1).reduce(0, +)
            for i in start..<end {
                let t = Double(i - start) / sampleRate
                let attack = min(1, t / attackSeconds)
                let envelope = attack * exp(-t / note.decay)
                var value = 0.0
                for (ratio, weight) in note.timbre.partials {
                    // Higher partials fade faster, as they do on real bars and bells.
                    let partialDecay = exp(-t * (ratio - 1) / (note.decay * 2))
                    value += weight * partialDecay * sin(2 * .pi * note.hz * ratio * t)
                }
                samples[i] += Float(note.amp * envelope * value / norm)
            }
        }
        // Keep headroom whatever the notes do.
        let peak = samples.map(abs).max() ?? 0
        if peak > 0.9 { samples = samples.map { $0 * 0.9 / peak } }
        return samples
    }

    static func wav(_ samples: [Float]) -> Data {
        var pcm = Data(capacity: samples.count * 2)
        for s in samples {
            var v = Int16(max(-1, min(1, s)) * 32767).littleEndian
            pcm.append(Data(bytes: &v, count: 2))
        }
        var data = Data()
        func chunk(_ tag: String) { data.append(tag.data(using: .ascii)!) }
        func u32(_ v: UInt32) { var v = v.littleEndian; data.append(Data(bytes: &v, count: 4)) }
        func u16(_ v: UInt16) { var v = v.littleEndian; data.append(Data(bytes: &v, count: 2)) }
        chunk("RIFF"); u32(UInt32(36 + pcm.count)); chunk("WAVE")
        chunk("fmt "); u32(16); u16(1); u16(1); u32(UInt32(sampleRate)); u32(UInt32(sampleRate) * 2); u16(2); u16(16)
        chunk("data"); u32(UInt32(pcm.count)); data.append(pcm)
        return data
    }
}

@MainActor
enum Sounds {
    static func recordingStarted() { play(.recordingStarted) }
    static func recordingStopped() { play(.recordingStopped) }
    static func capApproaching() { play(.capApproaching) }
    static func pasted() { play(.pasted) }
    static func failed() { play(.failed) }

    /// Plays one cue from a theme regardless of the current setting.
    static func preview(_ cue: SoundCue, theme: SoundTheme) {
        play(cue, theme: theme)
    }

    private static var cache: [String: NSSound] = [:]

    private static func play(_ cue: SoundCue, theme: SoundTheme = Settings.soundTheme) {
        guard theme != .off, let sound = sound(for: cue, theme: theme) else { return }
        sound.stop()
        sound.volume = Settings.soundVolume.gain
        sound.play()
    }

    private static func sound(for cue: SoundCue, theme: SoundTheme) -> NSSound? {
        let key = "\(theme.rawValue).\(cue.rawValue)"
        if let cached = cache[key] { return cached }
        let sound: NSSound?
        if let name = theme.systemName(for: cue) {
            sound = NSSound(named: NSSound.Name(name))
        } else {
            sound = NSSound(data: ToneSynth.wav(ToneSynth.render(theme.notes(for: cue))))
        }
        cache[key] = sound
        return sound
    }
}
