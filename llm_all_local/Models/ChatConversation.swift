import Foundation

struct ChatConversation: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var messages: [ChatMessage]
    let createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String = "New Chat",
        messages: [ChatMessage] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.messages = messages
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var previewText: String {
        let latestUser = messages.last(where: { $0.role == .user })?.content
        let latestAssistant = messages.last(where: { $0.role == .assistant })?.content
        return latestUser ?? latestAssistant ?? "No messages"
    }
}
