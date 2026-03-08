import SwiftUI

struct InputBarView: View {
    @Binding var text: String
    let isGenerating: Bool
    let onSend: () -> Void
    let onStop: () -> Void

    var body: some View {
        HStack(alignment: .bottom, spacing: 12) {
            TextField("Message...", text: $text, axis: .vertical)
                .lineLimit(1...6)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .onSubmit {
                    if !isGenerating {
                        onSend()
                    }
                }

            Button(action: isGenerating ? onStop : onSend) {
                Image(systemName: isGenerating ? "stop.circle.fill" : "arrow.up.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(isGenerating ? .red : .accentColor)
            }
            .disabled(!isGenerating && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }
}
