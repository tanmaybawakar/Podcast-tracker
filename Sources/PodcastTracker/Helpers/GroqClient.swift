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
    struct Section: Decodable, Sendable {
        struct Point: Decodable, Sendable { let title: String; let explanation: String; let timestampSeconds: Double? }
        let title: String; let introduction: String?; let points: [Point]
    }
    let brief: String
    let keyTopics: [Topic]
    let majorTakeaways: [Takeaway]
    let actionPlan: [Action]
    let sections: [Section]?
}

struct GroqTranscriptPayload: Decodable, Sendable {
    struct Segment: Decodable, Sendable { let start: Double; let end: Double?; let text: String }
    let text: String
    let segments: [Segment]?
}

enum QuirkyModel: String, CaseIterable, Identifiable, Sendable {
    case deep
    case balanced
    case instant

    var id: String { rawValue }
    var title: String {
        switch self {
        case .deep: "Deep"
        case .balanced: "Balanced"
        case .instant: "Instant"
        }
    }
    var detail: String {
        switch self {
        case .deep: "Hard problems · GPT-OSS 120B"
        case .balanced: "Thoughtful everyday help · Qwen 3.8 27B"
        case .instant: "Quick answers · GPT-OSS 20B"
        }
    }
    var symbol: String {
        switch self {
        case .deep: "brain.head.profile"
        case .balanced: "scale.3d"
        case .instant: "bolt.fill"
        }
    }
    var modelID: String {
        switch self {
        case .deep: "openai/gpt-oss-120b"
        case .balanced: "qwen/qwen3.8-27b"
        case .instant: "openai/gpt-oss-20b"
        }
    }
    var reasoningEffort: String {
        switch self {
        case .deep: "high"
        case .balanced: "medium"
        case .instant: "low"
        }
    }
    var temperature: Double { self == .balanced ? 1.0 : 0.55 }
}

enum QuirkyPrompt {
    static func system(episodeTitle: String, transcript: String) -> String {
        """
        You are Quirky, Tan's transcript-grounded learning mentor inside PodTrackio. You are a sharp thinking partner: practical, candid, curious, and allergic to generic advice.

        WHO YOU ARE HELPING
        Tan is a high-autonomy product founder and builder at Tangenix. He learns to ship and apply ideas, not to collect abstract notes. He values direct reasoning, premium product taste, concrete deliverables, global thinking, honest pushback, and fast execution. He may be applying a lesson to different projects; never assume which project or mix project details unless he identifies the context.

        SOURCE DISCIPLINE
        - Treat the episode transcript as the primary source of truth.
        - The supplied transcript may be an excerpt selected for this question. Say when an answer would require material outside it.
        - Clearly separate what the speaker said from your own analysis or recommendation.
        - Never invent a quote, step, example, number, or timestamp. If the transcript does not support something, say that plainly.
        - Cite useful transcript moments with the provided [m:ss] timestamp when available.
        - If the speaker gives a numbered framework, process, checklist, stages, rules, or examples, recover every item you can find, preserve the order, and explain the missing or unclear items instead of silently compressing them.

        MENTORING METHOD
        - Lead with the direct answer. Do not restate the question or advertise the episode.
        - Infer the real outcome Tan is trying to create, then connect the lesson to that outcome.
        - Challenge weak assumptions respectfully and explain the tradeoff.
        - For application questions, turn insight into a small executable plan: concrete action, deliverable, constraint, and success check. Prefer a useful first move Tan can do today.
        - When brainstorming, offer 3-5 meaningfully different strategic options, label the angle, and recommend one with a reason.
        - Ask at most one focused follow-up question when personalization genuinely depends on missing context. Still provide a useful provisional answer first.
        - Use examples grounded in Tan's stated situation. Never fabricate his audience, budget, metrics, assets, or capabilities.

        WRITING STANDARD
        Write like a top-tier mentor in a real working session: concise, specific, confident, and human. Use short sections or bullets only when they make the answer easier to act on. Avoid motivational filler, vague verbs such as “optimize” without saying how, canned summaries, and bloated action plans. Match Tan's language and level of detail. End with a single clear next move when action is appropriate; do not force one onto simple factual answers.

        EPISODE
        \(episodeTitle)

        TRANSCRIPT
        \(transcript)
        """
    }
}

enum QuirkyContext {
    /// Keeps one chat request comfortably below Groq's 8K TPM allowance once
    /// the system instructions, recent conversation, and answer budget are added.
    static let maximumTranscriptCharacters = 9_000
    static let maximumHistoryCharacters = 600
    static let maximumHistoryMessages = 3

