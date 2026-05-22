import Foundation
import UIKit
import SwiftUI

@MainActor
final class ChatViewModel: ObservableObject {
    // Persisted conversation list and selection
    @Published private(set) var conversations: [Conversation] = []
    @Published var currentConversationID: UUID

    @Published var inputText: String = ""
    @Published var selectedImage: UIImage?
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var lastUsage: TokenUsage?

    // Settings
    @AppStorage("fireworks_api_key") var apiKey: String = ""
    @AppStorage("fireworks_model") var model: String = "accounts/fireworks/models/kimi-k2p6"
    @AppStorage("fireworks_endpoint") var endpointURL: String = "https://api.fireworks.ai/inference/v1/chat/completions"
    @AppStorage("web_search_enabled") var webSearchEnabled: Bool = true
    @AppStorage("system_prompt") var systemPrompt: String = ""
    @AppStorage("temperature") var temperature: Double = 0.7
    @AppStorage("max_tokens") var maxTokens: Int = 4096
    @AppStorage("haptics_enabled") var hapticsEnabled: Bool = true
    @AppStorage("accent_color") var accentColorName: String = "orange"

    private let store = ConversationStore.shared
    private var streamingTask: Task<Void, Never>?
    private var persistDebounce: Task<Void, Never>?

    init() {
        let loaded = store.load()
        if loaded.isEmpty {
            let fresh = Conversation.newEmpty()
            self.conversations = [fresh]
            self.currentConversationID = fresh.id
        } else {
            self.conversations = loaded
            self.currentConversationID = loaded.first!.id
        }
    }

    // MARK: - Current conversation accessors

    var currentConversation: Conversation {
        conversations.first(where: { $0.id == currentConversationID }) ?? conversations[0]
    }

    var messages: [ChatMessage] {
        currentConversation.messages
    }

    private func mutateCurrent(_ block: (inout Conversation) -> Void) {
        guard let idx = conversations.firstIndex(where: { $0.id == currentConversationID }) else { return }
        block(&conversations[idx])
        conversations[idx].updatedAt = Date()
        conversations[idx].refreshTitleIfNeeded()
        persist()
    }

    private func persist() {
        store.save(conversations)
    }

