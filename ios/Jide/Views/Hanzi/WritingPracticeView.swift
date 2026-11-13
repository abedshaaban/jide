import PencilKit
import SwiftUI

/// Writing practice with PencilKit. "Quiz" checks each stroke against the expected median;
/// "Trace" shows the outline and lets you draw freely.
struct WritingPracticeView: View {
    var character: Character
    var graphics: HanziGraphics

    enum Mode: String, CaseIterable { case quiz = "Quiz", trace = "Trace", free = "Blank" }
    @State private var mode: Mode = .quiz
    @State private var accepted = 0
    @State private var misses = 0
    @State private var totalMistakes = 0
    @State private var flashWrong = false
    @State private var canvasID = UUID()

    private var done: Bool { mode == .quiz && accepted >= graphics.strokes.count }

    var body: some View {
        VStack(spacing: 14) {
            Picker("Mode", selection: $mode) {
                ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .onChange(of: mode) { restart() }

            ZStack {
                HanziGrid()
                if mode == .trace {
                    ForEach(graphics.strokes.indices, id: \.self) { i in
                        GlyphShape(path: graphics.strokes[i]).fill(Color.secondary.opacity(0.18))
                    }
                }
                if mode == .quiz {
                    ForEach(0..<min(accepted, graphics.strokes.count), id: \.self) { i in
                        GlyphShape(path: graphics.strokes[i]).fill(Color.primary)
                    }
                    if !done && misses >= 3 {
                        GlyphShape(path: graphics.strokes[accepted]).fill(Color.accentColor.opacity(0.35))
                    }
                }
                PencilCanvas(mode: mode, graphics: graphics, accepted: $accepted, onStroke: handle)
                    .id(canvasID)
                if flashWrong {
                    RoundedRectangle(cornerRadius: 4).stroke(Color.red, lineWidth: 4)
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .background(Color(.secondarySystemBackground))

            HStack {
                if mode == .quiz {
                    if done {
                        Label(totalMistakes == 0 ? "Perfect!" : "Done · \(totalMistakes) mistakes",
                              systemImage: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                    } else {
                        Text("Stroke \(accepted + 1) of \(graphics.strokes.count)")
                            .foregroundStyle(.secondary)
                        if misses >= 3 { Text("· hint shown").foregroundStyle(.secondary) }
                    }
                }
                Spacer()
                Button("Restart", systemImage: "arrow.counterclockwise") { restart() }
                    .buttonStyle(.bordered)
            }
            .font(.subheadline)
        }
    }

    private func restart() {
        accepted = 0
        misses = 0
        totalMistakes = 0
        canvasID = UUID()
    }

    /// Returns true if the stroke should stay on the canvas.
    private func handle(_ points: [CGPoint]) -> Bool {
        guard mode == .quiz, !done else { return mode != .quiz }
        if StrokeMatcher.matches(points, graphics.medians[accepted]) {
            accepted += 1
            misses = 0
        } else {
            misses += 1
            totalMistakes += 1
            withAnimation(.easeOut(duration: 0.1)) { flashWrong = true }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(350))
                withAnimation { flashWrong = false }
            }
        }
        return false
    }
}

enum StrokeMatcher {
    static func resample(_ pts: [CGPoint], _ n: Int) -> [CGPoint] {
        guard pts.count > 1 else { return Array(repeating: pts.first ?? .zero, count: n) }
        var cum: [CGFloat] = [0]
        for (a, b) in zip(pts, pts.dropFirst()) { cum.append(cum.last! + hypot(b.x - a.x, b.y - a.y)) }
        let total = cum.last!
        guard total > 0 else { return Array(repeating: pts[0], count: n) }
        var out: [CGPoint] = []
        var j = 0
        for k in 0..<n {
            let d = total * CGFloat(k) / CGFloat(n - 1)
            while j < cum.count - 2 && cum[j + 1] < d { j += 1 }
            let seg = cum[j + 1] - cum[j]
            let t = seg > 0 ? (d - cum[j]) / seg : 0
            out.append(CGPoint(x: pts[j].x + (pts[j + 1].x - pts[j].x) * t, y: pts[j].y + (pts[j + 1].y - pts[j].y) * t))
        }
        return out
    }

    /// Both inputs in the 1024 glyph box (screen orientation).
    static func matches(_ drawn: [CGPoint], _ median: [CGPoint]) -> Bool {
        guard drawn.count >= 2, median.count >= 2 else { return false }
        let a = resample(drawn, 24), b = resample(median, 24)
        let avg = zip(a, b).map { hypot($0.x - $1.x, $0.y - $1.y) }.reduce(0, +) / 24
        let start = hypot(a[0].x - b[0].x, a[0].y - b[0].y)
        let end = hypot(a[23].x - b[23].x, a[23].y - b[23].y)
        let lenA = zip(a, a.dropFirst()).map { hypot($0.x - $1.x, $0.y - $1.y) }.reduce(0, +)
        let lenB = zip(b, b.dropFirst()).map { hypot($0.x - $1.x, $0.y - $1.y) }.reduce(0, +)
        let ratio = lenA / max(lenB, 1)
        return avg < 170 && start < 230 && end < 260 && ratio > 0.35 && ratio < 2.5
    }
}

struct PencilCanvas: UIViewRepresentable {
    var mode: WritingPracticeView.Mode
    var graphics: HanziGraphics
    @Binding var accepted: Int
    /// Called with the stroke in glyph coordinates; return false to erase it.
    var onStroke: ([CGPoint]) -> Bool

    func makeUIView(context: Context) -> PKCanvasView {
        let v = PKCanvasView()
        v.drawingPolicy = .anyInput
        v.backgroundColor = .clear
        v.isOpaque = false
        v.tool = PKInkingTool(.pen, color: .label, width: 14)
        v.delegate = context.coordinator
        return v
    }

    func updateUIView(_ v: PKCanvasView, context: Context) {
        context.coordinator.parent = self
        let width: CGFloat = mode == .quiz ? 18 : 14
        v.tool = PKInkingTool(.pen, color: .label, width: width)
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        var parent: PencilCanvas
        private var count = 0
        private var updating = false
        init(_ p: PencilCanvas) { parent = p }

        func canvasViewDrawingDidChange(_ canvas: PKCanvasView) {
            guard !updating else { return }
            let strokes = canvas.drawing.strokes
            defer { count = canvas.drawing.strokes.count }
            guard strokes.count > count, let last = strokes.last else { return }
            let scale = 1024 / max(canvas.bounds.width, 1)
            let pts = last.path.map { CGPoint(x: $0.location.x * scale, y: $0.location.y * scale) }
            let keep = parent.onStroke(pts)
            if !keep {
                updating = true
                canvas.drawing = PKDrawing(strokes: Array(strokes.dropLast()))
                updating = false
            }
        }
    }
}