    static func transcriptExcerpt(_ transcript: String, for question: String) -> String {
        guard transcript.count > maximumTranscriptCharacters else { return transcript }

        let terms = Set(question.lowercased().split { !$0.isLetter && !$0.isNumber }
            .filter { $0.count > 2 }
            .map(String.init))
        let lines = transcript.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard !lines.isEmpty else { return String(transcript.prefix(maximumTranscriptCharacters)) }

        let rankedIndexes = lines.indices.sorted { lhs, rhs in
            relevance(of: lines[lhs], terms: terms) > relevance(of: lines[rhs], terms: terms)
        }
        var selected = Set<Int>()
        for index in rankedIndexes where relevance(of: lines[index], terms: terms) > 0 {
            for nearby in max(0, index - 2)...min(lines.count - 1, index + 2) {
                selected.insert(nearby)
            }
            if selected.count >= 80 { break }
        }

        guard !selected.isEmpty else { return String(transcript.prefix(maximumTranscriptCharacters)) }
        var excerpt = ""
        for index in selected.sorted() {
            let line = lines[index]
            guard excerpt.count + line.count + 1 <= maximumTranscriptCharacters else { break }
            excerpt += (excerpt.isEmpty ? "" : "\n") + line
        }
        return excerpt.isEmpty ? String(transcript.prefix(maximumTranscriptCharacters)) : excerpt
    }

    static func recentHistory(_ history: [(role: String, content: String)]) -> [[String: String]] {
        history.suffix(maximumHistoryMessages).map {
            ["role": $0.role, "content": String($0.content.prefix(maximumHistoryCharacters))]
        }
    }

    private static func relevance(of line: String, terms: Set<String>) -> Int {
        let words = Set(line.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init))
        return words.intersection(terms).count
    }
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
        You are a rigorous learning editor. Turn this transcript into a faithful, useful study guide. The transcript is the only source of truth.
        Episode: \(title)

        Requirements:
        - sections: create a small number of sections whose titles and content are specific to this video. Do not use a fixed template.
        - If the speaker presents numbered steps, a framework, process, checklist, stages, rules, or examples, make it impossible to miss: create a section for it and include every item in order as points. Preserve the speaker's wording where useful.
        - Each point must explain what it means, not merely name it. Use timestamps when they can be inferred.
        - brief, keyTopics, majorTakeaways and actionPlan remain required for backward compatibility, but they must also reflect the actual transcript.
        - actionPlan must be basic, concrete, and tailored to the listener's likely use of this video's idea. No motivational filler, generic “learn more,” or invented business details.
        - brief is a concise explanation of what the video teaches, not an advertisement for watching it.
        - Do not invent claims beyond the transcript. If the transcript is unclear, say so.

        Transcript:
        \(transcript)
        """
        let pointSchema: [String: Any] = ["type": "object", "additionalProperties": false,
            "properties": ["title": ["type": "string"], "explanation": ["type": "string"], "timestampSeconds": ["type": ["number", "null"]]],
            "required": ["title", "explanation", "timestampSeconds"]]
        let sectionSchema: [String: Any] = ["type": "object", "additionalProperties": false,
            "properties": ["title": ["type": "string"], "introduction": ["type": ["string", "null"]], "points": ["type": "array", "items": pointSchema]],
            "required": ["title", "introduction", "points"]]
        let schema: [String: Any] = ["type": "object", "additionalProperties": false,
            "properties": [
                "brief": ["type": "string"],
                "keyTopics": ["type": "array", "items": ["type": "object", "additionalProperties": false, "properties": ["title": ["type": "string"], "explanation": ["type": "string"], "timestampSeconds": ["type": ["number", "null"]]], "required": ["title", "explanation", "timestampSeconds"]]],
                "majorTakeaways": ["type": "array", "items": ["type": "object", "additionalProperties": false, "properties": ["title": ["type": "string"], "explanation": ["type": "string"]], "required": ["title", "explanation"]]],
                "actionPlan": ["type": "array", "items": ["type": "object", "additionalProperties": false, "properties": ["title": ["type": "string"], "detail": ["type": "string"]], "required": ["title", "detail"]]],
                "sections": ["type": "array", "items": sectionSchema]
            ], "required": ["brief", "keyTopics", "majorTakeaways", "actionPlan", "sections"]]
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

    func chat(transcript: String, title: String, question: String, history: [(role: String, content: String)], model: QuirkyModel, apiKey: String) async throws -> String {
        let excerpt = QuirkyContext.transcriptExcerpt(transcript, for: question)
        let system = QuirkyPrompt.system(episodeTitle: title, transcript: excerpt)
        var messages: [[String: String]] = [["role": "system", "content": system]]
        messages.append(contentsOf: QuirkyContext.recentHistory(history))
        messages.append(["role": "user", "content": String(question.prefix(1_000))])
        let body: [String: Any] = [
            "model": model.modelID,
            "messages": messages,
            "temperature": model.temperature,
            "reasoning_effort": model.reasoningEffort,
            "reasoning_format": "hidden",
            "max_completion_tokens": 800
        ]
        var request = URLRequest(url: baseURL.appendingPathComponent("chat/completions"))
        request.httpMethod = "POST"; request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type"); request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let data = try await perform(request)
        struct Response: Decodable { struct Choice: Decodable { struct Message: Decodable { let content: String }; let message: Message }; let choices: [Choice] }
        guard let content = try JSONDecoder().decode(Response.self, from: data).choices.first?.message.content, !content.isEmpty else { throw GroqError.malformedResponse }
        return content
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
