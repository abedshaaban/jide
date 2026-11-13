import AVFoundation
import Foundation

/// Shared audio session setup: play TTS and recordings, record from the mic.
enum AudioSessionConfig {
    static func activate() {
        let s = AVAudioSession.sharedInstance()
        try? s.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothA2DP])
        try? s.setActive(true)
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
        let id = UserDefaults.standard.string(forKey: SettingsKey.voiceIdentifier) ?? ""
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
        AudioSessionConfig.activate()
        VoicePlayer.shared.stop()
        if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }
        onFinish = then
        synth.speak(Speech.utterance(text, slow: slow))
    }

    func stop() {
        onFinish = nil
        synth.stopSpeaking(at: .immediate)
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
final class SpeechRenderer {
    private let synth = AVSpeechSynthesizer()
    private var samples: [Float] = []
    private var sampleRate: Double = 22050
    private var done = false

    func render(_ text: String, slow: Bool) async -> (samples: [Float], sampleRate: Double) {
        let utterance = Speech.utterance(text, slow: slow)
        return await withCheckedContinuation { cont in
            synth.write(utterance) { [self] buffer in
                guard !done else { return }
                guard let pcm = buffer as? AVAudioPCMBuffer, pcm.frameLength > 0 else {
                    done = true
                    cont.resume(returning: (samples, sampleRate))
                    return
                }
                sampleRate = pcm.format.sampleRate
                samples.append(contentsOf: PitchAnalyzer.monoFloats(pcm))
            }
        }
    }
}