    /// Debounced persistence used during high-frequency streaming updates.
    private func persistDebounced() {
        persistDebounce?.cancel()
        persistDebounce = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000) // 0.4s
            guard let self else { return }
            self.store.save(self.conversations)
        }
    }

    // MARK: - Conversation management

    func newConversation() {
        let fresh = Conversation.newEmpty()
        conversations.insert(fresh, at: 0)
        currentConversationID = fresh.id
        errorMessage = nil
        lastUsage = nil
        persist()
    }

    func selectConversation(_ id: UUID) {
        guard conversations.contains(where: { $0.id == id }) else { return }
        currentConversationID = id
        errorMessage = nil
        lastUsage = nil
    }

    func deleteConversation(_ id: UUID) {
        conversations.removeAll(where: { $0.id == id })
        if conversations.isEmpty {
            let fresh = Conversation.newEmpty()
            conversations.append(fresh)
            currentConversationID = fresh.id
        } else if id == currentConversationID {
            currentConversationID = conversations[0].id
        }
        persist()
    }

    func clearCurrent() {
        cancel()
        mutateCurrent { $0.messages.removeAll() }
        errorMessage = nil
        lastUsage = nil
    }

    // MARK: - Sending

    func send() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || selectedImage != nil else { return }
        guard !isLoading else { return }

        let userMessage = ChatMessage(role: .user, text: trimmed, image: selectedImage)
        mutateCurrent { $0.messages.append(userMessage) }
        inputText = ""
        selectedImage = nil
        errorMessage = nil
        lastUsage = nil
        triggerHaptic(.light)

        runGeneration()
    }

    /// Regenerate the last assistant reply.
    func regenerateLast() {
        guard !isLoading else { return }
        guard let lastAssistantIdx = messages.lastIndex(where: { $0.role == .assistant }) else { return }
        // Drop the last assistant message; keep everything before it.
        mutateCurrent { $0.messages.removeSubrange(lastAssistantIdx..<$0.messages.count) }
        errorMessage = nil
        lastUsage = nil
        triggerHaptic(.light)
        runGeneration()
    }

    /// Update an existing user message and regenerate everything after it.
    func editAndResend(messageID: UUID, newText: String) {
        guard !isLoading else { return }
        let trimmed = newText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        var didUpdate = false
        mutateCurrent { conv in
            guard let idx = conv.messages.firstIndex(where: { $0.id == messageID }) else { return }
            guard conv.messages[idx].role == .user else { return }
            conv.messages[idx].text = trimmed
            // Drop everything after this user message
            let cutoff = idx + 1
            if cutoff < conv.messages.count {
                conv.messages.removeSubrange(cutoff..<conv.messages.count)
            }
            didUpdate = true
        }
        guard didUpdate else { return }
        errorMessage = nil
        lastUsage = nil
        triggerHaptic(.light)
        runGeneration()
    }

    func cancel() {
        streamingTask?.cancel()
        streamingTask = nil
    }

    private func runGeneration() {
        isLoading = true
        let history = messages
        let api = FireworksAPI(
            apiKey: apiKey,
            model: model,
            endpoint: URL(string: endpointURL) ?? URL(string: "https://api.fireworks.ai/inference/v1/chat/completions")!,
            temperature: temperature,
            maxTokens: maxTokens,
            systemPrompt: systemPrompt
        )
        let searchService = WebSearchService()
        let useWebSearch = webSearchEnabled
        let queryForSearch = history.last(where: { $0.role == .user })?.text ?? ""

        streamingTask = Task { [weak self] in
            guard let self else { return }
            defer {
                Task { @MainActor in
                    self.isLoading = false
                    self.streamingTask = nil
                }
            }

            do {
                var requestMessages = history
                if useWebSearch, !queryForSearch.isEmpty {
                    do {
                        let searchResults = try await searchService.search(query: queryForSearch)
                        if !searchResults.isEmpty {
                            let webContext = searchService.context(for: queryForSearch, results: searchResults)
                            requestMessages.insert(ChatMessage(role: .system, text: webContext), at: 0)
                        }
                    } catch {
                        await MainActor.run {
                            self.errorMessage = "Веб-поиск недоступен: \(error.localizedDescription). Отвечаю без него."
                        }
                    }
                }

                // Append a placeholder assistant message
                let assistantMessage = ChatMessage(role: .assistant, text: "")
                let assistantID = assistantMessage.id
                await MainActor.run {
                    self.mutateCurrent { $0.messages.append(assistantMessage) }
                }

                let stream = api.sendChatStream(messages: requestMessages)
                var receivedAny = false
                var capturedUsage: TokenUsage?

                for try await event in stream {
                    try Task.checkCancellation()
                    switch event {
                    case .token(let token):
                        receivedAny = true
                        await MainActor.run {
                            self.appendToken(token, messageID: assistantID)
                        }
                    case .usage(let usage):
                        capturedUsage = usage
                    }
                }

                await MainActor.run {
                    if let usage = capturedUsage {
                        self.lastUsage = usage
                        self.attachUsage(usage, to: assistantID)
                    }
                    if !receivedAny {
                        self.removeMessage(assistantID)
                        self.errorMessage = "Получен пустой ответ от сервера."
                    } else {
                        self.triggerHaptic(.success)
                    }
                }
            } catch is CancellationError {
                await MainActor.run {
                    self.cleanupEmptyAssistant()
                }
            } catch FireworksError.cancelled {
                await MainActor.run {
                    self.cleanupEmptyAssistant()
                }
            } catch {
                await MainActor.run {
                    self.cleanupEmptyAssistant()
                    self.errorMessage = error.localizedDescription
                    self.triggerHaptic(.error)
                }
            }
        }
    }

    // MARK: - Mutation helpers

    private func appendToken(_ token: String, messageID: UUID) {
        guard let idx = conversations.firstIndex(where: { $0.id == currentConversationID }) else { return }
        guard let mIdx = conversations[idx].messages.firstIndex(where: { $0.id == messageID }) else { return }
        conversations[idx].messages[mIdx].text += token
        conversations[idx].updatedAt = Date()
        conversations[idx].refreshTitleIfNeeded()
        persistDebounced()
    }

    private func attachUsage(_ usage: TokenUsage, to messageID: UUID) {
        mutateCurrent { conv in
            guard let idx = conv.messages.firstIndex(where: { $0.id == messageID }) else { return }
            conv.messages[idx].usage = usage
        }
    }

    private func removeMessage(_ messageID: UUID) {
        mutateCurrent { conv in
            conv.messages.removeAll(where: { $0.id == messageID })
        }
    }

    /// If the last assistant message is empty, drop it (used after cancel/error).
    private func cleanupEmptyAssistant() {
        mutateCurrent { conv in
            if let last = conv.messages.last, last.role == .assistant, last.text.isEmpty {
                conv.messages.removeLast()
            }
        }
    }

    // MARK: - Haptics

    enum HapticKind { case light, success, error }

    func triggerHaptic(_ kind: HapticKind) {
        guard hapticsEnabled else { return }
        switch kind {
        case .light:
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        case .success:
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .error:
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }

    // MARK: - Export

    func exportCurrentAsMarkdown() -> String {
        var lines: [String] = []
        lines.append("# \(currentConversation.title)")
        lines.append("")
        for msg in currentConversation.messages {
            switch msg.role {
            case .user: lines.append("**Вы:**")
            case .assistant: lines.append("**Ассистент:**")
            case .system: lines.append("**System:**")
            }
            lines.append(msg.text)
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }
}
