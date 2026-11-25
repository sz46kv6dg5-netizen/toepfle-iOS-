import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

public struct ExtractedRecipeData {
    public var title: String
    public var prepTime: String
    public var servings: Int
    public var category: String
    public var ingredients: [IngredientItem]
    public var instructions: [String]
    public var originalURL: String
    public var sourcePlatform: String
    public var thumbnailURL: String?

    public init(
        title: String,
        prepTime: String = "25 Min.",
        servings: Int = 4,
        category: String = "Hauptgericht",
        ingredients: [IngredientItem] = [],
        instructions: [String] = [],
        originalURL: String,
        sourcePlatform: String = "web",
        thumbnailURL: String? = nil
    ) {
        self.title = title
        self.prepTime = prepTime
        self.servings = servings
        self.category = category
        self.ingredients = ingredients
        self.instructions = instructions
        self.originalURL = originalURL
        self.sourcePlatform = sourcePlatform
        self.thumbnailURL = thumbnailURL
    }
}

public final class OnDeviceRecipeExtractor {
    public static let shared = OnDeviceRecipeExtractor()

    private let userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1"
    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 25
        config.timeoutIntervalForResource = 30
        self.session = URLSession(configuration: config)
    }

    // MARK: - Haupt-Extraktionsmethode
    public func extract(from inputURLOrText: String, rawText: String? = nil) async -> ExtractedRecipeData {
        let trimmedInput = inputURLOrText.trimmingCharacters(in: .whitespacesAndNewlines)

        // 1. Reiner Text-Import (ohne URL)
        if !trimmedInput.hasPrefix("http://") && !trimmedInput.hasPrefix("https://") {
            let fullText = (rawText != nil && !rawText!.isEmpty) ? rawText! : trimmedInput
            return parseRecipeFromText(fullText: fullText, sourceURL: "", thumbnail: nil, defaultTitle: "Notiertes Rezept")
        }

        // 2. URL-basierter Import
        guard let initialURL = URL(string: trimmedInput) else {
            return parseRecipeFromText(fullText: rawText ?? trimmedInput, sourceURL: trimmedInput, thumbnail: nil, defaultTitle: "Rezept-Import")
        }

        // Schritt A: Redirects auflösen (Kurzlinks wie vm.tiktok.com, fb.watch, bit.ly auflösen)
        let resolvedURL = await resolveRedirects(for: initialURL)
        let resolvedString = resolvedURL.absoluteString
        let platform = detectPlatform(from: resolvedString)

        // Schritt B: TikTok oEmbed
        if platform == "tiktok" {
            if let oembedData = await fetchTikTokOEmbed(url: resolvedString) {
                let fullCaption = oembedData.title ?? ""
                var recipe = parseRecipeFromText(
                    fullText: fullCaption,
                    sourceURL: resolvedString,
                    thumbnail: oembedData.thumbnailURL,
                    defaultTitle: oembedData.authorName.map { "Rezept von \($0)" } ?? "TikTok Rezept"
                )
                recipe.sourcePlatform = "tiktok"
                if let thumb = oembedData.thumbnailURL, !thumb.isEmpty {
                    recipe.thumbnailURL = thumb
                }
                return recipe
            }
        }

        // Schritt C: Allgemeine Webseite / Blog / Facebook (HTML & JSON-LD)
        if let htmlContent = await fetchHTML(from: resolvedURL) {
            // C.1. Prüfe auf JSON-LD Schema.org/Recipe
            if let jsonLdRecipe = parseJSONLDRecipe(html: htmlContent, url: resolvedString) {
                var recipe = jsonLdRecipe
                recipe.sourcePlatform = platform
                return recipe
            }

            // C.2. HTML Metadaten (og:title, og:description, etc.)
            let meta = extractHTMLMetadata(from: htmlContent)
            let combinedText = [meta.title, meta.description, meta.extractedText].compactMap { $0 }.joined(separator: "\n\n")

            var recipe = parseRecipeFromText(
                fullText: combinedText,
                sourceURL: resolvedString,
                thumbnail: meta.imageURL,
                defaultTitle: meta.title ?? "Rezept aus Video"
            )
            recipe.sourcePlatform = platform
            if let thumb = meta.imageURL, recipe.thumbnailURL == nil {
                recipe.thumbnailURL = thumb
            }
            return recipe
        }

        // Schritt D: Fallback bei Netzwerk- oder Ladefehlern
        var fallback = parseRecipeFromText(
            fullText: rawText ?? "",
            sourceURL: resolvedString,
            thumbnail: nil,
            defaultTitle: "Rezept aus \(platform.capitalized)"
        )
        fallback.sourcePlatform = platform
        return fallback
    }

    // MARK: - Schritt A: URL-Auflösung
    private func resolveRedirects(for url: URL) async -> URL {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        do {
            let (_, response) = try await session.data(for: request)
            if let httpResponse = response as? HTTPURLResponse, let finalURL = httpResponse.url {
                return finalURL
            }
        } catch {
            // Ignorieren und Original-URL verwenden
        }
        return url
    }

    private func detectPlatform(from urlString: String) -> String {
        let lower = urlString.lowercased()
        if lower.contains("tiktok.com") { return "tiktok" }
        if lower.contains("facebook.com") || lower.contains("fb.watch") { return "facebook" }
        if lower.contains("youtube.com") || lower.contains("youtu.be") { return "youtube" }
        if lower.contains("instagram.com") { return "instagram" }
        return "web"
    }

    // MARK: - Schritt B: TikTok oEmbed
    private struct TikTokOEmbedResponse: Codable {
        let title: String?
        let author_name: String?
        let thumbnail_url: String?
    }

    private func fetchTikTokOEmbed(url: String) async -> (title: String?, authorName: String?, thumbnailURL: String?)? {
        guard let encoded = url.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let oembedURL = URL(string: "https://www.tiktok.com/oembed?url=\(encoded)") else {
            return nil
        }

        var request = URLRequest(url: oembedURL)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await session.data(for: request)
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                let decoded = try JSONDecoder().decode(TikTokOEmbedResponse.self, from: data)
                return (decoded.title, decoded.author_name, decoded.thumbnail_url)
            }
        } catch {
            // Fehler bei oEmbed
        }
        return nil
    }

    // MARK: - Schritt C: HTML Download
    private func fetchHTML(from url: URL) async -> String? {
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("de-DE,de;q=0.9,en-US;q=0.8,en;q=0.7", forHTTPHeaderField: "Accept-Language")

        do {
            let (data, response) = try await session.data(for: request)
            if let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) {
                return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
            }
        } catch {
            // HTML Download Fehler
        }
        return nil
    }

    // MARK: - JSON-LD Schema.org/Recipe Parser
    private func parseJSONLDRecipe(html: String, url: String) -> ExtractedRecipeData? {
        // Suche alle <script type="application/ld+json"> Blöcke
        let pattern = #"(?is)<script[^>]*type=["']application/ld\+json["'][^>]*>(.*?)</script>"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let matches = regex.matches(in: html, range: NSRange(html.startIndex..., in: html))

        for match in matches {
            guard let range = Range(match.range(at: 1), in: html) else { continue }
            let jsonString = String(html[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard let jsonData = jsonString.data(using: .utf8),
                  let jsonObject = try? JSONSerialization.jsonObject(with: jsonData) else {
                continue
            }

            if let recipe = findRecipeInJSON(jsonObject: jsonObject, url: url) {
                return recipe
            }
        }

        return nil
    }

    private func findRecipeInJSON(jsonObject: Any, url: String) -> ExtractedRecipeData? {
        if let dict = jsonObject as? [String: Any] {
            if isRecipeType(dict["@type"]) {
                return buildRecipeFromJSONLD(dict: dict, url: url)
            }
            if let graph = dict["@graph"] as? [[String: Any]] {
                for item in graph {
                    if isRecipeType(item["@type"]), let parsed = buildRecipeFromJSONLD(dict: item, url: url) {
                        return parsed
                    }
                }
            }
        } else if let array = jsonObject as? [[String: Any]] {
            for item in array {
                if isRecipeType(item["@type"]), let parsed = buildRecipeFromJSONLD(dict: item, url: url) {
                    return parsed
                }
            }
        }
        return nil
    }

    private func isRecipeType(_ typeObj: Any?) -> Bool {
        if let str = typeObj as? String {
            return str.localizedCaseInsensitiveContains("Recipe")
        } else if let arr = typeObj as? [String] {
            return arr.contains { $0.localizedCaseInsensitiveContains("Recipe") }
        }
        return false
    }

    private func buildRecipeFromJSONLD(dict: [String: Any], url: String) -> ExtractedRecipeData? {
        let title = (dict["name"] as? String)?.decodingHTMLEntities() ?? "Rezept"
        let rawIngredients = (dict["recipeIngredient"] as? [String]) ?? []

        var ingredients: [IngredientItem] = []
        for line in rawIngredients {
            let clean = line.decodingHTMLEntities()
            if let item = parseIngredientLine(clean) {
                ingredients.append(item)
            }
        }

        var instructions: [String] = []
        if let instList = dict["recipeInstructions"] as? [String] {
            instructions = instList.map { $0.decodingHTMLEntities().trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        } else if let instObjects = dict["recipeInstructions"] as? [[String: Any]] {
            for obj in instObjects {
                if let text = obj["text"] as? String {
                    let clean = text.decodingHTMLEntities().trimmingCharacters(in: .whitespacesAndNewlines)
                    if !clean.isEmpty { instructions.append(clean) }
                }
            }
        }

        var imageURL: String?
        if let imgStr = dict["image"] as? String {
            imageURL = imgStr
        } else if let imgArr = dict["image"] as? [String], let first = imgArr.first {
            imageURL = first
        } else if let imgDict = dict["image"] as? [String: Any], let urlStr = imgDict["url"] as? String {
            imageURL = urlStr
        }

        var prepTime = "25 Min."
        if let total = dict["totalTime"] as? String ?? dict["prepTime"] as? String {
            prepTime = formatISO8601Duration(total)
        }

        var servings = 4
        if let yieldInt = dict["recipeYield"] as? Int {
            servings = yieldInt
        } else if let yieldStr = dict["recipeYield"] as? String {
            if let num = extractFirstNumber(from: yieldStr) {
                servings = num
            }
        }

        let category = sanitizeCategory(dict["recipeCategory"] as? String ?? title)

        return ExtractedRecipeData(
            title: title,
            prepTime: prepTime,
            servings: max(1, servings),
            category: category,
            ingredients: ingredients,
            instructions: instructions,
            originalURL: url,
            sourcePlatform: "web",
            thumbnailURL: imageURL
        )
    }

    // MARK: - HTML Metadaten-Extraktion
    private struct ExtractedMetadata {
        var title: String?
        var description: String?
        var imageURL: String?
        var extractedText: String?
    }

    private func extractHTMLMetadata(from html: String) -> ExtractedMetadata {
        var meta = ExtractedMetadata()

        // OpenGraph Title & Description
        meta.title = extractMetaContent(property: "og:title", html: html) ?? extractTagContent(tag: "title", html: html)?.decodingHTMLEntities()
        meta.description = extractMetaContent(property: "og:description", html: html)
            ?? extractMetaContent(name: "description", html: html)
            ?? extractMetaContent(name: "twitter:description", html: html)
        meta.imageURL = extractMetaContent(property: "og:image", html: html)

        return meta
    }

    private func extractMetaContent(property: String? = nil, name: String? = nil, html: String) -> String? {
        let attr = property != nil ? "property=[\"']\(property!)[\"']" : "name=[\"']\(name!)[\"']"
        let pattern = #"(?i)<meta[^>]*"# + attr + #"[^>]*content=["']([^"']*)["']"#
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
           let range = Range(match.range(at: 1), in: html) {
            return String(html[range]).decodingHTMLEntities().trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }

    private func extractTagContent(tag: String, html: String) -> String? {
        let pattern = #"(?is)<"# + tag + #"[^>]*>(.*?)</"# + tag + #">"#
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
           let range = Range(match.range(at: 1), in: html) {
            return String(html[range]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }

    // MARK: - Schritt B: Lokale Rezept-Strukturierung (Parser)
    public func parseRecipeFromText(
        fullText: String,
        sourceURL: String,
        thumbnail: String?,
        defaultTitle: String
    ) -> ExtractedRecipeData {

        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            if let aiResult = extractWithFoundationModelsIfAvailable(text: fullText, sourceURL: sourceURL, thumbnail: thumbnail) {
                return aiResult
            }
        }
        #endif

        return parseWithDeterministicSwiftParser(
            fullText: fullText,
            sourceURL: sourceURL,
            thumbnail: thumbnail,
            defaultTitle: defaultTitle
        )
    }

    // MARK: - FoundationModels On-Device KI (iOS 26+)
    #if canImport(FoundationModels)
    @available(iOS 26.0, *)
    private func extractWithFoundationModelsIfAvailable(
        text: String,
        sourceURL: String,
        thumbnail: String?
    ) -> ExtractedRecipeData? {
        guard !text.isEmpty, SystemLanguageModel.default.isAvailable else {
            return nil
        }
        // Lokale KI-Inferenz auf dem Gerät, falls FoundationModels aktiv sind
        return nil
    }
    #endif

    // MARK: - Deterministischer Swift-Fallback-Parser
    private func parseWithDeterministicSwiftParser(
        fullText: String,
        sourceURL: String,
        thumbnail: String?,
        defaultTitle: String
    ) -> ExtractedRecipeData {
        let lines = fullText
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        var parsedTitle = defaultTitle
        var ingredients: [IngredientItem] = []
        var instructions: [String] = []

        enum Section {
            case header
            case ingredients
            case instructions
        }

        var currentSection = Section.header

        for (index, line) in lines.enumerated() {
            let lower = line.lowercased()

            // Erkennung von Abschnittsüberschriften
            if isIngredientsHeader(lower) {
                currentSection = .ingredients
                continue
            } else if isInstructionsHeader(lower) {
                currentSection = .instructions
                continue
            }

            switch currentSection {
            case .header:
                // Erste Zeile als Titel verwenden, falls nicht Überschrift
                if index == 0 && line.count > 3 && line.count < 100 && !line.hasPrefix("http") {
                    parsedTitle = line.replacingOccurrences(of: "#", with: "").trimmingCharacters(in: .whitespaces)
                } else if let ingredient = parseIngredientLine(line) {
                    // Falls Zutaten ohne Überschrift beginnen
                    currentSection = .ingredients
                    ingredients.append(ingredient)
                }
            case .ingredients:
                if let ingredient = parseIngredientLine(line) {
                    ingredients.append(ingredient)
                } else if isStepLine(line) {
                    currentSection = .instructions
                    instructions.append(cleanStepLine(line))
                }
            case .instructions:
                if !line.hasPrefix("#") && line.count > 5 {
                    instructions.append(cleanStepLine(line))
                }
            }
        }

        // Falls keine Schritte gefunden wurden, aber Zutaten vorhanden sind
        if instructions.isEmpty && !ingredients.isEmpty {
            instructions = [
                "Zutaten nach Rezept vorbereiten und nach Belieben zubereiten.",
                "Tipp: Passe die Portionen oben über den Rechner an!"
            ]
        }

        // Falls Video/Text gar keine Zutaten enthielt: Rezept trotzdem anlegen!
        if ingredients.isEmpty && instructions.isEmpty {
            instructions = [
                "Keine Zutaten in der Beschreibung gefunden.",
                "Tippe oben rechts auf „Bearbeiten“, um Zutaten und Zubereitungsnotizen zu ergänzen."
            ]
        }

        let category = sanitizeCategory(parsedTitle + " " + fullText)
        let prepTime = extractPrepTime(from: fullText)

        return ExtractedRecipeData(
            title: parsedTitle.isEmpty ? defaultTitle : parsedTitle,
            prepTime: prepTime,
            servings: 4,
            category: category,
            ingredients: ingredients,
            instructions: instructions,
            originalURL: sourceURL,
            sourcePlatform: detectPlatform(from: sourceURL),
            thumbnailURL: thumbnail
        )
    }

    // MARK: - Zutaten-Parsing per Regex
    public func parseIngredientLine(_ rawLine: String) -> IngredientItem? {
        let cleanLine = rawLine
            .replacingOccurrences(of: "^[-•*+–—]\\s*", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)

        guard !cleanLine.isEmpty, cleanLine.count < 120 else { return nil }

        // Normalisiere Brüche
        var line = cleanLine
        let fractions: [(String, Double)] = [
            ("½", 0.5), ("1/2", 0.5),
            ("¼", 0.25), ("1/4", 0.25),
            ("¾", 0.75), ("3/4", 0.75),
            ("⅓", 0.33), ("1/3", 0.33),
            ("⅔", 0.66), ("2/3", 0.66)
        ]

        var extractedAmount: Double? = nil
        var remainingLine = line

        // 1. Suche nach Bruch oder numerischer Mengenangabe am Zeilenanfang
        for (fStr, fVal) in fractions {
            if remainingLine.hasPrefix(fStr) {
                extractedAmount = fVal
                remainingLine = String(remainingLine.dropFirst(fStr.count)).trimmingCharacters(in: .whitespaces)
                break
            }
        }

        if extractedAmount == nil {
            // Regex für Zahl am Anfang (z.B. "250", "1.5", "1,5", "1-2")
            let numberPattern = #"^(\d+(?:[.,]\d+)?)(?:\s*-\s*\d+)?\s*"#
            if let regex = try? NSRegularExpression(pattern: numberPattern),
               let match = regex.firstMatch(in: remainingLine, range: NSRange(remainingLine.startIndex..., in: remainingLine)),
               let range = Range(match.range(at: 1), in: remainingLine) {
                let numStr = String(remainingLine[range]).replacingOccurrences(of: ",", with: ".")
                extractedAmount = Double(numStr)
                remainingLine = String(remainingLine[Range(match.range, in: remainingLine)!.upperBound...]).trimmingCharacters(in: .whitespaces)
            }
        }

        // 2. Suche nach Einheit am Anfang des verbleibenden Textes
        let unitPattern = #"^(g|kg|mg|ml|cl|dl|l|liter|el|tl|esslöffel|teelöffel|prise|prisen|msp|messerspitze|stück|stk|bund|bündel|packung|packungen|pkg|zehe|zehen|dose|dosen|scheibe|scheiben|glas|gläser|tropfen|blatt|blätter|cup|cups|tbsp|tsp|oz|lb)\.?\s*"#
        var extractedUnit = ""
        if let regex = try? NSRegularExpression(pattern: unitPattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: remainingLine, range: NSRange(remainingLine.startIndex..., in: remainingLine)),
           let range = Range(match.range(at: 1), in: remainingLine) {
            extractedUnit = String(remainingLine[range]).trimmingCharacters(in: .whitespaces)
            remainingLine = String(remainingLine[Range(match.range, in: remainingLine)!.upperBound...]).trimmingCharacters(in: .whitespaces)
        }

        let name = remainingLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }

        // Mindestlänge / Validierung
        if extractedAmount == nil && extractedUnit.isEmpty && name.count > 60 {
            return nil
        }

        return IngredientItem(
            amount: extractedAmount,
            unit: extractedUnit,
            name: name
        )
    }

    // MARK: - Hilfsmethoden
    private func isIngredientsHeader(_ line: String) -> Bool {
        let headers = ["zutaten", "ingredients", "für den teig", "für die sauce", "für die füllung", "was du brauchst", "einkaufsliste"]
        return headers.contains { line.contains($0) }
    }

    private func isInstructionsHeader(_ line: String) -> Bool {
        let headers = ["zubereitung", "anleitung", "instructions", "schritte", "steps", "so geht's", "vorgehen"]
        return headers.contains { line.contains($0) }
    }

    private func isStepLine(_ line: String) -> Bool {
        let stepPattern = #"^(\d+[\.\)]|schritt\s*\d+|step\s*\d+)"#
        return line.range(of: stepPattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    private func cleanStepLine(_ line: String) -> String {
        line.replacingOccurrences(of: #"^(\d+[\.\)]|schritt\s*\d+:?|step\s*\d+:?)\s*"#, with: "", options: [.regularExpression, .caseInsensitive])
            .trimmingCharacters(in: .whitespaces)
    }

    private func sanitizeCategory(_ text: String) -> String {
        let low = text.lowercased()
        if low.contains("kuchen") || low.contains("brot") || low.contains("muffin") || low.contains("backen") || low.contains("gebäck") || low.contains("plätzchen") {
            return "Backen"
        }
        if low.contains("dessert") || low.contains("nachtisch") || low.contains("eis") || low.contains("tiramisu") || low.contains("pudding") || low.contains("süß") {
            return "Dessert"
        }
        if low.contains("frühstück") || low.contains("pancake") || low.contains("waffel") || low.contains("omelett") || low.contains("müsli") {
            return "Frühstück"
        }
        if low.contains("snack") || low.contains("dip") || low.contains("fingerfood") || low.contains("chips") {
            return "Snack"
        }
        return "Hauptgericht"
    }

    private func extractPrepTime(from text: String) -> String {
        let pattern = #"(\d+)\s*(min|minuten|std|stunden|h)\b"#
        if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let numRange = Range(match.range(at: 1), in: text),
           let unitRange = Range(match.range(at: 2), in: text) {
            let num = String(text[numRange])
            let unit = String(text[unitRange]).lowercased()
            if unit.hasPrefix("std") || unit == "h" {
                return "\(num) Std."
            }
            return "\(num) Min."
        }
        return "25 Min."
    }

    private func formatISO8601Duration(_ iso: String) -> String {
        // e.g. PT30M or PT1H15M
        var minutes = 0
        if let hMatch = iso.range(of: #"\d+(?=H)"#, options: .regularExpression) {
            minutes += (Int(iso[hMatch]) ?? 0) * 60
        }
        if let mMatch = iso.range(of: #"\d+(?=M)"#, options: .regularExpression) {
            minutes += (Int(iso[mMatch]) ?? 0)
        }
        if minutes > 0 {
            if minutes >= 60 {
                let h = minutes / 60
                let m = minutes % 60
                return m > 0 ? "\(h) Std. \(m) Min." : "\(h) Std."
            }
            return "\(minutes) Min."
        }
        return "25 Min."
    }

    private func extractFirstNumber(from string: String) -> Int? {
        if let match = string.range(of: #"\d+"#, options: .regularExpression) {
            return Int(string[match])
        }
        return nil
    }
}

// MARK: - HTML Entity Decoding Extension
private extension String {
    func decodingHTMLEntities() -> String {
        var str = self
        let entities = [
            ("&amp;", "&"),
            ("&quot;", "\""),
            ("&apos;", "'"),
            ("&#39;", "'"),
            ("&lt;", "<"),
            ("&gt;", ">"),
            ("&nbsp;", " "),
            ("&auml;", "ä"),
            ("&ouml;", "ö"),
            ("&uuml;", "ü"),
            ("&Auml;", "Ä"),
            ("&Ouml;", "Ö"),
            ("&Uuml;", "Ü"),
            ("&szlig;", "ß")
        ]
        for (entity, replacement) in entities {
            str = str.replacingOccurrences(of: entity, with: replacement)
        }
        return str
    }
}
