import SwiftUI
import SwiftData
import UIKit

public struct RecipeDetailView: View {
    @Bindable var recipe: SavedRecipe
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var currentServings: Int = 4
    @State private var checkedIngredients: Set<UUID> = []
    @State private var completedSteps: Set<Int> = []
    @State private var isVideoExpanded: Bool = true

    private let impactFeedback = UIImpactFeedbackGenerator(style: .medium)

    public init(recipe: SavedRecipe) {
        self.recipe = recipe
        _currentServings = State(initialValue: max(1, recipe.baseServings))
    }

    private var portionRatio: Double {
        let base = max(1, Double(recipe.baseServings))
        return Double(currentServings) / base
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // 1. Eingebetteter Video-Player
                videoSection

                // 2. Rezept-Header & Metadaten
                headerSection
                    .padding(.horizontal)

                Divider()
                    .padding(.horizontal)

                // 3. Portionsrechner
                servingsCalculatorSection
                    .padding(.horizontal)

                // 4. Zutatenliste
                ingredientsSection
                    .padding(.horizontal)

                Divider()
                    .padding(.horizontal)

                // 5. Zubereitungsschritte
                instructionsSection
                    .padding(.horizontal)

                Spacer(minLength: 40)
            }
        }
        .navigationTitle(recipe.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    recipe.isFavorite.toggle()
                    try? modelContext.save()
                    impactFeedback.impactOccurred()
                } label: {
                    Image(systemName: recipe.isFavorite ? "heart.fill" : "heart")
                        .foregroundColor(recipe.isFavorite ? .red : .primary)
                }
            }
        }
        .onAppear {
            // Kochmodus: Display bleibt an
            UIApplication.shared.isIdleTimerDisabled = true
        }
        .onDisappear {
            // Kochmodus beenden
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }

    // MARK: - Video Section
    private var videoSection: some View {
        VStack(spacing: 8) {
            if isVideoExpanded {
                VideoEmbedView(urlString: recipe.originalURL, platform: recipe.sourcePlatform)
                    .frame(height: 460)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .padding(.horizontal)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            HStack {
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        isVideoExpanded.toggle()
                    }
                } label: {
                    Label(
                        isVideoExpanded ? "Video einklappen" : "Video einblenden",
                        systemImage: isVideoExpanded ? "chevron.up.circle.fill" : "play.circle.fill"
                    )
                    .font(.subheadline.weight(.medium))
                }

                Spacer()

                if let url = URL(string: recipe.originalURL) {
                    Link(destination: url) {
                        HStack(spacing: 4) {
                            Text("In Original-App öffnen")
                            Image(systemName: "arrow.up.right")
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.accentColor)
                    }
                }
            }
            .padding(.horizontal)
        }
    }

    // MARK: - Header Section
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(recipe.title)
                .font(.title2.weight(.bold))
                .foregroundColor(.primary)

            HStack(spacing: 12) {
                Label(recipe.category, systemImage: "tag.fill")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.secondary.opacity(0.15))
                    .clipShape(Capsule())

                Label(recipe.prepTime, systemImage: "clock.fill")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.orange.opacity(0.15))
                    .foregroundColor(.orange)
                    .clipShape(Capsule())

                platformBadge(platform: recipe.sourcePlatform)
            }
        }
    }

    // MARK: - Platform Badge
    @ViewBuilder
    private func platformBadge(platform: String) -> some View {
        let low = platform.lowercased()
        if low == "tiktok" {
            HStack(spacing: 4) {
                Image(systemName: "music.note")
                Text("TikTok")
            }
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.black.opacity(0.1))
            .clipShape(Capsule())
        } else if low == "facebook" {
            HStack(spacing: 4) {
                Image(systemName: "f.square.fill")
                Text("Facebook")
            }
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.blue.opacity(0.15))
            .foregroundColor(.blue)
            .clipShape(Capsule())
        } else if low == "youtube" {
            HStack(spacing: 4) {
                Image(systemName: "play.rectangle.fill")
                Text("YouTube")
            }
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.red.opacity(0.15))
            .foregroundColor(.red)
            .clipShape(Capsule())
        } else {
            HStack(spacing: 4) {
                Image(systemName: "globe")
                Text("Web")
            }
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.secondary.opacity(0.15))
            .clipShape(Capsule())
        }
    }

    // MARK: - Servings Calculator Section
    private var servingsCalculatorSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Portionen anpassen")
                    .font(.headline)

                Spacer()

                HStack(spacing: 14) {
                    Button {
                        if currentServings > 1 {
                            currentServings -= 1
                            impactFeedback.impactOccurred()
                        }
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .font(.title3)
                            .foregroundColor(currentServings > 1 ? .accentColor : .secondary.opacity(0.4))
                    }
                    .disabled(currentServings <= 1)

                    Text("\(currentServings)")
                        .font(.title3.weight(.bold).monospacedDigit())
                        .frame(minWidth: 26)

                    Button {
                        if currentServings < 12 {
                            currentServings += 1
                            impactFeedback.impactOccurred()
                        }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                            .foregroundColor(currentServings < 12 ? .accentColor : .secondary.opacity(0.4))
                    }
                    .disabled(currentServings >= 12)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.secondary.opacity(0.12))
                .clipShape(Capsule())
            }

            if currentServings != recipe.baseServings {
                Text("Zutatenmengen wurden automatisch für \(currentServings) Portionen umgerechnet.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Ingredients Section
    private var ingredientsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Zutaten")
                    .font(.title3.weight(.bold))

                Spacer()

                if !checkedIngredients.isEmpty {
                    Button("Alle abwählen") {
                        checkedIngredients.removeAll()
                        impactFeedback.impactOccurred()
                    }
                    .font(.caption)
                }
            }

            let ingredientsList = recipe.ingredients
            if ingredientsList.isEmpty {
                Text("Keine Zutaten hinterlegt.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else {
                VStack(spacing: 10) {
                    ForEach(ingredientsList) { item in
                        let isChecked = checkedIngredients.contains(item.id)
                        Button {
                            if isChecked {
                                checkedIngredients.remove(item.id)
                            } else {
                                checkedIngredients.insert(item.id)
                            }
                            impactFeedback.impactOccurred()
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
                                    .font(.title3)
                                    .foregroundColor(isChecked ? .green : .secondary)

                                let formattedAmount = formatAmount(item.amount)
                                if !formattedAmount.isEmpty || !item.unit.isEmpty {
                                    Text("\(formattedAmount) \(item.unit)".trimmingCharacters(in: .whitespaces))
                                        .font(.subheadline.weight(.semibold).monospacedDigit())
                                        .foregroundColor(isChecked ? .secondary : .primary)
                                        .strikethrough(isChecked, color: .secondary)
                                }

                                Text(item.name)
                                    .font(.subheadline)
                                    .foregroundColor(isChecked ? .secondary : .primary)
                                    .strikethrough(isChecked, color: .secondary)

                                Spacer()
                            }
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Instructions Section
    private var instructionsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Zubereitung")
                .font(.title3.weight(.bold))

            if recipe.instructions.isEmpty {
                Text("Keine Schritte hinterlegt.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else {
                VStack(spacing: 14) {
                    ForEach(Array(recipe.instructions.enumerated()), id: \.offset) { index, step in
                        let isDone = completedSteps.contains(index)
                        Button {
                            if isDone {
                                completedSteps.remove(index)
                            } else {
                                completedSteps.insert(index)
                            }
                            impactFeedback.impactOccurred()
                        } label: {
                            HStack(alignment: .top, spacing: 14) {
                                ZStack {
                                    Circle()
                                        .fill(isDone ? Color.green : Color.accentColor.opacity(0.15))
                                        .frame(width: 30, height: 30)

                                    if isDone {
                                        Image(systemName: "checkmark")
                                            .font(.footnote.weight(.bold))
                                            .foregroundColor(.white)
                                    } else {
                                        Text("\(index + 1)")
                                            .font(.footnote.weight(.bold))
                                            .foregroundColor(.accentColor)
                                    }
                                }

                                Text(step)
                                    .font(.body)
                                    .multilineTextAlignment(.leading)
                                    .foregroundColor(isDone ? .secondary : .primary)
                                    .strikethrough(isDone, color: .secondary)

                                Spacer()
                            }
                            .padding(12)
                            .background(isDone ? Color.secondary.opacity(0.08) : Color.secondary.opacity(0.05))
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Amount Formatting Helper
    private func formatAmount(_ amount: Double?) -> String {
        guard let original = amount else { return "" }
        let scaled = original * portionRatio

        // Brüche runden und sauber darstellen
        let epsilon = 0.04
        let floorVal = floor(scaled)
        let remainder = scaled - floorVal

        var fractionString = ""
        if abs(remainder - 0.5) < epsilon {
            fractionString = "½"
        } else if abs(remainder - 0.25) < epsilon {
            fractionString = "¼"
        } else if abs(remainder - 0.75) < epsilon {
            fractionString = "¾"
        } else if abs(remainder - 0.33) < epsilon {
            fractionString = "⅓"
        } else if abs(remainder - 0.66) < epsilon {
            fractionString = "⅔"
        }

        if !fractionString.isEmpty {
            if floorVal > 0 {
                return "\(Int(floorVal)) \(fractionString)"
            } else {
                return fractionString
            }
        }

        // Falls Ganzzahl
        if abs(scaled.rounded() - scaled) < 0.05 {
            return "\(Int(scaled.rounded()))"
        }

        // 1 Nachkommastelle
        let formatted = String(format: "%.1f", scaled)
        return formatted.replacingOccurrences(of: ".0", with: "")
    }
}
