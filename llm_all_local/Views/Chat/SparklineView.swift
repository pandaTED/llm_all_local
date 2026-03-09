import SwiftUI

struct SparklineView: View {
    let values: [Double]
    let color: Color
    let range: ClosedRange<Double>

    var body: some View {
        GeometryReader { proxy in
            let normalized = normalize(values: values, range: range)

            Path { path in
                guard !normalized.isEmpty else { return }

                for (index, value) in normalized.enumerated() {
                    let x = proxy.size.width * CGFloat(index) / CGFloat(max(normalized.count - 1, 1))
                    let y = proxy.size.height * (1 - CGFloat(value))

                    if index == 0 {
                        path.move(to: CGPoint(x: x, y: y))
                    } else {
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                }
            }
            .stroke(color, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
        }
    }

    private func normalize(values: [Double], range: ClosedRange<Double>) -> [Double] {
        guard !values.isEmpty else { return [] }
        let minValue = range.lowerBound
        let maxValue = range.upperBound
        let span = max(maxValue - minValue, 0.0001)

        return values.map { value in
            let clamped = min(max(value, minValue), maxValue)
            return (clamped - minValue) / span
        }
    }
}
