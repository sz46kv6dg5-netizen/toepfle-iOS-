import SwiftUI
import SwiftData

public struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var allRecipes: [SavedRecipe]

    @State private var defaultServings: Int = 4
    @State private var keepScreenOn: Bool = true
    @State private var exportFileURL: URL? = nil
    @State private var showShareSheet: Bool = false

    public init() {}

    public var body: some View {
        NavigationStack {
            Form {
                // 1. Koch- & Anzeige-Präferenzen
                Section("Kochen & Portionen") {
                    Stepper("Standard-Portionen: \(defaultServings)", value: $defaultServings, in: 1...12)
                        .onChange(of: defaultServings) { _, newValue in
                            SharedConstants.defaultServings = newValue
                        }

                    Toggle("Bildschirm beim Kochen anlassen", isOn: $keepScreenOn)
                        .onChange(of: keepScreenOn) { _, newValue in
                            SharedConstants.keepScreenOnDuringCooking = newValue
                        }
                }

                // 2. Datenschutz & On-Device-Verarbeitung
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: "lock.shield.fill")
                                .font(.title3)
                                .foregroundColor(.green)
                            Text("100 % On-Device & Privat")
                                .font(.headline)
                        }

                        Text("Töpfle arbeitet komplett lokal auf deinem iPhone. Alle Rezepte, Links, oEmbed-Daten und HTML-Analysen werden direkt auf deinem Gerät verarbeitet. Es existiert kein externes Backend-Server-Tracking.")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Datenschutz")
                }

                // 3. Backup & Export
                Section("Daten & Backup") {
                    Button {
                        exportRecipesAsJSON()
                    } label: {
                        HStack {
                            Image(systemName: "square.and.arrow.up")
                                .foregroundColor(.accentColor)
                            Text("Rezepte als JSON exportieren (\(allRecipes.count) Rezepte)")
                        }
                    }
                    .disabled(allRecipes.isEmpty)
                }

                // 4. App-Informationen
                Section("App-Informationen") {
                    LabeledContent("App", value: "Töpfle")
                    LabeledContent("Version", value: "1.0.0 (Build 1)")
                    LabeledContent("Architektur", value: "100 % On-Device")
                    LabeledContent("App Group", value: SharedConstants.appGroupID)
                    LabeledContent("Bundle ID", value: "de.toepfle.app")
                }
            }
            .navigationTitle("Einstellungen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                defaultServings = SharedConstants.defaultServings
                keepScreenOn = SharedConstants.keepScreenOnDuringCooking
            }
            .sheet(isPresented: $showShareSheet) {
                if let url = exportFileURL {
                    ShareSheetRepresentable(activityItems: [url])
                }
            }
        }
    }

    private func exportRecipesAsJSON() {
        struct RecipeExportDTO: Codable {
            let title: String
            let prepTime: String
            let baseServings: Int
            let category: String
            let ingredients: [IngredientItem]
            let instructions: [String]
            let originalURL: String
            let sourcePlatform: String
            let isFavorite: Bool
            let createdAt: Date
        }

        let exportList = allRecipes.map { r in
            RecipeExportDTO(
                title: r.title,
                prepTime: r.prepTime,
                baseServings: r.baseServings,
                category: r.category,
                ingredients: r.ingredients,
                instructions: r.instructions,
                originalURL: r.originalURL,
                sourcePlatform: r.sourcePlatform,
                isFavorite: r.isFavorite,
                createdAt: r.createdAt
            )
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        guard let data = try? encoder.encode(exportList) else { return }

        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("Toepfle_Rezepte_Backup.json")
        try? data.write(to: tempURL)
        self.exportFileURL = tempURL
        self.showShareSheet = true
    }
}

private struct ShareSheetRepresentable: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
