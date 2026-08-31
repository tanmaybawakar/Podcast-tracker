import Foundation
import SwiftUI

struct LearningCategory: Identifiable, Codable, Hashable, Sendable {
    static let generalID = "general"

    var id: String
    var name: String
    var symbolName: String
    var colorToken: String
    var sortOrder: Int
    var createdAt: Date
    var updatedAt: Date

    init(
        id: String = UUID().uuidString.lowercased(),
        name: String,
        symbolName: String = "book.closed.fill",
        colorToken: String = "blue",
        sortOrder: Int,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.symbolName = symbolName
        self.colorToken = colorToken
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var color: Color {
        switch colorToken {
        case "red": .red
        case "orange": .orange
        case "yellow": .yellow
        case "green": .green
        case "mint": .mint
        case "teal": .teal
        case "cyan": .cyan
        case "indigo": .indigo
        case "purple": .purple
        case "pink": .pink
        case "brown": .brown
        case "gray": .gray
        default: .blue
        }
    }

    static let defaults: [LearningCategory] = [
        .init(id: "general", name: "General", symbolName: "book.closed.fill", colorToken: "gray", sortOrder: 0),
        .init(id: "technology", name: "Technology", symbolName: "cpu", colorToken: "blue", sortOrder: 1),
        .init(id: "science", name: "Science", symbolName: "atom", colorToken: "green", sortOrder: 2),
        .init(id: "business", name: "Business", symbolName: "briefcase.fill", colorToken: "orange", sortOrder: 3),
        .init(id: "self-improvement", name: "Self Improvement", symbolName: "figure.mind.and.body", colorToken: "purple", sortOrder: 4),
        .init(id: "history", name: "History", symbolName: "clock.arrow.circlepath", colorToken: "brown", sortOrder: 5),
        .init(id: "philosophy", name: "Philosophy", symbolName: "brain.head.profile", colorToken: "indigo", sortOrder: 6),
        .init(id: "programming", name: "Programming", symbolName: "chevron.left.forwardslash.chevron.right", colorToken: "cyan", sortOrder: 7),
        .init(id: "mathematics", name: "Mathematics", symbolName: "function", colorToken: "red", sortOrder: 8),
        .init(id: "language", name: "Language", symbolName: "globe", colorToken: "teal", sortOrder: 9),
        .init(id: "health", name: "Health", symbolName: "heart.fill", colorToken: "pink", sortOrder: 10),
        .init(id: "finance", name: "Finance", symbolName: "chart.line.uptrend.xyaxis", colorToken: "yellow", sortOrder: 11)
    ]

    static func stableID(forLegacyName name: String) -> String {
        defaults.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.id ?? generalID
    }
}

enum CategoryValidationError: LocalizedError, Equatable {
    case emptyName
    case duplicateName
    case lastCategory
    case replacementRequired
    case categoryNotFound

    var errorDescription: String? {
        switch self {
        case .emptyName: "Category names cannot be empty."
        case .duplicateName: "A category with this name already exists."
        case .lastCategory: "PodTrackio needs at least one category."
        case .replacementRequired: "Choose a replacement for podcasts in this category."
        case .categoryNotFound: "That category no longer exists."
        }
    }
}

enum CategoryOperations {
    static func validatedName(_ name: String, excluding id: String? = nil, in categories: [LearningCategory]) throws -> String {
        let value = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { throw CategoryValidationError.emptyName }
        guard !categories.contains(where: { $0.id != id && $0.name.caseInsensitiveCompare(value) == .orderedSame }) else {
            throw CategoryValidationError.duplicateName
        }
        return value
    }

    static func delete(
        categoryID: String,
        replacementID: String?,
        categories: inout [LearningCategory],
        podcasts: inout [Podcast]
    ) throws {
        guard categories.count > 1 else { throw CategoryValidationError.lastCategory }
        guard let index = categories.firstIndex(where: { $0.id == categoryID }) else { throw CategoryValidationError.categoryNotFound }
        let isInUse = podcasts.contains { $0.categoryID == categoryID }
        if isInUse {
            guard let replacementID, replacementID != categoryID,
                  categories.contains(where: { $0.id == replacementID }) else {
                throw CategoryValidationError.replacementRequired
            }
            for podcastIndex in podcasts.indices where podcasts[podcastIndex].categoryID == categoryID {
                podcasts[podcastIndex].categoryID = replacementID
            }
        }
        categories.remove(at: index)
        for order in categories.indices { categories[order].sortOrder = order }
    }
}
