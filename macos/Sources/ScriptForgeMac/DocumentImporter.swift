import AppKit
import CoreFoundation
import Foundation
import PDFKit
import ZIPFoundation

enum DocumentImportError: LocalizedError {
    case unsupportedFormat(String)
    case unreadableText
    case invalidDOCX
    case invalidPDF
    case invalidRichText
    case noExtractableText(String)
    case documentTooLarge

    var errorDescription: String? {
        switch self {
        case let .unsupportedFormat(value):
            "暂不支持 \(value.isEmpty ? "该" : value.uppercased()) 格式；支持 DOCX、DOC、PDF、RTF、RTFD、TXT、Markdown、HTML 与 ODT"
        case .unreadableText:
            "无法读取文本编码；支持 UTF-8、UTF-16 与 GB18030"
        case .invalidDOCX:
            "DOCX 文件结构无效或正文已损坏"
        case .invalidPDF:
            "PDF 文件无效、已加密或正文已损坏"
        case .invalidRichText:
            "富文本文档无效或正文已损坏"
        case let .noExtractableText(format):
            "\(format.uppercased()) 中没有可提取的文字；扫描版 PDF 需要先进行 OCR"
        case .documentTooLarge:
            "文档超过本地安全解析上限"
        }
    }
}

enum DocumentImporter {
    static let supportedExtensions = [
        "docx", "doc", "pdf", "rtf", "rtfd", "txt", "md", "markdown", "html", "htm", "odt",
    ]
    static let supportedFormatNames = ["DOCX", "DOC", "PDF", "RTF", "RTFD", "TXT", "Markdown", "HTML", "ODT"]

    static func supports(_ url: URL) -> Bool {
        supportedExtensions.contains(url.pathExtension.lowercased())
    }

    private static let maximumArchiveBytes = 80 * 1_024 * 1_024
    private static let maximumXMLBytes: Int64 = 120 * 1_024 * 1_024
    private static let maximumTextCharacters = 20_000_000

    static func load(from url: URL) throws -> NovelDocument {
        let fileExtension = url.pathExtension.lowercased()
        guard supports(url) else {
            throw DocumentImportError.unsupportedFormat(fileExtension)
        }

        guard try measuredSize(of: url) <= maximumArchiveBytes else {
            throw DocumentImportError.documentTooLarge
        }

        let text: String
        switch fileExtension {
        case "docx":
            text = try extractDOCXText(from: url)
        case "pdf":
            text = try extractPDFText(from: url)
        case "rtf", "rtfd", "html", "htm", "doc", "odt":
            text = try extractAttributedText(from: url, fileExtension: fileExtension)
        default:
            let data = try Data(contentsOf: url, options: [.mappedIfSafe])
            text = try decodePlainText(data)
        }

        let normalized = normalize(text)
        guard normalized.count <= maximumTextCharacters else {
            throw DocumentImportError.documentTooLarge
        }
        guard !normalized.isEmpty else {
            throw DocumentImportError.noExtractableText(fileExtension)
        }
        return try NovelParser.parse(text: normalized, fileName: url.lastPathComponent)
    }

    static func decodePlainText(_ data: Data) throws -> String {
        let gb18030 = String.Encoding(
            rawValue: CFStringConvertEncodingToNSStringEncoding(
                CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
            )
        )
        let bytes = [UInt8](data.prefix(4))
        let utf16Order: [String.Encoding]
        if bytes.starts(with: [0xFF, 0xFE]) {
            utf16Order = [.utf16LittleEndian, .utf16BigEndian]
        } else if bytes.starts(with: [0xFE, 0xFF]) {
            utf16Order = [.utf16BigEndian, .utf16LittleEndian]
        } else {
            let sample = [UInt8](data.prefix(4_096))
            let evenNulls = sample.indices.filter { $0.isMultiple(of: 2) && sample[$0] == 0 }.count
            let oddNulls = sample.indices.filter { !$0.isMultiple(of: 2) && sample[$0] == 0 }.count
            utf16Order = evenNulls > oddNulls
                ? [.utf16BigEndian, .utf16LittleEndian]
                : [.utf16LittleEndian, .utf16BigEndian]
        }
        let encodings: [String.Encoding] = [.utf8] + utf16Order + [gb18030]
        for encoding in encodings {
            guard let value = String(data: data, encoding: encoding) else { continue }
            let nulls = value.unicodeScalars.filter { $0.value == 0 }.count
            guard nulls <= max(1, value.unicodeScalars.count / 1_000) else { continue }
            return value
                .trimmingCharacters(in: CharacterSet(charactersIn: "\u{FEFF}"))
                .precomposedStringWithCanonicalMapping
        }
        throw DocumentImportError.unreadableText
    }

