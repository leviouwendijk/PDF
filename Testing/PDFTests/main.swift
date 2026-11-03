import Foundation
import CoreGraphics
import CoreText
import IO
import Position
import Primitives
import PDFCore
import PDFApple
import PDF

private enum TestFailure: Error {
    case unexpected_result(String)
    case fixture_unavailable
}

@main
struct PDFTests {
    static func main() throws {
        try testModelInvariants()
        try testNativePDFNavigation()
        print("t_pdf: passed")
    }

    private static func testModelInvariants() throws {
        let text = try PDFPageTextSnapshot(id: "native", source: .native, text: "123.45")
        let bounds = try PDFRectangle(x: 0, y: 0, width: 200, height: 100)
        let page = try PDFPageRecord(index: 0, bounds: bounds, textSnapshots: [text])
        let reference = try PDFTextReference(
            pageIndex: 0,
            snapshotID: "native",
            snapshotFingerprint: text.fingerprint,
            start: Position.Offset<Position.Unit.UTF16>(0),
            end: Position.Offset<Position.Unit.UTF16>(text.utf16Count)
        )
        let node = PDFStructureGraph.Node(
            id: "page:0/text:0",
            value: try PDFElement(kind: .text, text: text.text, origin: .native, anchors: [.text(reference)])
        )
        let graph = try PDFStructureGraph(nodes: [node], edges: [])
        let source = try PDFSource(fingerprint: .fingerprint(for: Data()), byteCount: 0)
        let result = try PDFDocumentSnapshot(source: source, pages: [page], graph: graph)
        guard result.graph.nodes.count == 1,
              result.page(at: 0)?.index == 0,
              result.page(at: 1) == nil,
              result.node(id: node.id)?.id == node.id,
              try result.resolve(reference) == text.text else {
            throw TestFailure.unexpected_result("model navigation")
        }

        let stale = try PDFTextReference(
            pageIndex: 0,
            snapshotID: "native",
            snapshotFingerprint: .fingerprint(for: "stale"),
            start: Position.Offset<Position.Unit.UTF16>(0),
            end: Position.Offset<Position.Unit.UTF16>(1)
        )
        let staleGraph = try PDFStructureGraph(
            nodes: [.init(id: "stale", value: try PDFElement(
                kind: .text, origin: .native, anchors: [.text(stale)]
            ))],
            edges: []
        )
        do {
            _ = try PDFDocumentSnapshot(source: source, pages: [page], graph: staleGraph)
            throw TestFailure.unexpected_result("stale reference accepted")
        } catch PDFModelError.stale_text_snapshot(let id) where id == "native" {}

        do {
            _ = try result.resolve(stale)
            throw TestFailure.unexpected_result("stale reference resolved")
        } catch PDFModelError.stale_text_snapshot(let id) where id == "native" {}

        do {
            _ = try PDFNativeReader().read(Data())
            throw TestFailure.unexpected_result("invalid PDF accepted")
        } catch PDFReadError.invalid_document {}
    }

    private static func testNativePDFNavigation() throws {
        let data = try makePDFDocument()
        let document = try PDFNativeReader().read(data)
        let facade = try PDFReader.read(data)
        guard facade.source.fingerprint == document.source.fingerprint,
              document.pages.count == 2,
              document.source.byteCount == data.count,
              document.source.fingerprint == .fingerprint(for: data),
              document.page(at: 0)?.textSnapshots.first?.text.contains("Invoice 0007") == true,
              document.page(at: 1)?.textSnapshots.first?.text.contains("Second page") == true else {
            throw TestFailure.unexpected_result("native two-page PDF ingestion")
        }

        let lines = document.nodes(onPage: 0, kind: .line)
        guard lines.count >= 2,
              lines.contains(where: { $0.value.text?.contains("Invoice 0007") == true }),
              lines.contains(where: { $0.value.text?.contains("Total 123.45") == true }) else {
            throw TestFailure.unexpected_result("physical native lines")
        }

        let children = document.children(of: "page:0")
        guard children.filter({ $0.value.kind == .line }).count == lines.count,
              children.contains(where: { $0.value.kind == .text }) else {
            throw TestFailure.unexpected_result("page containment")
        }

        for line in lines {
            var textReference: PDFTextReference?
            var pageRegion: PDFPageRegion?
            for anchor in line.value.anchors {
                switch anchor {
                case .text(let reference):
                    textReference = reference
                case .region(let region):
                    pageRegion = region
                }
            }
            guard let textReference, let pageRegion,
                  try document.resolve(textReference) == line.value.text,
                  pageRegion.pageIndex == 0,
                  document.nodes(overlapping: pageRegion, kind: .line).contains(where: { $0.id == line.id }) else {
                throw TestFailure.unexpected_result("line text and geometry")
            }
        }

        let follows = document.graph.edges.filter { $0.value == .follows && $0.source.hasPrefix("page:0/") }
        guard follows.count == lines.count - 1 else {
            throw TestFailure.unexpected_result("native reading order")
        }
        let outside = try PDFPageRegion(
            pageIndex: 0,
            rectangle: PDFRectangle(x: 1000, y: 1000, width: 20, height: 20)
        )
        guard document.nodes(overlapping: outside, kind: .line).isEmpty,
              document.nodes(onPage: 2).isEmpty else {
            throw TestFailure.unexpected_result("region and page filtering")
        }
    }

    /// Deterministic, real two-page PDF; no external fixture path or OCR dependency.
    private static func makePDFDocument() throws -> Data {
        let output = NSMutableData()
        guard let consumer = CGDataConsumer(data: output as CFMutableData) else {
            throw TestFailure.fixture_unavailable
        }
        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw TestFailure.fixture_unavailable
        }
        let font = CTFontCreateWithName("Helvetica" as CFString, 14, nil)
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(rawValue: kCTFontAttributeName as String): font
        ]

        func draw(_ string: String, atY y: CGFloat) {
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: string, attributes: attributes))
            context.textMatrix = .identity
            context.textPosition = CGPoint(x: 72, y: y)
            CTLineDraw(line, context)
        }

        context.beginPDFPage(nil)
        draw("Invoice 0007", atY: 710)
        draw("Total 123.45", atY: 670)
        context.endPDFPage()
        context.beginPDFPage(nil)
        draw("Second page", atY: 710)
        context.endPDFPage()
        context.closePDF()
        return output as Data
    }
}
