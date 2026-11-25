import SwiftUI
import SwiftData

public struct RecipeListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SavedRecipe.createdAt, order: .reverse) private var allRecipes: [SavedRecipe]

    @State private var queueManager = ImportQueueManager.shared
    @State private var searchText: String = ""
    @State private var selectedCategory: String = "Alle"
    @State private var onlyFavorites: Bool = false
    @State private var showAddSheet: Bool = false
    @State private var showSettingsSheet: Bool = false

    private let categories = ["Alle", "Hauptgericht", "Dessert", "Frühstück", "Snack", "Backen"]

    public init() {}

    private var filteredRecipes: [SavedRecipe] {
        allRecipes.filter { recipe in
            let matchesCategory = (selectedCategory == "Alle" || recipe.category.localizedCaseInsensitiveContains(selectedCategory))
            let matchesFavorites = !onlyFavorites || recipe.isFavorite
            let matchesSearch = searchText.isEmpty
                || recipe.title.localizedCaseInsensitiveContains(searchText)
                || recipe.category.localizedCaseInsensitiveContains(searchText)
                || recipe.ingredients.contains { $0.name.localizedCaseInsensitiveContains(searchText) }

            return matchesCategory && matchesFavorites && matchesSearch
        }
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // 1. Live Status-Karten für anstehende/laufende Importe
                    pendingImportsSection

                    // 2. Kategorie-Filter-Chips
                    categoryChipsSection

                    // 3. Rezept-Liste
                    if filteredRecipes.isEmpty {
                        emptyStateView
                            .padding(.top, 40)
                    } else {
                        LazyVStack(spacing: 12) {
                            ForEach(filteredRecipes) { recipe in
                                NavigationLink(destination: RecipeDetailView(recipe: recipe)) {
                                    RecipeCardView(recipe: recipe)
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button {
                                        recipe.isFavorite.toggle()
                                        try? modelContext.save()
                                    } label: {
                                        Label(recipe.isFavorite ? "Aus Favoriten entfernen" : "Zu Favoriten hinzufügen", systemImage: recipe.isFavorite ? "heart.slash" : "heart")
                                    }

                                    Button(role: .destructive) {
                                        modelContext.delete(recipe)
                                        try? modelContext.save()
                                    } label: {
                                        Label("Löschen", systemImage: "trash")
                                    }
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                }
                .padding(.vertical, 8)
            }
            .navigationTitle("Töpfle")
            .searchable(text: $searchText, prompt: "Rezepte oder Zutaten suchen…")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        onlyFavorites.toggle()
                    } label: {
                        Image(systemName: onlyFavorites ? "heart.fill" : "heart")
                            .foregroundColor(onlyFavorites ? .red : .primary)
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 12) {
                        Button {
                            showSettingsSheet = true
                        } label: {
                            Image(systemName: "gearshape")
                        }

                        Button {
                            showAddSheet = true
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.title3)
                        }
                    }
                }
            }
            .sheet(isPresented: $showAddSheet) {
                AddRecipeSheet()
            }
            .sheet(isPresented: $showSettingsSheet) {
                SettingsView()
            }
        }
    }

    // MARK: - Pending Imports Section
    @ViewBuilder
    private var pendingImportsSection: some View {
        let queueItems = queueManager.queue
        if !queueItems.isEmpty {
            VStack(spacing: 10) {
                ForEach(queueItems) { item in
                    HStack(spacing: 12) {
                        if item.status == .processing {
                            ProgressView()
                                .controlSize(.small)
                        } else if item.status == .failed {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.red)
                        } else {
                            Image(systemName: "hourglass")
                                .foregroundColor(.orange)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(statusText(for: item.status))
                                .font(.subheadline.weight(.semibold))

                            Text(item.url)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)

                            if let error = item.errorMessage, item.status == .failed {
                                Text(error)
                                    .font(.caption2)
                                    .foregroundColor(.red)
                                    .lineLimit(2)
                            }
                        }

                        Spacer()

                        if item.status == .failed {
                            Button("Erneut") {
                                queueManager.retryImport(id: item.id, modelContext: modelContext)
                            }
                            .font(.caption.weight(.bold))
                            .buttonStyle(.borderedProminent)
                            .tint(.orange)
                        }

                        Button {
                            queueManager.removeImport(id: item.id)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(12)
                    .background(Color.secondary.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            .padding(.horizontal)
        }
    }

    private func statusText(for status: ImportStatus) -> String {
        switch status {
        case .queued:
            return "Wartet in der Warteschlange…"
        case .processing:
            return "KI analysiert Video & Rezept…"
        case .failed:
            return "Import fehlgeschlagen"
        }
    }

    // MARK: - Category Chips Section
    private var categoryChipsSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(categories, id: \.self) { cat in
                    let isSelected = (selectedCategory == cat)
                    Button {
                        selectedCategory = cat
                    } label: {
                        Text(cat)
                            .font(.subheadline.weight(isSelected ? .bold : .medium))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(isSelected ? Color.accentColor : Color.secondary.opacity(0.12))
                            .foregroundColor(isSelected ? .white : .primary)
                            .clipShape(Capsule())
                    }
                }
            }
            .padding(.horizontal)
        }
    }

    // MARK: - Empty State
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "fork.knife.circle")
                .font(.system(size: 60))
                .foregroundColor(.secondary.opacity(0.5))

            Text("Noch keine Rezepte gespeichert")
                .font(.headline)

            Text("Teile Videos direkt aus TikTok oder Facebook über das iOS-Teilen-Menü oder tippe oben rechts auf das Plus-Symbol.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Button {
                showAddSheet = true
            } label: {
                Label("Erstes Rezept hinzufügen", systemImage: "plus")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 8)
        }
    }
}

// MARK: - Recipe Card View
private struct RecipeCardView: View {
    let recipe: SavedRecipe

    var body: some View {
        HStack(spacing: 14) {
            // Thumbnail oder Platzhalter-Icon
            ZStack {
                if let thumb = recipe.thumbnailURL, let url = URL(string: thumb) {
                    AsyncImage(url: url) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Color.secondary.opacity(0.15)
                    }
                } else {
                    LinearGradient(
                        colors: [Color.orange.opacity(0.7), Color.pink.opacity(0.6)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    Image(systemName: "fork.knife")
                        .font(.title2)
                        .foregroundColor(.white)
                }
            }
            .frame(width: 88, height: 88)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(recipe.title)
                        .font(.headline)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    Spacer()

                    if recipe.isFavorite {
                        Image(systemName: "heart.fill")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }

                HStack(spacing: 8) {
                    Text(recipe.category)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.secondary.opacity(0.15))
                        .clipShape(Capsule())

                    Label(recipe.prepTime, systemImage: "clock")
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    Spacer()

                    platformIcon(platform: recipe.sourcePlatform)
                }
            }
        }
        .padding(12)
        .background(Color.secondary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    @ViewBuilder
    private func platformIcon(platform: String) -> some View {
        let low = platform.lowercased()
        if low == "tiktok" {
            Image(systemName: "music.note")
                .font(.caption)
                .foregroundColor(.black)
        } else if low == "facebook" {
            Image(systemName: "f.square.fill")
                .font(.caption)
                .foregroundColor(.blue)
        } else if low == "youtube" {
            Image(systemName: "play.rectangle.fill")
                .font(.caption)
                .foregroundColor(.red)
        } else {
            Image(systemName: "globe")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}
