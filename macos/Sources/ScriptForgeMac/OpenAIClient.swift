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
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(insert as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.unhandled(status) }
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
        guard status == errSecSuccess, let data = result as? Data else { return nil }
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
        case let .unhandled(status): "Keychain 错误：\(status)"
        }
    }
}

enum ModelRoute: String, Codable, Hashable, Sendable {
    case primary
    case flash
}

enum ModelStage: String, CaseIterable, Sendable {
    case characterNaming
    case chapterAnalysis
    case storyBible
    case episodeOutline
    case episodeDraft
    case episodeSemanticAudit
    case episodeRepair
    case seriesQualityAudit
    case seriesQualityRepair
    case bookAnalysisExtract
    case bookAnalysisDigest
    case bookAnalysisStructure
    case bookAnalysisCharacters
    case bookAnalysisCommercial
    case bookAnalysisRevision

    var route: ModelRoute {
        switch self {
        case .characterNaming, .chapterAnalysis, .episodeSemanticAudit,
             .seriesQualityAudit, .bookAnalysisExtract, .bookAnalysisDigest:
            .flash
        default:
            .primary
        }
    }
}

enum ModelError: LocalizedError {
    case invalidURL
    case transport(String)
    case server(Int, String)
    case missingOutput
    case invalidJSON(String)
    case endpointConsentRequired(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            "模型 Base URL 无效"
        case let .transport(message):
            "模型网络请求失败：\(message)"
        case let .server(status, message):
            "模型请求失败（HTTP \(status)）：\(message)"
        case .missingOutput:
            "模型没有返回可读取的文本"
        case let .invalidJSON(message):
            "模型 JSON 结构不完整：\(message)"
        case let .endpointConsentRequired(host):
            "请先在模型设置中确认允许将所选小说内容发送到 \(host)"
        }
    }
}

struct LLMClient: Sendable {
    let settings: ModelSettings
    let apiKey: String

    func structured<T: Decodable & Sendable>(
        stage: ModelStage,
        instructions: String,
        input: String,
        name: String,
        schema: [String: Any]
    ) async throws -> T {
        guard settings.hasEndpointConsent else {
            throw ModelError.endpointConsentRequired(settings.endpointHost)
        }
        let model = stage.route == .flash ? settings.flashModel : settings.primaryModel
        let payload = try makeResponsesPayload(
            model: model,
            instructions: instructions,
            input: input,
            name: name,
            schema: schema,
            strict: true
        )
        do {
            let data = try await post(endpoint: "responses", payload: payload)
            return try decodeOutput(data)
        } catch let error as ModelError where shouldUseCompatibilityFallback(error) {
            return try await compatibilityStructured(
                model: model,
                instructions: instructions,
                input: input,
                name: name,
                schema: schema
            )
        }
    }

    private func compatibilityStructured<T: Decodable & Sendable>(
        model: String,
        instructions: String,
        input: String,
        name: String,
        schema: [String: Any]
    ) async throws -> T {
        let schemaData = try JSONSerialization.data(withJSONObject: schema, options: [.sortedKeys])
        let schemaText = String(data: schemaData, encoding: .utf8) ?? "{}"
        let compatibilityInstruction = """
        \(instructions)

        只返回一个 JSON 对象，不要 Markdown 代码围栏，不要解释。对象必须符合以下 JSON Schema：
        \(schemaText)
        """

        do {
            let payload = try makeResponsesPayload(
                model: model,
                instructions: compatibilityInstruction,
                input: input,
                name: name,
                schema: schema,
                strict: false
            )
            let data = try await post(endpoint: "responses", payload: payload)
            return try decodeOutput(data)
        } catch let error as ModelError where shouldUseChatFallback(error) {
            let chatPayload: [String: Any] = [
                "model": model,
                "messages": [
                    ["role": "system", "content": compatibilityInstruction],
                    ["role": "user", "content": input],
                ],
                "temperature": 0.2,
            ]
            let data = try await post(endpoint: "chat/completions", payload: chatPayload)
            return try decodeOutput(data)
        }
    }

    private func makeResponsesPayload(
        model: String,
        instructions: String,
        input: String,
        name: String,
        schema: [String: Any],
        strict: Bool
    ) throws -> [String: Any] {
        var payload: [String: Any] = [
            "model": model,
            "instructions": instructions,
            "input": input,
            "store": false,
        ]
        if strict {
            payload["text"] = [
                "format": [
                    "type": "json_schema",
                    "name": name,
                    "strict": true,
                    "schema": schema,
                ],
            ]
        }
        if !settings.reasoningEffort.isEmpty {
            payload["reasoning"] = ["effort": settings.reasoningEffort]
        }
        return payload
    }

