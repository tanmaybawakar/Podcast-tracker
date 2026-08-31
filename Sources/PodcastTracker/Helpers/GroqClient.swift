import Foundation

enum GroqError: LocalizedError, Equatable {
    case missingKey
    case unauthorized
    case rateLimited(seconds: Int?)
    case modelUnavailable
    case offline
    case malformedResponse
    case server(String)

    var errorDescription: String? {
        switch self {
        case .missingKey: "Add your Groq API key in Settings before generating a summary."
        case .unauthorized: "Groq rejected this API key. Check it in Settings."
        case .rateLimited(let seconds): seconds.map { "Groq is rate-limiting requests. Try again in \($0) seconds." } ?? "Groq is rate-limiting requests. Try again shortly."
        case .modelUnavailable: "The requested Groq model is currently unavailable. Your existing summary is unchanged."
        case .offline: "You appear to be offline. Reconnect and try again."
        case .malformedResponse: "Groq returned an unreadable summary. Try again; your existing summary is unchanged."
        case .server(let message): message
        }
    }
}

struct GroqSummaryPayload: Decodable, Sendable {
    struct Topic: Decodable, Sendable { let title: String; let explanation: String; let timestampSeconds: Double? }
    struct Takeaway: Decodable, Sendable { let title: String; let explanation: String }
    struct Action: Decodable, Sendable { let title: String; let detail: String }
    let brief: String
    let keyTopics: [Topic]
    let majorTakeaways: [Takeaway]
    let actionPlan: [Action]
}

struct GroqTranscriptPayload: Decodable, Sendable {
    struct Segment: Decodable, Sendable { let start: Double; let end: Double?; let text: String }
    let text: String
    let segments: [Segment]?
}

final class GroqClient: @unchecked Sendable {
    static let shared = GroqClient()
    private let baseURL = URL(string: "https://api.groq.com/openai/v1")!
    private let session: URLSession

    init(session: URLSession = .shared) { self.session = session }

    func testConnection(apiKey: String) async throws {
        var request = URLRequest(url: baseURL.appendingPathComponent("models"))
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        _ = try await perform(request)
    }

    func summarize(transcript: String, title: String, apiKey: String) async throws -> GroqSummaryPayload {
        let prompt = """
        You are an expert learning editor. Turn this educational podcast transcript into a compact study artifact that a busy person will actually read.
        Episode: \(title)

        Requirements:
        - brief: a clear 60-second overview, 120-220 words.
        - keyTopics: 4-8 ordered topics; use transcript seconds when they can be inferred, otherwise null.
        - majorTakeaways: 3-6 consequential conclusions with explanation.
        - actionPlan: 3-6 specific, realistic, checkable actions. Never use generic advice such as “learn more.”
        - Do not invent claims beyond the transcript.

        Transcript:
        \(transcript)
        """
        let schema: [String: Any] = [
            "type": "object", "additionalProperties": false,
            "properties": [
                "brief": ["type": "string"],
                "keyTopics": ["type": "array", "items": [
                    "type": "object", "additionalProperties": false,
                    "properties": [
                        "title": ["type": "string"], "explanation": ["type": "string"],
                        "timestampSeconds": ["type": ["number", "null"]]
                    ], "required": ["title", "explanation", "timestampSeconds"]
                ]],
                "majorTakeaways": ["type": "array", "items": [
                    "type": "object", "additionalProperties": false,
                    "properties": ["title": ["type": "string"], "explanation": ["type": "string"]],
                    "required": ["title", "explanation"]
                ]],
                "actionPlan": ["type": "array", "items": [
                    "type": "object", "additionalProperties": false,
                    "properties": ["title": ["type": "string"], "detail": ["type": "string"]],
                    "required": ["title", "detail"]
                ]]
            ],
            "required": ["brief", "keyTopics", "majorTakeaways", "actionPlan"]
        ]
        let body: [String: Any] = [
            "model": "openai/gpt-oss-120b",
            "messages": [["role": "user", "content": prompt]],
            "temperature": 0.2,
            "response_format": [
                "type": "json_schema",
                "json_schema": ["name": "podcast_learning_summary", "strict": true, "schema": schema]
            ]
        ]
        var request = URLRequest(url: baseURL.appendingPathComponent("chat/completions"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let data = try await perform(request)
        struct Response: Decodable { struct Choice: Decodable { struct Message: Decodable { let content: String }; let message: Message }; let choices: [Choice] }
        guard let content = try JSONDecoder().decode(Response.self, from: data).choices.first?.message.content,
              let contentData = content.data(using: .utf8) else { throw GroqError.malformedResponse }
        do { return try JSONDecoder().decode(GroqSummaryPayload.self, from: contentData) }
        catch { throw GroqError.malformedResponse }
    }

    func transcribe(fileURL: URL, apiKey: String) async throws -> GroqTranscriptPayload {
        let boundary = "PodTrackio-\(UUID().uuidString)"
        var data = Data()
        func append(_ string: String) { data.append(Data(string.utf8)) }
        append("--\(boundary)\r\nContent-Disposition: form-data; name=\"model\"\r\n\r\nwhisper-large-v3-turbo\r\n")
        append("--\(boundary)\r\nContent-Disposition: form-data; name=\"response_format\"\r\n\r\nverbose_json\r\n")
        append("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"\(fileURL.lastPathComponent)\"\r\nContent-Type: audio/mp4\r\n\r\n")
        data.append(try Data(contentsOf: fileURL, options: .mappedIfSafe))
        append("\r\n--\(boundary)--\r\n")
        var request = URLRequest(url: baseURL.appendingPathComponent("audio/transcriptions"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = data
        let response = try await perform(request)
        return try JSONDecoder().decode(GroqTranscriptPayload.self, from: response)
    }

    private func perform(_ request: URLRequest) async throws -> Data {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw GroqError.malformedResponse }
            switch http.statusCode {
            case 200...299: return data
            case 401: throw GroqError.unauthorized
            case 404: throw GroqError.modelUnavailable
            case 429:
                throw GroqError.rateLimited(seconds: http.value(forHTTPHeaderField: "retry-after").flatMap(Int.init))
            default:
                let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])
                    .flatMap { $0["error"] as? [String: Any] }?["message"] as? String
                throw GroqError.server(message ?? "Groq returned HTTP \(http.statusCode).")
            }
        } catch let error as GroqError { throw error }
        catch let error as URLError where [.notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .dnsLookupFailed].contains(error.code) {
            throw GroqError.offline
        }
    }
}
