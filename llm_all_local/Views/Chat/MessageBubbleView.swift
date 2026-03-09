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

            VStack(alignment: isUser ? .trailing : .leading, spacing: 6) {
                Text(isUser ? "You" : "AI")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                if !message.attachments.isEmpty {
                    attachmentGrid(isUser: isUser)
                }

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
    private func attachmentGrid(isUser: Bool) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 6)], spacing: 6) {
            ForEach(message.attachments) { attachment in
                if let image = loadImage(path: attachment.thumbnailPath ?? attachment.localPath) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 92, height: 92)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
        }
        .frame(maxWidth: 220, alignment: isUser ? .trailing : .leading)
    }

    @ViewBuilder
    private func contentView(isUser: Bool) -> some View {
        if isUser {
            textWithCursor(value: message.content, showCursor: false)
        } else {
            TimelineView(.periodic(from: .now, by: 0.5)) { timeline in
                let showCursor = message.isGenerating && Int(timeline.date.timeIntervalSinceReferenceDate * 2).isMultiple(of: 2)
                assistantContent(showCursor: showCursor)
            }
        }
    }

    @ViewBuilder
    private func assistantContent(showCursor: Bool) -> some View {
        let parsed = parseThink(content: message.content)

        VStack(alignment: .leading, spacing: 8) {
            if let markdown = markdownText(value: parsed.answer, showCursor: showCursor && parsed.answer.isEmpty) {
                Text(markdown)
            } else {
                textWithCursor(value: parsed.answer, showCursor: showCursor)
            }

            if !parsed.thinkText.isEmpty || parsed.openThinking {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: "brain")
                            .foregroundStyle(.orange)
                        Text("思考过程")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                    }

                    if parsed.openThinking && message.isGenerating {
                        ProgressView()
                            .progressViewStyle(.linear)
                        Text("正在思考...")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    if !parsed.thinkText.isEmpty {
                        Text(parsed.thinkText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(8)
                .background(Color.orange.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    private func textWithCursor(value: String, showCursor: Bool) -> Text {
        let rendered = showCursor ? value + "▋" : value
        return Text(rendered.isEmpty && showCursor ? "▋" : rendered)
    }

    private func markdownText(value: String, showCursor: Bool) -> AttributedString? {
        let base = value.trimmingCharacters(in: .whitespacesAndNewlines)
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

    private func parseThink(content: String) -> (answer: String, thinkText: String, openThinking: Bool) {
        guard let start = content.range(of: "<think>") else {
            return (content, "", false)
        }

        let before = String(content[..<start.lowerBound])
        let afterStart = content[start.upperBound...]

        if let end = afterStart.range(of: "</think>") {
            let thinkText = String(afterStart[..<end.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            let after = String(afterStart[end.upperBound...])
            return (before + after, thinkText, false)
        }

        let thinking = String(afterStart).trimmingCharacters(in: .whitespacesAndNewlines)
        return (before, thinking, true)
    }

    private func loadImage(path: String?) -> UIImage? {
        guard let path, !path.isEmpty else { return nil }
        return UIImage(contentsOfFile: path)
    }
}
