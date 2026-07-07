import SwiftUI

struct SparklineView: View {
    let values: [Double]
    let color: Color
    var maxValue: Double = 100

    var body: some View {
        Canvas { context, size in
            let w = size.width
            let h = size.height
            guard values.count > 1 else { return }
            let cap  = maxValue > 0 ? maxValue : 1
            let step = w / Double(values.count - 1)

            func yPos(_ v: Double) -> Double { h - (min(v, cap) / cap * h) }

            // Gradient fill under line
            var fill = Path()
            fill.move(to: CGPoint(x: 0, y: h))
            for (i, v) in values.enumerated() {
                fill.addLine(to: CGPoint(x: Double(i) * step, y: yPos(v)))
            }
            fill.addLine(to: CGPoint(x: w, y: h))
            fill.closeSubpath()

            context.fill(fill, with: .linearGradient(
                Gradient(colors: [color.opacity(0.28), color.opacity(0.02)]),
                startPoint: CGPoint(x: 0, y: 0),
                endPoint: CGPoint(x: 0, y: h)))

            // Line
            var line = Path()
            line.move(to: CGPoint(x: 0, y: yPos(values[0])))
            for i in 1..<values.count {
                line.addLine(to: CGPoint(x: Double(i) * step, y: yPos(values[i])))
            }
            context.stroke(line, with: .color(color),
                           style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))

            // End-point dot
            if let last = values.last {
                let dx = Double(values.count - 1) * step
                let dy = yPos(last)
                context.fill(Path(ellipseIn: CGRect(x: dx - 2.5, y: dy - 2.5, width: 5, height: 5)),
                             with: .color(color))
            }
        }
        .background(color.opacity(0.04))
    }
}
