import Foundation
import Security

enum KeychainStore {
    private static let service = "cn.scriptforge.mac"
    private static let account = "model-api-key"

    static func save(apiKey: String) throws {
        let data = Data(apiKey.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        var insert = query
        insert[kSecValueData as String] = data
        let status = SecItemAdd(insert as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.unhandled(status)
        }
    }

    static func load() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard
            status == errSecSuccess,
            let data = result as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func clear() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

enum KeychainError: LocalizedError {
    case unhandled(OSStatus)

    var errorDescription: String? {
        switch self {
        case let .unhandled(status):
            "Keychain 错误：\(status)"
        }
    }
}

struct OpenAIClient {
    let settings: ModelSettings
    let apiKey: String

    func structured<T: Decodable>(
        instructions: String,
        input: String,
        name: String,
        schema: [String: Any]
    ) async throws -> T {
        let base = settings.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(base)/responses") else {
            throw URLError(.badURL)
        }
        let body: [String: Any] = [
            "model": settings.model,
            "instructions": instructions,
            "input": input,
            "store": false,
            "reasoning": ["effort": settings.reasoningEffort],
            "safety_identifier": safetyIdentifier(),
            "text": [
                "format": [
                    "type": "json_schema",
                    "name": name,
                    "strict": true,
                    "schema": schema,
                ],
            ],
        ]
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = Self.apiErrorMessage(data)
            throw ModelError.http(http.statusCode, message)
        }
        let text = try Self.outputText(from: data)
        guard let payload = text.data(using: .utf8) else {
            throw PipelineError.invalidResponse
        }
        return try JSONDecoder().decode(T.self, from: payload)
    }

    private func safetyIdentifier() -> String {
        let defaults = UserDefaults.standard
        if let existing = defaults.string(forKey: "safetyIdentifier") {
            return existing
        }
        let value = "desktop-\(UUID().uuidString.lowercased())"
        defaults.set(value, forKey: "safetyIdentifier")
        return value
    }

    private static func outputText(from data: Data) throws -> String {
        guard
            let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { throw PipelineError.invalidResponse }
        if let direct = object["output_text"] as? String, !direct.isEmpty {
            return direct
        }
        if let output = object["output"] as? [[String: Any]] {
            for item in output {
                guard let content = item["content"] as? [[String: Any]] else { continue }
                if let text = content.first(where: {
                    ($0["type"] as? String) == "output_text"
                })?["text"] as? String {
                    return text
                }
            }
        }
        throw PipelineError.invalidResponse
    }

    private static func apiErrorMessage(_ data: Data) -> String {
        guard
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let error = object["error"] as? [String: Any],
            let message = error["message"] as? String
        else { return "Unknown API error" }
        return message
    }
}

enum ModelError: LocalizedError {
    case http(Int, String)

    var errorDescription: String? {
        switch self {
        case let .http(code, message):
            "模型请求失败（HTTP \(code)）：\(message)"
        }
    }
}
