import SwiftUI

struct TypingIndicatorView: View {
    @State private var phase = 0

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(Color.secondary)
                    .frame(width: 8, height: 8)
                    .scaleEffect(phase == index ? 1.2 : 0.8)
                    .opacity(phase == index ? 1.0 : 0.35)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(.systemGray5))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .onAppear {
            withAnimation(.easeInOut(duration: 0.75).repeatForever(autoreverses: false)) {
                phase = 2
            }
        }
    }
}
