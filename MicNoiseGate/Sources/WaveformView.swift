import SwiftUI

struct WaveformView: View {
    let samples: [Float]
    let color: Color
    let label: String
    let level: Float

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                // Level indicator
                Text("\(Int(level * 100))%")
                    .font(.caption2)
                    .foregroundColor(color)
                    .monospacedDigit()
            }

            GeometryReader { geometry in
                let width = geometry.size.width
                let height = geometry.size.height
                let midY = height / 2

                ZStack {
                    // Background
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.1))

                    // Center line
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: midY))
                        path.addLine(to: CGPoint(x: width, y: midY))
                    }
                    .stroke(Color.gray.opacity(0.3), lineWidth: 0.5)

                    // Waveform
                    Path { path in
                        guard samples.count > 1 else { return }

                        let stepX = width / CGFloat(samples.count - 1)

                        path.move(to: CGPoint(x: 0, y: midY))

                        for (index, sample) in samples.enumerated() {
                            let x = CGFloat(index) * stepX
                            let normalizedSample = CGFloat(sample) * 3 // Scale for visibility
                            let y = midY - (normalizedSample * midY * 0.8)
                            path.addLine(to: CGPoint(x: x, y: y))
                        }
                    }
                    .stroke(color, lineWidth: 1.5)

                    // Filled area under waveform
                    Path { path in
                        guard samples.count > 1 else { return }

                        let stepX = width / CGFloat(samples.count - 1)

                        path.move(to: CGPoint(x: 0, y: midY))

                        for (index, sample) in samples.enumerated() {
                            let x = CGFloat(index) * stepX
                            let normalizedSample = CGFloat(sample) * 3
                            let y = midY - (normalizedSample * midY * 0.8)
                            path.addLine(to: CGPoint(x: x, y: y))
                        }

                        path.addLine(to: CGPoint(x: width, y: midY))
                        path.closeSubpath()
                    }
                    .fill(color.opacity(0.2))
                }
            }
            .frame(height: 40)
        }
    }
}

struct LevelMeterView: View {
    let inputLevel: Float
    let outputLevel: Float

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Text("IN")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .frame(width: 25, alignment: .trailing)

                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.gray.opacity(0.2))

                        RoundedRectangle(cornerRadius: 2)
                            .fill(levelColor(inputLevel))
                            .frame(width: geometry.size.width * CGFloat(inputLevel))
                    }
                }
                .frame(height: 8)
            }

            HStack(spacing: 8) {
                Text("OUT")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .frame(width: 25, alignment: .trailing)

                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.gray.opacity(0.2))

                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.green)
                            .frame(width: geometry.size.width * CGFloat(outputLevel))
                    }
                }
                .frame(height: 8)
            }
        }
    }

    private func levelColor(_ level: Float) -> Color {
        if level < 0.5 {
            return .green
        } else if level < 0.8 {
            return .yellow
        } else {
            return .red
        }
    }
}
