import Foundation

enum TranscriptAPIError: LocalizedError, Equatable {
    case missingKey
    case unauthorized
    case unavailable(String)
    case malformedResponse
    case offline

    var errorDescription: String? {
        switch self {
        case .missingKey: "Add your TranscriptAPI key in Settings to fetch transcripts automatically."
        case .unauthorized: "TranscriptAPI rejected this API key. Check it in Settings."
        case .unavailable(let message): message
        case .malformedResponse: "TranscriptAPI returned an unreadable transcript."
        case .offline: "You appear to be offline. Reconnect and try again."
        }
    }
}

struct TranscriptAPIResponse: Decodable, Sendable {
    struct Segment: Decodable, Sendable {
        let text: String
        let start: Double
        let duration: Double?
    }

    let transcript: [Segment]
}

final class TranscriptAPIClient: @unchecked Sendable {
    static let shared = TranscriptAPIClient()
    private let session: URLSession

    init(session: URLSession = .shared) { self.session = session }

    func fetchTranscript(videoID: String, apiKey: String) async throws -> [TranscriptSegment] {
        var components = URLComponents(string: "https://transcriptapi.com/api/v2/youtube/transcript")!
        components.queryItems = [
            URLQueryItem(name: "video_url", value: videoID),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "include_timestamp", value: "true"),
            URLQueryItem(name: "language", value: "en,asr")
        ]
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw TranscriptAPIError.malformedResponse }
            switch http.statusCode {
            case 200...299:
                let payload: TranscriptAPIResponse
                do { payload = try JSONDecoder().decode(TranscriptAPIResponse.self, from: data) }
                catch { throw TranscriptAPIError.malformedResponse }
                let segments = payload.transcript.map {
                    TranscriptSegment(text: $0.text, startSeconds: $0.start, durationSeconds: $0.duration)
                }.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                guard !segments.isEmpty else { throw TranscriptAPIError.malformedResponse }
                return segments
            case 401: throw TranscriptAPIError.unauthorized
            default:
                let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                let message = payload?["message"] as? String ?? payload?["error"] as? String
                throw TranscriptAPIError.unavailable(message ?? "TranscriptAPI returned HTTP \(http.statusCode).")
            }
        } catch let error as TranscriptAPIError { throw error }
        catch let error as URLError where [.notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .dnsLookupFailed].contains(error.code) {
            throw TranscriptAPIError.offline
        }
    }
}
