import SwiftUI

struct ConversationHistoryView: View {
    let conversations: [ChatConversation]
    let activeConversationID: UUID?
    let onSelect: (UUID) -> Void
    let onDelete: (UUID) -> Void
    let onNewChat: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Button {
                    onNewChat()
                    dismiss()
                } label: {
                    Label("New Chat", systemImage: "plus.bubble")
                }

                ForEach(conversations) { conversation in
                    Button {
                        onSelect(conversation.id)
                        dismiss()
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(conversation.title)
                                    .font(.headline)
                                    .lineLimit(1)
                                Spacer()
                                if activeConversationID == conversation.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(Color.accentColor)
                                }
                            }

                            Text(conversation.previewText)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)

                            Text(conversation.updatedAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 4)
                    }
                    .swipeActions {
                        Button(role: .destructive) {
                            onDelete(conversation.id)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
            .navigationTitle("History")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}
