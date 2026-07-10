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

struct LLMMessage: Codable {
    let role: String
    let content: String

    static func system(_ content: String) -> LLMMessage { .init(role: "system", content: content) }
    static func user(_ content: String) -> LLMMessage { .init(role: "user", content: content) }
    static func assistant(_ content: String) -> LLMMessage { .init(role: "assistant", content: content) }
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
            return "Couldn't read the coach's response. Please try again."
        }
    }
}

struct LLMClient {
    var provider: LLMProvider
    /// Empty string means "use the provider default".
    var modelOverride: String
    var apiKey: String

    /// Builds a client from the app's stored settings.
    static func fromSettings() -> LLMClient {
        let providerRaw = UserDefaults.standard.string(forKey: "llmProvider") ?? ""
        let modelOverride = UserDefaults.standard.string(forKey: "llmModelOverride") ?? ""
        return LLMClient(
            provider: LLMProvider(rawValue: providerRaw) ?? .deepseek,
            modelOverride: modelOverride,
            apiKey: KeychainStore.read(KeychainStore.apiKeyAccount)
        )
    }

    private struct ResponseFormat: Encodable {
        let type: String
    }

    private struct ChatRequest: Encodable {
        let model: String
        let messages: [LLMMessage]
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

    /// Sends a full message list and returns the raw text of the reply.
    /// Every coach role returns JSON, so JSON mode is always requested.
    func complete(messages: [LLMMessage], maxTokens: Int = 4096) async throws -> String {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw LLMError.missingAPIKey }

        let model = modelOverride.trimmingCharacters(in: .whitespaces).isEmpty
            ? provider.defaultModel
            : modelOverride

        var request = URLRequest(url: provider.chatCompletionsURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(ChatRequest(
            model: model,
            messages: messages,
            temperature: 0.7,
            max_tokens: maxTokens,
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

    /// Convenience for single-turn system + user calls.
    func complete(system: String, user: String, maxTokens: Int = 4096) async throws -> String {
        try await complete(messages: [.system(system), .user(user)], maxTokens: maxTokens)
    }
}
