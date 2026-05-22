import Foundation
import UIKit
import SwiftUI

@MainActor
final class ChatViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var inputText: String = ""
    @Published var selectedImage: UIImage?
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

    @AppStorage("fireworks_api_key") var apiKey: String = ""
    @AppStorage("fireworks_model") var model: String = "accounts/fireworks/models/kimi-k2p6"
    @AppStorage("web_search_enabled") var webSearchEnabled: Bool = true

    func send() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || selectedImage != nil else { return }
        guard !isLoading else { return }

        let userMessage = ChatMessage(role: .user, text: trimmed, image: selectedImage)
        messages.append(userMessage)
        inputText = ""
        selectedImage = nil
        errorMessage = nil
        isLoading = true

        let history = messages
        let api = FireworksAPI(apiKey: apiKey, model: model)
        let searchService = WebSearchService()

        Task {
            do {
                var requestMessages = history
                if webSearchEnabled, !trimmed.isEmpty {
                    do {
                        let searchResults = try await searchService.search(query: trimmed)
                        if !searchResults.isEmpty {
                            let webContext = searchService.context(for: trimmed, results: searchResults)
                            requestMessages.insert(ChatMessage(role: .system, text: webContext, image: nil), at: 0)
                        }
                    } catch {
                        self.errorMessage = "Веб-поиск недоступен: \(error.localizedDescription). Отвечаю без него."
                    }
                }

                // Append an empty assistant message to update in-place during streaming
                let assistantMessage = ChatMessage(role: .assistant, text: "", image: nil)
                self.messages.append(assistantMessage)
                let messageIndex = self.messages.count - 1

                let stream = api.sendChatStream(messages: requestMessages)
                for try await token in stream {
                    self.messages[messageIndex].text += token
                }

                // If stream completed but no tokens were received, remove the empty message
                if self.messages[messageIndex].text.isEmpty {
                    self.messages.remove(at: messageIndex)
                    self.errorMessage = "Получен пустой ответ от сервера."
                }
            } catch {
                // Check if we already appended an assistant message
                let lastIndex = self.messages.count - 1
                if lastIndex >= 0 && self.messages[lastIndex].role == .assistant {
                    if self.messages[lastIndex].text.isEmpty {
                        // No text received yet — remove the empty message
                        self.messages.remove(at: lastIndex)
                    }
                    // If some text was received, keep what we have
                }
                self.errorMessage = error.localizedDescription
            }
            self.isLoading = false
        }
    }

    func clear() {
        messages.removeAll()
        errorMessage = nil
    }
}
