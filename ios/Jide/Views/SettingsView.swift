import AVFoundation
import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @AppStorage(SettingsKey.newPerDay) private var newPerDay = 15
    @AppStorage(SettingsKey.autoPlayAudio) private var autoPlay = true
    @AppStorage(SettingsKey.slowRate) private var slowRate = 0.3
    @AppStorage(SettingsKey.voiceIdentifier) private var voiceID = ""
    @AppStorage(SettingsKey.desiredRetention) private var retention = 0.9
    @AppStorage(SettingsKey.leechThreshold) private var leechThreshold = 8
    @AppStorage(SettingsKey.suspendLeeches) private var suspendLeeches = false
    @AppStorage(SettingsKey.teachComponents) private var teachComponents = true
    @AppStorage(SettingsKey.reminderEnabled) private var reminderOn = false
    @AppStorage(SettingsKey.reminderHour) private var reminderHour = 19
    @AppStorage(SettingsKey.reminderMinute) private var reminderMinute = 0
    @State private var directions = AppSettings.enabledDirections
    @State private var exportDoc: BackupDocument?
    @State private var showExporter = false
    @State private var showImporter = false
    @State private var pendingImport: Data?
    @State private var message: String?
    @State private var reminderDenied = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Study") {
                    Stepper("New cards per day: \(newPerDay)", value: $newPerDay, in: 0...100, step: 5)
                        .accessibilityIdentifier("settings.newPerDay")
                    ForEach(Direction.allCases) { d in
                        Toggle(d.label, isOn: Binding(
                            get: { directions.contains(d) },
                            set: { on in
                                if on { directions.insert(d) } else if directions.count > 1 { directions.remove(d) }
                                AppSettings.enabledDirections = directions
                            }))
                    }
                    VStack(alignment: .leading) {
                        Text("Target retention: \(Int(retention * 100))%")
                        Slider(value: $retention, in: 0.8...0.97, step: 0.01)
                    }
                    Stepper("Leech after \(leechThreshold) lapses", value: $leechThreshold, in: 3...20)
                    Toggle("Suspend leeches", isOn: $suspendLeeches)
                    Toggle("Teach character parts before words", isOn: $teachComponents)
                        .accessibilityIdentifier("settings.teachComponents")
                }

                Section {
                    Toggle("Play audio when revealing", isOn: $autoPlay)
                    Picker("Voice", selection: $voiceID) {
                        Text("Best installed").tag("")
                        ForEach(Speech.chineseVoices, id: \.identifier) { v in
                            Text("\(v.name) · \(Speech.qualityLabel(v))").tag(v.identifier)
                        }
                    }
                    VStack(alignment: .leading) {
                        Text("Slow speed: \(Int(slowRate / Double(AVSpeechUtteranceDefaultSpeechRate) * 100))% of normal")
                        Slider(value: $slowRate, in: 0.1...0.45, step: 0.05)
                    }
                    HStack {
                        Button("Test") { Speech.shared.speak("你好，我在学中文。") }
                            .accessibilityIdentifier("settings.testVoice")
                        Button("Test slow") { Speech.shared.speak("你好，我在学中文。", slow: true) }
                    }
                    .buttonStyle(.bordered)
                } header: {
                    Text("Audio")
                } footer: {
                    Text("Using: \(Speech.voice.map { "\($0.name) (\(Speech.qualityLabel($0)))" } ?? "none"). "
                         + "Download more in iOS Settings › Accessibility › Spoken Content › Voices › Chinese (China mainland).")
                }

                Section("Reminder") {
                    Toggle("Daily reminder", isOn: $reminderOn)
                        .accessibilityIdentifier("settings.reminder")
                        .onChange(of: reminderOn) { _, on in
                            Task {
                                if on {
                                    if await Reminders.requestPermission() { Reminders.refresh() }
                                    else { reminderOn = false; reminderDenied = true }
                                } else {
                                    Reminders.cancel()
                                }
                            }
                        }
                    if reminderOn {
                        DatePicker("Time", selection: reminderTime, displayedComponents: .hourAndMinute)
                    }
                    Text(reminderOn ? "Reminder set for \(reminderTimeText)." : "")
                        .font(.caption).foregroundStyle(.secondary)
                        .accessibilityIdentifier("settings.reminderStatus")
                    if reminderDenied {
                        Text("Notifications are off for 记得. Turn them on in iOS Settings.").font(.caption).foregroundStyle(.red)
                    }
                }

                Section {
                    Button("Export backup…", systemImage: "square.and.arrow.up") { export() }
                        .accessibilityIdentifier("settings.export")
                    Button("Import backup…", systemImage: "square.and.arrow.down") { showImporter = true }
                        .accessibilityIdentifier("settings.import")
                } header: {
                    Text("Backup")
                } footer: {
                    Text("One JSON file with progress, review history, notes, custom words, decks, settings and recordings. "
                         + "Save it to Files (On My iPhone or a folder synced to your Mac). Importing merges; the file wins.")
                }

                Section("About") {
                    LabeledContent("Words", value: "\(Library.shared.words.count) (data v\(Library.shared.dataVersion))")
                    Text("Word list: Wiktionary (CC BY-SA). Dictionary: CC-CEDICT (CC BY-SA). Sentences: Tatoeba (CC BY). "
                         + "Characters: Make Me a Hanzi (LGPL / Arphic PL). HSK levels: complete-hsk-vocabulary (MIT).")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .fileExporter(isPresented: $showExporter, document: exportDoc, contentType: .json,
                          defaultFilename: "jide-backup-\(Date().formatted(.iso8601.year().month().day()))") { result in
                switch result {
                case .failure(let e):
                    // Cancelling the picker is not an error worth an alert.
                    if (e as NSError).code != NSUserCancelledError { message = e.localizedDescription }
                case .success:
                    message = "Backup saved."
                }
            }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
                switch result {
                case .success(let url):
                    let ok = url.startAccessingSecurityScopedResource()
                    defer { if ok { url.stopAccessingSecurityScopedResource() } }
                    do { pendingImport = try Data(contentsOf: url) } catch { message = error.localizedDescription }
                case .failure(let e):
                    message = e.localizedDescription
                }
            }
            .confirmationDialog("Import this backup? Cards, notes and recordings in the file replace the ones on this phone.",
                                isPresented: Binding(get: { pendingImport != nil }, set: { if !$0 { pendingImport = nil } }),
                                titleVisibility: .visible) {
                Button("Import") {
                    guard let data = pendingImport else { return }
                    pendingImport = nil
                    do {
                        message = try BackupService.importBackup(data, into: context).text
                        directions = AppSettings.enabledDirections
                    } catch {
                        message = "Import failed: \(error.localizedDescription)"
                    }
                }
            }
            .alert(message ?? "", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("OK", role: .cancel) {}
            }
        }
    }

    private var reminderTimeText: String {
        let d = Calendar.current.date(from: DateComponents(hour: reminderHour, minute: reminderMinute)) ?? Date()
        return d.formatted(date: .omitted, time: .shortened)
    }

    private var reminderTime: Binding<Date> {
        Binding(
            get: { Calendar.current.date(from: DateComponents(hour: reminderHour, minute: reminderMinute)) ?? Date() },
            set: { d in
                let c = Calendar.current.dateComponents([.hour, .minute], from: d)
                reminderHour = c.hour ?? 19
                reminderMinute = c.minute ?? 0
                Reminders.refresh()
            })
    }

    private func export() {
        do {
            exportDoc = BackupDocument(data: try BackupService.export(context))
            showExporter = true
        } catch {
            message = "Export failed: \(error.localizedDescription)"
        }
    }
}
