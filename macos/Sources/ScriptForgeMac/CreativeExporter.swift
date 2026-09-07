import Foundation
import ZIPFoundation

enum CreativeExportError: LocalizedError {
    case noAcceptedChapters

    var errorDescription: String? {
        switch self {
        case .noAcceptedChapters: "没有可导出的已接受章节"
        }
    }
}

enum CreativeExporter {
    static func makeExport(
        project: StoredProject,
        repository: ProjectRepository,
        chapterIDs: Set<UUID>? = nil
    ) throws -> CreativeProjectExport {
        guard let workspace = project.creativeWorkspace else { throw CreativeExportError.noAcceptedChapters }
        let selected = workspace.chapters
            .filter { chapterIDs == nil || chapterIDs!.contains($0.id) }
            .sorted { $0.number < $1.number }
        let chapters = try selected.compactMap { chapter -> CreativeExportChapter? in
            guard chapter.status == .accepted,
                  let versionID = chapter.currentVersionID,
                  let version = chapter.versions.first(where: { $0.id == versionID && $0.accepted })
            else { return nil }
            let content = try repository.readCreativeText(
                relativePath: version.contentPath,
                projectID: project.id
            )
            return CreativeExportChapter(
                number: chapter.number,
                volumeNumber: chapter.volumeNumber,
                title: chapter.title,
                content: content,
                versionID: version.id
            )
        }
        guard !chapters.isEmpty else { throw CreativeExportError.noAcceptedChapters }
        return CreativeProjectExport(
            schemaVersion: 1,
            projectName: project.name,
            brief: workspace.activeBrief,
            storyBible: workspace.activeStoryBible,
            outlines: workspace.outlines,
            chapters: chapters,
            characterStates: workspace.characterStates,
            timeline: workspace.timeline,
            foreshadowing: workspace.foreshadowing,
            exportedAt: Date()
        )
    }

    static func markdown(_ export: CreativeProjectExport) -> String {
        var lines = ["# \(export.projectName)", ""]
        var lastVolume: Int?
        for chapter in export.chapters {
            if lastVolume != chapter.volumeNumber {
                let volume = export.outlines.first(where: { $0.number == chapter.volumeNumber })
                lines.append("## \(volume?.title ?? "第\(chapter.volumeNumber)卷")")
                lines.append("")
                lastVolume = chapter.volumeNumber
            }
            lines.append("### 第\(chapter.number)章 \(chapter.title)")
            lines.append("")
            lines.append(chapter.content)
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    static func json(_ export: CreativeProjectExport) throws -> Data {
        try JSONEncoder.scriptForge.encode(export)
    }

    static func docx(_ export: CreativeProjectExport) throws -> Data {
        let temporary = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScriptForge-\(UUID().uuidString).docx")
        defer { try? FileManager.default.removeItem(at: temporary) }
        let archive = try Archive(url: temporary, accessMode: .create)
        try add(contentTypes, path: "[Content_Types].xml", to: archive)
        try add(packageRelationships, path: "_rels/.rels", to: archive)
        try add(documentXML(export), path: "word/document.xml", to: archive)
        return try Data(contentsOf: temporary)
    }

    private static func documentXML(_ export: CreativeProjectExport) -> String {
        var paragraphs: [(text: String, style: String?)] = [(export.projectName, "Title")]
        var lastVolume: Int?
        for chapter in export.chapters {
            if lastVolume != chapter.volumeNumber {
                let volume = export.outlines.first(where: { $0.number == chapter.volumeNumber })
                paragraphs.append((volume?.title ?? "第\(chapter.volumeNumber)卷", "Heading1"))
                lastVolume = chapter.volumeNumber
            }
            paragraphs.append(("第\(chapter.number)章 \(chapter.title)", "Heading2"))
            let chapterParagraphs = chapter.content
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            paragraphs.append(contentsOf: chapterParagraphs.map { ($0, nil) })
        }
        let body = paragraphs.map { paragraph in
            let style = paragraph.style.map { "<w:pPr><w:pStyle w:val=\"\($0)\"/></w:pPr>" } ?? ""
            if paragraph.text.isEmpty { return "<w:p/>" }
            return "<w:p>\(style)<w:r><w:t xml:space=\"preserve\">\(escapeXML(paragraph.text))</w:t></w:r></w:p>"
        }.joined()
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
          <w:body>\(body)<w:sectPr><w:pgSz w:w="11906" w:h="16838"/><w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440"/></w:sectPr></w:body>
        </w:document>
        """
    }

    private static func add(_ value: String, path: String, to archive: Archive) throws {
        let data = Data(value.utf8)
        try archive.addEntry(
            with: path,
            type: .file,
            uncompressedSize: Int64(data.count),
            compressionMethod: .deflate
        ) { position, size in
            data.subdata(in: Int(position)..<Int(position) + size)
        }
    }

    private static func escapeXML(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    private static let contentTypes = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
      <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
      <Default Extension="xml" ContentType="application/xml"/>
      <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
    </Types>
    """

    private static let packageRelationships = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
      <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
    </Relationships>
    """
}
