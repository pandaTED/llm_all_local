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

    init(id: UUID = UUID(), role: MessageRole, content: String, timestamp: Date = Date(), isGenerating: Bool = false) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.isGenerating = isGenerating
    }
}
