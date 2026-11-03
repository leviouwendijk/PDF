import Foundation
import Milieu
import PDF
import PDFCore

private enum FixtureFailure: Error {
    case invalid_root(String)
    case no_pdfs(String)
    case unknown_selection(String)
    case read_failed(String, String)
    case invalid_document(String)
    case invalid_line(String, Int, String)
}

private struct Fixture {
    let relativePath: String
    let url: URL
}

private struct Metrics {
    let pages: Int
    let nativeTextPages: Int
    let nativeLines: Int
    let withoutNativeText: Int
    let textWithoutLines: Int
}

@main
struct PDFFixtureTests {
    static func main() throws {
        let path = try EnvironmentExtractor.value("PDF_TEST_FILES")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { throw FixtureFailure.invalid_root("PDF_TEST_FILES is empty") }

        let root = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw FixtureFailure.invalid_root(root.path)
        }

        let available = try discoverPDFs(in: root)
        let requested = Array(CommandLine.arguments.dropFirst())
        let selected = try selectFixtures(from: available, requested: requested)

        var totalPages = 0
        var totalNativeTextPages = 0
        var totalNativeLines = 0
        var totalWithoutNativeText = 0
        var totalTextWithoutLines = 0

        for fixture in selected {
            let metrics = try inspect(fixture)
            totalPages += metrics.pages
            totalNativeTextPages += metrics.nativeTextPages
            totalNativeLines += metrics.nativeLines
            totalWithoutNativeText += metrics.withoutNativeText
            totalTextWithoutLines += metrics.textWithoutLines
            print([
                "fixture=\(fixture.relativePath)",
                "pages=\(metrics.pages)",
                "native_text_pages=\(metrics.nativeTextPages)",
                "lines=\(metrics.nativeLines)",
                "no_native_text=\(metrics.withoutNativeText)",
                "text_without_lines=\(metrics.textWithoutLines)"
            ].joined(separator: " "))
        }

        print([
            "t_pdf_fixtures: passed",
            "files=\(selected.count)",
            "pages=\(totalPages)",
            "native_text_pages=\(totalNativeTextPages)",
            "lines=\(totalNativeLines)",
            "no_native_text=\(totalWithoutNativeText)",
            "text_without_lines=\(totalTextWithoutLines)"
        ].joined(separator: " "))
    }

    /// Discover only PDF files; other invoice image and document formats are outside this pass.
    private static func discoverPDFs(in root: URL) throws -> [Fixture] {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            throw FixtureFailure.invalid_root(root.path)
        }

        let rootComponents = root.pathComponents
        var fixtures: [Fixture] = []
        for case let candidate as URL in enumerator {
            guard candidate.pathExtension.lowercased() == "pdf" else { continue }
            let isRegularFile = try candidate.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true
            guard isRegularFile else { continue }

            let components = candidate.standardizedFileURL.pathComponents
            guard components.starts(with: rootComponents),
                  components.count > rootComponents.count else { continue }

            let relative = components.dropFirst(rootComponents.count).joined(separator: "/")
            fixtures.append(Fixture(relativePath: relative, url: candidate.standardizedFileURL))
        }
        guard !fixtures.isEmpty else { throw FixtureFailure.no_pdfs(root.path) }
        return fixtures.sorted { $0.relativePath < $1.relativePath }
    }

    /// With no arguments, select one PDF per top-level directory. Otherwise use
    /// exact relative filenames passed as arguments (including spaces if quoted).
    private static func selectFixtures(from fixtures: [Fixture], requested: [String]) throws -> [Fixture] {
        if requested.isEmpty {
            var seen = Set<String>()
            return fixtures.filter { fixture in
                let group = fixture.relativePath.split(separator: "/", maxSplits: 1)
                    .first.map(String.init) ?? fixture.relativePath
                return seen.insert(group).inserted
            }
        }

        let byPath = Dictionary(uniqueKeysWithValues: fixtures.map { ($0.relativePath, $0) })
        return try requested.map { relativePath in
            guard let fixture = byPath[relativePath] else {
                throw FixtureFailure.unknown_selection(relativePath)
            }
            return fixture
        }
    }

    private static func inspect(_ fixture: Fixture) throws -> Metrics {
        let document: PDFDocumentSnapshot
        do {
            document = try PDFReader.read(fixture.url)
        } catch {
            throw FixtureFailure.read_failed(fixture.relativePath, String(describing: error))
        }

        guard document.source.url == fixture.url,
              document.source.byteCount > 0,
              !document.pages.isEmpty else {
            throw FixtureFailure.invalid_document(fixture.relativePath)
        }

        var nativeTextPages = 0
        var nativeLines = 0
        var withoutNativeText = 0
        var textWithoutLines = 0

        for page in document.pages {
            let lines = document.nodes(onPage: page.index, kind: .line)
            let hasNativeText = page.textSnapshots.contains {
                !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            if hasNativeText {
                nativeTextPages += 1
                if lines.isEmpty { textWithoutLines += 1 }
            } else {
                withoutNativeText += 1
            }
            nativeLines += lines.count

            let children = document.children(of: "page:\(page.index)")
            guard children.filter({ $0.value.kind == .line }).count == lines.count else {
                throw FixtureFailure.invalid_line(fixture.relativePath, page.index, "containment")
            }

            let follows = document.graph.edges.filter {
                $0.value == .follows && $0.source.hasPrefix("page:\(page.index)/")
            }
            guard follows.count == max(0, lines.count - 1) else {
                throw FixtureFailure.invalid_line(fixture.relativePath, page.index, "line sequence")
            }

            for line in lines {
                var textReference: PDFTextReference?
                var region: PDFPageRegion?
                for anchor in line.value.anchors {
                    switch anchor {
                    case .text(let reference):
                        textReference = reference
                    case .region(let pageRegion):
                        region = pageRegion
                    }
                }
                guard let textReference, let region,
                      textReference.pageIndex == page.index,
                      region.pageIndex == page.index else {
                    throw FixtureFailure.invalid_line(fixture.relativePath, page.index, "missing source anchors")
                }
                let resolvedText = try document.resolve(textReference)
                guard resolvedText == line.value.text,
                      document.nodes(overlapping: region, kind: .line).contains(where: { $0.id == line.id }) else {
                    throw FixtureFailure.invalid_line(fixture.relativePath, page.index, "source text or geometry")
                }
            }
        }

        return Metrics(
            pages: document.pages.count,
            nativeTextPages: nativeTextPages,
            nativeLines: nativeLines,
            withoutNativeText: withoutNativeText,
            textWithoutLines: textWithoutLines
        )
    }
}
