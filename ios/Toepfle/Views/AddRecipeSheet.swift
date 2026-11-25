import SwiftUI
import SwiftData
import UIKit

public struct AddRecipeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var urlInput: String = ""
    @State private var clipboardURL: String? = nil
    @State private var showErrorAlert: Bool = false
    @State private var errorMessage: String = ""

    public init() {}

    public var body: some View {
        NavigationStack {
            Form {
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

                Section {
                    Button {
                        startImport()
                    } label: {
                        HStack {
                            Spacer()
                            Text("Rezept importieren")
                                .font(.headline)
                            Spacer()
                        }
                    }
                    .disabled(urlInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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
            .alert("Ungültiger Link", isPresented: $showErrorAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
        }
    }

    private func checkClipboard() {
        if let clip = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines),
           clip.hasPrefix("http://") || clip.hasPrefix("https://") {
            clipboardURL = clip
        }
    }

    private func startImport() {
        let trimmed = urlInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), (url.scheme == "http" || url.scheme == "https") else {
            errorMessage = "Bitte gib eine gültige URL ein, die mit http:// oder https:// beginnt."
            showErrorAlert = true
            return
        }

        ImportQueueManager.shared.addManualImport(url: trimmed, modelContext: modelContext)
        dismiss()
    }
}
