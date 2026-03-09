import SwiftUI

struct PerformanceHeaderView: View {
    let generation: GenerationStats
    let generationSpeedHistory: [Double]
    let resourceSamples: [ResourceSample]

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                statCard(
                    title: "首字延时",
                    value: generation.firstTokenLatencyMs.map { String(format: "%.0f ms", $0) } ?? "--",
                    tint: .orange
                )

                statCard(
                    title: "生成速度",
                    value: String(format: "%.1f tok/s", generation.tokensPerSecond),
                    tint: .blue,
                    sparklineValues: generationSpeedHistory,
                    range: 0...80
                )

                statCard(
                    title: "已生成",
                    value: "\(generation.generatedTokenCount) tok",
                    tint: .green
                )
            }

            HStack(spacing: 8) {
                usageCard(title: "CPU", value: latestCPU, tint: .red, data: resourceSamples.map { $0.cpuPercent })
                usageCard(title: "内存", value: latestMemory, subtitle: latestMemoryMB, tint: .purple, data: resourceSamples.map { $0.memoryPercent })
                usageCard(title: "GPU*", value: latestGPU, tint: .mint, data: resourceSamples.map { $0.gpuPercent })
                usageCard(title: "NPU*", value: latestNPU, tint: .teal, data: resourceSamples.map { $0.npuPercent })
            }

            HStack {
                Spacer()
                Text("* GPU/NPU 为本地估算值")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal)
        .padding(.top, 6)
        .padding(.bottom, 4)
    }

    private var latestSample: ResourceSample? { resourceSamples.last }
    private var latestCPU: String { latestSample.map { String(format: "%.0f%%", $0.cpuPercent) } ?? "--" }
    private var latestMemory: String { latestSample.map { String(format: "%.0f%%", $0.memoryPercent) } ?? "--" }
    private var latestMemoryMB: String { latestSample.map { String(format: "%.0f MB", $0.memoryMB) } ?? "--" }
    private var latestGPU: String { latestSample.map { String(format: "%.0f%%", $0.gpuPercent) } ?? "--" }
    private var latestNPU: String { latestSample.map { String(format: "%.0f%%", $0.npuPercent) } ?? "--" }

    @ViewBuilder
    private func statCard(
        title: String,
        value: String,
        tint: Color,
        sparklineValues: [Double] = [],
        range: ClosedRange<Double> = 0...100
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.primary)
            if !sparklineValues.isEmpty {
                SparklineView(values: sparklineValues.suffix(36).map { $0 }, color: tint, range: range)
                    .frame(height: 22)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(tint.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func usageCard(
        title: String,
        value: String,
        subtitle: String? = nil,
        tint: Color,
        data: [Double]
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.primary)
            if let subtitle {
                Text(subtitle)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            SparklineView(values: data.suffix(36).map { $0 }, color: tint, range: 0...100)
                .frame(height: 18)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(tint.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
