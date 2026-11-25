import Foundation

public enum SharedConstants {
    public static let appGroupID = "group.de.toepfle.app"
    public static let defaultBackendURL = "https://rezepte.icareberlin.de/api"
    public static let queueFileName = "pending_imports.json"

    private static let keyBackendURL = "toepfle_backend_url"
    private static let keyAPIKey = "toepfle_api_key"

    public static var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: appGroupID)
    }

    public static var backendURL: String {
        get {
            let stored = sharedDefaults?.string(forKey: keyBackendURL)?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let stored = stored, !stored.isEmpty {
                return stored
            }
            return defaultBackendURL
        }
        set {
            sharedDefaults?.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: keyBackendURL)
        }
    }

    public static var apiKey: String {
        get {
            sharedDefaults?.string(forKey: keyAPIKey) ?? ""
        }
        set {
            sharedDefaults?.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: keyAPIKey)
        }
    }

    public static func resetBackendURLToDefault() {
        sharedDefaults?.set(defaultBackendURL, forKey: keyBackendURL)
    }
}
