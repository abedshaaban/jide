import Charts
import SwiftUI

/// Play / slow-play buttons for TTS.
struct SpeakButtons: View {
    var text: String
    var compact = false
    @ObservedObject private var speech = Speech.shared

    var body: some View {
        HStack(spacing: 12) {
            Button {
                speech.speak(text)
            } label: {
                Label("Play", systemImage: "speaker.wave.2.fill")
            }
            .accessibilityIdentifier("audio.play")
            Button {
                speech.speak(text, slow: true)
            } label: {
                Label("Slow", systemImage: "tortoise.fill")
            }
            .accessibilityIdentifier("audio.slow")
        }
        .labelStyle(compact ? AnyLabelStyle(.iconOnly) : AnyLabelStyle(ViewThatFitsLabelStyle()))
        .buttonStyle(.bordered)
    }
}

/// Icon + title, falling back to icon only when there is no room (large Dynamic Type, small phones).
struct ViewThatFitsLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        ViewThatFits(in: .horizontal) {
            Label(configuration).labelStyle(.titleAndIcon).lineLimit(1)
            Label(configuration).labelStyle(.iconOnly)
        }
    }
}

struct AnyLabelStyle: LabelStyle {
    private let make: (Configuration) -> AnyView
    init<S: LabelStyle>(_ s: S) { make = { AnyView(s.makeBody(configuration: $0)) } }
    func makeBody(configuration: Configuration) -> some View { make(configuration) }
}

/// Record own voice, play it, and compare with the TTS: audio back to back plus pitch contours.
struct PronunciationPractice: View {
    var word: Word
    @StateObject private var recorder = VoiceRecorder()
    @ObservedObject private var player = VoicePlayer.shared
    @ObservedObject private var speech = Speech.shared
    @State private var hasRecording = false
    @State private var ttsContour: [PitchAnalyzer.Point] = []
    @State private var myContour: [PitchAnalyzer.Point] = []
    @State private var analyzing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                recordButton
                Button {
                    VoicePlayer.shared.play(RecordingStore.url(for: word.id))
                } label: {
                    Label("Mine", systemImage: "person.wave.2.fill")
                }
                .disabled(!hasRecording || recorder.isRecording)
                .accessibilityIdentifier("audio.mine")
                Button {
                    compare()
                } label: {
                    Label("Compare", systemImage: "arrow.left.arrow.right")
                }
                .disabled(!hasRecording || recorder.isRecording)
                .accessibilityIdentifier("audio.compare")
            }
            .buttonStyle(.bordered)
            .labelStyle(ViewThatFitsLabelStyle())

            if recorder.isRecording {
                ProgressView(value: Double(recorder.level))
                    .tint(.red)
                Text("Recording… tap Stop when done").font(.caption).foregroundStyle(.secondary)
            }

            if !ttsContour.isEmpty || !myContour.isEmpty {
                PitchChart(reference: ttsContour, mine: myContour, syllables: word.syllables)
                    .frame(height: 150)
            } else if analyzing {
                ProgressView().frame(maxWidth: .infinity, minHeight: 60)
            }
            if recorder.permissionDenied {
                Text("Microphone access is off. Enable it in Settings › 记得.").font(.caption).foregroundStyle(.red)
            }
        }
        .onAppear(perform: refresh)
        .onChange(of: word.id) {
            recorder.stop()  // never keep recording into the previous word
            refresh()
        }
        .onDisappear { recorder.stop() }
    }

    private var recordButton: some View {
        Button {
            if recorder.isRecording {
                recorder.stop()
                refresh()
                VoicePlayer.shared.play(RecordingStore.url(for: word.id))
            } else {
                Task { await recorder.start(wordID: word.id) }
            }
        } label: {
            Label(recorder.isRecording ? "Stop" : "Record",
                  systemImage: recorder.isRecording ? "stop.circle.fill" : "mic.circle.fill")
        }
        .tint(.red)
        .accessibilityIdentifier("audio.record")
    }

    private func compare() {
        Speech.shared.speak(word.simplified) {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(250))
                VoicePlayer.shared.play(RecordingStore.url(for: word.id))
            }
        }
    }

    private func refresh() {
        hasRecording = RecordingStore.exists(word.id)
        let text = word.simplified
        let url = RecordingStore.url(for: word.id)
        let has = hasRecording
        guard has else {
            ttsContour = []
            myContour = []
            return
        }
        analyzing = true
        Task {
            let tts = await SpeechRenderer().render(text, slow: false)
            let ref = await Task.detached { PitchAnalyzer.contour(samples: tts.samples, sampleRate: tts.sampleRate) }.value
            var mine: [PitchAnalyzer.Point] = []
            if has {
                mine = await Task.detached { () -> [PitchAnalyzer.Point] in
                    guard let a = PitchAnalyzer.load(url) else { return [] }
                    return PitchAnalyzer.contour(samples: a.samples, sampleRate: a.sampleRate)
                }.value
            }
            ttsContour = ref
            myContour = mine
            analyzing = false
        }
    }
}

struct PitchChart: View {
    var reference: [PitchAnalyzer.Point]
    var mine: [PitchAnalyzer.Point]
    var syllables: [Pinyin.Syllable]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Chart {
                ForEach(reference) { p in
                    PointMark(x: .value("Time", p.time), y: .value("Pitch", p.semitones))
                        .symbolSize(12)
                        .foregroundStyle(by: .value("Voice", "Reference"))
                }
                ForEach(mine) { p in
                    PointMark(x: .value("Time", p.time), y: .value("Pitch", p.semitones))
                        .symbolSize(12)
                        .foregroundStyle(by: .value("Voice", "You"))
                }
            }
            .chartForegroundStyleScale(["Reference": Color.gray, "You": Color.accentColor])
            .chartXAxis(.hidden)
            .chartYAxis {
                AxisMarks(values: [-6, 0, 6]) { v in
                    AxisGridLine()
                    AxisValueLabel { Text(v.as(Int.self).map { $0 > 0 ? "+\($0)" : "\($0)" } ?? "") }
                }
            }
            .chartYScale(domain: -9...9)
            Text("Pitch shape in semitones, each voice relative to its own average.")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }
}
