import SwiftUI
import SwiftData

public struct EditRecipeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Bindable var recipe: SavedRecipe

    @State private var title: String
    @State private var category: String
    @State private var prepTime: String
    @State private var baseServings: Int
    @State private var ingredients: [IngredientItem]
    @State private var instructions: [String]

    // Neue Zutat / Neuer Schritt Felder
    @State private var newAmount: String = ""
    @State private var newUnit: String = ""
    @State private var newName: String = ""
    @State private var newStep: String = ""

    private let categories = ["Hauptgericht", "Dessert", "Frühstück", "Snack", "Backen"]

    public init(recipe: SavedRecipe) {
        self.recipe = recipe
        _title = State(initialValue: recipe.title)
        _category = State(initialValue: recipe.category)
        _prepTime = State(initialValue: recipe.prepTime)
        _baseServings = State(initialValue: recipe.baseServings)
        _ingredients = State(initialValue: recipe.ingredients)
        _instructions = State(initialValue: recipe.instructions)
    }

    public var body: some View {
        NavigationStack {
            Form {
                // 1. Basisdaten
                Section("Allgemein") {
                    TextField("Rezepttitel", text: $title)

                    Picker("Kategorie", selection: $category) {
                        ForEach(categories, id: \.self) { cat in
                            Text(cat).tag(cat)
                        }
                    }

                    TextField("Zubereitungszeit (z. B. 25 Min.)", text: $prepTime)

                    Stepper("Basis-Portionen: \(baseServings)", value: $baseServings, in: 1...12)
                }

                // 2. Zutaten
                Section("Zutaten") {
                    ForEach($ingredients) { $item in
                        HStack(spacing: 8) {
                            TextField("Menge", value: $item.amount, format: .number)
                                .frame(width: 60)
                                .keyboardType(.decimalPad)

                            TextField("Einheit", text: $item.unit)
                                .frame(width: 60)

                            TextField("Zutat", text: $item.name)
                        }
                    }
                    .onDelete { indexSet in
                        ingredients.remove(atOffsets: indexSet)
                    }

                    // Neue Zutat hinzufügen
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Zutat hinzufügen")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.secondary)

                        HStack(spacing: 8) {
                            TextField("Menge", text: $newAmount)
                                .frame(width: 60)
                                .keyboardType(.decimalPad)

                            TextField("Einheit", text: $newUnit)
                                .frame(width: 60)

                            TextField("Name (z.B. Mehl)", text: $newName)

                            Button {
                                addIngredient()
                            } label: {
                                Image(systemName: "plus.circle.fill")
                                    .font(.title3)
                                    .foregroundColor(.accentColor)
                            }
                            .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    }
                    .padding(.vertical, 4)
                }

                // 3. Zubereitungsschritte
                Section("Zubereitungsschritte") {
                    ForEach(Array(instructions.enumerated()), id: \.offset) { index, _ in
                        HStack(alignment: .top, spacing: 10) {
                            Text("\(index + 1).")
                                .font(.footnote.weight(.bold))
                                .foregroundColor(.secondary)
                                .padding(.top, 8)

                            TextEditor(text: Binding(
                                get: { instructions[index] },
                                set: { instructions[index] = $0 }
                            ))
                            .frame(minHeight: 44)
                        }
                    }
                    .onDelete { indexSet in
                        instructions.remove(atOffsets: indexSet)
                    }

                    // Neuer Schritt hinzufügen
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Schritt hinzufügen")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.secondary)

                        HStack {
                            TextField("Neuer Zubereitungsschritt…", text: $newStep)

                            Button {
                                addStep()
                            } label: {
                                Image(systemName: "plus.circle.fill")
                                    .font(.title3)
                                    .foregroundColor(.accentColor)
                            }
                            .disabled(newStep.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("Rezept bearbeiten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern") {
                        saveChanges()
                    }
                    .bold()
                }
            }
        }
    }

    private func addIngredient() {
        let cleanName = newName.trimmingCharacters(in: .whitespaces)
        guard !cleanName.isEmpty else { return }

        let cleanAmount = Double(newAmount.replacingOccurrences(of: ",", with: "."))
        let cleanUnit = newUnit.trimmingCharacters(in: .whitespaces)

        ingredients.append(IngredientItem(amount: cleanAmount, unit: cleanUnit, name: cleanName))

        newAmount = ""
        newUnit = ""
        newName = ""
    }

    private func addStep() {
        let cleanStep = newStep.trimmingCharacters(in: .whitespaces)
        guard !cleanStep.isEmpty else { return }

        instructions.append(cleanStep)
        newStep = ""
    }

    private func saveChanges() {
        recipe.title = title.trimmingCharacters(in: .whitespaces)
        recipe.category = category
        recipe.prepTime = prepTime.trimmingCharacters(in: .whitespaces)
        recipe.baseServings = baseServings
        recipe.ingredients = ingredients
        recipe.instructions = instructions

        try? modelContext.save()
        dismiss()
    }
}
