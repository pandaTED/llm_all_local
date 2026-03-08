import SwiftUI

struct ModelDownloadView: View {
    let modelName: String
    let progress: Double
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Text("Downloading Model")
                .font(.headline)

            Text(modelName)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            ProgressView(value: progress)
                .progressViewStyle(.linear)

            Text("\(Int(progress * 100))%")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)

            Button("Cancel", role: .destructive, action: onCancel)
                .buttonStyle(.bordered)
        }
        .padding(20)
        .presentationDetents([.fraction(0.26)])
        .presentationDragIndicator(.visible)
    }
}