    private func post(endpoint: String, payload: [String: Any]) async throws -> Data {
        let trimmed = settings.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(trimmed)/\(endpoint)") else { throw ModelError.invalidURL }
        let body: Data
        do {
            body = try JSONSerialization.data(withJSONObject: payload)
        } catch {
            throw ModelError.invalidJSON(error.localizedDescription)
        }

        var lastError: Error?
        for attempt in 0..<3 {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.timeoutInterval = 240
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            request.httpBody = body
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse else { throw ModelError.missingOutput }
                if (200..<300).contains(http.statusCode) { return data }
                let message = Self.serverMessage(data)
                if (http.statusCode == 429 || http.statusCode >= 500), attempt < 2 {
                    try await Task.sleep(for: .milliseconds(500 * (attempt + 1) * (attempt + 1)))
                    continue
                }
                throw ModelError.server(http.statusCode, message)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastError = error
                if let modelError = error as? ModelError { throw modelError }
                if attempt < 2 {
                    try await Task.sleep(for: .milliseconds(500 * (attempt + 1) * (attempt + 1)))
                }
            }
        }
        throw ModelError.transport(lastError?.localizedDescription ?? "未知错误")
    }

    private func decodeOutput<T: Decodable & Sendable>(_ data: Data) throws -> T {
        let object = try JSONSerialization.jsonObject(with: data)
        let text = Self.outputText(from: object)
        guard let text, !text.isEmpty else {
            let direct = try? JSONDecoder.scriptForge.decode(T.self, from: data)
            if let direct { return direct }
            throw ModelError.missingOutput
        }
        let cleaned = Self.extractJSONObject(text)
        guard let jsonData = cleaned.data(using: .utf8) else {
            throw ModelError.invalidJSON("响应不是 UTF-8 JSON")
        }
        do {
            return try JSONDecoder.scriptForge.decode(T.self, from: jsonData)
        } catch {
            throw ModelError.invalidJSON(Self.decodeMessage(error))
        }
    }

    private func shouldUseCompatibilityFallback(_ error: ModelError) -> Bool {
        switch error {
        case let .server(status, message):
            let lower = message.lowercased()
            if [404, 405, 501].contains(status) { return true }
            return [400, 415, 422].contains(status)
                && (lower.contains("response_format")
                    || lower.contains("json_schema")
                    || lower.contains("text.format")
                    || lower.contains("unavailable")
                    || lower.contains("unsupported"))
        default:
            return false
        }
    }

    private func shouldUseChatFallback(_ error: ModelError) -> Bool {
        switch error {
        case let .server(status, _): [404, 405, 501].contains(status)
        default: false
        }
    }

    private static func outputText(from object: Any) -> String? {
        guard let root = object as? [String: Any] else { return nil }
        if let value = root["output_text"] as? String { return value }
        if let choices = root["choices"] as? [[String: Any]],
           let message = choices.first?["message"] as? [String: Any] {
            if let content = message["content"] as? String { return content }
            if let content = message["content"] as? [[String: Any]] {
                return content.compactMap { $0["text"] as? String }.joined()
            }
        }
        guard let output = root["output"] as? [[String: Any]] else { return nil }
        return output.compactMap { item in
            (item["content"] as? [[String: Any]])?.compactMap { content in
                content["text"] as? String
                    ?? (content["value"] as? String)
            }.joined()
        }.joined()
    }

    private static func extractJSONObject(_ value: String) -> String {
        var cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("```") {
            cleaned = cleaned.replacingOccurrences(
                of: #"^```(?:json)?\s*|\s*```$"#,
                with: "",
                options: .regularExpression
            )
        }
        guard let start = cleaned.firstIndex(of: "{") else { return cleaned }
        var depth = 0
        var inString = false
        var escaped = false
        var index = start
        while index < cleaned.endIndex {
            let character = cleaned[index]
            if escaped {
                escaped = false
            } else if character == "\\" && inString {
                escaped = true
            } else if character == "\"" {
                inString.toggle()
            } else if !inString {
                if character == "{" { depth += 1 }
                if character == "}" {
                    depth -= 1
                    if depth == 0 { return String(cleaned[start...index]) }
                }
            }
            index = cleaned.index(after: index)
        }
        return cleaned
    }

    private static func serverMessage(_ data: Data) -> String {
        guard
            let object = try? JSONSerialization.jsonObject(with: data),
            let root = object as? [String: Any]
        else { return String(data: data, encoding: .utf8) ?? "未知服务端错误" }
        if let error = root["error"] as? [String: Any] {
            return error["message"] as? String ?? String(describing: error)
        }
        return root["message"] as? String ?? String(data: data, encoding: .utf8) ?? "未知服务端错误"
    }

    private static func decodeMessage(_ error: Error) -> String {
        guard let decoding = error as? DecodingError else { return error.localizedDescription }
        switch decoding {
        case let .keyNotFound(key, context):
            return "\(path(context.codingPath)).\(key.stringValue) 缺失"
        case let .valueNotFound(_, context):
            return "\(path(context.codingPath)) 缺少值"
        case let .typeMismatch(_, context):
            return "\(path(context.codingPath)) 类型错误：\(context.debugDescription)"
        case let .dataCorrupted(context):
            return "\(path(context.codingPath)) 数据损坏：\(context.debugDescription)"
        @unknown default:
            return error.localizedDescription
        }
    }

    private static func path(_ codingPath: [CodingKey]) -> String {
        codingPath.reduce("$") { partial, key in
            if let index = key.intValue { return partial + "[\(index)]" }
            return partial + "." + key.stringValue
        }
    }
}
