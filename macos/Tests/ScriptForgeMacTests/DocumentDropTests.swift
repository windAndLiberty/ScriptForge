import Foundation
import XCTest
@testable import ScriptForgeMac

final class DocumentDropTests: XCTestCase {
    func testResolvesOneSupportedLocalFileForRequestedRoute() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Sample.MD")
        try "CHAPTER 1 - Arrival\nA train reached the coast.".write(
            to: url,
            atomically: true,
            encoding: .utf8
        )

        let request = try DocumentDropRequest.resolve(urls: [url], route: .creation)

        XCTAssertEqual(request.url, url)
        XCTAssertEqual(request.route, .creation)
        XCTAssertTrue(DocumentImporter.supports(url))
    }

    func testRejectsMultipleFilesUnsupportedFilesAndDirectories() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let markdown = directory.appendingPathComponent("one.md")
        let text = directory.appendingPathComponent("two.txt")
        let image = directory.appendingPathComponent("cover.png")
        try "CHAPTER 1\nOne".write(to: markdown, atomically: true, encoding: .utf8)
        try "CHAPTER 1\nTwo".write(to: text, atomically: true, encoding: .utf8)
        try Data([0, 1, 2]).write(to: image)

        XCTAssertThrowsError(
            try DocumentDropRequest.resolve(urls: [markdown, text], route: .adaptation)
        ) { error in
            XCTAssertEqual(error as? DocumentDropError, .multipleFiles)
        }
        XCTAssertThrowsError(
            try DocumentDropRequest.resolve(urls: [image], route: .adaptation)
        ) { error in
            guard case DocumentImportError.unsupportedFormat("png") = error else {
                return XCTFail("Expected unsupported PNG error, got \(error)")
            }
        }

        let fakeTextDirectory = directory.appendingPathComponent("folder.txt", isDirectory: true)
        try FileManager.default.createDirectory(at: fakeTextDirectory, withIntermediateDirectories: true)
        XCTAssertThrowsError(
            try DocumentDropRequest.resolve(urls: [fakeTextDirectory], route: .adaptation)
        ) { error in
            XCTAssertEqual(error as? DocumentDropError, .directoryNotSupported)
        }
    }

    private func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScriptForgeDropTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