    private static func extractDOCXText(from url: URL) throws -> String {
        let archive: Archive
        do {
            archive = try Archive(url: url, accessMode: .read)
        } catch {
            throw DocumentImportError.invalidDOCX
        }
        guard let entry = archive["word/document.xml"],
              Int64(entry.uncompressedSize) <= maximumXMLBytes else {
            throw DocumentImportError.invalidDOCX
        }

        var xml = Data()
        xml.reserveCapacity(min(Int(entry.uncompressedSize), 4 * 1_024 * 1_024))
        do {
            _ = try archive.extract(entry) { chunk in
                guard Int64(xml.count + chunk.count) <= maximumXMLBytes else {
                    throw DocumentImportError.documentTooLarge
                }
                xml.append(chunk)
            }
        } catch let error as DocumentImportError {
            throw error
        } catch {
            throw DocumentImportError.invalidDOCX
        }

        let delegate = WordprocessingMLTextDelegate()
        let parser = XMLParser(data: xml)
        parser.delegate = delegate
        parser.shouldProcessNamespaces = false
        guard parser.parse() else { throw DocumentImportError.invalidDOCX }
        let text = delegate.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw DocumentImportError.invalidDOCX }
        return text
    }

    private static func extractPDFText(from url: URL) throws -> String {
        guard let document = PDFDocument(url: url), !document.isLocked, document.pageCount > 0 else {
            throw DocumentImportError.invalidPDF
        }
        let pages = (0..<document.pageCount).compactMap { index -> String? in
            guard let value = document.page(at: index)?.string?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                !value.isEmpty else { return nil }
            return value
        }
        guard !pages.isEmpty else {
            throw DocumentImportError.noExtractableText("pdf")
        }
        return pages.joined(separator: "\n\n")
    }

    private static func extractAttributedText(from url: URL, fileExtension: String) throws -> String {
        let documentType: NSAttributedString.DocumentType = switch fileExtension {
        case "rtf": .rtf
        case "rtfd": .rtfd
        case "html", "htm": .html
        case "doc": .docFormat
        case "odt": .openDocument
        default: .plain
        }
        do {
            let value = try NSAttributedString(
                url: url,
                options: [.documentType: documentType],
                documentAttributes: nil
            ).string
            guard !normalize(value).isEmpty else {
                throw DocumentImportError.noExtractableText(fileExtension)
            }
            return value
        } catch let error as DocumentImportError {
            throw error
        } catch {
            throw DocumentImportError.invalidRichText
        }
    }

    private static func measuredSize(of url: URL) throws -> Int {
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
        guard values.isDirectory == true else { return values.fileSize ?? 0 }
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }
        var total = 0
        for case let child as URL in enumerator {
            let childValues = try child.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard childValues.isRegularFile == true else { continue }
            total += childValues.fileSize ?? 0
            if total > maximumArchiveBytes { return total }
        }
        return total
    }

    private static func normalize(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\u{FFFC}", with: "")
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: #"[ \t]+\n"#, with: "\n", options: .regularExpression)
            .replacingOccurrences(of: #"\n{4,}"#, with: "\n\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private final class WordprocessingMLTextDelegate: NSObject, XMLParserDelegate {
    private var paragraphs: [String] = []
    private var paragraph = ""
    private var isCollectingText = false
    private var ignoredDepth = 0

    var text: String {
        paragraphs.joined(separator: "\n")
            .replacingOccurrences(of: #"\n{4,}"#, with: "\n\n\n", options: .regularExpression)
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        let name = localName(elementName)
        if name == "del" || name == "instrText" {
            ignoredDepth += 1
            return
        }
        guard ignoredDepth == 0 else { return }
        switch name {
        case "p":
            paragraph = ""
        case "t":
            isCollectingText = true
        case "tab":
            paragraph.append("\t")
        case "br", "cr":
            paragraph.append("\n")
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard ignoredDepth == 0, isCollectingText else { return }
        paragraph.append(string)
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let name = localName(elementName)
        if name == "del" || name == "instrText" {
            ignoredDepth = max(0, ignoredDepth - 1)
            return
        }
        guard ignoredDepth == 0 else { return }
        switch name {
        case "t":
            isCollectingText = false
        case "p":
            paragraphs.append(paragraph.trimmingCharacters(in: .whitespaces))
            paragraph = ""
        default:
            break
        }
    }

    private func localName(_ value: String) -> String {
        value.split(separator: ":").last.map(String.init) ?? value
    }
}
