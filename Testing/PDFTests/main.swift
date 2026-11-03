import Foundation
import IO
import Position
import Primitives
import PDFCore
import PDFApple

private enum TestFailure: Error {
    case unexpected_result
}

@main
struct PDFTests {
    static func main() throws {
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
        guard result.graph.nodes.count == 1 else { throw TestFailure.unexpected_result }

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
            throw TestFailure.unexpected_result
        } catch PDFModelError.stale_text_snapshot(let id) where id == "native" {}

        do {
            _ = try PDFNativeReader().read(Data())
            throw TestFailure.unexpected_result
        } catch PDFReadError.invalid_document {}

        print("t_pdf: passed")
    }
}
