import AVFoundation
import Foundation

/// Where the owner's recordings live: Documents/Recordings/<hex(wordID)>.m4a (visible in the Files app).
enum RecordingStore {
    /// Parent of the Recordings folder. Tests point this somewhere else.
    static var baseDirectory: URL = URL.documentsDirectory

    static var directory: URL {
        let dir = baseDirectory.appending(path: "Recordings", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func fileName(for wordID: String) -> String {
        Data(wordID.utf8).map { String(format: "%02x", $0) }.joined() + ".m4a"
    }

    static func wordID(fromFileName name: String) -> String? {
        let hex = name.replacingOccurrences(of: ".m4a", with: "")
        guard hex.count % 2 == 0 else { return nil }
        var bytes = [UInt8]()
        var i = hex.startIndex
        while i < hex.endIndex {
            let j = hex.index(i, offsetBy: 2)
            guard let b = UInt8(hex[i..<j], radix: 16) else { return nil }
            bytes.append(b)
            i = j
        }
        return String(bytes: bytes, encoding: .utf8)
    }

    static func url(for wordID: String) -> URL { directory.appending(path: fileName(for: wordID)) }
    static func exists(_ wordID: String) -> Bool { FileManager.default.fileExists(atPath: url(for: wordID).path) }
    static func delete(_ wordID: String) { try? FileManager.default.removeItem(at: url(for: wordID)) }

    /// Deletes recordings whose word no longer exists. Returns how many were removed.
    @discardableResult
    static func pruneOrphans(keeping wordIDs: Set<String>) -> Int {
        var removed = 0
        for r in all() where !wordIDs.contains(r.wordID) {
            try? FileManager.default.removeItem(at: r.url)
            removed += 1
        }
        return removed
    }

    static func all() -> [(wordID: String, url: URL)] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files.compactMap { u in wordID(fromFileName: u.lastPathComponent).map { ($0, u) } }
    }
}

@MainActor
final class VoicePlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
    static let shared = VoicePlayer()
    private var player: AVAudioPlayer?
    @Published private(set) var isPlaying = false

    func play(_ url: URL) {
        AudioCoordinator.takeOver(for: .playback)
        AudioSessionConfig.activate()
        player = try? AVAudioPlayer(contentsOf: url)
        player?.delegate = self
        player?.volume = 1
        isPlaying = player?.play() ?? false
    }

    func stop() {
        player?.stop()
        isPlaying = false
    }

    nonisolated func audioPlayerDidFinishPlaying(_ p: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.isPlaying = false }
    }
}

/// Records one take per word, replacing the previous one.
@MainActor
final class VoiceRecorder: NSObject, ObservableObject, AVAudioRecorderDelegate {
    /// The recorder that is currently recording, so TTS/playback can stop it first.
    static weak var current: VoiceRecorder?

    @Published private(set) var isRecording = false
    @Published private(set) var level: Float = 0
    @Published var permissionDenied = false
    private var recorder: AVAudioRecorder?
    private var target: URL?
    private var meterTimer: Timer?

    func start(wordID: String) async {
        guard !isRecording else { return }
        let granted = await AVAudioApplication.requestRecordPermission()
        guard granted else { permissionDenied = true; return }
        AudioCoordinator.takeOver(for: .recording)
        AudioSessionConfig.activate()
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]
        do {
            // Record to a temp file and move it into place on success, so a failed or interrupted take
            // never replaces the previous good recording.
            let temp = FileManager.default.temporaryDirectory.appending(path: "take-\(UUID().uuidString).m4a")
            let r = try AVAudioRecorder(url: temp, settings: settings)
            r.isMeteringEnabled = true
            r.delegate = self
            guard r.record() else { return }
            recorder = r
            target = RecordingStore.url(for: wordID)
            VoiceRecorder.current = self
            isRecording = true
            meterTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self, let r = self.recorder else { return }
                    r.updateMeters()
                    self.level = max(0, (r.averagePower(forChannel: 0) + 50) / 50)
                }
            }
        } catch {
            isRecording = false
        }
    }

    /// Stops and keeps the take if it has audio. Safe to call when not recording.
    func stop() {
        guard let r = recorder else { return }
        let duration = r.currentTime
        r.stop()
        recorder = nil
        if let target, duration > 0.2 {
            try? FileManager.default.removeItem(at: target)
            try? FileManager.default.moveItem(at: r.url, to: target)
        } else {
            try? FileManager.default.removeItem(at: r.url)
        }
        target = nil
        if VoiceRecorder.current === self { VoiceRecorder.current = nil }
        meterTimer?.invalidate()
        meterTimer = nil
        isRecording = false
        level = 0
    }

    nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        Task { @MainActor in self.stop() }
    }
}
