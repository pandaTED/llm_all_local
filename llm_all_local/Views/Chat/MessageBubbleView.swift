import SwiftUI
import UIKit

struct MessageBubbleView: View {
    let message: ChatMessage

    var body: some View {
        switch message.role {
        case .system:
            systemMessage
        case .user, .assistant:
            chatBubble
        }
    }

    private var chatBubble: some View {
        let isUser = message.role == .user

        return HStack(alignment: .bottom, spacing: 8) {
            if isUser { Spacer(minLength: 60) }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                Text(isUser ? "You" : "AI")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                contentView(isUser: isUser)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(isUser ? Color.accentColor : Color(.systemGray5))
                    .foregroundStyle(isUser ? .white : .primary)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .textSelection(.enabled)
                    .contextMenu {
                        Button("Copy", systemImage: "doc.on.doc") {
                            UIPasteboard.general.string = message.content
                        }
                    }
            }

            if !isUser { Spacer(minLength: 60) }
        }
    }

    private var systemMessage: some View {
        Text(message.content)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
    }

    @ViewBuilder
    private func contentView(isUser: Bool) -> some View {
        if isUser {
            textWithCursor(value: message.content, showCursor: false)
        } else {
            TimelineView(.periodic(from: .now, by: 0.5)) { timeline in
                let showCursor = message.isGenerating && Int(timeline.date.timeIntervalSinceReferenceDate * 2).isMultiple(of: 2)
                if let markdown = markdownText(showCursor: showCursor) {
                    Text(markdown)
                } else {
                    textWithCursor(value: message.content, showCursor: showCursor)
                }
            }
        }
    }

    private func textWithCursor(value: String, showCursor: Bool) -> Text {
        let rendered = showCursor ? value + "▋" : value
        return Text(rendered.isEmpty && showCursor ? "▋" : rendered)
    }

    private func markdownText(showCursor: Bool) -> AttributedString? {
        let base = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty else { return nil }

        do {
            var rendered = try AttributedString(
                markdown: base,
                options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .full)
            )

            if showCursor {
                rendered += AttributedString("▋")
            }
            return rendered
        } catch {
            return nil
        }
    }
}
