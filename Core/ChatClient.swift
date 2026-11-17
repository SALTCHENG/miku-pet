import Foundation

/// 一轮对话
struct ChatTurn {
    let role: String       // "user" / "assistant"
    let content: String
}

enum ChatError: LocalizedError {
    case http(Int)
    case empty
    case offline

    var errorDescription: String? {
        switch self {
        case .http(let c): return "网关返回 HTTP \(c)"
        case .empty:      return "网关没返回内容"
        case .offline:    return "连不上本机网关 127.0.0.1:3425"
        }
    }
}

/// 本机 magpie 网关客户端（免鉴权，走 group/never-stuck 路由组）
final class ChatClient {
    static let shared = ChatClient()

    private let endpoint = URL(string: "http://127.0.0.1:3425/v1/chat/completions")!
    private let model = "group/never-stuck"

    func reply(history: [ChatTurn], system: String, timeout: TimeInterval = 120) async throws -> String {
        var messages: [[String: String]] = []
        if !system.isEmpty {
            messages.append(["role": "system", "content": system])
        }
        for t in history {
            messages.append(["role": t.role, "content": t.content])
        }
        let body: [String: Any] = ["model": model, "messages": messages]

        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = timeout
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: req)
        } catch {
            throw ChatError.offline
        }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw ChatError.http(http.statusCode)
        }
        guard
            let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let choices = obj["choices"] as? [[String: Any]],
            let first = choices.first,
            let msg = first["message"] as? [String: Any],
            let text = msg["content"] as? String
        else { throw ChatError.empty }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { throw ChatError.empty }
        return trimmed
    }
}
