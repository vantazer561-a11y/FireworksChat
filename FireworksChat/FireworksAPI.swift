import Foundation
import UIKit

enum FireworksError: LocalizedError {
    case invalidURL
    case invalidResponse
    case http(Int, String)
    case decoding
    case missingAPIKey

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Неверный URL"
        case .invalidResponse: return "Неверный ответ сервера"
        case .http(let code, let body): return "HTTP \(code): \(body)"
        case .decoding: return "Ошибка декодирования ответа"
        case .missingAPIKey: return "Не задан API-ключ Fireworks"
        }
    }
}

struct FireworksAPI {
    var apiKey: String
    var model: String = "accounts/fireworks/models/llama-v3p2-90b-vision-instruct"
    var endpoint: URL = URL(string: "https://api.fireworks.ai/inference/v1/chat/completions")!

    func sendChat(messages: [ChatMessage]) async throws -> String {
        guard !apiKey.isEmpty else { throw FireworksError.missingAPIKey }

        let payloadMessages: [[String: Any]] = messages.map { message in
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

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 4096,
            "temperature": 0.7,
            "messages": payloadMessages
        ]

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw FireworksError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let text = String(data: data, encoding: .utf8) ?? ""
            throw FireworksError.http(http.statusCode, text)
        }

        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let choices = json["choices"] as? [[String: Any]],
            let first = choices.first,
            let message = first["message"] as? [String: Any],
            let content = message["content"] as? String
        else {
            throw FireworksError.decoding
        }
        return content
    }

    func sendChatStream(messages: [ChatMessage]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    guard !apiKey.isEmpty else {
                        continuation.finish(throwing: FireworksError.missingAPIKey)
                        return
                    }

                    let payloadMessages: [[String: Any]] = messages.map { message in
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

                    let body: [String: Any] = [
                        "model": model,
                        "max_tokens": 4096,
                        "temperature": 0.7,
                        "messages": payloadMessages,
                        "stream": true
                    ]

                    var request = URLRequest(url: endpoint)
                    request.httpMethod = "POST"
                    request.timeoutInterval = 120
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                    request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])

                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    guard let http = response as? HTTPURLResponse else {
                        continuation.finish(throwing: FireworksError.invalidResponse)
                        return
                    }
                    guard (200..<300).contains(http.statusCode) else {
                        var errorBody = ""
                        for try await line in bytes.lines {
                            errorBody += line
                        }
                        continuation.finish(throwing: FireworksError.http(http.statusCode, errorBody))
                        return
                    }

                    for try await line in bytes.lines {
                        if line.isEmpty { continue }
                        guard line.hasPrefix("data: ") else { continue }

                        let payload = String(line.dropFirst(6))
                        if payload == "[DONE]" {
                            break
                        }

                        guard let data = payload.data(using: .utf8),
                              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                              let choices = json["choices"] as? [[String: Any]],
                              let first = choices.first,
                              let delta = first["delta"] as? [String: Any],
                              let content = delta["content"] as? String
                        else {
                            continue
                        }

                        continuation.yield(content)
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}
