import AVFoundation
import os

/// Captures the default input device with AVAudioEngine and accumulates
/// mono Float32 samples at the device's native sample rate.
///
/// `start`/`stop` are called from the main actor; the tap callback runs on a
/// real-time audio thread, so shared state is guarded by a lock.
final class AudioRecorder: @unchecked Sendable {
    struct Recording: Sendable {
        let samples: [Float]
        let sampleRate: Double
        var duration: TimeInterval { Double(samples.count) / sampleRate }
    }

    private let logger = Logger(subsystem: "talkie", category: "audio")
    private let engine = AVAudioEngine()
    private let lock = NSLock()
    private var samples: [Float] = []
    private var sampleRate: Double = 0
    private var peak: Float = 0
    private(set) var isRecording = false

    /// Peak level of the most recent buffer, 0...1. Read from the UI for a meter.
    var level: Float { lock.withLock { peak } }

    /// Seconds captured so far in the current recording.
    var duration: TimeInterval {
        lock.withLock { sampleRate > 0 ? Double(samples.count) / sampleRate : 0 }
    }

    static func requestPermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .audio)
        default: return false
        }
    }

    func start() throws {
        guard !isRecording else { return }
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw TalkieError.audio("No input device available")
        }
        lock.withLock {
            samples.removeAll(keepingCapacity: true)
            samples.reserveCapacity(Int(format.sampleRate * 30))
            sampleRate = format.sampleRate
            peak = 0
        }
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            self?.append(buffer)
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw error
        }
        isRecording = true
        logger.info("Recording at \(format.sampleRate) Hz, \(format.channelCount) ch")
    }

    func stop() -> Recording {
        guard isRecording else { return Recording(samples: [], sampleRate: 16_000) }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRecording = false
        return lock.withLock {
            peak = 0
            return Recording(samples: samples, sampleRate: sampleRate)
        }
    }

    private func append(_ buffer: AVAudioPCMBuffer) {
        guard let channels = buffer.floatChannelData else { return }
        let frames = Int(buffer.frameLength)
        let mono = UnsafeBufferPointer(start: channels[0], count: frames)
        var bufferPeak: Float = 0
        for sample in mono { bufferPeak = max(bufferPeak, abs(sample)) }
        lock.withLock {
            samples.append(contentsOf: mono)
            peak = bufferPeak
        }
    }
}
