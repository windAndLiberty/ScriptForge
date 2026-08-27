import AppKit
import Foundation
import XCTest
import ZIPFoundation
@testable import ScriptForgeMac

final class DocumentImporterTests: XCTestCase {
    func testCommonDocumentExtensionsAreRegistered() {
        let expected = ["docx", "doc", "pdf", "rtf", "rtfd", "txt", "md", "markdown", "html", "htm", "odt"]
        XCTAssertEqual(Set(DocumentImporter.supportedExtensions), Set(expected))
        for fileExtension in expected {
            XCTAssertTrue(DocumentImporter.supports(URL(fileURLWithPath: "/tmp/sample.\(fileExtension)")))
        }
    }

    func testImportsDOCXLocallyAndPreservesParagraphBoundaries() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScriptForgeDOCX-\(UUID().uuidString)", isDirectory: true)
        let url = directory.appendingPathComponent("sample.docx")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let xml = Data("""
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
          <w:body>
            <w:p><w:r><w:t>第1集：归来</w:t></w:r></w:p>
            <w:p><w:r><w:t>场次1：旧宅</w:t></w:r></w:p>
            <w:p><w:r><w:t>【画面】程野推开门。</w:t></w:r></w:p>
            <w:p><w:r><w:t>程野：我回来了。</w:t></w:r></w:p>
            <w:p><w:r><w:t>【钩子】屋内传来脚步声。</w:t></w:r></w:p>
          </w:body>
        </w:document>
        """.utf8)
        let archive = try Archive(url: url, accessMode: .create)
        try archive.addEntry(
            with: "word/document.xml",
            type: .file,
            uncompressedSize: Int64(xml.count),
            compressionMethod: .deflate
        ) { position, size in
            xml.subdata(in: Int(position)..<Int(position) + size)
        }

        let document = try DocumentImporter.load(from: url)

        XCTAssertEqual(document.resolvedSourceKind, .screenplay)
        XCTAssertEqual(document.chapters.count, 1)
        XCTAssertTrue(document.rawText.contains("程野：我回来了。"))
        XCTAssertTrue(document.rawText.contains("\n场次1：旧宅\n"))
    }

    func testDecodesUTF16PlainText() throws {
        let value = "第一章 归来\n中文正文"
        let data = try XCTUnwrap(value.data(using: .utf16LittleEndian))

        XCTAssertEqual(try DocumentImporter.decodePlainText(data), value)
    }

    func testImportsRTFAndHTMLAsPlainStoryText() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScriptForgeRichText-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let source = "CHAPTER 1 - Arrival\nMara opened the harbor gate."
        let attributed = NSAttributedString(string: source)
        let rtf = try attributed.data(
            from: NSRange(location: 0, length: attributed.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )
        let rtfURL = directory.appendingPathComponent("sample.rtf")
        try rtf.write(to: rtfURL)
        let htmlURL = directory.appendingPathComponent("sample.html")
        try "<h1>CHAPTER 1 - Arrival</h1><p>Mara opened the harbor gate.</p>"
            .write(to: htmlURL, atomically: true, encoding: .utf8)

        XCTAssertTrue(try DocumentImporter.load(from: rtfURL).rawText.contains("Mara opened the harbor gate."))
        XCTAssertTrue(try DocumentImporter.load(from: htmlURL).rawText.contains("Mara opened the harbor gate."))
    }

    func testImportsLegacyWordOpenDocumentAndRTFD() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScriptForgeNativeDocs-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let source = "CHAPTER 1 - Arrival\nMara opened the harbor gate."
        let attributed = NSAttributedString(string: source)
        for (type, fileExtension) in [
            (NSAttributedString.DocumentType.docFormat, "doc"),
            (NSAttributedString.DocumentType.openDocument, "odt"),
        ] {
            let data = try attributed.data(
                from: NSRange(location: 0, length: attributed.length),
                documentAttributes: [.documentType: type]
            )
            let url = directory.appendingPathComponent("sample.\(fileExtension)")
            try data.write(to: url)
            XCTAssertTrue(try DocumentImporter.load(from: url).rawText.contains("Mara opened the harbor gate."))
        }

        let wrapper = try attributed.fileWrapper(
            from: NSRange(location: 0, length: attributed.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtfd]
        )
        let rtfdURL = directory.appendingPathComponent("sample.rtfd", isDirectory: true)
        try wrapper.write(to: rtfdURL, options: .atomic, originalContentsURL: nil)
        XCTAssertTrue(try DocumentImporter.load(from: rtfdURL).rawText.contains("Mara opened the harbor gate."))
        XCTAssertEqual(
            try DocumentDropRequest.resolve(urls: [rtfdURL], route: .creation).url,
            rtfdURL
        )
    }

    @MainActor
    func testImportsTextBasedPDF() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScriptForgePDF-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 612, height: 792))
        textView.string = "CHAPTER 1 - Arrival\nMara opened the harbor gate."
        let url = directory.appendingPathComponent("sample.pdf")
        try textView.dataWithPDF(inside: textView.bounds).write(to: url)

        let document = try DocumentImporter.load(from: url)
        XCTAssertTrue(document.rawText.contains("Mara opened the harbor gate."))
    }

    @MainActor
    func testImageOnlyPDFReportsThatOCRIsRequired() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScriptForgeEmptyPDF-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let view = NSView(frame: NSRect(x: 0, y: 0, width: 612, height: 792))
        let url = directory.appendingPathComponent("scan.pdf")
        try view.dataWithPDF(inside: view.bounds).write(to: url)

        XCTAssertThrowsError(try DocumentImporter.load(from: url)) { error in
            guard case DocumentImportError.noExtractableText("pdf") = error else {
                return XCTFail("Expected OCR guidance, got \(error)")
            }
        }
    }
}
