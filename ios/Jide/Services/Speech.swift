import AVFoundation
import Foundation

/// One audio session for TTS, recording and playback. Only one of them runs at a time:
/// starting any of them stops the others (see `AudioCoordinator.takeOver`).
enum AudioSessionConfig {
    private static var observers: [NSObjectProtocol] = []

    static func activate() {
        let s = AVAudioSession.sharedInstance()
        if s.category != .playAndRecord {
            try? s.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothA2DP])
        }
        try? s.setActive(true)
    }

    /// Stops everything on interruptions (calls, Siri) and when headphones are unplugged,
    /// so nothing suddenly plays from the speaker and a recording never keeps running silently.
    @MainActor
    static func startObserving() {
        guard observers.isEmpty else { return }
        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { n in
            let raw = n.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            guard raw.flatMap(AVAudioSession.InterruptionType.init) == .began else { return }
            MainActor.assumeIsolated { AudioCoordinator.stopAll() }
        })
        observers.append(nc.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { n in
            let raw = n.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            guard raw.flatMap(AVAudioSession.RouteChangeReason.init) == .oldDeviceUnavailable else { return }
            MainActor.assumeIsolated {
                Speech.shared.stop()
                VoicePlayer.shared.stop()
            }
        })
        observers.append(nc.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil,
                                        queue: .main) { _ in
            MainActor.assumeIsolated { AudioCoordinator.stopAll() }
        })
    }
}

@MainActor
enum AudioCoordinator {
    enum Source { case speech, playback, recording }

    /// Stops whatever else is using audio before `source` starts.
    static func takeOver(for source: Source) {
        if source != .recording { VoiceRecorder.current?.stop() }
        if source != .speech { Speech.shared.stop() }
        if source != .playback { VoicePlayer.shared.stop() }
    }

    static func stopAll() {
        VoiceRecorder.current?.stop()
        Speech.shared.stop()
        VoicePlayer.shared.stop()
    }
}

/// Text to speech through AVSpeechSynthesizer, zh-CN, preferring premium/enhanced voices.
@MainActor
final class Speech: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    static let shared = Speech()

    private let synth = AVSpeechSynthesizer()
    private var onFinish: (() -> Void)?
    @Published private(set) var isSpeaking = false

    override init() {
        super.init()
        synth.delegate = self
    }

    nonisolated static var chineseVoices: [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language == "zh-CN" }
            .sorted { ($0.quality.rawValue, $0.name) > ($1.quality.rawValue, $1.name) }
    }

    /// The chosen voice, else the best installed zh-CN voice.
    nonisolated static var voice: AVSpeechSynthesisVoice? {
        let id = AppSettings.defaults.string(forKey: SettingsKey.voiceIdentifier) ?? ""
        if !id.isEmpty, let v = AVSpeechSynthesisVoice(identifier: id) { return v }
        return chineseVoices.first ?? AVSpeechSynthesisVoice(language: "zh-CN")
    }

    nonisolated static func qualityLabel(_ v: AVSpeechSynthesisVoice) -> String {
        switch v.quality {
        case .premium: "Premium"
        case .enhanced: "Enhanced"
        default: "Default"
        }
    }

    nonisolated static func utterance(_ text: String, slow: Bool) -> AVSpeechUtterance {
        let u = AVSpeechUtterance(string: text)
        u.voice = voice
        u.rate = slow ? AppSettings.slowRate : AVSpeechUtteranceDefaultSpeechRate
        u.preUtteranceDelay = 0
        return u
    }

    func speak(_ text: String, slow: Bool = false, then: (() -> Void)? = nil) {
        AudioCoordinator.takeOver(for: .speech)
        AudioSessionConfig.activate()
        if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }
        onFinish = then
        synth.speak(Speech.utterance(text, slow: slow))
    }

    func stop() {
        onFinish = nil
        if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }
        isSpeaking = false
    }

    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        Task { @MainActor in self.isSpeaking = true }
    }

    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.isSpeaking = false
            let f = self.onFinish
            self.onFinish = nil
            f?()
        }
    }

    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.isSpeaking = false }
    }
}

/// Renders TTS to PCM samples so its pitch can be drawn next to the owner's recording.
final class SpeechRenderer: @unchecked Sendable {
    private let synth = AVSpeechSynthesizer()
    private let lock = NSLock()
    private var samples: [Float] = []
    private var sampleRate: Double = 22050
    private var continuation: CheckedContinuation<(samples: [Float], sampleRate: Double), Never>?

    /// Returns what was rendered; gives up after `timeout` if the synthesizer never signals the end.
    func render(_ text: String, slow: Bool, timeout: TimeInterval = 8) async -> (samples: [Float], sampleRate: Double) {
        let utterance = Speech.utterance(text, slow: slow)
        return await withCheckedContinuation { cont in
            lock.withLock { continuation = cont }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { [self] in finish() }
            synth.write(utterance) { [self] buffer in
                guard let pcm = buffer as? AVAudioPCMBuffer, pcm.frameLength > 0 else { return finish() }
                let floats = PitchAnalyzer.monoFloats(pcm)
                lock.withLock {
                    sampleRate = pcm.format.sampleRate
                    samples.append(contentsOf: floats)
                }
            }
        }
    }

    private func finish() {
        let (cont, result): (CheckedContinuation<(samples: [Float], sampleRate: Double), Never>?, ([Float], Double)) =
            lock.withLock {
                let c = continuation
                continuation = nil
                return (c, (samples, sampleRate))
            }
        cont?.resume(returning: (samples: result.0, sampleRate: result.1))
    }
}
