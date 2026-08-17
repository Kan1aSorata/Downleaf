import Foundation

struct RecoveredDraft: Codable, Sendable {
    let identifier: UUID
    let text: String
    let updatedAt: Date
}

enum RecoveryStore {
    private static let applicationFolderName = "Downleaf"
    private static let legacyApplicationFolderName = "MDReader"
    private static let folderName = "Recovery"

    static func save(identifier: UUID, text: String) throws {
        let directory = try recoveryDirectory(
            applicationFolderName: applicationFolderName,
            createIfNeeded: true
        )
        let draft = RecoveredDraft(identifier: identifier, text: text, updatedAt: Date())
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(draft)
        try data.write(to: directory.appendingPathComponent("\(identifier.uuidString).json"), options: .atomic)
    }

    static func remove(identifier: UUID) {
        for applicationFolderName in [applicationFolderName, legacyApplicationFolderName] {
            guard let directory = try? recoveryDirectory(
                applicationFolderName: applicationFolderName,
                createIfNeeded: false
            ) else { continue }
            try? FileManager.default.removeItem(
                at: directory.appendingPathComponent("\(identifier.uuidString).json")
            )
        }
    }

    static func loadAll() -> [RecoveredDraft] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var draftsByIdentifier: [UUID: RecoveredDraft] = [:]

        for applicationFolderName in [applicationFolderName, legacyApplicationFolderName] {
            guard let directory = try? recoveryDirectory(
                applicationFolderName: applicationFolderName,
                createIfNeeded: false
            ), let files = try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else { continue }

            for url in files where url.pathExtension == "json" {
                guard let data = try? Data(contentsOf: url),
                      let draft = try? decoder.decode(RecoveredDraft.self, from: data) else {
                    continue
                }
                if let existing = draftsByIdentifier[draft.identifier],
                   existing.updatedAt >= draft.updatedAt {
                    continue
                }
                draftsByIdentifier[draft.identifier] = draft
            }
        }

        return draftsByIdentifier.values
            .sorted { $0.updatedAt < $1.updatedAt }
    }

    private static func recoveryDirectory(
        applicationFolderName: String,
        createIfNeeded: Bool
    ) throws -> URL {
        let applicationSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: createIfNeeded
        )
        let directory = applicationSupport
            .appendingPathComponent(applicationFolderName, isDirectory: true)
            .appendingPathComponent(folderName, isDirectory: true)

        if createIfNeeded {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        }
        return directory
    }
}
