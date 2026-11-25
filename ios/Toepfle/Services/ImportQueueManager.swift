import Foundation
import Observation
import SwiftData

@Observable
public final class ImportQueueManager {
    public static let shared = ImportQueueManager()

    public var queue: [PendingImport] = []
    public var isProcessing: Bool = false

    private init() {
        refreshQueue()
    }

    public func refreshQueue() {
        self.queue = PendingImportStore.shared.loadQueue()
    }

    public func addManualImport(url: String, modelContext: ModelContext) {
        let entry = PendingImportStore.shared.addImport(url: url)
        refreshQueue()
        processQueue(modelContext: modelContext)
    }

    public func retryImport(id: UUID, modelContext: ModelContext) {
        PendingImportStore.shared.updateStatus(id: id, status: .queued, errorMessage: nil)
        refreshQueue()
        processQueue(modelContext: modelContext)
    }

    public func removeImport(id: UUID) {
        PendingImportStore.shared.removeImport(id: id)
        refreshQueue()
    }

    public func processQueue(modelContext: ModelContext) {
        guard !isProcessing else { return }

        refreshQueue()
        let itemsToProcess = queue.filter { $0.status == .queued }
        guard !itemsToProcess.isEmpty else { return }

        isProcessing = true

        Task { @MainActor in
            for item in itemsToProcess {
                PendingImportStore.shared.updateStatus(id: item.id, status: .processing, errorMessage: nil)
                self.refreshQueue()

                do {
                    let dto = try await RecipeAPIService.shared.extractRecipe(from: item.url)

                    let ingredients = dto.ingredients.map {
                        IngredientItem(amount: $0.amount, unit: $0.unit, name: $0.name)
                    }

                    let newRecipe = SavedRecipe(
                        title: dto.title,
                        prepTime: dto.prep_time,
                        baseServings: dto.servings,
                        category: dto.category,
                        ingredients: ingredients,
                        instructions: dto.instructions,
                        originalURL: dto.original_url.isEmpty ? item.url : dto.original_url,
                        sourcePlatform: dto.source_platform,
                        thumbnailURL: dto.thumbnail_url,
                        createdAt: Date(),
                        isFavorite: false
                    )

                    modelContext.insert(newRecipe)
                    try? modelContext.save()

                    // Erfolgreich verarbeitet -> Aus der Queue entfernen
                    PendingImportStore.shared.removeImport(id: item.id)
                } catch {
                    let errorMsg = (error as? APIError)?.localizedDescription ?? error.localizedDescription
                    PendingImportStore.shared.updateStatus(id: item.id, status: .failed, errorMessage: errorMsg)
                }

                self.refreshQueue()
            }

            self.isProcessing = false
        }
    }
}
