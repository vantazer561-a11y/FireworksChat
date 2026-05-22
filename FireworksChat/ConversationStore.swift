import Foundation

/// Persists conversations to disk as JSON in the app's Documents directory.
final class ConversationStore {
    static let shared = ConversationStore()

    private let fileURL: URL
    private let queue = DispatchQueue(label: "ConversationStore.io", qos: .utility)

    init(filename: String = "conversations.json") {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        self.fileURL = docs.appendingPathComponent(filename)
    }

    func load() -> [Conversation] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            return try decoder.decode([Conversation].self, from: data)
        } catch {
            return []
        }
    }

    /// Save asynchronously on a background queue.
    func save(_ conversations: [Conversation]) {
        let url = fileURL
        queue.async {
            do {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let data = try encoder.encode(conversations)
                try data.write(to: url, options: .atomic)
            } catch {
                // Silent fail; persistence is best-effort.
            }
        }
    }
}
