import Foundation

enum DocumentImportRoute: String, Hashable, Sendable {
    case adaptation
    case creation
}

enum DocumentDropError: LocalizedError, Equatable {
    case noFile
    case multipleFiles
    case notLocalFile
    case fileNotFound
    case directoryNotSupported

    var errorDescription: String? {
        switch self {
        case .noFile:
            "没有检测到可导入的文件"
        case .multipleFiles:
            "一次只能导入一个文档"
        case .notLocalFile:
            "拖入内容不是本地文件"
        case .fileNotFound:
            "拖入的文件不存在或已经移动"
        case .directoryNotSupported:
            "暂不支持导入文件夹；RTFD 文档包除外"
        }
    }
}

struct DocumentDropRequest: Equatable, Sendable {
    let url: URL
    let route: DocumentImportRoute

    static func resolve(
        urls: [URL],
        route: DocumentImportRoute,
        fileManager: FileManager = .default
    ) throws -> DocumentDropRequest {
        guard !urls.isEmpty else { throw DocumentDropError.noFile }
        guard urls.count == 1 else { throw DocumentDropError.multipleFiles }

        let url = urls[0]
        guard url.isFileURL else { throw DocumentDropError.notLocalFile }
        guard fileManager.fileExists(atPath: url.path) else {
            throw DocumentDropError.fileNotFound
        }

        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .isPackageKey])
        let isSupportedRTFDPackage = values.isPackage == true
            && url.pathExtension.lowercased() == "rtfd"
        guard values.isDirectory != true || isSupportedRTFDPackage else {
            throw DocumentDropError.directoryNotSupported
        }
        guard values.isRegularFile != false || isSupportedRTFDPackage else {
            throw DocumentDropError.directoryNotSupported
        }
        guard DocumentImporter.supports(url) else {
            throw DocumentImportError.unsupportedFormat(url.pathExtension.lowercased())
        }

        return DocumentDropRequest(url: url, route: route)
    }
}
