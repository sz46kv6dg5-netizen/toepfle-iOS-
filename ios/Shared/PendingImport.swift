import Foundation

public enum ImportStatus: String, Codable, CaseIterable {
    case queued
    case processing
    case failed
}

public struct PendingImport: Codable, Identifiable, Equatable {
    public let id: UUID
    public var url: String
    public var rawText: String?
    public let createdAt: Date
    public var status: ImportStatus
    public var errorMessage: String?

    public init(
        id: UUID = UUID(),
        url: String,
        rawText: String? = nil,
        createdAt: Date = Date(),
        status: ImportStatus = .queued,
        errorMessage: String? = nil
    ) {
        self.id = id
        self.url = url
        self.rawText = rawText
        self.createdAt = createdAt
        self.status = status
        self.errorMessage = errorMessage
    }
}

public final class PendingImportStore {
    public static let shared = PendingImportStore()

    private let fileCoordinator = NSFileCoordinator()

    private init() {}

    private var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: SharedConstants.appGroupID)
    }

    private var fileURL: URL? {
        containerURL?.appendingPathComponent(SharedConstants.queueFileName)
    }

    public func loadQueue() -> [PendingImport] {
        guard let url = fileURL else {
            return []
        }

        var result: [PendingImport] = []
        var coordinatorError: NSError?

        fileCoordinator.coordinate(readingItemAt: url, options: [], error: &coordinatorError) { readURL in
            guard FileManager.default.fileExists(atPath: readURL.path),
                  let data = try? Data(contentsOf: readURL) else {
                return
            }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            if let items = try? decoder.decode([PendingImport].self, from: data) {
                result = items
            }
        }

        return result
    }

    public func saveQueue(_ items: [PendingImport]) {
        guard let url = fileURL else { return }

        var coordinatorError: NSError?
        fileCoordinator.coordinate(writingItemAt: url, options: [], error: &coordinatorError) { writeURL in
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted]
            encoder.dateEncodingStrategy = .iso8601
            if let data = try? encoder.encode(items) {
                try? data.write(to: writeURL, options: .atomic)
            }
        }
    }

    @discardableResult
    public func addImport(url: String, rawText: String? = nil) -> PendingImport {
        let cleanURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        var items = loadQueue()

        // Vermeide doppelte identische Queued/Processing Einträge
        if !cleanURL.isEmpty, let existing = items.first(where: { $0.url == cleanURL && ($0.status == .queued || $0.status == .processing) }) {
            return existing
        }

        let newEntry = PendingImport(url: cleanURL, rawText: rawText, status: .queued)
        items.insert(newEntry, at: 0)
        saveQueue(items)
        return newEntry
    }

    public func updateStatus(id: UUID, status: ImportStatus, errorMessage: String? = nil) {
        var items = loadQueue()
        if let index = items.firstIndex(where: { $0.id == id }) {
            items[index].status = status
            items[index].errorMessage = errorMessage
            saveQueue(items)
        }
    }

    public func removeImport(id: UUID) {
        var items = loadQueue()
        items.removeAll(where: { $0.id == id })
        saveQueue(items)
    }
}
