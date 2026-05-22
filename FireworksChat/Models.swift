import Foundation
import UIKit

enum ChatRole: String, Codable {
    case system
    case user
    case assistant
}

struct TokenUsage: Codable, Equatable {
    var prompt: Int
    var completion: Int
    var total: Int
}

struct ChatMessage: Identifiable, Equatable, Codable {
    var id: UUID = UUID()
    var role: ChatRole
    var text: String
    var imageData: Data?
    var createdAt: Date = Date()
    var usage: TokenUsage?

    var image: UIImage? {
        get { imageData.flatMap { UIImage(data: $0) } }
        set { imageData = newValue?.jpegData(compressionQuality: 0.8) }
    }

    init(role: ChatRole, text: String, image: UIImage? = nil, usage: TokenUsage? = nil) {
        self.role = role
        self.text = text
        self.imageData = image?.jpegData(compressionQuality: 0.8)
        self.usage = usage
    }

    static func == (lhs: ChatMessage, rhs: ChatMessage) -> Bool {
        lhs.id == rhs.id
            && lhs.text == rhs.text
            && lhs.imageData == rhs.imageData
            && lhs.usage == rhs.usage
    }
}

struct Conversation: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var title: String
    var messages: [ChatMessage]
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    static func newEmpty() -> Conversation {
        Conversation(title: "Новый чат", messages: [])
    }

    /// Generate a short readable title from the first user message.
    mutating func refreshTitleIfNeeded() {
        guard title == "Новый чат" || title.isEmpty,
              let firstUser = messages.first(where: { $0.role == .user })
        else { return }
        let raw = firstUser.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return }
        title = String(raw.prefix(40))
    }
}
