import SwiftUI
import SwiftData
import UIKit

public struct AddRecipeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var selectedTab: Int = 0 // 0: Link, 1: Text

    // Link Tab
    @State private var urlInput: String = ""
    @State private var clipboardURL: String? = nil

    // Text Tab
    @State private var textInput: String = ""
    @State private var optionalLinkInput: String = ""
    @State private var clipboardText: String? = nil

    @State private var showErrorAlert: Bool = false
    @State private var errorMessage: String = ""

    public init() {}

    public var body: some View {
        NavigationStack {
            Form {
                Picker("Eingabemodus", selection: $selectedTab) {
                    Text("Link").tag(0)
                    Text("Rezepttext").tag(1)
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .padding(.vertical, 4)

                if selectedTab == 0 {
                    linkSection
                } else {
                    textSection
                }

                Section {
                    Button {
                        startImport()
                    } label: {
                        HStack {
                            Spacer()
                            Text("Rezept hinzufügen")
                                .font(.headline)
                            Spacer()
                        }
                    }
                    .disabled(isButtonDisabled)
                }
            }
            .navigationTitle("Rezept hinzufügen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                checkClipboard()
            }
            .alert("Ungültige Eingabe", isPresented: $showErrorAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
        }
    }

    // MARK: - Link Tab View
    @ViewBuilder
    private var linkSection: some View {
        Section {
            TextField("https://www.tiktok.com/@...", text: $urlInput)
                .keyboardType(.URL)
                .autocapitalization(.none)
                .disableAutocorrection(true)

            if !urlInput.isEmpty {
                Button("Eingabe leeren") {
                    urlInput = ""
                }
                .foregroundColor(.secondary)
                .font(.footnote)
            }
        } header: {
            Text("Video- oder Rezept-Link")
        } footer: {
            Text("Unterstützt Links von TikTok, Facebook, Instagram, YouTube Shorts und Rezept-Websites.")
        }

        if let detected = clipboardURL, urlInput.isEmpty {
            Section {
                Button {
                    urlInput = detected
                    clipboardURL = nil
                } label: {
                    HStack {
                        Image(systemName: "doc.on.clipboard.fill")
                            .foregroundColor(.accentColor)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Link aus Zwischenablage einfügen")
                                .font(.subheadline.weight(.medium))
                            Text(detected)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Text Tab View
    @ViewBuilder
    private var textSection: some View {
        Section {
            TextEditor(text: $textInput)
                .frame(minHeight: 140)

            if let clip = clipboardText, textInput.isEmpty {
                Button {
                    textInput = clip
                    clipboardText = nil
                } label: {
                    Label("Text aus Zwischenablage einfügen", systemImage: "doc.on.clipboard.fill")
                        .font(.footnote.weight(.medium))
                }
            }
        } header: {
            Text("Kopierter Rezepttext / Caption")
        } footer: {
            Text("Füge hier kopierten Text aus Facebook-Posts, Notizen oder Messengern ein. Töpfle erkennt Zutaten und Schritte automatisch.")
        }

        Section("Optionaler Original-Link") {
            TextField("https://...", text: $optionalLinkInput)
                .keyboardType(.URL)
                .autocapitalization(.none)
                .disableAutocorrection(true)
        }
    }

    private var isButtonDisabled: Bool {
        if selectedTab == 0 {
            return urlInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        } else {
            return textInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private func checkClipboard() {
        if let clip = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines) {
            if clip.hasPrefix("http://") || clip.hasPrefix("https://") {
                clipboardURL = clip
            } else if clip.count > 10 {
                clipboardText = clip
            }
        }
    }

    private func startImport() {
        if selectedTab == 0 {
            let trimmed = urlInput.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let url = URL(string: trimmed), (url.scheme == "http" || url.scheme == "https") else {
                errorMessage = "Bitte gib eine gültige URL ein, die mit http:// oder https:// beginnt."
                showErrorAlert = true
                return
            }

            ImportQueueManager.shared.addManualImport(url: trimmed, rawText: nil, modelContext: modelContext)
            dismiss()
        } else {
            let cleanText = textInput.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleanText.isEmpty else { return }

            let cleanURL = optionalLinkInput.trimmingCharacters(in: .whitespacesAndNewlines)
            ImportQueueManager.shared.addManualImport(url: cleanURL, rawText: cleanText, modelContext: modelContext)
            dismiss()
        }
    }
}
