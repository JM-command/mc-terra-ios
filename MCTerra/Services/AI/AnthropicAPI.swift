//
//  AnthropicAPI.swift
//  MCTerra
//
//  Created by Jaime Coelho on 05.06.2026.
//
//  Minimal client for the Anthropic Messages API, routed through the proxy.
//  Covers exactly what the command bar needs: a system prompt, a tools list,
//  a running message array, and the tool-use loop. No streaming (commands are
//  short — a single awaited response is simpler and good enough).
//

import Foundation

// MARK: - JSON value

/// A loosely-typed JSON value, used for tool `input` (arbitrary shape decoded
/// from Claude) and tool `input_schema` (arbitrary shape we send up).
enum JSONValue: Codable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() {
            self = .null
        } else if let b = try? c.decode(Bool.self) {
            self = .bool(b)
        } else if let n = try? c.decode(Double.self) {
            self = .number(n)
        } else if let s = try? c.decode(String.self) {
            self = .string(s)
        } else if let o = try? c.decode([String: JSONValue].self) {
            self = .object(o)
        } else if let a = try? c.decode([JSONValue].self) {
            self = .array(a)
        } else {
            self = .null
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let s): try c.encode(s)
        case .number(let n): try c.encode(n)
        case .bool(let b): try c.encode(b)
        case .object(let o): try c.encode(o)
        case .array(let a): try c.encode(a)
        case .null: try c.encodeNil()
        }
    }

    /// Builds a JSONValue from a plain `[String: Any]` / `[Any]` literal, so tool
    /// schemas can be authored as ordinary Swift dictionaries.
    static func from(_ any: Any) -> JSONValue {
        let data = (try? JSONSerialization.data(withJSONObject: any)) ?? Data("null".utf8)
        return (try? JSONDecoder().decode(JSONValue.self, from: data)) ?? .null
    }

    // Convenience accessors used by the tool executor.
    var stringValue: String? { if case .string(let s) = self { return s }; return nil }
    var doubleValue: Double? {
        switch self {
        case .number(let n): return n
        case .string(let s): return Double(s)
        default: return nil
        }
    }
    var intValue: Int? { doubleValue.map { Int($0) } }
    var arrayValue: [JSONValue]? {
        if case .array(let a) = self { return a }
        return nil
    }
    /// The array's elements as strings (drops non-strings).
    var stringArray: [String]? { arrayValue?.compactMap(\.stringValue) }
    subscript(key: String) -> JSONValue? {
        if case .object(let o) = self { return o[key] }
        return nil
    }
}

// MARK: - Content blocks & messages

/// One content block inside a message. The same struct round-trips text blocks,
/// `tool_use` blocks (decoded from Claude, echoed back), and `tool_result`
/// blocks (sent up). Optional fields are omitted when nil by Swift's synthesized
/// `encodeIfPresent`, so each block only carries the keys its `type` needs.
struct ContentBlock: Codable {
    let type: String
    var text: String?
    // tool_use (from assistant)
    var id: String?
    var name: String?
    var input: JSONValue?
    // tool_result (to assistant)
    var toolUseId: String?
    var content: String?

    enum CodingKeys: String, CodingKey {
        case type, text, id, name, input
        case toolUseId = "tool_use_id"
        case content
    }

    static func text(_ s: String) -> ContentBlock { ContentBlock(type: "text", text: s) }
    static func toolResult(id: String, _ s: String) -> ContentBlock {
        ContentBlock(type: "tool_result", toolUseId: id, content: s)
    }
}

/// A message's content: either a plain string (typical user turn) or an array of
/// blocks (assistant turns we echo back, and tool_result turns we send).
enum MessageContent: Codable {
    case text(String)
    case blocks([ContentBlock])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let s = try? c.decode(String.self) { self = .text(s) }
        else { self = .blocks(try c.decode([ContentBlock].self)) }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .text(let s): try c.encode(s)
        case .blocks(let b): try c.encode(b)
        }
    }
}

struct Message: Codable {
    let role: String  // "user" | "assistant"
    let content: MessageContent

    static func user(_ text: String) -> Message { Message(role: "user", content: .text(text)) }
    static func assistant(_ blocks: [ContentBlock]) -> Message { Message(role: "assistant", content: .blocks(blocks)) }
    static func toolResults(_ blocks: [ContentBlock]) -> Message { Message(role: "user", content: .blocks(blocks)) }
}

/// A tool definition Claude can call.
struct Tool: Codable {
    let name: String
    let description: String
    let inputSchema: JSONValue

    enum CodingKeys: String, CodingKey {
        case name, description
        case inputSchema = "input_schema"
    }
}

// MARK: - Request / response

private struct MessagesRequest: Codable {
    let model: String
    let maxTokens: Int
    let system: String
    let tools: [Tool]
    let messages: [Message]

    enum CodingKeys: String, CodingKey {
        case model, system, tools, messages
        case maxTokens = "max_tokens"
    }
}

/// Just the parts of the response the loop reads.
struct MessagesResponse: Codable {
    let content: [ContentBlock]
    let stopReason: String?

    enum CodingKeys: String, CodingKey {
        case content
        case stopReason = "stop_reason"
    }
}

// MARK: - Client

enum AnthropicError: LocalizedError {
    case http(Int, String)
    case decoding

    var errorDescription: String? {
        switch self {
        case .http(let code, _): return "Erreur serveur (\(code))."
        case .decoding: return "Réponse illisible."
        }
    }
}

/// Sends one Messages API call through the proxy and returns the parsed response.
struct AnthropicClient {
    static let shared = AnthropicClient()

    func send(system: String, tools: [Tool], messages: [Message]) async throws -> MessagesResponse {
        let body = MessagesRequest(
            model: AIConfig.model,
            maxTokens: AIConfig.maxTokens,
            system: system,
            tools: tools,
            messages: messages
        )

        var request = URLRequest(url: AIConfig.messagesURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(AIConfig.appToken, forHTTPHeaderField: "x-app-token")
        request.httpBody = try JSONEncoder().encode(body)
        request.timeoutInterval = 60

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AnthropicError.decoding }
        guard (200..<300).contains(http.statusCode) else {
            throw AnthropicError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        guard let decoded = try? JSONDecoder().decode(MessagesResponse.self, from: data) else {
            throw AnthropicError.decoding
        }
        return decoded
    }
}
