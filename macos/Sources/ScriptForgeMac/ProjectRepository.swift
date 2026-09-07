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
        let sourceDirectory = directoryURL(for: project.id)
        let destinationDirectory = directoryURL(for: copy.id)
        if FileManager.default.fileExists(atPath: sourceDirectory.path) {
            try FileManager.default.createDirectory(
                at: destinationDirectory.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try FileManager.default.copyItem(at: sourceDirectory, to: destinationDirectory)
        }
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

    func writeMedia(
        _ data: Data,
        fileExtension: String,
        projectID: UUID,
        episodeNumber: Int,
        shotID: String,
        kind: String
    ) throws -> String {
        let episodeDirectory = directoryURL(for: projectID)
            .appendingPathComponent("media", isDirectory: true)
            .appendingPathComponent(String(format: "episode-%03d", episodeNumber), isDirectory: true)
        try FileManager.default.createDirectory(at: episodeDirectory, withIntermediateDirectories: true)
        let safeShot = safeComponent(shotID)
        let safeKind = safeComponent(kind)
        let safeExtension = safeComponent(fileExtension.lowercased())
        let fileName = "\(safeShot)-\(safeKind).\(safeExtension)"
        try data.write(to: episodeDirectory.appendingPathComponent(fileName), options: .atomic)
        return "media/\(String(format: "episode-%03d", episodeNumber))/\(fileName)"
    }

    func writeWorkflowRun(_ run: WorkflowRun, projectID: UUID) throws {
        let directory = directoryURL(for: projectID)
            .appendingPathComponent("workflow-runs", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try encoder.encode(run).write(
            to: directory.appendingPathComponent("\(run.id.uuidString).json"),
            options: .atomic
        )
    }

    func loadWorkflowRuns(projectID: UUID) -> [WorkflowRun] {
        let directory = directoryURL(for: projectID)
            .appendingPathComponent("workflow-runs", isDirectory: true)
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return urls.compactMap { url in
            guard url.pathExtension == "json",
                  let data = try? Data(contentsOf: url),
                  var run = try? decoder.decode(WorkflowRun.self, from: data) else { return nil }
            if run.status == .running {
                run.status = .interrupted
                run.updatedAt = Date()
                try? writeWorkflowRun(run, projectID: projectID)
            }
            return run
        }.sorted { $0.updatedAt > $1.updatedAt }
    }

    func writeCreativeArtifact<T: Encodable>(
        _ value: T,
        artifactID: UUID,
        projectID: UUID
    ) throws -> String {
        let directory = directoryURL(for: projectID)
            .appendingPathComponent("workflow-artifacts", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileName = "\(artifactID.uuidString).json"
        try encoder.encode(value).write(to: directory.appendingPathComponent(fileName), options: .atomic)
        return "workflow-artifacts/\(fileName)"
    }

    func readCreativeArtifact<T: Decodable>(
        _ type: T.Type,
        relativePath: String,
        projectID: UUID
    ) throws -> T {
        let url = try creativeURL(relativePath: relativePath, projectID: projectID)
        return try decoder.decode(T.self, from: Data(contentsOf: url))
    }

    func writeChapterVersion(
        _ content: String,
        chapterID: UUID,
        versionID: UUID,
        projectID: UUID
    ) throws -> String {
        let relative = "chapters/\(chapterID.uuidString)/\(versionID.uuidString).md"
        let url = directoryURL(for: projectID).appendingPathComponent(relative)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try content.write(to: url, atomically: true, encoding: .utf8)
        return relative
    }

    func readCreativeText(relativePath: String, projectID: UUID) throws -> String {
        let url = try creativeURL(relativePath: relativePath, projectID: projectID)
        return try String(contentsOf: url, encoding: .utf8)
    }

    func writeChapterWorkingDraft(
        _ content: String,
        chapterID: UUID,
        projectID: UUID
    ) throws {
        let url = directoryURL(for: projectID)
            .appendingPathComponent("chapters/\(chapterID.uuidString)/working.md")
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    func readChapterWorkingDraft(chapterID: UUID, projectID: UUID) -> String? {
        let url = directoryURL(for: projectID)
            .appendingPathComponent("chapters/\(chapterID.uuidString)/working.md")
        return try? String(contentsOf: url, encoding: .utf8)
    }

    func mediaURL(relativePath: String, projectID: UUID) -> URL? {
        let normalized = relativePath.replacingOccurrences(of: "\\", with: "/")
        guard normalized.hasPrefix("media/"), !normalized.contains("../") else { return nil }
        let url = directoryURL(for: projectID).appendingPathComponent(normalized)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func rootDirectory() -> URL { rootURL }

    private func creativeURL(relativePath: String, projectID: UUID) throws -> URL {
        let normalized = relativePath.replacingOccurrences(of: "\\", with: "/")
        let allowed = normalized.hasPrefix("workflow-artifacts/")
            || normalized.hasPrefix("chapters/")
        guard allowed, !normalized.contains("../"), !normalized.hasPrefix("/") else {
            throw CocoaError(.fileReadInvalidFileName)
        }
        return directoryURL(for: projectID).appendingPathComponent(normalized)
    }

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

    private func safeComponent(_ value: String) -> String {
        let safe = value.replacingOccurrences(
            of: #"[^a-zA-Z0-9._-]"#,
            with: "-",
            options: .regularExpression
        )
        return safe.isEmpty ? "asset" : safe
    }
}
