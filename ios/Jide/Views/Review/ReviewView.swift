import Combine
import SwiftData
import SwiftUI

struct ReviewView: View {
    let scope: DeckScope
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var session: StudySession?

    var body: some View {
        NavigationStack {
            Group {
                if let session {
                    ReviewSessionView(session: session)
                } else {
                    ProgressView()
                }
            }
            .navigationTitle(scope.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        Speech.shared.stop()
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            if session == nil { session = StudySession(scope: scope, context: context) }
        }
    }
}

struct ReviewSessionView: View {
    @ObservedObject var session: StudySession
    @State private var revealed = false
    @State private var showDetails = false
    @State private var now = Date()
    @AppStorage(SettingsKey.autoPlayAudio) private var autoPlay = true
    private let timer = Timer.publish(every: 5, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            if let card = session.current, let word = card.word {
                HStack {
                    Text(card.direction.label).font(.caption).foregroundStyle(.secondary)
                    if card.isLeech { Image(systemName: "ant.fill").foregroundStyle(.red).font(.caption) }
                    Spacer()
                    Text("\(session.remaining) left · \(session.reviewedCount) done").font(.caption).foregroundStyle(.secondary)
                }
                .padding(.horizontal)
                .padding(.top, 8)

                ScrollView {
                    VStack(spacing: 20) {
                        CardFront(card: card, word: word, revealed: revealed)
                        if revealed {
                            Divider()
                            CardBack(card: card, word: word)
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                }
                .contentShape(Rectangle())
                .onTapGesture { if !revealed { reveal(word) } }

                bottomBar(word)
                    .sheet(isPresented: $showDetails) {
                        NavigationStack { WordDetailView(word: word) }
                    }
            } else if let until = session.waitingUntil {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "hourglass").font(.largeTitle)
                    Text("Next learning card in \(formatInterval(from: now, to: until))")
                    Button("Study it now") { session.continueNow() }.buttonStyle(.bordered)
                }
                Spacer()
            } else {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.seal.fill").font(.system(size: 56)).foregroundStyle(.green)
                    Text("Session complete").font(.title2.bold())
                    Text("\(session.reviewedCount) reviews").foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
        .onReceive(timer) { t in
            now = t
            if session.current == nil, let u = session.waitingUntil, u <= t { session.advance() }
        }
        .onChange(of: session.current?.id) { _, _ in
            revealed = false
            if let c = session.current, let w = c.word, c.direction == .audioToHanzi { Speech.shared.speak(w.simplified) }
        }
        .onAppear {
            if let c = session.current, let w = c.word, c.direction == .audioToHanzi { Speech.shared.speak(w.simplified) }
        }
        .alert("Leech", isPresented: Binding(get: { session.leechAlert != nil }, set: { if !$0 { session.leechAlert = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("\(session.leechAlert?.simplified ?? "") keeps slipping. Add a mnemonic or note to anchor it."
                 + (AppSettings.suspendLeeches ? " It has been suspended." : ""))
        }
    }

    @ViewBuilder private func bottomBar(_ word: Word) -> some View {
        VStack(spacing: 8) {
            if revealed {
                let preview = session.preview()
                HStack(spacing: 8) {
                    ForEach(Rating.allCases) { r in
                        Button {
                            Speech.shared.stop()
                            session.rate(r)
                        } label: {
                            VStack(spacing: 2) {
                                Text(r.label).font(.subheadline.bold())
                                if let p = preview[r] {
                                    Text(formatInterval(from: Date(), to: p.due)).font(.caption2)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(color(r))
                    }
                }
                Button("Details, notes & writing") { showDetails = true }
                    .font(.footnote)
            } else {
                Button {
                    reveal(word)
                } label: {
                    Text("Show answer").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .background(.bar)
    }

    private func reveal(_ word: Word) {
        revealed = true
        if autoPlay && session.current?.direction != .audioToHanzi { Speech.shared.speak(word.simplified) }
    }

    private func color(_ r: Rating) -> Color {
        switch r {
        case .again: .red
        case .hard: .orange
        case .good: .green
        case .easy: .blue
        }
    }
}

struct CardFront: View {
    var card: Card
    var word: Word
    var revealed: Bool

    var body: some View {
        VStack(spacing: 12) {
            switch card.direction {
            case .hanziToMeaning:
                HanziText(hanzi: word.simplified, numbered: word.pinyinNumbered, size: 80, colored: revealed)
                    .padding(.top, 30)
            case .meaningToHanzi:
                Text(word.shortMeaning)
                    .font(.title2)
                    .multilineTextAlignment(.center)
                    .padding(.top, 30)
                if revealed {
                    HanziText(hanzi: word.simplified, numbered: word.pinyinNumbered, size: 80)
                }
            case .audioToHanzi:
                SpeakButtons(text: word.simplified)
                    .padding(.top, 30)
                if revealed {
                    HanziText(hanzi: word.simplified, numbered: word.pinyinNumbered, size: 80)
                }
            }
        }
    }
}

struct CardBack: View {
    var card: Card
    var word: Word

    var body: some View {
        VStack(spacing: 14) {
            PinyinText(numbered: word.pinyinNumbered, font: .title)
            if word.traditional != word.simplified {
                Text("Traditional: \(word.traditional)").font(.subheadline).foregroundStyle(.secondary)
            }
            if card.direction != .meaningToHanzi {
                Text(word.shortMeaning).font(.title3).multilineTextAlignment(.center)
            }
            SpeakButtons(text: word.simplified, compact: true)

            if !word.mnemonic.isEmpty || !word.note.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    if !word.mnemonic.isEmpty { Label(word.mnemonic, systemImage: "lightbulb.fill") }
                    if !word.note.isEmpty { Label(word.note, systemImage: "note.text") }
                }
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.yellow.opacity(0.12)))
            }

            GroupBox("Your pronunciation") {
                PronunciationPractice(word: word)
            }

            if let s = (word.isCustom ? [] : Library.shared.sentences(for: word.simplified)).first {
                SentenceRow(sentence: s)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

struct SentenceRow: View {
    var sentence: Sentence
    var body: some View {
        Button {
            Speech.shared.speak(sentence.zh)
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(sentence.zh).font(.title3).foregroundStyle(.primary)
                MarkedPinyinText(text: sentence.pinyin, font: .caption)
                Text(sentence.en).font(.caption).foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.leading)
        }
        .buttonStyle(.plain)
    }
}
