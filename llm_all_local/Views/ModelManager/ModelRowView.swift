import SwiftUI

struct ModelRowView: View {
    let model: ModelConfig
    let deviceRAM: Double
    let isDownloading: Bool
    let onDownload: () -> Void
    let onUse: () -> Void
    let onDelete: () -> Void

    var needsRAMWarning: Bool {
        deviceRAM < model.ramRequiredGB
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(model.name)
                        .font(.headline)

                    HStack(spacing: 8) {
                        badge(text: String(format: "%.1f GB", model.fileSizeGB), color: .blue)
                        badge(text: String(format: "RAM %.1f GB+", model.ramRequiredGB), color: needsRAMWarning ? .red : .green)
                    }
                }

                Spacer()
            }

            if isDownloading {
                ProgressView(value: model.downloadProgress)
            }

            HStack(spacing: 10) {
                if model.isDownloaded {
                    Button("Use", action: onUse)
                        .buttonStyle(.borderedProminent)

                    Button("Delete", role: .destructive, action: onDelete)
                        .buttonStyle(.bordered)
                } else {
                    Button(isDownloading ? "Downloading…" : "Download", action: onDownload)
                        .buttonStyle(.borderedProminent)
                        .disabled(isDownloading)
                }
            }

            if needsRAMWarning {
                Label("This model may exceed available RAM on this device.", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 8)
    }

    private func badge(text: String, color: Color) -> some View {
        Text(text)
            .font(.caption.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.12))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}
