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
    case storyboardPlanning
    case creativeGeneration
    case creativeAudit

    var route: ModelRoute {
        switch self {
        case .characterNaming, .chapterAnalysis, .episodeSemanticAudit,
             .seriesQualityAudit, .bookAnalysisExtract, .bookAnalysisDigest,
             .creativeAudit:
            .flash
        default:
            .primary
        }
    }

    /// Explicit output budgets prevent OpenAI-compatible providers from applying
    /// a small provider default and cutting a structured response before its
    /// closing braces. Concise extraction and audit nodes need less room than
    /// generation nodes, which also keeps BYOK cost bounded.
    var outputTokenLimit: Int {
        switch self {
        case .characterNaming, .chapterAnalysis, .episodeSemanticAudit,
             .seriesQualityAudit, .creativeAudit:
            4_096
        default:
            8_192
        }
    }

    func resolvedReasoningEffort(configured: String) -> String {
        route == .flash ? "low" : configured
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
        let reasoningEffort = stage.resolvedReasoningEffort(configured: settings.reasoningEffort)
        if Self.prefersChatStructuredOutput(baseURL: settings.baseURL) {
            return try await chatStructured(
                model: model,
                instructions: instructions,
                input: input,
                name: name,
                schema: schema,
                outputTokenLimit: stage.outputTokenLimit,
                reasoningEffort: reasoningEffort
            )
        }
        let payload = try makeResponsesPayload(
            model: model,
            instructions: instructions,
            input: input,
            name: name,
            schema: schema,
            strict: true,
            outputTokenLimit: stage.outputTokenLimit,
            reasoningEffort: reasoningEffort
        )
        do {
            let data = try await post(endpoint: "responses", payload: payload)
            return try decodeOutput(data)
        } catch let error as ModelError where isResponsesEndpointUnavailable(error) {
            return try await chatStructured(
                model: model,
                instructions: instructions,
                input: input,
                name: name,
                schema: schema,
                outputTokenLimit: stage.outputTokenLimit,
                reasoningEffort: reasoningEffort
            )
        } catch let error as ModelError where shouldUseCompatibilityFallback(error) {
            return try await compatibilityStructured(
                model: model,
                instructions: instructions,
                input: input,
                name: name,
                schema: schema,
                outputTokenLimit: stage.outputTokenLimit,
                reasoningEffort: reasoningEffort
            )
        }
    }

    func generateImage(prompt: String, model: String) async throws -> Data {
        guard settings.hasEndpointConsent else {
            throw ModelError.endpointConsentRequired(settings.endpointHost)
        }
        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedModel.isEmpty else { throw ModelError.invalidJSON("未配置图片模型") }
        let payload: [String: Any] = [
            "model": trimmedModel,
            "prompt": prompt,
            "size": "1024x1536",
            "response_format": "b64_json",
        ]
        let data: Data
        do {
            data = try await post(endpoint: "images/generations", payload: payload)
        } catch let ModelError.server(status, _) where status == 400 || status == 422 {
            data = try await post(
                endpoint: "images/generations",
                payload: ["model": trimmedModel, "prompt": prompt]
            )
        }
        guard
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let item = (object["data"] as? [[String: Any]])?.first
        else { throw ModelError.missingOutput }
        if let encoded = item["b64_json"] as? String,
           let imageData = Data(base64Encoded: encoded) {
            return imageData
        }
        if let value = item["url"] as? String, let url = URL(string: value) {
            do {
                let (imageData, response) = try await URLSession.shared.data(from: url)
                guard let http = response as? HTTPURLResponse,
                      (200..<300).contains(http.statusCode), !imageData.isEmpty
                else { throw ModelError.missingOutput }
                return imageData
            } catch let error as ModelError {
                throw error
            } catch {
                throw ModelError.transport(error.localizedDescription)
            }
        }
        throw ModelError.missingOutput
    }

    func synthesizeSpeech(text: String, model: String, voice: String) async throws -> Data {
        guard settings.hasEndpointConsent else {
            throw ModelError.endpointConsentRequired(settings.endpointHost)
        }
        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedModel.isEmpty else { throw ModelError.invalidJSON("未配置语音模型") }
        let payload: [String: Any] = [
            "model": trimmedModel,
            "voice": voice.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "alloy" : voice,
            "input": String(text.prefix(4_000)),
            "response_format": "mp3",
        ]
        let data = try await post(endpoint: "audio/speech", payload: payload)
        guard !data.isEmpty else { throw ModelError.missingOutput }
        return data
    }

    private func compatibilityStructured<T: Decodable & Sendable>(
        model: String,
        instructions: String,
        input: String,
        name: String,
        schema: [String: Any],
        outputTokenLimit: Int,
        reasoningEffort: String
    ) async throws -> T {
        let schemaData = try JSONSerialization.data(withJSONObject: schema, options: [.sortedKeys])
        let schemaText = String(data: schemaData, encoding: .utf8) ?? "{}"
        let compatibilityInstruction = """
        \(instructions)

        Return exactly one JSON object with no Markdown code fence and no explanation. The object must conform to this JSON Schema:
        \(schemaText)
        """

        do {
            let payload = try makeResponsesPayload(
                model: model,
                instructions: compatibilityInstruction,
                input: input,
                name: name,
                schema: schema,
                strict: false,
                outputTokenLimit: outputTokenLimit,
                reasoningEffort: reasoningEffort
            )
            let data = try await post(endpoint: "responses", payload: payload)
            return try decodeOutput(data)
        } catch let error as ModelError where shouldUseChatFallback(error) {
            return try await chatStructured(
                model: model,
                instructions: instructions,
                input: input,
                name: name,
                schema: schema,
                outputTokenLimit: outputTokenLimit,
                reasoningEffort: reasoningEffort
            )
        }
    }

    private func chatStructured<T: Decodable & Sendable>(
        model: String,
        instructions: String,
        input: String,
        name: String,
        schema: [String: Any],
        outputTokenLimit: Int,
        reasoningEffort: String
    ) async throws -> T {
        let isOpenRouter = Self.prefersChatStructuredOutput(baseURL: settings.baseURL)
        do {
            let payload = try Self.makeChatPayload(
                model: model,
                instructions: instructions,
                input: input,
                name: name,
                schema: schema,
                outputTokenLimit: outputTokenLimit,
                reasoningEffort: reasoningEffort,
                isOpenRouter: isOpenRouter,
                strict: true
            )
            let data = try await post(endpoint: "chat/completions", payload: payload)
            return try decodeOutput(data)
        } catch let error as ModelError where shouldUseCompatibilityFallback(error) {
            let payload = try Self.makeChatPayload(
                model: model,
                instructions: instructions,
                input: input,
                name: name,
                schema: schema,
                outputTokenLimit: outputTokenLimit,
                reasoningEffort: reasoningEffort,
                isOpenRouter: false,
                strict: false
            )
            let data = try await post(endpoint: "chat/completions", payload: payload)
            return try decodeOutput(data)
        }
    }

    static func prefersChatStructuredOutput(baseURL: String) -> Bool {
        guard let host = URL(string: baseURL)?.host?.lowercased() else { return false }
        return host == "openrouter.ai" || host.hasSuffix(".openrouter.ai")
    }

    static func makeChatPayload(
        model: String,
        instructions: String,
        input: String,
        name: String,
        schema: [String: Any],
        outputTokenLimit: Int,
        reasoningEffort: String,
        isOpenRouter: Bool,
        strict: Bool
    ) throws -> [String: Any] {
        let schemaData = try JSONSerialization.data(withJSONObject: schema, options: [.sortedKeys])
        let schemaText = String(data: schemaData, encoding: .utf8) ?? "{}"
        let chatInstructions = strict
            ? instructions + "\n\nReturn exactly one JSON object with no Markdown code fence and no explanation."
            : """
              \(instructions)

              Return exactly one JSON object with no Markdown code fence and no explanation. The object must conform to this JSON Schema:
              \(schemaText)
              """
        var payload: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": chatInstructions],
                ["role": "user", "content": input],
            ],
            "temperature": 0.2,
        ]
        if isOpenRouter {
            payload["max_completion_tokens"] = outputTokenLimit
            payload["provider"] = ["require_parameters": true]
            payload["plugins"] = [["id": "response-healing"]]
            if !reasoningEffort.isEmpty, reasoningEffort != "none" {
                payload["reasoning"] = ["effort": reasoningEffort]
            }
        } else {
            payload["max_tokens"] = outputTokenLimit
        }
        if strict {
            payload["response_format"] = [
                "type": "json_schema",
                "json_schema": [
                    "name": name,
                    "strict": true,
                    "schema": schema,
                ],
            ]
        }
        return payload
    }

    private func makeResponsesPayload(
        model: String,
        instructions: String,
        input: String,
        name: String,
        schema: [String: Any],
        strict: Bool,
        outputTokenLimit: Int,
        reasoningEffort: String
    ) throws -> [String: Any] {
        var payload: [String: Any] = [
            "model": model,
            "instructions": instructions,
            "input": input,
            "store": false,
            "max_output_tokens": outputTokenLimit,
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
        if !reasoningEffort.isEmpty {
            payload["reasoning"] = ["effort": reasoningEffort]
        }
        return payload
    }

    private func post(endpoint: String, payload: [String: Any]) async throws -> Data {
        guard let url = Self.endpointURL(baseURL: settings.baseURL, endpoint: endpoint) else {
            throw ModelError.invalidURL
        }
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
                var message = Self.serverMessage(data)
                if http.statusCode == 405 {
                    message += " POST \(Self.displayEndpoint(url)) is not accepted. Enter the OpenAI-compatible API root URL, not a dashboard or model page URL."
                }
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
        try Self.decodeResponseData(data)
    }

    static func decodeResponseData<T: Decodable & Sendable>(_ data: Data) throws -> T {
        let object = try JSONSerialization.jsonObject(with: data)
        let text = Self.outputText(from: object)
        guard let text, !text.isEmpty else {
            let direct = try? JSONDecoder.scriptForge.decode(T.self, from: data)
            if let direct { return direct }
            let metadata = Self.safeTerminationMetadata(from: object)
            if !metadata.isEmpty {
                throw ModelError.invalidJSON(
                    "未返回可见正文；推理可能耗尽完成预算 [\(metadata)]"
                )
            }
            throw ModelError.missingOutput
        }
        do {
            return try Self.decodeStructuredText(text)
        } catch let ModelError.invalidJSON(detail) {
            let metadata = Self.safeTerminationMetadata(from: object)
            guard !metadata.isEmpty else { throw ModelError.invalidJSON(detail) }
            throw ModelError.invalidJSON("\(detail) [\(metadata)]")
        }
    }

    static func decodeStructuredText<T: Decodable & Sendable>(_ text: String) throws -> T {
        var lastSchemaError: Error?
        for candidate in jsonCandidates(from: text) {
            guard let data = candidate.data(using: .utf8) else { continue }
            guard (try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])) != nil else {
                continue
            }
            do {
                return try JSONDecoder.scriptForge.decode(T.self, from: data)
            } catch {
                lastSchemaError = error
            }
        }
        if let lastSchemaError {
            throw ModelError.invalidJSON(decodeMessage(lastSchemaError))
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let detail = appearsTruncatedJSON(trimmed)
            ? "响应 JSON 可能被截断；请缩小本次任务或单步重试"
            : "响应不是有效 JSON；请单步重试"
        throw ModelError.invalidJSON(detail)
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

    private func isResponsesEndpointUnavailable(_ error: ModelError) -> Bool {
        switch error {
        case let .server(status, _): [404, 405, 501].contains(status)
        default: false
        }
    }

    private func shouldUseChatFallback(_ error: ModelError) -> Bool {
        switch error {
        case let .server(status, _): [404, 405, 501].contains(status)
        default: false
        }
    }

    static func endpointURL(baseURL: String, endpoint: String) -> URL? {
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              components.host != nil else { return nil }

        var basePath = components.path
        while basePath.count > 1 && basePath.hasSuffix("/") { basePath.removeLast() }
        let knownEndpointSuffixes = [
            "/chat/completions",
            "/images/generations",
            "/audio/speech",
            "/responses",
        ]
        if let suffix = knownEndpointSuffixes.first(where: { basePath.lowercased().hasSuffix($0) }) {
            basePath.removeLast(suffix.count)
        }
        while basePath.count > 1 && basePath.hasSuffix("/") { basePath.removeLast() }
        let normalizedEndpoint = endpoint.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.path = (basePath == "/" ? "" : basePath) + "/" + normalizedEndpoint
        return components.url
    }

    private static func displayEndpoint(_ url: URL) -> String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url.path
        }
        components.query = nil
        components.fragment = nil
        return components.url?.absoluteString ?? url.path
    }

    private static func outputText(from object: Any) -> String? {
        guard let root = object as? [String: Any] else { return nil }
        if let value = root["output_text"] as? String { return value }
        if let value = jsonString(root["output_text"]) { return value }
        if let choices = root["choices"] as? [[String: Any]],
           let message = choices.first?["message"] as? [String: Any] {
            if let content = message["content"] as? String { return content }
            if let content = message["content"] as? [[String: Any]] {
                let value = content.compactMap { item in
                    item["text"] as? String
                        ?? item["value"] as? String
                        ?? jsonString(item["json"])
                }.joined()
                if !value.isEmpty { return value }
            }
            if let content = jsonString(message["content"]) { return content }
            if let arguments = (message["function_call"] as? [String: Any])?["arguments"] as? String {
                return arguments
            }
            if let toolCalls = message["tool_calls"] as? [[String: Any]],
               let arguments = (toolCalls.first?["function"] as? [String: Any])?["arguments"] as? String {
                return arguments
            }
        }
        guard let output = root["output"] as? [[String: Any]] else { return nil }
        return output.compactMap { item in
            if let arguments = item["arguments"] as? String { return arguments }
            return (item["content"] as? [[String: Any]])?.compactMap { content in
                content["text"] as? String
                    ?? (content["value"] as? String)
                    ?? jsonString(content["json"])
            }.joined()
        }.joined()
    }

    private static func jsonString(_ value: Any?) -> String? {
        guard let value, JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value),
              let string = String(data: data, encoding: .utf8) else { return nil }
        return string
    }

    private static func safeTerminationMetadata(from object: Any) -> String {
        guard let root = object as? [String: Any] else { return "" }
        var values: [String] = []
        if let status = root["status"] as? String {
            values.append("status=\(status)")
        }
        if let reason = (root["incomplete_details"] as? [String: Any])?["reason"] as? String {
            values.append("reason=\(reason)")
        }
        if let reason = (root["choices"] as? [[String: Any]])?.first?["finish_reason"] as? String {
            values.append("finish_reason=\(reason)")
        }
        if let usage = root["usage"] as? [String: Any] {
            for key in ["completion_tokens", "output_tokens"] {
                if let count = usage[key] as? NSNumber {
                    values.append("\(key)=\(count.intValue)")
                }
            }
            if let details = usage["completion_tokens_details"] as? [String: Any],
               let count = details["reasoning_tokens"] as? NSNumber {
                values.append("reasoning_tokens=\(count.intValue)")
            }
        }
        return values.joined(separator: ", ")
    }

    private static func jsonCandidates(from value: String) -> [String] {
        let base = stripCodeFence(value)
            .replacingOccurrences(of: "\u{FEFF}", with: "")
            .replacingOccurrences(of: "\u{200B}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        var values: [String] = []
        appendCandidate(base, to: &values)
        if let data = base.data(using: .utf8),
           let decoded = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
           let string = decoded as? String {
            appendCandidate(stripCodeFence(string), to: &values)
        }
        for candidate in Array(values) {
            appendCandidate(extractJSONObject(candidate), to: &values)
            appendCandidate(normalizeLooseJSON(candidate), to: &values)
            appendCandidate(normalizeLooseJSON(extractJSONObject(candidate)), to: &values)
        }
        return values
    }

    private static func appendCandidate(_ value: String, to values: inout [String]) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !values.contains(trimmed) else { return }
        values.append(trimmed)
    }

    private static func stripCodeFence(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(
            of: #"^```(?:json|JSON)?\s*|\s*```$"#,
            with: "",
            options: .regularExpression
        )
    }

    private static func normalizeLooseJSON(_ value: String) -> String {
        var output = ""
        var inString = false
        var escaped = false
        var index = value.startIndex
        while index < value.endIndex {
            let character = value[index]
            if escaped {
                output.append(character)
                escaped = false
            } else if character == "\\" && inString {
                output.append(character)
                escaped = true
            } else if character == "\"" {
                output.append(character)
                inString.toggle()
            } else if inString, character == "\n" {
                output.append("\\n")
            } else if inString, character == "\r" {
                output.append("\\r")
            } else if inString, character == "\t" {
                output.append("\\t")
            } else if !inString, character == "," {
                var next = value.index(after: index)
                while next < value.endIndex, value[next].isWhitespace {
                    next = value.index(after: next)
                }
                if next < value.endIndex, value[next] == "}" || value[next] == "]" {
                    index = value.index(after: index)
                    continue
                }
                output.append(character)
            } else {
                output.append(character)
            }
            index = value.index(after: index)
        }
        return output
    }

    private static func appearsTruncatedJSON(_ value: String) -> Bool {
        guard let start = value.firstIndex(where: { $0 == "{" || $0 == "[" }) else { return false }
        var stack: [Character] = []
        var inString = false
        var escaped = false
        for character in value[start...] {
            if escaped { escaped = false; continue }
            if character == "\\", inString { escaped = true; continue }
            if character == "\"" { inString.toggle(); continue }
            guard !inString else { continue }
            if character == "{" || character == "[" { stack.append(character) }
            if character == "}" || character == "]" { _ = stack.popLast() }
        }
        return inString || !stack.isEmpty
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
