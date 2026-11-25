import SwiftUI

public struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var backendURL: String = ""
    @State private var apiKey: String = ""
    @State private var isTestingConnection: Bool = false
    @State private var connectionStatus: ConnectionStatus = .idle
    @State private var isAPIKeyVisible: Bool = false

    private enum ConnectionStatus: Equatable {
        case idle
        case success
        case failed(String)
    }

    public init() {}

    public var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("https://rezepte.icareberlin.de/api", text: $backendURL)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .onChange(of: backendURL) { _, newValue in
                            SharedConstants.backendURL = newValue
                            connectionStatus = .idle
                        }

                    Button("Auf Standard-URL zurücksetzen") {
                        SharedConstants.resetBackendURLToDefault()
                        backendURL = SharedConstants.defaultBackendURL
                        connectionStatus = .idle
                    }
                    .font(.footnote)
                    .foregroundColor(.accentColor)
                } header: {
                    Text("Backend API URL")
                } footer: {
                    Text("Standard: \(SharedConstants.defaultBackendURL)")
                }

                Section {
                    HStack {
                        if isAPIKeyVisible {
                            TextField("API Key", text: $apiKey)
                                .autocapitalization(.none)
                                .disableAutocorrection(true)
                        } else {
                            SecureField("API Key", text: $apiKey)
                        }

                        Button {
                            isAPIKeyVisible.toggle()
                        } label: {
                            Image(systemName: isAPIKeyVisible ? "eye.slash" : "eye")
                                .foregroundColor(.secondary)
                        }
                    }
                    .onChange(of: apiKey) { _, newValue in
                        SharedConstants.apiKey = newValue
                        connectionStatus = .idle
                    }
                } header: {
                    Text("Sicherheits-Schlüssel (X-API-Key)")
                } footer: {
                    Text("Wird für geschützte Anfragen an das Töpfle-Backend verwendet.")
                }

                Section {
                    Button {
                        testConnection()
                    } label: {
                        HStack {
                            if isTestingConnection {
                                ProgressView()
                                    .padding(.trailing, 8)
                            }
                            Text("Verbindung testen")
                        }
                    }
                    .disabled(isTestingConnection)

                    if connectionStatus == .success {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("Erfolgreich mit Backend verbunden!")
                                .font(.footnote.weight(.semibold))
                                .foregroundColor(.green)
                        }
                    } else if case .failed(let msg) = connectionStatus {
                        HStack(alignment: .top) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.red)
                            Text(msg)
                                .font(.footnote)
                                .foregroundColor(.red)
                        }
                    }
                }

                Section("App-Informationen") {
                    LabeledContent("App", value: "Töpfle")
                    LabeledContent("Version", value: "1.0.0 (Build 1)")
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
                backendURL = SharedConstants.backendURL
                apiKey = SharedConstants.apiKey
            }
        }
    }

    private func testConnection() {
        isTestingConnection = true
        connectionStatus = .idle

        Task {
            do {
                let success = try await RecipeAPIService.shared.checkHealth()
                await MainActor.run {
                    self.isTestingConnection = false
                    self.connectionStatus = success ? .success : .failed("Server antwortete nicht mit OK.")
                }
            } catch {
                await MainActor.run {
                    self.isTestingConnection = false
                    self.connectionStatus = .failed(error.localizedDescription)
                }
            }
        }
    }
}
