import Foundation

final class ClaudeRunner: @unchecked Sendable {
    static let modelID = "claude-sonnet-4-6"
    private let lock = NSLock()
    private let session: URLSession
    private let timeout: TimeInterval
    private var task: URLSessionDataTask?
    private var cancelled = false

    init(session: URLSession? = nil, timeout: TimeInterval = 600) {
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.urlCache = nil
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            configuration.timeoutIntervalForRequest = timeout
            configuration.timeoutIntervalForResource = timeout
            self.session = URLSession(configuration: configuration)
        }
        self.timeout = timeout
    }

    func cancel() {
        lock.lock()
        cancelled = true
        let active = task
        lock.unlock()
        active?.cancel()
    }

    func execute(_ modelRequest: ModelRequest, apiKey: String, workspaceID: String? = nil, onUsage: (TokenUsage) -> Void = { _ in }) throws -> Data {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AppError.message("Add your Claude API key in Settings before summarizing. Your clipboard is unchanged.")
        }

        let prompt = modelRequest.instructions
        let schemaData = try Data(contentsOf: modelRequest.schema)
        let schema = try JSONSerialization.jsonObject(with: schemaData)
        let body: [String: Any] = [
            "model": Self.modelID,
            "max_tokens": 8192,
            "system": prompt,
            "messages": [["role": "user", "content": modelRequest.payload]],
            "output_config": ["format": ["type": "json_schema", "schema": schema]]
        ]
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        if let workspaceID { request.setValue(workspaceID, forHTTPHeaderField: "anthropic-workspace-id") }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let completed = DispatchSemaphore(value: 0)
        var data: Data?
        var response: URLResponse?
        var networkError: Error?
        let active = session.dataTask(with: request) { receivedData, receivedResponse, error in
            data = receivedData
            response = receivedResponse
            networkError = error
            completed.signal()
        }
        lock.lock()
        if cancelled {
            lock.unlock()
            throw CancellationError()
        }
        task = active
        lock.unlock()
        defer { lock.lock(); task = nil; lock.unlock() }
        active.resume()
        guard completed.wait(timeout: .now() + timeout) == .success else {
            active.cancel()
            lock.lock(); let wasCancelled = cancelled; lock.unlock()
            if wasCancelled { throw CancellationError() }
            throw AppError.message("Claude took longer than 10 minutes. Your clipboard is unchanged. Try again.")
        }
        lock.lock(); let wasCancelled = cancelled; lock.unlock()
        if wasCancelled { throw CancellationError() }
        if networkError != nil {
            throw AppError.message("Claude couldn't connect. Check your internet connection and try again. Your clipboard is unchanged.")
        }
        guard let response = response as? HTTPURLResponse, let data else {
            throw AppError.message("Claude returned no response. Your clipboard is unchanged. Try again.")
        }
        switch response.statusCode {
        case 200: break
        case 400 where ClaudeKeyVerifier.workspaceIDError(in: data):
            throw AppError.message("Claude needs a valid workspace ID for this key. Add it in Settings and try again. Your clipboard is unchanged.")
        case 401:
            throw AppError.message("Anthropic returned 401: the saved Claude API key is invalid, expired, or revoked. Create a new API key in Claude Console and replace it in Settings. Your transcript and clipboard are unchanged.")
        case 403:
            throw AppError.message("Anthropic returned 403: the saved API key lacks permission for this request. Check its workspace and model access in Claude Console. Your transcript and clipboard are unchanged.")
        case 402:
            throw AppError.message("Your Anthropic API account needs billing or credits. Check your Anthropic account and try again. Your clipboard is unchanged.")
        case 429:
            throw AppError.message("Claude is rate limiting requests. Wait a little and try again. Your clipboard is unchanged.")
        default:
            throw AppError.message("Claude couldn't complete the summary (HTTP \(response.statusCode)). Your clipboard is unchanged. Try again.")
        }
        guard data.count <= 2_000_000,
              let envelope = try? JSONDecoder().decode(MessageResponse.self, from: data),
              envelope.stop_reason != "max_tokens",
              let text = envelope.content.first(where: { $0.type == "text" })?.text else {
            throw AppError.message("Claude didn't return a complete, readable summary. Your clipboard is unchanged. Try again.")
        }
        if let usage = envelope.usage?.tokens { onUsage(usage) }
        return Data(text.utf8)
    }
}

private struct MessageResponse: Decodable {
    struct Usage: Decodable {
        let input_tokens: Int
        let output_tokens: Int
        let cache_creation_input_tokens: Int?
        let cache_read_input_tokens: Int?
        var tokens: TokenUsage? {
            guard let base = TokenUsage(input: input_tokens, output: output_tokens),
                  let cached = TokenUsage(input: cache_read_input_tokens ?? 0, output: 0),
                  let created = TokenUsage(input: cache_creation_input_tokens ?? 0, output: 0) else { return nil }
            return base.adding(cached)?.adding(created)
        }
    }
    struct Content: Decodable {
        let type: String
        let text: String?
    }
    let content: [Content]
    let stop_reason: String?
    let usage: Usage?

    private enum CodingKeys: String, CodingKey { case content, stop_reason, usage }
    init(from decoder: Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        content = try fields.decode([Content].self, forKey: .content)
        stop_reason = try fields.decodeIfPresent(String.self, forKey: .stop_reason)
        // Optional usage must never prevent a valid summary from being displayed.
        usage = try? fields.decode(Usage.self, forKey: .usage)
    }
}
