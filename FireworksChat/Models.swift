import Foundation
import UIKit

enum ChatRole: String, Codable {
    case system
    case user
    case assistant
}

struct ChatMessage: Identifiable, Equatable {
    let id = UUID()
    var role: ChatRole
    var text: String
    var image: UIImage?

    static func == (lhs: ChatMessage, rhs: ChatMessage) -> Bool {
        lhs.id == rhs.id
    }
}
