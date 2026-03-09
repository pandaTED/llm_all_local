import SwiftUI
import UIKit

struct InputBarView: View {
    @Binding var text: String
    let pendingAttachments: [ChatAttachment]
    let isGenerating: Bool
    let onSend: () -> Void
    let onStop: () -> Void
    let onPickFromLibrary: () -> Void
    let onPickFromCamera: () -> Void
    let onRemoveAttachment: (UUID) -> Void

    var body: some View {
        VStack(spacing: 8) {
            if !pendingAttachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(pendingAttachments) { attachment in
                            attachmentChip(attachment)
                        }
                    }
                    .padding(.horizontal)
                }
            }

            HStack(alignment: .bottom, spacing: 10) {
                Menu {
                    Button("Photo Library", systemImage: "photo") {
                        onPickFromLibrary()
                    }
                    Button("Camera", systemImage: "camera") {
                        onPickFromCamera()
                    }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(Color.accentColor)
                }

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
                .disabled(!isGenerating && sendDisabled)
            }
            .padding(.horizontal)
            .padding(.bottom, 10)
        }
        .padding(.top, 8)
    }

    private var sendDisabled: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && pendingAttachments.isEmpty
    }

    @ViewBuilder
    private func attachmentChip(_ attachment: ChatAttachment) -> some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let image = loadPreviewImage(for: attachment) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(.systemGray5))
                        .overlay {
                            Image(systemName: "photo")
                                .foregroundStyle(.secondary)
                        }
                }
            }
            .frame(width: 78, height: 78)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            Button {
                onRemoveAttachment(attachment.id)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.white, .black.opacity(0.55))
            }
            .offset(x: 6, y: -6)
        }
    }

    private func loadPreviewImage(for attachment: ChatAttachment) -> UIImage? {
        let path = attachment.thumbnailPath ?? attachment.localPath
        guard !path.isEmpty else { return nil }
        return UIImage(contentsOfFile: path)
    }
}
