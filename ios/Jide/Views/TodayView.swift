import SwiftData
import SwiftUI

struct TodayView: View {
    @Environment(\.modelContext) private var context
    @State private var counts = StudyQueue.Counts()
    @State private var stats = StatsSnapshot()
    @State private var studying: DeckScope?
    @Environment(\.dynamicTypeSize) private var typeSize

    /// Side by side normally, stacked at accessibility text sizes so words don't break mid-word.
    private var row: AnyLayout { typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 12)) : AnyLayout(HStackLayout(spacing: 12)) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    row {
                        StatTile(value: "\(stats.streak)", label: "day streak", systemImage: "flame.fill", tint: .orange)
                        StatTile(value: "\(stats.reviewedToday)", label: "reviewed today", systemImage: "checkmark.circle.fill",
                                 tint: .green)
                    }

                    VStack(spacing: 12) {
                        row {
                            CountPill(n: counts.new, label: "new", color: .blue)
                            CountPill(n: counts.learning, label: "learning", color: .orange)
                            CountPill(n: counts.review, label: "review", color: .green)
                        }
                        Button {
                            studying = .all
                        } label: {
                            Text(counts.total > 0 ? "Study now" : "All done for today")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(counts.total == 0)
                        .accessibilityIdentifier("today.study")
                    }
                    .padding()
                    .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemBackground)))

                    VStack(spacing: 0) {
                        NavigationLink { ToneQuizView() } label: {
                            PracticeRow(title: "Tone quiz", subtitle: "Hear a word, pick its tones", systemImage: "waveform")
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("today.toneQuiz")
                        Divider().padding(.leading, 52)
                        NavigationLink { WritingDrillView() } label: {
                            PracticeRow(title: "Writing drill", subtitle: "Write characters you have learned",
                                        systemImage: "pencil.and.scribble")
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("today.writingDrill")
                    }
                    .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemBackground)))

                    if !stats.leeches.isEmpty {
                        NavigationLink { LeechListView() } label: {
                            Label("\(stats.leeches.count) leeches need a mnemonic", systemImage: "ant.fill")
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding()
                                .background(RoundedRectangle(cornerRadius: 16).fill(Color.red.opacity(0.1)))
                        }
                    }
                }
                .padding()
                .readableWidth()
            }
            .navigationTitle("记得")
            .onAppear(perform: refresh)
            .fullScreenCover(item: $studying, onDismiss: refresh) { scope in
                ReviewView(scope: scope)
            }
        }
    }

    private func refresh() {
        counts = StudyQueue.counts(.all, context)
        stats = StatsBuilder.build(context)
    }
}

struct StatTile: View {
    var value: String
    var label: String
    var systemImage: String
    var tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: systemImage).foregroundStyle(tint)
            Text(value).font(.system(.largeTitle, design: .rounded).bold())
                .lineLimit(1).minimumScaleFactor(0.5)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemBackground)))
    }
}

struct CountPill: View {
    var n: Int
    var label: String
    var color: Color
    var body: some View {
        VStack {
            Text("\(n)").font(.title2.bold()).foregroundStyle(color)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

struct PracticeRow: View {
    var title: String
    var subtitle: String
    var systemImage: String
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage).font(.title3).frame(width: 26)
            VStack(alignment: .leading) {
                Text(title).font(.headline)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
        }
        .foregroundStyle(.primary)
        .padding()
    }
}
