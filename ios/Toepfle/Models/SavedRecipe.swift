import Foundation
import SwiftData

public struct IngredientItem: Codable, Identifiable, Hashable {
    public var id: UUID
    public var amount: Double?
    public var unit: String
    public var name: String

    public init(id: UUID = UUID(), amount: Double? = nil, unit: String = "", name: String) {
        self.id = id
        self.amount = amount
        self.unit = unit
        self.name = name
    }
}

@Model
public final class SavedRecipe {
    public var id: UUID
    public var title: String
    public var prepTime: String
    public var baseServings: Int
    public var category: String
    public var ingredientsData: Data
    public var instructions: [String]
    public var originalURL: String
    public var sourcePlatform: String
    public var thumbnailURL: String?
    public var createdAt: Date
    public var isFavorite: Bool

    public init(
        id: UUID = UUID(),
        title: String,
        prepTime: String,
        baseServings: Int = 4,
        category: String = "Hauptgericht",
        ingredients: [IngredientItem] = [],
        instructions: [String] = [],
        originalURL: String,
        sourcePlatform: String = "web",
        thumbnailURL: String? = nil,
        createdAt: Date = Date(),
        isFavorite: Bool = false
    ) {
        self.id = id
        self.title = title
        self.prepTime = prepTime
        self.baseServings = baseServings
        self.category = category
        self.instructions = instructions
        self.originalURL = originalURL
        self.sourcePlatform = sourcePlatform
        self.thumbnailURL = thumbnailURL
        self.createdAt = createdAt
        self.isFavorite = isFavorite

        let encoder = JSONEncoder()
        self.ingredientsData = (try? encoder.encode(ingredients)) ?? Data()
    }

    public var ingredients: [IngredientItem] {
        get {
            guard !ingredientsData.isEmpty else { return [] }
            let decoder = JSONDecoder()
            return (try? decoder.decode([IngredientItem].self, from: ingredientsData)) ?? []
        }
        set {
            let encoder = JSONEncoder()
            if let data = try? encoder.encode(newValue) {
                ingredientsData = data
            }
        }
    }
}
