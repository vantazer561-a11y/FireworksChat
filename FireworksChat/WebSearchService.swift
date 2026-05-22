import Foundation

struct WebSearchResult: Equatable {
    let title: String
    let summary: String
    let url: String
}

enum WebSearchError: LocalizedError {
    case invalidURL
    case invalidResponse
    case http(Int)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Неверный URL веб-поиска"
        case .invalidResponse:
            return "Неверный ответ сервиса веб-поиска"
        case .http(let code):
            return "Веб-поиск вернул HTTP \(code)"
        }
    }
}

struct WebSearchService {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func search(query: String, limit: Int = 6) async throws -> [WebSearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        var results: [WebSearchResult] = []
        results.append(contentsOf: try await searchDuckDuckGo(query: trimmed, limit: limit))

        if results.isEmpty {
            results.append(contentsOf: try await searchDuckDuckGoHTML(query: trimmed, limit: limit))
        }

        if results.count < limit {
            let wikipediaResults = try await searchWikipedia(query: trimmed, limit: limit - results.count)
            results.append(contentsOf: wikipediaResults)
        }

        return deduplicated(results).prefix(limit).map { $0 }
    }

    func context(for query: String, results: [WebSearchResult], date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateStyle = .long
        formatter.timeStyle = .short

        var lines = [
            "У тебя есть свежий интернет-контекст для ответа.",
            "Дата поиска: \(formatter.string(from: date)).",
            "Запрос пользователя: \(query)",
            "Используй результаты ниже, если они полезны. Если данных недостаточно, честно скажи об этом. По возможности указывай ссылки.",
            ""
        ]

        for (index, result) in results.enumerated() {
            lines.append("[\(index + 1)] \(result.title)")
            lines.append(result.summary)
            lines.append(result.url)
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    private func searchDuckDuckGo(query: String, limit: Int) async throws -> [WebSearchResult] {
        var components = URLComponents(string: "https://api.duckduckgo.com/")
        components?.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "no_html", value: "1"),
            URLQueryItem(name: "no_redirect", value: "1"),
            URLQueryItem(name: "skip_disambig", value: "1")
        ]

        guard let url = components?.url else { throw WebSearchError.invalidURL }
        let data = try await loadData(from: url)
        let response = try JSONDecoder().decode(DuckDuckGoResponse.self, from: data)

        var results: [WebSearchResult] = []
        if let abstract = response.abstractText?.trimmedNonEmpty,
           let url = response.abstractURL?.trimmedNonEmpty {
            results.append(WebSearchResult(
                title: response.heading?.trimmedNonEmpty ?? query,
                summary: abstract,
                url: url
            ))
        }

        for topic in response.relatedTopics ?? [] {
            collectDuckDuckGoTopics(topic, into: &results, limit: limit)
            if results.count >= limit { break }
        }

        return Array(results.prefix(limit))
    }

    private func searchDuckDuckGoHTML(query: String, limit: Int) async throws -> [WebSearchResult] {
        var components = URLComponents(string: "https://html.duckduckgo.com/html/")
        components?.queryItems = [
            URLQueryItem(name: "q", value: query)
        ]

        guard let url = components?.url else { throw WebSearchError.invalidURL }

        var request = URLRequest(url: url)
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent"
        )

        let data: Data
        do {
            data = try await loadData(from: request)
        } catch {
            return []
        }

        guard let html = String(data: data, encoding: .utf8) else { return [] }

        var results: [WebSearchResult] = []

        let linkPattern = #"<a class="result__a"[^>]*href="([^"]*)"[^>]*>(.*?)</a>"#
        let snippetPattern = #"<a class="result__snippet"[^>]*>(.*?)</a>"#

        guard let linkRegex = try? NSRegularExpression(pattern: linkPattern, options: .dotMatchesLineSeparators),
              let snippetRegex = try? NSRegularExpression(pattern: snippetPattern, options: .dotMatchesLineSeparators) else {
            return []
        }

        let nsHTML = html as NSString
        let linkMatches = linkRegex.matches(in: html, range: NSRange(location: 0, length: nsHTML.length))
        let snippetMatches = snippetRegex.matches(in: html, range: NSRange(location: 0, length: nsHTML.length))

