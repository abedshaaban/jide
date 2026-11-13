import SwiftUI

/// Make Me a Hanzi stroke data in a 1024 box with y up; screen y = 900 - y.
struct HanziGraphics {
    var strokes: [Path]
    var medians: [[CGPoint]]

    init?(_ info: CharacterInfo?) {
        guard let info, let s = info.strokes, let m = info.medians, !s.isEmpty else { return nil }
        strokes = s.map(HanziGraphics.parse)
        medians = m.map { $0.compactMap { p in p.count == 2 ? CGPoint(x: p[0], y: 900 - p[1]) : nil } }
    }

    static func parse(_ d: String) -> Path {
        var path = Path()
        let tokens = d.split(separator: " ").map(String.init)
        var i = 0
        var cmd = "M"
        func num() -> CGFloat {
            defer { i += 1 }
            return i < tokens.count ? CGFloat(Double(tokens[i]) ?? 0) : 0
        }
        func pt() -> CGPoint {
            let x = num(), y = num()
            return CGPoint(x: x, y: 900 - y)
        }
        while i < tokens.count {
            if let f = tokens[i].first, f.isLetter {
                cmd = tokens[i]
                i += 1
                if cmd == "Z" || cmd == "z" { path.closeSubpath(); continue }
            }
            switch cmd {
            case "M": path.move(to: pt()); cmd = "L"
            case "L": path.addLine(to: pt())
            case "Q": let c = pt(); path.addQuadCurve(to: pt(), control: c)
            case "C": let c1 = pt(); let c2 = pt(); path.addCurve(to: pt(), control1: c1, control2: c2)
            default: i += 1
            }
        }
        return path
    }
}

/// Scales a path from the 1024 box into the given rect.
struct GlyphShape: Shape {
    var path: Path
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 1024
        return path.applying(CGAffineTransform(scaleX: s, y: s))
    }
}

struct MedianShape: Shape {
    var points: [CGPoint]
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 1024
        var p = Path()
        guard let first = points.first else { return p }
        p.move(to: CGPoint(x: first.x * s, y: first.y * s))
        for q in points.dropFirst() { p.addLine(to: CGPoint(x: q.x * s, y: q.y * s)) }
        return p
    }
}

/// 米字格 practice grid.
struct HanziGrid: View {
    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            Path { p in
                p.move(to: .init(x: 0, y: h / 2)); p.addLine(to: .init(x: w, y: h / 2))
                p.move(to: .init(x: w / 2, y: 0)); p.addLine(to: .init(x: w / 2, y: h))
                p.move(to: .zero); p.addLine(to: .init(x: w, y: h))
                p.move(to: .init(x: w, y: 0)); p.addLine(to: .init(x: 0, y: h))
            }
            .stroke(Color.secondary.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [5, 5]))
            Rectangle().stroke(Color.secondary.opacity(0.4), lineWidth: 1)
        }
    }
}

/// Animated stroke order for one character.
struct StrokeOrderView: View {
    var graphics: HanziGraphics
    @State private var completed = 0
    @State private var progress: CGFloat = 0
    @State private var animating: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                HanziGrid()
                ForEach(graphics.strokes.indices, id: \.self) { i in
                    GlyphShape(path: graphics.strokes[i])
                        .fill(i < completed ? Color.primary : Color.secondary.opacity(0.18))
                }
                if completed < graphics.strokes.count {
                    GeometryReader { g in
                        let scale = min(g.size.width, g.size.height) / 1024
                        MedianShape(points: graphics.medians[completed])
                            .trim(from: 0, to: progress)
                            .stroke(Color.accentColor,
                                    style: StrokeStyle(lineWidth: 150 * scale, lineCap: .round, lineJoin: .round))
                            .mask(GlyphShape(path: graphics.strokes[completed]).fill(Color.black))
                    }
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .contentShape(Rectangle())
            .onTapGesture { play() }

            HStack {
                Button { play() } label: { Label("Animate", systemImage: "play.fill") }
                Button { stepForward() } label: { Label("Next stroke", systemImage: "forward.frame.fill") }
                Button { reset(showAll: true) } label: { Label("Show", systemImage: "eye") }
            }
            .buttonStyle(.bordered)
            .labelStyle(.iconOnly)
            Text("\(graphics.strokes.count) strokes").font(.caption).foregroundStyle(.secondary)
        }
        .onAppear { play() }
        .onDisappear { animating?.cancel() }
    }

    private func reset(showAll: Bool = false) {
        animating?.cancel()
        var t = Transaction()
        t.disablesAnimations = true
        withTransaction(t) {
            completed = showAll ? graphics.strokes.count : 0
            progress = 0
        }
    }

    private func stepForward() {
        animating?.cancel()
        if completed >= graphics.strokes.count { reset() }
        animateStroke(completed, then: nil)
    }

    private func animateStroke(_ i: Int, then: (() -> Void)?) {
        let length = zip(graphics.medians[i], graphics.medians[i].dropFirst())
            .reduce(0) { $0 + hypot($1.0.x - $1.1.x, $1.0.y - $1.1.y) }
        let duration = max(0.25, Double(length) / 900)
        var t = Transaction()
        t.disablesAnimations = true
        withTransaction(t) { progress = 0 }
        animating = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(30))
            withAnimation(.linear(duration: duration)) { progress = 1 }
            try? await Task.sleep(for: .seconds(duration + 0.1))
            guard !Task.isCancelled else { return }
            withTransaction(t) { completed = i + 1; progress = 0 }
            then?()
        }
    }

    private func play() {
        reset()
        func run(_ i: Int) {
            guard i < graphics.strokes.count else { return }
            animateStroke(i) {
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(120))
                    run(i + 1)
                }
            }
        }
        run(0)
    }
}
