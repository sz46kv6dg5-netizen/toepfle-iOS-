import Foundation

public struct RecipeResponseDTO: Codable {
    public let title: String
    public let prep_time: String
    public let servings: Int
    public let category: String
    public let ingredients: [IngredientDTO]
    public let instructions: [String]
    public let original_url: String
    public let source_platform: String
    public let thumbnail_url: String?
}

public struct IngredientDTO: Codable {
    public let amount: Double?
    public let unit: String
    public let name: String
}

public enum APIError: LocalizedError {
    case invalidURL
    case serverError(statusCode: Int, message: String)
    case decodingError(String)
    case unauthorized
    case networkError(String)

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Ungültige Server-URL konfiguriert."
        case .serverError(let code, let msg):
            return "Serverfehler (\(code)): \(msg)"
        case .decodingError(let msg):
            return "Antwort konnte nicht verarbeitet werden: \(msg)"
        case .unauthorized:
            return "API-Key ist ungültig oder nicht autorisiert (401)."
        case .networkError(let msg):
            return "Netzwerkfehler: \(msg)"
        }
    }
}

public final class RecipeAPIService {
    public static let shared = RecipeAPIService()

    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 120
        config.timeoutIntervalForResource = 150
        self.session = URLSession(configuration: config)
    }

    private func buildEndpointURL(path: String) throws -> URL {
        var base = SharedConstants.backendURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if base.hasSuffix("/") {
            base.removeLast()
        }
        let cleanPath = path.hasPrefix("/") ? path : "/\(path)"
        guard let url = URL(string: base + cleanPath) else {
            throw APIError.invalidURL
        }
        return url
    }

    public func checkHealth() async throws -> Bool {
        let url = try buildEndpointURL(path: "/health")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 10

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            return false
        }
        if httpResponse.statusCode == 200 {
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let status = json["status"] as? String, status == "ok" {
                return true
            }
            return true
        }
        return false
    }

    public func extractRecipe(from urlString: String) async throws -> RecipeResponseDTO {
        let endpoint = try buildEndpointURL(path: "/extract-recipe")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let apiKey = SharedConstants.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !apiKey.isEmpty {
            request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        }

        let bodyPayload: [String: String] = ["url": urlString]
        request.httpBody = try JSONEncoder().encode(bodyPayload)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.networkError(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.networkError("Ungültige Server-Antwort.")
        }

        if httpResponse.statusCode == 401 {
            throw APIError.unauthorized
        }

        if httpResponse.statusCode != 200 {
            var errorMsg = "Fehlercode \(httpResponse.statusCode)"
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let detail = json["detail"] as? String {
                errorMsg = detail
            } else if let text = String(data: data, encoding: .utf8), !text.isEmpty {
                errorMsg = text
            }
            throw APIError.serverError(statusCode: httpResponse.statusCode, message: errorMsg)
        }

        do {
            let decoder = JSONDecoder()
            return try decoder.decode(RecipeResponseDTO.self, from: data)
        } catch {
            throw APIError.decodingError(error.localizedDescription)
        }
    }
}
