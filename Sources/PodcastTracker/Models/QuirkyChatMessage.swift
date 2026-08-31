import Foundation

struct QuirkyChatMessage: Identifiable, Sendable {
    enum Role: String, Sendable { case user, quirky }

    let id: UUID
    let role: Role
    let text: String
    let model: QuirkyModel?

    init(id: UUID = UUID(), role: Role, text: String, model: QuirkyModel?) {
        self.id = id
        self.role = role
        self.text = text
        self.model = model
    }
}
