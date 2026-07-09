import Foundation

/// Supported LLM providers. Both expose OpenAI-compatible
/// chat-completion APIs, so one client covers them all.
enum LLMProvider: String, CaseIterable, Identifiable, Codable {
    case deepseek
    case qwen

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .deepseek: return "DeepSeek"
        case .qwen: return "Qwen (DashScope)"
        }
    }

    var chatCompletionsURL: URL {
        switch self {
        case .deepseek:
            return URL(string: "https://api.deepseek.com/v1/chat/completions")!
        case .qwen:
            return URL(string: "https://dashscope-intl.aliyuncs.com/compatible-mode/v1/chat/completions")!
        }
    }

    var defaultModel: String {
        switch self {
        case .deepseek: return "deepseek-chat"
        case .qwen: return "qwen-plus"
        }
    }
}

enum LLMError: LocalizedError {
    case missingAPIKey
    case httpError(status: Int, body: String)
    case emptyResponse
    case invalidJSON(underlying: Error)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "No API key set. Add your provider key in Settings."
        case .httpError(let status, let body):
            return "The AI service returned an error (HTTP \(status)). \(body.prefix(200))"
        case .emptyResponse:
            return "The AI service returned an empty response. Please try again."
        case .invalidJSON:
            return "Couldn't read the generated workout. Please try again."
        }
    }
}

struct LLMClient {
    var provider: LLMProvider
    /// Empty string means "use the provider default".
    var modelOverride: String
    var apiKey: String

    private struct ChatMessage: Codable {
        let role: String
        let content: String
    }

    private struct ResponseFormat: Encodable {
        let type: String
    }

    private struct ChatRequest: Encodable {
        let model: String
        let messages: [ChatMessage]
        let temperature: Double
        let max_tokens: Int
        let response_format: ResponseFormat
    }

    private struct ChatResponse: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable { let content: String? }
            let message: Message
        }
        let choices: [Choice]
    }

    /// Sends a system + user prompt and returns the raw text of the reply.
    func complete(system: String, user: String) async throws -> String {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw LLMError.missingAPIKey }

        let model = modelOverride.trimmingCharacters(in: .whitespaces).isEmpty
            ? provider.defaultModel
            : modelOverride

        var request = URLRequest(url: provider.chatCompletionsURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(ChatRequest(
            model: model,
            messages: [
                ChatMessage(role: "system", content: system),
                ChatMessage(role: "user", content: user),
            ],
            temperature: 0.7,
            max_tokens: 2048,
            response_format: ResponseFormat(type: "json_object")
        ))

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw LLMError.httpError(
                status: http.statusCode,
                body: String(data: data, encoding: .utf8) ?? ""
            )
        }

        let decoded = try JSONDecoder().decode(ChatResponse.self, from: data)
        guard let content = decoded.choices.first?.message.content,
              !content.isEmpty else {
            throw LLMError.emptyResponse
        }
        return content
    }
}