        for (index, linkMatch) in linkMatches.enumerated() {
            guard results.count < limit else { break }

            let rawURL = nsHTML.substring(with: linkMatch.range(at: 1))
            let rawTitle = nsHTML.substring(with: linkMatch.range(at: 2)).strippingHTML

            let resolvedURL = resolveRedirectURL(rawURL)
            guard let finalURL = resolvedURL.trimmedNonEmpty, let title = rawTitle.trimmedNonEmpty else { continue }

            var snippet = title
            if index < snippetMatches.count {
                let snippetText = nsHTML.substring(with: snippetMatches[index].range(at: 1)).strippingHTML
                if let trimmed = snippetText.trimmedNonEmpty {
                    snippet = trimmed
                }
            }

            results.append(WebSearchResult(title: title, summary: snippet, url: finalURL))
        }

        return Array(results.prefix(limit))
    }

    private func resolveRedirectURL(_ rawURL: String) -> String {
        if rawURL.contains("uddg="),
           let components = URLComponents(string: rawURL),
           let uddg = components.queryItems?.first(where: { $0.name == "uddg" })?.value {
            return uddg
        }
        return rawURL
    }

    private func collectDuckDuckGoTopics(_ topic: DuckDuckGoTopic, into results: inout [WebSearchResult], limit: Int) {
        guard results.count < limit else { return }

        if let text = topic.text?.trimmedNonEmpty,
           let url = topic.firstURL?.trimmedNonEmpty {
            let title = text.components(separatedBy: " - ").first?.trimmedNonEmpty ?? text
            results.append(WebSearchResult(title: title, summary: text, url: url))
        }

        for child in topic.topics ?? [] {
            collectDuckDuckGoTopics(child, into: &results, limit: limit)
            if results.count >= limit { break }
        }
    }

    private func searchWikipedia(query: String, limit: Int) async throws -> [WebSearchResult] {
        guard limit > 0 else { return [] }

        let host = query.containsCyrillic ? "ru.wikipedia.org" : "en.wikipedia.org"
        var components = URLComponents(string: "https://\(host)/w/api.php")
        components?.queryItems = [
            URLQueryItem(name: "action", value: "query"),
            URLQueryItem(name: "list", value: "search"),
            URLQueryItem(name: "srsearch", value: query),
            URLQueryItem(name: "srlimit", value: String(limit)),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "utf8", value: "1")
        ]

        guard let url = components?.url else { throw WebSearchError.invalidURL }
        let data = try await loadData(from: url)
        let response = try JSONDecoder().decode(WikipediaResponse.self, from: data)

        return (response.query?.search ?? []).prefix(limit).map { item in
            let wikiTitle = item.title.replacingOccurrences(of: " ", with: "_")
            let encodedTitle = wikiTitle.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? wikiTitle
            return WebSearchResult(
                title: item.title,
                summary: item.snippet.strippingHTML.trimmedNonEmpty ?? item.title,
                url: "https://\(host)/wiki/\(encodedTitle)"
            )
        }
    }

    private func loadData(from url: URL) async throws -> Data {
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse else {
            throw WebSearchError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw WebSearchError.http(http.statusCode)
        }
        return data
    }

    private func loadData(from request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw WebSearchError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw WebSearchError.http(http.statusCode)
        }
        return data
    }

    private func deduplicated(_ results: [WebSearchResult]) -> [WebSearchResult] {
        var seen = Set<String>()
        return results.filter { result in
            seen.insert(result.url).inserted
        }
    }
}

private struct DuckDuckGoResponse: Decodable {
    let heading: String?
    let abstractText: String?
    let abstractURL: String?
    let relatedTopics: [DuckDuckGoTopic]?

    enum CodingKeys: String, CodingKey {
        case heading = "Heading"
        case abstractText = "AbstractText"
        case abstractURL = "AbstractURL"
        case relatedTopics = "RelatedTopics"
    }
}

private struct DuckDuckGoTopic: Decodable {
    let text: String?
    let firstURL: String?
    let topics: [DuckDuckGoTopic]?

    enum CodingKeys: String, CodingKey {
        case text = "Text"
        case firstURL = "FirstURL"
        case topics = "Topics"
    }
}

private struct WikipediaResponse: Decodable {
    let query: WikipediaQuery?
}

private struct WikipediaQuery: Decodable {
    let search: [WikipediaSearchItem]
}

private struct WikipediaSearchItem: Decodable {
    let title: String
    let snippet: String
}

private extension String {
    var trimmedNonEmpty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    var containsCyrillic: Bool {
        range(of: "\\p{Cyrillic}", options: .regularExpression) != nil
    }

    var strippingHTML: String {
        replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&#039;", with: "'")
    }
}
