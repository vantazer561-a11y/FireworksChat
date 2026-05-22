import Foundation
import UIKit

enum FireworksError: LocalizedError {
    case invalidURL
    case invalidResponse
    case http(Int, String)
    case decoding
    case missingAPIKey
    case cancelled

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Неверный URL"
        case .invalidResponse: return "Неверный ответ сервера"
        case .http(let code, let body): return "HTTP \(code): \(body)"
        case .decoding: return "Ошибка декодирования ответа"
        case .missingAPIKey: return "Не задан API-ключ"
        case .cancelled: return "Запрос отменён"
        }
    }
}

/// Streaming events emitted while reading the SSE response.
enum FireworksStreamEvent {
    case token(String)
    case usage(TokenUsage)
}

struct FireworksAPI {
    var apiKey: String
    var model: String
    var endpoint: URL
    var temperature: Double
    var maxTokens: Int
    var systemPrompt: String

    init(
        apiKey: String,
        model: String = "accounts/fireworks/models/kimi-k2p6",
        endpoint: URL = URL(string: "https://api.fireworks.ai/inference/v1/chat/completions")!,
        temperature: Double = 0.7,
        maxTokens: Int = 4096,
        systemPrompt: String = ""
    ) {
        self.apiKey = apiKey
        self.model = model
        self.endpoint = endpoint
        self.temperature = temperature
        self.maxTokens = maxTokens
        self.systemPrompt = systemPrompt
    }

    func sendChatStream(messages: [ChatMessage]) -> AsyncThrowingStream<FireworksStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard !apiKey.isEmpty else {
                        continuation.finish(throwing: FireworksError.missingAPIKey)
                        return
                    }

                    var allMessages = messages
                    let trimmedPrompt = systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmedPrompt.isEmpty {
                        allMessages.insert(ChatMessage(role: .system, text: trimmedPrompt), at: 0)
                    }

                    let payloadMessages = Self.buildPayload(messages: allMessages)
                    let body: [String: Any] = [
                        "model": model,
                        "max_tokens": maxTokens,
                        "temperature": temperature,
                        "messages": payloadMessages,
                        "stream": true,
                        "stream_options": ["include_usage": true]
                    ]

                    var request = URLRequest(url: endpoint)
                    request.httpMethod = "POST"
                    request.timeoutInterval = 120
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    if !apiKey.isEmpty {
                        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                    }
                    request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])

                    let (bytes, response) = try await URLSession.shared.bytes(for: request)

                    try Task.checkCancellation()

                    guard let http = response as? HTTPURLResponse else {
                        continuation.finish(throwing: FireworksError.invalidResponse)
                        return
                    }
                    guard (200..<300).contains(http.statusCode) else {
                        var errorBody = ""
                        for try await line in bytes.lines { errorBody += line }
                        continuation.finish(throwing: FireworksError.http(http.statusCode, errorBody))
                        return
                    }

                    for try await line in bytes.lines {
                        try Task.checkCancellation()
                        if line.isEmpty { continue }
                        guard line.hasPrefix("data: ") else { continue }
                        let payload = String(line.dropFirst(6))
                        if payload == "[DONE]" { break }

                        guard
                            let data = payload.data(using: .utf8),
                            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                        else { continue }

                        if let choices = json["choices"] as? [[String: Any]],
                           let first = choices.first,
                           let delta = first["delta"] as? [String: Any],
                           let content = delta["content"] as? String,
                           !content.isEmpty {
                            continuation.yield(.token(content))
                        }

                        if let usage = json["usage"] as? [String: Any],
                           let prompt = usage["prompt_tokens"] as? Int,
                           let completion = usage["completion_tokens"] as? Int,
                           let total = usage["total_tokens"] as? Int {
                            continuation.yield(.usage(TokenUsage(
                                prompt: prompt,
                                completion: completion,
                                total: total
                            )))
                        }
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: FireworksError.cancelled)
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    private static func buildPayload(messages: [ChatMessage]) -> [[String: Any]] {
        messages.map { message in
            var contentParts: [[String: Any]] = []
            if !message.text.isEmpty {
                contentParts.append(["type": "text", "text": message.text])
            }
            if let img = message.image, let data = img.jpegData(compressionQuality: 0.8) {
                let b64 = data.base64EncodedString()
                contentParts.append([
                    "type": "image_url",
                    "image_url": ["url": "data:image/jpeg;base64,\(b64)"]
                ])
            }
            if contentParts.count == 1, let first = contentParts.first,
               let txt = first["text"] as? String, first["type"] as? String == "text" {
                return ["role": message.role.rawValue, "content": txt]
            }
            return ["role": message.role.rawValue, "content": contentParts]
        }
    }
}
