import Foundation

enum MessageRole: String, Codable {
    case user
    case assistant
    case system
}

struct ChatMessage: Identifiable, Codable, Equatable {
    let id: UUID
    var role: MessageRole
    var content: String
    let timestamp: Date
    var isGenerating: Bool
    var attachments: [ChatAttachment]
    var inferenceAugmentation: String?

    init(
        id: UUID = UUID(),
        role: MessageRole,
        content: String,
        timestamp: Date = Date(),
        isGenerating: Bool = false,
        attachments: [ChatAttachment] = [],
        inferenceAugmentation: String? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.isGenerating = isGenerating
        self.attachments = attachments
        self.inferenceAugmentation = inferenceAugmentation
    }

    enum CodingKeys: String, CodingKey {
        case id
        case role
        case content
        case timestamp
        case isGenerating
        case attachments
        case inferenceAugmentation
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        role = try container.decode(MessageRole.self, forKey: .role)
        content = try container.decode(String.self, forKey: .content)
        timestamp = try container.decodeIfPresent(Date.self, forKey: .timestamp) ?? Date()
        isGenerating = try container.decodeIfPresent(Bool.self, forKey: .isGenerating) ?? false
        attachments = try container.decodeIfPresent([ChatAttachment].self, forKey: .attachments) ?? []
        inferenceAugmentation = try container.decodeIfPresent(String.self, forKey: .inferenceAugmentation)
    }

    func contentForInference() -> String {
        guard let inferenceAugmentation, !inferenceAugmentation.isEmpty else {
            return content
        }

        if content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return inferenceAugmentation
        }

        return content + "\n\n" + inferenceAugmentation
    }
}
