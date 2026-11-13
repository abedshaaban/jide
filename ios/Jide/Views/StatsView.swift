import Charts
import SwiftData
import SwiftUI

struct StatsView: View {
    @Environment(\.modelContext) private var context
    @State private var s = StatsSnapshot()

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 12) {
                        StatTile(value: "\(s.streak)", label: "day streak", systemImage: "flame.fill", tint: .orange)
                        StatTile(value: "\(s.longestStreak)", label: "longest", systemImage: "trophy.fill", tint: .yellow)
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }
                Section("Today") {
                    LabeledContent("Reviews today", value: "\(s.reviewedToday)")
                    LabeledContent("Total reviews", value: "\(s.totalReviews)")
                    LabeledContent("Retention (30 days)",
                                   value: s.retention30.map { String(format: "%.0f%%", $0 * 100) } ?? "—")
                }
                Section("Reviews, last 30 days") {
                    Chart(s.last30) { d in
                        BarMark(x: .value("Day", d.day, unit: .day), y: .value("Reviews", d.count))
                            .foregroundStyle(Color.accentColor)
                    }
                    .chartXAxis { AxisMarks(values: .stride(by: .day, count: 7)) { _ in
                        AxisGridLine(); AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                    } }
                    .frame(height: 160)
                }
                Section("Due, next 14 days") {
                    Chart(s.forecast) { d in
                        BarMark(x: .value("Day", d.day, unit: .day), y: .value("Due", d.count))
                            .foregroundStyle(Color.green)
                    }
                    .chartXAxis { AxisMarks(values: .stride(by: .day, count: 3)) { _ in
                        AxisGridLine(); AxisValueLabel(format: .dateTime.weekday(.abbreviated))
                    } }
                    .frame(height: 140)
                }
                Section("Cards") {
                    LabeledContent("Words started", value: "\(s.wordsStarted)")
                    LabeledContent("New (enabled directions)", value: "\(s.newCards)")
                    LabeledContent("Learning", value: "\(s.learningCards)")
                    LabeledContent("Review", value: "\(s.reviewCards)")
                    LabeledContent("Mature (stability ≥ 21d)", value: "\(s.matureCards)")
                    LabeledContent("Suspended", value: "\(s.suspendedCards)")
                }
                Section("Leeches") {
                    if s.leeches.isEmpty {
                        Text("None. Cards forgotten \(AppSettings.leechThreshold)+ times show up here.")
                            .foregroundStyle(.secondary)
                    } else {
                        NavigationLink("\(s.leeches.count) leeches") { LeechListView() }
                    }
                }
            }
            .navigationTitle("Stats")
            .onAppear { s = StatsBuilder.build(context) }
            .refreshable { s = StatsBuilder.build(context) }
        }
    }
}
