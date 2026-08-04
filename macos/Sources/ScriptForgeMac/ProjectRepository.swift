import Foundation

enum ProjectRepositoryError: LocalizedError {
    case cannotDeleteRecentProject
    case projectNotFound

    var errorDescription: String? {
        switch self {
        case .cannotDeleteRecentProject:
            "只有已归档项目可以永久删除"
        case .projectNotFound:
            "项目不存在或已经被删除"
        }
    }
}

final class ProjectRepository {
    static let recentLimit = 50

    private let rootURL: URL
    private let encoder = JSONEncoder.scriptForge
    private let decoder = JSONDecoder.scriptForge

    init(baseURL: URL? = nil) {
        let support = baseURL ?? FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!.appendingPathComponent("ScriptForge", isDirectory: true)
        rootURL = support.appendingPathComponent("Projects", isDirectory: true)
    }

    func loadAll() -> [StoredProject] {
        guard let directories = try? FileManager.default.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return directories.compactMap { directory in
            let manifest = directory.appendingPathComponent("project.json")
            guard
                let data = try? Data(contentsOf: manifest),
                var project = try? decoder.decode(StoredProject.self, from: data)
            else { return nil }
            project.schemaVersion = StoredProject.currentSchemaVersion
            return project
        }.sorted { $0.updatedAt > $1.updatedAt }
    }

    @discardableResult
    func save(_ incoming: StoredProject) throws -> [StoredProject] {
        var project = incoming
        project.schemaVersion = StoredProject.currentSchemaVersion
        project.updatedAt = Date()
        try write(project)

        var projects = loadAll()
        let recent = projects.filter { $0.archivedAt == nil }.sorted { $0.updatedAt > $1.updatedAt }
        if recent.count > Self.recentLimit {
            for overflow in recent.dropFirst(Self.recentLimit) {
                var archived = overflow
                archived.archivedAt = Date()
                archived.updatedAt = Date()
                try write(archived)
            }
            projects = loadAll()
        }
        return projects
    }

    func archive(_ project: StoredProject) throws -> [StoredProject] {
        var updated = project
        updated.archivedAt = Date()
        updated.updatedAt = Date()
        try write(updated)
        return loadAll()
    }

    func restore(_ project: StoredProject) throws -> [StoredProject] {
        var updated = project
        updated.archivedAt = nil
        updated.updatedAt = Date()
        try write(updated)
        return try save(updated)
    }

    func delete(_ project: StoredProject) throws -> [StoredProject] {
        guard project.archivedAt != nil else {
            throw ProjectRepositoryError.cannotDeleteRecentProject
        }
        let directory = directoryURL(for: project.id)
        guard FileManager.default.fileExists(atPath: directory.path) else {
            throw ProjectRepositoryError.projectNotFound
        }
        try FileManager.default.removeItem(at: directory)
        return loadAll()
    }

    func duplicate(_ project: StoredProject) throws -> (StoredProject, [StoredProject]) {
        var copy = project
        copy.id = UUID()
        copy.name += " · 副本"
        copy.archivedAt = nil
        copy.createdAt = Date()
        copy.updatedAt = Date()
        let projects = try save(copy)
        return (copy, projects)
    }

    func writeArtifact<T: Encodable>(_ value: T, name: String, projectID: UUID) throws {
        let directory = directoryURL(for: projectID).appendingPathComponent("artifacts", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let safeName = name.replacingOccurrences(
            of: #"[^a-zA-Z0-9._-]"#,
            with: "-",
            options: .regularExpression
        )
        try encoder.encode(value).write(
            to: directory.appendingPathComponent("\(safeName).json"),
            options: .atomic
        )
    }

    func rootDirectory() -> URL { rootURL }

    private func write(_ project: StoredProject) throws {
        let directory = directoryURL(for: project.id)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try encoder.encode(project).write(
            to: directory.appendingPathComponent("project.json"),
            options: .atomic
        )
        if let source = project.document?.rawText {
            try source.write(
                to: directory.appendingPathComponent("source.txt"),
                atomically: true,
                encoding: .utf8
            )
        }
    }

    private func directoryURL(for projectID: UUID) -> URL {
        rootURL.appendingPathComponent(projectID.uuidString, isDirectory: true)
    }
}
