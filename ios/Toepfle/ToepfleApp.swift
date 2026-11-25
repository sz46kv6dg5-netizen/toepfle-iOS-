import SwiftUI
import SwiftData

@main
struct ToepfleApp: App {
    @Environment(\.scenePhase) private var scenePhase

    let sharedModelContainer: ModelContainer = {
        let schema = Schema([
            SavedRecipe.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Konnte ModelContainer nicht initialisieren: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            RecipeListView()
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .active {
                        ImportQueueManager.shared.refreshQueue()
                        ImportQueueManager.shared.processQueue(modelContext: sharedModelContainer.mainContext)
                    }
                }
                .onAppear {
                    ImportQueueManager.shared.refreshQueue()
                    ImportQueueManager.shared.processQueue(modelContext: sharedModelContainer.mainContext)
                }
        }
        .modelContainer(sharedModelContainer)
    }
}
