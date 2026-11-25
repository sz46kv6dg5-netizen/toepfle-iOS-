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

    public func addManualImport(url: String, rawText: String? = nil, modelContext: ModelContext) {
        PendingImportStore.shared.addImport(url: url, rawText: rawText)
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

                let extracted = await OnDeviceRecipeExtractor.shared.extract(
                    from: item.url,
                    rawText: item.rawText
                )

                let defaultServings = SharedConstants.defaultServings
                let initialServings = extracted.servings > 0 ? extracted.servings : defaultServings

                let newRecipe = SavedRecipe(
                    title: extracted.title,
                    prepTime: extracted.prepTime,
                    baseServings: initialServings,
                    category: extracted.category,
                    ingredients: extracted.ingredients,
                    instructions: extracted.instructions,
                    originalURL: extracted.originalURL.isEmpty ? item.url : extracted.originalURL,
                    sourcePlatform: extracted.sourcePlatform,
                    thumbnailURL: extracted.thumbnailURL,
                    createdAt: Date(),
                    isFavorite: false
                )

                modelContext.insert(newRecipe)
                try? modelContext.save()

                // Erfolgreich verarbeitet -> Aus der Queue entfernen
                PendingImportStore.shared.removeImport(id: item.id)
                self.refreshQueue()
            }

            self.isProcessing = false
        }
    }
}
