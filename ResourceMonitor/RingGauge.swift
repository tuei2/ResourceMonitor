import SwiftUI

struct RingGauge: View {
    let value: Double       // 0–100
    let color: Color
    var lineWidth: CGFloat = 5
    var label: String? = nil

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.12), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(value / 100, 1))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.4), value: value)
            if let label {
                if !label.isEmpty {
                    Text(label)
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(color)
                }
            } else {
                Text(String(format: "%.0f%%", value))
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(color)
            }
        }
    }
}
